-- tests/unit/location_dispatch_spec.lua
-- Headless tests for three "a result reaches the wrong callers, or the wrong code path"
-- defects found during the section-4 (location detection) bug-check pass. All three are
-- the section-2/3 patterns again: a value produced at one end and dropped at the other,
-- and per-player state with no owner tag.
--
--   1. location/cascading.lua  - options.priority was never read, so every HIGH-priority
--      latency path was unreachable from the only caller that asks for one.
--   2. location/phase.lua      - the originating caller's callback was registered in BOTH
--      the queue entry and the waiters group, so it fired twice per check.
--   3. location/maps.lua       - a second MapScan for the same player overwrote the first,
--      dropping its callback and orphaning its timer.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

-- Fire every currently-due timer once; not-yet-due timers survive (mock.flushTimers
-- unconditionally clears the whole queue, which would silently drop a timer scheduled
-- during the same flush).
local function fireDueTimers()
    local due, kept = {}, {}
    for _, t in ipairs(mock.timers) do
        if not t.cancelled and mock.clock >= t.at then due[#due + 1] = t else kept[#kept + 1] = t end
    end
    mock.timers = kept
    for _, t in ipairs(due) do t.fn() end
    return #due
end

-- ===================================================================================
-- 1. cascading.lua: options.priority must reach the checks it was written for
-- ===================================================================================
--
-- hooks/trp3_scan_pipeline.lua sets `priority = "HIGH"` on every TRP3 scan reply because
-- TRP3 only holds the reply window open for ~3 seconds. CheckLocationCascading never read
-- the field, so StartStandardChecks/RunMapCheck ran with priority = nil and every
-- HIGH-keyed fast path stayed dead: the 0.2s parallel map check, the 0.3s parallel map
-- scan, CheckPlayerPhase's 1.5s timeout, MapScan's 5s rate limit and 2.5s timeout.

local function freshCascading(prefs)
    local fw = H.newNamespace()
    fw.Prefs = prefs or {}
    fw.Prefs.blockStartPhase = false
    fw.Prefs.interactionCacheDuration = fw.Prefs.interactionCacheDuration or 600
    fw.Prefs.transitionGracePeriod = fw.Prefs.transitionGracePeriod or 3
    fw.profiler = { start = function() end, stop = function() end }

    H.loadModule("core/cache_interface.lua", fw)
    fw.CacheInterface:Register("interaction", {})
    fw.CacheInterface:Register("spvpVerified", {})

    _G.C_Map = { GetBestMapForUnit = function() return 1 end }
    _G.GetRealZoneText = function() return "TestZone" end

    function fw:GetCurrentPhaseID() return 1 end
    function fw:IsPhaseCheckEnabled() return true end
    function fw:IsMapCheckEnabled() return false end
    fw.hasEpsilonAPI = true
    fw.detectedAddons = {}
    fw.ServiceContainer = { Get = function() return nil end }

    -- mock.timers is process-global. CheckLocationCascading arms a 2.0s deadline that
    -- these tests never fire, and a later spec's fireDueTimers() would otherwise run it
    -- against a torn-down namespace.
    mock.timers = {}

    -- Capture what priority the phase check is actually asked for.
    fw.observedPriority = "__never_called__"
    function fw:CheckPlayerPhase(_, _, _, priority) fw.observedPriority = priority end

    H.loadModule("location/cascading.lua", fw)
    return fw
end

T.describe("CheckLocationCascading: options.priority plumbing", function()
    T.it("forwards a HIGH priority from the caller down to the phase check", function()
        mock.setClock(1000)
        local fw = freshCascading()

        fw:CheckLocationCascading("Bob", 1, function() end, { priority = "HIGH" })

        T.eq(fw.observedPriority, "HIGH",
            "scan replies ask for HIGH; dropping it disables every latency path built for them")
    end)

    T.it("leaves priority nil when the caller does not ask for one", function()
        mock.setClock(1000)
        local fw = freshCascading()

        fw:CheckLocationCascading("Bob", 1, function() end, {})

        T.is_nil(fw.observedPriority,
            "the ordinary send path must keep its NORMAL-by-default behaviour")
    end)

    T.it("arms the 0.2s parallel map-check fast fallback only for HIGH", function()
        mock.setClock(1000)

        -- With map checks enabled, StartStandardChecks schedules a 0.2s C_Timer only on
        -- the HIGH path. Count timers armed in the first 0.2s to detect it.
        local function countFastFallback(priority)
            local fw = freshCascading()
            function fw:IsMapCheckEnabled() return true end
            mock.timers = {}
            fw:CheckLocationCascading("Bob", 1, function() end, { priority = priority })
            -- The only other timer CheckLocationCascading arms is the 2.0s correctness
            -- deadline, so anything under 1s is the fast fallback. (Not `<= 0.2`: the mock
            -- stores an absolute time and 1000.2 - 1000 lands just above 0.2 in floats.)
            local fast = 0
            for _, t in ipairs(mock.timers) do
                if t.at - mock.clock < 1.0 then fast = fast + 1 end
            end
            return fast
        end

        T.truthy(countFastFallback("HIGH") > 0,
            "HIGH must arm the 0.2s fallback so a scan reply can still make TRP3's 3s window")
        T.eq(countFastFallback(nil), 0,
            "the normal path must not start speculative parallel map checks")
    end)
end)

-- ===================================================================================
-- 2. phase.lua: one result per caller, not two
-- ===================================================================================
--
-- QueuePhaseCheck seeded pendingPhaseCheckWaiters with the originating caller's own
-- callback, but that same function is also stored on the queue entry. Every resolver
-- delivers both (check.callback(...) then ResolvePhaseCheckWaiters(...)), so the caller
-- that started the check was invoked twice while attached callers were invoked once.

local function freshPhase(batchMode)
    local fw = H.newNamespace()
    fw.Prefs = { phaseCheckBatchMode = batchMode or false, phaseCheckBatchMinSize = 1 }
    fw.ServiceContainer = { Get = function() return nil end }

    mock.timers = {}  -- see the note in freshCascading
    H.loadModule("location/phase.lua", fw)

    fw.hasEpsilonAPI = true
    function fw:IsPhaseCheckEnabled() return true end
    function fw:SanitizePlayerName(n) return n end
    function fw:GetAvailablePrivilegedTokens() return 10 end
    function fw:IsInspectActive() return false end
    function fw:RunPrivilegedSafe() return true end

    _G.UnitExists = function() return false end
    _G.UnitGUID = function() return "Player-0000-00000000" end
    _G.GetUnitName = function() return nil end
    _G.C_Map = { GetBestMapForUnit = function() return 1 end }

    return fw
end

-- Drive a queued check all the way to resolution on the individual path (1.0s batch
-- accumulation, then the 3.0s NORMAL targeting timeout resolves it).
local function runToResolution()
    mock.advance(1.0); fireDueTimers()
    mock.advance(3.0); fireDueTimers()
end

T.describe("Phase check result delivery: exactly once per caller", function()
    T.it("individual path: the originating caller's callback fires exactly once", function()
        mock.setClock(1000)
        local fw = freshPhase(false)

        local calls = 0
        fw:CheckPlayerPhase("Grace", 1, function() calls = calls + 1 end, "NORMAL")
        runToResolution()

        T.eq(calls, 1, "delivered via check.callback AND ResolvePhaseCheckWaiters = twice")
    end)

    T.it("batch path: the originating caller's callback fires exactly once", function()
        mock.setClock(1000)
        local fw = freshPhase(true)

        local calls = 0
        fw:CheckPlayerPhase("Grace", 1, function() calls = calls + 1 end, "NORMAL")
        runToResolution()

        T.eq(calls, 1, "finishStep fans out check.callbacks and then the waiters group too")
    end)

    T.it("two concurrent callers each get exactly one result", function()
        mock.setClock(1000)
        local fw = freshPhase(false)

        local first, second = 0, 0
        fw:CheckPlayerPhase("Grace", 1, function() first = first + 1 end, "NORMAL")
        fw:CheckPlayerPhase("Grace", 2, function() second = second + 1 end, "NORMAL")
        runToResolution()

        T.eq(first, 1, "the caller that started the check must not be favoured with a second result")
        T.eq(second, 1, "the attached caller must still be told exactly once")
    end)

    T.it("still delivers the SAME result to both callers (dedupe did not drop anyone)", function()
        mock.setClock(1000)
        local fw = freshPhase(false)
        -- Make targeting "succeed" so the manual fallback check resolves true.
        function fw:RunPrivilegedSafe(code)
            if code:find("TargetUnit") then _G.UnitName = function() return "Heidi" end end
            return true
        end

        local firstResult, secondResult
        fw:CheckPlayerPhase("Heidi", 1, function(r) firstResult = r end, "NORMAL")
        fw:CheckPlayerPhase("Heidi", 2, function(r) secondResult = r end, "NORMAL")
        runToResolution()

        T.eq(firstResult, true)
        T.eq(secondResult, true)
        _G.UnitName = function() return "TestPlayer" end
    end)

    T.it("the originating caller's onTargetingStarted signal also fires exactly once", function()
        mock.setClock(1000)
        local fw = freshPhase(false)

        local started = 0
        fw:CheckPlayerPhase("Ivan", 1, function() end, "NORMAL", function() started = started + 1 end)
        mock.advance(1.0); fireDueTimers()

        T.eq(started, 1, "the signal rode on both the queue entry and the waiters list")
    end)
end)

-- ===================================================================================
-- 3. maps.lua: a second scan for the same player must attach, not overwrite
-- ===================================================================================
--
-- activeScanCallbacks is keyed by player name alone. A second MapScan used to replace the
-- first entry outright: the first caller's callback was discarded (never told anything),
-- and the first entry's timer stayed armed - when it fired it found the SECOND entry and
-- resolved it as a timeout early, writing a `found = false` mapScan cache entry that then
-- suppressed the player for scanCacheFailureDuration.

local function freshMaps()
    local fw = H.newNamespace()
    fw.Prefs = {
        scanCacheDuration = 120,
        scanCacheFailureDuration = 10,
        mapScanMinInterval = 60,
        scanResponseRequireNonce = false,
    }
    fw.detectedAddons = { MapScanner = true }
    fw.sessionStats = { cacheStats = {
        mapCacheHits = 0, mapCacheMisses = 0,
        broadcastCacheHits = 0, broadcastCacheMisses = 0,
    } }
    fw.ServiceContainer = { Get = function() return nil end }

    H.loadModule("core/cache_interface.lua", fw)
    fw.CacheInterface:Register("mapScan", {})
    fw.CacheInterface:Register("broadcast", {})
    fw.CacheInterface:Register("mapName", {})

    function fw:IsMapCheckEnabled() return true end
    function fw:CleanPlayerName(n) return n end

    _G.C_Map = { GetBestMapForUnit = function() return 1 end, GetMapInfo = function() return { name = "TestZone" } end }
    _G.GetRealZoneText = function() return "TestZone" end
    _G.WorldMapFrame = nil
    _G.TRP3_API = nil
    _G.RPMapScan = nil
    _G.AddOn_TotalRP3 = nil

    mock.frames = {}
    mock.timers = {}
    H.loadModule("location/maps.lua", fw)
    return fw, mock.lastFrame()
end

T.describe("MapScan: concurrent scans for the same player", function()
    T.it("delivers the timeout to BOTH callers instead of dropping the first", function()
        mock.setClock(1000)
        local fw = freshMaps()

        local first, second
        fw:MapScan("Kara", 1, function(found, source) first = { found, source } end)
        fw:MapScan("Kara", 2, function(found, source) second = { found, source } end)

        mock.advance(5); fireDueTimers()  -- the 5s scan timeout

        T.not_nil(first, "the first caller's callback was silently overwritten and never fired")
        T.not_nil(second)
        T.eq(first[2], "timeout")
        T.eq(second[2], "timeout")
    end)

    T.it("does not arm a second timer that can prematurely fail the survivor", function()
        mock.setClock(1000)
        local fw = freshMaps()

        fw:MapScan("Kara", 1, function() end)
        local afterFirst = #mock.timers
        fw:MapScan("Kara", 2, function() end)

        T.eq(#mock.timers, afterFirst,
            "attaching must reuse the in-flight scan's timer, not orphan one that fires early")
    end)

    T.it("delivers a WHISPER scan reply to every attached caller", function()
        mock.setClock(1000)
        local fw, frame = freshMaps()

        local results = {}
        fw:MapScan("Kara", 1, function(found, source) results[1] = { found, source } end)
        fw:MapScan("Kara", 2, function(found, source) results[2] = { found, source } end)

        -- C_SCAN reply: "RPB1~C_SCAN~<x>~<y>" over WHISPER.
        frame:Fire("CHAT_MSG_ADDON", "RPB1", "RPB1~C_SCAN~0.5~0.5", "WHISPER", "Kara")

        T.not_nil(results[1], "first caller must be told the player was found")
        T.not_nil(results[2], "attached caller must be told too")
        T.eq(results[1][1], true)
        T.eq(results[2][1], true)
    end)

    T.it("a scan started after the previous one resolved registers fresh (no stale attach)", function()
        mock.setClock(1000)
        local fw = freshMaps()

        fw:MapScan("Kara", 1, function() end)
        mock.advance(5); fireDueTimers()  -- resolves and clears the entry

        -- Past the 60s min interval so the rate limiter does not answer first.
        mock.advance(60)
        local second
        fw:MapScan("Kara", 2, function(found, source) second = { found, source } end)
        mock.advance(5); fireDueTimers()

        T.not_nil(second, "a fresh scan must get its own timer and resolve on its own")
        T.eq(second[2], "timeout")
    end)
end)

return T
