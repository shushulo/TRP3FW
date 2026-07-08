-- tests/unit/phase_check_ttl_spec.lua
-- Headless tests for location/phase.lua's CheckPlayerPhase - the ORIGINAL/canonical
-- phaseCheck-cache TTL implementation that every other consumer in the codebase
-- (CacheStage, trp3_scan_pipeline's CheckCache) copied. Despite being the source of the
-- pattern, it had zero direct boundary tests of its own before this file.
--
-- Two-tier freshness check:
--   age < refreshThreshold (ttl * phaseCacheRefreshThreshold, default 20%): "fresh" -
--       return the cached result immediately, no background refresh queued.
--   refreshThreshold <= age < ttl: "stale but valid" - return the cached result AND
--       queue a LOW-priority background refresh.
--   age >= ttl: expired - fall through to a real queued check (no cached callback).
-- ttl itself is phaseCacheDuration normally, or the shorter phaseCacheFailureDuration
-- when cached.inPhase == false (a failed check is trusted for less time than a success).

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW(prefs)
    local fw = H.newNamespace()
    fw.Prefs = prefs or { phaseCacheDuration = 300, phaseCacheFailureDuration = 10, phaseCacheRefreshThreshold = 0.2 }
    fw.ServiceContainer = { Get = function() return nil end }  -- no HistoryService needed

    H.loadModule("core/cache_interface.lua", fw)
    fw.CacheInterface:Register("phaseCheck", {})

    H.loadModule("location/phase.lua", fw)

    fw.hasEpsilonAPI = true
    function fw:IsPhaseCheckEnabled() return true end
    function fw:SanitizePlayerName(n) return n end
    function fw:GetAvailablePrivilegedTokens() return 10 end

    return fw
end

T.describe("CheckPlayerPhase TTL: fresh branch (immediate return, no refresh queued)", function()
    T.it("returns immediately for an entry within the refresh threshold", function()
        mock.setClock(1000)
        -- ttl=300, refreshThreshold=0.2 -> refresh boundary at 60s
        local fw = freshFW({ phaseCacheDuration = 300, phaseCacheRefreshThreshold = 0.2 })
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = true, timestamp = 970, method = "targeting" })  -- 30s old

        local result, reason
        fw:CheckPlayerPhase("Bob", 1, function(r, src) result, reason = r, src end, "NORMAL")

        T.eq(result, true)
        T.eq(reason, "cached")
        T.eq(#fw.pendingPhaseChecks, 0, "fresh hit must not queue anything, including a refresh")
    end)

    T.it("treats the entry as no-longer-fresh at exactly the refresh-threshold boundary (age >= threshold)", function()
        mock.setClock(1000)
        local fw = freshFW({ phaseCacheDuration = 300, phaseCacheRefreshThreshold = 0.2 })
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = true, timestamp = 940, method = "targeting" })  -- exactly 60s old

        local result, reason
        fw:CheckPlayerPhase("Bob", 1, function(r, src) result, reason = r, src end, "NORMAL")

        T.eq(result, true, "still within full ttl, so still a cache hit")
        T.eq(reason, "cached")
        T.eq(#fw.pendingPhaseChecks, 1, "age == refreshThreshold must NOT take the fresh (no-refresh) branch")
        T.eq(fw.pendingPhaseChecks[1].priority, "LOW", "boundary case takes the stale-but-valid branch, which queues a LOW refresh")
    end)

    T.it("just past the refresh threshold is still valid, but queues a background refresh", function()
        mock.setClock(1000)
        local fw = freshFW({ phaseCacheDuration = 300, phaseCacheRefreshThreshold = 0.2 })
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = true, timestamp = 939, method = "targeting" })  -- 61s old

        local result, reason
        fw:CheckPlayerPhase("Bob", 1, function(r, src) result, reason = r, src end, "NORMAL")

        T.eq(result, true, "still a valid cache hit")
        T.eq(reason, "cached")
        T.eq(#fw.pendingPhaseChecks, 1, "must queue a background refresh")
        T.eq(fw.pendingPhaseChecks[1].priority, "LOW")
        T.is_nil(fw.pendingPhaseChecks[1].callback, "refresh queue entry must carry no callback (fire-and-forget)")
    end)
end)

T.describe("CheckPlayerPhase TTL: full-ttl boundary (stale-but-valid vs expired)", function()
    T.it("returns the cached result (with refresh) just before the full TTL", function()
        mock.setClock(1000)
        local fw = freshFW({ phaseCacheDuration = 300, phaseCacheRefreshThreshold = 0.2 })
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = true, timestamp = 701, method = "targeting" })  -- 299s old

        local result, reason
        fw:CheckPlayerPhase("Bob", 1, function(r, src) result, reason = r, src end, "NORMAL")

        T.eq(result, true)
        T.eq(reason, "cached")
        T.eq(#fw.pendingPhaseChecks, 1, "stale-but-valid queues a LOW refresh")
        T.eq(fw.pendingPhaseChecks[1].priority, "LOW")
    end)

    T.it("BOUNDARY: treats the entry as expired at exactly the full TTL (age >= ttl, not just >)", function()
        mock.setClock(1000)
        local fw = freshFW({ phaseCacheDuration = 300, phaseCacheRefreshThreshold = 0.2 })
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = true, timestamp = 700, method = "targeting" })  -- exactly 300s old

        local callbackFired = false
        fw:CheckPlayerPhase("Bob", 1, function(r, src) callbackFired = true end, "NORMAL")

        T.falsy(callbackFired, "expired entry must not deliver a cached callback at all")
        T.eq(#fw.pendingPhaseChecks, 1, "must fall through to a real (NORMAL priority) queued check")
        T.eq(fw.pendingPhaseChecks[1].priority, "NORMAL", "a genuinely expired entry queues a real check, not a LOW refresh")
    end)

    T.it("a STALE (expired) entry falls through to a real check, not a background refresh", function()
        mock.setClock(1000)
        local fw = freshFW({ phaseCacheDuration = 300, phaseCacheRefreshThreshold = 0.2 })
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = true, timestamp = 600, method = "targeting" })  -- 400s old

        local callbackFired = false
        fw:CheckPlayerPhase("Bob", 1, function() callbackFired = true end, "NORMAL")

        T.falsy(callbackFired, "must not fast-return a stale result")
        T.eq(#fw.pendingPhaseChecks, 1)
        T.eq(fw.pendingPhaseChecks[1].priority, "NORMAL")
    end)
end)

T.describe("CheckPlayerPhase TTL: success TTL vs failure TTL selection", function()
    -- With phaseCacheFailureDuration=10 and phaseCacheRefreshThreshold=0.2, a failure
    -- entry's own refresh threshold is 10*0.2=2s (fixed to scale off the FAILURE ttl, not
    -- the success ttl - see the BUG FIX comment in location/phase.lua's CheckPlayerPhase).

    T.it("uses the (shorter) failure TTL when cached.inPhase == false", function()
        mock.setClock(1000)
        local fw = freshFW({ phaseCacheDuration = 300, phaseCacheFailureDuration = 10, phaseCacheRefreshThreshold = 0.2 })
        -- 11s old: past the 10s failure TTL, but nowhere near the 300s success TTL.
        -- If the success TTL were wrongly used here, this would still look "valid".
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = false, timestamp = 989, method = "timeout" })

        local callbackFired = false
        fw:CheckPlayerPhase("Bob", 1, function() callbackFired = true end, "NORMAL")

        T.falsy(callbackFired, "a stale FAILURE (11s, past the 10s failure TTL) must not fast-return")
        T.eq(#fw.pendingPhaseChecks, 1)
        T.eq(fw.pendingPhaseChecks[1].priority, "NORMAL", "must fall through to a real check, not a refresh")
    end)

    T.it("BOUNDARY: a failure entry is expired at exactly the failure TTL (age >= failTTL)", function()
        mock.setClock(1000)
        local fw = freshFW({ phaseCacheDuration = 300, phaseCacheFailureDuration = 10, phaseCacheRefreshThreshold = 0.2 })
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = false, timestamp = 990, method = "timeout" })  -- exactly 10s old

        local callbackFired = false
        fw:CheckPlayerPhase("Bob", 1, function() callbackFired = true end, "NORMAL")

        T.falsy(callbackFired, "age == failTTL must already be considered expired")
        T.eq(#fw.pendingPhaseChecks, 1)
        T.eq(fw.pendingPhaseChecks[1].priority, "NORMAL")
    end)

    T.it("a fresh failure (within the failure entry's own refresh threshold) fast-returns the failed result", function()
        mock.setClock(1000)
        local fw = freshFW({ phaseCacheDuration = 300, phaseCacheFailureDuration = 10, phaseCacheRefreshThreshold = 0.2 })
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = false, timestamp = 999, method = "timeout" })  -- 1s old, within the 2s refresh threshold

        local result, reason
        fw:CheckPlayerPhase("Bob", 1, function(r, src) result, reason = r, src end, "NORMAL")

        T.eq(result, false)
        T.eq(reason, "cached")
        T.eq(#fw.pendingPhaseChecks, 0, "within the failure entry's own (scaled) refresh threshold - no refresh queued yet")
    end)

    T.it("a failure entry past its OWN refresh threshold (but before its ttl) queues a LOW refresh, not just a fresh hit", function()
        mock.setClock(1000)
        local fw = freshFW({ phaseCacheDuration = 300, phaseCacheFailureDuration = 10, phaseCacheRefreshThreshold = 0.2 })
        -- refreshThreshold for a failure = 10*0.2 = 2s. 5s old is past that but under the 10s ttl.
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = false, timestamp = 995, method = "timeout" })

        local result, reason
        fw:CheckPlayerPhase("Bob", 1, function(r, src) result, reason = r, src end, "NORMAL")

        T.eq(result, false, "still a valid cached failure")
        T.eq(reason, "cached")
        T.eq(#fw.pendingPhaseChecks, 1, "past the failure's own refresh threshold (2s) - must queue a background refresh")
        T.eq(fw.pendingPhaseChecks[1].priority, "LOW")
    end)

    T.it("a fresh SUCCESS uses the (longer) success TTL and its own refresh threshold, not the failure TTL", function()
        mock.setClock(1000)
        local fw = freshFW({ phaseCacheDuration = 300, phaseCacheFailureDuration = 10, phaseCacheRefreshThreshold = 0.2 })
        -- 15s old: past the 10s failure TTL, but this is a SUCCESS entry, so the 300s
        -- success TTL (and its 60s refresh threshold) applies - if the failure TTL were
        -- wrongly used, this would already be expired.
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = true, timestamp = 985, method = "targeting" })

        local result, reason
        fw:CheckPlayerPhase("Bob", 1, function(r, src) result, reason = r, src end, "NORMAL")

        T.eq(result, true)
        T.eq(reason, "cached")
        T.eq(#fw.pendingPhaseChecks, 0, "15s is still within the SUCCESS refresh threshold (60s) - no refresh queued yet")
    end)
end)

T.describe("CheckPlayerPhase TTL: no entry / phase check disabled", function()
    T.it("queues a real check when there is no cached entry at all", function()
        mock.setClock(1000)
        local fw = freshFW()
        local callbackFired = false
        fw:CheckPlayerPhase("NeverChecked", 1, function() callbackFired = true end, "NORMAL")

        T.falsy(callbackFired)
        T.eq(#fw.pendingPhaseChecks, 1)
        T.eq(fw.pendingPhaseChecks[1].priority, "NORMAL")
    end)

    T.it("skips the cache entirely when phase checking is disabled", function()
        mock.setClock(1000)
        local fw = freshFW()
        function fw:IsPhaseCheckEnabled() return false end
        fw.CacheInterface:Set("phaseCheck", "Bob", { inPhase = true, timestamp = 999 })  -- fresh, would normally fast-return

        local result, reason
        fw:CheckPlayerPhase("Bob", 1, function(r, src) result, reason = r, src end, "NORMAL")

        T.is_nil(result)
        T.eq(reason, "unavailable")
        T.eq(#fw.pendingPhaseChecks, 0, "disabled phase checking must not touch the queue OR the cache")
    end)
end)

return T
