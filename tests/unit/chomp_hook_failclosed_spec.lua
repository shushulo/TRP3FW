-- tests/unit/chomp_hook_failopen_spec.lua
-- The installed AddOn_Chomp.SmartAddonMessage wrapper must contain errors and FAIL CLOSED.
--
-- InstallChompHook REPLACES AddOn_Chomp.SmartAddonMessage globally, so TRP3FW's decision
-- pipeline executes inside TRP3's own send call for every profile message. Two requirements,
-- and they pull in opposite directions:
--
--   1. CONTAIN. An unprotected Lua error propagates out of Chomp into TRP3, aborting TRP3's
--      send mid-flight, leaving Chomp's queue inconsistent, and surfacing as a TRP3 bug whose
--      stack never mentions TRP3FW. So the pipeline call is pcall-wrapped.
--
--   2. FAIL CLOSED. Containment must NOT mean "recover by sending anyway". This is a privacy
--      tool, and the code most likely to be running when the pipeline throws is the code
--      deciding *not* to transmit real profile data (ShouldBlockForStartPhase,
--      EnableGhostForNextSend, location gating). Calling originalSend on error would convert a
--      crash in exactly that logic into a full unfiltered send of the real profile, to the
--      player the user configured the addon to hide from, silently. A profile that fails to
--      arrive is visible and recoverable; a disclosure is not.
--
-- Dropping is also what the unguarded code did (the error killed the send), so the pcall adds
-- containment without weakening the security behaviour.

local T = require("tests.framework")
local H = require("tests.harness")

local function installHook(pipelineImpl)
    local fw = H.newNamespace()
    fw.Prefs = { strictHookMode = false }
    fw.hookStatus = {}
    fw.hookConflicts = {}
    fw.ServiceContainer = { Get = function() return nil end }

    local errors = {}
    function fw:Error(msg) errors[#errors + 1] = tostring(msg) end

    -- Records anything that reaches the REAL send. On the error path this must stay empty.
    local sent = {}
    _G.AddOn_Chomp = {
        SmartAddonMessage = function(prefix, text, chatType, target, ...)
            sent[#sent + 1] = { prefix = prefix, text = text, chatType = chatType, target = target }
            return "SENT"
        end,
    }
    _G.debugprofilestop = function() return 0 end

    H.loadModule("hooks/installer.lua", fw)
    H.loadModule("hooks/trp3.lua", fw)

    fw.ChompHookPipeline = pipelineImpl

    local installed = fw:InstallChompHook()
    return fw, _G.AddOn_Chomp.SmartAddonMessage, sent, errors, installed
end

T.describe("Chomp hook error containment", function()
    T.it("installs over AddOn_Chomp.SmartAddonMessage", function()
        local _, wrapper, _, _, installed = installHook(function() return "OK" end)
        T.truthy(installed, "InstallChompHook should report success")
        T.truthy(type(wrapper) == "function", "wrapper must be callable")
    end)

    T.it("returns the pipeline's value when the pipeline succeeds", function()
        local calls = 0
        local _, wrapper, sent = installHook(function()
            calls = calls + 1
            return "PIPELINE_RESULT"
        end)

        local ret = wrapper("TRP3", "body", "WHISPER", "Someone")
        T.eq(ret, "PIPELINE_RESULT", "wrapper returns what the pipeline returned")
        T.eq(calls, 1, "pipeline ran exactly once")
        T.eq(#sent, 0, "pipeline owns the send; wrapper must not double-send")
    end)

    T.it("does not let a pipeline error escape into TRP3", function()
        local _, wrapper = installHook(function() error("simulated pipeline explosion") end)

        local ok = pcall(wrapper, "TRP3", "body", "WHISPER", "Someone")
        T.truthy(ok, "the error must be contained, not propagated into TRP3's send")
    end)

    T.it("DROPS the send when the pipeline errors (fails closed, no leak)", function()
        local _, wrapper, sent = installHook(function() error("simulated pipeline explosion") end)

        local ok, ret = pcall(wrapper, "TRP3", "body", "WHISPER", "Someone")

        T.truthy(ok, "contained")
        -- The security assertion: nothing reached the wire.
        T.eq(#sent, 0, "an unfiltered profile must NEVER be sent after a gating failure")
        T.eq(ret, nil, "wrapper reports no send result")
    end)

    T.it("never leaks even under repeated failures", function()
        local _, wrapper, sent = installHook(function() error("boom") end)
        for i = 1, 5 do
            local ok = pcall(wrapper, "TRP3", "body", "WHISPER", "P" .. i)
            T.truthy(ok, "call " .. i .. " must not throw")
        end
        T.eq(#sent, 0, "no send may escape gating, however many times the pipeline fails")
    end)

    T.it("reports the failure rather than swallowing it", function()
        local _, wrapper, _, errors = installHook(function()
            error("simulated pipeline explosion")
        end)
        wrapper("TRP3", "body", "WHISPER", "Someone")

        T.eq(#errors, 1, "exactly one error reported")
        T.truthy(errors[1]:find("simulated pipeline explosion", 1, true),
            "the original error text is preserved for diagnosis")
        T.truthy(errors[1]:find("dropped", 1, true),
            "the message must say the send was dropped, so a silent non-delivery is explainable")
    end)
end)

return T
