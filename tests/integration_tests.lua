-- tests/integration_tests.lua
-- In-game integration tests for TRP3FW. These exercise code paths that need
-- the real WoW environment (frames, C_Timer, the live TRP3FW namespace) and
-- cannot run headless.
--
-- Run in-game with:  /trp3fwtest
-- Output goes to the default chat frame. Safe to run anytime; tests are
-- read-only / self-cleaning and do not send addon messages to other players.
--
-- This file is loaded by the .toc. It adds the /trp3fwtest command and does
-- nothing until invoked.

local addonName, TRP3FW = ...

local IT = { passed = 0, failed = 0, failures = {} }

local function color(hex, s) return "|cff" .. hex .. s .. "|r" end

local function it(name, fn)
    local ok, err = pcall(fn)
    if ok then
        IT.passed = IT.passed + 1
    else
        IT.failed = IT.failed + 1
        table.insert(IT.failures, { name = name, err = err })
    end
end

-- Assertions (kept local; mirror the headless framework's names)
local function eq(a, b, msg)
    if a ~= b then error((msg or "not equal") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "expected truthy", 2) end end
local function falsy(v, msg) if v then error(msg or "expected falsy", 2) end end
local function not_nil(v, msg) if v == nil then error(msg or "expected non-nil", 2) end end
local function no_raise(fn, msg)
    local ok, err = pcall(fn)
    if not ok then error((msg or "unexpected error") .. ": " .. tostring(err), 2) end
end

-- ===================== Tests =====================

local function runAll()
    IT.passed, IT.failed, IT.failures = 0, 0, {}

    -- --- Namespace / service wiring ---
    it("core services are registered", function()
        not_nil(TRP3FW.ServiceContainer:Get("CacheService"), "CacheService")
        not_nil(TRP3FW.ServiceContainer:Get("HistoryService"), "HistoryService")
        not_nil(TRP3FW.ServiceContainer:Get("NotificationService"), "NotificationService")
        not_nil(TRP3FW.ServiceContainer:Get("SecurityService"), "SecurityService")
        not_nil(TRP3FW.ServiceContainer:Get("WhoService"), "WhoService")
    end)

    it("decision pipeline is initialized with stages", function()
        not_nil(TRP3FW.DecisionPipeline, "DecisionPipeline exists")
        truthy(#TRP3FW.DecisionPipeline.stages > 0, "has stages")
    end)

    -- --- Cache registration (regression for the spvpSessions fix) ---
    it("all caches used by the code are registered", function()
        local CI = TRP3FW.CacheInterface
        for _, name in ipairs({
            "allowedSenders", "interaction", "phaseCheck", "whoName", "whoZone",
            "mapScan", "broadcast", "spvpVerified", "spvpPhaseSalt", "spvpSessions",
            "cleanName", "sanitizedName", "mapName",
        }) do
            -- A registered cache returns (nil, "miss"); an unregistered one returns
            -- (nil, "unknown_cache"). This is exactly the spvpSessions bug guard.
            local _, reason = CI:Get(name, "____nonexistent_key____")
            truthy(reason ~= "unknown_cache", "cache not registered: " .. name)
        end
    end)

    -- --- SPVP replay protection actually stores now (fix #1) ---
    it("spvpSessions cache stores and round-trips", function()
        local CI = TRP3FW.CacheInterface
        eq(CI:Set("spvpSessions", "__test_session__", { t = 1 }), true, "Set succeeds")
        not_nil(CI:Get("spvpSessions", "__test_session__"), "round-trips")
        CI:Remove("spvpSessions", "__test_session__")
    end)

    -- --- Ghost flag lifecycle (fix #10 depends on this working) ---
    it("ghost flag set / query / clear round-trips", function()
        local target = "__GhostTestTarget__"
        TRP3FW:EnableGhostForNextSend(target, nil)
        truthy(TRP3FW:ShouldGhostSendTo(target), "flag active after enable")
        falsy(TRP3FW:ShouldGhostSendTo("__SomeoneElse__"), "only matches target")
        TRP3FW:ClearGhostFlag(target)
        falsy(TRP3FW:ShouldGhostSendTo(target), "cleared")
    end)

    -- --- Name sanitization in the live environment ---
    it("SanitizePlayerName rejects digits, accepts plain names (live)", function()
        local svc = TRP3FW.ServiceContainer:Get("SecurityService")
        not_nil(svc:SanitizePlayerName("Bob"), "plain name ok")
        eq(svc:SanitizePlayerName("Bob2"), nil, "digit name rejected")
    end)

    -- --- Minimap reset exists and runs (fix #13) ---
    it("ResetMinimapButton is defined and runs without error", function()
        not_nil(TRP3FW.ResetMinimapButton, "function exists")
        no_raise(function() TRP3FW:ResetMinimapButton() end)
    end)

    -- --- Stats fields exist (fix #14) ---
    it("per-type block/ghost stat fields exist", function()
        local s = TRP3FW.sessionStats
        for _, k in ipairs({ "phaseBlocks", "mapBlocks", "phaseGhost", "mapGhost", "startPhaseGhost" }) do
            not_nil(s[k], "sessionStats." .. k)
        end
    end)

    -- --- Whitelist round-trip ---
    it("whitelist add/check/clear works", function()
        local saved = TRP3FW.Prefs.whitelistEntries
        local savedEnabled = TRP3FW.Prefs.whitelistEnabled
        TRP3FW.Prefs.whitelistEnabled = true
        TRP3FW.Prefs.whitelistEntries = "Testwhitelistname"
        TRP3FW:RefreshWhitelistCache()
        truthy(TRP3FW:IsPlayerWhitelisted("Testwhitelistname"), "listed player matches")
        falsy(TRP3FW:IsPlayerWhitelisted("Randomother"), "non-listed does not match")
        TRP3FW.Prefs.whitelistEntries = saved
        TRP3FW.Prefs.whitelistEnabled = savedEnabled
        TRP3FW:RefreshWhitelistCache()
    end)

    -- --- Report ---
    local total = IT.passed + IT.failed
    print(color("00ffff", "=== TRP3FW Integration Tests ==="))
    if IT.failed > 0 then
        for _, f in ipairs(IT.failures) do
            print(color("ff0000", "[FAIL] ") .. f.name)
            print("       " .. tostring(f.err))
        end
    end
    local summary = string.format("Passed: %d / %d", IT.passed, total)
    print(IT.failed == 0 and color("00ff00", summary .. "  ALL PASS") or color("ff0000", summary))
end

-- Register the slash command (separate from /trp3fw so it can't be triggered by accident)
SLASH_TRP3FWTEST1 = "/trp3fwtest"
SlashCmdList["TRP3FWTEST"] = function()
    runAll()
end

TRP3FW.RunIntegrationTests = runAll
