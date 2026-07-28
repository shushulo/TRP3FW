-- tests/unit/escaped_name_target_match_spec.lua
-- Regression test: names whose sanitized form differs from the raw name (any name
-- containing a quote or backslash, e.g. "'Grumble'" or "Shi'kala") broke every
-- live-target comparison in the individual phase-check path.
--
-- Root cause: SanitizePlayerName escapes quotes/backslashes so its result is safe to
-- embed in the TargetUnit("...") code string ("'Grumble'" -> "\'Grumble\'", with
-- literal backslash bytes). CheckPlayerPhase sanitizes once and that ESCAPED string is
-- what ExecutePhaseCheck binds as `playerName`. But UnitName("target") returns the raw
-- in-game name, unescaped. So every `UnitName("target") == playerName` comparison
-- compares "\'Grumble\'" against "'Grumble'" and is always false. Two consequences:
--
--   1. The success paths (onTargetChanged, and the timeout fallback) never match, so a
--      player who WAS successfully targeted is reported "timeout"/not-in-phase, and the
--      profile gets blocked.
--   2. manualRetargetDetected is always true, so the restore branch is skipped and the
--      target is left sitting on the check's subject instead of being put back - the
--      "target switches but doesn't switch back" symptom.
--
-- The batch path already unescapes for its cache lookups (see ProcessPhaseCheckBatch's
-- cleanCheckName) and has the same latent bug in its own name comparisons.
--
-- Fix: compare live target names against the UNESCAPED name.

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

-- Loads the REAL SecurityService: a stubbed identity SanitizePlayerName would hide the
-- escaping that causes this bug entirely.
local function freshFW(batchMode)
    local fw = H.newNamespace()
    fw.Prefs = { phaseCheckBatchMode = batchMode, phaseCheckBatchMinSize = 3 }
    fw.hasEpsilonAPI = false
    _G.TRP3FW_ValidatedNames = {}
    H.loadModule("core/Service.lua", fw)
    H.loadModule("core/ServiceContainer.lua", fw)
    H.loadModule("core/cache_interface.lua", fw)
    H.loadModule("features/services/SecurityService.lua", fw)
    H.loadModule("core/utils.lua", fw)
    fw.CacheInterface:Register("phaseCheck", {})
    fw.CacheInterface:Register("whoName", {})
    fw.CacheInterface:Register("sanitizedName", {})
    fw.CacheInterface:Register("cleanName", {})
    fw.CacheInterface:Register("interaction", {})
    fw.CacheInterface:Register("allowedSenders", {})
    fw.hasEpsilonAPI = true

    H.loadModule("location/phase.lua", fw)

    function fw:IsPhaseCheckEnabled() return true end
    function fw:GetAvailablePrivilegedTokens() return 10 end
    function fw:IsInspectActive() return false end

    _G.C_Map = { GetBestMapForUnit = function() return 1 end }
    return fw
end

-- Sanity check that this name really does get escaped; if SanitizePlayerName ever stops
-- escaping, these tests would pass vacuously and must be revisited.
T.describe("Sanitization escapes quoted names (precondition for the tests below)", function()
    T.it("turns 'Grumble' into a string that differs from the raw name", function()
        local fw = freshFW(false)
        local sanitized = fw:SanitizePlayerName("'Grumble'")
        T.not_nil(sanitized, "'Grumble' must be accepted by sanitization")
        T.neq(sanitized, "'Grumble'", "sanitize is expected to escape the quotes")
    end)
end)

T.describe("Quoted name is detected as IN PHASE when targeting succeeds", function()
    T.it("reports success (not timeout) for \"'Grumble'\" once the target lands", function()
        mock.setClock(1000)
        local fw = freshFW(false)

        _G.UnitExists = function() return false end
        _G.UnitGUID = function() return nil end
        _G.GetUnitName = function() return nil end

        function fw:RunPrivilegedSafe(code)
            -- Our TargetUnit() call lands: the live target is now the player, and
            -- UnitName returns the RAW in-game name (no escaping).
            if code:find("TargetUnit") then
                _G.UnitExists = function() return true end
                _G.UnitGUID = function() return "Player-0000-GRUMBLE" end
                _G.UnitName = function() return "'Grumble'" end
            end
            return true
        end

        local result, reason
        fw:CheckPlayerPhase("'Grumble'", 1, function(r, src) result, reason = r, src end, "NORMAL")
        mock.advance(1.0)
        fireDueTimers()
        mock.advance(3.0)
        fireDueTimers()

        T.truthy(result, "successfully-targeted quoted name must be reported IN PHASE, got reason: " .. tostring(reason))
    end)
end)

T.describe("Quoted name restores the previous target after the check", function()
    T.it("restores to the pre-check target instead of leaving it on \"'Grumble'\"", function()
        mock.setClock(1000)
        local fw = freshFW(false)

        _G.UnitExists = function() return true end
        _G.UnitGUID = function() return "Player-0000-OLDTARGET" end
        _G.GetUnitName = function() return "OldTarget" end

        local privilegedCalls = {}
        function fw:RunPrivilegedSafe(code)
            table.insert(privilegedCalls, code)
            if code:find("TargetUnit") and code:find("Grumble") then
                _G.UnitGUID = function() return "Player-0000-GRUMBLE" end
                _G.UnitName = function() return "'Grumble'" end
            end
            return true
        end

        fw:CheckPlayerPhase("'Grumble'", 1, function() end, "NORMAL")
        mock.advance(1.0)
        fireDueTimers()
        mock.advance(3.0)
        fireDueTimers()

        local restoredToOld = false
        for _, code in ipairs(privilegedCalls) do
            if code:find('TargetUnit%("OldTarget"') then restoredToOld = true end
        end
        T.truthy(restoredToOld,
            "must restore the pre-check target - the quoted name is our own target, not a manual retarget")
    end)
end)

T.describe("Quoted name in the batch path", function()
    T.it("reports IN PHASE and restores the pre-batch target", function()
        mock.setClock(1000)
        local fw = freshFW(true)
        fw.Prefs.phaseCheckBatchSize = 5
        fw.Prefs.privilegedReservedTokens = 2

        _G.UnitExists = function() return true end
        _G.UnitGUID = function() return "Player-0000-OLDTARGET" end
        _G.GetUnitName = function() return "OldTarget" end

        local privilegedCalls = {}
        function fw:RunPrivilegedSafe(code, category)
            table.insert(privilegedCalls, code)
            if category == "phase_restore_target_by_name" or category == "phase_restore_target"
                or category == "phase_clear_target" then
                return true
            end
            if code:find("TargetUnit") and code:find("Grumble") then
                _G.UnitGUID = function() return "Player-0000-GRUMBLE" end
                _G.UnitName = function() return "'Grumble'" end
            end
            return true
        end

        local results = {}
        fw:CheckPlayerPhase("'Grumble'", 1, function(r, src) results.grumble = { r, src } end, "NORMAL")
        fw:ProcessPhaseCheckBatch()
        for _ = 1, 10 do
            mock.advance(0.1)
            fireDueTimers()
        end

        T.not_nil(results.grumble, "sanity: the callback fired")
        T.truthy(results.grumble[1],
            "batch path must report the quoted name IN PHASE, got reason: " .. tostring(results.grumble[2]))

        local restoredToOld = false
        for _, code in ipairs(privilegedCalls) do
            if code:find('TargetUnit%("OldTarget"') then restoredToOld = true end
        end
        T.truthy(restoredToOld, "batch path must restore the pre-batch target for a quoted name")
    end)
end)

return T
