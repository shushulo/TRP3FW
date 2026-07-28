# Data Structures Reference

Complete reference of all global variables, arrays, caches, and state containers in TRP3FW.

## Core Namespace

### TRP3FW (Main Table)
The primary namespace that contains all addon functionality.

```lua
TRP3FW.VERSION           -- string: Current version (e.g., "3.0")
TRP3FW.ADDON_NAME        -- string: Addon name from TOC
TRP3FW.hasEpsilonAPI     -- boolean: C_Epsilon API available
TRP3FW.hasTRP3ExchangeHooks -- boolean: TRP3 hooks installed successfully
TRP3FW.Prefs             -- table: Runtime proxy for the ACTIVE profile settings
TRP3FW.GlobalDB          -- table: Reference to the root TRP3FW_DB
TRP3FW.TabManager        -- table: UI module manager (see below)
```

## Settings & Storage

### TRP3FW_DB (Saved Variable)
The root database for all settings, supporting multiple profiles.

```lua
TRP3FW_DB = {
    global = {
        version = "3.0",
        -- System-wide settings (if any)
    },
    profileKeys = {
        ["CharacterName - RealmName"] = "Default",
        ["AltName - RealmName"] = "Strict Mode",
    },
    profiles = {
        ["Default"] = {
            -- ... all settings for Default profile ...
        },
        ["Strict Mode"] = {
            -- ... all settings for Strict Mode profile ...
        }
    }
}
```

### TRP3FW.Prefs (Runtime Settings)
This is a reference to `TRP3FW_DB.profiles[ActiveProfile]`. It contains the actual setting values used by the code.

Key structure (inside a profile):
```lua
{
    -- Notifications
    notifyEnabled = boolean,
    showInChat = boolean,
    showOnScreen = boolean,
    playSound        = boolean,
    suppressionTime = number,
    refreshSuppression = boolean,

    -- Location checking modes
    phaseCheckMode = string, -- "off", "alert", "block", "ghost", "alert_block", "alert_ghost"
    mapCheckMode = string,

    -- SPVP (Secure Phase Verification Protocol) v2.5
    spvpEnabled = boolean,            -- Master toggle
    spvpMode = string,                -- "off" | "optional" | "preferred" | "required"
    spvpAutoInitialize = boolean,     -- Defaults to false
    spvpBlockDuration = number,       -- seconds
    spvpSaltCacheDuration = number,   -- default: 10800 (3h)
    spvpPerPhaseOverrides = table,    -- [phaseID] = boolean

    -- Ghost mode & Overrides
    ghostOnStartPhase = boolean,
    ghostProfileSwitch = boolean,
    ghostProfileID = string,
    ghostProfileName = string,
    ghostProfileOverrides = {
        { match = "169", profileID = "..." },
        { match = "169,1605", profileID = "..." }
    },

    -- Cache Clearing
    clearSpvpOnPhaseChange = boolean, -- default: true
    clearSpvpOnZoneChange = boolean,  -- default: false
    -- ... other cache clear toggles

    -- Debug
    debug = boolean,
    debugSPVP = boolean,
    -- ... other category toggles
}
```

## UI Architecture (Modular System)

### TabManager
The central coordinator for the lazy-loaded, modular settings UI.

```lua
TRP3FW.TabManager = {
    tabs = { [id] = tabObject },        -- Registry of tab definitions
    orderedTabs = { tabObject, ... },   -- List for display order
    activeTab = tabObject,              -- Currently displayed tab
    
    -- Shared context linked via LinkUI()
    uiElements = table,                 -- Global registry of UI widgets by key
    complexityWidgets = table           -- List of widgets filtered by complexity level
}
```

### Tab Object Structure
```lua
{
    id = "alerts",
    name = "Alerts",
    title = "Alerts & Blocking",
    create = function(container),       -- Returns the scrollFrame
    refresh = function(),               -- Called on tab switch/update
    frame = frameObject                 -- Created lazily on first access
}
```

### uiElements
A shared table (passed by reference from `ui/settings.lua`) containing all created UI widgets. This allows `RefreshUI` to update widgets created by modular tabs without direct coupling.

## Cache Systems

### CacheInterface (LRU Cache System)
All caches use the unified `TRP3FW.CacheInterface` with O(1) LRU eviction.

**Registered Caches:**
1. **allowedSenders** - Players who passed location checks
2. **interaction** - Mouseover/target tracking
3. **phaseCheck** - Phase verification results
4. **whoName** - WHO query by player name
5. **whoZone** - WHO query by zone
6. **mapScan** - Map scanning results
7. **broadcast** - Map broadcast results
8. **spvpVerified** - Successful SPVP verification results
9. **spvpPhaseSalt** - Cached phase salts (TRP3FW_SPVP_KEY)
10. **spvpSessions** - Active session IDs (replay protection)
11. **cleanName** - CleanPlayerName() results
12. **sanitizedName** - SanitizePlayerName() results

## SPVP State

### Handshake & Fetch State
```lua
TRP3FW.spvpSessions = {
    [sessionID] = {
        playerName = string,
        sendId = number,
        privateKey = number,
        publicKey = number,
        generator = number,
        timestamp = number,
        attempt = number,
        callback = function
    }
}

TRP3FW.spvpIncomingSessions = {
    [sessionID] = {
        sharedKey = number,
        sender = string,
        timestamp = number
    }
}

TRP3FW.spvpFailedAttempts = {
    [playerName] = {
        count = number,
        firstFailTime = number,
        blockedUntil = number
    }
}

TRP3FW.pendingSaltTickets = {
    [ticket] = phaseID  -- Async salt fetch tracking (Epsilon API)
}

TRP3FW.pendingSPVPInits = {
    {sender = string, message = string} -- Queued INITs waiting for async salt
}
```

## History & Statistics

### Session Statistics (Managed by HistoryService)
```lua
TRP3FW.sessionStats = {
    alerts = number,
    blocks = number,
    ghostSends = number,
    phaseAlerts = number,
    mapAlerts = number,
    startPhaseBlocks = number,
    requestsByAddon = {
        TRP3 = number,
        MRP = number,
        XRP = number,
        MSP = number
    },
    cacheStats = {
        -- ... hits/misses for all caches ...
        spvpVerifiedCacheHits = number,
        spvpVerifiedCacheMisses = number
    },
    performance = {
        totalTime = number,
        totalRequests = number,
        peakTime = number,
        -- ... interval and window stats ...
    }
}
```

### Notification History Entry
```lua
{
    player = string,     -- Sanitized player name
    addon = string,      -- Source addon
    timestamp = number,  -- GetTime() result
    wasAlert = boolean,
    wasBlocked = boolean,
    wasGhost = boolean,
    alertType = string   -- "phase_mismatch", "map_mismatch", etc.
}
```

## Hook State

### Hook State Container
```lua
TRP3FW.hookState = {
    chomp = {
        replayingPhaseInSend = boolean,
        sendingGhostProfile = boolean
    },
    exchange = {},
    originals = {}
}
```

---
**Last Updated:** 2026-02-22
**Version:** 3.0-beta
