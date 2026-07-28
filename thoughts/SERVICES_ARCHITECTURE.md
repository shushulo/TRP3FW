# Services Architecture Reference

Complete reference for the service container pattern, service lifecycle, and service implementations.

## Overview

TRP3FW uses a **Service Container pattern** to manage stateful systems. Services are singleton objects that handle specific domains (caching, history, notifications, security).

**Benefits:**
- Centralized lifecycle management
- Dependency injection
- Clean separation of concerns
- Testable components
- Lazy initialization

## Service Container

### Location
`core/ServiceContainer.lua`

### Structure
```lua
TRP3FW.ServiceContainer = {
    services = {}  -- [serviceName] = serviceInstance
}
```

### API

#### Register(service)
Register a service with the container.

```lua
TRP3FW.ServiceContainer:Register(service)
```

**Parameters:**
- `service` - Service instance with `GetName()` method

**Example:**
```lua
local MyService = TRP3FW.Service:New("MyService")
TRP3FW.ServiceContainer:Register(MyService)
```

#### Get(name)
Retrieve a service by name.

```lua
local service = TRP3FW.ServiceContainer:Get("CacheService")
```

**Returns:** Service instance or `nil`

#### InitializeAll()
Initialize all registered services.

```lua
TRP3FW.ServiceContainer:InitializeAll()
```

Called on `PLAYER_LOGIN` event. Calls `Initialize()` on each service that hasn't been initialized yet.

**Initialization Order (CRITICAL):**
EventService **must** initialize first to ensure event handlers are registered before other services try to register callbacks.

```lua
function TRP3FW.ServiceContainer:InitializeAll()
    -- Initialize EventService FIRST
    local eventService = self.services["EventService"]
    if eventService and eventService.Initialize and not eventService.initialized then
        eventService:Initialize()
    end

    -- Initialize all other services
    for name, service in pairs(self.services) do
        if name ~= "EventService" and service.Initialize and not service.initialized then
            service:Initialize()
        end
    end
end
```

**Why this matters:**
- WhoService registers callbacks with EventService during initialization
- If WhoService initializes first (due to `pairs()` undefined order), callbacks fail to register
- Result: WHO_LIST_UPDATE and CHAT_MSG_SYSTEM events never reach WhoService
- WHO queries execute but results are never processed

---

## Service Base Class

### Location
`core/Service.lua`

### Structure
```lua
TRP3FW.Service = {
    initialized = false,
    name = string
}
```

### Singleton-by-design

`TRP3FW.Service:New(name)` is a *singleton* factory, not a class instantiator.
The returned table has the base class itself as its metatable, so calling `:New`
twice with the same logical service name would share one method namespace —
adding methods to the second instance would bleed into the first. Existing
services (`HistoryService`, `NotificationService`, `CacheService`,
`SecurityService`, `EventService`, `WhoService`) all use this pattern correctly
because each is created exactly once at file load.

If a future service needs to be instantiated multiple times, follow the
`SPVPStage`-style pattern instead:

```lua
TRP3FW.Foo = setmetatable({}, { __index = TRP3FW.Service })
function TRP3FW.Foo:New(name)
    local instance = TRP3FW.Service:New(name or "Foo")
    setmetatable(instance, { __index = self })
    return instance
end
```

### Creating a Service

```lua
local addonName, TRP3FW = ...

-- Create service class inheriting from base
local MyService = setmetatable({}, { __index = TRP3FW.Service })

function MyService:New(name)
    local instance = TRP3FW.Service:New(name or "MyService")
    setmetatable(instance, { __index = self })
    return instance
end

function MyService:Initialize()
    -- Call parent initialize
    TRP3FW.Service.Initialize(self)

    -- Service initialization code
    self.data = {}
    self:RegisterEvents()

    TRP3FW:Debug("MyService initialized", "core")
end

function MyService:RegisterEvents()
    -- Event registration
end

-- Create singleton instance
local instance = MyService:New()

-- Register with container
TRP3FW.ServiceContainer:Register(instance)
```

### Base Methods

#### GetName()
```lua
function Service:GetName()
    return self.name
end
```

#### Initialize()
```lua
function Service:Initialize()
    if self.initialized then
        return
    end
    self.initialized = true
end
```

---

## Core Services

### 1. CacheService

**Purpose:** Manage all caches, cleanup, and cache-related events

**Location:** `features/services/CacheService.lua`

**Responsibilities:**
- Register caches with CacheInterface
- Periodic cache cleanup (60s interval)
- Event-based cache clearing (zone/phase changes)
- Interaction tracking (mouseover/target events)
- Zone cache clearing management

**Initialization:**
```lua
function CacheService:Initialize()
    TRP3FW.Service.Initialize(self)

    self:InitializeCaches()
    self:InitializeCacheCleanup()
    self:InitializeZoneCacheClearing()
    self:InitializeInteractionTracking()
end
```

**Public Methods:**

#### InitializeCaches()
Registers all caches with CacheInterface:
```lua
function CacheService:InitializeCaches()
    local CI = TRP3FW.CacheInterface

    CI:Register("allowedSenders", {
        ttl = TRP3FW.Prefs.sendCacheDuration,
        maxSize = 1000
    })

    CI:Register("interaction", {
        ttl = TRP3FW.Prefs.interactionCacheDuration,
        maxSize = TRP3FW.Prefs.cacheSizeLimit
    })

    -- ... register all other caches
end
```

#### InitializeCacheCleanup()
Starts periodic cleanup timer:
```lua
function CacheService:InitializeCacheCleanup()
    self.cleanupTimer = C_Timer.NewTicker(CACHE_CLEANUP_INTERVAL, function()
        self:PerformCleanup()
    end)
end
```

#### PerformCleanup()
Incrementally prunes expired entries:
```lua
function CacheService:PerformCleanup()
    local budget = CACHE_PRUNE_BUDGET  -- 200 entries max per cycle

    for cacheName, config in pairs(registeredCaches) do
        if budget <= 0 then break end

        local cache = GetCacheTable(cacheName)
        local ttl = config.ttl

        for key, entry in pairs(cache) do
            if budget <= 0 then break end

            if ttl and (now - entry.timestamp) > ttl then
                cache[key] = nil
                budget = budget - 1
            end
        end
    end
end
```

#### InitializeZoneCacheClearing()
Hooks zone/phase change events:
```lua
function CacheService:InitializeZoneCacheClearing()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("SCENARIO_UPDATE")

    frame:SetScript("OnEvent", function(self, event)
        if event == "ZONE_CHANGED_NEW_AREA" then
            CacheService:OnZoneChange()
        elseif event == "SCENARIO_UPDATE" then
            CacheService:OnPhaseChange()
        end
    end)
end
```

#### OnZoneChange()
Clears caches based on settings:
```lua
function CacheService:OnZoneChange()
    -- Update zone name cache
    TRP3FW.currentZoneName = GetZoneText()
    TRP3FW.lastZoneChangeTime = TRP3FW:GetCurrentTime()

    if not TRP3FW.Prefs.clearCacheOnZoneChange then
        return
    end

    if TRP3FW.Prefs.clearPhaseCheckOnZoneChange then
        ClearCache("phaseCheck")
    end

    if TRP3FW.Prefs.clearInteractionOnZoneChange then
        ClearCache("interaction")
    end

    -- ... clear other caches
end
```

#### InitializeInteractionTracking()
Hooks mouseover and target events:
```lua
function CacheService:InitializeInteractionTracking()
    -- Mouseover tracking (throttled to 10/sec)
    local lastMouseover = 0
    GameTooltip:HookScript("OnTooltipSetUnit", function()
        local now = TRP3FW:GetCurrentTime()
        if (now - lastMouseover) < 0.1 then return end  -- 100ms throttle
        lastMouseover = now

        local unit = select(2, GameTooltip:GetUnit())
        if unit and UnitIsPlayer(unit) then
            local name = UnitName(unit)
            TrackInteraction(name, "mouseover")
        end
    end)

    -- Target tracking
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:SetScript("OnEvent", function()
        if UnitExists("target") and UnitIsPlayer("target") then
            local name = UnitName("target")
            TrackInteraction(name, "target")
        end
    end)
end
```

---

### 2. HistoryService

**Purpose:** Track session statistics and send history

**Location:** `features/services/HistoryService.lua`

**Responsibilities:**
- Session statistics (allows, blocks, ghosts, alerts)
- Per-addon request tracking
- Cache statistics (hits/misses)
- WHO query statistics
- Send history (last 50-100 sends)

**Data Structures:**
```lua
TRP3FW.sessionStats = {
    totalRequests = 0,
    allowed = 0,
    blocked = 0,
    ghosted = 0,
    alerts = {
        phase = 0,
        map = 0,
        start_phase = 0
    },
    requestsByAddon = {
        TRP3 = 0,
        MRP = 0,
        XRP = 0,
        MSP = 0
    },
    cacheStats = {
        phaseCheckCacheHits = 0,
        phaseCheckCacheMisses = 0,
        mapScanCacheHits = 0,
        mapScanCacheMisses = 0,
        whoCacheHits = 0,
        whoCacheMisses = 0,
        interactionCacheHits = 0,
        interactionCacheMisses = 0,
        allowedSendersCacheHits = 0,
        allowedSendersCacheMisses = 0
    },
    whoStats = {
        zoneQueries = 0,
        nameQueries = 0,
        prepopulations = 0,
        rateLimitHits = 0,
        timeouts = 0,
        truncations = 0,
        backoffs = 0
    }
}
```

**Public Methods:**

#### RecordHistory(playerName, addon, wasAlert, wasBlocked, wasGhost, alertType)
Records a transaction in the notification history.
```lua
function HistoryService:RecordHistory(playerName, addon, wasAlert, wasBlocked, wasGhost, alertType)
    -- ... sanitizes player name and inserts into self.notificationHistory ...
end
```

#### IncrementStat(category, subcategory, amount)
Increments a session statistic counter.
```lua
function HistoryService:IncrementStat(category, subcategory, amount)
    -- ... increments self.sessionStats[category][subcategory] ...
end
```

#### RecordPerformance(duration, context)
Tracks execution time and throughput metrics.
```lua
function HistoryService:RecordPerformance(duration, context)
    -- ... updates windowed and interval performance stats ...
end
```

#### GetStats()
```lua
function HistoryService:GetStats()
    return self.sessionStats
end
```

#### Send-history API (post-Phase-3 hardening)

Stages and services should use these helpers instead of poking
`historyService.profileSendHistory` directly. The aliased table
(`TRP3FW.profileSendHistory`) and the service's internal table can fall out of
sync if either side ever reassigns rather than mutates — these helpers route
through the canonical service-owned table.

```lua
-- Read the send-history entry (timestamp, suppressedCount) for a player.
function HistoryService:GetSendHistory(playerName)

-- Returns (isFirstTime, suppressedCount) relative to the suppression window.
function HistoryService:IsFirstSend(playerName, now, suppressionTime)

-- Stamp `playerName` as having just sent now (resets suppressedCount).
-- Use when a notification is shown/refreshed.
function HistoryService:RecordSend(playerName, now)
```

Used by: `BurstStage`, `LocationStage`, `AlertFastPathStage`, `NotificationService`.

#### Stat increment discipline

All `sessionStats.<key>` mutations should go through `IncrementStat`. Direct
writes (e.g. `self.sessionStats.ghostSends = self.sessionStats.ghostSends + 1`)
bypass any future bookkeeping the service may add.

---

### 3. NotificationService

**Purpose:** Dispatch notifications and manage suppression

**Location:** `features/services/NotificationService.lua`

**Responsibilities:**
- Notification dispatch (chat, on-screen, sound)
- Per-player suppression tracking
- Suppression window management (sliding/fixed)
- Notification formatting (supports Allow, Alert, Block, and Ghost modes)

**Data Structures:**
```lua
NotificationService.suppressionHistory = {
    [playerName] = {
        lastNotification = timestamp,
        suppressedCount = number,
        lastType = string
    }
}
```

**Public Methods:**

#### Notify(playerName, context)
```lua
function NotificationService:Notify(playerName, context)
    -- context: {type, addon, reason, isWhisper, settings, locationResult, cacheInfo, checkDetails}

    -- 1. Check settings toggles
    -- 2. Check suppression
    -- 3. Update History Timestamp
    -- 4. Display (ShowChatNotification / ShowOnScreenNotification)
end
```

#### ShouldSuppress(playerName, notifType, settings)
Handles severity-based suppression. If severity increases (e.g., allow -> alert), suppression is bypassed.
```lua
function NotificationService:ShouldSuppress(playerName, notifType, settings)
    -- ... logic to determine if notification should be shown ...
end
```

#### ShowChatNotification(...)
The primary display engine for chat-based notifications. Handles complex formatting for location failures, ghost profiles, and cache hits.


---

### 4. SecurityService

**Purpose:** Input sanitization and debug message redaction

**Location:** `features/services/SecurityService.lua`

**Responsibilities:**
- Player name sanitization (regex validation)
- Command injection prevention (Epsilon API)
- Debug message redaction (GUIDs, IPs, emails)
- Rate limiting enforcement

**Public Methods:**

#### SanitizePlayerName(name)
```lua
function SecurityService:SanitizePlayerName(name)
    if not name or type(name) ~= "string" then
        return nil
    end

    -- Check validated names cache
    if TRP3FW_ValidatedNames[name] then
        local age = now - TRP3FW_ValidatedNames[name]
        if age < TRP3FW.Prefs.validatedNamesCacheDuration then
            return name
        end
    end

    -- Validate length
    if #name < 2 or #name > 12 then
        return nil
    end

    -- Validate characters (letters, hyphens, apostrophes only)
    if not name:match("^[A-Za-z%-']+$") then
        return nil
    end

    -- Add to validated names
    TRP3FW_ValidatedNames[name] = now
    return name
end
```

#### RedactDebugMessage(message)
```lua
function SecurityService:RedactDebugMessage(message)
    if not TRP3FW.Prefs.redactEnabled then
        return message
    end

    -- Redact GUIDs
    if TRP3FW.Prefs.redactNetwork then
        message = message:gsub("Player%-[0-9A-F]+%-[0-9A-F]+", "Player-REDACTED-GUID")
    end

    -- Redact IPs
    if TRP3FW.Prefs.redactNetwork then
        message = message:gsub("%d+%.%d+%.%d+%.%d+", "XXX.XXX.XXX.XXX")
    end

    -- Redact emails
    if TRP3FW.Prefs.redactNetwork then
        message = message:gsub("[%w%.%-_]+@[%w%.%-_]+%.[%a]+", "redacted@email.com")
    end

    return message
end
```

---

## Service Initialization Flow

```
PLAYER_LOGIN event
    ↓
TRP3FW.ServiceContainer:InitializeAll()
    ↓
For each registered service:
    ↓
    service:Initialize()
        ↓
        CacheService:
            - RegisterCaches()
            - StartCleanupTimer()
            - HookZoneEvents()
            - HookInteractionEvents()
        ↓
        HistoryService:
            - InitializeStats()
            - InitializeHistory()
        ↓
        NotificationService:
            - InitializeSuppressionTracking()
        ↓
        SecurityService:
            - InitializeValidatedNames()
```

---

## Adding a New Service

1. **Create service file** in `features/services/`:

```lua
local addonName, TRP3FW = ...

local MyService = setmetatable({}, { __index = TRP3FW.Service })

function MyService:New()
    local instance = TRP3FW.Service:New("MyService")
    setmetatable(instance, { __index = self })
    return instance
end

function MyService:Initialize()
    TRP3FW.Service.Initialize(self)

    -- Service initialization
    self.data = {}

    TRP3FW:Debug("MyService initialized", "core")
end

-- Create and register
local instance = MyService:New()
TRP3FW.ServiceContainer:Register(instance)
```

2. **Add to TOC** in Services section

3. **Service auto-initializes** on `PLAYER_LOGIN`

4. **Access service** via container:
```lua
local myService = TRP3FW.ServiceContainer:Get("MyService")
```
