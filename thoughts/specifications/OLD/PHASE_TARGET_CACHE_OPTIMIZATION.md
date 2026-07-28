# Feature Specification: Phase Check Target Caching Optimization

## 1. Overview
This optimization aims to reduce redundant WHO queries to the Epsilon server by leveraging successful phase checks. When the addon successfully targets a player during a phase check, we implicitly confirm their presence in the current zone. This data should be immediately written to the WHO cache.

## 2. Problem Statement
Currently, the location detection system runs in a cascading manner:
1.  **Phase Check:** Attempts to target the player (via `RunPrivileged` batching or manual target).
2.  **Map Check:** If the phase check succeeds but requires map verification (or fails and cascades), the system runs a Map Check.
3.  **Map Check Logic:** The map check first looks at the `whoName` and `whoZone` caches. If missing, it triggers a `who n-"Player"` or `who z-"Zone"` query.

**Inefficiency:** Even if `CheckPlayerPhase` successfully targets a player (confirming they are in the instance/zone), this "location data" is only stored in the `phaseCheck` cache. It is *not* propagated to the `who*` caches. Consequently, if the logic proceeds to a Map Check, the addon may redundantly fire a WHO query for a player we just successfully targeted.

## 3. Proposed Solution
Modify the Phase Check logic (specifically the targeting method) to populate the `whoName` cache upon a successful target.

**Logic Flow:**
1.  `CheckPlayerPhase` (or the batch processor) executes `/target Player`.
2.  Target is acquired (`UnitExists` is true).
3.  **NEW STEP:** Immediately write an entry to the `whoName` cache.
    *   **Key:** Player Name (Sanitized).
    *   **Value:**
        *   `zoneName`: Current Zone Name (since targeting implies same instance).
        *   `mapID`: `C_Map.GetBestMapForUnit("target")`.
        *   `timestamp`: Current Time.

## 4. Technical Implementation

### 4.1. Affected Files
*   `location/phase.lua`

### 4.2. Logic Changes

#### In `PerformBatchPhaseCheck` (or equivalent targeting logic):
When a unit is successfully targeted:

```lua
-- Existing logic
local mapID = C_Map.GetBestMapForUnit("target")
CacheInterface:Set("phaseCheck", playerName, {
    timestamp = now,
    result = true,
    mapID = mapID,
    source = "batch", -- or "target"
    method = "target"
})

-- NEW LOGIC: Cross-populate WHO cache
-- Since we targeted them, they are definitely in our zone/instance.
local currentZone = GetRealZoneText() -- or TRP3FW.currentZoneName
CacheInterface:Set("whoName", playerName, {
    timestamp = now,
    zoneName = currentZone,
    mapID = mapID
})
```

#### In `CheckPlayerViaWho` (Cache Hit Handler):
When retrieving data from the WHO cache:

```lua
local cached, cacheType, age = CheckWhoCaches(playerName)
if cached then
    -- NEW LOGIC: Background Refresh
    -- If cache entry is valid but aging, trigger a low-priority refresh
    local thresholdPercent = TRP3FW.Prefs.whoCacheRefreshThreshold -- e.g., 50 (50%)
    local ttl = TRP3FW.Prefs.whoNameCacheDuration
    
    if age > (ttl * (thresholdPercent / 100)) then
        -- Queue a background WHO query (or Phase Check if more efficient?)
        -- Since this is the WHO cache, we default to a low-priority WHO query.
        TRP3FW:CheckPlayerViaWho(playerName, nil, function() end, false, true, "LOW")
    end

    callback(true, "cached", age, cached.zoneName, cached.mapID)
    TrackWhoCacheStat(sendId, true, playerName)
    return
end
```

### 4.3. Cache Selection
We will write to the **`whoName`** cache (tier 1) rather than `whoZone` cache.
*   **Reason:** The `whoName` cache is intended for specific player lookups and typically has a specific TTL (`whoNameCacheDuration`).
*   **Lookup Priority:** `CheckPlayerViaWho` checks `whoName` before `whoZone`, so this ensures the hit occurs.

### 4.4. Configuration & Refresh Logic
To align with other cache systems (Phase, Interaction), we will add a refresh threshold setting to ensure data remains fresh without blocking the main thread.

**New Setting:**
*   **Name:** `whoCacheRefreshThreshold`
*   **Type:** `number` (0 - 100)
*   **Default:** `50` (50%)
*   **Description:** Percentage of the cache duration after which a cache hit triggers a background refresh.
    *   *Example:* If Duration = 180s and Threshold = 50, a hit after 90s will return the cached value immediately but queue a "LOW" priority WHO query to update the entry.

**Implementation Details:**
*   Add to `TRP3FW.Prefs` in `core/init.lua` (defaults).
*   Add logic to `CheckPlayerViaWho` (as shown in 4.2).
*   Ensure the background refresh uses "LOW" priority to avoid consuming `RunPrivileged` tokens needed for active user requests.

### 4.5. UI Changes
The new setting needs to be exposed to the user in the configuration menu.

**Location:**
*   **Tab:** Cache and Debug
*   **Section:** Who and Zone Cache Settings

**UI Element:**
*   **Type:** Text Box (EditBox)
*   **Label:** "WHO Cache Refresh Threshold (%)"
*   **Default:** "50"
*   **Validation:** Numeric, 0-100.
*   **Tooltip:** "Percentage of cache duration after which a cache hit triggers a background refresh. Lower values refresh more often."

## 5. Impact Analysis

### 5.1. Performance
*   **API Calls:** Reduces Epsilon `RunPrivileged` calls (WHO queries) significantly in scenarios where Phase Checks pass but Map Checks are still requested (e.g., for verifying map IDs).
*   **Latency:** Eliminates the wait time for WHO query results (network RTT + processing) during the cascading check, making the final `locationOK` decision faster.

### 5.2. Edge Cases
*   **Wrong Map:** `C_Map.GetBestMapForUnit` is generally reliable if targeted. If it returns nil, we should still cache the Zone Name, as that is sufficient to prevent a "Not Found" result in WHO.
*   **Cross-Phase Targeting:** Epsilon allows targeting across phases?
    *   *Assumption:* Generally, `/target` works within the same map instance. If Epsilon mechanics allow targeting someone in a different *phase ID* but same *map instance* (which TRP3FW treats as "Same Phase" usually), the WHO cache entry of "Current Zone" is still technically correct regarding the "Zone" check.

## 6. Success Metrics
*   Increase in `whoCacheHits` in Session Statistics.
*   Decrease in `whoStats.nameQueries` relative to `totalRequests`.
