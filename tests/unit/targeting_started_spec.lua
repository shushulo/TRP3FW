-- tests/unit/targeting_started_spec.lua
-- Headless tests for the onTargetingStarted signal in location/phase.lua.
--
-- Context: location/cascading.lua races a fixed correctness deadline against phase
-- targeting. Before this signal existed, a phase check that spent time queued behind
-- a busy mutex (targetingInProgress held by a prior check) could have its own 3.0s/1.5s
-- targeting timeout preempted by the shorter fixed deadline, producing a phantom
-- "not in phase" -> block even though the player was clearly nearby. onTargetingStarted
-- fires exactly when TargetUnit() is actually issued (queue/mutex wait is over), so the
-- caller can push its deadline out to cover the real timeout instead of the unbounded
-- queue wait. These tests verify the signal fires at the right time and not before.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

-- Fire every currently-due timer once; not-yet-due timers survive (mock.flushTimers
-- unconditionally clears the whole queue, which would silently drop a timer scheduled
-- with a delay during the same flush -- e.g. the deferred_low_priority retry below).
local function fireDueTimers()
    local due, kept = {}, {}
    for _, t in ipairs(mock.timers) do
        if not t.cancelled and mock.clock >= t.at then due[#due + 1] = t else kept[#kept + 1] = t end
    end
    mock.timers = kept
    for _, t in ipairs(due) do t.fn() end
    return #due
end

local function freshPhase()
    local fw = H.newNamespace()
    fw.Prefs = { phaseCheckBatchMode = false }  -- exercise ExecutePhaseCheck (individual path)
    fw.ServiceContainer = { Get = function() return nil end }  -- no EventService -> event path inert

    H.loadModule("location/phase.lua", fw)

    fw.hasEpsilonAPI = true
    function fw:IsPhaseCheckEnabled() return true end
    function fw:SanitizePlayerName(n) return n end
    function fw:GetAvailablePrivilegedTokens() return 10 end
    function fw:IsInspectActive() return false end

    _G.UnitExists = function() return false end
    _G.UnitGUID = function() return "Player-0000-00000000" end
    _G.GetUnitName = function() return nil end
    _G.C_Map = { GetBestMapForUnit = function() return 1 end }

    return fw
end

T.describe("onTargetingStarted: individual path", function()
    T.it("fires once TargetUnit() is actually issued", function()
        mock.setClock(1000)
        local fw = freshPhase()
        function fw:RunPrivilegedSafe() return true end  -- targeting succeeds immediately

        local started = false
        fw:CheckPlayerPhase("Bob", 1, function() end, "NORMAL", function() started = true end)

        -- CheckPlayerPhase only queues; SchedulePhaseCheckProcessing's batch-accumulation
        -- timer (phaseCheckBatchDelay, default 1.0s) is what actually kicks off processing.
        mock.advance(1.0)
        fireDueTimers()

        T.truthy(started, "onTargetingStarted should fire as soon as RunPrivilegedSafe succeeds")
    end)

    T.it("does not fire when RunPrivilegedSafe fails outright", function()
        mock.setClock(1000)
        local fw = freshPhase()
        function fw:RunPrivilegedSafe() return false, "api_error" end

        local started = false
        fw:CheckPlayerPhase("Bob", 1, function() end, "NORMAL", function() started = true end)

        mock.advance(1.0)
        fireDueTimers()

        T.falsy(started, "no targeting was actually issued, so the signal must not fire")
    end)

    T.it("fires only after a token-scarcity defer resolves, not at initial queue time", function()
        mock.setClock(1000)
        local fw = freshPhase()

        local attempt = 0
        function fw:RunPrivilegedSafe()
            attempt = attempt + 1
            if attempt == 1 then
                return false, "deferred_low_priority", 0.5  -- deferred; retried after waitTime
            end
            return true
        end

        local started = false
        fw:CheckPlayerPhase("Bob", 1, function() end, "NORMAL", function() started = true end)

        mock.advance(1.0)
        fireDueTimers()  -- kicks off processing -> first RunPrivilegedSafe attempt (deferred)

        T.falsy(started, "still deferred - must not have fired yet")

        -- Deferred retry: C_Timer.After(waitTime) re-queues the entry and arms a fresh
        -- 0.1s batch timer (see phase.lua ExecutePhaseCheck deferred_low_priority branch)
        -- rather than processing inline, so both delays need to elapse.
        mock.advance(0.5)
        fireDueTimers()  -- re-queues + arms the 0.1s follow-up timer

        mock.advance(0.1)
        fireDueTimers()  -- follow-up timer fires -> second RunPrivilegedSafe attempt (succeeds)

        T.truthy(started, "fires once the deferred retry actually issues TargetUnit()")
    end)

    T.it("carries the signal across a busy-mutex requeue (ProcessPhaseCheckQueue chain)", function()
        -- Simulates the scenario the cascading fix targets: a check queued behind a prior
        -- one, where targeting only actually starts once the mutex frees up.
        mock.setClock(1000)
        local fw = freshPhase()
        function fw:RunPrivilegedSafe() return true end

        local started = false
        fw:QueuePhaseCheck("Carol", 2, function() end, "NORMAL", nil, function() started = true end)
        T.falsy(started, "queued but not yet processed")

        fw:ProcessPhaseCheckQueue()
        T.truthy(started, "fires once the queued entry is actually processed and targeted")
    end)
end)

T.describe("onTargetingStarted: batch path duplicate-merge", function()
    local function freshBatchPhase()
        local fw = freshPhase()
        fw.Prefs.phaseCheckBatchMode = true
        fw.Prefs.phaseCheckBatchSize = 5
        fw.Prefs.privilegedReservedTokens = 2
        return fw
    end

    T.it("fires onTargetingStarted for a single batched entry", function()
        mock.setClock(1000)
        local fw = freshBatchPhase()
        function fw:RunPrivilegedSafe() return true end

        local started = false
        fw:QueuePhaseCheck("Dave", 1, function() end, "NORMAL", nil, function() started = true end)
        fw:ProcessPhaseCheckBatch()

        T.truthy(started, "batch path must fire the signal just like the individual path")
    end)

    -- Regression: when two requests for the same player arrive close together (e.g. an
    -- MSP send and a TRP3 map-scan reply both racing to verify the same target), the
    -- SECOND call to QueuePhaseCheck now attaches to the first via pendingPhaseCheckWaiters
    -- instead of creating its own separate queue entry - so there's only ever one real
    -- TargetUnit() call, and BOTH callers' onTargetingStarted still fire when it happens.
    -- Without this, the second caller's cascading deadline never extends and it can be
    -- phantom-timed-out even though targeting genuinely started (confirmed live: two
    -- concurrent sends to the same player, one blocked with phase=fail(timeout) while the
    -- other's phase check succeeded within the same second).
    T.it("fires onTargetingStarted for BOTH callers when a second request attaches to the first", function()
        mock.setClock(1000)
        local fw = freshBatchPhase()
        function fw:RunPrivilegedSafe() return true end

        local firstStarted, secondStarted = false, false
        fw:QueuePhaseCheck("Erin", 1, function() end, "NORMAL", nil, function() firstStarted = true end)
        fw:QueuePhaseCheck("Erin", 2, function() end, "NORMAL", nil, function() secondStarted = true end)

        T.eq(#fw.pendingPhaseChecks, 1, "second request attaches to the first instead of queuing separately")

        fw:ProcessPhaseCheckBatch()

        T.truthy(firstStarted, "first caller's onTargetingStarted must fire")
        T.truthy(secondStarted, "second (merged/duplicate) caller's onTargetingStarted must also fire")
    end)

    T.it("fires all merged onTargetingStarted callbacks after a deferred_low_priority requeue", function()
        mock.setClock(1000)
        local fw = freshBatchPhase()

        local attempt = 0
        function fw:RunPrivilegedSafe()
            attempt = attempt + 1
            if attempt == 1 then
                return false, "deferred_low_priority", 0.5
            end
            return true
        end

        local firstStarted, secondStarted = false, false
        fw:QueuePhaseCheck("Frank", 1, function() end, "NORMAL", nil, function() firstStarted = true end)
        fw:QueuePhaseCheck("Frank", 2, function() end, "NORMAL", nil, function() secondStarted = true end)

        fw:ProcessPhaseCheckBatch()  -- merges both, then defers (attempt 1)
        T.falsy(firstStarted, "deferred - must not have fired yet")
        T.falsy(secondStarted, "deferred - must not have fired yet")

        mock.advance(0.5)
        fireDueTimers()  -- re-queues with the combined onTargetingStarted
        mock.advance(0.1)
        fireDueTimers()  -- follow-up batch timer -> second attempt succeeds

        T.truthy(firstStarted, "first caller's signal must survive the requeue")
        T.truthy(secondStarted, "second (merged) caller's signal must also survive the requeue")
    end)

    -- Isolates the LEGACY check.callback/check.callbacks delivery path from
    -- pendingPhaseCheckWaiters entirely (entries are pushed directly onto
    -- pendingPhaseChecks, bypassing QueuePhaseCheck, so no waiters entry exists to
    -- deliver results via the newer registry). This proves the fix holds at the
    -- check.callbacks layer itself, not just via the separate waiters mechanism.
    --
    -- Regression: ProcessPhaseCheckBatch's deferred_low_priority requeue used to pass
    -- only `check.callbacks[1]` to QueuePhaseCheck, silently dropping every other merged
    -- caller's result callback. They'd never learn the real phase result at all (relying
    -- entirely on cascading.lua's blunt 2.0s deadline to eventually fail them safe).
    T.it("delivers the real RESULT to all merged callbacks after a deferred_low_priority requeue (legacy path)", function()
        mock.setClock(1000)
        local fw = freshBatchPhase()

        local attempt = 0
        function fw:RunPrivilegedSafe()
            attempt = attempt + 1
            if attempt == 1 then
                return false, "deferred_low_priority", 0.5
            end
            return true
        end
        _G.UnitName = function() return "George" end  -- so the manual/event check matches -> inPhase true

        local firstResult, secondResult
        -- Push two entries directly (bypasses QueuePhaseCheck -> no waiters entry).
        table.insert(fw.pendingPhaseChecks, { playerName = "George", sendId = 1, priority = "NORMAL",
            callback = function(r, src) firstResult = { r, src } end, queuedAt = mock.clock })
        table.insert(fw.pendingPhaseChecks, { playerName = "George", sendId = 2, priority = "NORMAL",
            callback = function(r, src) secondResult = { r, src } end, queuedAt = mock.clock })

        T.is_nil(fw.pendingPhaseCheckWaiters["George"], "sanity: bypassed the waiters registry entirely")

        fw:ProcessPhaseCheckBatch()  -- merges both into one batch entry, then defers (attempt 1)
        T.is_nil(firstResult); T.is_nil(secondResult)

        mock.advance(0.5)
        fireDueTimers()  -- deferred_low_priority requeue fires -> re-queues (combinedCallback fan-out)

        -- The requeue is a single entry, below phaseCheckBatchMinSize, so
        -- SchedulePhaseCheckProcessing's 1.0s batch-accumulation timer routes it to the
        -- INDIVIDUAL path (ExecutePhaseCheck), not back through the batch - that path's
        -- own 3.0s NORMAL timeout (not a 0.1s batch interDelay) is what resolves it.
        mock.advance(1.0)
        fireDueTimers()  -- batch-accumulation timer -> queue size 1 -> ExecutePhaseCheck (2nd RunPrivilegedSafe attempt, succeeds)
        mock.advance(3.0)
        fireDueTimers()  -- ExecutePhaseCheck's 3.0s NORMAL timeout -> manual fallback check resolves it

        T.not_nil(firstResult, "first caller must receive the real result")
        T.not_nil(secondResult, "second (merged) caller must ALSO receive the real result, not be silently dropped")
        T.eq(firstResult[1], true)
        T.eq(secondResult[1], true, "both must see the same successful result")
    end)
end)

-- Cross-request coordination (pendingPhaseCheckWaiters): two independent callers checking
-- the SAME player concurrently must not each get their own serialized TargetUnit() call.
-- Live repro that motivated this: an MSP send and a TRP3 map-scan reply for the same
-- player within the same second - one got phase=fail(timeout) while the other's phase
-- check succeeded, because each ran its own fully separate queue entry and the second
-- one's own correctness deadline (cascading.lua) expired while still queued behind the
-- first's targeting attempt.
T.describe("Cross-request coordination: same player, individual (non-batch) path", function()
    T.it("a second concurrent request attaches instead of queuing separately", function()
        mock.setClock(1000)
        local fw = freshPhase()
        -- Simulate a successful target: once TargetUnit() "succeeds", UnitName("target")
        -- reports the checked player so the 3.0s timeout's manual fallback check passes.
        function fw:RunPrivilegedSafe(code)
            if code:find("TargetUnit") then _G.UnitName = function() return "Grace" end end
            return true
        end

        local firstResult, secondResult
        fw:CheckPlayerPhase("Grace", 1, function(r) firstResult = r end, "NORMAL")
        fw:CheckPlayerPhase("Grace", 2, function(r) secondResult = r end, "NORMAL")

        T.eq(#fw.pendingPhaseChecks, 1, "second request must not create its own queue entry")

        mock.advance(1.0)
        fireDueTimers()  -- SchedulePhaseCheckProcessing's batch-accumulation timer fires -> targeting starts
        mock.advance(3.0)
        fireDueTimers()  -- 3.0s NORMAL timeout fires -> manual fallback check resolves it

        T.eq(firstResult, true, "first caller gets the real result")
        T.eq(secondResult, true, "second (attached) caller gets the SAME result, not a separate timeout")
    end)

    T.it("both onTargetingStarted callbacks fire together for attached requests", function()
        mock.setClock(1000)
        local fw = freshPhase()
        function fw:RunPrivilegedSafe() return true end

        local firstStarted, secondStarted = false, false
        fw:CheckPlayerPhase("Henry", 1, function() end, "NORMAL", function() firstStarted = true end)
        fw:CheckPlayerPhase("Henry", 2, function() end, "NORMAL", function() secondStarted = true end)

        mock.advance(1.0)
        fireDueTimers()

        T.truthy(firstStarted)
        T.truthy(secondStarted, "attached caller's deadline-extension signal must also fire")
    end)

    T.it("a request attaching AFTER targeting already started fires its signal immediately", function()
        mock.setClock(1000)
        local fw = freshPhase()
        -- RunPrivilegedSafe succeeds but never resolves the check (no event, no timer
        -- fired yet) so we can attach a second caller mid-flight, after targeting started
        -- but before the result is known.
        function fw:RunPrivilegedSafe() return true end

        local firstStarted = false
        fw:CheckPlayerPhase("Ivy", 1, function() end, "NORMAL", function() firstStarted = true end)
        mock.advance(1.0)
        fireDueTimers()  -- targeting starts for real; firstStarted fires; result still pending (3s timeout not due)

        T.truthy(firstStarted, "sanity: first caller's targeting has started")

        -- Second caller attaches now, mid-flight (waiters.targetingStarted is already true).
        local secondStarted = false
        fw:CheckPlayerPhase("Ivy", 2, function() end, "NORMAL", function() secondStarted = true end)

        T.truthy(secondStarted, "must fire immediately - targeting already started, no signal left to wait for")
    end)

    T.it("clears the waiters entry after resolution (no leak, no stale attach)", function()
        mock.setClock(1000)
        local fw = freshPhase()
        function fw:RunPrivilegedSafe() return true end  -- targeting starts; resolves false via timeout fallback

        local resolved
        fw:CheckPlayerPhase("Jack", 1, function(r) resolved = r end, "NORMAL")
        mock.advance(1.0)
        fireDueTimers()  -- targeting starts
        mock.advance(3.0)
        fireDueTimers()  -- 3.0s timeout fires -> resolves (false, UnitName mock never matches "Jack")

        T.not_nil(resolved, "sanity: the check actually resolved")
        T.is_nil(fw.pendingPhaseCheckWaiters["Jack"], "waiters entry must be cleared once resolved")
    end)
end)

return T
