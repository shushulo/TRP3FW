# Caching System Reference

Complete reference for all cache layers, TTLs, eviction policies, and management.

## Architecture Overview

TRP3FW uses a **unified LRU (Least Recently Used) cache system** with O(1) access and eviction.

**CacheInterface** manages all caches with:
- Automatic TTL expiration
- LRU eviction when size limit reached
- Per-cache configuration (TTL, max size)
- O(1) Get/Set/Delete operations

## Cache Hierarchy

### 1. Interaction Cache
**Purpose:** Track players you've moused over or targeted (mutual exchanges allowed)

**Key:** Player name (sanitized)

**Value Structure:**
```lua
{
    timestamp = number,    -- When interaction occurred
    zone = string,         -- Zone at time of interaction
    mapID = number,        -- Map ID at time of interaction
    method = string        -- "mouseover" | "target" | "mutual_exchange"
}
```

**Configuration:**
- **TTL:** `interactionCacheDuration` (default: 600s / 10 min)
- **Max Size:** `cacheSizeLimit` (default: 1000)
- **Refresh Rate:** `interactionRefreshRate` (default: 10% = 60s threshold)

**Invalidation:** `InteractionStage` invalidates the cached entry on lookup if
either `mapID` or `zone` differs from the current value. `mapID` is the primary
key (more reliably populated than `zone`); the `zone` mismatch is a secondary
fallback.

---

### 2. Phase Check Cache
**Purpose:** Cache phase verification results (same/different phase)

**Key:** Player name (sanitized)

**Value Structure:**
```lua
{
    timestamp = number,
    inPhase = true|false|nil,  -- Same phase | Different | Unknown
    mapID = number,           -- Their map ID (if available)
    method = string           -- Detection method used
}
```

**Configuration:**
- **TTL:** `phaseCacheDuration` (default: 300s / 5 min)
- **Failure TTL:** `phaseCacheFailureDuration` (default: 10s - allows quick retries)
- **Max Size:** `cacheSizeLimit` (default: 1000)
- **Refresh Threshold:** `phaseCacheRefreshThreshold` (default: 50% = 150s)

---

### 3. WHO Name Cache
**Purpose:** Cache individual WHO query results (most authoritative)

**Key:** Player name (sanitized)

**Value Structure:**
```lua
{
    timestamp = number,
    found = boolean,      -- true if player found, false if not found
    zone = string,        -- Zone they were found in (nil if not found)
    mapID = number        -- Our map ID at time of query (nil if not found)
}
```

**Configuration:**
- **TTL:** `whoNameCacheDuration` (default: 180s / 3 min)
- **Max Size:** `cacheSizeLimit` (default: 1000)
- **Refresh Threshold:** `whoCacheRefreshThreshold` (default: 50%)

**Negative Caching (CRITICAL FIX):**
When a WHO query completes and the player is **not found**, the result is cached as `found=false`. This prevents repeated WHO queries for the same player.

**Before Fix:** Each check for an offline player triggered a new WHO query.
**After Fix:** Offline players are cached for 3 minutes, eliminating redundant queries.

**Example:**
```lua
-- Player not found in WHO results
CI:Set("whoName", playerName, {
    found = false,
    zone = currentZone,
    timestamp = now,
    mapID = nil
})
```

---

### 4. WHO Zone Cache
**Purpose:** Cache zone-wide WHO query results (all players in zone)

**Key:** Player name (sanitized)

**Value Structure:**
```lua
{
    timestamp = number,
    found = boolean,
    zone = string,
    mapID = number
}
```

**Configuration:**
- **TTL:** `whoZoneCacheDuration` (default: 180s / 3 min)
- **Max Size:** `cacheSizeLimit` (default: 1000)

---

### 5. Map Scan Cache
**Purpose:** Cache map scanning results (TRP3 protocol)

**Key:** Player name (sanitized)

**Value Structure:**
```lua
{
    timestamp = number,
    found = boolean,           -- Found on map | Not found
    mapID = number,            -- Map ID at time of scan
    verified = boolean         -- Nonce matched (true) or not (false)
}
```

**Configuration:**
- **TTL (found):** `scanCacheDuration` (default: 120s / 2 min)
- **TTL (not found):** `scanCacheFailureDuration` (default: 10s)
- **Max Size:** 1000

---

### 6. Broadcast Cache
**Purpose:** Cache recent map broadcast events (passive detection)

**Key:** Player name (sanitized)

**Value Structure:**
```lua
{
    timestamp = number,
    mapID = number,
    verified = boolean
}
```

**Configuration:**
- **TTL:** `scanCacheDuration` (default: 120s)
- **Max Size:** 1000

---

### 7. Allowed Senders Cache
**Purpose:** Cache players who passed location checks (bypass future checks)

**Key:** Player name (sanitized)

**Value Structure:**
```lua
{
    timestamp = number,
    reason = string  -- "location_ok" | "manual" | "whitelist"
}
```

**Configuration:**
- **TTL:** `sendCacheDuration` (default: 600s / 10 min)
- **Max Size:** 1000
- **Refresh Rate:** `sendCacheRefreshRate` (default: 10% = 60s threshold)

---

### 8. SPVP Verified Cache (New)
**Purpose:** Cache successful cryptographic phase verifications

**Key:** Player name (sanitized)

**Value Structure:**
```lua
{
    timestamp = number,
    verified = true,
    sessionID = string
}
```

**Configuration:**
- **TTL:** 300s (5 min)
- **Max Size:** 1000

---

### 9. SPVP Phase Salt Cache (New)
**Purpose:** Cache Epsilon Phase Addon Data (Security Keys)

**Key:** Phase ID (number)

**Value Structure (Positive):**
```lua
{
    salt = string,      -- The 64-char hex key
    timestamp = number
}
```

**Value Structure (Negative):**
```lua
{
    noSalt = true,      -- Explicit marker for unsecured phases
    timestamp = number
}
```

**Configuration:**
- **TTL (Positive):** `spvpSaltCacheDuration` (default: 10800s / 3 hours)
- **TTL (Negative):** 3600s (1 hour)
- **Max Size:** 500 phases

---

## Performance Optimizations

### Monotonic Time Caching
`TRP3FW:GetCurrentTime()` caches the result of `GetTime()` per frame to avoid redundant system calls (saves ~95 calls per complex request).

### Negative Caching
To prevent API spamming in unsecured phases, "No Salt found" results are cached for **1 hour**. The system will not attempt to fetch the key again during this window unless a manual forced refresh occurs (e.g., handshake failure).

### Cross-Population
Successful Targeting checks (Phase Cache) automatically populate the WHO Name Cache, eliminating redundant zone queries.
