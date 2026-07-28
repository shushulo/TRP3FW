# Epsilon Server Compatibility Guide

Complete reference for Epsilon-specific features, workarounds, and known issues.

## Overview

TRP3 Firewall is designed to work on **Epsilon WoW 9.2.5**, which includes custom features and API limitations not present in retail WoW. This document covers all Epsilon-specific considerations.

---

## Epsilon API Features

### C_Epsilon.RunPrivileged

**Purpose:** Execute protected Lua code that would normally be blocked by Blizzard's protected function system.

**Usage in TRP3FW:**
- WHO queries (`C_FriendList.SendWho`)
- Targeting (`TargetUnit`)
- Frame operations in combat

**Rate Limiting:**
- Token bucket: 10 tokens/second
- Reserved tokens: 2 (for HIGH priority operations)
- Tracked via `TRP3FW:RunPrivilegedSafe()`

**Example:**
```lua
local code = 'C_FriendList.SetWhoToUi(false); C_FriendList.SendWho([[z-"ZoneName"]])'
local success, err = TRP3FW:RunPrivilegedSafe(code, "who_zone_query")
```

---

## Known Issues & Workarounds

### Issue 1: WHO_LIST_UPDATE Event Not Firing

**Problem:**
On Epsilon 9.2.5, the `WHO_LIST_UPDATE` event does not fire reliably after calling `C_FriendList.SendWho()` via `RunPrivileged`.

**Symptoms:**
- WHO queries execute successfully
- Results are available in `C_FriendList.GetNumWhoResults()`
- Event never triggers, leaving queries "stuck"
- WHO caches remain empty

**Root Cause:**
Protected function calls via `RunPrivileged` may bypass normal event dispatch.

**Workaround 1: Polling Fallback (Primary)**
```lua
-- After executing WHO query, wait 0.5s and check manually
C_Timer.After(0.5, function()
    if self.pendingQuery and self.pendingQuery.requestId == currentReqId then
        local ok, numWho = pcall(C_FriendList.GetNumWhoResults)
        if ok and numWho and numWho > 0 then
            -- Results available but event didn't fire - process manually
            self:OnWhoListUpdate()
        end
    end
end)
```

**Workaround 2: CHAT_MSG_SYSTEM Backup (Secondary)**
Monitor system chat messages for WHO result patterns:
```lua
EventService:RegisterCallback("CHAT_MSG_SYSTEM", function(event, msg)
    -- Match "X |4player:players; total"
    if msg:find("found") or msg:find("Players") or msg:find("Online") then
        C_Timer.After(0.1, function()
            self:OnWhoListUpdate()
        end)
    end
end)
```

**Files:**
- `features/services/WhoService.lua:320-332` (polling fallback)
- `features/services/WhoService.lua:44-55` (CHAT_MSG_SYSTEM backup)
- `core/EventService.lua:93-94` (CHAT_MSG_SYSTEM forwarding)

---

### Issue 2: Custom Map Names

**Problem:**
Epsilon allows server admins to rename maps. The WoW API `C_Map.GetMapInfo(mapID).name` returns the **default Blizzard name**, not the custom Epsilon name.

**Example:**
- Actual zone: "Silverwind Refuge" (custom Epsilon name)
- `C_Map.GetMapInfo(896).name`: "Infinite Flatlands" (Blizzard default)

**Impact:**
WHO queries searching for "Infinite Flatlands" find zero players because everyone is actually in "Silverwind Refuge".

**Solution:**
Prioritize actual zone text functions over map info:

```lua
-- CORRECT order for Epsilon
local zoneName = GetRealZoneText()  -- Returns custom name
if not zoneName or zoneName == "" then
    zoneName = GetZoneText()
end
if not zoneName or zoneName == "" then
    zoneName = GetMinimapZoneText()
end
-- Only use as last resort
if not zoneName or zoneName == "" then
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then
        local info = C_Map.GetMapInfo(mapID)
        zoneName = info and info.name or nil
    end
end
```

**Files:**
- `features/services/CacheService.lua:450-458` (zone change handler)
- `features/services/CacheService.lua:594-620` (prepopulation)

---

### Issue 3: Service Initialization Order

**Problem:**
`pairs()` has undefined iteration order. If WhoService initializes before EventService, event callbacks fail to register.

**Symptoms:**
- `WHO_LIST_UPDATE` callbacks never fire (even when event does fire)
- `CHAT_MSG_SYSTEM` callbacks never fire
- WHO queries execute but results never processed

**Solution:**
Force EventService to initialize first:

```lua
function TRP3FW.ServiceContainer:InitializeAll()
    -- Initialize EventService FIRST
    local eventService = self.services["EventService"]
    if eventService and not eventService.initialized then
        eventService:Initialize()
    end

    -- Initialize all others
    for name, service in pairs(self.services) do
        if name ~= "EventService" and not service.initialized then
            service:Initialize()
        end
    end
end
```

**Files:**
- `core/ServiceContainer.lua:30-45`

---

## Privileged Code Best Practices

### Semicolon Separators Required

**Wrong:**
```lua
local code = 'C_FriendList.SetWhoToUi(false) C_FriendList.SendWho(...)'
-- Fails to parse - two statements on one line
```

**Correct:**
```lua
local code = 'C_FriendList.SetWhoToUi(false); C_FriendList.SendWho(...)'
-- Semicolon separates statements
```

### Error Handling

Always wrap privileged calls in `pcall`:
```lua
local success, result = pcall(C_Epsilon.RunPrivileged, code)
if not success then
    TRP3FW:Debug("[RunPrivileged] FAILED: "..tostring(result))
    return false, "execution_error"
end
```

### Rate Limiting Awareness

High-priority operations (targeting, clearing) use reserved tokens. Design your code to:
- Batch operations when possible
- Use appropriate priority levels
- Handle `rate_limit` errors gracefully

---

## Testing on Epsilon

### Debug Commands

```bash
/trp3fw debug
/trp3fw debugfilter who
/trp3fw debugfilter cache
/trp3fw debugfilter security  # Shows RunPrivileged calls
/reload
```

### Expected Output (Successful WHO Query)

```
[Prepopulate] Detected zone: Silverwind Refuge (mapID: 896)
[WhoService] Executing WHO query: z-"Silverwind Refuge" (useZoneQuery=true)
[WhoService] Privileged code: C_FriendList.SetWhoToUi(false); C_FriendList.SendWho(...)
[RunPrivileged] SUCCESS (NORMAL): 'who_zone_query' (Tokens: 9.0/10)
[WhoService] RunPrivileged succeeded, waiting for WHO_LIST_UPDATE event
[WhoService] DIAGNOSTIC: WHO results available (5) but WHO_LIST_UPDATE hasn't fired yet!
[WhoService] OnWhoListUpdate processing results for <YourName>
[WhoService] WHO results: 5 players found
[WhoService] Cached zone metadata for Silverwind Refuge (count=5)
[WhoService] Cached 5 player results
```

### Red Flags

**No WHO query executed:**
```
[Prepopulate] Skipped - hasEpsilonAPI=false, useWhoQuery=false
```
→ Epsilon API not detected or WHO queries disabled

**Wrong zone name:**
```
[Prepopulate] Detected zone: Infinite Flatlands (mapID: 896)
```
→ Using map info instead of zone text (custom name not detected)

**Query timeout:**
```
[WhoService] Query timeout for <PlayerName>
```
→ Results never arrived or event never fired

**Event didn't fire:**
```
[WhoService] DIAGNOSTIC: WHO results available (X) but WHO_LIST_UPDATE hasn't fired yet!
```
→ Expected on Epsilon - fallback is working correctly

---

## Phase System (Epsilon-Specific)

Epsilon's phase system allows creating isolated instances of the game world. TRP3FW uses phases for proximity detection.

### Phase Detection Methods

1. **SPVP (Secure Phase Verification Protocol)** - Cryptographic handshake
2. **Targeting** - `TargetUnit(name)` via `RunPrivileged`
3. **Nameplate scanning** - Check visible nameplates
4. **Party/Raid check** - Group members assumed same phase (optional)

### Phase 169 Blocking

Phase 169 is a special "start phase" on Epsilon. Can be blocked via:
- `blockStartPhase` - Block profile sends
- `ghostOnStartPhase` - Send blank profile

---

## Debugging Epsilon Issues

### 1. Verify Epsilon API

```lua
/run print("Epsilon API:", C_Epsilon and "Available" or "Missing")
/run print("RunPrivileged:", C_Epsilon and C_Epsilon.RunPrivileged and "Available" or "Missing")
```

### 2. Check Zone Detection

```lua
/run print("RealZone:", GetRealZoneText(), "Zone:", GetZoneText(), "MapInfo:", select(2, C_Map.GetMapInfo(C_Map.GetBestMapForUnit("player") or 0)))
```

### 3. Test WHO Query Manually

```lua
/run C_Epsilon.RunPrivileged('C_FriendList.SetWhoToUi(false); C_FriendList.SendWho([[z-"'..GetRealZoneText()..'"]])')
/run print("WHO Results:", C_FriendList.GetNumWhoResults())
```

### 4. Monitor Event Firing

```lua
/run local f = CreateFrame("Frame"); f:RegisterEvent("WHO_LIST_UPDATE"); f:SetScript("OnEvent", function() print("WHO_LIST_UPDATE FIRED!") end)
```

---

## Version Compatibility

**Tested On:**
- Epsilon WoW 9.2.5 (Shadowlands)
- Interface: 90205

**Known Compatible:**
- Epsilon WoW 9.2.7 (latest)

**Not Compatible:**
- Retail WoW (no Epsilon API)
- Classic WoW (no Epsilon API)
- Private servers without Epsilon API

---

## Performance Considerations

### Privileged Call Rate Limiting

- **Token Bucket:** 10 tokens/second
- **Cost per Call:** 1 token
- **Reserved:** 2 tokens for HIGH priority

**WHO queries are NORMAL priority.** In heavy usage scenarios (many profile requests), WHO queries may be deferred when token bucket is low.

**Solution:** WHO queries use prepopulation to build zone cache during idle periods.

### WHO Query Cooldowns

- **Zone query cooldown:** 20s (default)
- **Name query cooldown:** 1.0s (default)

These prevent spamming Epsilon's WHO system.

---

## Future Considerations

### Potential Improvements

1. **Event Hooking:** Hook `WHO_LIST_UPDATE` at C++ level (requires Epsilon API extension)
2. **Batch WHO Queries:** Queue multiple player checks into single zone query
3. **Phase API:** Direct phase membership API (avoiding targeting requirement)
4. **Zone Name API:** `C_Epsilon.GetCustomZoneName(mapID)` to avoid text fallbacks

### Known Limitations

- WHO queries limited to 50 results (WoW API limitation)
- Truncated zones require name-specific queries (slower)
- Zone text functions may lag on zone transitions
- Custom zone names not available via API (text parsing only)
