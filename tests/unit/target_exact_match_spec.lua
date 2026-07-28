-- tests/unit/target_exact_match_spec.lua
-- Regression test: the phase check's TargetUnit() calls must request an EXACT name match.
--
-- TargetUnit's real signature is TargetUnit([name, exactMatch]), and exactMatch DEFAULTS
-- TO FALSE - i.e. partial matching. Calling TargetUnit("Grumble") with one argument could
-- therefore select "Grumblesnout" or "Grumble'thok" instead of the player "Grumble".
-- Combined with proximity-based selection (WoW picks the closest match, with no
-- player-vs-NPC priority), a nearby mob with a superstring name could satisfy - or
-- silently derail - a phase check for a player who was never there.
--
-- Passing exactMatch=true removes that entire class of collision. It does NOT filter
-- NPCs (Epsilon's own SpellCreator documents exactMatch purely as name matching: their
-- example is "Bear" vs "Brown Bear"), so the UnitIsPlayer guard in phase.lua is still
-- required and is tested separately in npc_name_collision_spec.
--
-- NOTE: the RESTORE calls deliberately do NOT pass exactMatch. They target
-- previousTargetName, captured via GetUnitName(unit, true), which carries a realm suffix
-- ("Name-Realm"). Forcing an exact match on that form risks failing the restore outright,
-- which is the stranded-target symptom this module was just fixed for.

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

-- The targeting call for a phase check: TargetUnit("<name>", ...) issued under one of the
-- phase_check_target* categories. Restores use their own distinct categories.
local function findCheckTargetCall(calls)
    for _, c in ipairs(calls) do
        if c.category and c.category:find("^phase_check_target") then return c.code end
    end
    return nil
end

T.describe("Phase check targeting requests an exact name match", function()
    T.it("passes exactMatch=true on the individual path", function()
        mock.setClock(1000)
        local fw = freshFW(false)

        _G.UnitExists = function() return false end
        _G.UnitGUID = function() return nil end
        _G.GetUnitName = function() return nil end

        local calls = {}
        function fw:RunPrivilegedSafe(code, category)
            table.insert(calls, { code = code, category = category })
            return true
        end

        fw:CheckPlayerPhase("Grumble", 1, function() end, "NORMAL")
        mock.advance(1.0)
        fireDueTimers()

        local code = findCheckTargetCall(calls)
        T.not_nil(code, "sanity: a phase-check targeting call was issued")
        T.truthy(code:find("true", 1, true),
            "TargetUnit must request an exact match, otherwise 'Grumble' can match 'Grumblesnout' - got: " .. tostring(code))
    end)

    T.it("passes exactMatch=true on the batch path", function()
        mock.setClock(1000)
        local fw = freshFW(true)
        fw.Prefs.phaseCheckBatchSize = 5
        fw.Prefs.privilegedReservedTokens = 2

        _G.UnitExists = function() return false end
        _G.UnitGUID = function() return nil end
        _G.GetUnitName = function() return nil end

        local calls = {}
        function fw:RunPrivilegedSafe(code, category)
            table.insert(calls, { code = code, category = category })
            return true
        end

        fw:CheckPlayerPhase("Grumble", 1, function() end, "NORMAL")
        fw:ProcessPhaseCheckBatch()
        mock.advance(0.2)
        fireDueTimers()

        local code = findCheckTargetCall(calls)
        T.not_nil(code, "sanity: a batch targeting call was issued")
        T.truthy(code:find("true", 1, true),
            "batch TargetUnit must request an exact match - got: " .. tostring(code))
    end)

    T.it("still quotes and escapes the name correctly alongside the new argument", function()
        mock.setClock(1000)
        local fw = freshFW(false)

        _G.UnitExists = function() return false end
        _G.UnitGUID = function() return nil end
        _G.GetUnitName = function() return nil end

        local calls = {}
        function fw:RunPrivilegedSafe(code, category)
            table.insert(calls, { code = code, category = category })
            return true
        end

        fw:CheckPlayerPhase("Shi'kala", 1, function() end, "NORMAL")
        mock.advance(1.0)
        fireDueTimers()

        local code = findCheckTargetCall(calls)
        T.not_nil(code, "sanity: a targeting call was issued")
        -- The name must still be a quoted first argument, with exactMatch as a separate
        -- second argument - not accidentally concatenated into the name string.
        T.truthy(code:find('^TargetUnit%("'),
            "name must remain the quoted first argument - got: " .. tostring(code))
        T.truthy(code:find('",%s*true%)$'),
            "exactMatch must be a separate second argument - got: " .. tostring(code))
    end)
end)

T.describe("Target restore does NOT force an exact match", function()
    T.it("omits exactMatch when restoring the pre-check target", function()
        mock.setClock(1000)
        local fw = freshFW(false)

        -- Pre-check target, captured with realm suffix by GetUnitName(unit, true).
        _G.UnitExists = function() return true end
        _G.UnitGUID = function() return "Player-0000-OLDTARGET" end
        _G.GetUnitName = function() return "OldTarget-SomeRealm" end
        _G.UnitIsPlayer = function() return true end

        local calls = {}
        function fw:RunPrivilegedSafe(code, category)
            table.insert(calls, { code = code, category = category })
            if code:find("TargetUnit") and code:find("Grumble") then
                _G.UnitGUID = function() return "Player-0000-GRUMBLE" end
                _G.UnitName = function() return "Grumble" end
            end
            return true
        end

        fw:CheckPlayerPhase("Grumble", 1, function() end, "NORMAL")
        mock.advance(1.0)
        fireDueTimers()
        mock.advance(3.0)
        fireDueTimers()

        local restoreCode
        for _, c in ipairs(calls) do
            if c.category == "phase_restore_target_by_name" then restoreCode = c.code end
        end

        T.not_nil(restoreCode, "sanity: a restore-by-name call was issued")
        T.falsy(restoreCode:find("true", 1, true),
            "restore must not force an exact match on a realm-suffixed name - got: " .. tostring(restoreCode))
    end)
end)

return T
