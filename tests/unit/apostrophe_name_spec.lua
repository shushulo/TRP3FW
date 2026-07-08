-- tests/unit/apostrophe_name_spec.lua
-- Regression test: apostrophe-containing player names (e.g. "Shi'kala") used to be
-- rejected with "invalid_name" partway through phase checking, even though
-- SanitizePlayerName("Shi'kala") succeeds on its own.
--
-- Root cause: SanitizePlayerName escapes quotes/backslashes in its return value so the
-- result is safe to embed in the TargetUnit("...") code string passed to RunPrivileged
-- (e.g. "Shi'kala" -> "Shi\'kala", with a literal backslash byte). CheckPlayerPhase
-- sanitizes once and queues that escaped name. ProcessPhaseCheckBatch/ExecutePhaseCheck
-- used to re-sanitize check.playerName a SECOND time before targeting - but the sanitize
-- pattern has no backslash in its accepted character class, so re-sanitizing the
-- already-escaped "Shi\'kala" always failed, rejecting every apostrophe name.
-- Fix: check.playerName is already sanitized: use it directly, don't re-sanitize.
--
-- These tests load the REAL SecurityService (not an identity-stub), since a stubbed
-- SanitizePlayerName would trivially "pass" this test whether or not the underlying bug
-- was fixed.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function fireDueTimers()
    local due, kept = {}, {}
    for _, t in ipairs(mock.timers) do
        if not t.cancelled and mock.clock >= t.at then due[#due + 1] = t else kept[#kept + 1] = t end
    end
    mock.timers = kept
    for _, t in ipairs(due) do t.fn() end
    return #due
end

local function freshFW(batchMode)
    local fw = H.newNamespace()
    fw.Prefs = { phaseCheckBatchMode = batchMode, phaseCheckBatchMinSize = 3 }
    fw.hasEpsilonAPI = false
    _G.TRP3FW_ValidatedNames = {}
    H.loadModule("core/Service.lua", fw)
    H.loadModule("core/ServiceContainer.lua", fw)
    H.loadModule("core/cache_interface.lua", fw)
    H.loadModule("features/services/SecurityService.lua", fw)
    H.loadModule("core/utils.lua", fw)  -- defines the TRP3FW:SanitizePlayerName delegating wrapper
    fw.CacheInterface:Register("phaseCheck", {})
    fw.CacheInterface:Register("whoName", {})
    fw.CacheInterface:Register("sanitizedName", {})
    fw.CacheInterface:Register("cleanName", {})
    fw.hasEpsilonAPI = true

    H.loadModule("location/phase.lua", fw)

    function fw:IsPhaseCheckEnabled() return true end
    function fw:GetAvailablePrivilegedTokens() return 10 end
    function fw:IsInspectActive() return false end

    _G.UnitExists = function() return false end
    _G.UnitGUID = function() return "Player-0000-00000000" end
    _G.GetUnitName = function() return nil end
    _G.C_Map = { GetBestMapForUnit = function() return 1 end }

    return fw
end

T.describe("Apostrophe names survive real SanitizePlayerName through the queue (individual path)", function()
    T.it("does not reject \"Shi'kala\" with invalid_name", function()
        mock.setClock(1000)
        local fw = freshFW(false)
        function fw:RunPrivilegedSafe() return true end  -- targeting call succeeds

        local result, reason
        fw:CheckPlayerPhase("Shi'kala", 1, function(r, src) result, reason = r, src end, "NORMAL")

        mock.advance(1.0)
        fireDueTimers()  -- batch-accumulation delay -> processing starts
        mock.advance(3.0)
        fireDueTimers()  -- 3.0s NORMAL timeout -> resolves via manual fallback check

        T.neq(reason, "invalid_name", "apostrophe name must not be rejected as invalid")
    end)
end)

T.describe("Apostrophe names survive real SanitizePlayerName through the batch path", function()
    T.it("does not reject \"Shi'kala\" with invalid_name when batched with others", function()
        mock.setClock(1000)
        local fw = freshFW(true)
        function fw:RunPrivilegedSafe() return true end

        local results = {}
        fw:CheckPlayerPhase("Shi'kala", 1, function(r, src) results.shikala = { r, src } end, "NORMAL")
        fw:CheckPlayerPhase("Plainbob", 2, function(r, src) results.bob = { r, src } end, "NORMAL")
        fw:CheckPlayerPhase("Otherguy", 3, function(r, src) results.other = { r, src } end, "NORMAL")

        -- Drive the batch to completion: process the batch, then let its per-entry
        -- interDelay timer (default 0.1s) fire so finishStep actually delivers results.
        fw:ProcessPhaseCheckBatch()
        mock.advance(0.2)
        fireDueTimers()

        T.not_nil(results.shikala, "sanity: Shi'kala's callback fired")
        T.neq(results.shikala[2], "invalid_name", "apostrophe name must not be rejected as invalid in the batch path")
    end)
end)

return T
