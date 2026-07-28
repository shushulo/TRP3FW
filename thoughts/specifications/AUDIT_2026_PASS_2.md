# TRP3FW Audit Pass 2 — Bugs & Gaps Specification

**Date:** 2026-04-29
**Reviewer:** Second-pass audit over `core/`, `features/`, `location/`, `hooks/`, `ui/`, services, and pipeline stages.
**Scope:** Defects discovered *after* the Pass 1 audit (`AUDIT_2026_BUGS_AND_GAPS.md`) was applied. Focuses on items that affect correctness, observability, or user-visible behavior. Does not re-list Pass 1 findings.

Each finding is structured as:

> **ID — Title** (Severity)
> **Where:** files / lines
> **What's wrong:** observed behavior / code
> **Impact:** what breaks
> **Proposed fix:** minimal change

Severity legend:
- **Critical** — Silent correctness failure, stat inflation, or stops core feature from working
- **High** — Wrong behavior in common paths, but partially mitigated by other code
- **Medium** — Edge case, latent bug, or cleanup with concrete user impact
- **Low** — Hygiene, dead code, minor inconsistency

---

## CRITICAL findings

### N1 — Alert / block / ghost stats are double-counted (Critical)

**Where:** [features/decision.lua:450-474](../../features/decision.lua), [features/services/HistoryService.lua:261-266](../../features/services/HistoryService.lua)

**What's wrong:** `ApplyLocationDecision` calls `self:RecordHistory(...)` which delegates to `HistoryService:RecordHistory`, and that method already does:

```lua
if wasAlert  then self.sessionStats.alerts     = self.sessionStats.alerts + 1 end
if wasBlocked then self.sessionStats.blocks    = self.sessionStats.blocks + 1 end
if wasGhost   then self.sessionStats.ghostSends = self.sessionStats.ghostSends + 1 end
if alertType == "phase" then self.sessionStats.phaseAlerts = self.sessionStats.phaseAlerts + 1
elseif alertType == "map" then self.sessionStats.mapAlerts  = self.sessionStats.mapAlerts + 1 end
```

Immediately after, `decision.lua` does it *again* via `historyService:IncrementStat("alerts")`, `IncrementStat("blocks")`, `IncrementStat("ghostSends")`, `IncrementStat("phaseAlerts")` (using `:find`), `IncrementStat("mapAlerts")`, `IncrementStat("startPhaseBlocks")`.

The two paths use different match logic for `alertType` (`==` vs `:find`), so the inflation factor varies — `alertType = "phase+map"` is doubled in `decision.lua` but not in `RecordHistory`, while `alertType = "phase"` is doubled in both.

**Impact:** Status panel and history-tab counters are wrong (typically 2x for alerts/blocks/ghosts; 1.5–2x for phaseAlerts/mapAlerts depending on alertType shape). User-facing stats lie about activity.

**Proposed fix:** Centralize on `RecordHistory`. In `decision.lua`:
- Remove the entire `historyService:IncrementStat(...)` block at lines 453–475.
- Add `startPhaseBlocks` and combined alertType (`phase+map`) handling to `HistoryService:RecordHistory`:

```lua
-- features/services/HistoryService.lua RecordHistory
if alertType == "start_phase_block" then
    self.sessionStats.startPhaseBlocks = self.sessionStats.startPhaseBlocks + 1
end
if alertType then
    if alertType:find("phase") then self.sessionStats.phaseAlerts = self.sessionStats.phaseAlerts + 1 end
    if alertType:find("map")   then self.sessionStats.mapAlerts   = self.sessionStats.mapAlerts + 1 end
end
```

Replace the existing `==` branches with the `:find` branches (a `phase+map` alert should bump both counters).

---

### N2 — `LocationStage` never sets `priority = "HIGH"`, so the cascading deadline never arms for the main pipeline (Critical)

**Where:** [features/stages/LocationStage.lua:110-114](../../features/stages/LocationStage.lua), [location/cascading.lua:412-440](../../location/cascading.lua)

**What's wrong:** The 2.0s deadline timer, the 0.2s phase fast-fallback, and the 0.3s WHO fast-fallback in `cascading.lua` only run when `options.priority == "HIGH"`. `LocationStage` builds `options` with only `spvpEnabled / spvpPhaseID / spvpSalt`. The only call site that sets `HIGH` is `hooks/trp3_scan_pipeline.lua:169`.

For all Chomp/MSP-routed sends, if a phase check or WHO query hangs (Epsilon API stall, no targeting opportunity, server lag), `EvaluateResults` is never called — the cascading callback never fires — and the only thing rescuing the pending state is `LocationStage`'s 30s housekeeping `C_Timer.After`, which simply nils `pendingSends[sendId]` and `pendingLocationChecks[player]`.

**Impact:**
- `context.originalFunc` is never invoked for the original request (silent send failure).
- Queued burst siblings sitting in `pendingLocationChecks[player].queuedRequests` are silently abandoned (`ProcessLocationDecision` is never called for them, so `BuildQueuedContext` / `ApplyLocationDecision` never run).
- User sees nothing — no allow, no block, no alert. The send just disappeared.
- `pendingChompSends[player]` may still be populated, leaking into N8.

**Proposed fix:** Make the 2.0s deadline unconditional — it is a correctness rail, not an optimization. Keep the 0.2s/0.3s fast-fallbacks gated on HIGH priority (those *are* optimizations specific to scan-reply latency budgets).

Concrete change in [cascading.lua:412](../../location/cascading.lua):

```lua
-- Before
if options.priority == "HIGH" then
    local deadlineTimer = C_Timer.NewTimer(2.0, function() ... end)
    ...
end

-- After
local deadlineTimer = C_Timer.NewTimer(2.0, function() ... end)
local originalCallback = results.callback
results.callback = function(...)
    if deadlineTimer then deadlineTimer:Cancel() deadlineTimer = nil end
    originalCallback(...)
end
```

Leave the priority-gated 0.2s/0.3s blocks alone.

---

**Followup — N2b (Critical, surfaced 2026-04-29 during in-game testing):**

Phase 3's N2 fix made the deadline unconditional but introduced a regression: legitimate sends from random players started getting falsely BLOCKED with `[checks: phase=fail (timeout), map=fail (timeout)]` reasons, with no actual phase/map check activity in the log preceding the deadline.

Repro from a live debug log (Squirtsage, Morely, Dirana, Velranh, Zayura, Dizzee, Orléon — all consecutive false blocks):

```
13:31:04  CheckLocationAndNotify START for Squirtsage
13:31:04  Phase salt NEGATIVE cache hit for phase 76209
13:31:04  SPVP pending: Phase salt loading...
13:31:04  Phase salt NEGATIVE cache hit (x2)
13:31:04  SPVP INIT sent to Squirtsage
13:31:04  Pipeline 'DecisionPipeline' handled by stage 'Location'
            ← no `CheckPlayerPhase called`, no `[Phase Queue] Enqueued`, no `MapScan`
13:31:06  [Deadline] Forcing location evaluation (2.0s reached)
13:31:06  [BLOCKED] Your profile was blocked for Squirtsage [checks: phase=fail (timeout), map=fail (timeout)]
```

Compare to a working request (Bellydancer, earlier in the same session) which showed `CheckPlayerPhase called for: Bellydancer` followed by `[Phase Queue] Enqueued`. The broken cases never fired any phase or map check at all — the deadline force-failed `phaseCheck` and `mapCheck` to `false` even though the checks had not been initiated, and EvaluateResults then synthesized a definitive BLOCK from those phantom failures.

**Two interacting bugs were responsible:**

1. **Late SPVP resolution treated `nil` salt as "salt present"** at [cascading.lua:407](../../location/cascading.lua):

   ```lua
   if currentPhaseID and currentPhaseID ~= 169 and self:GetPhaseSalt(currentPhaseID) ~= "" then
       spvpEnabled = true
   end
   ```

   `GetPhaseSalt` returns `nil` on negative cache hit (no salt configured for this phase). `nil ~= ""` is true, so `spvpEnabled` was wrongly set to true for every send in a no-salt phase. SPVP INIT was then fired into the void; `expected.spvp = true` was added to the result tracker; the SPVP handshake timed out at the standard 5s but the cascading deadline at 2s force-completed everything first.

2. **Deadline force-failed checks that never started** at [cascading.lua:440-449](../../location/cascading.lua):

   ```lua
   if results.phaseCheck == nil then
       results.phaseCheck = false
       results.phaseSource = "deadline_timeout"
       ...
   end
   ```

   The unconditional `== nil` check meant any pending state — including "this check was never initiated" — got force-failed to `false`. EvaluateResults then treated `phaseCheck == false` as a definitive "not in phase" verdict and added `"phase"` to alertTypes, which under any block-mode setting produced a hard BLOCK.

   This is the exact failure mode N3 (resolved-flag guard) was supposed to prevent late results from triggering, but the deadline ran *before* any result arrived, not after — so the guard didn't apply.

**Why these compounded:** Bug 1 added `spvp` to `expected` for sends that didn't need SPVP. Bug 2 then force-failed phase + map at the deadline because `expected.spvp` kept `IsComplete()` returning false until forced. The combination converted "we're waiting on SPVP" into "phase and map definitively failed".

**Fixes applied:**

1. Late SPVP resolution at [cascading.lua:405-415](../../location/cascading.lua) now requires non-nil and non-empty salt:

   ```lua
   if currentPhaseID and currentPhaseID ~= 169 then
       local salt = self:GetPhaseSalt(currentPhaseID)
       if salt and salt ~= "" then
           spvpEnabled = true
       end
   end
   ```

2. Deadline at [cascading.lua:436-466](../../location/cascading.lua) only force-fails checks that actually started:

   ```lua
   if results.phaseCheck == nil and results.phaseCheckStarted then
       results.phaseCheck = false
       ...
   end
   if results.mapCheck == nil and results.mapCheckStarted then
       results.mapCheck = false
       ...
   end
   ```

   Checks that never started stay `nil`. EvaluateResults reads `nil` as `phase_unknown`/`map_unknown`, which alerts (and only blocks under modes that explicitly block on unknown). A request that legitimately can't be verified now fails open or alert-only rather than blocking with false certainty.

**Lessons for future deadline-timer code:**

- Deadlines must distinguish "in-flight but slow" from "never started". Force-failing the latter creates phantom failures.
- A boolean `false` in a check-result field is a strong claim ("definitely not in phase"). Use `nil` for "unknown" and reserve `false` for confirmed negative results.
- Late-resolution code that opportunistically enables a feature (like SPVP) needs to handle every possible return value of its enable-condition function, not just the obvious ones. `nil`, `""`, and `"some_salt"` are three distinct cases with three distinct meanings.



---

### N3 — `EvaluateResults` early-success path leaves SPVP work running and outstanding callback handlers crashable (Critical)

**Where:** [location/cascading.lua:71-89](../../location/cascading.lua), [location/cascading.lua:305-345](../../location/cascading.lua)

**What's wrong:** When the `mapVerified and phaseVerified and (isStrongPhase or isStrongMap) and spvpMode ~= "required"` branch fires, the code falls through and calls `results.callback` and clears it. But if `expected.spvp = true` was set (SPVP enabled, optional/preferred mode), the SPVP handshake is still in flight. When it completes, `OnSPVPResult` runs unconditionally and may:
- Mutate `results.phaseCheck`, `results.phaseSource`, `results.phaseMethod` (line 316).
- Call `TRP3FW:CheckPlayerPhase` for "map verification" (line 323), which seizes the player's target frame for batch/individual targeting.
- Call `StartStandardChecks(results, "HIGH")` on the failed-preferred branch (line 342), which re-fires phase and map checks.

Even though `results.callback` is now `nil` (so `EvaluateResults` won't double-deliver), the side effects already happened: the user briefly sees their target frame flicker to a stranger, after the request was already allowed and they've moved on.

**Impact:** Visible target-frame flicker, wasted phase/WHO queries on already-resolved requests, and noise in `phaseCheckTargeting` state that can interfere with concurrent unrelated checks.

**Proposed fix:** Add a `results.resolved = true` flag set whenever `results.callback` is consumed, and gate the side-effecting branches in `OnSPVPResult` on it:

```lua
-- In EvaluateResults, just before invoking callback:
results.resolved = true

-- In OnSPVPResult:
function OnSPVPResult(results, verified, source)
    if results.resolved then
        TRP3FW:Debug("[SPVP] Late result for "..results.playerName.." discarded (already resolved)", "spvp")
        return
    end
    ...
end
```

Same guard at the top of `HandlePhaseResult` and `HandleMapResult` for symmetry — late results from any source should be discarded once the request is resolved.

---

### N4 — `CacheStage` increments a non-existent `cacheStats.spvpCacheHits` key (Critical, observability)

**Where:** [features/stages/CacheStage.lua:108](../../features/stages/CacheStage.lua), [features/services/HistoryService.lua:21-40](../../features/services/HistoryService.lua)

**What's wrong:** `cacheStats` defines `spvpVerifiedCacheHits` / `spvpVerifiedCacheMisses`. The CacheStage SPVP-verified-cache-hit path increments `spvpCacheHits`. `IncrementStat` silently no-ops because the key does not exist:

```lua
-- HistoryService:IncrementStat
if self.sessionStats[category] and self.sessionStats[category][subcategory] ~= nil then
    self.sessionStats[category][subcategory] = ...  -- never reached
end
```

**Impact:** SPVP cache hit-rate displays are stuck at 0. Also, no code increments `spvpVerifiedCacheMisses` anywhere — even if N4 is fixed, the miss counter remains at 0.

**Proposed fix:**
1. In `CacheStage.lua:108`, change `"spvpCacheHits"` → `"spvpVerifiedCacheHits"`.
2. Add a corresponding miss increment when SPVP cache lookup returns nil — either in `CacheStage` (after the `if spvpEntry and spvpEntry.verified then` block, in an `else` branch on the lookup) or inside the SPVP check path in `cascading.lua`.

---

### N5 — `CacheStage` reads a phantom second return value from `CI:Get` and the "different phase" branch is empty (Critical, dead-code-with-impact)

**Where:** [features/stages/CacheStage.lua:15-57](../../features/stages/CacheStage.lua)

**What's wrong:**

```lua
local phaseResult, reason = CI:Get("phaseCheck", context.playerName)
```

`CacheInterface:Get` returns one value. `reason` is always `nil`. More importantly, the `else` branch on line 50 is comment-only:

```lua
else
    -- Cached as DIFFERENT phase - this is a block/alert condition
    -- We can't handle it fully here because we need to run the full decision logic
    -- But we can skip the async check
    -- For now, let's return handled=false to let LocationStage handle the full check logic
    -- OR we could implement a "Fast Fail" here.
end
```

**Impact:** A cached "different phase" result is ignored. The request falls through to `LocationStage`, which runs a fresh `CheckLocationCascading`, which consults the same cached entry inside `CheckPlayerPhase` and re-derives the same answer. Wasted work on every hostile send during incoming spam — the exact case where caching matters most.

**Followup — N5b (Critical, surfaced 2026-04-29 during in-game testing):**

The fast-fail implementation initially read `phaseResult.isSamePhase` to determine the cache verdict, but the writer in [location/phase.lua:447](../../location/phase.lua) and [location/phase.lua:654](../../location/phase.lua) stores the boolean as `inPhase`. `isSamePhase` was always `nil`, so:

- **Pre-N5 behavior:** the same-phase branch never fired (cache effectively unused), the different-phase branch was a comment-only stub, requests fell through to `LocationStage` and re-checked. Wasted work but no user-visible bug.
- **Post-N5 behavior:** the different-phase branch became active fast-fail, and every cached entry — including ones cached just after a successful "IN PHASE" check — was read as different-phase and **blocked**. Users saw "Profile sent" immediately followed by "Profile blocked" for the same player on consecutive requests.

Repro case from a live debug log:
```
09:29:35  Phase check result for Bellydancer: IN PHASE     ← request 1 succeeds
09:29:35  Final decision for Bellydancer: ALLOW
09:29:35  Phase cache hit: Bellydancer is in DIFFERENT phase, fast-fail   ← request 2, 0.5s later
09:29:35  [BLOCKED] Your profile was blocked for Bellydancer
```

**Fix applied:**
- Read `phaseResult.inPhase` (matches writer schema). Gate on `~= nil` so cache entries missing the field fall through instead of being treated as different-phase.
- Removed stale `phaseResult.theirZone` read (also non-existent).
- Threaded `phaseResult.mapID` and `phaseResult.method` into the synthesized `checkDetails.phase` so block notifications carry the cached method label.

**Lesson for future cache fast-fails:** verify the cache writer's schema before reading. Pass 2 didn't include reader/writer schema reconciliation; that should be a checklist item for any new cache-consuming code path.

**Original proposed fix below remains valid:**



```lua
else
    -- Synthesize a failed locationResult and dispatch the decision stage directly.
    local locationResult = {
        locationOK = false,
        alertType = "phase",
        source = "phase_cache",
        mapCacheAge = 0,
        theirZone = "Unknown",
        myZone = TRP3FW.currentZoneName or "Unknown",
        cacheInfo = { phaseCache = "hit" },
        recentTransition = false,
        timeSinceTransition = 0,
        checkDetails = { phase = { result = false, source = "cached", method = "cached" } }
    }
    local historyService = TRP3FW.ServiceContainer:Get("HistoryService")
    if historyService then
        historyService:IncrementStat("cacheStats", "phaseCacheHits")
    end
    TRP3FW:Pipeline_DecisionStage(context, locationResult)
    return { handled = true, allowed = false, reason = "phase_cache_fail" }
end
```

Also remove the unused `reason` local on line 15.

---

## HIGH findings

### N6 — Parallel burst queues (`pendingChompSends` vs `pendingLocationChecks`) can both hold the same sendId (High)

**Where:** [features/decision.lua:236-334](../../features/decision.lua), [hooks/trp3_chomp_pipeline.lua:247-307](../../hooks/trp3_chomp_pipeline.lua), [features/stages/BurstStage.lua](../../features/stages/BurstStage.lua)

**What's wrong:** Two separate burst-detection layers exist:

1. **Hook-layer burst** (`trp3_chomp_pipeline.lua:247`): Detects requests within 2s of a prior request and queues into `pendingChompSends[player].queuedRequests` with raw Chomp args (`prefix`, `text`, `chatType`, `target`, ...). Replays via `ProcessBurstAllows` calling `q.orig(...)`.
2. **Pipeline-layer burst** (`BurstStage.lua`): Detects requests arriving while `pendingLocationChecks[player]` is set, queues into `pendingLocationChecks[player].queuedRequests` with `originalFunc`/`originalArgs`. Replays via `ApplyLocationDecision` which calls `originalFunc`.

Both queues are populated for the same player during a burst window. `ProcessBurstAllows` is called by `ApplyLocationDecision` **and** by `InteractionStage` and `AlertFastPathStage`. The pipeline-layer queue is processed by `ProcessLocationDecision`'s replay loop (line 626).

**Impact:**
- Possible duplicate sends if a request sneaks into both queues (one path replays raw args via `q.orig`, the other replays `originalFunc(unpack(originalArgs))`).
- `pendingChompSends` replay has no recursion guard equivalent to `chompState.replayingPhaseInSend` — it goes back through the Chomp hook fresh.
- N8 (below) compounds this: timeout windows differ between the two queues (30s pipeline, 30s+60s hook).

**Proposed fix:** Eliminate the hook-layer burst queue. Have the Chomp hook unconditionally call `CheckLocationAndNotify`, letting `BurstStage` handle queuing. The hook should retain only:
- Recursion guard (`sendingGhostProfile`, `replayingPhaseInSend`).
- Phase-in delay (separate concern from burst).

Remove `ChompPipeline_BurstDetection_V2` and the `pendingChompSends` table entirely. This is a multi-hour refactor — flag for a follow-up branch, not a hotfix.

**Interim mitigation (small patch):** Make `BurstStage`'s queue authoritative. Have `pendingChompSends` only track *whether* a burst is in progress (boolean), not queue replay payloads. All replays go through `ApplyLocationDecision`.

---

### N7 — `OnSPVPResult` verified-preferred branch leaves `phaseCheckStarted` unset, breaking an implicit invariant (High, latent)

**Where:** [location/cascading.lua:315-337](../../location/cascading.lua), [location/cascading.lua:272-303](../../location/cascading.lua)

**What's wrong:** When SPVP verifies in preferred/required mode:

```lua
if verified and (spvpMode == "preferred" or spvpMode == "required") then
    results.phaseCheck, results.phaseSource, results.phaseMethod = true, "spvp", "spvp"
    -- phaseCheckStarted NOT set
    ...
end
```

The invariant "phase is verified iff `phaseCheckStarted` was true or SPVP set it" relies on `StartStandardChecks` reading `results.phaseCheck ~= nil` first (line 293). If a future refactor ever swaps that order — checks `phaseCheckStarted` first — SPVP-verified requests would re-fire the phase check.

**Impact:** No live bug today. One refactor away from breaking. The implicit invariant is undocumented.

**Proposed fix:** Set the flag explicitly when SPVP overrides phase:

```lua
results.phaseCheck, results.phaseSource, results.phaseMethod = true, "spvp", "spvp"
results.phaseCheckStarted = true  -- invariant: started is true if phase was resolved by any path
```

Same in the `inPhase=true` map-verification branch (line 324) — `mapCheckStarted = true`.

---

### N8 — `LocationStage` 30s timeout doesn't clear parallel hook queues (High)

**Where:** [features/stages/LocationStage.lua:65-72](../../features/stages/LocationStage.lua), [hooks/trp3_chomp_pipeline.lua:299-303](../../hooks/trp3_chomp_pipeline.lua), [features/services/CacheService.lua:319-332](../../features/services/CacheService.lua)

**What's wrong:** `LocationStage` schedules a 30s timer that nils `pendingSends[sendId]` and `pendingLocationChecks[player]`. `pendingChompSends[player]` has its own 30s timer. The `CacheService` 60s backstop covers `pendingChompSends`.

If a location check hangs (see N2), `pendingLocationChecks[player]` is cleared at 30s but `pendingChompSends[player]` may survive until 30s on the hook timer (which started at a different time) or 60s on the backstop. A new request arriving at second 35 sees no `pendingLocationChecks` entry — fresh check starts via `LocationStage` — but `pendingChompSends[player]` may still be set, so the Chomp hook's burst detector queues into the *prior* burst's queue.

**Impact:** Mixed-burst state. Replay of the new burst can include stale entries from the abandoned old burst, or new entries replay against an old `originalFunc` reference.

**Proposed fix:** When `LocationStage`'s 30s timeout fires, also clear hook-layer queues:

```lua
C_Timer.After(30, function()
    if TRP3FW.pendingSends[context.sendId] then
        TRP3FW.pendingSends[context.sendId] = nil
        if TRP3FW.pendingLocationChecks then
            TRP3FW.pendingLocationChecks[context.playerName] = nil
        end
        if TRP3FW.pendingChompSends then
            TRP3FW.pendingChompSends[context.playerName] = nil
        end
        if TRP3FW.pendingTRP3Sends then
            TRP3FW.pendingTRP3Sends[context.playerName] = nil
        end
        if TRP3FW.pendingMSPReplies then
            TRP3FW.pendingMSPReplies[context.playerName] = nil
        end
    end
end)
```

N6's full refactor obviates this; this is the cheap interim fix.

---

### N9 — `lastPhaseChangeTime` is never initialized (High, defensive)

**Where:** [core/init.lua:560](../../core/init.lua) (where `lastZoneChangeTime` is initialized), [features/services/CacheService.lua:471](../../features/services/CacheService.lua) (only writer)

**What's wrong:** `TRP3FW.lastZoneChangeTime = 0` is initialized at addon load. `TRP3FW.lastPhaseChangeTime` has no such initialization — it stays `nil` until the first `SCENARIO_UPDATE` or `EPSILON_PHASE_CHANGE` event.

The `IsBurstRequestStale` check at [decision.lua:36](../../features/decision.lua):

```lua
if queuedReq.phaseSnapshot and self.lastPhaseChangeTime and queuedReq.phaseSnapshot ~= self.lastPhaseChangeTime then
    return true, "phase_change"
end
```

Skips the comparison entirely if either side is nil. On a fresh login before any phase event, `phaseSnapshot` captured at queue-time is `nil`, so even if a phase change happens before replay, the staleness check passes a request that should be dropped.

**Impact:** Edge case: phase change between queue and replay during the first ~minutes of session is not detected. Player crossing a phase boundary during the first burst after login could see queued requests applied to the wrong phase.

**Proposed fix:** Initialize alongside `lastZoneChangeTime` in [core/init.lua:560](../../core/init.lua):

```lua
TRP3FW.lastZoneChangeTime = 0
TRP3FW.lastPhaseChangeTime = 0  -- ADD THIS
```

Update `IsBurstRequestStale` to treat snapshot mismatch as stale even when one side was nil-then-number (which now becomes 0-then-number, naturally detected by `~=`).

---

### N10 — Validated names cleanup uses `time()` while the rest of the codebase uses `GetCurrentTime()`/`GetTime()` (High, future hazard)

**Where:** [features/services/CacheService.lua:383](../../features/services/CacheService.lua) (`local now = time()`)

**What's wrong:** `time()` returns Unix epoch seconds; `GetTime()` returns session-relative seconds. M1 from the prior audit observed there are no live writers to `TRP3FW_ValidatedNames`, so the cleanup is currently no-op anyway. But if writes are ever wired in using `GetTime()`/`GetCurrentTime()`, the cleanup will compare a 1.7e9 Unix timestamp against a small session-relative timestamp and prune everything immediately.

**Impact:** Latent — no impact today, hard-to-debug data loss the moment writes land using the wrong clock.

**Proposed fix:** Document the convention in [DATA_STRUCTURES.md](../DATA_STRUCTURES.md): persistent SavedVariables caches use `time()` (Unix epoch); session caches use `GetCurrentTime()`. Add an assertion in the cleanup if values look session-relative:

```lua
if timestamp > 0 and timestamp < 1000000000 then
    -- Looks like GetTime() not time(); skip and warn
    TRP3FW:Warn("[ValidatedNames] Entry "..name.." has session-relative timestamp; skipping prune")
end
```

---

## MEDIUM findings

### N11 — `MutualExchange_V2` Chomp pipeline stage is effectively dead, and `H4`-style dead block still present (Medium)

**Where:** [hooks/trp3_chomp_pipeline.lua:51](../../hooks/trp3_chomp_pipeline.lua), [hooks/trp3_chomp_pipeline.lua:141-166](../../hooks/trp3_chomp_pipeline.lua)

**What's wrong:**
1. Line 51 still has the `if not TRP3FW.Prefs.enabled` block from H4 in Pass 1; the body remains empty. Pass 1 listed this as an open item.
2. `ChompPipeline_MutualExchange_V2` (lines 141–166) returns `{shouldContinue=true, isMutual=...}` but no caller reads `isMutual`. The function is a documented no-op with a comment block explaining "we just return the status".

**Impact:** Reader confusion. The Chomp hook reads as if it has more stages than it actually has.

**Proposed fix:** Delete both blocks. If a master `enabled` toggle is wanted later, wire it properly in `defaultSettings`.

---

### N12 — `IsBurstRequestStale` second return value is dropped at SPVP rescue sites (Medium)

**Where:** [features/decision.lua:262](../../features/decision.lua), [features/decision.lua:575](../../features/decision.lua), [features/decision.lua:598](../../features/decision.lua)

**What's wrong:** Most call sites destructure `local stale, reason = self:IsBurstRequestStale(req)`. The two SPVP rescue paths (verified-replay and failed-replay) drop the second return:

```lua
local stale = self:IsBurstRequestStale(req)
if not stale then
    ...
end
```

When a queued request is dropped on the SPVP rescue path, no reason appears in debug logs.

**Impact:** Burst-drop debugging is harder — half the call sites log the reason, the other half don't. Cosmetic but real friction during incident analysis.

**Proposed fix:**

```lua
local stale, reason = self:IsBurstRequestStale(req)
if stale then
    self:Debug("Dropping stale SPVP-rescue queued request for "..context.playerName.." ("..tostring(reason)..")", "send")
else
    ...
end
```

---

### N13 — `AlertFastPathStage` shows a delayed "allowed" notification 1–2s after the send already completed (Medium, UX)

**Where:** [features/stages/AlertFastPathStage.lua:84-95](../../features/stages/AlertFastPathStage.lua)

**What's wrong:** The fast path immediately calls `originalFunc` and `AllowSender` without notifying. Then 1–2 seconds later the async `CheckLocationCascading` callback fires; if the result is OK and `notifyOnAllow` is true, it shows an "allowed" notification.

The user sees a "Profile sent to X" toast appearing after the send already happened and they may have moved on. Looks like a stuck or duplicate event.

**Impact:** User-hostile: notifications detached from the action that triggered them. Particularly confusing in alert-only mode (the whole point of which is to be quiet on success).

**Proposed fix:** Drop the `elseif notifyOnAllow` block. Alert-only mode should be silent on success — the user opted into "alert me only when something is wrong". If a delayed-allow notification is desired, gate it on a new explicit setting (`notifyOnDelayedAllow`, default `false`).

---

### N14 — `Service:New(name)` instances and stage instances use three different inheritance patterns (Medium, hygiene)

**Where:** [core/Service.lua:9-16](../../core/Service.lua), [features/services/HistoryService.lua:6](../../features/services/HistoryService.lua), [features/services/CacheService.lua:6](../../features/services/CacheService.lua), [features/stages/SPVPStage.lua:10](../../features/stages/SPVPStage.lua), [features/stages/LocationStage.lua:6-7](../../features/stages/LocationStage.lua)

**What's wrong:** Pass 1 H2 was filed but not addressed.
- `HistoryService`/`CacheService`: `Service:New("Name")` then attach methods directly to instance.
- `SPVPStage`: `setmetatable({}, { __index = TRP3FW.Stage })` then explicit `:New`.
- `LocationStage`: `Stage:New("Name")` followed by `LocationStage.__index = LocationStage`.

Three patterns. New contributors choose one at random.

**Impact:** Today, no live bug because each is instantiated once. Adding a second instance of any service or stage breaks unpredictably depending on which pattern the file uses.

**Proposed fix:** Pick one. The SPVPStage explicit-metatable pattern is the most defensible because it works for both single-instance and multi-instance use. Apply uniformly. Document in [SERVICES_ARCHITECTURE.md](../SERVICES_ARCHITECTURE.md) and add a brief block comment to `core/Service.lua` calling out the convention.

---

### N15 — `decision.lua` SPVP rescue path duplicates ~80 lines of queue-replay logic three times (Medium, maintainability)

**Where:** [features/decision.lua:568-605](../../features/decision.lua), [features/decision.lua:619-641](../../features/decision.lua)

**What's wrong:** The `verified` and `not verified` branches inside the SPVP rescue callback (lines 568–605) are near-identical, differing only in the args to `ApplyLocationDecision`. The no-rescue path (lines 619–641) has a third copy.

Each copy does:
1. Look up `pendingLocationChecks[player].queuedRequests`.
2. Clear the entry.
3. Iterate, check staleness, build queued context, call `ApplyLocationDecision`.

**Impact:** Three places to update when burst replay logic changes. N12 (drop reason logging) is a symptom — it was fixed in two of the three call sites, missed in the rescue paths.

**Proposed fix:** Extract:

```lua
function TRP3FW:ReplayQueuedRequests(playerName, originalContext, locationResult, shouldBlock, shouldAlert, useGhost)
    if not (self.pendingLocationChecks and self.pendingLocationChecks[playerName]) then return end
    local queuedRequests = self.pendingLocationChecks[playerName].queuedRequests
    self.pendingLocationChecks[playerName] = nil
    if not queuedRequests or #queuedRequests == 0 then return end

    for _, req in ipairs(queuedRequests) do
        local stale, reason = self:IsBurstRequestStale(req)
        if stale then
            self:Debug("Dropping stale queued request for "..playerName.." ("..tostring(reason)..")", "send")
        else
            local queuedContext = BuildQueuedContext(originalContext, req)
            self:ApplyLocationDecision(queuedContext, shouldBlock, shouldAlert, useGhost, CloneLocationResult(locationResult))
        end
    end
end
```

Replace all three call sites.

---

### N16 — `LocationStage` start-phase block path returns `async = false` but no explicit `allowed` field (Medium)

**Where:** [features/stages/LocationStage.lua:106](../../features/stages/LocationStage.lua)

**What's wrong:** Returns `{handled = true, async = false, reason = "start_phase_block"}`. The pipeline runner (and `CheckLocationAndNotify`) consult `result.allowed`. Without the field, the return value of `CheckLocationAndNotify` is `nil` for start-phase blocks.

**Impact:** Most callers ignore the return, but any code that does `if not allowed then ...` treats nil as falsy — coincidentally correct here, but the contract is undefined.

**Proposed fix:** Return `{handled = true, async = false, allowed = false, reason = "start_phase_block"}`. Audit other stages for the same pattern; the contract should be: every `handled = true` result includes an explicit `allowed` boolean.

---

## LOW findings

### N17 — UI usability spec items 1–3 status uncertain (Low, follow-through)

**Where:** [thoughts/specifications/UI_USABILITY_IMPROVEMENTS.md](UI_USABILITY_IMPROVEMENTS.md), [ui/settings.lua](../../ui/settings.lua)

**What's wrong:** The UI usability spec is "Awaiting approval before implementation" but the `ui/` directory shows seven modified files plus an untracked `ui/tabs/Security.lua`. Whether issues 1 (frame width 600→700), 2 (active tab highlight), and 3 (RefreshUI no-op while hidden) actually landed is unclear.

**Impact:** Spec drift — docs claim pending, code may have already changed.

**Proposed fix:** Verify the three issues are resolved or open. Update spec status to "Implemented" with commit refs, or leave as pending. Specifically check:
- `settingsFrame:SetSize(700, ...)` in `ui/settings.lua`.
- `OnShow` hook restoring tab highlight.
- `HookScript("OnShow", function() TRP3FW:RefreshUI() end)`.

---

### N18 — `pre_phase2_backup/` still shipped inside the addon directory (Low, hygiene)

**Where:** [pre_phase2_backup/TRP3FW/](../../pre_phase2_backup/)

**What's wrong:** Pass 1 M6 flagged this. Still present. WoW addon loader ignores it (no `.toc`), but it ships in releases, doubling on-disk footprint and creating debugging confusion when greps return matches in the backup tree.

**Impact:** ~2x disk footprint on user installs. Real-world cost: someone debugging "why isn't my fix taking effect" will eventually grep the backup copy by mistake.

**Proposed fix:** Either move outside the addon directory (cleanest) or add to `.pkgmeta` `ignore` list (CurseForge packager) so releases skip it. Git history is the actual backup.

---

### N19 — `HistoryService.Initialize` calls `TRP3FW.Service.Initialize(self)` as a function rather than a method (Low, style)

**Where:** [features/services/HistoryService.lua:9](../../features/services/HistoryService.lua)

**What's wrong:** `TRP3FW.Service.Initialize(self)` works because `Service:Initialize` doesn't reference an inherited base, but it's an unusual call shape when the class defines `:Initialize`.

**Impact:** Reader confusion. Likely copy-paste from a context where the base form was needed.

**Proposed fix:** Either `TRP3FW.Service:Initialize(self)` or restructure. Low priority; cosmetic.

---

## Cross-cutting recommendations

1. **Centralize stat tracking.** `RecordHistory` should be the *only* place session stats increment. `IncrementStat` should remain available for cache-stat sub-keys but not for the top-level alert/block/ghost counters. Add a runtime assertion that catches double-counting attempts during development.

2. **Make the cascading deadline unconditional.** Anything that takes `callback` and may run async should have a hard upper bound on resolution time. Fast-fallback optimizations remain priority-gated; correctness rails do not.

3. **Add a `results.resolved` flag.** Every async-coordinator pattern in this codebase needs late-result protection. Apply the same pattern to any future stages that mix early-success branches with in-flight side-effecting work.

4. **Reconcile the parallel burst queues.** N6/N8 are linked. The hook-layer burst was an early optimization that the pipeline-layer burst now subsumes. Plan a follow-up branch to delete `pendingChompSends`/`pendingTRP3Sends`/`pendingMSPReplies` queue payloads, keeping only "burst-in-progress" boolean state.

5. **TOC vs filesystem CI check.** Pass 1 H7 surfaced a missing file in TOC. Add a build-time assertion that every `^[^#]` line in `TRP3FW.toc` references a file that exists.

6. **Audit every `IncrementStat` call site for typos.** N4 was a typo that silently no-op'd. Either change `IncrementStat` to assert on missing keys (development builds only) or add a one-time linter pass over all call sites.

---

## Findings summary by severity

| Sev      | Count | IDs                                       |
|----------|-------|-------------------------------------------|
| Critical | 7     | N1, N2, N2b, N3, N4, N5, N5b              |
| High     | 5     | N6, N7, N8, N9, N10                       |
| Medium   | 6     | N11, N12, N13, N14, N15, N16              |
| Low      | 3     | N17, N18, N19                             |

**N5b** was discovered during in-game testing of the Phase 4 fix (N5) and is documented inline under N5. It exposed a pre-existing latent bug (wrong cache field name) that N5 made user-visible.

**N2b** was discovered during in-game testing of the Phase 3 fix (N2) and is documented inline under N2. The Phase 3 fix made the deadline unconditional but interacted with a pre-existing latent bug in late SPVP resolution to produce false BLOCK notifications.

**Top 5 to fix first** (biggest impact, smallest patches):

1. **N4** — One-character typo: `spvpCacheHits` → `spvpVerifiedCacheHits`. Restores SPVP cache-hit observability.
2. **N1** — Remove the duplicate `IncrementStat` block in `decision.lua:453–475`. Restores accurate user-facing stats.
3. **N2** — Move the deadline-timer setup outside the `if priority == "HIGH"` block in `cascading.lua`. Eliminates silent send loss.
4. **N9** — One-line addition: `TRP3FW.lastPhaseChangeTime = 0` in `core/init.lua`. Closes the burst-staleness edge case.
5. **N3** — Add `results.resolved` guard in `EvaluateResults`, `OnSPVPResult`, `HandlePhaseResult`, `HandleMapResult`. Prevents target-frame flicker after early-success.

Each is small, isolated, and addresses a real correctness or observability regression.

---

**End of audit.**
