# Location Detection Systems

Complete reference for phase checking, WHO queries, map scanning, and cascading logic.

## Overview

TRP3FW uses three complementary location detection methods to determine if a player is "nearby":

1. **Phase Detection** (Epsilon only) - Same phase check (Targeting + **SPVP**)
2. **WHO Queries** (Epsilon only) - Zone-based detection
3. **Map Scanning** (All servers) - TRP3 protocol broadcasts

These run in a **sequential cascading system** with intelligent fallbacks and cryptographic verification.

## Cascading Logic Flow

```
CheckLocationCascading(playerName, sendId, callback, options)
    ↓
Check if blockStartPhase enabled AND Phase == 169 → FAIL FAST
    ↓
Check interaction cache → ALLOW FAST (Success)
    ↓
Start Phase Check (if enabled)
    ↓
    [Execution Mode: Sequential]
    ↓
    1. SPVP Handshake (if enabled)
        ├─ Success: Phase verified. Proceed to Targeting Check (Nearness).
        └─ Failure/Timeout: Fallback to Standard Checks (if mode != Required).
    ↓
    2. Targeting Check (Standard or SPVP-Success Validation)
        ├─ Success (Target found/Nameplate): Nearness confirmed. 
        │  → SKIP Map Check.
        │  → ALLOW (Success).
        └─ Failure: Out of phase or out of targeting range.
           → Proceed to Map Check.
    ↓
Start Map Check (if enabled)
    ↓
    Epsilon + useWhoQuery? → WHO query
        ├─ Result: Found in zone → Compare maps (Match = Success)
        └─ Result: Not found → Block/Alert (Reliable Failure)
    ↓
    Otherwise → Map scan
        ├─ Result: Found on map → ALLOW (Success)
        └─ Result: No reply → Block/Alert (Reliable Failure)
    ↓
Evaluate Results
    ↓
Combine results → Final locationOK + alertType
    ↓
[Optimization: Early Success]
In parallel/optional mode, return Success if Phase(Target) + Map pass, 
even if SPVP is still pending.
    ↓
callback(locationOK, alertType, source, ...)
```

## Phase Detection

### Methods

#### 1. SPVP (Secure Phase Verification Protocol)
Cryptographic handshake to verify phase presence.
- **Success:** Phase is valid. Triggers explicit **Targeting Check** to validate physical nearness (Map).
- **Failure:** Fallback to standard methods or Block (depending on mode).
- **Optimization:** Results cached for 5 minutes. Handshake bypassed on cache hit.

#### 2. Group Check (Optional Bypass)
Enabled via `allowGroupPhaseBypass` (Default: OFF).
- **Logic:** Party/Raid members instantly pass the phase check.
- **Risk:** High. Group members are often in different phases or maps.

#### 3. Nameplate Check (Instant)
Checks visible nameplates for the target. Confirms physical proximity.

#### 4. Targeting Check (Authoritative)
The gold standard for nearness.
- **Standard:** `TargetUnit(name)`.
- **Optimization:** Batch processing (up to 8 targets per token refill).
- **Effect:** If Targeting succeeds, the subsequent Map Check is **skipped** entirely.

### Phase Check Cache
- **TTL:** 300s (5 minutes).
- **Refresh:** Background refresh at 50% age (150s).
- **Failure TTL:** 10s (Allows quick retry on transient fails).

---

## WHO Queries

### Purpose
Query players in current zone via Epsilon API. Faster and more reliable than map scanning.

### Epsilon-Specific Implementation

WHO queries use the **Epsilon privileged API** (`C_Epsilon.RunPrivileged`) because standard WHO functions are protected in WoW 9.2.5+:

```lua
local privilegedCode = 'C_FriendList.SetWhoToUi(false); C_FriendList.SendWho([[z-"ZoneName"]])'
local success, err = TRP3FW:RunPrivilegedSafe(privilegedCode, "who_zone_query")
```

**Important Fixes:**
- **Semicolon separator required** between statements in privileged code
- **WHO_LIST_UPDATE event doesn't fire** on Epsilon 9.2.5 - uses 0.5s fallback check
- **CHAT_MSG_SYSTEM backup detection** for query completion

### Zone Detection Priority (Epsilon Custom Maps)

Epsilon allows custom map renaming. The system now prioritizes actual zone text over map info:

1. **`GetRealZoneText()`** - Most reliable (returns custom Epsilon zone names)
2. **`GetZoneText()`** - Fallback to main zone
3. **`GetMinimapZoneText()`** - Fallback to minimap
4. **`C_Map.GetMapInfo(mapID).name`** - Last resort (returns default Blizzard name)

**Critical:** Using map info first caused WHO queries to search for wrong zone (e.g., "Infinite Flatlands" instead of custom name), returning zero results.

### Two-Tier Caching
1. **WHO Zone Cache:** Zone metadata + all players in zone (3 min TTL).
2. **WHO Name Cache:** Specific player results including negatives (3 min TTL).

**Negative Caching:** Players not found in WHO queries are cached as `found=false` to prevent repeated queries.

### WHO_LIST_UPDATE Event Workaround

On Epsilon WoW 9.2.5, the `WHO_LIST_UPDATE` event does not fire reliably after privileged WHO calls.

**Fallback Mechanism:**
- After 0.5s, manually check `C_FriendList.GetNumWhoResults()`
- If results available but event didn't fire, manually trigger processing
- Diagnostic message: `"WHO results available (X) but WHO_LIST_UPDATE hasn't fired yet!"`

**Backup Detection:**
- Monitor `CHAT_MSG_SYSTEM` for WHO result messages
- Pattern match: "X |4player:players; total"
- Trigger processing after 0.1s delay

### Optimization: Cross-Population
Successful **Targeting** or **Nameplate** checks immediately populate the WHO Name Cache for that player (since nearness implies zone presence). This saves an API call if the logic cascades.

---

## Map Scanning

### Purpose
Broadcast TRP3 protocol message to detect players on current map. Works on all servers.

### Prerequisites
Map scanning requires a valid map ID to function:
- **Guard Clause:** If `GetCurrentMapID()` returns `nil`, the scan is skipped entirely
- **Common scenarios:** Instances, protected areas, loading screens, zone transitions
- **Callback Result:** Returns `false, "no_mapid"` when map ID unavailable
- **Impact:** Prevents wasted network traffic and potential errors in unmapped areas

### Sequential Gating
Map scanning is now the **last resort**. It is only triggered if:
1. Phase Check failed or wasn't authoritative (e.g., cached without nearness).
2. WHO Queries are unavailable or failed to find the player.
3. No recent Passive Broadcast has been received from the target.
4. **A valid map ID is available** (see Prerequisites above).

---

## Optimizations

### 1. Early Fast-Path (Fail Fast / Success Fast)
Before allocating result tables or closures, the system checks:
- **Phase 169:** Fails immediately if blocking is on.
- **Interaction Cache:** Succeeds immediately if the user recently interacted with the target.

### 2. Sequential Serialization
Checks are no longer purely parallel. Map checks are deferred until Phase Check results are known. If Phase Check proves nearness (via Targeting), the Map Check is **cancelled** to save network traffic and prevent conflicting "Map: Timeout" alerts.

### 3. Early Success (Parallel SPVP)
In `optional` mode, if Standard checks pass quickly (Target found), the system returns **Success immediately**. It does not wait for the SPVP handshake/timeout to complete, providing zero-latency exchanges for nearby friends.

### 4. Fallback Priority
If SPVP times out in `preferred` mode, the subsequent standard checks are automatically elevated to **HIGH priority** to recover the lost time.

### 5. Negative Salt Caching
Phases without a security key (Unsecured) are cached for **1 hour**. This prevents the system from repeatedly hitting the Epsilon API during handshakes in unsecured phases.

---

## Evaluation Logic

### Reliable vs Unreliable Failures
The system distinguishes between definitive "They are not here" and transient "Check failed."

**Reliable (Blocks Traffic):**
- `zone_mismatch` (WHO found them elsewhere).
- `map_scan_no_reply` (Timed out).
- `phase_fail` (Targeting failed).

**Unreliable (Ignored if Phase Verified):**
- `who_timeout` (Server lag).
- `who_backoff` (Rate limiting).
- `spvp_timeout` (Slow client).

**Strict Map Blocking:** If map checks fail reliably (Different Map), the request is **BLOCKED** even if SPVP verified the phase (prevents "phase sniping" from the same phase but remote locations).