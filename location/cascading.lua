-- location/cascading.lua
-- Cascading location check logic - coordinates phase, WHO, and map scanning

local addonName, TRP3FW = ...

-- Constants
local START_PHASE_ID = 169  -- Epsilon start phase ID (blocks all transmissions)

-- ===================== Helpers =====================

local function IsMethodStrong(m)
    return m and (m:find("target") or m:find("batch") or m == "nameplate" or m == "group" or m:find("scanned") or m == "who_query")
end

local function IsReliableMapFailure(results, source, spvpVerified)
    if not source then return false end

    -- Throttles and backoffs are always unreliable signals of location
    if source:find("backoff") or source:find("rate_limit") then return false end

    -- Nearness signal: proves they are physically nearby (not just same-phase)
    local isNear = IsMethodStrong(results.phaseMethod) or IsMethodStrong(results.mapMethod)

    if results.phaseCheck == true or spvpVerified then
        -- If we are SURE they are nearby (targeting confirmed), then timeouts and missing info are unreliable
        if isNear then
            if source:find("timeout") or source == "who_not_found" or source == "cached" then return false end
        end
    end

    -- Standard reliable failure sources (mismatch, explicit who/scanned fail)
    local isReliable = (source == "cached" or source:find("mismatch") or source:find("no_zone") or source:find("who") or source:find("scanned") or source == "cached_zone_complete")

    -- Timeouts are considered reliable failures if we don't have a nearness signal (Targeting)
    -- (Unless we are in a transition grace period where everything is unreliable)
    if source:find("timeout") and not results.recentTransition then
        isReliable = not isNear
    end

    return isReliable
end

-- H8: Track per-kind completion instead of fragile counter math. `expected` records which
-- check kinds were ever in scope for this evaluation; `done` records which have reported in.
-- A result is considered complete when every expected kind has either reported or been
-- short-circuited (e.g. map skipped because phase verified strongly).
local function MarkComplete(results, kind)
    if not results.done then results.done = {} end
    results.done[kind] = true
end

local function IsComplete(results)
    if results.expected then
        for kind in pairs(results.expected) do
            if not (results.done and results.done[kind]) then return false end
        end
        return true
    end
    return false
end

local function EvaluateResults(results)
    local playerName = results.playerName
    local spvpEnabled = results.spvpEnabled
    local spvpMode = results.spvpMode or "off"
    local CI = TRP3FW.CacheInterface

    local spvpVerified = (results.spvpCheck == true) or (CI and CI:Get("spvpVerified", playerName) ~= nil)

    -- OPTIMIZATION: Early Success (Don't wait for slow SPVP if standard checks pass)
    if not IsComplete(results) then
        local mapVerified = (results.mapCheck == true)
        local phaseVerified = (results.phaseCheck == true or spvpVerified)
        local isStrongPhase = IsMethodStrong(results.phaseMethod)
        local isStrongMap = IsMethodStrong(results.mapMethod)

        if mapVerified and phaseVerified and (isStrongPhase or isStrongMap) and spvpMode ~= "required" then
            TRP3FW:Debug("Early Success (Mutual) triggered for "..playerName..": Phase/Map verified (skipping pending SPVP)", "location")
        elseif mapVerified and isStrongMap and results.whoNameOnly and spvpMode == "optional" then
            -- SPECIAL CASE: Scan replies with strong map success don't need to wait for SPVP/Phase if optional
            TRP3FW:Debug("Early Success (Scan) triggered for "..playerName..": Map verified (skipping pending Phase/SPVP)", "location")
            -- Satisfy the evaluation logic so it doesn't block on phase_unknown/phase_fail
            results.phaseCheck = true
            results.phaseSource = "early_success_scan"
            results.phaseMethod = "map_satisfaction"
        else
            return -- Wait for all checks
        end
    end

    TRP3FW:Debug("=== All location checks complete for "..playerName.." ===", "location")
    local locationOK = true
    local alertTypes = {}

    local checkDetails = {
        phase = { result = results.phaseCheck, source = results.phaseSource, method = results.phaseMethod, theirMapID = results.theirMapID, myMapID = results.myMapID, disabled = results.phaseDisabled },
        map = { result = results.mapCheck, source = results.mapSource, method = results.mapMethod, cacheAge = results.mapCacheAge, theirZone = results.theirZone, myZone = results.myZone, theirMapID = results.theirMapFromWho or results.theirMapID, myMapID = results.myMapID, skippedBecausePhase = results.mapSkippedBecausePhase, disabled = results.mapDisabled },
        spvp = { result = results.spvpCheck, source = results.spvpSource, disabled = results.spvpDisabled }
    }

    -- 1. SPVP Required failure
    if spvpEnabled and spvpMode == "required" and not spvpVerified then
        locationOK = false
        table.insert(alertTypes, results.spvpSource == "timeout" and "spvp_timeout" or "spvp_failed")
    end

    -- 2. Phase Check Evaluation
    if not results.phaseDisabled then
        if results.phaseCheck == false and not spvpVerified then
            if TRP3FW:ShouldAlertOnPhase() or TRP3FW:ShouldBlockOnPhase() then
                locationOK = false
                table.insert(alertTypes, "phase")
            end
        elseif results.phaseCheck == nil and not spvpVerified then
            if TRP3FW:ShouldAlertOnPhase() or TRP3FW:ShouldBlockOnPhase() then
                locationOK = false
                table.insert(alertTypes, "phase_unknown")
            end
        end
    end

    -- Update checkDetails for notification display
    if spvpVerified then
        checkDetails.phase.result = true
        checkDetails.phase.source = results.spvpSource or "spvp"
        checkDetails.phase.method = "spvp"
    end

    -- 3. Map Check Evaluation
    -- If phase verified via strong signal, map check failure is irrelevant noise
    local isPhaseStrong = IsMethodStrong(results.phaseMethod) or (results.phaseMethod == "spvp" and results.mapMethod == "target")
    if (results.phaseCheck == true or spvpVerified) and isPhaseStrong then
        if results.mapCheck == false then
             results.mapCheck = true
             results.mapSource = "ignored_targeting_verified"
             results.mapSkippedBecausePhase = true
             checkDetails.map.result = true
             checkDetails.map.source = "ignored_targeting_verified"
             checkDetails.map.skippedBecausePhase = true
        end
    end

    if not results.mapDisabled then
        if results.mapCheck == false then
            if IsReliableMapFailure(results, results.mapSource, spvpVerified) then
                if TRP3FW:ShouldAlertOnMap() or TRP3FW:ShouldBlockOnMap() then
                    locationOK = false
                    table.insert(alertTypes, "map")
                end
            else
                if TRP3FW:ShouldAlertOnMap() or TRP3FW:ShouldBlockOnMap() then
                    locationOK = false
                    table.insert(alertTypes, "map_unknown")
                end
            end
        elseif results.mapCheck == nil then
            if TRP3FW:ShouldAlertOnMap() or TRP3FW:ShouldBlockOnMap() then
                locationOK = false
                table.insert(alertTypes, "map_unknown")
            end
        end
    end

    -- 4. Overrides
    if results.phaseCheck == true or spvpVerified then
        local reliableMapFailure = not results.mapDisabled and results.mapCheck == false and IsReliableMapFailure(results, results.mapSource, spvpVerified)
        if not reliableMapFailure then
            locationOK = true
            alertTypes = {} -- CLEAR ALERTS on success!

            -- FORCE NOTIFICATION TO SHOW SUCCESS
            if spvpVerified and results.phaseCheck ~= true then
                results.phaseCheck = true
                results.phaseSource = results.spvpSource or "spvp"
                results.phaseMethod = "spvp"
                checkDetails.phase.result = true
                checkDetails.phase.source = results.phaseSource
                checkDetails.phase.method = results.phaseMethod
            end
            TRP3FW:Debug("  Final decision for "..playerName..": ALLOW", "location")
        end
    end

    local alertType = #alertTypes > 0 and table.concat(alertTypes, "+") or nil
    TRP3FW.profiler.stop("CheckLocationCascading")
    if results.callback and not results.resolved then
        -- N3: mark resolved BEFORE invoking callback so any late handlers (SPVP arriving
        -- after early-success, deadline firing during callback, etc.) bail out cleanly.
        results.resolved = true
        results.callback(locationOK, alertType, "combined", results.mapCacheAge, results.theirZone, results.myZone, results.cacheInfo, results.recentTransition, results.timeSinceTransition, checkDetails)
        results.callback = nil
    end
end

local function HandleMapResult(results, found, source, age, method, tMapID, tZone)
    if results.resolved then return end  -- N3: discard late results
    if results.mapCheck ~= nil then return end
    results.mapCheck, results.mapSource, results.mapMethod, results.mapCacheAge = found, source, method or source, age
    results.theirMapID, results.theirZone = tMapID or results.theirMapID, tZone or results.theirZone
    MarkComplete(results, "map")
    EvaluateResults(results)
end

local function RunMapCheck(results, priority)
    if not results.mapCheckEnabled or results.mapCheck ~= nil or results.mapCheckStarted then return end
    results.mapCheckStarted = true

    local playerName = results.playerName
    local sendId = results.sendId

    local function startMapScan()
        if results.mapCheck ~= nil or results.mapScanTriggered then return end
        results.mapScanTriggered = true
        if TRP3FW.detectedAddons.MapScanner then
            TRP3FW:MapScan(playerName, sendId, function(f, s, a)
                if s:find("cached") then results.cacheInfo.mapCache = "hit" end
                HandleMapResult(results, f, s, a)
            end)
        else
            -- No scanner, fail map check
            HandleMapResult(results, false, "no_scanner")
        end
    end

    local whoService = TRP3FW.ServiceContainer:Get("WhoService")
    local whoBusy = whoService and (whoService.pendingQuery or whoService.cooldownActive)

    if TRP3FW.Prefs.useWhoQuery and TRP3FW.hasEpsilonAPI and not (priority == "HIGH" and whoBusy) then
        -- Trigger WHO
        TRP3FW:CheckPlayerViaWho(playerName, sendId, function(found, source, age, zone, tMapID)
            if source == "cached" then results.cacheInfo.whoCache = "hit" end

            -- If we already have a map result (e.g. from parallel scan), don't trigger another one
            if results.mapCheck ~= nil then return end

            if (source:find("timeout") or source:find("backoff") or source:find("rate_limit")) then
                -- WHO failed/timed out, start map scan if not already running
                startMapScan()
            else
                local f = found
                if not zone and tMapID and results.myMapID and tMapID ~= results.myMapID then f = false end
                HandleMapResult(results, f, source, age, source, tMapID, zone)
            end
        end, true, results.whoNameOnly or false, priority)

        -- FAST FALLBACK for WHO:
        -- If HIGH priority, don't wait for WHO to timeout. Start Map Scan after 0.3s.
        if priority == "HIGH" then
            C_Timer.After(0.3, function()
                startMapScan()
            end)
        end
    else
        startMapScan()
    end
end

local function HandlePhaseResult(results, inPhase, source, theirMapID, phaseMethod, priority)
    if results.resolved then return end  -- N3: discard late results
    results.phaseCheck, results.theirMapID, results.phaseSource, results.phaseMethod = inPhase, theirMapID, source, phaseMethod
    MarkComplete(results, "phase")
    if source and source:find("cached") then results.cacheInfo.phaseCache = "hit" end

    if results.mapCheckEnabled and results.mapCheck == nil and not results.mapCheckStarted and inPhase == true and IsMethodStrong(phaseMethod) then
        results.mapCheck, results.mapSource, results.mapMethod, results.mapSkippedBecausePhase = true, "skipped_phase_verified", "skipped", true
        MarkComplete(results, "map")
        EvaluateResults(results)
    else
        if results.mapCheckEnabled and results.mapCheck == nil and not results.mapCheckStarted then
            RunMapCheck(results, priority)
        else
            EvaluateResults(results)
        end
    end
end

local function StartStandardChecks(results, priority)
    local phaseCheckEnabled = results.phaseCheckEnabled
    local playerName = results.playerName
    local sendId = results.sendId

    if phaseCheckEnabled and results.phaseCheck == nil and not results.phaseCheckStarted then
        results.phaseCheckStarted = true
        TRP3FW:CheckPlayerPhase(playerName, sendId, function(inPhase, source, theirMapID, phaseMethod)
            HandlePhaseResult(results, inPhase, source, theirMapID, phaseMethod, priority)
        end, priority)

        -- FAST FALLBACK: If high priority (like scan replies), don't wait for the full targeting timeout.
        -- If targeting hasn't finished in 0.2s, start map checks in parallel to meet the 3s window.
        if priority == "HIGH" then
            C_Timer.After(0.2, function()
                if results.mapCheckEnabled and results.mapCheck == nil and not results.mapCheckStarted then
                    TRP3FW:Debug("[Fast Fallback] Targeting taking too long for "..playerName..", starting map checks", "location")
                    RunMapCheck(results, priority)
                end
            end)
        end
    elseif results.phaseCheck ~= nil then
        if results.mapCheckEnabled and results.mapCheck == nil and not results.mapCheckStarted then
            RunMapCheck(results, priority)
        end
    else
        -- Start map check if phase is disabled or not started
        if results.mapCheckEnabled and results.mapCheck == nil and not results.mapCheckStarted then
            RunMapCheck(results, priority)
        end
    end
end

local function OnSPVPResult(results, verified, source)
    -- N3: SPVP can return after EvaluateResults already invoked the callback via the
    -- early-success branch. Prior to this guard, late SPVP success would re-fire phase
    -- target queries (visible target-frame flicker after the request was already allowed)
    -- and SPVP-failed-preferred would re-trigger StartStandardChecks on a resolved request.
    if results.resolved then
        TRP3FW:Debug("[SPVP] Late result for "..results.playerName.." discarded (already resolved)", "spvp")
        return
    end

    local playerName = results.playerName
    local sendId = results.sendId
    local mapCheckEnabled = results.mapCheckEnabled
    local spvpMode = results.spvpMode or "off"

    results.spvpCheck, results.spvpSource = verified, source
    MarkComplete(results, "spvp")
    if source == "cached" then results.cacheInfo.spvpCache = "hit" end

    if verified and (spvpMode == "preferred" or spvpMode == "required") then
        results.phaseCheck, results.phaseSource, results.phaseMethod = true, "spvp", "spvp"
        -- N7: Maintain the implicit invariant "phase resolved => phaseCheckStarted true".
        -- StartStandardChecks reads `phaseCheck ~= nil` first today, but if anyone reorders
        -- those checks, the absence of phaseCheckStarted would re-fire phase queries on an
        -- already-SPVP-verified request. Set it explicitly.
        results.phaseCheckStarted = true
        if results.phaseCheckEnabled then
            results.expected.phase = true
            MarkComplete(results, "phase")
        end
        if mapCheckEnabled then
            results.expected.map = true
            TRP3FW:CheckPlayerPhase(playerName, sendId, function(inPhase, s, tMapID, pMethod)
                    if inPhase then
                        results.mapCheck, results.mapSource, results.mapMethod, results.theirMapID = true, "target_verification", "target", tMapID
                        results.mapCheckStarted = true  -- N7: same invariant for map.
                        MarkComplete(results, "map")
                        EvaluateResults(results)
                    else
                        -- H3: was passing the category "who_map_verification" as priority.
                        -- That string falls through every `priority == "HIGH"` branch silently.
                        -- This is the SPVP-verified-also-need-map path; NORMAL is correct.
                        StartStandardChecks(results, "NORMAL")
                    end
                end, "who_map_verification")
        else
            EvaluateResults(results)
        end
    elseif not verified and spvpMode == "preferred" then
        -- SPVP failed in preferred mode: fall back to standard phase+map. Re-expand `expected`.
        if results.phaseCheckEnabled then results.expected.phase = true end
        if results.mapCheckEnabled then results.expected.map = true end
        StartStandardChecks(results, "HIGH")
    else
        EvaluateResults(results)
    end
end

-- ===================== Cascading Location Check =====================

function TRP3FW:CheckLocationCascading(playerName, sendId, callback, options)
    options = options or {}
    TRP3FW.profiler.start("CheckLocationCascading")

    local now = self:GetCurrentTime()

    -- OPTIMIZATION: Start Phase Early Exit (Fail Fast)
    if TRP3FW.Prefs.blockStartPhase and self:GetCurrentPhaseID() == START_PHASE_ID then
        TRP3FW.profiler.stop("CheckLocationCascading")
        if callback then callback(false, "start_phase_block", "start_phase", 0, nil, nil, {}, false, 0, nil) end
        return
    end

    -- OPTIMIZATION: Interaction Cache Fast-Path (Success Fast)
    local CI = self.CacheInterface
    local interaction = CI and CI:Get("interaction", playerName)
    if interaction and (now - interaction.timestamp) < TRP3FW.Prefs.interactionCacheDuration then
        local inTransitionGracePeriod = (now - (self.lastZoneChangeTime or 0)) < (TRP3FW.Prefs.transitionGracePeriod or 3)
        TRP3FW.profiler.stop("CheckLocationCascading")
        if callback then callback(true, nil, "interaction_cache", now - interaction.timestamp, nil, nil, { interactionCache = "hit" }, inTransitionGracePeriod, 0, nil) end
        return
    end

    local myMapID = C_Map.GetBestMapForUnit("player")
    local myZone = GetRealZoneText()
    local timeSinceTransition = math.min(now - (self.lastZoneChangeTime or 0), now - (self.lastPhaseChangeTime or 0))
    local inTransitionGracePeriod = timeSinceTransition < (TRP3FW.Prefs.transitionGracePeriod or 3)

    local phaseCheckEnabled = self.hasEpsilonAPI and (options.phaseCheckEnabled ~= false and self:IsPhaseCheckEnabled())
    local mapCheckEnabled = options.mapCheckEnabled ~= false and self:IsMapCheckEnabled()

    local spvpEnabled = options.spvpEnabled
    local spvpMode = options.spvpMode or TRP3FW.Prefs.spvpMode or "off"

    -- Late SPVP Resolution
    -- BUG FIX: GetPhaseSalt returns nil on negative cache hit (no salt configured for this
    -- phase) and "" is never returned by current code paths. The previous `~= ""` check
    -- treated nil-salt as "salt present" because `nil ~= ""` is true, enabling SPVP for
    -- phases without salts. This caused SPVP INIT packets to be sent into the void, the
    -- handshake to time out at 5s, and meanwhile the cascading flow allocated `expected.spvp`
    -- which the 2.0s deadline force-completed alongside falsely-failing phase/map. Result:
    -- phantom blocks with `phase=fail (timeout), map=fail (timeout)` for all sends in
    -- phases without an SPVP salt configured.
    if spvpEnabled == nil and TRP3FW.Prefs.spvpEnabled and self.hasEpsilonAPI then
        local currentPhaseID = self:GetCurrentPhaseID()
        if currentPhaseID and currentPhaseID ~= 169 then
            local salt = self:GetPhaseSalt(currentPhaseID)
            if salt and salt ~= "" then
                spvpEnabled = true
            end
        end
    end

    local results = {
        playerName = playerName, sendId = sendId, callback = callback,
        phaseCheck = nil, mapCheck = nil, spvpCheck = nil,
        mapCacheAge = nil, theirMapID = nil, theirZone = nil, theirMapFromWho = nil,
        mapSource = nil, spvpSource = nil, phaseSource = nil, phaseMethod = nil,
        myMapID = myMapID, myZone = myZone,
        -- H8: Per-kind tracking. `expected` = which kinds will report; `done` = which have.
        expected = {}, done = {},
        recentTransition = inTransitionGracePeriod, timeSinceTransition = timeSinceTransition,
        phaseDisabled = not phaseCheckEnabled, mapDisabled = not mapCheckEnabled, spvpDisabled = not spvpEnabled,
        phaseCheckEnabled = phaseCheckEnabled, mapCheckEnabled = mapCheckEnabled,
        spvpEnabled = spvpEnabled, spvpMode = spvpMode,
        whoNameOnly = options.whoNameOnly,
        cacheInfo = {}
    }
    if phaseCheckEnabled then results.expected.phase = true end
    if mapCheckEnabled then results.expected.map = true end
    if spvpEnabled then results.expected.spvp = true end

    -- DEADLINE HANDLER (N2): Unconditional 2.0s deadline. Without this, a hung phase or
    -- WHO check leaves `results.callback` pending forever; `LocationStage`'s 30s housekeeping
    -- timer then nils the pending state without ever invoking originalFunc, silently dropping
    -- the send. Fast-fallbacks (0.2s phase, 0.3s WHO) remain HIGH-priority-only — those are
    -- latency optimizations; this is a correctness rail.
    local deadlineTimer = C_Timer.NewTimer(2.0, function()
        if results.callback and not results.resolved then
            TRP3FW:Debug("[Deadline] Forcing location evaluation for "..playerName.." (2.0s reached)", "location")
            -- BUG FIX: Only force-fail checks that ACTUALLY STARTED. Forcing checks that
            -- were never started (e.g. SPVP wrongly enabled with no salt, or phase queue
            -- mutex held by a hung prior check) makes the deadline synthesize phantom
            -- failures and produces false BLOCK notifications with "phase=fail (timeout),
            -- map=fail (timeout)" reasons even when those checks should never have run.
            --
            -- Use `nil` (unknown) instead of `false` (definitively-not-in-phase) so
            -- EvaluateResults treats them as `phase_unknown`/`map_unknown`, which only
            -- alert (don't block) under the standard alert/block mode. A request that
            -- legitimately can't be verified should fail open or alert-only — never block
            -- with a false certainty.
            if results.phaseCheck == nil and results.phaseCheckStarted then
                results.phaseCheck = false
                results.phaseSource = "deadline_timeout"
                results.phaseMethod = "timeout"
            end
            if results.mapCheck == nil and results.mapCheckStarted then
                results.mapCheck = false
                results.mapSource = "deadline_timeout"
                results.mapMethod = "timeout"
            end
            -- Force all expected kinds to be 'complete' so EvaluateResults proceeds
            if results.expected then
                for kind in pairs(results.expected) do MarkComplete(results, kind) end
            end
            EvaluateResults(results)
        end
    end)
    -- Wrap callback to cancel timer
    local originalCallback = results.callback
    results.callback = function(...)
        if deadlineTimer then deadlineTimer:Cancel() deadlineTimer = nil end
        if originalCallback then originalCallback(...) end
    end

    -- SPVP Execution
    -- preferred/required SPVP: gate phase+map behind SPVP first (only `spvp` is initially expected;
    -- OnSPVPResult re-expands `expected` to phase/map as it discovers what else is needed).
    if results.spvpEnabled and (results.spvpMode == "preferred" or results.spvpMode == "required") then
        results.expected = { spvp = true }
        self:CheckPlayerViaSPVP(playerName, sendId, function(verified, source)
            OnSPVPResult(results, verified, source)
        end)
    else
        if results.spvpEnabled then
            self:CheckPlayerViaSPVP(playerName, sendId, function(verified, source)
                OnSPVPResult(results, verified, source)
            end)
        end
        StartStandardChecks(results)
    end
end