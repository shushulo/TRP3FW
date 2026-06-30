-- tests/wowunit/TRP3FW_Smoke.lua
-- WoWUnit port of the original /trp3fwtest integration cases.
--
-- These are *wiring* smoke tests: they need the real, fully-loaded TRP3FW
-- namespace (services registered, pipeline built, caches created) and assert
-- that it is wired together correctly. They do NOT mock anything -- that is
-- what TRP3FW_Mocked.lua is for.
--
-- WoWUnit auto-runs these at PLAYER_LOGIN and shows results in its panel
-- (minimap-adjacent toggle button, coloured by pass/fail). The legacy
-- /trp3fwtest command still works independently; this just gives the same
-- coverage inside a real framework with a UI.
--
-- Loaded only on the v1.5-tests branch (see tests/WoWUnit + the .toc test
-- block). Never shipped to v1.5/GitHub.

local addonName, TRP3FW = ...

-- WoWUnit is an OptionalDep; bail quietly if the test addon isn't installed so
-- the firewall still loads normally without it.
if not _G.WoWUnit then return end

local AreEqual, IsTrue, IsFalse, Exists =
    WoWUnit.AreEqual, WoWUnit.IsTrue, WoWUnit.IsFalse, WoWUnit.Exists

-- Run at PLAYER_LOGIN (the default) so the full addon + service stack is up.
local Tests = WoWUnit("TRP3FW Smoke")

-- --- Namespace / service wiring ---
function Tests:CoreServicesRegistered()
    Exists(TRP3FW.ServiceContainer:Get("CacheService"))
    Exists(TRP3FW.ServiceContainer:Get("HistoryService"))
    Exists(TRP3FW.ServiceContainer:Get("NotificationService"))
    Exists(TRP3FW.ServiceContainer:Get("SecurityService"))
    Exists(TRP3FW.ServiceContainer:Get("WhoService"))
end

function Tests:DecisionPipelineHasStages()
    Exists(TRP3FW.DecisionPipeline)
    IsTrue(#TRP3FW.DecisionPipeline.stages > 0)
end

-- --- Cache registration (regression for the spvpSessions fix) ---
-- A registered cache returns (nil, "miss"); an unregistered one returns
-- (nil, "unknown_cache"). This is exactly the spvpSessions bug guard.
function Tests:AllCachesRegistered()
    local CI = TRP3FW.CacheInterface
    for _, name in ipairs({
        "allowedSenders", "interaction", "phaseCheck", "whoName", "whoZone",
        "mapScan", "broadcast", "spvpVerified", "spvpPhaseSalt", "spvpSessions",
        "cleanName", "sanitizedName", "mapName",
    }) do
        local _, reason = CI:Get(name, "____nonexistent_key____")
        IsTrue(reason ~= "unknown_cache")  -- cache must be registered
    end
end

-- --- SPVP replay protection actually stores (fix #1) ---
function Tests:SpvpSessionsCacheRoundTrips()
    local CI = TRP3FW.CacheInterface
    AreEqual(true, CI:Set("spvpSessions", "__wu_session__", { t = 1 }))
    Exists(CI:Get("spvpSessions", "__wu_session__"))
    CI:Remove("spvpSessions", "__wu_session__")
end

-- --- Ghost flag lifecycle (fix #10 depends on this) ---
function Tests:GhostFlagRoundTrips()
    local target = "__WuGhostTarget__"
    TRP3FW:EnableGhostForNextSend(target, nil)
    IsTrue(TRP3FW:ShouldGhostSendTo(target))            -- active after enable
    IsFalse(TRP3FW:ShouldGhostSendTo("__SomeoneElse__")) -- only matches target
    TRP3FW:ClearGhostFlag(target)
    IsFalse(TRP3FW:ShouldGhostSendTo(target))            -- cleared
end

-- --- Name sanitization in the live environment ---
function Tests:SanitizePlayerNameLive()
    local svc = TRP3FW.ServiceContainer:Get("SecurityService")
    Exists(svc:SanitizePlayerName("Bob"))           -- plain name ok
    AreEqual(nil, svc:SanitizePlayerName("Bob2"))   -- digit name rejected
end

-- --- Minimap reset exists and runs (fix #13) ---
function Tests:ResetMinimapButtonRuns()
    Exists(TRP3FW.ResetMinimapButton)
    TRP3FW:ResetMinimapButton()  -- must not raise
    IsTrue(true)
end

-- --- Per-type block/ghost stat fields exist (fix #14) ---
function Tests:PerTypeStatFieldsExist()
    local s = TRP3FW.sessionStats
    for _, k in ipairs({ "phaseBlocks", "mapBlocks", "phaseGhost", "mapGhost", "startPhaseGhost" }) do
        Exists(s[k])
    end
end

-- --- Whitelist round-trip ---
-- Restores Prefs by hand because these are persistent settings, not WoWUnit
-- Replaces (Replace would be auto-reverted, but we are mutating saved Prefs).
function Tests:WhitelistRoundTrips()
    local savedEntries  = TRP3FW.Prefs.whitelistEntries
    local savedEnabled  = TRP3FW.Prefs.whitelistEnabled

    TRP3FW.Prefs.whitelistEnabled = true
    TRP3FW.Prefs.whitelistEntries = "Testwhitelistname"
    TRP3FW:RefreshWhitelistCache()
    IsTrue(TRP3FW:IsPlayerWhitelisted("Testwhitelistname"))  -- listed matches
    IsFalse(TRP3FW:IsPlayerWhitelisted("Randomother"))       -- non-listed does not

    TRP3FW.Prefs.whitelistEntries = savedEntries
    TRP3FW.Prefs.whitelistEnabled = savedEnabled
    TRP3FW:RefreshWhitelistCache()
end
