-- tests/unit/history_service_spec.lua
-- Headless tests for HistoryService (features/services/HistoryService.lua):
-- session-stat accounting and send-history bookkeeping. These are pure table
-- math. Two documented past bugs are guarded here: the per-type block/ghost
-- breakdown fields that nothing populated, and the combined-alertType (":find")
-- accounting that must bump both phase and map counters for "phase+map".

local T = require("tests.framework")
local H = require("tests.harness")

-- Build a HistoryService instance on a fresh namespace and initialize it.
-- SecurityService is intentionally NOT loaded: RecordHistory falls back to the
-- raw player name when the service is absent, which keeps these tests focused on
-- the accounting logic rather than sanitization (covered by sanitize_spec).
local function newHistory(prefs)
    local fw = H.newNamespace()
    fw.Prefs = prefs or { trackHistory = true, maxHistorySize = 50 }
    H.loadModule("core/Service.lua", fw)
    H.loadModule("core/ServiceContainer.lua", fw)
    H.loadModule("features/services/HistoryService.lua", fw)
    local svc = fw.ServiceContainer:Get("HistoryService")
    svc:Initialize()
    return fw, svc
end

-- ===================== RecordHistory: counters =====================

T.describe("HistoryService:RecordHistory alert/block/ghost counters", function()
    T.it("does nothing when trackHistory is off", function()
        local fw, svc = newHistory({ trackHistory = false, maxHistorySize = 50 })
        svc:RecordHistory("Bob", "TRP3", true, true, false, "phase")
        T.eq(#svc.notificationHistory, 0)
        T.eq(svc.sessionStats.alerts, 0)
    end)

    T.it("counts a plain alert", function()
        local fw, svc = newHistory()
        svc:RecordHistory("Bob", "TRP3", true, false, false, "phase")
        T.eq(svc.sessionStats.alerts, 1)
        T.eq(svc.sessionStats.blocks, 0)
        T.eq(svc.sessionStats.ghostSends, 0)
    end)

    T.it("routes a block vs a ghost correctly", function()
        local fw, svc = newHistory()
        svc:RecordHistory("Bob", "TRP3", true, true, false, "map")   -- block
        svc:RecordHistory("Cid", "TRP3", true, true, true,  "map")   -- ghost
        T.eq(svc.sessionStats.blocks, 1)
        T.eq(svc.sessionStats.ghostSends, 1)
    end)
end)

T.describe("HistoryService:RecordHistory per-type breakdown (the unpopulated-fields bug)", function()
    T.it("a phase block bumps phaseBlocks, not mapBlocks", function()
        local fw, svc = newHistory()
        svc:RecordHistory("Bob", "TRP3", true, true, false, "phase")
        T.eq(svc.sessionStats.phaseBlocks, 1)
        T.eq(svc.sessionStats.mapBlocks, 0)
        T.eq(svc.sessionStats.phaseAlerts, 1)
    end)

    T.it("a map ghost bumps mapGhost, not phaseGhost", function()
        local fw, svc = newHistory()
        svc:RecordHistory("Bob", "TRP3", true, true, true, "map")
        T.eq(svc.sessionStats.mapGhost, 1)
        T.eq(svc.sessionStats.phaseGhost, 0)
    end)

    T.it("a combined phase+map alert bumps BOTH counters (the :find logic)", function()
        local fw, svc = newHistory()
        svc:RecordHistory("Bob", "TRP3", true, true, false, "phase+map")
        T.eq(svc.sessionStats.phaseAlerts, 1)
        T.eq(svc.sessionStats.mapAlerts, 1)
        T.eq(svc.sessionStats.phaseBlocks, 1)
        T.eq(svc.sessionStats.mapBlocks, 1)
    end)

    T.it("start_phase_block is its own bucket (not phase/map)", function()
        local fw, svc = newHistory()
        svc:RecordHistory("Bob", "TRP3", true, true, true, "start_phase_block")
        T.eq(svc.sessionStats.startPhaseBlocks, 1)
        T.eq(svc.sessionStats.startPhaseGhost, 1, "ghost variant tracked")
        T.eq(svc.sessionStats.phaseBlocks, 0, "must not leak into phase breakdown")
    end)
end)

T.describe("HistoryService:RecordHistory history list", function()
    T.it("prepends newest-first", function()
        local fw, svc = newHistory()
        svc:RecordHistory("First", "TRP3", true, false, false, "phase")
        svc:RecordHistory("Second", "TRP3", true, false, false, "phase")
        T.eq(svc.notificationHistory[1].player, "Second")
        T.eq(svc.notificationHistory[2].player, "First")
    end)

    T.it("caps the list at maxHistorySize", function()
        local fw, svc = newHistory({ trackHistory = true, maxHistorySize = 3 })
        for i = 1, 10 do
            svc:RecordHistory("P"..i, "TRP3", true, false, false, "phase")
        end
        T.eq(#svc.notificationHistory, 3, "oldest entries trimmed")
        T.eq(svc.notificationHistory[1].player, "P10", "newest retained")
    end)
end)

-- ===================== IncrementStat =====================

T.describe("HistoryService:IncrementStat", function()
    T.it("increments a nested cacheStats field", function()
        local fw, svc = newHistory()
        svc:IncrementStat("cacheStats", "phaseCacheHits")
        svc:IncrementStat("cacheStats", "phaseCacheHits", 4)
        T.eq(svc.sessionStats.cacheStats.phaseCacheHits, 5)
    end)

    T.it("increments a top-level numeric field", function()
        local fw, svc = newHistory()
        svc:IncrementStat("alerts")
        T.eq(svc.sessionStats.alerts, 1)
    end)

    T.it("is a no-op for unknown categories/subcategories", function()
        local fw, svc = newHistory()
        T.no_raise(function() svc:IncrementStat("nope", "alsoNope") end)
        T.no_raise(function() svc:IncrementStat("cacheStats", "unknownField") end)
    end)
end)

-- ===================== TrackAddonRequest =====================

T.describe("HistoryService:TrackAddonRequest", function()
    T.it("counts a known addon and dedups by sendId", function()
        local fw, svc = newHistory()
        svc:TrackAddonRequest("TRP3", 1)
        svc:TrackAddonRequest("TRP3", 1)  -- same sendId -> ignored
        svc:TrackAddonRequest("TRP3", 2)
        T.eq(svc.sessionStats.requestsByAddon.TRP3, 2)
    end)

    T.it("folds case (mrp -> MRP)", function()
        local fw, svc = newHistory()
        svc:TrackAddonRequest("mrp", 10)
        T.eq(svc.sessionStats.requestsByAddon.MRP, 1)
    end)

    T.it("ignores unknown addons and bad input", function()
        local fw, svc = newHistory()
        T.no_raise(function() svc:TrackAddonRequest("WeirdAddon", 20) end)
        T.no_raise(function() svc:TrackAddonRequest(nil, 21) end)
        T.is_nil(svc.sessionStats.requestsByAddon.WEIRDADDON)
    end)
end)

-- ===================== Send-history / suppression window =====================

T.describe("HistoryService send-history suppression", function()
    T.it("treats a never-seen player as a first send", function()
        local fw, svc = newHistory()
        local isFirst, count = svc:IsFirstSend("Newbie", 100, 60)
        T.truthy(isFirst)
        T.eq(count, 0)
    end)

    T.it("RecordSend then IsFirstSend within the window is NOT first", function()
        local fw, svc = newHistory()
        svc:RecordSend("Bob", 100)
        local isFirst = svc:IsFirstSend("Bob", 130, 60)  -- 30s < 60s window
        T.falsy(isFirst)
    end)

    T.it("after the window elapses it IS a first send again", function()
        local fw, svc = newHistory()
        svc:RecordSend("Bob", 100)
        local isFirst = svc:IsFirstSend("Bob", 200, 60)  -- 100s > 60s window
        T.truthy(isFirst)
    end)

    T.it("RecordSend resets the suppressed count", function()
        local fw, svc = newHistory()
        svc:RecordSend("Bob", 100)
        svc.profileSendHistory["Bob"].suppressedCount = 5
        svc:RecordSend("Bob", 150)
        T.eq(svc.profileSendHistory["Bob"].suppressedCount, 0)
        T.eq(svc.profileSendHistory["Bob"].timestamp, 150)
    end)
end)

return T
