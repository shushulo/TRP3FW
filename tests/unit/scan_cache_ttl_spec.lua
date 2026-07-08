-- tests/unit/scan_cache_ttl_spec.lua
-- Headless tests for hooks/trp3_scan_pipeline.lua's CheckCache (Stage 2 of the scan reply
-- pipeline) - specifically the phase-SUCCESS TTL boundary (phaseCacheDuration) and the
-- WHO-cache TTL boundary (whoNameCacheDuration), each in isolation from the other.
--
-- tests/unit/scan_reply_cache_veto_spec.lua already covers the cross-cache veto behavior
-- (a fresh phase FAILURE blocking an otherwise-valid WHO cache hit) and the phase-failure
-- TTL boundary as it relates to that veto. It does NOT independently test: (a) that a
-- stale phase-SUCCESS entry falls through rather than fast-allowing, or (b) that a stale
-- WHO-cache entry falls through rather than fast-allowing. This file fills that gap.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW(prefs)
    local fw = H.newNamespace()
    fw.Prefs = prefs or {}
    fw.hasEpsilonAPI = false
    H.loadModule("core/cache_interface.lua", fw)
    fw.CacheInterface:Register("phaseCheck", {})
    fw.CacheInterface:Register("whoName", {})
    fw.CacheInterface:Register("allowedSenders", {})
    fw.CacheInterface:Register("interaction", {})

    function fw:IsMapCheckEnabled() return false end
    function fw:GetCurrentMapID() return nil end
    _G.GetRealZoneText = function() return "TestZone" end

    local mod = H.loadModule("hooks/trp3_scan_pipeline.lua", fw)
    return fw, mod.CheckCache
end

local function withDefaults(overrides)
    local prefs = {
        scanResponsePhaseCheckEnabled = true,
        scanResponsePhaseMode = "alert",
        scanResponseMapMode = "alert",
        phaseCacheDuration = 300,
        phaseCacheFailureDuration = 10,
        whoNameCacheDuration = 180,
        scanResponseAllowCacheBypass = false,
    }
    for k, v in pairs(overrides or {}) do prefs[k] = v end
    return prefs
end

T.describe("CheckCache: phase-SUCCESS TTL boundary (phaseCacheDuration)", function()
    T.it("allows via phase cache on a fresh success entry", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults({ phaseCacheDuration = 300 }))
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = true, timestamp = 990 })  -- 10s old

        local action, reason, age = CheckCache(fw, "Bob")
        T.eq(action, "allow")
        T.eq(reason, "phase_cache")
        T.eq(age, 10)
    end)

    T.it("BOUNDARY: a phase-success entry is stale at exactly phaseCacheDuration (age >= ttl)", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults({ phaseCacheDuration = 300 }))
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = true, timestamp = 700 })  -- exactly 300s old

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "continue", "age == ttl must not fast-allow via the phase cache")
        T.is_nil(reason)
    end)

    T.it("a STALE phase-success entry falls through, not fast-allow", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults({ phaseCacheDuration = 300 }))
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = true, timestamp = 600 })  -- 400s old

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "continue")
        T.is_nil(reason)
    end)

    T.it("a fresh entry just inside the boundary (age = ttl - 1) still allows", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults({ phaseCacheDuration = 300 }))
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = true, timestamp = 701 })  -- 299s old

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "allow")
        T.eq(reason, "phase_cache")
    end)
end)

T.describe("CheckCache: WHO-cache TTL boundary (whoNameCacheDuration)", function()
    T.it("allows via WHO cache on a fresh found entry", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults({ whoNameCacheDuration = 180 }))
        fw.CacheInterface:Set("whoName", "Bob", { found = true, timestamp = 990, zone = "Elwynn Forest" })  -- 10s old

        local action, reason, age = CheckCache(fw, "Bob")
        T.eq(action, "allow")
        T.eq(reason, "who_cache")
        T.eq(age, 10)
    end)

    T.it("BOUNDARY: a WHO-cache entry is stale at exactly whoNameCacheDuration (age >= ttl)", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults({ whoNameCacheDuration = 180 }))
        fw.CacheInterface:Set("whoName", "Bob", { found = true, timestamp = 820, zone = "Elwynn Forest" })  -- exactly 180s old

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "continue", "age == ttl must not fast-allow via the WHO cache")
        T.is_nil(reason)
    end)

    T.it("a STALE WHO-cache entry falls through, not fast-allow", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults({ whoNameCacheDuration = 180 }))
        fw.CacheInterface:Set("whoName", "Bob", { found = true, timestamp = 700, zone = "Elwynn Forest" })  -- 300s old

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "continue")
        T.is_nil(reason)
    end)

    T.it("a fresh entry just inside the boundary (age = ttl - 1) still allows", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults({ whoNameCacheDuration = 180 }))
        fw.CacheInterface:Set("whoName", "Bob", { found = true, timestamp = 821, zone = "Elwynn Forest" })  -- 179s old

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "allow")
        T.eq(reason, "who_cache")
    end)

    T.it("a stale WHO-cache entry with found=false never allows regardless of age (sanity: found gate, not TTL)", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults({ whoNameCacheDuration = 180 }))
        fw.CacheInterface:Set("whoName", "Bob", { found = false, timestamp = 999, zone = "Elwynn Forest" })  -- fresh but not found

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "continue")
        T.is_nil(reason)
    end)
end)

return T
