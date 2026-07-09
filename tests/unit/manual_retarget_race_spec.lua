-- tests/unit/manual_retarget_race_spec.lua
-- Headless tests for a race between an in-flight automated phase check and the player
-- manually retargeting someone else during the check window.
--
-- Bug: after a phase check resolves (success, failure, or timeout), the restore logic
-- only compared the target's CURRENT GUID against whatever it was BEFORE the check
-- started. It had no way to tell "the target changed because our own TargetUnit(playerName)
-- succeeded" apart from "the target changed because the player manually /tar'd or clicked
-- someone else during the 1.5-3s check window (or, for a batch, several seconds across
-- several players)". Any change from the pre-check target was blindly restored to the
-- pre-check target (or cleared, if there was none) - silently overwriting a target the
-- player had just chosen on purpose.
--
-- Fix: only restore/clear when the current target is confirmed to be OUR doing - either
-- it's still the check's own subject (individual path) / one of the batch's own targets
-- (batch path), or it never changed at all. Anything else is left alone.

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

local function freshPhase()
    local fw = H.newNamespace()
    fw.Prefs = { phaseCheckBatchMode = false }
    fw.ServiceContainer = { Get = function() return nil end }

    H.loadModule("location/phase.lua", fw)

    fw.hasEpsilonAPI = true
    function fw:IsPhaseCheckEnabled() return true end
    function fw:SanitizePlayerName(n) return n end
    function fw:GetAvailablePrivilegedTokens() return 10 end
    function fw:IsInspectActive() return false end

    _G.C_Map = { GetBestMapForUnit = function() return 1 end }
    return fw
end

T.describe("Manual retarget during an in-flight individual phase check", function()
    T.it("does NOT restore/clear when the player manually retargeted someone else", function()
        mock.setClock(1000)
        local fw = freshPhase()

        -- Before the check: player has "OldTarget" selected.
        _G.UnitExists = function() return true end
        _G.UnitGUID = function() return "Player-0000-OLDTARGET" end
        _G.GetUnitName = function() return "OldTarget" end

        local privilegedCalls = {}
        function fw:RunPrivilegedSafe(code, category)
            table.insert(privilegedCalls, code)
            -- Simulate: our own TargetUnit("Bob") call "succeeds" in the sense that
            -- RunPrivileged didn't error, but the player has ALREADY manually retargeted
            -- to "ManualPick" by the time anything checks the live target state (both the
            -- event fallback and the final restore read UnitGUID/UnitName live).
            _G.UnitGUID = function() return "Player-0000-MANUALPICK" end
            _G.UnitName = function() return "ManualPick" end
            return true
        end

        fw:CheckPlayerPhase("Bob", 1, function() end, "NORMAL")
        mock.advance(1.0)
        fireDueTimers()  -- batch-accumulation timer -> targeting issued
        mock.advance(3.0)
        fireDueTimers()  -- 3.0s NORMAL timeout -> UnitName("target") is "ManualPick", not "Bob" -> handleResult(false, ...)

        for _, code in ipairs(privilegedCalls) do
            T.falsy(code:find("ClearTarget") or code:find("TargetLastTarget") or code:find('TargetUnit%("OldTarget"'),
                "must not restore/clear over a manual retarget - got: " .. code)
        end
    end)

    T.it("DOES restore to the original target when nothing manual interfered", function()
        mock.setClock(1000)
        local fw = freshPhase()

        _G.UnitExists = function() return true end
        _G.UnitGUID = function() return "Player-0000-OLDTARGET" end
        _G.GetUnitName = function() return "OldTarget" end

        local privilegedCalls = {}
        function fw:RunPrivilegedSafe(code, category)
            table.insert(privilegedCalls, code)
            if code:find('TargetUnit%("Bob"') then
                -- Our own call succeeds and IS what's currently selected (no manual interference).
                _G.UnitGUID = function() return "Player-0000-BOB" end
                _G.UnitName = function() return "Bob" end
            end
            return true
        end

        fw:CheckPlayerPhase("Bob", 1, function() end, "NORMAL")
        mock.advance(1.0)
        fireDueTimers()
        mock.advance(3.0)
        fireDueTimers()

        local restoredToOld = false
        for _, code in ipairs(privilegedCalls) do
            if code:find('TargetUnit%("OldTarget"') then restoredToOld = true end
        end
        T.truthy(restoredToOld, "must restore to the pre-check target when the current target is genuinely ours (Bob)")
    end)

    T.it("does NOT clear when the player had no target before but manually targeted someone during the check", function()
        mock.setClock(1000)
        local fw = freshPhase()

        -- No target before the check.
        _G.UnitExists = function() return false end
        _G.UnitGUID = function() return nil end
        _G.GetUnitName = function() return nil end

        local privilegedCalls = {}
        function fw:RunPrivilegedSafe(code, category)
            table.insert(privilegedCalls, code)
            -- After our TargetUnit("Bob") call, the player manually picks someone else.
            _G.UnitExists = function() return true end
            _G.UnitGUID = function() return "Player-0000-MANUALPICK" end
            _G.UnitName = function() return "ManualPick" end
            return true
        end

        fw:CheckPlayerPhase("Bob", 1, function() end, "NORMAL")
        mock.advance(1.0)
        fireDueTimers()
        mock.advance(3.0)
        fireDueTimers()

        for _, code in ipairs(privilegedCalls) do
            T.falsy(code:find("ClearTarget"), "must not clear a manually-chosen target - got: " .. code)
        end
    end)
end)

T.describe("Manual retarget during an in-flight BATCH phase check", function()
    local function freshBatchPhase()
        local fw = freshPhase()
        fw.Prefs.phaseCheckBatchMode = true
        fw.Prefs.phaseCheckBatchSize = 5
        fw.Prefs.privilegedReservedTokens = 2
        return fw
    end

    T.it("does NOT restore when the final target is outside the whole batch's own targets", function()
        mock.setClock(1000)
        local fw = freshBatchPhase()

        _G.UnitExists = function() return true end
        _G.UnitGUID = function() return "Player-0000-OLDTARGET" end
        _G.GetUnitName = function() return "OldTarget" end

        local privilegedCalls = {}
        function fw:RunPrivilegedSafe(code, category)
            table.insert(privilegedCalls, code)
            if category == "phase_restore_target_by_name" or category == "phase_restore_target" or category == "phase_clear_target" then
                return true
            end
            -- Every TargetUnit() during the batch itself "succeeds" but doesn't change
            -- the live target (simulating players who were never actually reachable) -
            -- except the player manually settles on "ManualPick" partway through, which
            -- is never one of the queued players.
            _G.UnitGUID = function() return "Player-0000-MANUALPICK" end
            _G.UnitName = function() return "ManualPick" end
            return true
        end

        fw:QueuePhaseCheck("Alice", 1, function() end, "NORMAL")
        fw:QueuePhaseCheck("Bob", 2, function() end, "NORMAL")
        fw:QueuePhaseCheck("Carol", 3, function() end, "NORMAL")
        fw:ProcessPhaseCheckBatch()

        -- Drive each batch entry's interDelay timer (default 0.1s) through to completion.
        for _ = 1, 10 do
            mock.advance(0.1)
            fireDueTimers()
        end

        for _, code in ipairs(privilegedCalls) do
            T.falsy(code:find('TargetUnit%("OldTarget"') or code:find("ClearTarget"),
                "must not restore/clear over a manual retarget outside this batch's players - got: " .. code)
        end
    end)

    T.it("DOES restore when the final target is one of the batch's own players", function()
        mock.setClock(1000)
        local fw = freshBatchPhase()

        _G.UnitExists = function() return true end
        _G.UnitGUID = function() return "Player-0000-OLDTARGET" end
        _G.GetUnitName = function() return "OldTarget" end

        local privilegedCalls = {}
        function fw:RunPrivilegedSafe(code, category)
            table.insert(privilegedCalls, code)
            if category == "phase_restore_target_by_name" or category == "phase_restore_target" or category == "phase_clear_target" then
                return true
            end
            -- Simulate ending on "Carol" (one of the batch's own players) - e.g. the last
            -- TargetUnit() call in the batch actually landed and nothing manual interfered.
            if code:find('TargetUnit%("Carol"') then
                _G.UnitGUID = function() return "Player-0000-CAROL" end
                _G.UnitName = function() return "Carol" end
            end
            return true
        end

        fw:QueuePhaseCheck("Alice", 1, function() end, "NORMAL")
        fw:QueuePhaseCheck("Bob", 2, function() end, "NORMAL")
        fw:QueuePhaseCheck("Carol", 3, function() end, "NORMAL")
        fw:ProcessPhaseCheckBatch()

        for _ = 1, 10 do
            mock.advance(0.1)
            fireDueTimers()
        end

        local restoredToOld = false
        for _, code in ipairs(privilegedCalls) do
            if code:find('TargetUnit%("OldTarget"') then restoredToOld = true end
        end
        T.truthy(restoredToOld, "must restore to the pre-batch target when ending on one of the batch's own players")
    end)
end)

return T
