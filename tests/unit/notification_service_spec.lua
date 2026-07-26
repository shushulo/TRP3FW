-- tests/unit/notification_service_spec.lua
-- Headless tests for features/services/NotificationService.lua.
--
-- The subject here is the suppression bookkeeping and, specifically, whether the
-- count it accumulates ever reaches the user. NotificationService:ShouldSuppress
-- carefully tallies how many notifications it swallowed during a suppression
-- window and hands that number back to Notify, and ShowChatNotification knows how
-- to render it as "(+N suppressed in last Xs)". But Notify passed a hardcoded
-- `isFirstTime = true` into ShowChatNotification, whose gate is
-- `if not isFirstTime and suppressedCount > 0`. With isFirstTime pinned true that
-- branch was unreachable: the rollup never rendered on the production path, and the
-- "(again)" marker and the yellow repeat colour in ShowOnScreenNotification were
-- dead too. Every notification looked like a first sighting.
--
-- Only decision.lua's *fallback* path (used when NotificationService is missing,
-- i.e. never in practice) passed a real isFirstTime, which is why the dead code read
-- as reachable.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function newNotifications(prefs)
    local fw = H.newNamespace()
    fw.Prefs = prefs or {
        notifyEnabled = true,
        showInChat = true,
        showOnScreen = false,
        playSound = false,
        showAddonSource = false,
        suppressionTime = 60,
        notifyOnAllow = true,
    }

    -- Capture what would have been printed to chat.
    local printed = {}
    function fw:PrintColored(_, msg) table.insert(printed, msg) end
    function fw:FormatTime(s) return tostring(s) .. "s" end

    H.loadModule("core/Service.lua", fw)
    H.loadModule("core/ServiceContainer.lua", fw)
    H.loadModule("features/services/NotificationService.lua", fw)

    local svc = fw.ServiceContainer:Get("NotificationService")
    svc:Initialize()
    return fw, svc, printed
end

local function notify(svc, fw, player, notifType)
    svc:Notify(player, {
        type = notifType or "alert",
        addon = "TRP3",
        settings = fw.Prefs,
        isWhisper = true,
    })
end

-- ===================== ShouldSuppress accounting =====================

T.describe("NotificationService:ShouldSuppress", function()
    T.it("never suppresses the first notification for a player", function()
        mock.setClock(1000)
        local fw, svc = newNotifications()
        local suppressed, count = svc:ShouldSuppress("Bob", "alert", fw.Prefs)
        T.falsy(suppressed)
        T.eq(count, 0)
    end)

    T.it("suppresses a repeat inside the window and counts it", function()
        mock.setClock(1000)
        local fw, svc = newNotifications()
        svc:ShouldSuppress("Bob", "alert", fw.Prefs)
        mock.setClock(1010)
        local suppressed, count = svc:ShouldSuppress("Bob", "alert", fw.Prefs)
        T.truthy(suppressed)
        T.eq(count, 1)
    end)

    T.it("returns the accumulated count once the window elapses", function()
        -- refreshSuppression defaults on (~= false), so each suppressed hit slides the
        -- window forward; step past suppressionTime from the LAST hit to escape it.
        mock.setClock(1000)
        local fw, svc = newNotifications()
        svc:ShouldSuppress("Bob", "alert", fw.Prefs)
        mock.setClock(1010)
        svc:ShouldSuppress("Bob", "alert", fw.Prefs)
        mock.setClock(1020)
        svc:ShouldSuppress("Bob", "alert", fw.Prefs)

        mock.setClock(1200)
        local suppressed, count = svc:ShouldSuppress("Bob", "alert", fw.Prefs)
        T.falsy(suppressed, "well past the window - must show")
        T.eq(count, 2, "both swallowed notifications must be reported")
    end)

    T.it("breaks suppression when severity escalates", function()
        mock.setClock(1000)
        local fw, svc = newNotifications()
        svc:ShouldSuppress("Bob", "allow", fw.Prefs)
        mock.setClock(1005)
        local suppressed = svc:ShouldSuppress("Bob", "block", fw.Prefs)
        T.falsy(suppressed, "allow -> block must break through the window")
    end)
end)

-- ===================== The rollup actually reaches the user =====================

T.describe("NotificationService:Notify suppressed-count rollup", function()
    T.it("shows no rollup on a genuine first notification", function()
        mock.setClock(1000)
        local fw, svc, printed = newNotifications()
        notify(svc, fw, "Bob")

        T.eq(#printed, 1)
        T.falsy(printed[1]:find("suppressed", 1, true),
            "nothing was suppressed yet - no rollup")
    end)

    T.it("reports the swallowed count when the window elapses", function()
        mock.setClock(1000)
        local fw, svc, printed = newNotifications()

        notify(svc, fw, "Bob")            -- shown
        mock.setClock(1010)
        notify(svc, fw, "Bob")            -- suppressed
        mock.setClock(1020)
        notify(svc, fw, "Bob")            -- suppressed
        T.eq(#printed, 1, "only the first should have printed so far")

        mock.setClock(1200)
        notify(svc, fw, "Bob")            -- window elapsed -> shown, with the rollup

        T.eq(#printed, 2)
        T.truthy(printed[2]:find("+2 suppressed", 1, true),
            "the two swallowed notifications must be reported to the user, got: " .. printed[2])
    end)

    T.it("marks a repeat sighting as not-first", function()
        mock.setClock(1000)
        local fw, svc, printed = newNotifications()

        notify(svc, fw, "Bob")
        mock.setClock(1010)
        notify(svc, fw, "Bob")            -- suppressed, count -> 1
        mock.setClock(1200)
        notify(svc, fw, "Bob")

        T.truthy(printed[2]:find("suppressed", 1, true),
            "a returning player with swallowed notifications is not a first sighting")
    end)

    T.it("does not claim suppression for a quiet returning player", function()
        -- Seen before, nothing suppressed in between: count is 0, so no rollup even
        -- though this is not literally the first notification.
        mock.setClock(1000)
        local fw, svc, printed = newNotifications()
        notify(svc, fw, "Bob")
        mock.setClock(1200)
        notify(svc, fw, "Bob")

        T.eq(#printed, 2)
        T.falsy(printed[2]:find("suppressed", 1, true),
            "no notifications were swallowed - do not print a zero rollup")
    end)
end)

return T
