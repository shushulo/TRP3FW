# TRP3FW Audit — Bugs & Gaps Specification

**Date:** 2026-04-27
**Reviewer:** Audit pass over `core/`, `features/`, `location/`, `hooks/`, `ui/`, services, and pipeline stages.
**Scope:** Identify defects, missing initialization, logic errors, doc/code drift, and risk areas. Does **not** propose every refactor — focuses on items that affect correctness, security, or user-visible behavior.

Each finding is structured as:

> **ID — Title** (Severity)
> **Where:** files / lines
> **What's wrong:** observed behavior / code
> **Impact:** what breaks
> **Proposed fix:** minimal change

Severity legend:
- **Critical** — Silent correctness failure, security regression, or stops core feature from working
- **High** — Wrong behavior in common paths, but partially mitigated by other code
- **Medium** — Edge case, latent bug, or doc drift causing confusion
- **Low** — Cleanup, dead code, minor inconsistency

---

## CRITICAL findings

### C1 — `EventService` never registers `ZONE_CHANGED_NEW_AREA` (Critical)

**Where:** [core/EventService.lua:23-32](../../core/EventService.lua) (`Initialize`), [core/EventService.lua:86](../../core/EventService.lua) (`OnEvent` switch)

**What's wrong:** `OnEvent` translates `ZONE_CHANGED_NEW_AREA` → `EventService.Events.ZONE_CHANGED`, but the corresponding `self:Listen("ZONE_CHANGED_NEW_AREA")` call is **missing**. Only `PLAYER_ENTERING_WORLD`, `LOADING_SCREEN_DISABLED`, `SCENARIO_UPDATE`, target/mouseover, WHO, and chat events are registered.

**Impact:** Zone changes (running across a zone boundary without a loading screen) never trigger:
- `CacheService.HandleZonePhaseChange` (no cache clear, no `lastZoneChangeTime` update on plain zone change)
- WHO prepopulation on zone change
- Profile-send history clear

The phase-in delay window relies on `lastZoneChangeTime`, which only updates on loading screens or `EPSILON_PHASE_CHANGE`. After crossing a zone boundary on foot, stale `interactionCache` entries from the prior zone keep firing the `interactionCache.zone ~= currentZone` invalidation only if `currentZoneName` itself was updated — and `currentZoneName` is updated inside `HandleZonePhaseChange`, which never runs. So `currentZoneName` stays stale until the next loading screen or phase event.

**Proposed fix:** Add `self:Listen("ZONE_CHANGED_NEW_AREA")` (and likely also `ZONE_CHANGED_INDOORS` / `ZONE_CHANGED` if you want sub-zone resolution). Verify the existing dedup logic at `CacheService.lua:467,477` still works once the event actually fires.

---

### C2 — `cascading.lua:EvaluateResults` references `spvpVerified` before it's declared (Critical)

**Where:** [location/cascading.lua:52](../../location/cascading.lua) and [location/cascading.lua:74](../../location/cascading.lua)

**What's wrong:** Line 52 reads `spvpVerified` inside the early-success block:
```lua
local phaseVerified = (results.phaseCheck == true or spvpVerified)
```
The local `spvpVerified` is not declared until line 74. At line 52, `spvpVerified` resolves to a global (always `nil`).

**Impact:** The "Early Success (Mutual)" optimization documented in `LOCATION_DETECTION.md` and `DECISION_LOGIC.md` (return Success immediately when standard checks pass while SPVP is still pending) **never fires when phase verification comes from SPVP alone**. It only fires when `results.phaseCheck == true` directly (i.e., a regular phase check already succeeded), which is a narrower case than intended. SPVP-verified-and-map-pass requests wait the full SPVP timeout before completing.

**Proposed fix:** Move the `local spvpVerified = ...` line above the `if results.checksComplete < results.checksExpected then` block (i.e., right after `local CI = TRP3FW.CacheInterface`). No other behavior change required.

---

### C3 — `CacheService` re-creates `profileSendHistory` table, breaking HistoryService alias (Critical)

**Where:** [features/services/CacheService.lua:500](../../features/services/CacheService.lua), [features/services/CacheService.lua:525](../../features/services/CacheService.lua); alias established at [features/services/HistoryService.lua:100](../../features/services/HistoryService.lua)

**What's wrong:** `HistoryService:Initialize` does:
```lua
TRP3FW.profileSendHistory = self.profileSendHistory  -- alias, same table
```

`CacheService.HandleZonePhaseChange` does:
```lua
TRP3FW.profileSendHistory = {}  -- NEW table; HistoryService still holds old reference
```

After the first phase or zone clear, `historyService.profileSendHistory` and `TRP3FW.profileSendHistory` point to **different** tables. Any code that reads through one and writes through the other diverges.

**Impact:** Suppression and "first time" logic become inconsistent. Stages like `BurstStage`, `LocationStage`, `AlertFastPathStage`, and `NotificationService.Notify` all reach into `historyService.profileSendHistory` directly. Writes from `NotificationService.Notify` (line 148-153) write to `TRP3FW.profileSendHistory` (legacy alias). After a clear, those writes vanish from the service's view, while the service's writes vanish from the alias.

**Proposed fix:** Replace the two `TRP3FW.profileSendHistory = {}` lines with `wipe(TRP3FW.profileSendHistory)` (Blizzard utility) or a manual loop — mutate, don't replace. Same applies to `TRP3FW.scanNotificationHistory` if it's aliased anywhere (currently only in `core/init.lua` and `CacheService`, but worth verifying).

---

### C4 — `core/init.lua` calls `TRP3FW:Debug` and `TRP3FW:Error` before `core/utils.lua` is loaded (Critical for new debug/error paths)

**Where:** [core/init.lua:484](../../core/init.lua), [core/init.lua:518-528](../../core/init.lua), [core/init.lua:622](../../core/init.lua), [core/init.lua:669](../../core/init.lua), [core/init.lua:677](../../core/init.lua); load order in [TRP3FW.toc:11-12](../../TRP3FW.toc) (`core/init.lua` then `core/utils.lua`)

**What's wrong:** `core/init.lua` is the **first** core file loaded. It defines a metatable proxy `createDeprecatedCacheTable` whose `__index`/`__newindex` calls `TRP3FW:Debug(...)`. It also defines `InitializeSettings`, `LoadProfile`, `MigrateSettings`, `InitializeCaches`, `GetCachedPhaseID`, etc., all of which call `TRP3FW:Debug` / `TRP3FW:Error`.

`TRP3FW:Debug`, `TRP3FW:Error`, `TRP3FW:Warn`, `TRP3FW:Info`, `TRP3FW:GetCurrentTime` are all defined in `core/utils.lua`, loaded **after** `core/init.lua`.

In practice this works because the proxy's methods aren't *called* during file load — they're called later at runtime, by which time `utils.lua` has loaded. But the dependency is fragile and will break the moment any code at the top level of `core/init.lua` calls one of these helpers. The deprecated proxies `__index` traps would crash if a piece of legacy code tried to read a deprecated cache table during file-load time of any other file.

**Impact:** Fragile load order. Any future top-level call (or any addon that wraps `core/init.lua` access) crashes. The current code happens to defer all calls past `PLAYER_LOGIN`, masking the latent ordering bug.

**Proposed fix (lower-risk):** Either (a) reorder TOC so `core/utils.lua` loads first, or (b) move the deprecated-proxy and other helpers from `init.lua` into a "post-utils" file that loads later. Option (a) is the minimal change and matches the comment in init.lua line 1.

---

### C5 — `LocationStage` and `location_stage.lua` are duplicate implementations; only one wins (Critical for maintainability)

**Where:** [features/stages/LocationStage.lua](../../features/stages/LocationStage.lua) and [features/stages/location_stage.lua](../../features/stages/location_stage.lua); TOC loads only `LocationStage.lua` (case-sensitive on some filesystems but Lua/Windows is forgiving).

**What's wrong:** Two files exist with nearly identical logic but different code paths. The TOC explicitly references `features\stages\LocationStage.lua`, so `location_stage.lua` is loaded only because it gets globbed/co-resident. On case-sensitive filesystems this can become non-deterministic.

`location_stage.lua` adds extra fields to `pendingLocationChecks[playerName]` (`zoneSnapshot`, `phaseSnapshot`, `settingsFingerprint`) which `BurstStage` and `decision.lua:IsBurstRequestStale` rely on for staleness detection. The active `LocationStage.lua` does **not** set these fields, so burst requests queued during a check never see staleness from zone/phase/settings changes — only the 2.0s age limit triggers.

**Impact:** Burst requests aren't dropped on phase or zone change while a location check is pending. A user crossing a phase boundary mid-check could see queued requests applied to the wrong location.

**Proposed fix:** Delete `features/stages/location_stage.lua` and merge the missing snapshot fields into `LocationStage.lua:34-37`:
```lua
TRP3FW.pendingLocationChecks[context.playerName] = {
    timestamp = context.now,
    zoneSnapshot = TRP3FW.lastZoneChangeTime,
    phaseSnapshot = TRP3FW.lastPhaseChangeTime,
    settingsFingerprint = TRP3FW:GetBurstSettingsFingerprint(),
    queuedRequests = {}
}
```

---

## HIGH findings

### H1 — `MoveToTail` in CacheInterface crashes if cache has only one node and `key ~= cache.tail` (High, latent)

**Where:** [core/cache_interface.lua:55-75](../../core/cache_interface.lua)

**What's wrong:**
```lua
local function MoveToTail(cache, key)
    local node = cache.data[key]
    if not node or key == cache.tail then return end -- early return
    local prevKey = node.prev
    local nextKey = node.next
    if prevKey then ... else cache.head = nextKey end
    cache.data[nextKey].prev = prevKey  -- crashes if nextKey is nil
    ...
end
```

The unconditional `cache.data[nextKey].prev = prevKey` assumes `nextKey` is non-nil. The early return covers the case where `key == cache.tail` (which implies `nextKey == nil`), so under correct invariants this is safe. **However**, if the doubly-linked list ever falls out of sync — for instance if `Clear()` is partial or if a manual call to `Remove()` interleaves with iteration — `MoveToTail` will index `cache.data[nil]` and throw.

**Impact:** Latent crash. Hard to trigger today, but no defensive guard.

**Proposed fix:** Add `if not nextKey then return end` after capturing `nextKey`, or assert the invariant explicitly. Cheap and removes the foot-gun.

---

### H2 — `Service:New` shares the base class via `setmetatable(instance, self)`, so all services share state by accident (High risk if subclassed)

**Where:** [core/Service.lua:9-16](../../core/Service.lua), [core/EventService.lua:6](../../core/EventService.lua), [features/services/NotificationService.lua:6](../../features/services/NotificationService.lua), [features/services/HistoryService.lua:6](../../features/services/HistoryService.lua)

**What's wrong:** Each service uses `local FooService = TRP3FW.Service:New("FooService")` which creates an *instance* table whose metatable is `TRP3FW.Service` (because `self == TRP3FW.Service` at `:New` call time). Then methods are attached directly to that instance:
```lua
function NotificationService:Initialize() ... end
```
This is fine because there's only one instance per service. But the pattern in `SPVPStage.lua:10`:
```lua
TRP3FW.SPVPStage = setmetatable({}, { __index = TRP3FW.Stage })
function TRP3FW.SPVPStage:New(name)
    local instance = TRP3FW.Stage:New(name or "SPVPStage")
    setmetatable(instance, { __index = self })
    return instance
end
```
is a different (correct) pattern. The codebase mixes both.

**Impact:** Today, no actual bug because each service is instantiated once. But adding a second service instance, or ever calling `Service:New` twice with the same logical class, would cause cross-instance method bleed. The pattern is unobvious.

**Proposed fix:** Standardize on the explicit-metatable pattern (like SPVPStage) for all services. Or add a comment to `Service:New` documenting that it intentionally produces singletons.

---

### H3 — `cascading.lua` evaluates `RunMapCheck` with a stage label as the priority (High, behavioral)

**Where:** [location/cascading.lua:310-312](../../location/cascading.lua)

**What's wrong:**
```lua
StartStandardChecks(results, "who_map_verification")
```
`"who_map_verification"` is a *category* string defined in `core/utils.lua` priority config (LOW priority bucket). It is then passed downstream as the `priority` argument:
```lua
if priority == "HIGH" then ...
```
So a category name is being conflated with a priority level. The branches that compare `priority == "HIGH"` will never match here, but anywhere the value is inspected as a category-vs-priority it's ambiguous.

**Impact:** Confusing, but not directly broken — the only checks against `priority` are equality with `"HIGH"`. Future code that adds a `priority == "LOW"` branch will silently break.

**Proposed fix:** Either (a) pass `"NORMAL"` and the category separately, or (b) rename the parameter. Document that priority and category are different namespaces.

---

### H4 — `ChompPipeline_GuardChecks_V2` references non-existent `TRP3FW.Prefs.enabled` (High, dead code with no harm today)

**Where:** [hooks/trp3_chomp_pipeline.lua:51](../../hooks/trp3_chomp_pipeline.lua)

**What's wrong:**
```lua
if not TRP3FW.Prefs.enabled then
    -- For now, just continue as there isn't a global 'enabled' toggle in defaultSettings
end
```
The condition is always true (since `Prefs.enabled` is `nil`), but the body is empty. Dead code that confuses future readers.

**Impact:** None functional. Misleading.

**Proposed fix:** Delete the block, or properly add a master `enabled` setting and wire it.

---

### H5 — `decision.lua:218` and `:230` write directly to `self.sessionStats.ghostSends` — bypasses HistoryService increment helpers (High consistency risk)

**Where:** [hooks/trp3_chomp_pipeline.lua:218,230](../../hooks/trp3_chomp_pipeline.lua); HistoryService increments via [features/decision.lua:421](../../features/decision.lua) using `historyService:IncrementStat("ghostSends")`

**What's wrong:** Two different paths increment `ghostSends`:
- `Chomp pipeline start-phase ghost path`: direct `self.sessionStats.ghostSends = self.sessionStats.ghostSends + 1`
- `decision.ApplyLocationDecision`: through `HistoryService:IncrementStat`

The alias works today (HistoryService aliases the table), but if the alias breaks (see C3) or the service ever wraps the table with bookkeeping, the direct write skips it.

**Impact:** Stat divergence, broken if HistoryService adds derived metrics.

**Proposed fix:** Replace direct writes with `historyService:IncrementStat("ghostSends")`. Same for `startPhaseBlocks` writes elsewhere. Audit all sites that touch `sessionStats` directly.

---

### H6 — `BurstStage` reads `historyService.profileSendHistory` *before* `LocationStage` initializes the player's pending entry (High behavior gap)

**Where:** [features/stages/BurstStage.lua:11-43](../../features/stages/BurstStage.lua)

**What's wrong:** `BurstStage` only fires if `TRP3FW.pendingLocationChecks[player]` exists, which is only set by `LocationStage`. In the documented pipeline order (Burst is stage 7, Location is stage 8), the *first* request sails through Burst (no entry yet) and creates the entry inside Location. Subsequent requests within the burst window correctly land in BurstStage. **OK so far.**

But the queued request's `isFirstTime` is computed using `context.settings.suppressionTime` from the *new* request's settings snapshot — which is fine because we just snapshotted it — and reads `historyService.profileSendHistory[player]` directly. If `NotificationService.Notify` or `CacheService` clears `profileSendHistory` mid-burst (see C3), the timeline is inconsistent.

**Impact:** Compounded by C3. Not a standalone bug, but the close coupling means BurstStage should probably ask HistoryService for an "is first time?" check rather than reaching into the table.

**Proposed fix:** Add `historyService:IsFirstSend(player, suppressionTime)` returning `(isFirstTime, suppressedCount)` and use it in `BurstStage`, `LocationStage`, and `AlertFastPathStage` to remove direct table access.

---

### H7 — Architecture docs say "8 stages including PhaseInStage"; pipeline only registers 7 (High doc drift)

**Where:** [thoughts/DECISION_LOGIC.md:7,21](../../thoughts/DECISION_LOGIC.md), [features/pipelines/DecisionPipeline.lua](../../features/pipelines/DecisionPipeline.lua), [features/stages/PhaseInStage.lua] (referenced in TOC at line 49 but the file does not exist in the live `features/stages/` directory — it's only in `pre_phase2_backup`)

**What's wrong:** TOC line 49 lists `features\stages\PhaseInStage.lua`, but `Glob features/stages/*.lua` shows no such file (only the backup copy). At addon load, this will print a load error to the console.

The DecisionPipeline does NOT add a PhaseInStage either. The docs say "Stage 3: PhaseInStage" but it's missing. Phase-in delay logic now lives only in the Chomp hook pipeline (`trp3_chomp_pipeline.lua:63`), which means MSP-only or non-Chomp pathways skip the delay entirely.

**Impact:**
1. TOC load error for missing file (confirm by running addon and checking `/console scriptErrors 1`).
2. Doc lies about pipeline structure.
3. Phase-in delay protection only applies to Chomp-routed sends (which is most TRP3 + MSP, but worth verifying).

**Proposed fix:** Either (a) re-add a thin `PhaseInStage` that wraps `lastZoneChangeTime` check and queues into `pendingPhaseInSends`, calling `originalFunc` after the delay; or (b) remove the TOC entry, update docs to say "7 stages" and document that phase-in delay is Chomp-only by design.

---

### H8 — `cascading.lua:418` double-counts `checksExpected` for SPVP in non-required mode (High behavioral)

**Where:** [location/cascading.lua:417-425](../../location/cascading.lua)

**What's wrong:**
```lua
results.checksExpected = (results.phaseCheckEnabled and 1 or 0) + (results.mapCheckEnabled and 1 or 0) + (results.spvpEnabled and 1 or 0)
if results.spvpEnabled then
    self:CheckPlayerViaSPVP(playerName, sendId, function(verified, source)
        OnSPVPResult(results, verified, source)
    end)
end
StartStandardChecks(results)
```

`StartStandardChecks` (line 258) also recomputes `results.checksExpected`:
```lua
if results.checksExpected == 0 or results.checksExpected == 1 then
    results.checksExpected = ... -- recomputes excluding SPVP
end
```

But this branch only fires when `checksExpected == 0 or == 1`. When SPVP is enabled and both phase+map are enabled, `checksExpected` starts at 3, so the recompute is skipped. Good — but now look at `OnSPVPResult` line 297: `results.checksComplete = results.checksComplete + 1`. And inside `HandlePhaseResult` line 242 the map-skipped path also increments. The accounting can desynchronize.

Also the very first request from `EvaluateResults:50` does:
```lua
if results.checksComplete < results.checksExpected then
```
With no SPVP yet completed but the code calling `EvaluateResults` after every individual check, the early-exit fast paths inside `EvaluateResults` rely on this counter being correct.

**Impact:** Possible premature `EvaluateResults` early-success or premature stall. Requires careful trace to confirm a specific failing scenario, but the counter math is fragile across `OnSPVPResult`, `HandlePhaseResult`, `HandleMapResult`.

**Proposed fix:** Refactor `checksComplete`/`checksExpected` to use a `pending` set keyed by check type (`phase`, `map`, `spvp`) and an "evaluation due when set is empty or early-exit triggered" model. Concrete change: add a `kind` parameter to the result handlers, mark results in a `done = {phase=false, map=false, spvp=false}` table, and replace counter math with a `done.phase or not enabled` check.

---

## MEDIUM findings

### M1 — Validated names persistent cache (`TRP3FW_ValidatedNames`) is declared but never seen pruned in code (Medium)

**Where:** [core/init.lua:764](../../core/init.lua) (declared); [thoughts/CACHING_SYSTEM.md] (described)

**What's wrong:** Settings include `validatedNamesCacheDuration` (default 7 days) and `validatedNamesCacheLimit` (default 5000). Search found no code path that **uses** `TRP3FW_ValidatedNames` for reads, writes, or LRU pruning. The variable persists across sessions but appears unused in the current modular layout. Either it was migrated to `CacheInterface` and the SavedVariable should be removed, or it is dead.

**Impact:** Dead SavedVariable consuming user disk space across releases, or missing functionality.

**Proposed fix:** Grep more carefully (`pre_phase2_backup` references suggest it was used previously). Either remove from TOC SavedVariables and `init.lua:764`, or wire it into `cleanName` / `whoName` cache as a persistent backing store.

---

### M2 — `decision.lua:498` uses `self:GetCurrentPhaseID()` but `GetCurrentPhaseID` is not the same function as `GetCachedPhaseID` (Medium)

**Where:** [features/decision.lua:499](../../features/decision.lua), [core/utils.lua:665](../../core/utils.lua) (`GetCachedPhaseID`); search for `GetCurrentPhaseID` definition.

<sub>Note: I did not verify `GetCurrentPhaseID` is defined elsewhere — quick grep shows it called in many places but only `GetCachedPhaseID` is defined in utils.lua. If `GetCurrentPhaseID` is missing, every SPVP-fallback decision will error or silently bypass.</sub>

**Impact:** Possible nil-call crash on SPVP fallback path.

**Proposed fix:** Verify `GetCurrentPhaseID` is defined (likely in `location/phase.lua` or `features/encryption/spvp.lua`). If it doesn't exist, add it as a thin wrapper for `GetCachedPhaseID`.

---

### M3 — `IsUserInitiatedExchange` uses `GetTime()` for TTL but `userInitiatedQueries` is never cleaned beyond per-call eviction (Medium)

**Where:** [hooks/trp3.lua:258-275](../../hooks/trp3.lua)

**What's wrong:** Entries are added in `sendQuery` and `msp.Request` hooks but only deleted when `IsUserInitiatedExchange` is called for that specific player past TTL. Players you query but never receive replies from leak forever in `userInitiatedQueries`.

**Impact:** Slow memory growth for highly active users. Not a leak in the strict sense (table reference is held) but unbounded.

**Proposed fix:** Wire a periodic prune (e.g., every 5 minutes) into `CacheService` that walks `userInitiatedQueries` and drops entries older than 30s. Or convert to `CacheInterface` with a 30s TTL.

---

### M4 — Architecture doc mismatch: `notifyOnAlert`/`notifyOnBlock` removed but doc tables/settings reference them (Medium doc drift)

**Where:** [thoughts/DATA_STRUCTURES.md, SETTINGS_REFERENCE.md, GHOST_MODE.md, HOOK_SYSTEM.md]; setting comment at [core/init.lua:48](../../core/init.lua) confirms removal.

**Impact:** New contributors reading docs will look for settings that don't exist, or wonder why `phaseCheckMode` controls both alert and block.

**Proposed fix:** Update SETTINGS_REFERENCE.md and DECISION_LOGIC.md to reflect the unified `phaseCheckMode`/`mapCheckMode` dropdown model. Cross-link to the helper functions in `core/init.lua` (`ShouldAlertOnPhase`, `ShouldBlockOnPhase`, etc.).

---

### M5 — `decision.lua` SPVP fallback creates a new context for each queued request but reuses `locationResult` (Medium)

**Where:** [features/decision.lua:540-554, 576-590](../../features/decision.lua)

**What's wrong:** Inside the SPVP rescue callback, queued burst requests are processed by constructing a fresh `queuedContext` but passing the same `locationResult` table. If `ApplyLocationDecision` mutates `locationResult` (e.g., to add `spvpRescue = true` at line 526), all subsequent queued requests see the mutated state — generally fine, but `cacheInfo` and `checkDetails` inside `locationResult` are also shared mutable references. Notification logic could surface stale or inconsistent details.

**Impact:** Notification text for queued requests may include leftover state from earlier requests in the burst.

**Proposed fix:** Shallow-copy `locationResult` (and inner `cacheInfo`/`checkDetails`) before passing to each queued `ApplyLocationDecision`. Or freeze `locationResult` after construction.

---

### M6 — `pre_phase2_backup/` ships with the addon (Medium hygiene)

**Where:** [pre_phase2_backup/TRP3FW/](../../pre_phase2_backup/) contains a full copy of the addon's pre-Phase 2 source.

**What's wrong:** This directory is inside the addon folder. WoW's addon loader ignores it (no `.toc`), but it ships in releases, doubling the on-disk footprint and creating risk that someone debugging "why is my fix not taking effect" greps the backup copy by mistake.

**Impact:** ~2x disk usage, debugging confusion.

**Proposed fix:** Move `pre_phase2_backup` outside the working addon directory, or add it to `.pkgmeta`'s `ignore` list (CurseForge packager) so releases skip it. Optionally just delete it — git history is the real backup.

---

### M7 — `ValidateSettings` defaults conflict with `defaultSettings` (Medium)

**Where:** [core/utils.lua:577-607](../../core/utils.lua) (validator) vs [core/init.lua:34-235](../../core/init.lua) (defaults)

**What's wrong:** Validator uses `default = 300` for `suppressionTime` but `defaultSettings.suppressionTime = 600`. Same for `phaseCacheDuration` (validator default 120, init.lua default 300), `whoZoneCacheDuration` (validator 60, init 180), `whoNameCacheDuration` (validator 60, init 180), `interactionCacheDuration` (validator 300, init 600), `cacheSizeLimit` (validator 500, init 1000), and `scanCacheDuration` (validator and init agree at 120).

If validation fires (e.g. user enters an out-of-range value), the user is silently reset to the *validator's* default, which often differs from the documented/init default. This silently downgrades the cache durations.

**Impact:** Surprising user-facing behavior after a bad input.

**Proposed fix:** Make validator pull defaults from `TRP3FW.defaultSettings` rather than hardcoding. Single source of truth.

---

### M8 — `ProcessLocationDecision` re-runs `IsUserInitiatedExchange` for queued contexts but original burst-request contexts may already be expired (Medium)

**Where:** [features/decision.lua:551,587,636](../../features/decision.lua)

**What's wrong:** `IsUserInitiatedExchange` checks `userInitiatedQueries[player]` against a 5s TTL. Queued burst requests may be 1-2s old already; by the time they replay, the user-initiated marker may have expired even though the original request *was* user-initiated.

**Impact:** Mutual-exchange suppression may not apply to queued requests in the same burst, causing duplicate "Profile sent" notifications.

**Proposed fix:** Cache `isUserInitiated` on the original `context` and inherit it for all queued requests instead of re-evaluating.

---

### M9 — `interactionCache` `zone` invalidation only fires when `currentZone` is non-nil (Medium)

**Where:** [features/stages/InteractionStage.lua:21](../../features/stages/InteractionStage.lua)

**What's wrong:**
```lua
if lastInteraction and currentZone and lastInteraction.zone and lastInteraction.zone ~= currentZone then
    CI:Remove("interaction", context.playerName)
    lastInteraction = nil
end
```
If `currentZone` is `nil` (the EventService bug C1 means this happens often after foot-zone-changes), the stale cross-zone entry survives and the player gets allowed.

**Impact:** Compounded by C1. Independent fix: invalidate by `mapID` instead of (or in addition to) `zone`, since mapID is more reliably populated.

**Proposed fix:** Use `mapID` mismatch as primary invalidation key; keep zone as secondary.

---

### M10 — `location_stage.lua` (the legacy file) calls `self:RecordHistory` (no service indirection) (Medium dead code)

**Where:** [features/stages/location_stage.lua:16](../../features/stages/location_stage.lua)

**What's wrong:** Legacy file calls `self:RecordHistory(...)` which is now defined on `HistoryService`, not on `TRP3FW`. If this file ever loads (depending on filesystem case sensitivity), the call fails silently because `TRP3FW:RecordHistory` doesn't exist as a top-level method anymore.

**Impact:** Bound up with C5. After deleting `location_stage.lua` per C5, this is moot.

---

## LOW findings

### L1 — `TRP3FW.profiler.report` re-sorts `stats.calls` on every report (Low)

**Where:** [core/init.lua:432-438](../../core/init.lua)

**What's wrong:** Every `report()` call sorts the entire `calls` array for each tracked function. With 1000 calls × N functions, this is O(N·M log M) per report. Profiling reports are rare so not a real cost.

**Proposed fix:** None unless reports become frequent. Note for future.

---

### L2 — Random eviction comment in profiler (Low)

**Where:** [core/init.lua:388-390](../../core/init.lua)

**What's wrong:**
```lua
-- FIXED: MEDIUM-2 - Use random eviction instead of FIFO to prevent timing attacks
local randomIndex = math.random(1, #stats.calls)
table.remove(stats.calls, randomIndex)
```
Random eviction defeats the point of an LRU/percentile-tracking buffer. P95 calculations on randomly-evicted samples are statistically biased toward older outliers. The comment about "timing attacks" against a profiler buffer is unmotivated — the buffer is local to the user's client.

**Impact:** Inaccurate P95 and P99 reports. Not a security issue.

**Proposed fix:** Switch to FIFO (or reservoir sampling if you want statistical correctness). Remove the timing-attack rationale.

---

### L3 — Multiple comments saying "// removed" / "DEPRECATED" without removing the code (Low)

**Where:** [core/init.lua:535-561](../../core/init.lua) (deprecated cache table proxies)

**What's wrong:** The proxies emit deprecation warnings on every access, but they're still wired in. If everything is migrated, delete them. If not, the deprecation warnings spam debug logs.

**Proposed fix:** Confirm no live code uses `TRP3FW.allowedSendersCache` etc. directly (grep), then delete the proxies. They're a runtime cost and a maintenance distraction.

---

### L4 — `TODO.md` mentions completed Phase 2 work but lists "Future Optimizations" that should move to a separate file (Low)

**Where:** [thoughts/TODO.md](../../thoughts/TODO.md)

**Proposed fix:** Archive completed sections, reorganize.

---

### L5 — Doc index has a stray space in dropdown enum: `" statistics"` (Low)

**Where:** [thoughts/DATA_STRUCTURES.md:61](../../thoughts/DATA_STRUCTURES.md)

**What's wrong:** Documents `phaseCheckMode = "off", " statistics", ...` — the ` statistics` value has a leading space. Either typo in docs or actual code accepts `" statistics"`. Code uses `"alert"`, `"block"`, `"ghost"`, `"alert_block"`, `"alert_ghost"`, no `"statistics"`.

**Proposed fix:** Doc cleanup.

---

## Cross-cutting recommendations

1. **Single-source-of-truth for defaults.** Make `ValidateSettings` pull from `defaultSettings` (M7) and replace all hardcoded fallbacks (e.g., `or 600`, `or 4`, `or 30`) with reads from `defaultSettings`.

2. **HistoryService API hardening.** Remove direct `historyService.profileSendHistory` access from stages and notification service. Expose:
   - `historyService:GetSendHistory(player) -> entry`
   - `historyService:RecordSend(player, timestamp)`
   - `historyService:IsFirstSend(player, suppressionTime) -> isFirst, suppressedCount`

   This eliminates C3, M5, H6 in one stroke.

3. **EventService completeness.** Audit `Listen()` calls vs the `OnEvent` dispatch table. Add a unit test or runtime assertion: every event mentioned in `OnEvent` must be in `Listen()`. C1 demonstrates this gap.

4. **Stage-style consistency.** Pick either the `setmetatable({}, {__index = TRP3FW.Stage})` pattern or the `TRP3FW.Stage:New()` instance pattern, and apply uniformly. Mixed styles have already produced one suspicious area (H2).

5. **Reconcile `LocationStage.lua` vs `location_stage.lua`.** Pick one, delete the other, document the choice in HOOK_SYSTEM.md.

6. **Verify TOC entries against filesystem.** Add a build/CI check that every entry in `TRP3FW.toc` exists. H7 (PhaseInStage) is the proof point.

---

## Findings summary by severity

| Sev      | Count | IDs                              |
|----------|-------|----------------------------------|
| Critical | 5     | C1, C2, C3, C4, C5               |
| High     | 8     | H1–H8                            |
| Medium   | 10    | M1–M10                           |
| Low      | 5     | L1–L5                            |

**Top 3 to fix first** (biggest impact, smallest patch):
1. **C2** — Move `local spvpVerified = ...` above the early-success block in `cascading.lua`. ~1 line.
2. **C1** — Add `self:Listen("ZONE_CHANGED_NEW_AREA")` in `EventService:Initialize`. ~1 line.
3. **C3** — Replace `TRP3FW.profileSendHistory = {}` with `wipe(TRP3FW.profileSendHistory)` in `CacheService.lua` (2 sites). ~2 lines.

Each is small, isolated, and addresses a real correctness regression masked by other working paths.

---

**End of audit.**
