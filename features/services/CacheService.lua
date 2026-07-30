-- features/services/CacheService.lua
-- Cache Service: Manages all caching logic, cleanup, and event tracking

local addonName, TRP3FW = ...

local CacheService = TRP3FW.Service:New("CacheService")

-- Constants
local EVENT_DEDUPLICATION_WINDOW = 0.5
local CACHE_CLEANUP_INTERVAL = 60
local CACHE_PRUNE_BUDGET = 200
local START_PHASE_ID = 169

function CacheService:Initialize()
    TRP3FW.Service.Initialize(self)

    self:InitializeCacheCleanup()
    self:InitializeZoneCacheClearing()
    self:InitializeInteractionTracking()
end

-- ===================== Cleanup Logic =====================

function CacheService:CleanupTableCache(cache, maxAge, cacheName)
    if not maxAge then return end
    local now = TRP3FW:GetCurrentTime()
    local pruned = 0
    for k, v in pairs(cache) do
        if v.timestamp and (now - v.timestamp) > maxAge then
            cache[k] = nil
            pruned = pruned + 1
            if TRP3FW.Prefs.debug and TRP3FW.Prefs.debugCache then
                local age = now - v.timestamp
                TRP3FW:Debug(function()
                    return "[Cache Prune] "..cacheName..": Removed "..k.." (age: "..string.format("%.1f", age).."s)"
                end, "cache")
            end
        end
    end
    if pruned > 0 then
        TRP3FW:Debug(function()
            return "[Cache Prune] "..cacheName..": Pruned "..pruned.." entries"
        end, "cache")
    end
    if TRP3FW.cacheCounts then
        TRP3FW.cacheCounts[cacheName] = TRP3FW:CountTableEntries(cache)
    end
end

function CacheService:CleanupTimestampCache(cache, maxAge, cacheName)
    if not maxAge then return end
    local now = TRP3FW:GetCurrentTime()
    local pruned = 0
    for k, timestamp in pairs(cache) do
        local ts
        if type(timestamp) == "number" then
            ts = timestamp
        elseif type(timestamp) == "table" and timestamp.timestamp then
            ts = timestamp.timestamp
        else
            cache[k] = nil
            pruned = pruned + 1
            ts = nil
        end

        if ts and (now - ts) > maxAge then
            cache[k] = nil
            pruned = pruned + 1
            if TRP3FW.Prefs.debug and TRP3FW.Prefs.debugCache then
                local age = now - ts
                TRP3FW:Debug(function()
                    return "[Cache Prune] "..cacheName..": Removed "..k.." (age: "..string.format("%.1f", age).."s)"
                end, "cache")
            end
        end
    end
    if pruned > 0 then
        TRP3FW:Debug(function()
            return "[Cache Prune] "..cacheName..": Pruned "..pruned.." entries"
        end, "cache")
    end
    if TRP3FW.cacheCounts then
        TRP3FW.cacheCounts[cacheName] = TRP3FW:CountTableEntries(cache)
    end
end

-- Incremental prune helper: trims caches with a bounded budget and enforces strict caps
function CacheService:PruneCachesIncremental(budget)
    local CI = TRP3FW.CacheInterface
    if not CI then return end

    local pruneBudget = budget or CACHE_PRUNE_BUDGET
    local targets = {
        "allowedSenders",
        "mapScan",
        "phaseCheck",
        "whoZone",
        "whoName",
        "broadcast",
        "interaction"
    }

    for _, cacheName in ipairs(targets) do
        CI:PruneIncremental(cacheName, pruneBudget)
    end
end

-- Drop interaction cache entries that are for a different zone than the current one
function CacheService:PruneInteractionZoneMismatch(currentZone)
    if not currentZone or currentZone == "" then
        return
    end

    local CI = TRP3FW.CacheInterface
    local cache = CI and CI.caches and CI.caches["interaction"]
    if not cache or not cache.head then
        return
    end

    local pruned = 0
    local key = cache.head
    while key do
        local node = cache.data[key]
        local nextKey = node and node.next
        local entry = node and node.value
        local entryZone = entry and entry.zone

        if entryZone and entryZone ~= currentZone then
            CI:Remove("interaction", key)
            pruned = pruned + 1
        end

        key = nextKey
    end

    if pruned > 0 and TRP3FW.Prefs and TRP3FW.Prefs.debugCache then
        TRP3FW:Debug("[Cache Prune] interaction: removed "..pruned.." entries outside zone "..tostring(currentZone), "cache")
    end
end

function CacheService:InitializeCacheCleanup()
    TRP3FW.cacheCounts = TRP3FW.cacheCounts or {}

    local function RecordPerf(start, context)
        local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
        if hs then hs:RecordPerformance(debugprofilestop() - start, context or "Cache Cleanup") end
    end

    local function cleanSendIdTable(tableName, counterName)
        local tbl = TRP3FW[tableName]
        if not tbl then return end

        local count = 0
        for _ in pairs(tbl) do
            count = count + 1
        end

        if count <= 1000 then
            return
        end

        TRP3FW:Debug("[Cache Prune] "..tableName.." has "..count.." entries, pruning to keep last 500", "cache")

        -- Compute a threshold without full sorting (O(n) instead of O(n log n)).
        local maxSendId = 0
        for sendId in pairs(tbl) do
            if sendId > maxSendId then
                maxSendId = sendId
            end
        end

        -- Keep approximately the newest 500 ids by dropping anything well below the observed max.
        local keepThreshold = maxSendId - 500
        local pruned = 0
        for sendId in pairs(tbl) do
            if sendId < keepThreshold then
                tbl[sendId] = nil
                pruned = pruned + 1
            end
        end

        if counterName then
            TRP3FW[counterName] = math.max((TRP3FW[counterName] or 0) - pruned, 0)
        end

        TRP3FW:Debug("[Cache Prune] "..tableName..": Pruned "..pruned.." old entries, keeping "..(count - pruned), "cache")
    end

    -- OPTIMIZATION: Spread cleanup across 5 staggered timers (12s each = 60s total cycle)
    -- This prevents single-frame spikes and distributes work evenly

    -- Task 1: Core cache pruning (every 12 seconds)
    C_Timer.NewTicker(12, function()
        local start = debugprofilestop()
        if not TRP3FW.Prefs or not TRP3FW.Prefs.sendCacheDuration then
            return
        end

        local CI = TRP3FW.CacheInterface
        -- Smaller budget per cycle (40 instead of 200) since we run 5x more frequently
        self:PruneCachesIncremental(100)
        RecordPerf(start, "Cache Cleanup (Core)")
    end)

    -- Task 2: History and user-initiated query cleanup (every 12 seconds, offset 2.4s)
    C_Timer.After(2.4, function()
        C_Timer.NewTicker(12, function()
        local start = debugprofilestop()
            if not TRP3FW.Prefs then return end

            -- Use HistoryService for history cleanup if possible, but for now access directly via alias
            self:CleanupTableCache(TRP3FW.profileSendHistory, TRP3FW.Prefs.suppressionTime * 2, "profileSendHistory")
            self:CleanupTableCache(TRP3FW.scanNotificationHistory, TRP3FW.Prefs.suppressionTime * 2, "scanNotificationHistory")

            if TRP3FW.userInitiatedQueries then
                self:CleanupTimestampCache(TRP3FW.userInitiatedQueries, 30, "userInitiatedQueries")
            end
            RecordPerf(start, "Cache Cleanup (History)")
        end)
    end)

    -- Task 3: SendId table cleanup (every 12 seconds, offset 4.8s)
    C_Timer.After(4.8, function()
        C_Timer.NewTicker(12, function()
        local start = debugprofilestop()
            cleanSendIdTable("lastCacheStatSendId", "lastCacheStatSendIdCount")
            cleanSendIdTable("lastAddonRequestSendId", "lastAddonRequestSendIdCount")
            cleanSendIdTable("lastInteractionCacheSendId", "lastInteractionCacheSendIdCount")
            cleanSendIdTable("lastPhaseCacheSendId", "lastPhaseCacheSendIdCount")
            cleanSendIdTable("lastWhoCacheSendId", "lastWhoCacheSendIdCount")
            cleanSendIdTable("lastMapCacheSendId", "lastMapCacheSendIdCount")
            cleanSendIdTable("lastBroadcastCacheSendId", "lastBroadcastCacheSendIdCount")
            RecordPerf(start, "Cache Cleanup (SendId)")
        end)
    end)

    -- Task 4: MSP callback cleanup (every 12 seconds, offset 7.2s)
    C_Timer.After(7.2, function()
        C_Timer.NewTicker(12, function()
        local start = debugprofilestop()
            if TRP3FW.mspCallbackSendIds then
                local now = TRP3FW:GetCurrentTime()
                local pruned = 0
                for playerName, info in pairs(TRP3FW.mspCallbackSendIds) do
                    if (now - info.timestamp) > 5 then
                        TRP3FW.mspCallbackSendIds[playerName] = nil
                        pruned = pruned + 1
                    end
                end
                if pruned > 0 then
                    TRP3FW:Debug("[Cache Prune] mspCallbackSendIds: Pruned "..pruned.." old entries", "cache")
                end
            end
            RecordPerf(start, "Cache Cleanup (MSP)")
        end)
    end)

    -- Task 5: Queue cleanup (WHO, PhaseIn requests/sends) (every 12 seconds, offset 9.6s)
    C_Timer.After(9.6, function()
        C_Timer.NewTicker(12, function()
        local start = debugprofilestop()
            if TRP3FW.pendingWhoQueries then
                local now = TRP3FW:GetCurrentTime()
                local pruned = 0
                local kept = {}
                local head = TRP3FW.pendingWhoQueueHead or 1

                for i = head, #TRP3FW.pendingWhoQueries do
                    local query = TRP3FW.pendingWhoQueries[i]
                    local age = now - (query.queuedAt or query.timestamp or 0)

                    if age < 30 then
                        kept[#kept + 1] = query
                    else
                        pruned = pruned + 1
                        TRP3FW:Debug("[Cache Prune] Removed stale WHO query for "..tostring(query.playerName).." (age: "..string.format("%.1f", age).."s)", "cache")
                        if query.callback then
                            query.callback(false, "queue_timeout", 0, nil)
                        end
                    end
                end

                if pruned > 0 then
                    TRP3FW.pendingWhoQueries = kept
                    TRP3FW.pendingWhoQueueHead = 1
                    TRP3FW:Debug("[Cache Prune] pendingWhoQueries: Pruned "..pruned.." stale entries, "..#kept.." remaining", "cache")
                end
            end

            if TRP3FW.pendingPhaseInSends then
                local now = TRP3FW:GetCurrentTime()
                local ttl = math.max((TRP3FW.Prefs.phaseInDelay or 4) * 3, 10)
                local pruned = 0

                for i = #TRP3FW.pendingPhaseInSends, 1, -1 do
                    local entry = TRP3FW.pendingPhaseInSends[i]
                    local age = now - (entry.queuedAt or 0)
                    if age > ttl then
                        table.remove(TRP3FW.pendingPhaseInSends, i)
                        pruned = pruned + 1
                    end
                end

                if pruned > 0 then
                    TRP3FW:Debug("[Cache Prune] pendingPhaseInSends: Pruned "..pruned.." stale entries", "cache")
                end

                local limit = TRP3FW.PHASE_IN_QUEUE_LIMIT or 200
                local oversize = #TRP3FW.pendingPhaseInSends - limit
                if oversize > 0 then
                    for i = 1, oversize do
                        table.remove(TRP3FW.pendingPhaseInSends, 1)
                    end
                    TRP3FW:Warn("[Cache Prune] pendingPhaseInSends trimmed to limit ("..limit.."), dropped "..oversize.." oldest entries")
                end
            end

            -- FIX: Cleanup pendingChompSends (burst detection queue)
            if TRP3FW.pendingChompSends and next(TRP3FW.pendingChompSends) then
                local now = TRP3FW:GetCurrentTime()
                local pruned = 0
                for playerName, data in pairs(TRP3FW.pendingChompSends) do
                    -- Burst window is 2s, timeout is 30s in hook. 60s is a safe fallback for leak prevention.
                    if (now - (data.timestamp or 0)) > 60 then
                        TRP3FW.pendingChompSends[playerName] = nil
                        pruned = pruned + 1
                    end
                end
                if pruned > 0 then
                    TRP3FW:Debug("[Cache Prune] pendingChompSends: Pruned "..pruned.." stale entries", "cache")
                end
            end

            -- FIX: Cleanup currentMessageIsRequest (request tracking)
            if TRP3FW.currentMessageIsRequest and next(TRP3FW.currentMessageIsRequest) then
                -- Logic uses 1s window, so 5s is plenty safe
                self:CleanupTimestampCache(TRP3FW.currentMessageIsRequest, 5, "currentMessageIsRequest")
            end

            -- FIX: Cleanup pendingMSPAutoReplies (auto-reply tracking)
            if TRP3FW.pendingMSPAutoReplies and next(TRP3FW.pendingMSPAutoReplies) then
                self:CleanupTimestampCache(TRP3FW.pendingMSPAutoReplies, 10, "pendingMSPAutoReplies")
            end

            -- FIX: Cleanup pendingLocationChecks (location check tracking)
            if TRP3FW.pendingLocationChecks then
                self:CleanupTimestampCache(TRP3FW.pendingLocationChecks, 60, "pendingLocationChecks")
            end

            -- FIX: Cleanup pendingSends (outgoing message tracking)
            if TRP3FW.pendingSends then
                self:CleanupTimestampCache(TRP3FW.pendingSends, 60, "pendingSends")
            end

            -- Cleanup alertOnlyChecksInFlight (AlertFastPathStage's per-player dedup markers).
            -- Entries are normally cleared by the cascading callback; this is the backstop for
            -- a check whose callback never fires, so the table cannot grow with one entry per
            -- player encountered in alert-only mode.
            if TRP3FW.alertOnlyChecksInFlight then
                self:CleanupTimestampCache(TRP3FW.alertOnlyChecksInFlight, 60, "alertOnlyChecksInFlight")
            end

            -- FIX: Cleanup pendingPhaseChecks (phase check priority queue)
            if TRP3FW.pendingPhaseChecks then
                local now = TRP3FW:GetCurrentTime()
                local pruned = 0
                -- Iterate backwards to safely remove
                for i = #TRP3FW.pendingPhaseChecks, 1, -1 do
                    local entry = TRP3FW.pendingPhaseChecks[i]
                    if (now - (entry.queuedAt or 0)) > 60 then
                        table.remove(TRP3FW.pendingPhaseChecks, i)
                        pruned = pruned + 1
                    end
                end
                if pruned > 0 then
                    TRP3FW:Debug("[Cache Prune] pendingPhaseChecks: Pruned "..pruned.." stale entries", "cache")
                end
            end

            RecordPerf(start, "Cache Cleanup (Queues)")
        end)
    end)

    -- Task 6: Validated names cache cleanup (every hour)
    -- OPTIMIZATION: TTL-based cleanup for validated names cache (user-configurable)
    -- Removes entries older than validatedNamesCacheDuration (default: 7 days)
    -- Also enforces hard limit of 5000 entries as safety fallback
    --
    -- N10 — CLOCK CONVENTION:
    --   Persistent SavedVariables caches (TRP3FW_ValidatedNames) MUST use `time()` (Unix
    --   epoch seconds). Session caches (anything keyed off TRP3FW:GetCurrentTime() or
    --   GetTime()) MUST use session-relative seconds. Mixing the two produces ~1.7e9-second
    --   age math and prunes everything on first cleanup. The assertion below guards writers
    --   that get this wrong.
    C_Timer.NewTicker(3600, function()  -- Once per hour
        if not TRP3FW_ValidatedNames or not TRP3FW.Prefs then return end

        local now = time()
        local ttl = TRP3FW.Prefs.validatedNamesCacheDuration or 604800 -- Default: 7 days
        local pruned = 0
        local total = 0
        local skippedBadClock = 0

        -- Prune expired entries based on TTL
        for name, entry in pairs(TRP3FW_ValidatedNames) do
            total = total + 1
            local timestamp = type(entry) == "table" and entry.timestamp or 0

            -- N10 guard: session-relative timestamps will be tiny vs `time()` epoch values.
            -- Skip them and warn rather than mass-pruning legitimate entries on first run.
            if timestamp > 0 and timestamp < 1000000000 then
                skippedBadClock = skippedBadClock + 1
            else
                local age = now - timestamp
                if age > ttl then
                    TRP3FW_ValidatedNames[name] = nil
                    pruned = pruned + 1
                end
            end
        end

        if skippedBadClock > 0 then
            TRP3FW:Warn("[ValidatedNames] "..skippedBadClock.." entries have session-relative timestamps; writer is using GetTime() instead of time(). Skipping prune for those.")
        end

        local remaining = total - pruned

        -- Hard limit fallback: If still over limit after TTL pruning, clear oldest
        local limit = TRP3FW.Prefs.validatedNamesCacheLimit or 5000
        if remaining > limit then
            -- Convert to array for sorting by timestamp
            local entries = {}
            for name, entry in pairs(TRP3FW_ValidatedNames) do
                local timestamp = type(entry) == "table" and entry.timestamp or 0
                table.insert(entries, {name = name, timestamp = timestamp})
            end

            -- Sort by timestamp (oldest first)
            table.sort(entries, function(a, b) return a.timestamp < b.timestamp end)

            -- Remove oldest entries until we're at the limit
            local toRemove = remaining - limit
            for i = 1, toRemove do
                TRP3FW_ValidatedNames[entries[i].name] = nil
                pruned = pruned + 1
            end

            TRP3FW:Debug(function()
                return "[Cache Cleanup] Validated names cache exceeded "..limit.." entries, pruned "..toRemove.." oldest entries"
            end, "cache")
        end

        if pruned > 0 then
            TRP3FW:Debug(function()
                return "[Cache Cleanup] Validated names: Pruned "..pruned.." entries (TTL: "..TRP3FW:FormatTime(ttl).."), "..remaining - pruned.." remaining"
            end, "cache")
        else
            TRP3FW:Debug(function()
                return "[Cache Cleanup] Validated names: "..remaining.." entries, no pruning needed (TTL: "..TRP3FW:FormatTime(ttl)..")"
            end, "cache")
        end
    end)
end

-- ===================== Zone/Phase Change Logic =====================

function CacheService:InitializeZoneCacheClearing()
    local ES = TRP3FW.ServiceContainer:Get("EventService")
    if not ES then return end

    local function HandleZonePhaseChange(event, ...)
        local start = debugprofilestop()
        local now = TRP3FW:GetCurrentTime()
        local CI = TRP3FW.CacheInterface

        -- EPSILON FIX: Use GetRealZoneText first (more reliable for custom-renamed maps)
        local zone = GetRealZoneText()
        if not zone or zone == "" then
            zone = GetZoneText()
        end
        if not zone or zone == "" then
            zone = GetMinimapZoneText()
        end
        TRP3FW.currentZoneName = (zone and zone ~= "") and zone or nil

        local shouldClear = false
        local isMergedEvent = false  -- Track if zone+phase events happened close together

        if event == "SCENARIO_UPDATE" or event == "EPSILON_PHASE_CHANGE" then
            shouldClear = TRP3FW.Prefs.clearCacheOnPhaseChange
            TRP3FW:Debug(string.format("[%s] Detected, clearCacheOnPhaseChange=%s", event, tostring(shouldClear)), "cache")

            if (now - (TRP3FW.lastZoneEventTime or 0)) < 0.5 then
                TRP3FW:Debug(string.format("[%s] Zone event fired recently, skipping duplicate clear", event), "cache")
                return
            end
            TRP3FW.lastPhaseChangeTime = now

        elseif event == "ZONE_CHANGED_NEW_AREA" then
            shouldClear = TRP3FW.Prefs.clearCacheOnZoneChange
            TRP3FW:Debug("[Zone Change] ZONE_CHANGED_NEW_AREA detected, clearCacheOnZoneChange="..tostring(shouldClear), "cache")

            if (now - (TRP3FW.lastPhaseChangeTime or 0)) < 0.5 then
                TRP3FW:Debug("[Zone Change] Phase event fired recently, merging clear settings", "cache")
                isMergedEvent = true  -- Zone change happened right after phase change
            end
            TRP3FW.lastZoneEventTime = now

        elseif event == "PLAYER_ENTERING_WORLD" then
            shouldClear = true
            TRP3FW:Debug("[Zone Change] PLAYER_ENTERING_WORLD detected, clearing caches", "cache")
        end

        if not shouldClear then
            TRP3FW:Debug("[Cache] Skipping cache clear for "..event.." (disabled in settings)", "cache")
            -- FALL THROUGH to prepopulate logic (don't return!)
        else
            TRP3FW:Debug("[Zone/Phase Change] Clearing caches due to "..event, "cache")
            TRP3FW.lastZoneChangeTime = now

            if event == "SCENARIO_UPDATE" or event == "EPSILON_PHASE_CHANGE" then
                if TRP3FW.Prefs.clearPhaseCheckOnPhaseChange then if CI then CI:Clear("phaseCheck") end end
                if TRP3FW.Prefs.clearAllowedSendersOnPhaseChange then if CI then CI:Clear("allowedSenders") end end
                if TRP3FW.Prefs.clearInteractionOnPhaseChange then if CI then CI:Clear("interaction") end end
                if TRP3FW.Prefs.clearSuppressionOnPhaseChange then
                    if TRP3FW.profileSendHistory then wipe(TRP3FW.profileSendHistory) end
                    if TRP3FW.scanNotificationHistory then wipe(TRP3FW.scanNotificationHistory) end
                end
                if TRP3FW.Prefs.clearRecentBroadcastsOnPhaseChange then if CI then CI:Clear("broadcast") end end
                if TRP3FW.Prefs.clearRecentScansOnPhaseChange then if CI then CI:Clear("mapScan") end end
                if TRP3FW.Prefs.clearWhoZoneOnPhaseChange then if CI then CI:Clear("whoZone") end end
                if TRP3FW.Prefs.clearWhoNameOnPhaseChange then if CI then CI:Clear("whoName") end end
                if TRP3FW.Prefs.clearSpvpOnPhaseChange then
                    if CI then
                        CI:Clear("spvpVerified")
                        CI:Clear("spvpPhaseSalt")
                    end
                end

            elseif event == "ZONE_CHANGED_NEW_AREA" then
                if TRP3FW.Prefs.clearPhaseCheckOnZoneChange or (isMergedEvent and TRP3FW.Prefs.clearPhaseCheckOnPhaseChange) then
                    if CI then CI:Clear("phaseCheck") end
                end
                if TRP3FW.Prefs.clearAllowedSendersOnZoneChange or (isMergedEvent and TRP3FW.Prefs.clearAllowedSendersOnPhaseChange) then
                    if CI then CI:Clear("allowedSenders") end
                end
                if TRP3FW.Prefs.clearInteractionOnZoneChange or (isMergedEvent and TRP3FW.Prefs.clearInteractionOnPhaseChange) then
                    if CI then CI:Clear("interaction") end
                end
                if TRP3FW.Prefs.clearSuppressionOnZoneChange or (isMergedEvent and TRP3FW.Prefs.clearSuppressionOnPhaseChange) then
                    if TRP3FW.profileSendHistory then wipe(TRP3FW.profileSendHistory) end
                    if TRP3FW.scanNotificationHistory then wipe(TRP3FW.scanNotificationHistory) end
                end
                if TRP3FW.Prefs.clearRecentBroadcastsOnZoneChange or (isMergedEvent and TRP3FW.Prefs.clearRecentBroadcastsOnPhaseChange) then
                    if CI then CI:Clear("broadcast") end
                end
                if TRP3FW.Prefs.clearRecentScansOnZoneChange or (isMergedEvent and TRP3FW.Prefs.clearRecentScansOnPhaseChange) then
                    if CI then CI:Clear("mapScan") end
                end
                TRP3FW.recentScanRequests = {}
                if TRP3FW.Prefs.clearWhoZoneOnZoneChange or (isMergedEvent and TRP3FW.Prefs.clearWhoZoneOnPhaseChange) then
                    if CI then CI:Clear("whoZone") end
                end
                if TRP3FW.Prefs.clearWhoNameOnZoneChange or (isMergedEvent and TRP3FW.Prefs.clearWhoNameOnPhaseChange) then
                    if CI then CI:Clear("whoName") end
                end
                if TRP3FW.Prefs.clearSpvpOnZoneChange or (isMergedEvent and TRP3FW.Prefs.clearSpvpOnPhaseChange) then
                    if CI then
                        CI:Clear("spvpVerified")
                        CI:Clear("spvpPhaseSalt")
                    end
                end

            elseif event == "PLAYER_ENTERING_WORLD" then
                if CI then
                    CI:Clear("phaseCheck")
                    CI:Clear("allowedSenders")
                    CI:Clear("interaction")
                    CI:Clear("broadcast")
                    CI:Clear("mapScan")
                    CI:Clear("whoZone")
                    CI:Clear("whoName")
                    CI:Clear("spvpVerified")
                    CI:Clear("spvpPhaseSalt")
                end
                TRP3FW.recentScanRequests = {}
            end
        end

        -- After clears, enforce caps and drop cross-zone interaction entries
        self:PruneInteractionZoneMismatch(TRP3FW.currentZoneName)
        self:PruneCachesIncremental(CACHE_PRUNE_BUDGET)

        local shouldPrepopWho = TRP3FW.Prefs.prepopulateWhoCache ~= false and ((isMergedEvent and TRP3FW.Prefs.prepopulateWhoOnPhase ~= false) or (not isMergedEvent and TRP3FW.Prefs.prepopulateWhoOnZone ~= false))

        TRP3FW:Debug(string.format("[Prepopulate] shouldPrepopWho=%s (prepopulateWhoCache=%s, isMergedEvent=%s, prepopulateWhoOnPhase=%s, prepopulateWhoOnZone=%s)",
            tostring(shouldPrepopWho),
            tostring(TRP3FW.Prefs.prepopulateWhoCache),
            tostring(isMergedEvent),
            tostring(TRP3FW.Prefs.prepopulateWhoOnPhase),
            tostring(TRP3FW.Prefs.prepopulateWhoOnZone)), "cache")

        if shouldPrepopWho then
            local configuredDelay = math.max(TRP3FW.Prefs.phaseInDelay or 5, 0)
            local prepopulateDelay = configuredDelay -- Use the configured delay (5s) directly

            local now = time()
            if TRP3FW.nextAllowedWhoPrepopulate and now < TRP3FW.nextAllowedWhoPrepopulate then
                return
            end
            TRP3FW.nextAllowedWhoPrepopulate = now + 3

            if TRP3FW.pendingWhoPrepopulateTimer then
                TRP3FW.pendingWhoPrepopulateTimer:Cancel()
            end

            TRP3FW.pendingWhoPrepopulateTimer = C_Timer.NewTimer(prepopulateDelay, function()
                TRP3FW.pendingWhoPrepopulateTimer = nil
                TRP3FW:Debug("[Prepopulate] Timer fired, starting WHO prepopulation", "cache")

                -- EPSILON FIX: Prioritize actual zone text over map info (maps can be renamed on Epsilon)
                local zoneName = GetRealZoneText()  -- Most reliable for current zone
                if not zoneName or zoneName == "" then
                    zoneName = GetZoneText()  -- Fallback to main zone
                end
                if not zoneName or zoneName == "" then
                    zoneName = GetMinimapZoneText()  -- Fallback to minimap
                end

                -- Only use map info as last resort (may return default Blizzard name on Epsilon)
                if not zoneName or zoneName == "" then
                    local mapID = C_Map.GetBestMapForUnit("player")
                    if mapID then
                        local info = C_Map.GetMapInfo(mapID)
                        if info and info.name and info.name ~= "" then
                            zoneName = info.name
                        end
                    end
                end

                -- Store mapID separately for reference
                local mapID = C_Map.GetBestMapForUnit("player")
                if mapID then
                    TRP3FW.currentMapID = mapID
                end

                TRP3FW:Debug("[Prepopulate] Detected zone: "..tostring(zoneName).." (mapID: "..tostring(mapID)..")", "cache")

                -- Sanitize as a GATE on prepopulating, but do NOT write the sanitized form
                -- back to currentZoneName.
                --
                -- currentZoneName is the RAW zone name (set from GetRealZoneText at :476) and
                -- every consumer is built around that: WhoService sanitizes at the point of
                -- use because the zone name crosses a RunPrivileged string boundary there
                -- (see WhoService.lua:389-395). This line used to overwrite it with the
                -- sanitized form, so the variable alternated between two forms depending on
                -- which code path last ran -- and it is used as a `whoZone` CACHE KEY and
                -- compared against entry.zone in PruneInteractionZoneMismatch, so two forms
                -- mean two keyspaces and a prune that drops entries stored under the other.
                local sanitized = zoneName and TRP3FW:SanitizeZoneName(zoneName) or nil
                if not sanitized then
                    TRP3FW:Debug("[Prepopulate] Zone sanitization failed, aborting prepopulation", "cache")
                    return
                end

                TRP3FW:Debug("[Prepopulate] Zone validated: "..tostring(zoneName), "cache")

                if TRP3FW.hasEpsilonAPI and TRP3FW.Prefs.useWhoQuery then
                    TRP3FW:Debug("[Prepopulate] Epsilon API and useWhoQuery enabled, starting WHO query", "cache")
                    -- Use player's own name for prepopulation to ensure it passes sanitization
                    local myName = UnitName("player")
                    TRP3FW:CheckPlayerViaWho(myName, 0, function(found, source, cacheAge, zone, mapID)
                        TRP3FW:Debug("[Prepopulate] WHO query completed - found="..tostring(found)..", source="..tostring(source)..", zone="..tostring(zone), "cache")
                    end, false)
                else
                    TRP3FW:Debug("[Prepopulate] Skipped - hasEpsilonAPI="..tostring(TRP3FW.hasEpsilonAPI)..", useWhoQuery="..tostring(TRP3FW.Prefs.useWhoQuery), "cache")
                end
            end)

            TRP3FW:Debug("[Prepopulate] Timer scheduled for "..tostring(prepopulateDelay).."s", "cache")
        end

        local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
        if hs then hs:RecordPerformance(debugprofilestop() - start, "Zone Change Cleanup") end
    end

    ES:RegisterCallback(ES.Events.ZONE_CHANGED, HandleZonePhaseChange, 10)
    ES:RegisterCallback(ES.Events.PHASE_CHANGED, HandleZonePhaseChange, 10)
    ES:RegisterCallback("LOADING_FINISHED", function()
        TRP3FW:Debug("[Zone Change] Loading screen finished, resetting phase-in timer", "cache")
        TRP3FW.lastZoneChangeTime = TRP3FW:GetCurrentTime()
    end, 10)
end

-- ===================== Interaction Tracking =====================

function CacheService:InitializeInteractionTracking()
    if self.interactionTrackingInitialized then
        return
    end

    local ES = TRP3FW.ServiceContainer:Get("EventService")
    if not ES then return end

    -- Interaction refresh logic uses a percentage of the TTL.
    --
    -- Read LIVE, not snapshotted into the closure at init. These two prefs are editable in the
    -- settings UI and via /trp3fw, and capturing them here meant a change had no effect until
    -- /reload -- with nothing in the UI saying so. The cost is two table reads and a multiply
    -- on a path that already calls CleanPlayerName and is throttled to 2Hz besides, so the
    -- perf argument for snapshotting does not survive contact with the numbers.
    local function GetRefreshThreshold()
        local refreshPercent = TRP3FW.Prefs.interactionRefreshRate or 10
        local cacheDuration = TRP3FW.Prefs.interactionCacheDuration or 600
        return cacheDuration * (refreshPercent / 100)
    end

    local lastMouseoverProcess = 0
    local MOUSEOVER_THROTTLE = 0.5  -- OPTIMIZATION: Reduced from 0.1s (10Hz) to 0.5s (2Hz) for 80% event reduction

    local function OnInteractionEvent(event)
        local start = debugprofilestop()
        if TRP3FW.Prefs.blockStartPhase and TRP3FW.hasEpsilonAPI then
            local myPhaseID = tonumber(C_Epsilon.GetPhaseId())
            if myPhaseID == START_PHASE_ID then
                return
            end
        end

        if event == "UPDATE_MOUSEOVER_UNIT" then
            local now = GetTime()
            if (now - lastMouseoverProcess) < MOUSEOVER_THROTTLE then
                return
            end
            lastMouseoverProcess = now

            if UnitIsPlayer("mouseover") and not UnitIsUnit("mouseover", "player") then
                local unitName = UnitName("mouseover")
                if not unitName then return end

                -- Read and write must use the SAME key. This used to read with the RAW
                -- unitName but write with CleanPlayerName(unitName), justified as "check the
                -- cache before the expensive CleanPlayerName call". CleanPlayerName truncates
                -- at the first hyphen, so for any hyphenated name the read was a guaranteed
                -- miss and every single mouseover redundantly re-Set the entry -- the same
                -- defect class as the allowedSenders/interaction key mismatch in 30ee55c.
                --
                -- The optimization it bought was largely illusory anyway: CleanPlayerName is
                -- cached twice over (the persistent TRP3FW_ValidatedNames cache plus the clean
                -- -name cache), so the "expensive" path is a table lookup for any name seen
                -- before -- which, on a repeat mouseover, is exactly the case being optimized.
                local CI = TRP3FW.CacheInterface
                local now = TRP3FW:GetCurrentTime()
                local name = TRP3FW:CleanPlayerName(unitName)
                if not name then return end

                local existing = CI and CI:Get("interaction", name)

                if not existing or (now - existing.timestamp) > GetRefreshThreshold() then
                    local zone = TRP3FW.currentZoneName or "Unknown"
                    if CI then
                        CI:Set("interaction", name, {
                            timestamp = now,
                            zone = zone,
                            mapID = TRP3FW.currentMapID,
                            source = "mouseover"
                        })
                        TRP3FW:Debug(function()
                            return "[Interaction Cache] Cached "..name.." from mouseover in "..zone
                        end, "cache")
                    end
                end
            end

        elseif event == "PLAYER_TARGET_CHANGED" then
            -- Ignore automated targeting (individual or batch checks)
            if TRP3FW.phaseCheckTargeting or TRP3FW.targetingInProgress then
                return
            end

            if UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
                local name = TRP3FW:CleanPlayerName(UnitName("target"))
                if name then
                    local now = TRP3FW:GetCurrentTime()
                    local zone = TRP3FW.currentZoneName or "Unknown"

                    local CI = TRP3FW.CacheInterface
                    if CI then
                        CI:Set("interaction", name, {
                            timestamp = now,
                            zone = zone,
                            mapID = TRP3FW.currentMapID,
                            source = "target"
                        })
                        TRP3FW:Debug(function()
                            return "[Interaction Cache] Cached "..name.." from target change in "..zone
                        end, "cache")
                    end
                end
            end
        end

        local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
        if hs then hs:RecordPerformance(debugprofilestop() - start, "Interaction Tracking") end
    end

    ES:RegisterCallback(ES.Events.TARGET_CHANGED, OnInteractionEvent)
    ES:RegisterCallback("MOUSEOVER_CHANGED", OnInteractionEvent)

    self.interactionTrackingInitialized = true
    TRP3FW:Debug("[CacheService] Interaction tracking enabled (refresh threshold: "..string.format("%.1f", GetRefreshThreshold()).."s)", "cache")
end

TRP3FW.ServiceContainer:Register(CacheService)
