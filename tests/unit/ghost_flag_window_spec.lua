-- tests/unit/ghost_flag_window_spec.lua
-- Headless tests for section 7 (features/) findings.
--
-- BUG 1 - features/ghostmode_trp3.lua: the jittered ghost window was inert.
--
--     local jitter = math.random(0, 2000) / 1000   -- 0-2s
--     local expireTime = now + 2 + jitter          -- 2-4 second window
--     ...
--     self.ghostCleanupTimer = C_Timer.NewTimer(2, function() ... end)
--
-- `expires` carried the jitter but the auto-cleanup timer was hardcoded to 2s, so the
-- timer always won the race and the flag was cleared at a fixed 2.0s on every send. The
-- jitter widened the window by exactly zero frames. Its stated purpose (MEDIUM-3) is to
-- stop the ghost window's width from being a timing oracle - a constant 2.0s teardown is
-- precisely the observable the jitter exists to hide, so the mitigation was self-defeating.
-- Fix: both the expiry and the timer now derive from one `ghostWindow` value.
--
-- BUG 2 - hooks/trp3.lua: `hasTRP3ExchangeHooks` was never set true.
--
-- core/init.lua:349 declares `TRP3FW.hasTRP3ExchangeHooks = false` and no production line
-- ever assigns it again (verified repo-wide; the only other writes are in
-- tests/unit/start_phase_spec.lua). But InstallSendObjectHook IS the TRP3 exchange hook -
-- it is the sole thing that swaps outgoing SI profile payloads for ghost data. So the flag
-- that gates "TRP3 ghosting is available" was permanently false while the capability it
-- describes was fully installed. Consequences at its four read sites:
--   * features/decision.lua:346 - every queued TRP3/Chomp burst sibling took the drop path
--     instead of being ghosted, so burst siblings were silently never sent.
--   * features/ghostmode.lua:51 - phase-169 ghost fell back to hard block unless MSP hooks
--     happened to be present.
--   * NotificationService.lua:258/:338 - ghost sends were labelled as plain blocks.
-- Fix: set the flag where the hook is actually installed (and on the already-installed
-- "skip" path, which is equally ours).

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW()
    local fw = H.newNamespace()
    fw.Prefs = {}
    mock.setClock(1000)
    mock.timers = {}
    H.loadModule("features/ghostmode_trp3.lua", fw)
    return fw
end

-- ===================== BUG 1: jittered ghost window =====================

T.describe("EnableGhostForNextSend - ghost window", function()

    T.it("arms the cleanup timer for the same duration as the expiry it set", function()
        local fw = freshFW()
        -- Force a large jitter so any mismatch is unmistakable.
        local realRandom = math.random
        math.random = function() return 2000 end
        fw:EnableGhostForNextSend("Bob")
        math.random = realRandom

        local expiresIn = fw.ghostNextSend.expires - mock.clock
        T.eq(expiresIn, 4, "max jitter should give a 4s window")

        -- Exactly one cleanup timer, and it must fire at the END of that window.
        local armed = {}
        for _, t in ipairs(mock.timers) do
            if not t.cancelled then armed[#armed + 1] = t end
        end
        T.eq(#armed, 1, "one cleanup timer expected")
        T.eq(armed[1].at - 1000, expiresIn,
            "cleanup timer must fire when the flag expires, not at a hardcoded 2s")
    end)

    T.it("keeps the flag alive past 2s when jitter extended the window", function()
        local fw = freshFW()
        local realRandom = math.random
        math.random = function() return 2000 end   -- 4s window
        fw:EnableGhostForNextSend("Bob")
        math.random = realRandom

        -- A send landing at 3s is inside the 4s window and must still ghost.
        mock.advance(3)
        mock.flushTimers()   -- the old hardcoded 2s timer would have fired by now
        T.truthy(fw:ShouldGhostSendTo("Bob"),
            "flag cleared early: cleanup timer ran before the jittered expiry")
    end)

    T.it("still clears the flag once the window genuinely elapses", function()
        local fw = freshFW()
        local realRandom = math.random
        math.random = function() return 0 end      -- minimum 2s window
        fw:EnableGhostForNextSend("Bob")
        math.random = realRandom

        mock.advance(2)
        mock.flushTimers()
        T.falsy(fw:ShouldGhostSendTo("Bob"), "flag should be gone after its window")
        T.eq(fw.ghostNextSend, nil, "auto-cleanup should nil the flag")
    end)

    T.it("expiry check in ShouldGhostSendTo agrees with the armed window", function()
        local fw = freshFW()
        local realRandom = math.random
        math.random = function() return 1000 end   -- 3s window
        fw:EnableGhostForNextSend("Bob")
        math.random = realRandom

        mock.advance(2.5)
        T.truthy(fw:ShouldGhostSendTo("Bob"), "2.5s is inside a 3s window")
        mock.advance(1)
        T.falsy(fw:ShouldGhostSendTo("Bob"), "3.5s is outside a 3s window")
    end)

    T.it("replacing a flag cancels the previous timer so it cannot clear the new one", function()
        local fw = freshFW()
        fw:EnableGhostForNextSend("Bob")
        local firstGen = fw.ghostNextSend.generation

        mock.advance(1)
        fw:EnableGhostForNextSend("Carol")
        T.truthy(fw.ghostNextSend.generation > firstGen, "generation should advance")

        -- Fire everything due; Bob's timer must not take Carol's flag down.
        mock.advance(1.5)
        mock.flushTimers()
        T.eq(fw.ghostNextSend and fw.ghostNextSend.target, "Carol",
            "previous player's cleanup timer clobbered the current flag")
    end)
end)

-- ===================== BUG 2: hasTRP3ExchangeHooks =====================

T.describe("InstallSendObjectHook - hasTRP3ExchangeHooks", function()

    -- Minimal namespace able to load hooks/trp3.lua and run just the installer.
    local function fwWithSendObject()
        local fw = H.newNamespace()
        fw.Prefs = { monitorTRP3 = true }
        fw.hookState = { originals = {} }
        fw.hookStatus = {}
        fw.hasTRP3ExchangeHooks = false   -- as core/init.lua leaves it
        function fw:CleanPlayerName(n) return n end
        function fw:CheckHookConflict() return { action = "install" } end
        return fw
    end

    T.it("sets the flag when the hook installs successfully", function()
        local fw = fwWithSendObject()
        _G.AddOn_TotalRP3 = { Communications = { sendObject = function() end } }
        H.loadModule("hooks/trp3.lua", fw)

        local ok = fw:InstallSendObjectHook()
        T.truthy(ok, "install should succeed")
        T.truthy(fw.hasTRP3ExchangeHooks,
            "sendObject IS the TRP3 exchange hook; the flag gating TRP3 ghosting must be set")
        _G.AddOn_TotalRP3 = nil
    end)

    T.it("sets the flag on the already-installed skip path", function()
        local fw = fwWithSendObject()
        function fw:CheckHookConflict() return { action = "skip" } end
        _G.AddOn_TotalRP3 = { Communications = { sendObject = function() end } }
        H.loadModule("hooks/trp3.lua", fw)

        fw:InstallSendObjectHook()
        T.truthy(fw.hasTRP3ExchangeHooks,
            "an already-installed hook is still ours, so ghosting is still available")
        _G.AddOn_TotalRP3 = nil
    end)

    T.it("leaves the flag false when the hook cannot be installed", function()
        local fw = fwWithSendObject()
        _G.AddOn_TotalRP3 = nil   -- TRP3 comms missing
        H.loadModule("hooks/trp3.lua", fw)

        local ok = fw:InstallSendObjectHook()
        T.falsy(ok, "install should fail without AddOn_TotalRP3.Communications")
        T.falsy(fw.hasTRP3ExchangeHooks,
            "flag must stay false when TRP3 ghosting really is unavailable")
    end)

    T.it("leaves the flag false when a conflicting hook is refused", function()
        local fw = fwWithSendObject()
        function fw:CheckHookConflict() return { action = "refuse" } end
        _G.AddOn_TotalRP3 = { Communications = { sendObject = function() end } }
        H.loadModule("hooks/trp3.lua", fw)

        local ok = fw:InstallSendObjectHook()
        T.falsy(ok, "refused install should return false")
        T.falsy(fw.hasTRP3ExchangeHooks,
            "a refused hook means no ghosting, so the flag must stay false")
        _G.AddOn_TotalRP3 = nil
    end)
end)

-- ===================== BUG 2 consequence: burst ghosting =====================

T.describe("ProcessBurstBlocks - TRP3/Chomp ghost path", function()

    T.it("ghosts queued Chomp siblings once the exchange-hook flag is set", function()
        local fw = freshFW()
        fw.ServiceContainer = { Get = function() return nil end }
        H.loadModule("features/decision.lua", fw)

        fw.hasTRP3ExchangeHooks = true
        local sent = {}
        fw.originalChompSend = function(prefix, text) sent[#sent + 1] = text end
        fw.pendingChompSends = {
            Bob = { queuedRequests = {
                { prefix = "TRP3", text = "payload1", queuedAt = mock.clock },
                { prefix = "TRP3", text = "payload2", queuedAt = mock.clock },
            } }
        }

        fw:ProcessBurstBlocks("Bob", true)
        T.eq(#sent, 2, "both burst siblings should have been ghost-sent")
        T.eq(fw.pendingChompSends.Bob, nil, "queue should be cleared")
    end)

    T.it("drops queued siblings (fail-closed) when ghosting is unavailable", function()
        local fw = freshFW()
        fw.ServiceContainer = { Get = function() return nil end }
        H.loadModule("features/decision.lua", fw)

        fw.hasTRP3ExchangeHooks = false   -- no exchange hook -> cannot ghost
        local sent = {}
        fw.originalChompSend = function(prefix, text) sent[#sent + 1] = text end
        fw.pendingChompSends = {
            Bob = { queuedRequests = {
                { prefix = "TRP3", text = "payload1", queuedAt = mock.clock },
            } }
        }

        fw:ProcessBurstBlocks("Bob", true)
        T.eq(#sent, 0, "must not send the real profile when ghosting is impossible")
        T.eq(fw.pendingChompSends.Bob, nil, "queue should still be cleared")
    end)
end)
