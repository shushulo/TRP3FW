# Location System Optimizations

## Overview
This specification outlines optimizations for the TRP3FW location detection system (`who.lua`, `cascading.lua`, `maps.lua`). These changes are designed to improve performance in high-population "Hub" zones (like Infinite Flatlands) and reduce unnecessary network traffic.

## 1. Hub Memory (Extended Truncation Window)

### The Problem
Currently, `WHO_ZONE_LIMIT_WINDOW` resets every 15 seconds. In permanently populated zones (Infinite Flatlands), this causes the system to repeatedly "rediscover" that the zone is full, wasting one `whozone` API call shortly after the short window expires.

### The Fix
Extend the memory of a truncated zone from 15 seconds to **60 seconds**.

### Implementation Details
- **File:** `location/who.lua`
- **Logic:** 
    - Change `WHO_ZONE_LIMIT_WINDOW` constant from `15` to `60`.
    - This ensures that once a zone is found to be full, we default to efficient `whoname` queries for a full minute before re-checking the zone list.

---

## 2. Trusting WHO ("Definitive Not Found")

### The Problem
When `whoname` returns `found=false` (a definitive server-side response), the system often falls back to a Map Scan "just in case." This generates unnecessary add-on communication traffic when the server has already confirmed the player doesn't exist or is offline.

### The Fix
Treat an explicit `whoname` failure (not timeout/error) as authoritative.

### Implementation Details
- **File:** `location/who.lua` (Callback logic) and `location/cascading.lua` (Fallback logic)
- **Logic:**
    - In `CheckPlayerViaWho`, distinguish between `who_not_found` (authoritative) and `timeout`/`error` (unreliable).
    - In `CheckLocationCascading`, if the result is `who_not_found`, **skip** the `MapScan` entirely.
    - **Exception:** Keep Map Scan fallback if the failure reason is `timeout`, `rate_limit`, or `unavailable`.

---

## 3. Map ID Reliability (Nil ID Safety)

### The Problem
`GetCurrentMapID()` can return `nil` on custom maps, instances, or during transitions. Currently, the system might try to fallback or handle this ambiguously.

### The Fix
Enforce strict Map ID requirements for **Map Scans**, but allow **WHO Queries** to proceed based on Zone Name alone.
- **Map Scans:** If `GetCurrentMapID()` returns `nil`, **ABORT** the map scan immediately. Map scanning relies on broadcasting a specific Map ID to peers; without it, the protocol is unreliable and spammy.
- **WHO Queries:** Continue to allow `whozone` and `whoname` if `GetRealZoneText()` is valid, even if Map ID is `nil`.
    - Note: `whozone` might return truncated results (50 limit), but it's still worth running once. The existing "Hub Memory" (Section 1) will handle the truncation fallout.

### Implementation Details
- **File:** `location/maps.lua`
- **Logic:**
    - Ensure `MapScan` has a hard guard clause: `if not mapID then return false end`. (This exists but ensure no "fallback" bypasses it).
- **File:** `location/who.lua`
- **Logic:**
    - Ensure `CheckPlayerViaWho` uses `GetRealZoneText()` if Map ID lookup fails to resolve a zone name.

---

## Implementation Checklist (TODO)

- [ ] **1. Hub Memory** (`location/who.lua`)
    - [ ] Change `WHO_ZONE_LIMIT_WINDOW` constant to `60`.

- [ ] **2. Trusting WHO** (`location/cascading.lua`)
    - [ ] Update `startStandardChecks` to inspect failure reason from WHO.
    - [ ] If `source == "who_not_found"`, skip Map Scan.

- [ ] **3. Map ID Reliability** (`location/maps.lua`)
    - [ ] Verify `MapScan` strictly blocks on nil mapID (no changes needed if already strict, just verification).