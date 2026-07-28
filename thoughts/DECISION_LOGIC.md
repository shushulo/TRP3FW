# Decision Logic Reference

Complete reference for the decision pipeline, stages, and allow/block/ghost logic.

## Overview

TRP3FW uses a **7-stage pipeline architecture** to decide whether to allow, block, or ghost profile sends. Each stage can either:
- **Handle** the request (return `{handled = true}`) - stops pipeline
- **Pass** the request to next stage (return `{handled = false}`)

> **Note:** Phase-in delay is handled in the Chomp hook ([trp3_chomp_pipeline.lua](../hooks/trp3_chomp_pipeline.lua)) BEFORE the decision pipeline runs, not as a stage. This means MSP-only / non-Chomp send paths bypass the phase-in delay by design.

## Decision Pipeline Flow

```
CheckLocationAndNotify()
    ↓
Create Context (snapshot time, settings, parameters)
    ↓
DecisionPipeline:Run(context)
    ↓
Stage 1: WhitelistStage          → Allow if whitelisted
    ↓ (not handled)
Stage 2: SPVPStage               → Mark for parallel SPVP verification
    ↓ (not handled)
Stage 3: CacheStage              → Allow if cached as safe
    ↓ (not handled)
Stage 4: InteractionStage        → Allow if recently interacted
    ↓ (not handled)
Stage 5: AlertFastPathStage      → Allow immediately if blocking disabled
    ↓ (not handled)
Stage 6: BurstStage              → Queue if check already in progress
    ↓ (not handled)
Stage 7: LocationStage           → Run async location checks (with SPVP if enabled)
    ↓
CheckLocationCascading()
    ├─ Early-Fail: Block if Start Phase 169
    ├─ Early-Success: Interaction Cache
    └─ Standard Flow: Phase → Map
    ↓
ProcessLocationDecision()
    ↓
ApplyLocationDecision()
```

## Entry Point

### TRP3FW:CheckLocationAndNotify()
```lua
function CheckLocationAndNotify(playerName, addon, isWhisper, sendId, originalFunc, originalArgs)
```

**Parameters:**
- `playerName` - Target player name (sanitized)
- `addon` - Source addon ("TRP3", "MRP", "XRP", "MSP")
- `isWhisper` - Direct request (true) or broadcast (false)
- `sendId` - Unique send ID for deduplication
- `originalFunc` - Original send function to call if allowed
- `originalArgs` - Original arguments to pass

**Returns:** `boolean` - Allow (true) or Block (false)

## Pipeline Stages

### Stage 2: SPVPStage
Marks the context for Secure Phase Verification Protocol (SPVP).
- **Hard Exclusion:** Never in Phase 169 (Start Phase).
- **Pre-flight Check:** Verifies Epsilon API and presence of Phase Salt.
- **Action:** Does NOT block; simply prepares SPVP metadata for Stage 7 (LocationStage).

---

### Stage 7: LocationStage (Optimized)
Runs the `CheckLocationCascading` logic with the following enhancements:

#### 1. Early-Fail: Start Phase Protection
If `blockStartPhase` is enabled and current phase is 169, the check fails instantly before any closure allocation.

#### 2. Early-Success: Interaction Cache
If target is in Interaction Cache (recent mouseover/target), the check succeeds instantly.

#### 3. Sequential Cascading
Standard checks are now serialized:
- **Phase Check** runs first.
- **Targeting/Nameplate Success** → Nearness confirmed. **Skip Map Check**.
- **Phase Fail/Weak Result** → Trigger **Map Check** (WHO/Scan) as fallback.

#### 4. SPVP Early-Success
In `optional` (parallel) mode, if standard checks pass (Phase:Target + Map:Match) while SPVP is still handshaking, the check returns **Success immediately**. Users no longer wait for slow SPVP handshakes if nearness is already proven.

#### 5. Fallback Priority
If SPVP times out in `preferred` mode, standard checks are automatically elevated to **HIGH priority** to minimize the impact of the delay.

---

## Location Decision Processing

### ProcessLocationDecision()
Determines the final outcome based on the cascade results.

**Combined Result Rules:**
- **SPVP Verified + No Reliable Map Fail:** Allow.
- **Targeting Pass:** Allow (Implicit Map Match).
- **Map Fail (Reliable):** Block (Even if SPVP verified - prevents remote sniping).
- **Reliable Failure Sources:** `zone_mismatch`, `map_id_mismatch`, `map_scan_no_reply`, `who_not_found`.
- **Unreliable Failure Sources:** `who_timeout`, `who_backoff`, `spvp_timeout`.

---

## Apply Location Decision

### ApplyLocationDecision()
Executes the allow/block/ghost decision and dispatches notifications.

- **Allow:** Records interaction, updates allowedSenders cache, calls original function.
- **Block:** Records history, suppresses original function.
- **Ghost:** Sets ghost flag, calls original function (interceptor will swap payload).

---

## Performance Optimizations

1. **Closure Minimization:** Moved heavy logic to top-level helpers where possible.
2. **Context Snapshots:** Prevents TOCTOU race conditions.
3. **Negative Caching:** Missing phase salts cached for 1 hour to prevent API spam.
4. **Frame-based Time:** Monotonic clock reduces syscall overhead.
5. **Deduplication:** `sendId` tracking and `BurstStage` prevent redundant parallel checks.

---

## Implementation Notes

### Cascading completion tracking (`location/cascading.lua`)

`CheckLocationCascading` tracks evaluation progress with two sets on the `results`
table rather than counters:

- `results.expected = { phase=true, map=true, spvp=true }` — which check kinds
  will report. Initialized from enabled-check flags. SPVP `preferred`/`required`
  modes initially expect *only* `spvp`, then `OnSPVPResult` re-expands `expected`
  with `phase`/`map` if standard checks must follow.
- `results.done = { ... }` — kinds that have reported in. Set via `MarkComplete(results, kind)`.
- `IsComplete(results)` — true iff every key in `expected` is in `done`. Used by
  the Early-Success gate and the deadline handler.

This replaces fragile `checksComplete < checksExpected` counter math that could
desynchronize across `OnSPVPResult` / `HandlePhaseResult` / `HandleMapResult`.

### Burst staleness snapshots

`LocationStage` records three snapshots when starting a check, against which
`BurstStage`-queued requests are validated before replay:

- `zoneSnapshot = TRP3FW.lastZoneChangeTime`
- `phaseSnapshot = TRP3FW.lastPhaseChangeTime`
- `settingsFingerprint = TRP3FW:GetBurstSettingsFingerprint()`

`IsBurstRequestStale(req)` rejects queued requests if any snapshot drifts during
the in-flight check. Plus a 2.0s age cap as an unconditional ceiling.

### Per-request `locationResult` cloning

When the cascading callback fires, queued burst requests share the original
decision but each gets its own `CloneLocationResult(locationResult)` (shallow
copy of the result + nested `cacheInfo`/`checkDetails`). This prevents
per-request notification-text mutations from leaking across burst siblings.

### `isUserInitiated` inheritance

`BuildQueuedContext` copies `isUserInitiated` from the *original* burst context
rather than re-evaluating `IsUserInitiatedExchange` for each queued request.
The `userInitiatedQueries` TTL is 5 seconds — re-evaluating mid-burst would
flip the flag false on requests that are part of the same exchange.

---
**Last Updated:** 2026-04-28
**Version:** 2.7