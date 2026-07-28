# Hook System Architecture

**Last Updated**: 2026-01-11
**Version**: 2.9.2-hotfix (v2.0-beta)

---

## Table of Contents

1. [Overview](#overview)
2. [Hook Installer](#hook-installer)
3. [Hook Types](#hook-types)
4. [Conflict Detection](#conflict-detection)
5. [Hook State Management](#hook-state-management)
6. [TRP3 Hooks](#trp3-hooks)
7. [MSP Hooks](#msp-hooks)
8. [Chomp Pipeline Hook](#chomp-pipeline-hook)
9. [Scan Reply Hooks](#scan-reply-hooks)
10. [Safety Mechanisms](#safety-mechanisms)
11. [Hook Chaining](#hook-chaining)
12. [Common Patterns](#common-patterns)
13. [Troubleshooting](#troubleshooting)

---

## Overview

TRP3FW intercepts RP addon communication to enforce location-based access control. The hook system wraps external addon functions to:

- **Track profile requests** (user-initiated vs automatic)
- **Gate profile sends** (block, allow, or ghost based on location)
- **Enable ghost mode** (send blank/alternate profiles)
- **Notify users** (profile send alerts)
- **Prevent start phase leaks** (Phase 169 protection on Epsilon)

### Hook Architecture

```
Addon Function Call
    ↓
TRP3FW Hook Wrapper
    ↓
[Conflict Detection]
    ↓
[Pipeline Processing]
    ↓
[Decision Engine]
    ↓
Original Function (or blocked)
```

### Supported Addons

- **TotalRP3** - Primary target (sendQuery, sendObject, Chomp, scan replies)
- **MyRolePlay** - Via LibMSP hooks
- **XRP** - Via LibMSP hooks
- **LibMSP** - MSP protocol layer (Request, callback system)
- **Chomp** - Message chunking library (used by TRP3 and LibMSP)

---

## Hook Installer

**File**: `hooks/installer.lua`

### Initialization Flow

```lua
TRP3FW:InstallHooks()
    ├─ Detect available addons (TRP3, MRP, XRP, MSP, MapScanner)
    ├─ Check compatibility (abort if multiple RP addons)
    ├─ Install individual hooks:
    │   ├─ SendQueryHook (TRP3 user requests)
    │   ├─ MSPRequestHook (MSP user requests)
    │   ├─ ChompHook (profile send gating)
    │   ├─ SendObjectHook (pre-serialization ghost mode)
    │   ├─ MSPExchangeHooks (ghost mode helpers)
    │   ├─ MSPHooks (LibMSP callbacks, NA guards)
    │   ├─ GradientHooks (UI text effects)
    │   ├─ FontSizeHooks (UI font scaling)
    │   └─ TRP3ScanNotification (map scan replies)
    └─ Set hookInstalled flag
```

### Addon Detection

```lua
-- Global API checks
if TRP3_API then self.detectedAddons.TRP3 = true end
if mrp then self.detectedAddons.MRP = true end
if xrp then self.detectedAddons.XRP = true end

-- LibMSP via LibStub fallback
if not msp and LibStub then
    local success, lib = pcall(LibStub, "LibMSP")
    if success and lib then msp = lib end
end
if msp then self.detectedAddons.MSP = true end

-- Map scanner detection
if TRP3_API and TRP3_API.MapScannersManager then
    self.detectedAddons.MapScanner = "TRP3"
elseif RPMapScan then
    self.detectedAddons.MapScanner = "RPMapScan"
end
```

### Compatibility Checks

**Multiple RP Addon Protection**:
```lua
local rpCount = (TRP3 and 1 or 0) + (MRP and 1 or 0) + (XRP and 1 or 0)
if rpCount > 1 and TRP3FW.Prefs.abortOnMultipleRPAddons then
    self.disabledReason = "multiple_rp_addons"
    -- Disable all monitoring
    return
end
```

**Map Scanner Conflicts**:
```lua
-- TRP3 + RPMapScan = incompatible
if detectedAddons.TRP3 and detectedAddons.MapScanner == "RPMapScan" then
    self.mapScanDisabledReason = "trp3_with_rpmapscan"
end
```

---

## Hook Types

### 1. Request Tracking Hooks

**Purpose**: Detect user-initiated profile queries

**TRP3 sendQuery Hook** (`hooks/trp3.lua`):
```lua
TRP3_API.r.sendQuery = function(unitID)
    local cleanName = TRP3FW:CleanPlayerName(unitID)

    -- STRICT CHECK: Only count if actually targeting/mousing
    local isTarget = UnitName("target") == cleanName and not TRP3FW.phaseCheckTargeting
    local isMouseover = UnitName("mouseover") == cleanName

    if isTarget or isMouseover then
        TRP3FW.userInitiatedQueries[cleanName] = GetTime()
    end

    return originalSendQuery(unitID)
end
```

**MSP Request Hook** (`hooks/msp.lua`):
```lua
msp.Request = function(self, name, fields)
    local cleanName = TRP3FW:CleanPlayerName(name)

    -- Same strict targeting check
    if isTarget or isMouseover then
        TRP3FW.userInitiatedQueries[cleanName] = GetTime()
    end

    -- Pre-seed NA field (prevents nil crashes)
    EnsureMSPNA(cleanName)

    return originalMSPRequest(self, name, fields)
end
```

**Why Strict Targeting?**
Automated background scans (map scanners) call Request() without user interaction. Strict targeting ensures only genuine user-initiated queries suppress notifications.

### 2. Send Gating Hooks

**Purpose**: Intercept outgoing profile sends for location checking

**Chomp Hook** (`hooks/trp3_chomp_pipeline.lua`):
Central hook for ALL profile sends (TRP3 and MSP use Chomp for transmission).

```lua
AddOn_Chomp.SmartAddonMessage = function(prefix, text, chatType, target, priority, queue, callback, callbackArg)
    -- 6-stage pipeline
    return TRP3FW:ChompHookPipeline(prefix, text, chatType, target, priority, queue, callback, callbackArg, originalSend)
end
```

**Pipeline Stages** (see [Chomp Pipeline Hook](#chomp-pipeline-hook) section):
1. Guard checks (recursion, replay)
2. Phase-in delay (queue during zone transitions)
3. Mutual exchange detection
4. Start phase blocking/ghosting (Phase 169)
5. Burst detection (deduplicate concurrent requests)
6. Location gating (decision engine)

### 3. Ghost Mode Hooks

**Purpose**: Replace profile data with blank/alternate profiles

**SendObject Hook** (`hooks/trp3.lua`):
Pre-serialization hook for TRP3 profile sends. Allows inspection of `informationType` to generate appropriate ghost data.

```lua
AddOn_TotalRP3.Communications.sendObject = function(prefix, object, ...)
    if prefix == "SI" and ShouldGhost(target) then
        local informationType = object[1]
        local ghostData = TRP3FW:GetGhostDataForInformationType(informationType, profileID)
        object = {informationType, ghostData}  -- Replace data
    end

    return originalSendObject(prefix, object, ...)
end
```

**MSP Exchange Hooks** (`hooks/msp_exchange.lua`):
Generates MSP ghost payloads for Chomp hook to substitute.

```lua
-- Generate blank MSP fields
function TRP3FW:GetBlankMSPFields()
    return {
        VP = "3",  -- Protocol version
        VA = "TRP3FW/"..VERSION,
        NA = UnitName("player"),
        GU = UnitGUID("player"),
        GC = select(2, UnitClass("player")),
        -- All RP fields omitted
    }
end

-- Convert TRP3 → MSP format (for alternate profiles)
function TRP3FW:GetProfileTRP3ToMSP(profileID)
    -- Cache-backed conversion (expensive operation)
    -- Converts characteristics, about, misc to MSP fields
end
```

### 4. MSP Callback Hooks

**Purpose**: Detect incoming MSP profile requests, trigger ghost mode for Phase 169

**LibMSP Callback Hook** (`hooks/msp.lua`):
```lua
-- Fires when LibMSP receives a REQUEST for OUR profile
table.insert(msp.callback.received, 1, function(senderName)
    -- Phase 169 check
    local shouldBlock, action = TRP3FW:ShouldBlockForStartPhase(senderName, true)

    if shouldBlock and action == "ghost" then
        TRP3FW:EnableGhostForNextSend(cleanName, alternateProfileID)
    elseif shouldBlock and action == "block" then
        TRP3FW.startPhaseBlockList[cleanName] = {timestamp = now, expires = now + 5}
    end

    -- Mark as pending auto-reply (for Chomp hook)
    TRP3FW.pendingMSPAutoReplies[cleanName] = {timestamp = now, expires = now + 5}
end)
```

**MSP Name Guard** (Crash Prevention):
```lua
-- Ensure msp.char[name].field.NA is never nil (prevents MRP crashes)
ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", function(_, event, message, author, ...)
    EnsureMSPNA(author)  -- Fills missing NA fields
    return false
end)
```

### 5. Scan Reply Hooks

**Purpose**: Gate map scan responses (only send if requester is nearby)

See [Scan Reply Hooks](#scan-reply-hooks) section below.

---

## Conflict Detection

**Purpose**: Detect and handle hook conflicts with other addons

### Conflict Detection Function

```lua
function TRP3FW:CheckHookConflict(hookName, current, cachedOriginal, ourWrapper)
    if type(current) ~= "function" then
        return {ok = false, action = "refuse", reason = "target_not_callable"}
    end

    -- Another addon modified the function
    if cachedOriginal and current ~= cachedOriginal and current ~= ourWrapper then
        return {
            ok = not TRP3FW.Prefs.strictHookMode,
            action = TRP3FW.Prefs.strictHookMode and "refuse" or "chain",
            reason = "conflict_existing_hook"
        }
    end

    -- Already wrapped by us
    if ourWrapper and current == ourWrapper then
        return {ok = false, action = "skip", reason = "already_wrapped"}
    end

    return {ok = true, action = "chain"}
end
```

### Conflict Actions

| Action | Behavior | Use Case |
|--------|----------|----------|
| `chain` | Install hook anyway | Non-strict mode, hook chaining |
| `refuse` | Skip installation | Strict mode, incompatible hook |
| `skip` | Already installed | Prevent double-wrapping |

### Strict Hook Mode

**Setting**: `TRP3FW.Prefs.strictHookMode`
**Default**: `false`

When enabled:
- Refuses to install hooks if another addon modified the function
- Prevents potential conflicts but may break compatibility
- Logs conflicts to `TRP3FW.hookConflicts` table

**Example Conflict Log**:
```lua
TRP3FW.hookConflicts["chomp"] = {
    reason = "conflict_existing_hook",
    source = "@SomeOtherAddon/hook.lua:42",
    action = "refuse"
}
```

---

## Hook State Management

**Table**: `TRP3FW.hookState`

### Structure

```lua
TRP3FW.hookState = {
    originals = {
        -- Cached original functions
        sendQuery = <function>,
        chompSend = <function>,
        mspRequest = <function>,
        sendObject = <function>,
    },
    chomp = {
        -- Chomp hook guards
        sendingGhostProfile = false,  -- Recursion guard
        replayingPhaseInSend = false, -- Replay guard
    },
    exchange = {
        -- MSP exchange state
        mspMyMeta = <metatable>,
        originalMSPMy = <table>,
    }
}
```

### Recursion Guards

**Problem**: Ghost mode hooks modify profile data, which triggers profile send hooks again (infinite loop).

**Solution**: Recursion flags

```lua
-- Before sending ghost profile
self.hookState.chomp.sendingGhostProfile = true

-- Send ghost profile (bypasses hook)
AddOn_Chomp.SmartAddonMessage(...)

-- Clear flag
self.hookState.chomp.sendingGhostProfile = false
```

### Replay Guards

**Problem**: Phase-in delay queues sends, then replays them. Replayed sends shouldn't be re-queued.

**Solution**: Replay flag

```lua
-- Before replaying queued send
self.hookState.chomp.replayingPhaseInSend = true

-- Replay send (bypasses phase-in queue)
AddOn_Chomp.SmartAddonMessage(queuedSend.prefix, ...)

-- Clear flag
self.hookState.chomp.replayingPhaseInSend = false
```

---

## TRP3 Hooks

### 1. SendQuery Hook

**File**: `hooks/trp3.lua`
**Function**: `TRP3_API.r.sendQuery(unitID)`

**Purpose**: Track user-initiated TRP3 profile queries

**Logic**:
```lua
1. Clean player name
2. Check if targeting/mousing over player
   - Ignore if TRP3FW.phaseCheckTargeting (our own targeting)
3. If user-initiated:
   - Record in userInitiatedQueries table
   - Used for mutual exchange detection
4. Call original sendQuery
```

**Data Tracked**:
```lua
TRP3FW.userInitiatedQueries[playerName] = timestamp
-- TTL: 5 seconds (exchanges complete in 1-2s)
```

### 2. SendObject Hook

**File**: `hooks/trp3.lua`
**Function**: `AddOn_TotalRP3.Communications.sendObject(prefix, object, ...)`

**Purpose**: Pre-serialization ghost mode for TRP3 profiles

**Prefixes Handled**:
- `VQ` - Version query (request, not profile data) → Mark as request
- `VR` - Version response (contains profile version numbers)
- `GI` - Get info (request, not profile data) → Mark as request
- `SI` - Send info (ACTUAL PROFILE DATA) → Apply ghost mode

**Ghost Mode Logic**:
```lua
if prefix == "SI" and object and object[1] then
    local informationType = object[1]  -- characteristics/about/misc/character

    if ShouldGhostSendTo(target) then
        local ghostProfileID = GetGhostProfileID(target) or Settings.ghostProfileID
        local ghostData = GetGhostDataForInformationType(informationType, ghostProfileID)

        -- Validate and sanitize payload
        local valid, sanitized = ValidateGhostTRP3Payload(informationType, ghostData)

        if valid then
            object = {informationType, sanitized}  -- Replace data
        else
            return  -- Block send (malformed ghost data)
        end
    end
end
```

**Why Pre-Serialization?**
Chomp serializes payloads before transmission. By hooking `sendObject` (before serialization), we have access to structured data (informationType, profile sections) instead of opaque serialized strings.

### 3. Scan Notification Hook

**File**: `hooks/trp3.lua`
**Function**: `AddOn_TotalRP3.Communications.broadcast.sendP2PMessage(target, command, ...)`

**Purpose**: Gate map scan responses (C_SCAN replies)

See [Scan Reply Hooks](#scan-reply-hooks) section.

---

## MSP Hooks

### 1. MSP Request Hook

**File**: `hooks/msp.lua`
**Function**: `msp.Request(self, name, fields)`

**Purpose**: Track user-initiated MSP queries (MRP, XRP)

**Logic**: Same as TRP3 sendQuery hook (strict targeting check)

**Additional Feature**: NA Pre-Seeding
```lua
EnsureMSPNA(cleanName)  -- Prevents nil NA crashes before reply arrives
```

### 2. LibMSP Callback Hook

**File**: `hooks/msp.lua`
**Callback**: `msp.callback.received`

**Purpose**: Detect incoming MSP profile requests

**Hook Installation**:
```lua
-- Insert our callback FIRST (priority)
table.insert(msp.callback.received, 1, function(senderName)
    -- Our logic runs before other callbacks
end)
```

**Responsibilities**:
1. **Phase 169 Protection**
   - Check if in start phase (169)
   - Enable ghost mode or block list
2. **Auto-Reply Tracking**
   - Mark sender in `pendingMSPAutoReplies` (5s TTL)
   - Chomp hook uses this to distinguish request from reply
3. **Addon Detection**
   - Check `msp.char[sender].client` and `.field.VA`
   - Detect if sender uses MRP, XRP, or TRP3
4. **SendId Coordination**
   - Create sendId for this exchange
   - Store in `mspCallbackSendIds` (reused by Chomp hook)
   - Prevents double-counting when MSP sends multiple messages

**Why Multiple Messages?**
MSP sends TWO messages per exchange:
- **Safe fields** (NA, NH, NI, NT, etc.) - short, safe data
- **Unsafe fields** (DE, HI, etc.) - long text, potential for taint

Both messages reuse the same sendId (reuseCount tracks this).

### 3. MSP Name Guard

**File**: `hooks/msp.lua`
**Purpose**: Prevent MyRolePlay crashes from nil NA fields

**Problem**:
MyRolePlay's chat integration crashes if `msp.char[name].field.NA` is nil:
```lua
-- MRP/Chat.lua:108
if msp.my["NA"]:find(pattern) then  -- CRASH if NA is nil
```

**Solution**: Chat filter ensures NA exists before MRP's filter runs
```lua
for _, event in ipairs(CHAT_EVENTS) do
    ChatFrame_AddMessageEventFilter(event, function(_, event, message, author, ...)
        EnsureMSPNA(author)  -- Fills missing NA
        TRP3FW:VerifyMSPIntegrity()  -- Restores metatable if dropped
        return false  -- Don't filter message
    end)
end
```

**Throttling**:
- NA checks: Once per player per 5 seconds
- Integrity checks: Twice per second (prevents spam)

### 4. MSP Integrity Verification

**File**: `hooks/msp_exchange.lua`
**Function**: `TRP3FW:VerifyMSPIntegrity()`

**Purpose**: Restore MSP metatable if another addon drops it

**Problem**:
Ghost mode uses a metatable proxy on `msp.my` to intercept field reads. Other addons sometimes reassign `msp.my = {}`, dropping our metatable.

**Solution**: Periodic integrity checks
```lua
function TRP3FW:VerifyMSPIntegrity()
    local currentMeta = getmetatable(msp.my)
    local ourMeta = self.hookState.exchange.mspMyMeta

    if currentMeta ~= ourMeta then
        -- Metatable dropped! Restore it

        -- Security: Validate and merge physical fields
        for k, v in pairs(msp.my) do
            if VALID_MSP_FIELDS[k] and IsSafe(v) then
                originalMSPMy[k] = v
            end
        end

        -- Restore metatable
        setmetatable(msp.my, ourMeta)

        -- Clear physical fields (metatable serves values now)
        for k in pairs(msp.my) do
            msp.my[k] = nil
        end
    end
end
```

**Security Checks**:
- Field whitelist (only known MSP fields)
- Type validation (strings/numbers/booleans only)
- Size limits (10KB per field)
- Total field count limit (100 fields max)

---

## Chomp Pipeline Hook

**File**: `hooks/trp3_chomp_pipeline.lua`
**Function**: `AddOn_Chomp.SmartAddonMessage(...)`

**Purpose**: Central location gating for ALL profile sends

### Why Hook Chomp?

Both TRP3 and LibMSP use Chomp for message transmission:
- **TRP3**: `AddOn_TotalRP3.Communications.sendObject()` → Chomp
- **MSP**: `msp.Reply()` → Chomp

By hooking Chomp, we intercept all profile sends in one place.

### Pipeline Architecture

```
ChompHookPipeline
    ├─ Stage 1: Guard Checks
    │   └─ Recursion guards, replay guards, enabled checks
    ├─ Stage 2: Phase-In Delay
    │   └─ Queue sends during zone transitions
    ├─ Stage 3: Mutual Exchange Detection
    │   └─ Check if user-initiated (suppress notifications)
    ├─ Stage 4: Start Phase Block/Ghost
    │   └─ Phase 169 protection (block or ghost)
    ├─ Stage 5: Burst Detection
    │   └─ Deduplicate concurrent requests
    └─ Stage 6: Location Gating
        └─ Decision engine (allow/block/ghost)
```

### Stage Details

#### Stage 1: Guard Checks

```lua
function TRP3FW:ChompPipeline_GuardChecks_V2(prefix, text, chatType, target, ...)
    -- Recursion guard (ghost mode sends bypass)
    if self.hookState.chomp.sendingGhostProfile then
        return {shouldContinue = false, reason = "recursion_guard"}
    end

    -- Replay guard (queued sends bypass phase-in)
    if self.hookState.chomp.replayingPhaseInSend then
        return {shouldContinue = false, reason = "replay_guard"}
    end

    return {shouldContinue = true}
end
```

#### Stage 2: Phase-In Delay

**Purpose**: Queue profile sends during zone transitions (phase/map changes confuse location checks)

```lua
function TRP3FW:ChompPipeline_PhaseInDelay_V2(playerName, prefix, text, chatType, target, ...)
    local phaseInDelay = TRP3FW.Prefs.phaseInDelay or 4  -- Default 4 seconds
    local timeSinceZoneChange = now - self.lastZoneChangeTime

    if timeSinceZoneChange < phaseInDelay then
        -- Queue this send
        table.insert(self.pendingPhaseInSends, {
            prefix = prefix,
            text = text,
            chatType = chatType,
            target = target,
            -- ... all args
            queuedAt = now
        })

        -- Schedule replay after delay
        C_Timer.After(delayRemaining, function()
            -- Replay with replay guard enabled
            self.hookState.chomp.replayingPhaseInSend = true
            AddOn_Chomp.SmartAddonMessage(queuedSend.prefix, ...)
            self.hookState.chomp.replayingPhaseInSend = false
        end)

        return {shouldContinue = false, queued = true}
    end

    return {shouldContinue = true}
end
```

**Queue Limits**:
- Max size: 200 entries
- TTL: 3x phase-in delay (default 12 seconds)
- Eviction: Oldest entry dropped if full

#### Stage 3: Mutual Exchange Detection

```lua
function TRP3FW:ChompPipeline_MutualExchange_V2(playerName)
    local isMutual = self:IsUserInitiatedExchange(playerName)
    return {shouldContinue = true, isMutual = isMutual}
end
```

**Mutual Exchange**: Both players simultaneously request each other's profiles (common in RP interactions).

**Detection**: Check if player was recently queried via sendQuery/MSP Request hooks.

**Effect**: Suppress notifications (user already knows about exchange), but **still enforce blocking**.

#### Stage 4: Start Phase Block/Ghost

**Purpose**: Phase 169 (Epsilon start phase) protection

```lua
function TRP3FW:ChompPipeline_StartPhaseBlock_V2(playerName, prefix, text, chatType, target, ...)
    local isRequest = false  -- Check if this message is a request (VQ, GI, ?MSP)

    if isRequest then
        -- Requests don't contain profile data, allow
        return {shouldContinue = false, blocked = false, ghost = false}
    end

    -- This is a profile send
    local shouldBlock, action = TRP3FW:ShouldBlockForStartPhase(target, true)

    if shouldBlock and action == "ghost" then
        local isMSP = prefix and prefix:find("MSP")

        if isMSP then
            -- MSP ghost handled by metatable (already applied)
            return {shouldContinue = false, blocked = false, ghost = true}
        else
            -- TRP3 ghost: enable flag (sendObject hook will intercept)
            TRP3FW:EnableGhostForNextSend(cleanTarget, alternateProfileID)
            return {shouldContinue = false, blocked = false, ghost = true}
        end
    elseif shouldBlock and action == "block" then
        -- Block the send entirely
        return {shouldContinue = false, blocked = true, ghost = false}
    end

    return {shouldContinue = true}
end
```

**Request Detection**:
`sendObject` hook marks VQ/GI messages in `TRP3FW.currentMessageIsRequest[playerName]` (1s TTL). Chomp hook checks this flag.

#### Stage 5: Burst Detection

**Purpose**: Deduplicate concurrent profile requests (e.g., TRP3 sends 3+ messages per exchange)

```lua
function TRP3FW:ChompPipeline_BurstDetection_V2(playerName, ...)
    if self.pendingChompSends[playerName] then
        local timeSinceFirst = now - self.pendingChompSends[playerName].timestamp

        if timeSinceFirst < 2 then
            -- Recent request in progress, queue this one
            table.insert(self.pendingChompSends[playerName].queuedRequests, {
                prefix = prefix,
                text = text,
                -- ... all args
            })
            return {shouldContinue = false, queued = true}
        else
            -- Old entry, clear it
            self.pendingChompSends[playerName] = nil
        end
    end

    -- Mark as pending (first request in burst)
    self.pendingChompSends[playerName] = {
        timestamp = now,
        queuedRequests = {}
    }

    return {shouldContinue = true}
end
```

**Burst Window**: 2 seconds
**Queued Requests**: Processed after location check completes (shared result)

#### Stage 6: Location Gating

```lua
function TRP3FW:ChompPipeline_LocationGating_V2(playerName, addon, sendId, originalFunc, originalArgs, context)
    -- Call decision engine
    local result = self:CheckLocationAndNotify(
        playerName,
        addon,
        true,  -- isWhisper
        sendId,
        originalFunc,
        originalArgs
    )

    return {result = result}
end
```

Calls the main decision engine (see [DECISION_LOGIC.md](DECISION_LOGIC.md)).

---

## Scan Reply Hooks

**Purpose**: Gate map scan responses to prevent information leakage

### Problem

Map scanning broadcasts position to ALL players on the map. Without gating, remote players (different phase/location) can:
- Track your position
- Know you're online
- Harvest profile data without being nearby

### Solution

Hook scan response functions and apply location checks:
- **Allow**: If requester passes location checks
- **Block**: If requester fails location checks
- **Alert**: Notify user of blocked scan replies

### TRP3 Scan Hook

**File**: `hooks/trp3.lua`
**Function**: `AddOn_TotalRP3.Communications.broadcast.sendP2PMessage(target, command, ...)`

```lua
AddOn_TotalRP3.Communications.broadcast.sendP2PMessage = function(target, command, ...)
    if command == "C_SCAN" then
        -- C_SCAN is a scan reply (contains position data)
        return HandleScanReply(target, C_Map.GetBestMapForUnit("player"), function()
            return originalSendP2P(target, command, ...)
        end, "TRP3")
    end

    return originalSendP2P(target, command, ...)
end
```

### RPMapScan Hook

**File**: `hooks/trp3.lua`
**Function**: `RPMapScan.SendP2PResponse(self, target, requestedMapID, ...)`

```lua
RPMapScan.SendP2PResponse = function(selfRef, target, requestedMapID, ...)
    local myMapID = C_Map.GetBestMapForUnit("player")

    -- Only gate if on same map (cross-map scans already filtered)
    if myMapID == requestedMapID then
        return HandleScanReply(target, requestedMapID, function()
            return originalRPMSend(selfRef, target, requestedMapID, ...)
        end, "RPMapScan")
    end

    return originalRPMSend(selfRef, target, requestedMapID, ...)
end
```

### HandleScanReply Pipeline

**File**: `features/pipelines/ScanReplyPipeline.lua`

```lua
function TRP3FW:HandleScanReplyPipeline(targetRaw, sendFunc, contextLabel)
    local playerName = self:CleanPlayerName(targetRaw)

    -- Check if map scanning disabled
    if self.mapScanDisabledReason then
        return sendFunc()  -- Allow (no map checks available)
    end

    -- Check if map alerts disabled
    if not TRP3FW.Prefs.alertOnMapFail then
        return sendFunc()  -- Allow (user disabled map protection)
    end

    -- Check whitelist
    if self:IsPlayerWhitelisted(playerName) then
        return sendFunc()  -- Allow
    end

    -- Check location (phase → WHO → map cascade)
    self:CheckLocationCascading(playerName, function(locationOK, method)
        if locationOK then
            sendFunc()  -- Allow scan reply
        else
            -- Block scan reply
            self:ShowScanReplyBlockNotification(playerName, method, contextLabel)
            self.sessionStats.blockedScanReplies = (self.sessionStats.blockedScanReplies or 0) + 1
        end
    end)
end
```

**Performance**: Async location check (non-blocking)

---

## Safety Mechanisms

### 1. Recursion Prevention

**Problem**: Ghost mode modifies data, triggering hooks again.

**Guards**:
```lua
-- Chomp hook
self.hookState.chomp.sendingGhostProfile = true
-- ... send ghost data ...
self.hookState.chomp.sendingGhostProfile = false

-- MSP metatable
self.sendingGhostProfile = true
-- ... access msp.my fields ...
self.sendingGhostProfile = false
```

### 2. Hook Chaining

**Problem**: Multiple addons may hook the same function.

**Solution**: Cache original function, not current function
```lua
-- BAD: Wraps existing wrapper
local current = AddOn_Chomp.SmartAddonMessage
AddOn_Chomp.SmartAddonMessage = function(...)
    return current(...)  -- May call another addon's hook
end

-- GOOD: Wraps original function
self.hookState.originals.chompSend = self.hookState.originals.chompSend or AddOn_Chomp.SmartAddonMessage
local original = self.hookState.originals.chompSend
AddOn_Chomp.SmartAddonMessage = function(...)
    return original(...)  -- Calls cached original
end
```

### 3. Conflict Detection

See [Conflict Detection](#conflict-detection) section.

### 4. Graceful Degradation

**Principle**: If hook fails, addon continues functioning

```lua
-- Safe hook installation
local ok, err = pcall(function()
    AddOn_Chomp.SmartAddonMessage = TRP3FW.ChompHookWrapper
end)

if not ok then
    self:Warn("Failed to install Chomp hook: "..tostring(err))
    self.hookStatus.chomp = "failed"
    -- Addon continues without location gating
end
```

### 5. Phase Check Targeting Guard

**Problem**: TRP3FW's phase checks use targeting API. If we count our own targeting as "user-initiated", every phase check looks like a manual query.

**Solution**: Phase check flag
```lua
-- Before phase check targeting
TRP3FW.phaseCheckTargeting = true

-- Perform targeting
TargetUnit(playerName)

-- Clear flag
TRP3FW.phaseCheckTargeting = false

-- sendQuery hook checks this flag
if UnitName("target") == name and not TRP3FW.phaseCheckTargeting then
    -- Real user targeting
end
```

---

## Hook Chaining

**Principle**: Multiple addons can hook the same function if done correctly.

### Bad Chaining (Breaks)

```lua
-- Addon A
local oldFunc = SomeAddon.DoThing
SomeAddon.DoThing = function(...)
    print("Addon A")
    return oldFunc(...)
end

-- Addon B (loaded after A)
local oldFunc = SomeAddon.DoThing  -- Wraps A's wrapper!
SomeAddon.DoThing = function(...)
    print("Addon B")
    return oldFunc(...)  -- Calls A's wrapper
end

-- Call chain: B → A → original
-- If A is disabled, chain breaks
```

### Good Chaining (Robust)

```lua
-- Addon A
A.originals = A.originals or {}
A.originals.doThing = A.originals.doThing or SomeAddon.DoThing
SomeAddon.DoThing = function(...)
    print("Addon A")
    return A.originals.doThing(...)  -- Calls cached original
end

-- Addon B
B.originals = B.originals or {}
B.originals.doThing = B.originals.doThing or SomeAddon.DoThing
SomeAddon.DoThing = function(...)
    print("Addon B")
    return B.originals.doThing(...)  -- Calls cached original
end

-- Both call the ORIGINAL function
-- If A is disabled, B still works
```

**TRP3FW Implementation**:
```lua
-- Cache original ONCE
self.hookState.originals.chompSend = self.hookState.originals.chompSend or AddOn_Chomp.SmartAddonMessage

-- Always call cached original
local original = self.hookState.originals.chompSend
AddOn_Chomp.SmartAddonMessage = function(...)
    return TRP3FW:ChompHookWrapper(..., original)
end
```

---

## Common Patterns

### Pattern 1: Hook with Conflict Detection

```lua
function TRP3FW:InstallMyHook()
    if not SomeAddon or not SomeAddon.TargetFunction then
        self:Debug("Cannot install hook - TargetFunction not found", "hooks")
        return false
    end

    local conflict = self:CheckHookConflict("myHook", SomeAddon.TargetFunction, self.hookState.originals.myHook, nil)
    if conflict.action == "skip" then
        return true  -- Already installed
    elseif conflict.action == "refuse" then
        self.hookStatus.myHook = "refused"
        return false
    end

    self.hookState.originals.myHook = self.hookState.originals.myHook or SomeAddon.TargetFunction
    local original = self.hookState.originals.myHook

    SomeAddon.TargetFunction = function(...)
        -- Hook logic
        return original(...)
    end

    self:Debug("Installed myHook", "hooks")
    return true
end
```

### Pattern 2: Async Hook with Callback

```lua
SomeAddon.SendProfile = function(target, ...)
    local args = {...}

    -- Async location check
    TRP3FW:CheckLocationCascading(target, function(locationOK)
        if locationOK then
            originalSendProfile(target, unpack(args))
        else
            TRP3FW:ShowBlockNotification(target)
        end
    end)
end
```

### Pattern 3: Ghost Mode Hook

```lua
SomeAddon.SendData = function(data, target, ...)
    local ghostTarget = TRP3FW:GetCurrentGhostTarget()

    if ghostTarget and ghostTarget == target then
        -- Replace data with ghost data
        data = TRP3FW:GenerateGhostData(target)
        TRP3FW:ClearGhostFlag(target)  -- Consume ghost flag
    end

    return originalSendData(data, target, ...)
end
```

---

## Troubleshooting

### Hooks Not Installing

**Check**:
```bash
/trp3fw status
# Look for "Hook Status" section
```

**Common Causes**:
- Addon loaded before TRP3/MSP (load order issue)
- Strict hook mode enabled (conflict detected)
- Multiple RP addons detected (auto-disable)

**Fix**:
```bash
/trp3fw reloadhooks  # Reinstall all hooks
/reload              # Reload UI
```

### Ghost Mode Not Working

**Check**:
```lua
/dump TRP3FW.ghostNextSend  -- Should be table if active
/dump TRP3FW.hasMSPExchangeHooks  -- Should be true
```

**Common Causes**:
- Ghost mode disabled in settings
- Exchange hooks not installed (MSP/TRP3 not detected)
- Ghost flag expired (30s TTL)

**Debug**:
```bash
/trp3fw debug
/trp3fw debugfilter ghost
# Trigger ghost send, watch for "[Ghost Flag]" messages
```

### Location Checks Bypassed

**Symptom**: Profiles sent without location checks

**Check**:
```lua
/dump TRP3FW.originalChompSend  -- Should be function
/dump AddOn_Chomp.SmartAddonMessage  -- Should be TRP3FW wrapper
```

**Common Causes**:
- Chomp hook failed to install
- Another addon replaced Chomp function after TRP3FW
- Recursion guard stuck (sendingGhostProfile = true)

**Fix**:
```bash
/trp3fw reloadhooks
/reload
```

### Hook Conflicts

**Check**:
```lua
/dump TRP3FW.hookConflicts
-- Example output:
-- {
--   chomp = {reason = "conflict_existing_hook", source = "@SomeAddon/hook.lua:42", action = "refuse"}
-- }
```

**Diagnosis**:
- `conflict_existing_hook` - Another addon modified the function
- `already_wrapped` - Hook already installed (shouldn't happen)
- `target_not_callable` - Function doesn't exist or is nil

**Solutions**:
1. Disable strict hook mode: `/trp3fw strict off`
2. Load TRP3FW after conflicting addon (change load order)
3. Report conflict to addon authors

---

## Performance

### Hook Overhead

**Measured with `/trp3fw profile on`**:

| Hook | Avg Latency | P95 | Notes |
|------|-------------|-----|-------|
| Chomp | 0.8ms | 2.1ms | Pipeline processing |
| SendQuery | 0.1ms | 0.2ms | Tracking only |
| MSP Request | 0.1ms | 0.2ms | Tracking + NA guard |
| SendObject | 0.3ms | 0.7ms | Ghost mode checks |
| Scan Reply | 1.2ms | 3.4ms | Async location check |

**Total Overhead**: ~1-2ms per profile send (acceptable for RP)

### Optimization Techniques

1. **Early Exit**: Guards check return immediately
2. **Cache Hits**: Cached results bypass location checks (0.1ms)
3. **Lazy Evaluation**: Debug messages use function syntax to avoid string concat when debug disabled
4. **Pooled Tables**: Reuse context/result tables instead of creating new ones
5. **Throttling**: NA guard checks once per 5s per player

---

**Related Documentation**:
- [DECISION_LOGIC.md](DECISION_LOGIC.md) - Decision pipeline (called by Chomp hook)
- [GHOST_MODE.md](GHOST_MODE.md) - Ghost mode implementation
- [LOCATION_DETECTION.md](LOCATION_DETECTION.md) - Location check methods
- [DATA_STRUCTURES.md](DATA_STRUCTURES.md) - Hook state variables

**Last Updated**: 2026-01-11
**Maintainer**: Review when adding new hooks or modifying pipeline stages
