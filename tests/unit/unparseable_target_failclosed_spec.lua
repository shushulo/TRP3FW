-- tests/unit/unparseable_target_failclosed_spec.lua
-- An unidentifiable recipient must never receive an ungated transmission.
--
-- Both send paths used to treat "CleanPlayerName returned nil" as permission to send:
--   * hooks/trp3.lua:304          -> return originalFunc(...)
--   * hooks/trp3_scan_pipeline.lua:307 -> "-- Invalid name, allow"
--
-- In both cases the ENTIRE pipeline was skipped -- no whitelist, no cache, no location check,
-- no ghosting -- for a send addressed to a specific named recipient. The scan-reply one is the
-- more sensitive of the two: a C_SCAN reply carries the player's exact map coordinates
-- (PlayerMapScanner.lua:161), so an ungated reply discloses physical position to someone who
-- may be explicitly blocked.
--
-- Not remotely exploitable -- the target is a server-supplied character name, capped at 12
-- chars plus realm, and services initialise a second before hooks install -- so this is a
-- "should never happen" branch. That is precisely why it must fail closed: an unreachable
-- branch that silently transmits is one whose failure nobody would ever notice.
--
-- The distinction that must be preserved: a nil TARGET (broadcast/channel send with no specific
-- recipient) is normal protocol traffic and must still pass through. Only an unparseable
-- non-nil target is blocked.

local T = require("tests.framework")
local H = require("tests.harness")

-- ===================== Chomp send path =====================

local function chompFixture(cleanImpl)
    local fw = H.newNamespace()
    fw.Prefs = {}
    fw.hookState = {}
    fw.ServiceContainer = { Get = function() return nil end }

    local sent = {}
    local function originalFunc(prefix, text, chatType, target)
        sent[#sent + 1] = { prefix = prefix, text = text, target = target }
        return "SENT"
    end

    function fw:Warn() end
    function fw:CleanPlayerName(n) return cleanImpl(n) end
    -- Guards pass; stop the pipeline right after the name check so the test isolates it.
    function fw:ChompPipeline_GuardChecks_V2() return { shouldContinue = true, reason = "guards_passed" } end
    function fw:CreateVerifiedSendId() return { id = 1 } end
    function fw:ShouldGhostSendTo() return false end
    function fw:ChompPipeline_PhaseInDelay_V2() return { shouldContinue = false, queued = true } end

    H.loadModule("hooks/trp3.lua", fw)
    return fw, originalFunc, sent
end

T.describe("Chomp hook: unparseable target", function()
    T.it("blocks the send when the target cannot be parsed", function()
        local fw, orig, sent = chompFixture(function() return nil end)

        fw:ChompHookPipeline("TRP3", "profile data", "WHISPER", "\1\2bad", nil, nil, nil, nil, orig)

        T.eq(#sent, 0, "an unidentifiable recipient must not receive an ungated send")
    end)

    T.it("still passes through a broadcast send with no target", function()
        -- nil target = channel/broadcast traffic, not a per-recipient decision.
        local fw, orig, sent = chompFixture(function() return nil end)

        fw:ChompHookPipeline("TRP3", "broadcast", "CHANNEL", nil, nil, nil, nil, nil, orig)

        T.eq(#sent, 1, "broadcast traffic must not be broken by the fail-closed change")
    end)

    T.it("proceeds normally when the target parses", function()
        local fw, orig, sent = chompFixture(function(n) return n end)

        -- Reaches the phase-in stage, which queues; the point is that it got past the guard.
        fw:ChompHookPipeline("TRP3", "profile data", "WHISPER", "Arthas", nil, nil, nil, nil, orig)

        T.eq(#sent, 0, "queued by the phase-in stage rather than blocked at the name check")
    end)
end)

-- ===================== Scan reply path =====================

local function scanFixture(cleanImpl)
    local fw = H.newNamespace()
    fw.Prefs = { scanResponsePhaseMode = "off", scanResponseMapMode = "off" }
    fw.ServiceContainer = { Get = function() return nil end }
    fw.CacheInterface = nil

    local sent = {}
    local function originalFunc()
        sent[#sent + 1] = true
        return "REPLIED"
    end

    function fw:CleanPlayerName(n) return cleanImpl(n) end
    function fw:ShowScanNotification() end
    -- Stubs for the stages after the name check. With both scan modes "off" the pipeline
    -- short-circuits to an allow, so these only need to decline and let it fall through.
    function fw:IsPlayerWhitelisted() return false end
    function fw:IsMapCheckEnabled() return false end
    function fw:IsPhaseCheckEnabled() return false end
    function fw:IsInGroupWith() return false end

    H.loadModule("hooks/trp3_scan_pipeline.lua", fw)
    return fw, originalFunc, sent
end

T.describe("Scan reply: unparseable target", function()
    T.it("drops the reply rather than disclosing coordinates ungated", function()
        local fw, orig, sent = scanFixture(function() return nil end)

        fw:HandleScanReplyPipeline("\1\2bad", orig, "TRP3")

        T.eq(#sent, 0, "coordinates must not be sent to an unidentifiable recipient")
    end)

    T.it("still replies when the name parses and checks are disabled", function()
        local fw, orig, sent = scanFixture(function(n) return n end)

        fw:HandleScanReplyPipeline("Arthas", orig, "TRP3")

        T.eq(#sent, 1, "normal scan replies must be unaffected")
    end)
end)

return T
