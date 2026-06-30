-- tests/unit/start_phase_spec.lua
-- Headless tests for TRP3FW:ShouldBlockForStartPhase (features/ghostmode.lua).
-- This is the start-phase (phase 169) allow/block/ghost decision. It's pure
-- branching over Prefs, the whitelist, the profile-switch override, the Epsilon
-- API flag, and the cached phase ID. The function returns (shouldBlock, action)
-- where action is "ghost", "block", or nil.

local T = require("tests.framework")
local H = require("tests.harness")

-- ShouldBlockForStartPhase depends on IsPlayerWhitelisted + GetCachedPhaseID, both
-- defined in core/utils.lua, so load that alongside ghostmode.lua. The whitelist
-- path also routes player names through SecurityService:SanitizePlayerName, so the
-- service stack is loaded too (otherwise whitelist lookups silently resolve to nil).
local function newFW(prefs)
    local fw = H.newNamespace()
    fw.Prefs = prefs or {}
    fw.hasEpsilonAPI = false  -- SecurityService reads this at load; flip on after.
    _G.TRP3FW_ValidatedNames = {}
    H.loadModule("core/Service.lua", fw)
    H.loadModule("core/ServiceContainer.lua", fw)
    H.loadModule("core/cache_interface.lua", fw)
    H.loadModule("features/services/SecurityService.lua", fw)
    H.loadModule("core/utils.lua", fw)
    H.loadModule("features/ghostmode.lua", fw)
    fw.hasEpsilonAPI = true
    fw.PHASE_CACHE_TTL = 1
    return fw
end

-- Force GetCachedPhaseID to return a specific phase without hitting the API by
-- pre-seeding the cache fields it reads (time()-based TTL from mock_wow).
local function setPhase(fw, phaseID)
    fw.cachedPhaseID = phaseID
    fw.cachedPhaseTimestamp = _G.time()  -- fresh -> cache hit, no API call
end

T.describe("ShouldBlockForStartPhase whitelist + gating", function()
    T.it("whitelisted players are never blocked", function()
        local fw = newFW({ whitelistEnabled = true, whitelistEntries = "Bob",
                           blockStartPhase = true, ghostOnStartPhase = true })
        setPhase(fw, 169)
        local block, action = fw:ShouldBlockForStartPhase("Bob", true)
        T.falsy(block)
        T.is_nil(action)
    end)

    T.it("non-profile sends are not blocked", function()
        local fw = newFW({ blockStartPhase = true })
        setPhase(fw, 169)
        local block = fw:ShouldBlockForStartPhase("Stranger", false)  -- isProfileSend = false
        T.falsy(block)
    end)

    T.it("does nothing when neither block nor ghost is enabled", function()
        local fw = newFW({ blockStartPhase = false, ghostOnStartPhase = false })
        setPhase(fw, 169)
        local block = fw:ShouldBlockForStartPhase("Stranger", true)
        T.falsy(block)
    end)

    T.it("a profile-switch override short-circuits the check", function()
        local fw = newFW({ blockStartPhase = true })
        setPhase(fw, 169)
        fw.IsProfileSwitchOverrideActive = function() return true end
        local block = fw:ShouldBlockForStartPhase("Stranger", true)
        T.falsy(block, "override should skip block/ghost")
    end)

    T.it("bails when the Epsilon API is unavailable", function()
        local fw = newFW({ blockStartPhase = true })
        fw.hasEpsilonAPI = false
        local block = fw:ShouldBlockForStartPhase("Stranger", true)
        T.falsy(block)
    end)
end)

T.describe("ShouldBlockForStartPhase phase decision", function()
    T.it("allows when not in phase 169", function()
        local fw = newFW({ blockStartPhase = true, ghostOnStartPhase = true })
        fw.hasTRP3ExchangeHooks = true
        setPhase(fw, 170)  -- some other phase
        local block, action = fw:ShouldBlockForStartPhase("Stranger", true)
        T.falsy(block)
        T.is_nil(action)
    end)

    T.it("blocks in phase 169 when only blockStartPhase is set", function()
        local fw = newFW({ blockStartPhase = true, ghostOnStartPhase = false })
        setPhase(fw, 169)
        local block, action = fw:ShouldBlockForStartPhase("Stranger", true)
        T.truthy(block)
        T.eq(action, "block")
    end)

    T.it("ghosts in phase 169 when ghost is enabled and exchange hooks exist", function()
        local fw = newFW({ blockStartPhase = true, ghostOnStartPhase = true })
        fw.hasTRP3ExchangeHooks = true  -- ghost requires an exchange hook
        setPhase(fw, 169)
        local block, action = fw:ShouldBlockForStartPhase("Stranger", true)
        T.truthy(block)
        T.eq(action, "ghost", "ghost takes priority over block when hooks are present")
    end)

    T.it("MSP exchange hooks also satisfy the ghost requirement", function()
        local fw = newFW({ ghostOnStartPhase = true })
        fw.hasMSPExchangeHooks = true
        setPhase(fw, 169)
        local block, action = fw:ShouldBlockForStartPhase("Stranger", true)
        T.truthy(block)
        T.eq(action, "ghost")
    end)

    T.it("falls back to block when ghost is set but no exchange hooks exist", function()
        local fw = newFW({ blockStartPhase = true, ghostOnStartPhase = true })
        -- no hasTRP3ExchangeHooks / hasMSPExchangeHooks
        setPhase(fw, 169)
        local block, action = fw:ShouldBlockForStartPhase("Stranger", true)
        T.truthy(block)
        T.eq(action, "block", "ghost wanted but unavailable -> block wins")
    end)

    T.it("allows when ghost is set, no hooks, and block is off", function()
        local fw = newFW({ blockStartPhase = false, ghostOnStartPhase = true })
        -- ghost wanted but no hooks, and block not enabled -> allow the send
        setPhase(fw, 169)
        local block, action = fw:ShouldBlockForStartPhase("Stranger", true)
        T.falsy(block)
        T.is_nil(action)
    end)
end)

return T
