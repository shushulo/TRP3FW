-- tests/unit/scan_pipeline_who_mode_spec.lua
-- Headless tests for the WHO query-mode selection in hooks/trp3_scan_pipeline.lua's
-- PerformLocationCheck.
--
-- Bug fixed: the block is a copy of WhoService:CheckPlayer's zone-completeness test
-- (features/services/WhoService.lua:272-276) but was missing that function's load-bearing
-- `lastZoneQueryTime > 0` guard. Both zone-tracking fields start at 0/nil and the clock is
-- client uptime, so `now - 0 < 60` held for the first 60 seconds of every session and a zone
-- query that had NEVER RUN was read as "queried just now, and complete".
--
-- WhoService itself was fixed for this in section 2 (see who_service_queue_spec.lua, where
-- the same false premise made WHO checks fail shut). This copy only chooses the query TYPE,
-- so it never failed shut - but it still decided from a premise that was false, and it
-- decided it backwards: once past 60s uptime with no zone query ever run, the old code
-- concluded "stale zone, refresh it" and issued a broad whozone query. TRP3 holds its scan
-- reply window open for only ~3 seconds, so with no zone data at all the direct whoname
-- query is the answer that can actually arrive in time.
--
-- Also collapsed here: of the five branches the old form spelled out, three set
-- `whoNameOnly = true` with comments implying they differed, the fresh+complete branch's
-- inner `if recentMapScan` picked `true` either way, and the trailing `else` was unreachable
-- (the two elseif conditions are exhaustive once the first branch is excluded). Verified by
-- exhaustive comparison: of 750 input combinations across the four state variables, the only
-- ones where old and new disagree are exactly those with lastZoneQueryTime == 0.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW()
    local fw = H.newNamespace()
    fw.Prefs = { spvpMode = "off" }
    fw.currentZoneName = "Stormwind City"
    fw.lastMapScanAt = 0

    fw.whoService = {
        lastZoneQueryTime = 0,
        lastZoneResultCount = nil,
    }
    fw.ServiceContainer = {
        Get = function(_, name)
            if name == "WhoService" then return fw.whoService end
            return nil
        end
    }

    function fw:CreateVerifiedSendId() return { id = 1 } end
    function fw:IsPlayerWhitelisted() return false end
    function fw:IsMapCheckEnabled() return true end
    function fw:GetCurrentMapID() return 84 end

    -- Capture the options the cascading check is invoked with.
    fw.captured = nil
    function fw:CheckLocationCascading(playerName, sendId, callback, options)
        fw.captured = options
    end

    local mod = H.loadModule("hooks/trp3_scan_pipeline.lua", fw)
    return fw, mod
end

-- Run PerformLocationCheck and report the whoNameOnly it selected.
local function selectMode(fw, mod)
    mod.PerformLocationCheck(fw, "Bob", function() end, nil)
    return fw.captured.whoNameOnly
end

T.describe("scan reply WHO mode: a never-run zone query proves nothing", function()
    T.it("BUG (fixed): uses a name query when no zone query has ever run", function()
        mock.setClock(100)  -- past the 60s zone TTL
        local fw, mod = freshFW()
        fw.whoService.lastZoneQueryTime = 0     -- never queried
        fw.whoService.lastZoneResultCount = nil

        T.eq(selectMode(fw, mod), true,
            "with no zone data at all, the ~3s TRP3 reply window needs the direct whoname "
            .. "query - the old code read 'stale' and issued a broad whozone refresh instead")
    end)

    T.it("BUG (fixed): does not treat time-zero as a fresh complete scan during early uptime", function()
        mock.setClock(30)  -- inside the 60s window, where `now - 0 < 60` used to hold
        local fw, mod = freshFW()
        fw.whoService.lastZoneQueryTime = 0
        fw.whoService.lastZoneResultCount = nil

        -- The selected mode is the same as the old code's here, but for a sound reason
        -- rather than the false "scanned at t=0, found 0, therefore complete" premise.
        T.eq(selectMode(fw, mod), true, "never-scanned is not fresh-and-complete")
    end)
end)

T.describe("scan reply WHO mode: the one case that wants a zone query", function()
    T.it("allows a whozone refresh for a stale, complete, uncontested zone", function()
        mock.setClock(500)
        local fw, mod = freshFW()
        fw.whoService.lastZoneQueryTime = 400   -- 100s ago: stale (>60s TTL)
        fw.whoService.lastZoneResultCount = 12  -- under 50: was not truncated
        fw.lastMapScanAt = 0                    -- no map scan competing for the window

        T.eq(selectMode(fw, mod), false,
            "a stale but previously-complete zone is worth refreshing for other scanners")
    end)

    T.it("prefers a name query when a map scan is competing for the reply window", function()
        mock.setClock(500)
        local fw, mod = freshFW()
        fw.whoService.lastZoneQueryTime = 400
        fw.whoService.lastZoneResultCount = 12
        fw.lastMapScanAt = 498  -- 2s ago, inside the 5s "recent" window

        T.eq(selectMode(fw, mod), true, "the tight scan window needs the fast answer")
    end)

    T.it("forces a name query when the last zone query was truncated", function()
        mock.setClock(500)
        local fw, mod = freshFW()
        fw.whoService.lastZoneQueryTime = 400
        fw.whoService.lastZoneResultCount = 50  -- hit the result limit: truncated
        fw.lastMapScanAt = 0

        T.eq(selectMode(fw, mod), true,
            "a truncated zone list cannot prove absence, so query the player by name")
    end)

    T.it("uses a name query while the zone cache is still fresh", function()
        mock.setClock(430)
        local fw, mod = freshFW()
        fw.whoService.lastZoneQueryTime = 400   -- 30s ago: inside the 60s TTL
        fw.whoService.lastZoneResultCount = 12
        fw.lastMapScanAt = 0

        T.eq(selectMode(fw, mod), true, "the zone completeness check handles a fresh zone")
    end)
end)

T.describe("scan reply WHO mode: degrades without WhoService", function()
    T.it("falls back to a name query when WhoService is absent", function()
        mock.setClock(500)
        local fw, mod = freshFW()
        fw.ServiceContainer = { Get = function() return nil end }

        T.eq(selectMode(fw, mod), true, "no zone state to reason about")
    end)
end)

T.describe("scan reply WHO mode: other options passed to the cascading check", function()
    T.it("marks scan replies HIGH priority", function()
        mock.setClock(500)
        local fw, mod = freshFW()
        selectMode(fw, mod)
        T.eq(fw.captured.priority, "HIGH",
            "TRP3 only holds the reply window open for ~3s")
    end)

    T.it("downgrades a non-required SPVP mode to optional", function()
        mock.setClock(500)
        local fw, mod = freshFW()
        fw.Prefs.spvpMode = "off"
        selectMode(fw, mod)
        T.eq(fw.captured.spvpMode, "optional")

        fw.Prefs.spvpMode = "required"
        selectMode(fw, mod)
        T.eq(fw.captured.spvpMode, "required", "required stays required")
    end)

    T.it("lets caller-supplied options override the defaults", function()
        mock.setClock(500)
        local fw, mod = freshFW()
        mod.PerformLocationCheck(fw, "Bob", function() end,
            { priority = "NORMAL", phaseCheckEnabled = false })
        T.eq(fw.captured.priority, "NORMAL")
        T.eq(fw.captured.phaseCheckEnabled, false)
    end)
end)
