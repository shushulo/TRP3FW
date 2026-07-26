-- tests/unit/pipeline_spec.lua
-- Headless tests for the decision-pipeline engine itself (core/Pipeline.lua,
-- core/Stage.lua) using fake stages. This covers the runner
-- contract that every real stage relies on: stages run in insertion order, the
-- first stage returning { handled = true } short-circuits the rest, and a
-- malformed stage (no :Process) is logged but doesn't halt the pipeline.

local T = require("tests.framework")
local H = require("tests.harness")

local TRP3FW = H.newNamespace()
H.loadModule("core/Stage.lua", TRP3FW)
H.loadModule("core/Pipeline.lua", TRP3FW)
local mock = H.mock

-- Build a stage that records its name into `trace` and returns a fixed result.
local function recordingStage(name, trace, result)
    local s = TRP3FW.Stage:New(name)
    function s:Process(context)
        table.insert(trace, name)
        return result  -- nil or { handled = ... }
    end
    return s
end

T.describe("Pipeline ordering and pass-through", function()
    T.it("runs every stage in insertion order when none handle", function()
        local trace = {}
        local p = TRP3FW.Pipeline:New("p")
        p:AddStage(recordingStage("a", trace, { handled = false }))
        p:AddStage(recordingStage("b", trace, nil))  -- nil result == not handled
        p:AddStage(recordingStage("c", trace, { handled = false }))

        local result = p:Run({})
        T.eq(table.concat(trace, ","), "a,b,c")
        T.falsy(result.handled, "unhandled pipeline reports handled=false")
    end)
end)

T.describe("Pipeline early-exit on handled", function()
    T.it("stops at the first stage returning handled=true", function()
        local trace = {}
        local p = TRP3FW.Pipeline:New("p")
        p:AddStage(recordingStage("first", trace, { handled = false }))
        p:AddStage(recordingStage("decider", trace, { handled = true, allowed = true, reason = "ok" }))
        p:AddStage(recordingStage("never", trace, { handled = false }))

        local result = p:Run({})
        T.eq(table.concat(trace, ","), "first,decider", "stage after the decider must not run")
        T.truthy(result.handled)
        T.truthy(result.allowed)
        T.eq(result.reason, "ok")
    end)
end)

T.describe("Pipeline malformed-stage tolerance", function()
    T.it("logs an error but continues past a stage with no Process", function()
        -- Spy on Error so we can confirm the bad stage was reported.
        local errors = {}
        function TRP3FW:Error(msg) table.insert(errors, msg) end

        local trace = {}
        local p = TRP3FW.Pipeline:New("p")
        p:AddStage({ name = "broken" })  -- no :Process method
        p:AddStage(recordingStage("after", trace, { handled = false }))

        T.no_raise(function() p:Run({}) end)
        T.eq(table.concat(trace, ","), "after", "valid stage after the broken one still runs")
        T.truthy(#errors >= 1, "the malformed stage was logged")

        TRP3FW.Error = function() end  -- restore no-op for any later use
    end)
end)

-- NOTE: a "Context" describe block lived here, covering TRP3FW.Context (core/Context.lua).
-- That class was instantiated ONLY by these tests -- production contexts are plain tables from
-- TRP3FW:CreateDecisionContext, and no production line ever called Context:New or
-- GetTimestamp. The class and its tests were removed rather than adopted: CreateDecisionContext
-- already produces everything the pipeline needs, and keeping both meant two ways to build one
-- thing. The Pipeline tests above now pass plain tables, matching what Run actually receives.

return T
