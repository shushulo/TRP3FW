-- tests/unit/history_service_spec.lua
-- Headless tests for HistoryService (features/services/HistoryService.lua):
-- session-stat accounting and send-history bookkeeping. These are pure table
-- math. Two documented past bugs are guarded here: the per-type block/ghost
-- breakdown fields that nothing populated, and the combined-alertType (":find")
-- accounting that must bump both phase and map counters for "phase+map".

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

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

    T.it("counts a request with no sendId instead of erroring", function()
        -- `TRP3FW.lastAddonRequestSendId[nil] = true` is a hard "table index is nil"
        -- error, and this runs inside the profile-send hook.
        local fw, svc = newHistory()
        T.no_raise(function() svc:TrackAddonRequest("TRP3", nil) end)
        T.eq(svc.sessionStats.requestsByAddon.TRP3, 1, "still counted, just not deduplicated")
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

-- ===================== Wall-clock vs monotonic timestamps =====================
--
-- `timestamp` is TRP3FW:GetCurrentTime() = GetTimePreciseSec(): seconds since the
-- client started, NOT a Unix epoch. It is the right clock for the elapsed-time math
-- the rest of the addon does with it (suppression windows, cache ages), but three UI
-- sites render history entries with `date(fmt, entry.timestamp)` - ui/settings.lua
-- (Status tab "Recent events"), ui/tabs/Dashboard.lua, and ui/historywindow.lua's
-- perf-graph tooltip. `date()` interprets its argument as an epoch, so feeding it an
-- uptime value printed every event as a time in Jan 1970 that drifted with uptime.
--
-- Fix: entries carry BOTH clocks - `timestamp` (monotonic, for math) and `wallTime`
-- (time(), epoch, for display). These tests pin that both are present and distinct.
-- The mock clock is session-relative and mock `time()` adds a plausible epoch base,
-- so a wallTime that is really an uptime value is detectable here.

local EPOCH_FLOOR = 1000000000  -- ~2001-09; any real epoch timestamp exceeds this

T.describe("HistoryService timestamps carry a wall clock for display", function()
    T.it("RecordHistory stores an epoch wallTime alongside the monotonic timestamp", function()
        mock.setClock(1234)
        local fw, svc = newHistory()
        svc:RecordHistory("Bob", "TRP3", true, false, false, "phase")

        local entry = svc.notificationHistory[1]
        T.eq(entry.timestamp, 1234, "monotonic clock preserved for elapsed-time math")
        T.truthy(entry.wallTime and entry.wallTime > EPOCH_FLOOR,
            "wallTime must be a real epoch value - date() renders 1970 otherwise")
    end)

    T.it("performanceHistory entries also carry an epoch wallTime", function()
        -- Nonzero start clock: RecordPerformance uses `intervalStart == 0` as its
        -- "not yet armed" sentinel, so a clock literally at 0 re-arms every call and
        -- the interval never rolls over. Production time is client uptime, never 0.
        mock.setClock(100)
        local fw, svc = newHistory({ trackHistory = true, maxHistorySize = 50,
            statusRefreshRate = 1, performanceHistoryEnabled = true })

        -- Two samples straddling the 1s interval boundary so the interval rolls over
        -- and appends a performanceHistory row.
        svc:RecordPerformance(5, "ctx")
        mock.setClock(102)
        svc:RecordPerformance(5, "ctx")

        local entry = svc.sessionStats.performanceHistory[1]
        T.not_nil(entry, "an interval rollover must append a history row")
        T.eq(entry.timestamp, 102, "monotonic clock preserved")
        T.truthy(entry.wallTime and entry.wallTime > EPOCH_FLOOR,
            "perf-graph tooltip renders this with date() - it must be an epoch value")
    end)
end)

-- ===================== Canonical (unescaped) player names =====================
--
-- SanitizePlayerName ESCAPES quotes/backslashes for safe embedding in RunPrivileged()
-- code strings ("Il'tar" -> "Il\'tar", with a literal backslash byte). That form is for
-- code generation only; the canonical form used everywhere else - cache keys, display -
-- is CleanPlayerName's output. See commit 30ee55c, which fixed the same confusion in
-- AllowSender. RecordHistory preferred the escaped form, so every apostrophe name was
-- stored and DISPLAYED with a stray backslash in the history list and Status tab.

T.describe("HistoryService:RecordHistory player-name form", function()
    local function newHistoryWithSecurity()
        local fw = H.newNamespace()
        fw.Prefs = { trackHistory = true, maxHistorySize = 50 }
        H.loadModule("core/Service.lua", fw)
        H.loadModule("core/ServiceContainer.lua", fw)
        H.loadModule("core/cache_interface.lua", fw)
        fw.CacheInterface:Register("cleanName", {})
        fw.CacheInterface:Register("sanitizedName", {})
        _G.TRP3FW_ValidatedNames = {}
        H.loadModule("features/services/SecurityService.lua", fw)
        H.loadModule("features/services/HistoryService.lua", fw)
        fw.ServiceContainer:Get("SecurityService"):Initialize()
        local svc = fw.ServiceContainer:Get("HistoryService")
        svc:Initialize()
        return fw, svc
    end

    T.it("stores an apostrophe name unescaped", function()
        local fw, svc = newHistoryWithSecurity()
        svc:RecordHistory("Il'tar", "TRP3", true, false, false, "phase")
        T.eq(svc.notificationHistory[1].player, "Il'tar",
            "history must hold the canonical name, not RunPrivileged's escaped form")
    end)

    T.it("leaves an ordinary name untouched", function()
        local fw, svc = newHistoryWithSecurity()
        svc:RecordHistory("Bob", "TRP3", true, false, false, "phase")
        T.eq(svc.notificationHistory[1].player, "Bob")
    end)
end)

return T
