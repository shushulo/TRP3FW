-- tests/unit/who_service_queue_spec.lua
-- Headless tests for WhoService's queue plumbing and the "zone scan was complete"
-- shortcut. Companion to who_service_ttl_spec, which covers the age comparisons.
--
-- Three separate defects are pinned here:
--
-- 1. The zone-completeness shortcut (CheckPlayer, ~line 258) short-circuits a WHO
--    query to "not found" when the last zone scan was recent AND returned fewer than
--    50 results - the reasoning being that a complete zone scan that missed you proves
--    you are not in the zone. But lastZoneQueryTime/lastZoneResultCount both start at
--    0, and 0 reads as "scanned at t=0, found 0 players, therefore complete". The
--    clock is client uptime, so for the first 60 seconds of uptime `now - 0 < 60` held
--    and EVERY WHO check returned not-found without ever querying. A player who got
--    into the world quickly had location checks silently failing shut.
--
-- 2. Enqueuing a second query for a player already in the queue overwrote the entry,
--    discarding the first caller's callback. That caller waits forever - it is never
--    told found, not-found, or timed out.
--
-- 3. ScanZoneForPlayers cleared pendingQuery/cooldownActive on timeout and on
--    RunPrivileged failure but never called ProcessQueue, so anything queued behind
--    the scan sat untouched until it aged out at 60s as "queue_timeout". Every other
--    exit path in the file drains the queue.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW(prefs)
    local fw = H.newNamespace()
    fw.Prefs = prefs or { whoNameCacheDuration = 180, whoCacheRefreshThreshold = 50 }
    fw.hasEpsilonAPI = true
    fw.sessionStats = { cacheStats = { whoCacheHits = 0, whoCacheMisses = 0 } }
    fw.currentZoneName = "Elwynn Forest"

    H.loadModule("core/cache_interface.lua", fw)
    fw.CacheInterface:Register("whoName", {})
    fw.CacheInterface:Register("whoZone", {})

    H.loadModule("core/Service.lua", fw)
    H.loadModule("core/ServiceContainer.lua", fw)

    function fw:CleanPlayerName(n) return n end
    function fw:SanitizePlayerName(n) return n end
    function fw:SanitizeZoneName(z) return z end
    function fw:RunPrivilegedSafe() return true end

    _G.C_FriendList = {
        SetWhoToUi = function() end,
        SendWho = function() end,
        GetNumWhoResults = function() return 0 end,
        GetWhoInfo = function() return nil end,
    }

    H.loadModule("features/services/WhoService.lua", fw)
    local svc = fw.ServiceContainer:Get("WhoService")

    -- Mirror the state :Initialize() sets up, without needing WhoList_Update /
    -- ChatFrame_AddMessageEventFilter mocks that are unrelated to queue behaviour.
    svc.pendingQuery = nil
    svc.queryQueue = {}
    svc.queueHead = 1
    -- Exactly what :Initialize() sets, zeros included - the zero-initialised pair is
    -- the whole point of the first test below.
    svc.lastZoneQueryTime = 0
    svc.lastZoneResultCount = 0
    svc.cooldownActive = false
    svc.requestId = 0

    mock.timers = {}
    return fw, svc
end

-- ===================== Zone-completeness shortcut =====================

T.describe("WhoService zone-completeness shortcut", function()
    T.it("does NOT fire when no zone scan has ever run", function()
        -- Uptime under 60s: `now - lastZoneQueryTime(0)` is inside the 60s trust
        -- window, so a zero-initialised lastZoneResultCount used to read as a
        -- complete scan that found nobody.
        mock.setClock(30)
        local fw, svc = freshFW()

        local result
        svc:CheckPlayer("Bob", 1, function(found, source) result = { found, source } end)

        T.neq(result and result[2], "cached_zone_complete",
            "a zone that was never scanned must not answer as a complete scan")
        T.not_nil(svc.pendingQuery, "it must fall through to a real WHO query")
    end)

    T.it("fires after a real, complete zone scan", function()
        mock.setClock(1000)
        local fw, svc = freshFW()
        svc.lastZoneQueryTime = 990   -- 10s ago, inside the 60s trust window
        svc.lastZoneResultCount = 12  -- under the 50-result truncation limit

        local result
        svc:CheckPlayer("Bob", 1, function(found, source) result = { found, source } end)

        T.eq(result[2], "cached_zone_complete")
        T.eq(result[1], false, "a complete scan that missed them means not in zone")
        T.is_nil(svc.pendingQuery, "no query needed")
    end)

    T.it("does not fire when the last zone scan was truncated", function()
        mock.setClock(1000)
        local fw, svc = freshFW()
        svc.lastZoneQueryTime = 990
        svc.lastZoneResultCount = 50  -- hit the result limit: results were truncated

        local result
        svc:CheckPlayer("Bob", 1, function(found, source) result = { found, source } end)

        T.neq(result and result[2], "cached_zone_complete",
            "a truncated scan proves nothing about who was omitted")
    end)
end)

-- ===================== Queue dedupe preserves callbacks =====================

T.describe("WhoService queue dedupe", function()
    T.it("keeps a single queue entry per player", function()
        mock.setClock(1000)
        local fw, svc = freshFW()
        svc.pendingQuery = { playerName = "Someone", requestId = 99 }  -- force queuing

        svc:CheckPlayer("Bob", 1, function() end)
        svc:CheckPlayer("Bob", 2, function() end)

        T.eq(svc:GetQueueSize(), 1, "the same player must not occupy two slots")
    end)

    T.it("still answers the FIRST caller after a dedupe", function()
        mock.setClock(1000)
        local fw, svc = freshFW()
        svc.pendingQuery = { playerName = "Someone", requestId = 99 }

        local firstCalled, secondCalled = false, false
        svc:CheckPlayer("Bob", 1, function() firstCalled = true end)
        svc:CheckPlayer("Bob", 2, function() secondCalled = true end)

        -- Drain the queue: the in-flight query finishes and ProcessQueue runs the
        -- deduped entry, which resolves from cache.
        fw.CacheInterface:Set("whoName", "Bob", { found = true, zone = "Elwynn Forest", timestamp = 1000 })
        svc.pendingQuery = nil
        svc.cooldownActive = false
        svc:ProcessQueue()

        T.truthy(secondCalled, "the surviving entry's callback must run")
        T.truthy(firstCalled, "the overwritten caller must still get an answer, not hang forever")
    end)
end)

-- ===================== ScanZoneForPlayers drains the queue =====================

T.describe("WhoService:ScanZoneForPlayers queue draining", function()
    T.it("drains queued queries when the scan times out", function()
        mock.setClock(1000)
        local fw, svc = freshFW()

        svc:ScanZoneForPlayers(function() end)
        T.not_nil(svc.pendingQuery, "scan is in flight")

        -- Something queued up behind the in-flight scan.
        local queuedAnswered = false
        svc:CheckPlayer("Bob", 1, function() queuedAnswered = true end)
        T.eq(svc:GetQueueSize(), 1)

        -- Resolve from cache so ProcessQueue can answer without another round trip.
        fw.CacheInterface:Set("whoName", "Bob", { found = true, zone = "Elwynn Forest", timestamp = 1000 })

        -- Fire the scan's timeout timer.
        mock.setClock(1006)
        mock.flushTimers()

        T.is_nil(svc.pendingQuery, "timeout must clear the in-flight scan")
        T.truthy(queuedAnswered, "the queue must be drained after the scan gives up")
    end)

    T.it("drains queued queries when RunPrivileged fails outright", function()
        mock.setClock(1000)
        local fw, svc = freshFW()
        svc.pendingQuery = { playerName = "Someone", requestId = 99 }

        local queuedAnswered = false
        svc:CheckPlayer("Bob", 1, function() queuedAnswered = true end)
        fw.CacheInterface:Set("whoName", "Bob", { found = true, zone = "Elwynn Forest", timestamp = 1000 })

        svc.pendingQuery = nil
        svc.cooldownActive = false
        function fw:RunPrivilegedSafe() return false, "rate_limit" end

        local scanReason
        svc:ScanZoneForPlayers(function(ok, list, reason) scanReason = reason end)

        T.eq(scanReason, "rate_limit")
        T.truthy(queuedAnswered, "a failed scan must not strand the queue behind it")
    end)
end)

return T
