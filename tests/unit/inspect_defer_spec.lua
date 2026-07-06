-- tests/unit/inspect_defer_spec.lua
-- Headless tests for the armory/inspect deferral in location/phase.lua:
--   ExecutePhaseCheck, while the inspect window is open and pausePhaseCheckOnInspect
--   is set, must re-queue the check (retry) until a 10s deadline; past the deadline it
--   resolves the check via the callback as in-phase or out-of-phase per
--   inspectTimeoutResolution (so the normal modes + SPVP fallback still decide action).
--
-- We drive TRP3FW.inspectOpen to simulate the window and the mock clock for the 10s
-- window. SanitizePlayerName / IsInspectActive are stubbed on the namespace so the
-- test targets only the deferral branch (it returns before any real targeting).

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshPhase(resolution)
    local fw = H.newNamespace()
    fw.Prefs = { pausePhaseCheckOnInspect = true, inspectTimeoutResolution = resolution }
    fw.ServiceContainer = { Get = function() return nil end }

    -- Load the module under test (defines QueuePhaseCheck / ExecutePhaseCheck etc.)
    H.loadModule("location/phase.lua", fw)

    -- Stubs for the helpers ExecutePhaseCheck / QueuePhaseCheck reach.
    function fw:SanitizePlayerName(n) return n end
    function fw:GetAvailablePrivilegedTokens() return 10 end  -- QueuePhaseCheck reads this
    fw.inspectOpen = true
    function fw:IsInspectActive() return self.inspectOpen end

    return fw
end

T.describe("Inspect deferral: retry then resolve", function()
    T.it("re-queues (retries) while inspect is open and within the 10s window", function()
        mock.setClock(1000)
        local fw = freshPhase("in_phase")
        local resolved = nil
        local cb = function(inPhase) resolved = inPhase end

        fw:ExecutePhaseCheck({ playerName = "Bob", sendId = 1, callback = cb, priority = "NORMAL" })

        -- Not resolved yet; a retry entry was queued carrying a deadline ~10s out.
        T.is_nil(resolved)
        T.eq(#fw.pendingPhaseChecks, 1)
        T.eq(fw.pendingPhaseChecks[1].playerName, "Bob")
        T.not_nil(fw.pendingPhaseChecks[1].inspectDeadline)
        T.eq(fw.pendingPhaseChecks[1].inspectDeadline, 1010)  -- 1000 + 10
    end)

    T.it("resolves as IN PHASE past the deadline when set to in_phase", function()
        mock.setClock(1000)
        local fw = freshPhase("in_phase")
        local resolved, reason = nil, nil
        local cb = function(inPhase, r) resolved, reason = inPhase, r end

        -- Simulate a check whose deadline has already passed.
        fw:ExecutePhaseCheck({ playerName = "Bob", sendId = 1, callback = cb,
                               priority = "NORMAL", inspectDeadline = 999 })

        T.eq(resolved, true)
        T.eq(reason, "checked")
        T.eq(#fw.pendingPhaseChecks, 0)  -- resolved, not re-queued
    end)

    T.it("tags the resolution with the inspect_timeout method (for block-reason display)", function()
        mock.setClock(1000)
        local fw = freshPhase("out_of_phase")
        -- Cascading reads the callback as (inPhase, source, theirMapID, phaseMethod);
        -- phaseMethod becomes checkDetails.phase.method, which the notification uses.
        local method
        local cb = function(_, _, _, m) method = m end

        fw:ExecutePhaseCheck({ playerName = "Bob", sendId = 1, callback = cb,
                               priority = "NORMAL", inspectDeadline = 999 })

        T.eq(method, "inspect_timeout")
    end)

    T.it("resolves as NOT IN PHASE past the deadline when set to out_of_phase", function()
        mock.setClock(1000)
        local fw = freshPhase("out_of_phase")
        local resolved = nil
        local cb = function(inPhase) resolved = inPhase end

        fw:ExecutePhaseCheck({ playerName = "Bob", sendId = 1, callback = cb,
                               priority = "NORMAL", inspectDeadline = 999 })

        T.eq(resolved, false)
    end)

    T.it("carries the same deadline across retries (window doesn't reset)", function()
        mock.setClock(1000)
        local fw = freshPhase("in_phase")
        local cb = function() end

        -- First defer stamps deadline 1010.
        fw:ExecutePhaseCheck({ playerName = "Bob", sendId = 1, callback = cb, priority = "NORMAL" })
        local firstDeadline = fw.pendingPhaseChecks[1].inspectDeadline

        -- Advance 3s and re-run the dequeued entry: deadline must be unchanged.
        mock.advance(3)
        local requeued = table.remove(fw.pendingPhaseChecks, 1)
        fw:ExecutePhaseCheck(requeued)
        T.eq(fw.pendingPhaseChecks[1].inspectDeadline, firstDeadline)  -- still 1010
    end)

    T.it("does not take the inspect-defer path when inspect is closed", function()
        mock.setClock(1000)
        local fw = freshPhase("in_phase")
        fw.inspectOpen = false
        -- Past the guard it would try real targeting; stub the target bits so it doesn't
        -- error, then assert no inspect-retry entry (deadline-carrying) was queued.
        fw.hasEpsilonAPI = false
        function fw:RunPrivilegedSafe() return false, "api_unavailable" end
        _G.UnitExists = function() return false end
        _G.GetUnitName = function() return nil end
        _G.C_Map = { GetBestMapForUnit = function() return nil end }

        local ok = pcall(function()
            fw:ExecutePhaseCheck({ playerName = "Bob", sendId = 1, callback = function() end, priority = "NORMAL" })
        end)
        T.truthy(ok)

        local hasInspectRetry = false
        for _, e in ipairs(fw.pendingPhaseChecks) do
            if e.inspectDeadline ~= nil then hasInspectRetry = true end
        end
        T.falsy(hasInspectRetry)
    end)
end)

-- Fire every currently-due pump/queue timer once, advancing nothing. Returns the
-- number of callbacks fired. Rebuilds the pending timer list so not-yet-due timers
-- survive (the mock's own flushTimers drops them).
local function fireDueTimers()
    local due, kept = {}, {}
    for _, t in ipairs(mock.timers) do
        if not t.cancelled and mock.clock >= t.at then due[#due + 1] = t else kept[#kept + 1] = t end
    end
    mock.timers = kept
    for _, t in ipairs(due) do t.fn() end
    return #due
end

T.describe("Inspect deferral: multiple concurrent requests", function()
    local function queueMany(fw, names, priority)
        local resolved = {}
        for _, n in ipairs(names) do
            fw:QueuePhaseCheck(n, n, function(inPhase) resolved[n] = inPhase end, priority or "NORMAL")
        end
        return resolved
    end

    T.it("defers all queued checks, each with its own 10s deadline", function()
        mock.setClock(2000)
        local fw = freshPhase("in_phase")
        mock.timers = {}
        queueMany(fw, { "Bob", "Carol", "Dave" })

        -- Drive processing: the first defers itself + arms the shared pump; one pump
        -- sweep then stamps the rest.
        fw:ProcessPhaseCheckQueue()
        fireDueTimers()          -- nothing due yet at t=2000 (pump is +1s)
        mock.advance(1)
        fireDueTimers()          -- pump sweep at t=2001

        T.eq(#fw.pendingPhaseChecks, 3)  -- all three still deferred, none resolved
        local seen = {}
        for _, e in ipairs(fw.pendingPhaseChecks) do
            T.not_nil(e.inspectDeadline)
            seen[e.playerName] = true
        end
        T.truthy(seen.Bob); T.truthy(seen.Carol); T.truthy(seen.Dave)
    end)

    T.it("keeps exactly one shared pump timer regardless of request count", function()
        mock.setClock(2000)
        local fw = freshPhase("in_phase")
        mock.timers = {}
        queueMany(fw, { "Bob", "Carol", "Dave", "Erin", "Frank" })
        fw:ProcessPhaseCheckQueue()

        -- One and only one pump timer object is tracked.
        T.not_nil(fw.inspectRetryTimer)
        local pumpTimers = 0
        for _, t in ipairs(mock.timers) do if not t.cancelled then pumpTimers = pumpTimers + 1 end end
        T.eq(pumpTimers, 1)
    end)

    T.it("resolves every check once the window passes (in one sweep)", function()
        mock.setClock(2000)
        local fw = freshPhase("out_of_phase")
        mock.timers = {}
        local resolved = queueMany(fw, { "Bob", "Carol", "Dave" })

        -- Stamp deadlines for all three.
        fw:ProcessPhaseCheckQueue()
        mock.advance(1); fireDueTimers()      -- t=2001: rest get stamped (deadline 2011)
        T.eq(#fw.pendingPhaseChecks, 3)

        -- Jump past the 10s window and pump once: all resolve together.
        mock.advance(11)                       -- t=2012 > 2011
        fireDueTimers()

        T.eq(resolved.Bob, false)
        T.eq(resolved.Carol, false)
        T.eq(resolved.Dave, false)
        T.eq(#fw.pendingPhaseChecks, 0)
    end)

    T.it("resolves staggered deadlines independently", function()
        mock.setClock(2000)
        local fw = freshPhase("in_phase")
        mock.timers = {}
        local resolved = {}

        -- Bob deadline 2005 (already close), Carol deadline 2020 (far).
        fw:QueuePhaseCheck("Bob", 1, function(p) resolved.Bob = p end, "NORMAL", 2005)
        fw:QueuePhaseCheck("Carol", 2, function(p) resolved.Carol = p end, "NORMAL", 2020)
        fw:ScheduleInspectPump()

        mock.advance(6)                        -- t=2006: Bob expired, Carol not
        fireDueTimers()

        T.eq(resolved.Bob, true)               -- Bob resolved
        T.is_nil(resolved.Carol)               -- Carol still waiting
        T.eq(#fw.pendingPhaseChecks, 1)
        T.eq(fw.pendingPhaseChecks[1].playerName, "Carol")
    end)

    T.it("resumes normal processing for all when inspect closes mid-wait", function()
        mock.setClock(2000)
        local fw = freshPhase("in_phase")
        mock.timers = {}
        -- Stub the post-guard targeting path so ProcessPhaseCheckQueue doesn't error.
        fw.hasEpsilonAPI = false
        function fw:RunPrivilegedSafe() return false, "api_unavailable" end
        _G.UnitExists = function() return false end
        _G.GetUnitName = function() return nil end
        _G.C_Map = { GetBestMapForUnit = function() return nil end }

        queueMany(fw, { "Bob", "Carol" })
        fw:ProcessPhaseCheckQueue()
        mock.advance(1); fireDueTimers()       -- both deferred with deadlines

        -- Inspect closes; next pump should hand back to normal processing, not resolve
        -- via timeout.
        fw.inspectOpen = false
        mock.advance(1); fireDueTimers()

        -- No inspect_timeout resolution happened; checks left the deferral system.
        local stillDeferred = false
        for _, e in ipairs(fw.pendingPhaseChecks) do
            if e.inspectDeadline then stillDeferred = true end
        end
        T.falsy(stillDeferred)
    end)
end)
