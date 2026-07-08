-- tests/unit/scan_reply_cache_veto_spec.lua
-- Headless tests for hooks/trp3_scan_pipeline.lua's CheckCache (Stage 2 of the scan
-- reply pipeline).
--
-- Bug fixed: each cache lookup (phaseCheck, whoName) was checked as an independent
-- "allow" fast-path with no cross-veto. A player with a fresh, EXPLICIT phase-check
-- FAILURE (phaseCheck.inPhase == false, e.g. they changed phase after an earlier WHO
-- hit was cached) could still get allowed via a leftover whoName cache hit, since that
-- check never looked at the phase result at all. This is a real leak: a scan reply gets
-- allowed to someone we just confirmed is NOT reachable. The fix vetoes the WHO-cache
-- fast-path whenever a fresh phase failure exists (and phase checking actually matters
-- for scan replies), falling through to "continue" so the real CheckLocationCascading
-- check decides instead of a stale/unrelated cache.

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

T.describe("CheckCache: phase failure vetoes WHO cache allow", function()
    T.it("allows via WHO cache when there is no phase cache entry at all", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults())
        fw.CacheInterface:Set("whoName", "Bob", { found = true, timestamp = 1000, zone = "Elwynn Forest" })

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "allow")
        T.eq(reason, "who_cache")
    end)

    T.it("BUG (fixed): a fresh phase FAILURE must veto an otherwise-valid WHO cache hit", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults())
        -- Phase check explicitly failed 2s ago (well within the 10s failure TTL).
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = false, timestamp = 998 })
        -- WHO cache still has an old "found" hit (e.g. from before Bob changed phase).
        fw.CacheInterface:Set("whoName", "Bob", { found = true, timestamp = 999, zone = "Elwynn Forest" })

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "continue", "must NOT allow via WHO cache - phase explicitly failed recently")
        T.is_nil(reason)
    end)

    T.it("does not veto once the phase failure has expired (past phaseCacheFailureDuration)", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults({ phaseCacheFailureDuration = 10 }))
        -- Phase failure is 20s old - stale, should no longer veto.
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = false, timestamp = 980 })
        fw.CacheInterface:Set("whoName", "Bob", { found = true, timestamp = 999, zone = "Elwynn Forest" })

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "allow", "stale phase failure should no longer block the WHO cache allow")
        T.eq(reason, "who_cache")
    end)

    T.it("does not veto when scan-reply phase checking is disabled (mode = off)", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults({ scanResponsePhaseMode = "off" }))
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = false, timestamp = 999 })
        fw.CacheInterface:Set("whoName", "Bob", { found = true, timestamp = 999, zone = "Elwynn Forest" })

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "allow", "phase isn't a signal this pipeline cares about when its mode is off")
        T.eq(reason, "who_cache")
    end)

    T.it("does not veto when scanResponsePhaseCheckEnabled is explicitly false", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults({ scanResponsePhaseCheckEnabled = false }))
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = false, timestamp = 999 })
        fw.CacheInterface:Set("whoName", "Bob", { found = true, timestamp = 999, zone = "Elwynn Forest" })

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "allow")
        T.eq(reason, "who_cache")
    end)

    -- Phase and map checking can be toggled independently (per-feature Prefs). The veto
    -- must key ONLY off phase settings/results, regardless of the map toggle's state.
    T.it("map checking OFF + phase checking ON: fresh phase failure still vetoes WHO cache", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults({ scanResponseMapMode = "off" }))
        function fw:IsMapCheckEnabled() return false end
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = false, timestamp = 998 })
        fw.CacheInterface:Set("whoName", "Bob", { found = true, timestamp = 999, zone = "Elwynn Forest" })

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "continue", "phase veto must hold even with map checking entirely off")
        T.is_nil(reason)
    end)

    T.it("map checking ON + phase checking OFF: no phase signal exists, WHO cache allow proceeds normally", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults({ scanResponsePhaseMode = "off" }))
        function fw:IsMapCheckEnabled() return true end
        function fw:GetCurrentMapID() return 42 end
        -- Stale/irrelevant phase-fail entry present, but phase checking is off for scan
        -- replies - it must not gate anything (there's nothing to veto WITH).
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = false, timestamp = 999 })
        fw.CacheInterface:Set("whoName", "Bob", { found = true, timestamp = 999, zone = "TestZone" })

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "allow", "phase-off means no phase veto signal; map-gated WHO cache still decides normally")
        T.eq(reason, "who_cache")
    end)

    T.it("a fresh phase SUCCESS still allows via phase cache directly (unaffected by the fix)", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults())
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = true, timestamp = 999 })

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "allow")
        T.eq(reason, "phase_cache")
    end)

    T.it("does not veto the allowedSenders/interaction fast-paths (stronger, unrelated trust signals)", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults({ scanResponseAllowCacheBypass = true }))
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = false, timestamp = 999 })
        fw.CacheInterface:Set("interaction", "Bob", { timestamp = 999 })

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "allow", "direct interaction is a stronger signal than a phase-check cache and isn't vetoed")
        T.eq(reason, "interaction_cache")
    end)

    T.it("falls through to continue (no allow) when phase failed AND there is no WHO cache to veto", function()
        mock.setClock(1000)
        local fw, CheckCache = freshFW(withDefaults())
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = false, timestamp = 999 })

        local action, reason = CheckCache(fw, "Bob")
        T.eq(action, "continue")
        T.is_nil(reason)
    end)
end)

return T
