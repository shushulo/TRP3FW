-- tests/unit/event_service_spec.lua
-- Headless tests for core/EventService.lua's callback registry and dispatch.
--
-- The case that motivated these: location/phase.lua registers a one-shot
-- TARGET_CHANGED handler per batch step which, from inside its own invocation,
-- unregisters itself (finishStep) and registers its successor (processNext).
-- Dispatching over the live array meant table.remove shifted the *next* callback
-- into an index the ipairs loop had already passed, so CacheService's interaction
-- tracker silently missed the very target events batch phase checking generates.
--
-- Frame/event plumbing (Initialize, :Listen, OnEvent routing) is not covered here
-- -- that needs a real client. These exercise the pure registry logic, which is
-- where the ordering bug lived.

local T = require("tests.framework")
local H = require("tests.harness")

local TRP3FW = H.newNamespace()
H.loadModule("core/Service.lua", TRP3FW)
H.loadModule("core/ServiceContainer.lua", TRP3FW)
H.loadModule("core/EventService.lua", TRP3FW)

local ES = TRP3FW.ServiceContainer:Get("EventService")

-- EventService is a singleton registered at load, so specs share one callback
-- table. Clear it between tests to keep them independent.
local function reset()
    ES.callbacks = {}
end

T.describe("EventService registration", function()
    T.it("registers the service under its name", function()
        T.truthy(ES, "EventService is retrievable from the container")
        T.eq(ES:GetName(), "EventService")
    end)

    T.it("runs callbacks in priority order, lowest first", function()
        reset()
        local trace = {}
        ES:RegisterCallback("E", function() table.insert(trace, "late") end, 90)
        ES:RegisterCallback("E", function() table.insert(trace, "early") end, 10)
        ES:RegisterCallback("E", function() table.insert(trace, "mid") end, 50)

        ES:Trigger("E", "E")
        T.eq(table.concat(trace, ","), "early,mid,late")
    end)

    T.it("passes the source event and payload through to callbacks", function()
        reset()
        local got
        ES:RegisterCallback("E", function(sourceEvent, a, b) got = { sourceEvent, a, b } end)

        ES:Trigger("E", "PLAYER_LOGIN", "x", 7)
        T.eq(got[1], "PLAYER_LOGIN")
        T.eq(got[2], "x")
        T.eq(got[3], 7)
    end)

    T.it("ignores registration with a missing event or function", function()
        reset()
        T.no_raise(function()
            ES:RegisterCallback(nil, function() end)
            ES:RegisterCallback("E", nil)
        end)
        T.falsy(ES.callbacks["E"], "no callback list created for a nil func")
    end)

    T.it("Trigger on an event with no listeners is a no-op", function()
        reset()
        T.no_raise(function() ES:Trigger("NOBODY_LISTENING", "NOBODY_LISTENING") end)
    end)
end)

T.describe("EventService error isolation", function()
    T.it("a throwing callback does not stop later callbacks", function()
        reset()
        local errors = {}
        TRP3FW.Error = function(_, msg) table.insert(errors, msg) end

        local reached = false
        ES:RegisterCallback("E", function() error("boom") end, 10)
        ES:RegisterCallback("E", function() reached = true end, 20)

        ES:Trigger("E", "E")
        T.truthy(reached, "the callback after the throwing one still ran")
        T.truthy(#errors >= 1, "the failure was logged")

        TRP3FW.Error = function() end
    end)
end)

T.describe("EventService dispatch is stable under mutation", function()
    -- The core regression. Before the snapshot fix this left `survivor` false.
    T.it("a callback unregistering itself does not skip the next callback", function()
        reset()
        local survivor = false

        local oneShot
        oneShot = function()
            ES:UnregisterCallback("TARGET_CHANGED", oneShot)
        end

        ES:RegisterCallback("TARGET_CHANGED", oneShot, 10)
        ES:RegisterCallback("TARGET_CHANGED", function() survivor = true end, 20)

        ES:Trigger("TARGET_CHANGED", "PLAYER_TARGET_CHANGED")
        T.truthy(survivor, "the callback following the self-unregistering one still ran")
        T.eq(#ES.callbacks["TARGET_CHANGED"], 1, "only the one-shot was removed")
    end)

    -- phase.lua's actual shape: unregister self, then register the next step's
    -- handler, all from inside the dispatch.
    T.it("a callback that unregisters itself and registers a successor is not lossy", function()
        reset()
        local trace = {}

        local step
        step = function()
            table.insert(trace, "step")
            ES:UnregisterCallback("TARGET_CHANGED", step)
            ES:RegisterCallback("TARGET_CHANGED", function() table.insert(trace, "next") end, 10)
        end

        ES:RegisterCallback("TARGET_CHANGED", step, 10)
        ES:RegisterCallback("TARGET_CHANGED", function() table.insert(trace, "tracker") end, 50)

        ES:Trigger("TARGET_CHANGED", "PLAYER_TARGET_CHANGED")
        -- The successor registered mid-dispatch defers to the next event; the
        -- interaction tracker must not be lost.
        T.eq(table.concat(trace, ","), "step,tracker")

        -- And on the following event the successor does run.
        ES:Trigger("TARGET_CHANGED", "PLAYER_TARGET_CHANGED")
        T.eq(table.concat(trace, ","), "step,tracker,next,tracker")
    end)

    T.it("a callback unregistered by an earlier callback does not fire", function()
        reset()
        local laterRan = false
        local later = function() laterRan = true end

        ES:RegisterCallback("E", function() ES:UnregisterCallback("E", later) end, 10)
        ES:RegisterCallback("E", later, 20)

        ES:Trigger("E", "E")
        T.falsy(laterRan, "a callback removed mid-dispatch is skipped, not stale-fired")
    end)

    T.it("a callback registered mid-dispatch does not run in that same dispatch", function()
        reset()
        local addedRan = false

        ES:RegisterCallback("E", function()
            ES:RegisterCallback("E", function() addedRan = true end, 99)
        end, 10)

        ES:Trigger("E", "E")
        T.falsy(addedRan, "registrations during dispatch defer to the next event")

        ES:Trigger("E", "E")
        T.truthy(addedRan, "and take effect on the next event")
    end)

    T.it("unregistering an unknown callback is harmless", function()
        reset()
        ES:RegisterCallback("E", function() end)
        T.no_raise(function()
            ES:UnregisterCallback("E", function() end)
            ES:UnregisterCallback("NOPE", function() end)
        end)
        T.eq(#ES.callbacks["E"], 1)
    end)
end)

return T
