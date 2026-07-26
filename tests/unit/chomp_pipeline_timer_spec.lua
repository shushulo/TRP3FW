-- tests/unit/chomp_pipeline_timer_spec.lua
-- Headless tests for the two deferred timers in hooks/trp3_chomp_pipeline.lua.
--
-- Both bugs are the same shape as the LocationStage timer bug (see
-- tests/unit/location_stage_timer_spec.lua): a C_Timer.After callback that identifies the
-- work it owns by a key or a value rather than by identity, and so tears down a successor's
-- state instead of its own.
--
-- BUG 1 - ChompPipeline_BurstDetection_V2's 30s timeout.
--   The give-up timer read `if self.pendingChompSends[playerName] then ... = nil end`. That
--   is a presence check, not an ownership check. The stage itself replaces an entry older
--   than 2s with a fresh one under the same player key, so a second request from the same
--   player inside the 30s window installs a NEW burst entry - and the first request's timer
--   then deleted it, along with every request queued behind it. Those are never replayed:
--   ProcessBurstAllows and ProcessBurstBlocks (features/decision.lua:289, :343) both no-op
--   on a missing key, so the queued sends are neither sent, ghosted, nor blocked. The
--   profile silently never arrives.
--
-- BUG 2 - ChompPipeline_PhaseInDelay_V2's replay timer.
--   The timer located its queued send by `queuedSend.target == target and
--   queuedSend.queuedAt == now`. Two sends to the same target close enough together share a
--   `queuedAt` value and are indistinguishable by that predicate. Both timers then matched the FIRST entry: it was
--   replayed twice and the second entry stayed queued until the TTL sweep dropped it unsent.
--   Additionally the replay called the hooked SmartAddonMessage bare - nothing in that chain
--   is pcall-wrapped - so an error skipped the `replayingPhaseInSend = false` line and
--   latched the guard flag true for the rest of the session, disabling every Chomp guard
--   until /reload.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW(prefs)
    local fw = H.newNamespace()
    fw.Prefs = prefs or {}
    fw.pendingChompSends = {}
    fw.pendingPhaseInSends = {}
    fw.PHASE_IN_QUEUE_LIMIT = 200
    fw.lastZoneChangeTime = 0
    fw.lastPhaseChangeTime = 0
    fw.hookState = {}

    fw.ServiceContainer = { Get = function() return nil end }
    function fw:CleanPlayerName(n) return n end
    function fw:GetBurstSettingsFingerprint() return "fp" end
    function fw:ShouldBlockOnPhase() return true end
    function fw:ShouldBlockOnMap() return false end

    H.loadModule("hooks/trp3_chomp_pipeline.lua", fw)
    return fw
end

-- Drive the burst stage the way the Chomp hook does.
local function burst(fw, playerName)
    return fw:ChompPipeline_BurstDetection_V2(playerName, "TRP3", "payload", "WHISPER",
        playerName, "NORMAL", nil, nil, nil)
end

T.describe("Chomp burst timeout: must not tear down a NEWER burst", function()
    T.it("BUG (fixed): the first request's timer leaves a successor's burst intact", function()
        mock.setClock(1000); mock.timers = {}
        local fw = freshFW()

        -- Request A opens a burst window for Bob.
        burst(fw, "Bob")
        T.not_nil(fw.pendingChompSends["Bob"], "A opens the burst window")

        -- 29s later request B arrives. The >2s branch retires A's entry and installs a fresh
        -- one, and a sibling request queues behind it.
        mock.setClock(1029)
        burst(fw, "Bob")
        local newEntry = fw.pendingChompSends["Bob"]
        T.not_nil(newEntry, "B opens a new burst window under the same key")
        burst(fw, "Bob")
        T.eq(#newEntry.queuedRequests, 1, "a sibling request queues behind B")

        -- A's 30s give-up timer comes due.
        mock.setClock(1030)
        mock.flushTimers()

        T.not_nil(fw.pendingChompSends["Bob"],
            "B's burst must survive A's timer - dropping it loses the queued sends silently")
        T.eq(fw.pendingChompSends["Bob"], newEntry, "and it must still be B's entry")
        T.eq(#fw.pendingChompSends["Bob"].queuedRequests, 1,
            "the queued sibling must still be there to replay")
    end)

    T.it("still gives up on a burst that genuinely never resolved", function()
        mock.setClock(1000); mock.timers = {}
        local fw = freshFW()

        burst(fw, "Bob")
        T.not_nil(fw.pendingChompSends["Bob"])

        -- Nothing else happens for Bob; the timer must clean up.
        mock.setClock(1030)
        mock.flushTimers()

        T.is_nil(fw.pendingChompSends["Bob"],
            "the give-up path must still work - the fix must not read as 'disable the timer'")
    end)

    T.it("opens no burst window when no blocking mode is active", function()
        mock.setClock(1000); mock.timers = {}
        local fw = freshFW()
        function fw:ShouldBlockOnPhase() return false end
        function fw:ShouldBlockOnMap() return false end

        local result = burst(fw, "Bob")
        T.truthy(result.shouldContinue, "nothing is being gated, so nothing needs queueing")
        T.is_nil(fw.pendingChompSends["Bob"])
    end)
end)

T.describe("Chomp phase-in replay: identifies its own queued send", function()
    local function phaseIn(fw, target)
        return fw:ChompPipeline_PhaseInDelay_V2(target, "TRP3", "payload", "WHISPER",
            target, "NORMAL", nil, nil, nil)
    end

    T.it("BUG (fixed): two sends queued in the same frame both replay", function()
        mock.setClock(1000); mock.timers = {}
        local fw = freshFW({ phaseInDelay = 4 })
        fw.lastZoneChangeTime = 1000  -- inside the phase-in window

        -- Two sends to the same target in the SAME frame - identical queuedAt.
        local r1 = phaseIn(fw, "Bob")
        local r2 = phaseIn(fw, "Bob")
        T.truthy(r1.queued and r2.queued, "both are queued during the phase-in window")
        T.eq(#fw.pendingPhaseInSends, 2, "two distinct entries are queued")
        T.eq(fw.pendingPhaseInSends[1].queuedAt, fw.pendingPhaseInSends[2].queuedAt,
            "the clock has not advanced between them, so they share a queuedAt - identity is "
            .. "the only way to tell them apart")

        -- Capture the replays instead of really sending.
        local replays = {}
        _G.AddOn_Chomp = {
            SmartAddonMessage = function(prefix, text, chatType, target)
                table.insert(replays, { prefix = prefix, text = text, target = target })
            end
        }

        mock.setClock(1004)
        mock.flushTimers()

        T.eq(#replays, 2, "both queued sends must replay - previously one was replayed twice "
            .. "and the other was dropped unsent")
        T.eq(#fw.pendingPhaseInSends, 0, "and the queue must drain")

        _G.AddOn_Chomp = nil
    end)

    T.it("a failing replay does not latch the replay guard flag", function()
        mock.setClock(1000); mock.timers = {}
        local fw = freshFW({ phaseInDelay = 4 })
        fw.lastZoneChangeTime = 1000

        phaseIn(fw, "Bob")

        _G.AddOn_Chomp = {
            SmartAddonMessage = function() error("chomp exploded") end
        }

        mock.setClock(1004)
        T.no_raise(function() mock.flushTimers() end,
            "the replay error must not escape the timer")

        T.falsy(fw.hookState.chomp.replayingPhaseInSend,
            "a latched flag disables every Chomp guard - recursion, phase-in and gating - "
            .. "for the rest of the session")

        _G.AddOn_Chomp = nil
    end)

    T.it("does not queue outside the phase-in window", function()
        mock.setClock(1000); mock.timers = {}
        local fw = freshFW({ phaseInDelay = 4 })
        fw.lastZoneChangeTime = 900  -- 100s ago, well past the window

        local result = phaseIn(fw, "Bob")
        T.truthy(result.shouldContinue, "past the window the send proceeds normally")
        T.falsy(result.queued)
        T.eq(#fw.pendingPhaseInSends, 0)
    end)

    T.it("a queue entry evicted by the TTL sweep is not replayed", function()
        mock.setClock(1000); mock.timers = {}
        local fw = freshFW({ phaseInDelay = 4 })
        fw.lastZoneChangeTime = 1000

        phaseIn(fw, "Bob")

        -- Emulate CacheService's sweeper clearing the queue before the timer fires.
        fw.pendingPhaseInSends = {}

        local replays = 0
        _G.AddOn_Chomp = { SmartAddonMessage = function() replays = replays + 1 end }

        mock.setClock(1004)
        T.no_raise(function() mock.flushTimers() end)
        T.eq(replays, 0, "an entry that is no longer queued must not be resurrected")

        _G.AddOn_Chomp = nil
    end)
end)
