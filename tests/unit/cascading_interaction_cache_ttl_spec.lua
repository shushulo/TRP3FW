-- tests/unit/cascading_interaction_cache_ttl_spec.lua
-- Headless tests for location/cascading.lua's CheckLocationCascading interaction-cache
-- fast-path (the very first cache check inside the function, before phase/map/SPVP ever
-- run): a fresh "interaction" cache hit (recent mouseover/target/mutual-exchange) allows
-- immediately without running any of the expensive location checks. Like every other
-- phaseCheck-style cache in this codebase, this fast-path must gate on
-- TRP3FW.Prefs.interactionCacheDuration - a stale entry must fall through to the real
-- cascading check rather than being trusted indefinitely.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW(prefs)
    local fw = H.newNamespace()
    fw.Prefs = prefs or { interactionCacheDuration = 600 }
    fw.profiler = { start = function() end, stop = function() end }

    H.loadModule("core/cache_interface.lua", fw)
    fw.CacheInterface:Register("interaction", {})
    fw.CacheInterface:Register("spvpVerified", {})

    -- Globals CheckLocationCascading touches unconditionally near the top, even on the
    -- interaction-cache-hit fast path (blockStartPhase check) or immediately after it
    -- (myMapID/myZone) if the fast path is bypassed.
    _G.C_Map = { GetBestMapForUnit = function() return 1 end }
    _G.GetRealZoneText = function() return "TestZone" end

    function fw:GetCurrentPhaseID() return 1 end  -- never the START_PHASE_ID (169)
    fw.Prefs.blockStartPhase = false

    -- Disable every real check kind so a fallthrough (cache miss/stale) doesn't need the
    -- full phase/map/SPVP machinery mocked - StartStandardChecks becomes a no-op when
    -- nothing is enabled, which is sufficient to prove "did not fast-allow via interaction
    -- cache" without invoking the callback synchronously.
    function fw:IsPhaseCheckEnabled() return false end
    function fw:IsMapCheckEnabled() return false end
    fw.hasEpsilonAPI = false

    H.loadModule("location/cascading.lua", fw)
    return fw
end

T.describe("CheckLocationCascading interaction-cache TTL", function()
    T.it("allows immediately on a fresh interaction cache hit", function()
        mock.setClock(1000)
        local fw = freshFW({ interactionCacheDuration = 600 })
        fw.CacheInterface:Set("interaction", "Bob", { timestamp = 990 })  -- 10s old

        local called, allowed, source
        fw:CheckLocationCascading("Bob", 1, function(ok, alertType, src) called, allowed, source = true, ok, src end)

        T.truthy(called, "fresh interaction cache hit must resolve synchronously")
        T.truthy(allowed)
        T.eq(source, "interaction_cache")
    end)

    T.it("BOUNDARY: treats the entry as expired at exactly the TTL (age >= ttl, not just >)", function()
        mock.setClock(1000)
        local fw = freshFW({ interactionCacheDuration = 600 })
        fw.CacheInterface:Set("interaction", "Bob", { timestamp = 400 })  -- exactly 600s old

        local called = false
        fw:CheckLocationCascading("Bob", 1, function() called = true end)

        T.falsy(called, "age == ttl must not fast-allow synchronously via the interaction cache")
    end)

    T.it("a STALE interaction cache entry falls through to the real cascading check", function()
        mock.setClock(1000)
        local fw = freshFW({ interactionCacheDuration = 600 })
        fw.CacheInterface:Set("interaction", "Bob", { timestamp = 300 })  -- 700s old, well past 600s ttl

        local called = false
        fw:CheckLocationCascading("Bob", 1, function() called = true end)

        T.falsy(called, "stale entry must not resolve via the fast path")
    end)

    T.it("falls through cleanly when there is no interaction cache entry at all", function()
        mock.setClock(1000)
        local fw = freshFW({ interactionCacheDuration = 600 })

        local called = false
        fw:CheckLocationCascading("NeverInteracted", 1, function() called = true end)

        T.falsy(called)
    end)

    T.it("a fresh entry just inside the boundary (age = ttl - 1) still fast-allows", function()
        mock.setClock(1000)
        local fw = freshFW({ interactionCacheDuration = 600 })
        fw.CacheInterface:Set("interaction", "Bob", { timestamp = 401 })  -- 599s old

        local called, allowed
        fw:CheckLocationCascading("Bob", 1, function(ok) called, allowed = true, ok end)

        T.truthy(called)
        T.truthy(allowed)
    end)
end)

return T
