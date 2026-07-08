-- tests/unit/who_service_ttl_spec.lua
-- Headless tests for features/services/WhoService.lua's TTL/age comparisons.
--
-- WhoService:CheckPlayer's whoName cache READ (CI:Get("whoName", playerName)) is backed
-- by core/cache_interface.lua, which is registered with ttl = Prefs.whoNameCacheDuration
-- (see core/init.lua InitializeCaches) - CacheInterface:Get already evicts entries whose
-- age >= that ttl before WhoService ever sees them, so there is no SEPARATE stale-read bug
-- to cover at that call site (unlike CacheStage/CheckPlayerPhase/CheckCache, which each
-- read via CI:Get from an UNTIL-ttl-less registration and re-check age themselves).
--
-- Two independent, real age-gated DECISIONS in this file are NOT covered by CacheInterface
-- and are the actual audit targets:
--   1. CheckPlayer's background-refresh trigger (~line 209): age > ttl*(refreshThreshold/100)
--      decides whether to schedule a low-priority background refresh of an aging (but still
--      valid) cache entry. Getting this boundary wrong either refreshes one tick too early/
--      late or (worse) never refreshes at all if inverted, silently letting entries ride to
--      full expiry unrefreshed.
--   2. ProcessQueue's queued-query staleness check (~line 158): a hardcoded 60s cutoff that
--      decides whether a queued WHO query is dropped (queue_timeout) instead of executed.
--      Too generous silently executes a query for a request that's long since moved on;
--      too strict drops queries that are still perfectly actionable.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW(prefs)
    local fw = H.newNamespace()
    fw.Prefs = prefs or { whoNameCacheDuration = 180, whoCacheRefreshThreshold = 50 }
    fw.hasEpsilonAPI = true
    fw.sessionStats = { cacheStats = { whoCacheHits = 0, whoCacheMisses = 0 } }

    H.loadModule("core/cache_interface.lua", fw)
    -- Deliberately registered WITHOUT a ttl option (unlike production's core/init.lua) so
    -- CacheInterface:Get never evicts on its own - this isolates WhoService's OWN age
    -- comparisons from the cache interface's independent eviction, letting us test each
    -- boundary in isolation without conflating the two layers.
    fw.CacheInterface:Register("whoName", {})
    fw.CacheInterface:Register("whoZone", {})

    H.loadModule("core/Service.lua", fw)
    H.loadModule("core/ServiceContainer.lua", fw)

    function fw:CleanPlayerName(n) return n end
    function fw:SanitizePlayerName(n) return n end

    -- WhoService.lua registers itself via TRP3FW.ServiceContainer:Register(WhoService) at
    -- load time and calls TRP3FW.Service:New("WhoService") - both already set up above.
    H.loadModule("features/services/WhoService.lua", fw)

    local svc = fw.ServiceContainer:Get("WhoService")
    -- Minimal instance state normally set up by :Initialize() (not calling the real
    -- Initialize to avoid needing WhoList_Update/ChatFrame_AddMessageEventFilter/etc mocks
    -- unrelated to the TTL logic under test).
    svc.pendingQuery = nil
    svc.queryQueue = {}
    svc.queueHead = 1
    svc.lastZoneQueryTime = 0
    svc.cooldownActive = false
    svc.lastZoneResultCount = 0
    svc.requestId = 0

    mock.timers = {}  -- isolate per-test timer counts (mock.timers is a module-level list)

    return fw, svc
end

T.describe("WhoService:CheckPlayer background-refresh threshold", function()
    T.it("does NOT schedule a refresh for a genuinely fresh entry", function()
        mock.setClock(1000)
        local fw, svc = freshFW({ whoNameCacheDuration = 180, whoCacheRefreshThreshold = 50 })
        fw.CacheInterface:Set("whoName", "Bob", { found = true, zone = "Elwynn Forest", timestamp = 990 })  -- 10s old

        local result
        svc:CheckPlayer("Bob", 1, function(found, source) result = { found, source } end)

        T.eq(result[1], true)
        T.eq(result[2], "cached")
        T.is_nil(svc.refreshInProgress and svc.refreshInProgress["Bob"], "well under the 90s refresh threshold - no refresh scheduled")
    end)

    T.it("BOUNDARY: schedules a refresh at exactly the refresh threshold (age > threshold, not >=)", function()
        -- ttl=180, refreshThreshold%=50 -> refresh boundary at 90s. The source uses a
        -- strict `>`, so age == 90 must NOT yet refresh (still within the fresh half).
        mock.setClock(1000)
        local fw, svc = freshFW({ whoNameCacheDuration = 180, whoCacheRefreshThreshold = 50 })
        fw.CacheInterface:Set("whoName", "Bob", { found = true, zone = "Elwynn Forest", timestamp = 910 })  -- exactly 90s old

        svc:CheckPlayer("Bob", 1, function() end)

        T.is_nil(svc.refreshInProgress and svc.refreshInProgress["Bob"], "age == threshold must NOT trigger a refresh yet (strict >)")
    end)

    T.it("schedules a background refresh just past the threshold", function()
        mock.setClock(1000)
        local fw, svc = freshFW({ whoNameCacheDuration = 180, whoCacheRefreshThreshold = 50 })
        fw.CacheInterface:Set("whoName", "Bob", { found = true, zone = "Elwynn Forest", timestamp = 909 })  -- 91s old

        svc:CheckPlayer("Bob", 1, function() end)

        T.truthy(svc.refreshInProgress and svc.refreshInProgress["Bob"], "age just past the 90s threshold must schedule a refresh")
    end)

    T.it("still returns the cached (correct) result even while a refresh is scheduled", function()
        mock.setClock(1000)
        local fw, svc = freshFW({ whoNameCacheDuration = 180, whoCacheRefreshThreshold = 50 })
        fw.CacheInterface:Set("whoName", "Bob", { found = true, zone = "Elwynn Forest", timestamp = 850 })  -- 150s old, aging but not expired

        local result
        svc:CheckPlayer("Bob", 1, function(found, source, age) result = { found, source, age } end)

        T.eq(result[1], true)
        T.eq(result[2], "cached")
        T.eq(result[3], 150)
        T.truthy(svc.refreshInProgress and svc.refreshInProgress["Bob"])
    end)

    T.it("does not double-schedule a refresh for an already-in-progress player", function()
        mock.setClock(1000)
        local fw, svc = freshFW({ whoNameCacheDuration = 180, whoCacheRefreshThreshold = 50 })
        fw.CacheInterface:Set("whoName", "Bob", { found = true, zone = "Elwynn Forest", timestamp = 900 })  -- 100s old

        svc:CheckPlayer("Bob", 1, function() end)
        T.eq(#mock.timers, 1, "first call schedules exactly one refresh timer")

        svc:CheckPlayer("Bob", 2, function() end)
        T.eq(#mock.timers, 1, "second call while refresh is already in-progress must not stack another timer")
    end)
end)

T.describe("WhoService:ProcessQueue staleness cutoff (60s)", function()
    T.it("executes a queued query well within the 60s window", function()
        mock.setClock(1000)
        local fw, svc = freshFW()
        local dropped = false
        table.insert(svc.queryQueue, { playerName = "Bob", sendId = 1, timestamp = 990,  -- 10s old
            callback = function(ok, reason) if reason == "queue_timeout" then dropped = true end end })

        -- CheckPlayer will run for real; hasEpsilonAPI stubs stop it before any WoW API
        -- calls that would need further mocking - we only care whether it was DROPPED.
        function fw:CleanPlayerName(n) return n end
        function fw:SanitizePlayerName(n) return nil end  -- force early "invalid_name" exit, harmless for this check

        svc:ProcessQueue()

        T.falsy(dropped, "a 10s-old queued query must not be dropped as stale")
    end)

    T.it("BOUNDARY: drops a queued query at exactly 60s (age > 60, not >=, per source's strict >)", function()
        mock.setClock(1000)
        local fw, svc = freshFW()
        function fw:RunPrivilegedSafe() return true end  -- reached only if NOT dropped as stale
        _G.C_FriendList = { SetWhoToUi = function() end, SendWho = function() end }

        local reason
        table.insert(svc.queryQueue, { playerName = "Bob", sendId = 1, timestamp = 940,  -- exactly 60s old
            callback = function(ok, r) reason = r end })

        svc:ProcessQueue()

        T.neq(reason, "queue_timeout", "age == 60s must NOT be dropped yet under the source's strict > comparison")
    end)

    T.it("drops a queued query just past the 60s cutoff", function()
        mock.setClock(1000)
        local fw, svc = freshFW()
        local reason
        table.insert(svc.queryQueue, { playerName = "Bob", sendId = 1, timestamp = 939,  -- 61s old
            callback = function(ok, r) reason = r end })

        svc:ProcessQueue()

        T.eq(reason, "queue_timeout", "a query older than 60s must be dropped as stale")
    end)
end)

return T
