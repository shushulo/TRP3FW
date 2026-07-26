-- tests/unit/alert_fastpath_dedup_spec.lua
-- Headless tests for AlertFastPathStage's async-check deduplication.
--
-- AlertFastPathStage sits BEFORE BurstStage in the pipeline and returns handled, so requests
-- in alert-only mode never reach the burst queue. A burst of N requests from one player
-- therefore started N independent CheckLocationCascading runs -- each spending its own WHO
-- query and map scan, all answering the same question about the same player at the same
-- moment, during exactly the traffic spike that produced the burst.
--
-- Only the CHECK is deduplicated. The send must still happen for every request, because
-- alert-only mode gates nothing -- that is what makes it "alert only".

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW()
    local fw = H.newNamespace()
    fw.Prefs = {}
    fw.alertOnlyChecksInFlight = {}

    -- Alert-only: alert on both kinds, block on neither.
    function fw:ShouldAlertOnPhase() return true end
    function fw:ShouldBlockOnPhase() return false end
    function fw:ShouldAlertOnMap() return true end
    function fw:ShouldBlockOnMap() return false end
    function fw:IsPhaseCheckEnabled() return true end
    function fw:IsMapCheckEnabled() return true end
    function fw:IsProfileSwitchOverrideActive() return false end
    function fw:TrackAddonRequest() end
    function fw:AllowSender() end
    function fw:ProcessBurstAllows() end

    fw.ServiceContainer = { Get = function() return nil end }

    -- Count checks started, and capture callbacks so a spec can resolve them.
    fw.checksStarted = 0
    fw.pendingCallbacks = {}
    function fw:CheckLocationCascading(playerName, sendId, callback)
        self.checksStarted = self.checksStarted + 1
        table.insert(self.pendingCallbacks, { playerName = playerName, callback = callback })
    end

    H.loadModule("core/Stage.lua", fw)
    H.loadModule("features/stages/AlertFastPathStage.lua", fw)
    return fw
end

-- Each request carries its own originalFunc so we can count actual sends.
local function ctx(fw, playerName, sends)
    return {
        playerName = playerName, addon = "MSP", sendId = 1, isWhisper = true,
        now = mock.clock,
        settings = { blockStartPhase = false, ghostOnStartPhase = false },
        originalFunc = function() sends[#sends + 1] = playerName end,
        originalArgs = {},
    }
end

T.describe("AlertFastPathStage: sends are never deduplicated", function()
    T.it("every request in a burst is still sent", function()
        mock.setClock(1000)
        local fw = freshFW()
        local sends = {}

        for _ = 1, 5 do
            fw.AlertFastPathStage:Process(ctx(fw, "Bob", sends))
        end

        T.eq(#sends, 5,
            "alert-only mode gates nothing - all 5 requests must reach the wire")
    end)

    T.it("every request reports handled+allowed", function()
        mock.setClock(1000)
        local fw = freshFW()
        local sends = {}

        for i = 1, 3 do
            local r = fw.AlertFastPathStage:Process(ctx(fw, "Bob", sends))
            T.truthy(r.handled, "request "..i.." must be handled")
            T.truthy(r.allowed, "request "..i.." must be allowed")
        end
    end)
end)

T.describe("AlertFastPathStage: async checks ARE deduplicated", function()
    T.it("BUG (fixed): a burst starts ONE check, not N", function()
        mock.setClock(1000)
        local fw = freshFW()
        local sends = {}

        for _ = 1, 5 do
            fw.AlertFastPathStage:Process(ctx(fw, "Bob", sends))
        end

        T.eq(fw.checksStarted, 1,
            "5 requests from one player must not start 5 cascading runs")
    end)

    T.it("different players are not deduplicated against each other", function()
        mock.setClock(1000)
        local fw = freshFW()
        local sends = {}

        fw.AlertFastPathStage:Process(ctx(fw, "Bob", sends))
        fw.AlertFastPathStage:Process(ctx(fw, "Carol", sends))

        T.eq(fw.checksStarted, 2, "dedup is per player, not global")
    end)

    T.it("a resolved check releases the marker immediately", function()
        mock.setClock(1000)
        local fw = freshFW()
        local sends = {}

        fw.AlertFastPathStage:Process(ctx(fw, "Bob", sends))
        T.eq(fw.checksStarted, 1)

        -- Resolve it: source "disabled" avoids the alert branch and its service lookups.
        fw.pendingCallbacks[1].callback(true, nil, "disabled")

        -- A later request should start a fresh check rather than waiting out the window.
        fw.AlertFastPathStage:Process(ctx(fw, "Bob", sends))
        T.eq(fw.checksStarted, 2,
            "once a check has answered, the next request must be free to start another")
    end)

    T.it("a check whose callback never fires cannot latch the player off forever", function()
        -- The reason this is a timestamp window rather than a strict in-flight flag: a
        -- cascading run that drops its callback would otherwise suppress that player's
        -- alerts for the rest of the session.
        mock.setClock(1000)
        local fw = freshFW()
        local sends = {}

        fw.AlertFastPathStage:Process(ctx(fw, "Bob", sends))
        T.eq(fw.checksStarted, 1)

        -- Callback never invoked. Past the dedup window, a new check must be allowed.
        mock.advance(6)
        fw.AlertFastPathStage:Process(ctx(fw, "Bob", sends))

        T.eq(fw.checksStarted, 2, "a hung check must not silence the player permanently")
        T.eq(#sends, 2, "and sends were unaffected throughout")
    end)
end)
