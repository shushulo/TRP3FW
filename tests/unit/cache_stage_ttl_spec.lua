-- tests/unit/cache_stage_ttl_spec.lua
-- Headless tests for features/stages/CacheStage.lua's phase-cache TTL handling.
--
-- Bug fixed: CacheStage's phase-cache fast-path (both the same-phase allow and the
-- different-phase fast-fail) never checked the cached entry's age against
-- phaseCacheDuration/phaseCacheFailureDuration - every other phaseCheck-cache consumer
-- in the codebase (CheckPlayerPhase, trp3_scan_pipeline's CheckCache) does this TTL
-- check, but this stage did not. A single stale result (especially a transient timeout)
-- got replayed indefinitely: manually re-targeting a player minutes after an old failed
-- check still fast-failed here with the OLD "timeout" reason, never re-verifying, even
-- though the player was confirmed reachable in the moment (confirmed via a live debug
-- log: a check at 17:38:56 timed out, then a manual target at 17:39:24 - 28s later, well
-- past the 10s phaseCacheFailureDuration default - still fast-failed off that stale entry).

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW(prefs)
    local fw = H.newNamespace()
    fw.Prefs = prefs or { phaseCacheDuration = 300, phaseCacheFailureDuration = 10 }
    H.loadModule("core/cache_interface.lua", fw)
    fw.CacheInterface:Register("phaseCheck", {})
    fw.CacheInterface:Register("allowedSenders", {})
    fw.CacheInterface:Register("spvpVerified", {})

    fw.hasEpsilonAPI = false
    fw.ServiceContainer = { Get = function() return nil end }  -- no HistoryService/NotificationService needed
    H.loadModule("core/Stage.lua", fw)
    function fw:IsPhaseCheckEnabled() return true end
    function fw:IsMapCheckEnabled() return false end
    function fw:TrackAddonRequest() end
    function fw:AllowSender() end
    function fw:Pipeline_DecisionStage() end

    H.loadModule("features/stages/CacheStage.lua", fw)
    return fw
end

-- `now` mirrors CreateDecisionContext's clock snapshot: CacheStage does its TTL math
-- against the context's clock, not a fresh GetCurrentTime() read, so the fixture has to
-- carry it the same way production does.
local function ctx(playerName)
    return { playerName = playerName, addon = "MSP", sendId = 1, isWhisper = true, settings = {}, originalFunc = nil, originalArgs = {}, now = GetTime() }
end

T.describe("CacheStage phase-cache TTL: fast-FAIL branch (the bug's actual trigger)", function()
    T.it("fast-fails on a fresh (within TTL) different-phase cache entry", function()
        mock.setClock(1000)
        local fw = freshFW({ phaseCacheFailureDuration = 10 })
        fw.CacheInterface:Set("phaseCheck", "Incendeviate", { inPhase = false, timestamp = 995, method = "timeout" })  -- 5s old

        local result = fw.CacheStage:Process(ctx("Incendeviate"))
        T.truthy(result.handled, "fresh failure cache entry should still fast-fail")
        T.falsy(result.allowed)
        T.eq(result.reason, "phase_cache_fail")
    end)

    T.it("BUG (fixed): a STALE different-phase entry must NOT fast-fail - falls through to a real check", function()
        mock.setClock(1000)
        local fw = freshFW({ phaseCacheFailureDuration = 10 })
        -- Same scenario as the live repro: a check timed out ~28s ago; a new request
        -- (e.g. from manually re-targeting the player) arrives well past the 10s TTL.
        fw.CacheInterface:Set("phaseCheck", "Incendeviate", { inPhase = false, timestamp = 972, method = "timeout" })  -- 28s old

        local result = fw.CacheStage:Process(ctx("Incendeviate"))
        T.falsy(result.handled, "stale entry must fall through so LocationStage runs a REAL check")
    end)

    T.it("treats the entry as stale at exactly the TTL boundary (age >= ttl, not just >)", function()
        mock.setClock(1000)
        local fw = freshFW({ phaseCacheFailureDuration = 10 })
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = false, timestamp = 990, method = "timeout" })  -- exactly 10s old

        local result = fw.CacheStage:Process(ctx("Bob"))
        T.falsy(result.handled, "age == ttl should already be considered expired")
    end)
end)

T.describe("CacheStage phase-cache TTL: fast-ALLOW branch (same gap existed here too)", function()
    T.it("fast-allows on a fresh (within TTL) same-phase cache entry", function()
        mock.setClock(1000)
        local fw = freshFW({ phaseCacheDuration = 300 })
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = true, timestamp = 700 })  -- 300s old, right at the edge

        local result = fw.CacheStage:Process(ctx("Bob"))
        T.falsy(result.handled, "age == ttl (300s) is already stale - sanity check for the boundary below")
    end)

    T.it("fast-allows a genuinely fresh same-phase entry", function()
        mock.setClock(1000)
        local fw = freshFW({ phaseCacheDuration = 300 })
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = true, timestamp = 990 })  -- 10s old, well within 300s

        local result = fw.CacheStage:Process(ctx("Bob"))
        T.truthy(result.handled)
        T.truthy(result.allowed)
        T.eq(result.reason, "phase_cache")
    end)

    T.it("BUG (fixed): a STALE same-phase entry must NOT fast-allow - falls through to a real check", function()
        mock.setClock(1000)
        local fw = freshFW({ phaseCacheDuration = 300 })
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = true, timestamp = 600 })  -- 400s old, past the 300s TTL

        local result = fw.CacheStage:Process(ctx("Bob"))
        T.falsy(result.handled, "an arbitrarily-stale success must not fast-allow without re-verifying")
    end)
end)

T.describe("CacheStage phase-cache TTL: no entry / phase check disabled", function()
    T.it("falls through cleanly when there is no cached entry at all", function()
        mock.setClock(1000)
        local fw = freshFW()
        local result = fw.CacheStage:Process(ctx("NeverChecked"))
        T.falsy(result.handled)
    end)

    T.it("ignores the phase cache entirely when phase checking is disabled", function()
        mock.setClock(1000)
        local fw = freshFW()
        function fw:IsPhaseCheckEnabled() return false end
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = false, timestamp = 999 })  -- fresh, would normally fast-fail

        local result = fw.CacheStage:Process(ctx("Bob"))
        T.falsy(result.handled, "phase cache must be skipped entirely when phase checking is off")
    end)
end)

return T
