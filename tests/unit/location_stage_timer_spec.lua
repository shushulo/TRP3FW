-- tests/unit/location_stage_timer_spec.lua
-- Headless tests for features/stages/LocationStage.lua's 30s housekeeping timer.
--
-- Bug fixed: LocationStage registers a C_Timer.After(30, ...) give-up handler that tears
-- down pendingLocationChecks plus the three hook-layer burst queues
-- (pendingChompSends/pendingTRP3Sends/pendingMSPReplies) for the player. Its only guard
-- was `if TRP3FW.pendingSends[sendId] then` - i.e. "the check never resolved".
--
-- But nothing cleared pendingSends[sendId] on the async success path. The start-phase
-- branch cleared it; the normal cascading callback did not. And CacheService's sweeper
-- only prunes pendingSends at 60s, well past the 30s mark. So the entry was ALWAYS still
-- present at t+30 and the timer ALWAYS fired as though the check had hung - for every
-- single request. (CheckLocationCascading has an unconditional 2.0s deadline, so in
-- practice a genuinely hung check does not even happen.)
--
-- Consequence: if another request from the same player started a fresh location check in
-- that 30s window - routine for anyone actively RPing near you - the older request's
-- timer deleted the newer check's pendingLocationChecks entry and its hook burst queues.
-- Requests queued behind the newer check were then never replayed: not sent, not ghosted,
-- not blocked. The profile silently never arrived, and ReplayQueuedRequests' own
-- `if not pendingLocationChecks[playerName] then return end` guard made the loss quiet.
--
-- Fix has two halves, tested separately below: retire pendingSends[sendId] when the check
-- resolves, and tag pendingLocationChecks with the owning sendId so the timer only tears
-- down its own check.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW()
    local fw = H.newNamespace()
    fw.Prefs = { suppressionTime = 10 }
    H.loadModule("core/Stage.lua", fw)

    fw.pendingSends = {}
    fw.pendingLocationChecks = {}
    fw.pendingChompSends = {}
    fw.pendingTRP3Sends = {}
    fw.pendingMSPReplies = {}
    fw.currentZoneName = "Stormwind City"
    fw.lastZoneChangeTime = 0
    fw.lastPhaseChangeTime = 0

    fw.ServiceContainer = { Get = function() return nil end }
    function fw:IsPhaseCheckEnabled() return true end
    function fw:IsMapCheckEnabled() return true end
    function fw:GetBurstSettingsFingerprint() return "fp" end
    function fw:TrackAddonRequest() end
    function fw:AllowSender() end
    function fw:ShouldBlockForStartPhase() return false, nil end
    function fw:Pipeline_DecisionStage() end
    function fw:ProcessLocationDecision() end

    -- Capture the cascading callback so tests can resolve the check on demand.
    fw.captured = {}
    function fw:CheckLocationCascading(playerName, sendId, callback, options)
        fw.captured[sendId] = { playerName = playerName, callback = callback, options = options }
    end

    H.loadModule("features/stages/LocationStage.lua", fw)
    return fw
end

local function ctx(playerName, sendId)
    return {
        playerName = playerName, addon = "TRP3", sendId = sendId, isWhisper = true,
        now = mock.clock, settings = { suppressionTime = 10 },
        originalFunc = nil, originalArgs = {},
    }
end

-- Resolve a started check the way CheckLocationCascading would, then emulate the
-- ReplayQueuedRequests teardown that ProcessLocationDecision performs on completion.
local function resolve(fw, sendId, playerName)
    fw.captured[sendId].callback(true, nil, "map", 0, "Stormwind City", "Stormwind City", {}, false, 0, {})
    fw.pendingLocationChecks[playerName] = nil
end

T.describe("LocationStage: retiring a resolved send", function()
    T.it("clears pendingSends[sendId] when the cascading check resolves", function()
        mock.setClock(1000); mock.timers = {}
        local fw = freshFW()

        fw.LocationStage:Process(ctx("Bob", 1))
        T.not_nil(fw.pendingSends[1], "a started check registers its pending send")

        fw.captured[1].callback(true, nil, "map", 0, "SW", "SW", {}, false, 0, {})
        T.is_nil(fw.pendingSends[1],
            "a resolved check must retire its pendingSends entry, or the 30s timer fires as if it hung")
    end)

    T.it("tags the in-flight check with the sendId that owns it", function()
        mock.setClock(1000); mock.timers = {}
        local fw = freshFW()

        fw.LocationStage:Process(ctx("Bob", 7))
        T.eq(fw.pendingLocationChecks["Bob"].sendId, 7,
            "the timer needs this tag to tell its own check from a successor's")
    end)
end)

T.describe("LocationStage: the 30s timer must not tear down a NEWER check", function()
    T.it("BUG (fixed): a resolved check's timer leaves a newer check for the same player intact", function()
        mock.setClock(1000); mock.timers = {}
        local fw = freshFW()

        -- Request A starts a check for Bob, then resolves normally.
        fw.LocationStage:Process(ctx("Bob", 1))
        resolve(fw, 1, "Bob")

        -- 29s later request B starts a fresh check for the same player, and hook-layer
        -- sends queue up behind it.
        mock.setClock(1029)
        fw.LocationStage:Process(ctx("Bob", 2))
        fw.pendingChompSends["Bob"] = { queuedRequests = { { prefix = "TRP3" } } }
        fw.pendingTRP3Sends["Bob"] = { queuedRequests = { { messageType = 1 } } }
        fw.pendingMSPReplies["Bob"] = { queuedRequests = { { sender = "Bob" } } }

        -- A's 30s housekeeping timer comes due.
        mock.setClock(1030)
        mock.flushTimers()

        T.not_nil(fw.pendingLocationChecks["Bob"], "B's in-flight check must survive A's timer")
        T.eq(fw.pendingLocationChecks["Bob"].sendId, 2, "and it must still be B's check")
        T.not_nil(fw.pendingChompSends["Bob"], "B's queued Chomp sends must not be dropped")
        T.not_nil(fw.pendingTRP3Sends["Bob"], "B's queued TRP3 sends must not be dropped")
        T.not_nil(fw.pendingMSPReplies["Bob"], "B's queued MSP replies must not be dropped")
    end)

    T.it("the timer still retires its own pendingSends entry either way", function()
        mock.setClock(1000); mock.timers = {}
        local fw = freshFW()

        fw.LocationStage:Process(ctx("Bob", 1))
        resolve(fw, 1, "Bob")
        mock.setClock(1030)
        mock.flushTimers()

        T.is_nil(fw.pendingSends[1], "no pendingSends leak once the timer has run")
    end)
end)

T.describe("LocationStage: the give-up path still works", function()
    T.it("a genuinely hung check tears down its own state at 30s", function()
        mock.setClock(1000); mock.timers = {}
        local fw = freshFW()

        -- Start a check and never resolve it.
        fw.LocationStage:Process(ctx("Bob", 1))
        fw.pendingChompSends["Bob"] = { queuedRequests = { { prefix = "TRP3" } } }
        fw.pendingTRP3Sends["Bob"] = { queuedRequests = { { messageType = 1 } } }
        fw.pendingMSPReplies["Bob"] = { queuedRequests = { { sender = "Bob" } } }

        mock.setClock(1030)
        mock.flushTimers()

        T.is_nil(fw.pendingSends[1], "hung send is retired")
        T.is_nil(fw.pendingLocationChecks["Bob"], "hung check is abandoned")
        T.is_nil(fw.pendingChompSends["Bob"], "its abandoned Chomp queue is cleared")
        T.is_nil(fw.pendingTRP3Sends["Bob"], "its abandoned TRP3 queue is cleared")
        T.is_nil(fw.pendingMSPReplies["Bob"], "its abandoned MSP queue is cleared")
    end)

    T.it("one player's timer never touches another player's check", function()
        mock.setClock(1000); mock.timers = {}
        local fw = freshFW()

        fw.LocationStage:Process(ctx("Bob", 1))    -- will hang; its timer is due at 1030

        -- Alice's check starts later, so her own timer is not due when Bob's fires.
        mock.setClock(1010)
        fw.LocationStage:Process(ctx("Alice", 2))
        fw.pendingChompSends["Alice"] = { queuedRequests = { { prefix = "TRP3" } } }

        mock.setClock(1030)
        mock.flushTimers()

        T.is_nil(fw.pendingLocationChecks["Bob"])
        T.not_nil(fw.pendingLocationChecks["Alice"], "Alice's check is unrelated to Bob's timeout")
        T.not_nil(fw.pendingChompSends["Alice"])
    end)
end)

T.describe("LocationStage: start-phase branch (unchanged behaviour)", function()
    T.it("clears its pending send immediately and never starts a cascading check", function()
        mock.setClock(1000); mock.timers = {}
        local fw = freshFW()
        function fw:ShouldBlockForStartPhase() return true, "block" end

        local result = fw.LocationStage:Process(ctx("Bob", 1))
        T.truthy(result.handled)
        T.falsy(result.allowed)
        T.eq(result.reason, "start_phase_block")
        T.is_nil(fw.pendingSends[1])
        T.is_nil(fw.pendingLocationChecks["Bob"])
        T.is_nil(fw.captured[1], "no location check is started for a start-phase block")
    end)
end)

T.describe("LocationStage: always handles (Pipeline:Run never falls through)", function()
    -- core/Pipeline.lua returns { handled = false } on full fall-through and
    -- CheckLocationAndNotify returns result.allowed - which would be nil, indistinguishable
    -- from an explicit block. That is only safe because this last stage always handles.
    T.it("returns handled = true on the no-checks-enabled path", function()
        mock.setClock(1000); mock.timers = {}
        local fw = freshFW()
        function fw:IsPhaseCheckEnabled() return false end
        function fw:IsMapCheckEnabled() return false end

        local result = fw.LocationStage:Process(ctx("Bob", 1))
        T.truthy(result.handled)
        T.truthy(result.allowed)
        T.eq(result.reason, "no_checks")
    end)

    T.it("returns handled = true on the async path", function()
        mock.setClock(1000); mock.timers = {}
        local fw = freshFW()

        local result = fw.LocationStage:Process(ctx("Bob", 1))
        T.truthy(result.handled)
        T.truthy(result.async)
        T.eq(result.reason, "check_started")
    end)
end)

return T
