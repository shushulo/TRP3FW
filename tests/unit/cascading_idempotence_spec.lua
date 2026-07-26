-- tests/unit/cascading_idempotence_spec.lua
-- Headless tests for HandlePhaseResult's idempotence guard (location/cascading.lua).
--
-- HandleMapResult has always opened with `if results.mapCheck ~= nil then return end`.
-- HandlePhaseResult had no equivalent, so a repeat delivery of the phase callback re-ran
-- its entire body -- including the RunMapCheck dispatch. That asymmetry is why an earlier
-- duplicate phase-check callback went unnoticed for so long: the phase side quietly
-- absorbed it instead of failing loudly. These tests pin the guard.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW()
    local fw = H.newNamespace()
    fw.Prefs = { interactionCacheDuration = 600, blockStartPhase = false }
    fw.profiler = { start = function() end, stop = function() end }

    H.loadModule("core/cache_interface.lua", fw)
    fw.CacheInterface:Register("interaction", {})
    fw.CacheInterface:Register("spvpVerified", {})

    _G.C_Map = { GetBestMapForUnit = function() return 1 end }
    _G.GetRealZoneText = function() return "TestZone" end

    function fw:GetCurrentPhaseID() return 1 end
    function fw:IsPhaseCheckEnabled() return true end
    function fw:IsMapCheckEnabled() return true end
    -- phaseCheckEnabled is gated on hasEpsilonAPI (cascading.lua:412), so the phase leg
    -- only starts with the Epsilon API present.
    fw.hasEpsilonAPI = true
    fw.detectedAddons = { MapScanner = true }
    fw.ServiceContainer = { Get = function() return nil end }

    -- Alert/block policy: blocking on both kinds, so a failed check produces a real block
    -- and the phaseCheck==true override is observable as a flip to allow.
    function fw:ShouldAlertOnPhase() return true end
    function fw:ShouldBlockOnPhase() return true end
    function fw:ShouldAlertOnMap() return true end
    function fw:ShouldBlockOnMap() return true end

    -- Capture the phase callback so a spec can deliver it more than once, which is the
    -- duplicate-delivery scenario the guard exists for.
    fw.capturedPhaseCallback = nil
    function fw:CheckPlayerPhase(playerName, sendId, callback)
        self.capturedPhaseCallback = callback
    end

    -- Count map-scan dispatches: the observable consequence of a re-run is a SECOND
    -- RunMapCheck going out.
    fw.mapScanCount = 0
    fw.capturedMapCallback = nil
    function fw:MapScan(playerName, sendId, callback)
        self.mapScanCount = self.mapScanCount + 1
        self.capturedMapCallback = callback
    end

    H.loadModule("location/cascading.lua", fw)
    return fw
end

T.describe("HandlePhaseResult idempotence", function()
    T.it("dispatches exactly one map check for a single phase result", function()
        mock.setClock(1000)
        local fw = freshFW()

        fw:CheckLocationCascading("Bob", 1, function() end)
        T.not_nil(fw.capturedPhaseCallback, "sanity: phase check must have been started")

        -- inPhase=false so the 'skipped_phase_verified' shortcut is not taken and a real
        -- map check is dispatched.
        fw.capturedPhaseCallback(false, "targeting", nil, "target")
        T.eq(fw.mapScanCount, 1, "one phase result must produce one map scan")
    end)

    -- NOTE ON WHAT THIS GUARD ACTUALLY PROTECTS.
    -- `results.resolved` already absorbs a duplicate that arrives AFTER the cascade has
    -- finished, so the interesting window is a duplicate arriving while the cascade is
    -- still in flight: phase reports twice before the map leg comes back. That is the only
    -- state in which the missing guard was observable, and it is the state the earlier
    -- duplicate phase-check callback actually occupied.
    -- This one passes with OR without the guard -- RunMapCheck's own `mapCheckStarted` flag
    -- already stops the second dispatch. Kept as a regression fence on that second line of
    -- defence, not as the pin for the guard itself; the flip-to-allow test below is the one
    -- that actually fails against the unfixed code.
    T.it("a duplicate phase result mid-flight does not dispatch a second map check", function()
        mock.setClock(1000)
        local fw = freshFW()

        local calls = 0
        fw:CheckLocationCascading("Bob", 1, function() calls = calls + 1 end)

        -- Phase says "not in phase" -> map leg dispatched, cascade still UNRESOLVED
        -- because the map callback has not been delivered yet.
        fw.capturedPhaseCallback(false, "targeting", nil, "target")
        T.eq(fw.mapScanCount, 1, "sanity: first delivery dispatches a map scan")
        T.eq(calls, 0, "sanity: cascade is still in flight, not yet resolved")

        -- Duplicate arrives while still in flight. Without the guard this re-runs the whole
        -- body and dispatches a SECOND map scan (RunMapCheck's own mapCheckStarted flag is
        -- the only thing that would stop it, so this pins that the phase side bails first).
        fw.capturedPhaseCallback(false, "targeting", nil, "target")
        T.eq(fw.mapScanCount, 1, "a repeat phase result must be discarded, not re-run")
        T.eq(calls, 0, "and must not resolve the cascade early")

        -- The real map result still lands correctly afterwards.
        fw.capturedMapCallback(false, "no_match", nil)
        T.eq(calls, 1, "the genuine map result still resolves the cascade exactly once")
    end)

    T.it("BUG (fixed): a mid-flight duplicate cannot flip a pending block into an allow", function()
        mock.setClock(1000)
        local fw = freshFW()

        local allowed, resolved
        fw:CheckLocationCascading("Bob", 1, function(ok) resolved = true; allowed = ok end)

        -- First delivery: NOT in phase. Map leg dispatched; cascade still unresolved.
        fw.capturedPhaseCallback(false, "targeting", nil, "target")
        T.falsy(resolved, "sanity: cascade is still in flight")

        -- A contradictory duplicate arrives before the map leg returns. Without the guard
        -- this overwrites phaseCheck to true; EvaluateResults' `phaseCheck == true` override
        -- would then clear the alerts and turn the pending block into an ALLOW.
        fw.capturedPhaseCallback(true, "targeting", nil, "target")

        -- Map also says no. With phase=false and map=false the cascade must block.
        fw.capturedMapCallback(false, "no_match", nil)

        T.truthy(resolved, "the genuine map result resolves the cascade")
        T.falsy(allowed, "a contradictory mid-flight duplicate must not flip a block into an allow")
    end)

    T.it("a contradictory late duplicate does not flip an already-resolved allow", function()
        mock.setClock(1000)
        local fw = freshFW()

        local calls, lastAllowed = 0, nil
        fw:CheckLocationCascading("Bob", 1, function(ok) calls = calls + 1; lastAllowed = ok end)

        -- inPhase=true via a strong method short-circuits the map leg, so this resolves.
        fw.capturedPhaseCallback(true, "targeting", nil, "target")
        T.eq(calls, 1, "sanity: a strong in-phase result resolves the cascade")
        T.truthy(lastAllowed, "sanity: and resolves it as an allow")

        -- A late contradictory duplicate must be discarded, not re-run into a block.
        fw.capturedPhaseCallback(false, "timeout", nil, "timeout")
        T.eq(calls, 1, "the callback must not fire a second time")
        T.truthy(lastAllowed, "the recorded allow must stand")
    end)
end)
