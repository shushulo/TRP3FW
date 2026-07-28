-- tests/unit/npc_name_collision_spec.lua
-- Regression test: TargetUnit("Name") matches NPCs as well as players, and WoW will
-- happily select a nearby NPC that shares a name with the player we're checking.
--
-- Bug: the phase check verified the result by NAME only (UnitName("target") == name).
-- An NPC named "Grumble" standing next to you therefore satisfied the check's success
-- condition, so:
--
--   1. The check reported IN PHASE based on an NPC, even when the actual player was
--      nowhere near (a false allow), OR - depending on which branch resolved first -
--      failed while still believing the NPC was "our" target.
--   2. The restore logic's isOneOfOurTargets/manualRetargetDetected test is also
--      name-only, so an NPC target was classified as "ours"... but the phase result
--      itself was driven by the same bad match, leaving the player stuck on the NPC.
--
-- Fix: every live-target verification must also confirm the unit is a PLAYER
-- (UnitIsPlayer("target")), not just that the name matches.
--
-- These tests use the REAL SecurityService so the escaping behavior is exercised too.

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

-- Simulates TargetUnit() landing on an NPC that shares the player's name.
local function targetBecomesNPC(name)
    _G.UnitExists = function() return true end
    _G.UnitGUID = function() return "Creature-0-1234-5678-9012-0815-000012345678" end
    _G.UnitName = function() return name end
    _G.UnitIsPlayer = function() return false end
end

local function targetBecomesPlayer(name)
    _G.UnitExists = function() return true end
    _G.UnitGUID = function() return "Player-0000-GRUMBLE" end
    _G.UnitName = function() return name end
    _G.UnitIsPlayer = function() return true end
end

T.describe("NPC sharing the checked player's name (individual path)", function()
    T.it("does NOT report IN PHASE when only a same-named NPC was targeted", function()
        mock.setClock(1000)
        local fw = freshFW(false)

        _G.UnitExists = function() return false end
        _G.UnitGUID = function() return nil end
        _G.GetUnitName = function() return nil end
        _G.UnitIsPlayer = function() return false end

        function fw:RunPrivilegedSafe(code)
            if code:find("TargetUnit") and code:find("Grumble") then
                targetBecomesNPC("Grumble")
            end
            return true
        end

        local result, reason
        fw:CheckPlayerPhase("Grumble", 1, function(r, src) result, reason = r, src end, "NORMAL")
        mock.advance(1.0)
        fireDueTimers()
        mock.advance(3.0)
        fireDueTimers()

        T.falsy(result,
            "an NPC must not satisfy the phase check - that is a false allow (reason: " .. tostring(reason) .. ")")
    end)

    T.it("still reports IN PHASE for a real player of the same name", function()
        mock.setClock(1000)
        local fw = freshFW(false)

        _G.UnitExists = function() return false end
        _G.UnitGUID = function() return nil end
        _G.GetUnitName = function() return nil end
        _G.UnitIsPlayer = function() return false end

        function fw:RunPrivilegedSafe(code)
            if code:find("TargetUnit") and code:find("Grumble") then
                targetBecomesPlayer("Grumble")
            end
            return true
        end

        local result
        fw:CheckPlayerPhase("Grumble", 1, function(r) result = r end, "NORMAL")
        mock.advance(1.0)
        fireDueTimers()
        mock.advance(3.0)
        fireDueTimers()

        T.truthy(result, "a genuine player target must still pass the check")
    end)

    T.it("restores the previous target after landing on a same-named NPC", function()
        mock.setClock(1000)
        local fw = freshFW(false)

        _G.UnitExists = function() return true end
        _G.UnitGUID = function() return "Player-0000-OLDTARGET" end
        _G.GetUnitName = function() return "OldTarget" end
        _G.UnitIsPlayer = function() return true end

        local privilegedCalls = {}
        function fw:RunPrivilegedSafe(code)
            table.insert(privilegedCalls, code)
            if code:find("TargetUnit") and code:find("Grumble") then
                targetBecomesNPC("Grumble")
            end
            return true
        end

        fw:CheckPlayerPhase("Grumble", 1, function() end, "NORMAL")
        mock.advance(1.0)
        fireDueTimers()
        mock.advance(3.0)
        fireDueTimers()

        local restoredToOld = false
        for _, code in ipairs(privilegedCalls) do
            if code:find('TargetUnit%("OldTarget"') then restoredToOld = true end
        end
        T.truthy(restoredToOld,
            "the NPC was selected by OUR TargetUnit() call, so it must be cleaned up and the real target restored")
    end)

    T.it("clears the NPC target when there was no target before the check", function()
        mock.setClock(1000)
        local fw = freshFW(false)

        _G.UnitExists = function() return false end
        _G.UnitGUID = function() return nil end
        _G.GetUnitName = function() return nil end
        _G.UnitIsPlayer = function() return false end

        local privilegedCalls = {}
        function fw:RunPrivilegedSafe(code)
            table.insert(privilegedCalls, code)
            if code:find("TargetUnit") and code:find("Grumble") then
                targetBecomesNPC("Grumble")
            end
            return true
        end

        fw:CheckPlayerPhase("Grumble", 1, function() end, "NORMAL")
        mock.advance(1.0)
        fireDueTimers()
        mock.advance(3.0)
        fireDueTimers()

        local cleared = false
        for _, code in ipairs(privilegedCalls) do
            if code:find("ClearTarget") then cleared = true end
        end
        T.truthy(cleared, "an NPC we targeted ourselves must be cleared, not left selected")
    end)
end)

T.describe("NPC sharing the checked player's name (batch path)", function()
    T.it("does NOT report IN PHASE and restores the pre-batch target", function()
        mock.setClock(1000)
        local fw = freshFW(true)
        fw.Prefs.phaseCheckBatchSize = 5
        fw.Prefs.privilegedReservedTokens = 2

        _G.UnitExists = function() return true end
        _G.UnitGUID = function() return "Player-0000-OLDTARGET" end
        _G.GetUnitName = function() return "OldTarget" end
        _G.UnitIsPlayer = function() return true end

        local privilegedCalls = {}
        function fw:RunPrivilegedSafe(code, category)
            table.insert(privilegedCalls, code)
            if category == "phase_restore_target_by_name" or category == "phase_restore_target"
                or category == "phase_clear_target" then
                return true
            end
            if code:find("TargetUnit") and code:find("Grumble") then
                targetBecomesNPC("Grumble")
            end
            return true
        end

        local results = {}
        fw:CheckPlayerPhase("Grumble", 1, function(r, src) results.grumble = { r, src } end, "NORMAL")
        fw:ProcessPhaseCheckBatch()
        for _ = 1, 10 do
            mock.advance(0.1)
            fireDueTimers()
        end

        T.not_nil(results.grumble, "sanity: the callback fired")
        T.falsy(results.grumble[1],
            "batch path must not accept an NPC as the player (reason: " .. tostring(results.grumble[2]) .. ")")

        local restoredToOld = false
        for _, code in ipairs(privilegedCalls) do
            if code:find('TargetUnit%("OldTarget"') then restoredToOld = true end
        end
        T.truthy(restoredToOld, "batch path must restore the pre-batch target after landing on an NPC")
    end)
end)

return T
