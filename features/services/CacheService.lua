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
    
    self:InitializeCaches()
    self:InitializeCacheCleanup()
    self:InitializeZoneCacheClearing()
    self:InitializeInteractionTracking()
end

-- ===================== Cache Initialization =====================

function CacheService:InitializeCaches()
    local CI = TRP3FW.CacheInterface
    if not CI then
        TRP3FW:Error("CacheInterface not loaded!")
        return
    end

    -- Send Cache (Allowed Senders)
    CI:Register("allowedSenders", {
        ttl = TRP3FW_Settings.sendCacheDuration,
        maxSize = 1000
    })

    -- Interaction Cache
    CI:Register("interaction", {
        ttl = TRP3FW_Settings.interactionCacheDuration,
        maxSize = TRP3FW_Settings.cacheSizeLimit or 1000
    })

    -- Phase Check Cache
    CI:Register("phaseCheck", {
        ttl = TRP3FW_Settings.phaseCacheDuration,
        maxSize = TRP3FW_Settings.cacheSizeLimit or 1000
    })

    -- WHO Name Cache
    CI:Register("whoName", {
        ttl = TRP3FW_Settings.whoNameCacheDuration,
        maxSize = TRP3FW_Settings.cacheSizeLimit or 1000
    })

    -- WHO Zone Cache
    CI:Register("whoZone", {
        ttl = TRP3FW_Settings.whoZoneCacheDuration,
        maxSize = TRP3FW_Settings.cacheSizeLimit or 1000
    })

    -- Map Scan Cache (recentScans)
    CI:Register("mapScan", {
        ttl = TRP3FW_Settings.scanCacheDuration,
        maxSize = 1000
    })

    -- Broadcast Cache (recentBroadcasts)
    CI:Register("broadcast", {
        ttl = TRP3FW_Settings.scanCacheDuration,
        maxSize = 1000
    })

    -- Name Normalization Caches (Utility)
    CI:Register("cleanName", {
        maxSize = TRP3FW_Settings.cleanNameCacheSize or 500
    })
    CI:Register("sanitizedName", {
        maxSize = TRP3FW_Settings.sanitizedNameCacheSize or 500
    })

    TRP3FW:Debug("[CacheService] Core caches registered with CacheInterface", "cache")
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
            if TRP3FW_Settings.debug and TRP3FW_Settings.debugCache then
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
            if TRP3FW_Settings.debug and TRP3FW_Settings.debugCache then
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

    if pruned > 0 and TRP3FW_Settings and TRP3FW_Settings.debugCache then
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
        if not TRP3FW_Settings or not TRP3FW_Settings.sendCacheDuration then
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
            if not TRP3FW_Settings then return end

            -- Use HistoryService for history cleanup if possible, but for now access directly via alias
            self:CleanupTableCache(TRP3FW.profileSendHistory, TRP3FW_Settings.suppressionTime * 2, "profileSendHistory")
            self:CleanupTableCache(TRP3FW.scanNotificationHistory, TRP3FW_Settings.suppressionTime * 2, "scanNotificationHistory")

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

            if TRP3FW.pendingPhaseInRequests then
                local now = TRP3FW:GetCurrentTime()
                local pruned = 0
                local kept = {}

                for i, request in ipairs(TRP3FW.pendingPhaseInRequests) do
                    local age = now - (request.queuedAt or 0)

                    if age < 60 then
                        table.insert(kept, request)
                    else
                        pruned = pruned + 1
                        TRP3FW:Debug("[Cache Prune] Removed stale phase-in request for "..tostring(request.playerName).." (age: "..string.format("%.1f", age).."s)", "cache")
                    end
                end

                if pruned > 0 then
                    TRP3FW.pendingPhaseInRequests = kept
                    TRP3FW:Debug("[Cache Prune] pendingPhaseInRequests: Pruned "..pruned.." stale entries, "..#kept.." remaining", "cache")
                end
            end

            if TRP3FW.pendingPhaseInSends then
                local now = TRP3FW:GetCurrentTime()
                local ttl = math.max((TRP3FW_Settings.phaseInDelay or 4) * 3, 10)
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
    C_Timer.NewTicker(3600, function()  -- Once per hour
        if not TRP3FW_ValidatedNames or not TRP3FW_Settings then return end

        local now = time()
        local ttl = TRP3FW_Settings.validatedNamesCacheDuration or 604800 -- Default: 7 days
        local pruned = 0
        local total = 0

        -- Prune expired entries based on TTL
        for name, entry in pairs(TRP3FW_ValidatedNames) do
            total = total + 1
            local timestamp = type(entry) == "table" and entry.timestamp or 0
            local age = now - timestamp

            if age > ttl then
                TRP3FW_ValidatedNames[name] = nil
                pruned = pruned + 1
            end
        end

        local remaining = total - pruned

        -- Hard limit fallback: If still over limit after TTL pruning, clear oldest
        local limit = TRP3FW_Settings.validatedNamesCacheLimit or 5000
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
    local zoneChangeFrame = CreateFrame("Frame")
    zoneChangeFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    zoneChangeFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    zoneChangeFrame:RegisterEvent("SCENARIO_UPDATE")
    zoneChangeFrame:RegisterEvent("LOADING_SCREEN_DISABLED")
    zoneChangeFrame:SetScript("OnEvent", function(frame, event)
        local start = debugprofilestop()
        local now = TRP3FW:GetCurrentTime()
        local CI = TRP3FW.CacheInterface

        local zone = GetZoneText()
        if not zone or zone == "" then
            zone = GetRealZoneText()
        end
        if not zone or zone == "" then
            zone = GetMinimapZoneText()
        end
        TRP3FW.currentZoneName = (zone and zone ~= "") and zone or nil

        -- Special handling for loading screen end: reset phase-in timer but don't clear caches
        if event == "LOADING_SCREEN_DISABLED" then
            TRP3FW:Debug("[Zone Change] Loading screen finished, resetting phase-in timer", "cache")
            TRP3FW.lastZoneChangeTime = now
            return
        end

        local shouldClear = false
        if event == "SCENARIO_UPDATE" then
            shouldClear = TRP3FW_Settings.clearCacheOnPhaseChange
            TRP3FW:Debug("[Phase Change] SCENARIO_UPDATE detected, clearCacheOnPhaseChange="..tostring(shouldClear), "cache")

            if (now - (TRP3FW.lastZoneEventTime or 0)) < 0.5 then
                TRP3FW:Debug("[Phase Change] Zone event fired recently, skipping duplicate clear", "cache")
                return
            end
            TRP3FW.lastPhaseChangeTime = now

        elseif event == "ZONE_CHANGED_NEW_AREA" then
            shouldClear = TRP3FW_Settings.clearCacheOnZoneChange
            TRP3FW:Debug("[Zone Change] ZONE_CHANGED_NEW_AREA detected, clearCacheOnZoneChange="..tostring(shouldClear), "cache")

            if (now - (TRP3FW.lastPhaseChangeTime or 0)) < 0.5 then
                TRP3FW:Debug("[Zone Change] Phase event fired recently, merging clear settings", "cache")
            end
            TRP3FW.lastZoneEventTime = now

        elseif event == "PLAYER_ENTERING_WORLD" then
            shouldClear = true
            TRP3FW:Debug("[Zone Change] PLAYER_ENTERING_WORLD detected, clearing caches", "cache")
        end

        if not shouldClear then
            TRP3FW:Debug("[Cache] Skipping cache clear for "..event.." (disabled in settings)", "cache")
            return
        end

        TRP3FW:Debug("[Zone/Phase Change] Clearing caches due to "..event, "cache")
        TRP3FW.lastZoneChangeTime = now

        local isMergedEvent = false
        if event == "ZONE_CHANGED_NEW_AREA" and (now - (TRP3FW.lastPhaseChangeTime or 0)) < 0.5 then
            isMergedEvent = true
        end

        if event == "SCENARIO_UPDATE" then
            if TRP3FW_Settings.clearPhaseCheckOnPhaseChange then if CI then CI:Clear("phaseCheck") end end
            if TRP3FW_Settings.clearAllowedSendersOnPhaseChange then if CI then CI:Clear("allowedSenders") end end
            if TRP3FW_Settings.clearInteractionOnPhaseChange then if CI then CI:Clear("interaction") end end
            if TRP3FW_Settings.clearSuppressionOnPhaseChange then
                TRP3FW.profileSendHistory = {}
                TRP3FW.scanNotificationHistory = {}
            end
            if TRP3FW_Settings.clearRecentBroadcastsOnPhaseChange then if CI then CI:Clear("broadcast") end end
            if TRP3FW_Settings.clearRecentScansOnPhaseChange then if CI then CI:Clear("mapScan") end end
            if TRP3FW_Settings.clearWhoZoneOnPhaseChange then if CI then CI:Clear("whoZone") end end
            if TRP3FW_Settings.clearWhoNameOnPhaseChange then if CI then CI:Clear("whoName") end end

        elseif event == "ZONE_CHANGED_NEW_AREA" then
            if TRP3FW_Settings.clearPhaseCheckOnZoneChange or (isMergedEvent and TRP3FW_Settings.clearPhaseCheckOnPhaseChange) then
                if CI then CI:Clear("phaseCheck") end
            end
            if TRP3FW_Settings.clearAllowedSendersOnZoneChange or (isMergedEvent and TRP3FW_Settings.clearAllowedSendersOnPhaseChange) then
                if CI then CI:Clear("allowedSenders") end
            end
            if TRP3FW_Settings.clearInteractionOnZoneChange or (isMergedEvent and TRP3FW_Settings.clearInteractionOnPhaseChange) then
                if CI then CI:Clear("interaction") end
            end
            if TRP3FW_Settings.clearSuppressionOnZoneChange or (isMergedEvent and TRP3FW_Settings.clearSuppressionOnPhaseChange) then
                TRP3FW.profileSendHistory = {}
                TRP3FW.scanNotificationHistory = {}
            end
            if TRP3FW_Settings.clearRecentBroadcastsOnZoneChange or (isMergedEvent and TRP3FW_Settings.clearRecentBroadcastsOnPhaseChange) then
                if CI then CI:Clear("broadcast") end
            end
            if TRP3FW_Settings.clearRecentScansOnZoneChange or (isMergedEvent and TRP3FW_Settings.clearRecentScansOnPhaseChange) then
                if CI then CI:Clear("mapScan") end
            end
            TRP3FW.recentScanRequests = {}
            if TRP3FW_Settings.clearWhoZoneOnZoneChange or (isMergedEvent and TRP3FW_Settings.clearWhoZoneOnPhaseChange) then
                if CI then CI:Clear("whoZone") end
            end
            if TRP3FW_Settings.clearWhoNameOnZoneChange or (isMergedEvent and TRP3FW_Settings.clearWhoNameOnPhaseChange) then
                if CI then CI:Clear("whoName") end
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
            end
            TRP3FW.recentScanRequests = {}
        end

        -- After clears, enforce caps and drop cross-zone interaction entries
        self:PruneInteractionZoneMismatch(TRP3FW.currentZoneName)
        self:PruneCachesIncremental(CACHE_PRUNE_BUDGET)

        local shouldPrepopWho = TRP3FW_Settings.prepopulateWhoCache ~= false and ((isMergedEvent and TRP3FW_Settings.prepopulateWhoOnPhase ~= false) or (not isMergedEvent and TRP3FW_Settings.prepopulateWhoOnZone ~= false))

        if shouldPrepopWho then
            local configuredDelay = math.max(TRP3FW_Settings.phaseInDelay or 4, 0)
            local prepopulateDelay = configuredDelay > 2 and (configuredDelay - 2) or 0

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

                local zoneName
                local mapID = C_Map.GetBestMapForUnit("player")
                if mapID then
                    local info = C_Map.GetMapInfo(mapID)
                    if info and info.name and info.name ~= "" then
                        zoneName = info.name
                        TRP3FW.currentMapID = mapID
                    end
                end
                if not zoneName or zoneName == "" then
                    zoneName = GetZoneText()
                    if not zoneName or zoneName == "" then zoneName = GetRealZoneText() end
                    if not zoneName or zoneName == "" then zoneName = GetMinimapZoneText() end
                end

                local sanitized = zoneName and TRP3FW:SanitizeZoneName(zoneName) or nil
                if not sanitized then
                    return
                end

                TRP3FW.currentZoneName = sanitized

                if TRP3FW.hasEpsilonAPI and TRP3FW_Settings.useWhoQuery then
                    TRP3FW:CheckPlayerViaWho("__PREPOPULATE__", 0, function(found, source, cacheAge, zone, mapID)
                        TRP3FW:Debug("[Zone Change] WHO zone cache pre-populated (source: "..tostring(source)..")", "cache")
                    end, false)
                end
            end)
        end
        
        local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
        if hs then hs:RecordPerformance(debugprofilestop() - start, "Zone Change Cleanup") end
    end)
end

-- ===================== Interaction Tracking =====================

function CacheService:InitializeInteractionTracking()
    if self.interactionTrackingInitialized then
        return
    end

    local interactionFrame = CreateFrame("Frame")
    -- OPTIMIZATION: Interaction refresh logic uses percentage of TTL
    local refreshPercent = TRP3FW_Settings.interactionRefreshRate or 10
    local cacheDuration = TRP3FW_Settings.interactionCacheDuration or 600
    local refreshThreshold = cacheDuration * (refreshPercent / 100)
    
    local lastMouseoverProcess = 0
    local MOUSEOVER_THROTTLE = 0.5  -- OPTIMIZATION: Reduced from 0.1s (10Hz) to 0.5s (2Hz) for 80% event reduction

    interactionFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    interactionFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    self.interactionTrackingInitialized = true
    TRP3FW:Debug("[CacheService] Interaction tracking enabled (refresh threshold: "..string.format("%.1f", refreshThreshold).."s)", "cache")

    interactionFrame:SetScript("OnEvent", function(frame, event)
        local start = debugprofilestop()
        if TRP3FW_Settings.blockStartPhase and TRP3FW.hasEpsilonAPI then
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

                -- OPTIMIZATION: Check cache BEFORE expensive CleanPlayerName call
                -- This avoids regex pattern matching on cache hits (common case)
                local CI = TRP3FW.CacheInterface
                local now = TRP3FW:GetCurrentTime()
                local existing = CI and CI:Get("interaction", unitName)

                -- Only do expensive CleanPlayerName if cache miss or stale entry
                if not existing or (now - existing.timestamp) > refreshThreshold then
                    local name = TRP3FW:CleanPlayerName(unitName)
                    if name then
                        local zone = TRP3FW.currentZoneName or "Unknown"
                        if CI then
                            CI:Set("interaction", name, {
                                timestamp = now,
                                zone = zone,
                                source = "mouseover"
                            })
                            TRP3FW:Debug(function()
                                return "[Interaction Cache] Cached "..name.." from mouseover in "..zone
                            end, "cache")
                        end
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
    end)
end

TRP3FW.ServiceContainer:Register(CacheService)
