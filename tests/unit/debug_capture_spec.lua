-- tests/unit/debug_capture_spec.lua
-- Headless tests for debug log capture routing in core/utils.lua.
--
-- The debug window buffer is fed on every Debug() call while debug mode is on,
-- regardless of the "Debug output destination" setting. Previously the buffer was
-- only fed when the destination included Window, so opening the window after an
-- event showed nothing. The destination setting now only controls chat output.
--
-- The window frame itself (ui/debugwindow.lua) needs CreateFrame and is verified
-- in-game; this spec covers the routing decision that feeds it.

local T = require("tests.framework")
local H = require("tests.harness")

-- Build a namespace with the real Debug() plus capture stubs for both sinks.
local function newDebugNamespace(prefs)
    local fw = H.newNamespace()
    fw.Prefs = prefs
    H.loadModule("core/utils.lua", fw)

    local captured = { chat = {}, window = {} }

    -- Stub the chat sink (real PrintColored needs COLOR + print).
    function fw:PrintColored(_, msg)
        table.insert(captured.chat, msg)
    end

    -- Stub the window sink (real one lives in ui/debugwindow.lua behind CreateFrame).
    function fw:AddDebugMessage(msg, category)
        table.insert(captured.window, { msg = msg, category = category })
    end

    return fw, captured
end

T.describe("Debug capture: master toggle", function()
    T.it("captures nothing at all when debug mode is off", function()
        local fw, cap = newDebugNamespace({ debug = false, debugOutputChat = true })
        fw:Debug("hello", "decision")
        T.eq(#cap.chat, 0)
        T.eq(#cap.window, 0, "buffer must stay empty when debug is off")
    end)
end)

T.describe("Debug capture: output destination", function()
    T.it("buffers for the window even with destination set to Chat only", function()
        local fw, cap = newDebugNamespace({
            debug = true,
            debugOutputChat = true,
            debugOutputWindow = false,
            debugOutputBoth = false,
            debugDecision = true,
        })
        fw:Debug("chat only", "decision")
        T.eq(#cap.chat, 1, "chat destination still prints")
        T.eq(#cap.window, 1, "window buffer is fed regardless of destination")
    end)

    T.it("buffers without printing to chat when destination is Window only", function()
        local fw, cap = newDebugNamespace({
            debug = true,
            debugOutputChat = false,
            debugOutputWindow = true,
            debugOutputBoth = false,
            debugDecision = true,
        })
        fw:Debug("window only", "decision")
        T.eq(#cap.chat, 0, "Window destination suppresses chat spam")
        T.eq(#cap.window, 1)
    end)

    T.it("feeds both sinks exactly once when destination is Both", function()
        local fw, cap = newDebugNamespace({
            debug = true,
            debugOutputChat = true,
            debugOutputWindow = true,
            debugOutputBoth = true,
            debugDecision = true,
        })
        fw:Debug("both", "decision")
        T.eq(#cap.chat, 1)
        T.eq(#cap.window, 1, "no duplicate buffer entry for Both")
    end)
end)

T.describe("Debug capture: category filtering", function()
    T.it("respects a disabled category for the buffer too", function()
        local fw, cap = newDebugNamespace({
            debug = true,
            debugOutputChat = true,
            debugCache = false,
            debugDecision = true,
        })
        fw:Debug("cache noise", "cache")
        T.eq(#cap.window, 0, "filtered-out categories are not buffered")

        fw:Debug("decision kept", "decision")
        T.eq(#cap.window, 1)
    end)

    T.it("passes the category through to the buffer for later filtering", function()
        local fw, cap = newDebugNamespace({ debug = true, debugOutputChat = false, debugSPVP = true })
        fw:Debug("handshake", "spvp")
        T.eq(#cap.window, 1)
        T.eq(cap.window[1].category, "spvp")
    end)

    T.it("buffers messages with no category", function()
        local fw, cap = newDebugNamespace({ debug = true, debugOutputChat = false })
        fw:Debug("uncategorised")
        T.eq(#cap.window, 1)
        T.is_nil(cap.window[1].category)
    end)
end)

T.describe("Debug capture: lazy messages", function()
    T.it("evaluates function messages once and buffers the result", function()
        local calls = 0
        local fw, cap = newDebugNamespace({ debug = true, debugOutputChat = true, debugDecision = true })
        fw:Debug(function() calls = calls + 1; return "lazy result" end, "decision")
        T.eq(calls, 1, "message builder runs once for both sinks")
        T.eq(#cap.window, 1)
        T.truthy(cap.window[1].msg:find("lazy result", 1, true))
    end)

    T.it("does not evaluate function messages when debug is off", function()
        local calls = 0
        local fw = newDebugNamespace({ debug = false })
        fw:Debug(function() calls = calls + 1; return "never" end, "decision")
        T.eq(calls, 0)
    end)
end)

return T
