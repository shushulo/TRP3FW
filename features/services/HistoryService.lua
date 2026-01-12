-- features/services/HistoryService.lua
-- History Service: Manages session stats and notification history

local addonName, TRP3FW = ...

local HistoryService = TRP3FW.Service:New("HistoryService")

function HistoryService:Initialize()
    TRP3FW.Service.Initialize(self)
    
    self.notificationHistory = {}
    self.profileSendHistory = {}
    self.sessionStats = {
        alerts = 0,
        blocks = 0,
        ghostSends = 0,
        phaseAlerts = 0,
        mapAlerts = 0,
        startPhaseBlocks = 0,
        requestsByAddon = {TRP3=0, MRP=0, XRP=0, MSP=0},
        cacheStats = {
            allowedSendersCacheHits = 0,
            allowedSendersCacheMisses = 0,
            interactionCacheHits = 0,
            interactionCacheMisses = 0,
            phaseCacheHits = 0,
            phaseCacheMisses = 0,
            mapCacheHits = 0,
            mapCacheMisses = 0,
            whoCacheHits = 0,
            whoCacheMisses = 0,
            whoZoneCacheHits = 0,
            whoZoneCacheMisses = 0,
            whoNameCacheHits = 0,
            whoNameCacheMisses = 0,
            broadcastCacheHits = 0,
            broadcastCacheMisses = 0,
            spvpVerifiedCacheHits = 0,
            spvpVerifiedCacheMisses = 0
        },
        privilegedStats = {
            phaseCheckBatches = 0,
            phaseCheckTokensSaved = 0
        },
        spvpCache = {
            hits = 0,
            misses = 0,
            activeEntries = 0,
            apiCallsSaved = 0,
            lastRefresh = 0
        },
        performance = {
            -- Global Stats
            totalTime = 0,
            totalRequests = 0,
            peakTime = 0,
        
            -- "Live" Window Stats (Last 1s)
            lastWindowTime = 0,
            windowRequests = 0,
            windowTime = 0,
            
            -- Snapshot for Display
            lastSecondRequests = 0,
            lastSecondTime = 0,

            -- Interval Stats (Accumulating)
            intervalStart = 0,
            intervalTime = 0,
            intervalRequests = 0,
            intervalPeakLatency = 0,
            intervalPeakLoad = 0,
            intervalPeakThroughput = 0,
            
            -- Last Completed Interval (Snapshot for UI)
            lastInterval = {
                duration = 1,
                time = 0,
                requests = 0,
                peakLatency = 0,
                peakLoad = 0,
                peakThroughput = 0
            },
            
            -- Interval Context Stats (Accumulating)
            intervalContextStats = {}, -- [context] = { count, total, peak }

            -- Top 5 Lists (Snapshot)
            topStats = {
                latency = {},    -- { context, value } (Peak ms)
                cpu = {},        -- { context, value } (Total ms)
                throughput = {}  -- { context, value } (Req/sec)
            }
        },
        performanceHistory = {} -- Array of {ts, lat, load, tput, peakLat, peakLoad, memory}
    }
    
    -- Register legacy aliases
    TRP3FW.notificationHistory = self.notificationHistory
    TRP3FW.profileSendHistory = self.profileSendHistory
    TRP3FW.sessionStats = self.sessionStats
end

function HistoryService:RecordPerformance(duration, context)
    local stats = self.sessionStats.performance
    
    -- Update global stats
    stats.totalTime = stats.totalTime + duration
    stats.totalRequests = stats.totalRequests + 1
    if duration > stats.peakTime then
        stats.peakTime = duration
    end
    
    -- Track Context Stats for Interval
    if context then
        local iStats = stats.intervalContextStats
        if not iStats[context] then
            iStats[context] = { count = 0, total = 0, peak = 0 }
        end
        local entry = iStats[context]
        entry.count = entry.count + 1
        entry.total = entry.total + duration
        if duration > entry.peak then entry.peak = duration end
    end
    
    -- Update 1-second window (Instant Display)
    local now = TRP3FW:GetCurrentTime()
    if (now - stats.lastWindowTime) > 1.0 then
        -- Capture current load for interval peak tracking
        local currentLoad = (stats.windowTime / 1000) * 100
        if currentLoad > stats.intervalPeakLoad then
            stats.intervalPeakLoad = currentLoad
        end
        
        -- Capture current throughput for interval peak tracking
        if stats.windowRequests > stats.intervalPeakThroughput then
            stats.intervalPeakThroughput = stats.windowRequests
        end

        -- Roll over window
        stats.lastSecondRequests = stats.windowRequests
        stats.lastSecondTime = stats.windowTime
        
        stats.windowRequests = 0
        stats.windowTime = 0
        stats.lastWindowTime = now
    end
    
    stats.windowRequests = stats.windowRequests + 1
    stats.windowTime = stats.windowTime + duration

    -- Update Interval Stats (Always track for UI Window Avg)
    local refreshRate = TRP3FW_Settings.statusRefreshRate or 30
    
    -- Initialize interval start if needed
    if stats.intervalStart == 0 then stats.intervalStart = now end

    stats.intervalTime = stats.intervalTime + duration
    stats.intervalRequests = stats.intervalRequests + 1
    if duration > stats.intervalPeakLatency then
        stats.intervalPeakLatency = duration
    end
    
    if (now - stats.intervalStart) >= refreshRate then
        -- Snapshot for UI (Average over the window)
        stats.lastInterval.duration = refreshRate
        stats.lastInterval.time = stats.intervalTime
        stats.lastInterval.requests = stats.intervalRequests
        stats.lastInterval.peakLatency = stats.intervalPeakLatency
        stats.lastInterval.peakLoad = stats.intervalPeakLoad
        stats.lastInterval.peakThroughput = stats.intervalPeakThroughput

        -- Calculate Top 5 Stats for this Interval
        local latList, cpuList, tputList = {}, {}, {}
        for ctx, data in pairs(stats.intervalContextStats) do
            table.insert(latList,  { context = ctx, value = data.peak })
            table.insert(cpuList,  { context = ctx, value = data.total })
            table.insert(tputList, { context = ctx, value = data.count / refreshRate })
        end
        
        local function sortDesc(a,b) return a.value > b.value end
        table.sort(latList, sortDesc)
        table.sort(cpuList, sortDesc)
        table.sort(tputList, sortDesc)
        
        -- Unpack first 5 (or fewer) into new arrays
        local function slice(t, n)
            local res = {}
            for i = 1, math.min(#t, n) do res[i] = t[i] end
            return res
        end
        
        stats.topStats.latency = slice(latList, 5)
        stats.topStats.cpu = slice(cpuList, 5)
        stats.topStats.throughput = slice(tputList, 5)
        
        -- Reset Interval Context Stats (Reuse table to reduce GC churn)
        if wipe then
            wipe(stats.intervalContextStats)
        else
            stats.intervalContextStats = {}
        end

        -- History Recording (if enabled)
        if TRP3FW_Settings.performanceHistoryEnabled then
            local avgLat = stats.intervalRequests > 0 and (stats.intervalTime / stats.intervalRequests) or 0
            local avgLoad = (stats.intervalTime / (refreshRate * 1000)) * 100
            local tput = stats.intervalRequests / refreshRate
            
            -- Capture memory usage (expensive operation)
            UpdateAddOnMemoryUsage()
            local memKB = GetAddOnMemoryUsage("TRP3FW")

            table.insert(self.sessionStats.performanceHistory, {
                timestamp = now,
                avgLatency = avgLat,
                peakLatency = stats.intervalPeakLatency,
                avgLoad = avgLoad,
                maxLoad = stats.intervalPeakLoad,
                throughput = tput,
                peakThroughput = stats.intervalPeakThroughput,
                memory = memKB
            })
            
            while #self.sessionStats.performanceHistory > 50 do
                table.remove(self.sessionStats.performanceHistory, 1)
            end
        end
        
        -- Reset Interval
        stats.intervalStart = now
        stats.intervalTime = 0
        stats.intervalRequests = 0
        stats.intervalPeakLatency = 0
        stats.intervalPeakLoad = 0
        stats.intervalPeakThroughput = 0
    end
end

function HistoryService:RecordHistory(playerName, addon, wasAlert, wasBlocked)
    if not TRP3FW_Settings.trackHistory then return end
    
    -- Use SecurityService for sanitization
    local security = TRP3FW.ServiceContainer:Get("SecurityService")
    local cleanPlayer = playerName
    if security then
        cleanPlayer = security:SanitizePlayerName(playerName) or security:CleanPlayerName(playerName) or playerName
    end

    table.insert(self.notificationHistory, 1, {
        player = cleanPlayer,
        addon = addon,
        timestamp = TRP3FW:GetCurrentTime(),
        wasAlert = wasAlert,
        wasBlocked = wasBlocked
    })
    
    while #self.notificationHistory > TRP3FW_Settings.maxHistorySize do
        table.remove(self.notificationHistory)
    end
end

function HistoryService:GetSessionStats()
    return self.sessionStats
end

function HistoryService:IncrementStat(category, subcategory, amount)
    amount = amount or 1
    if subcategory then
        if self.sessionStats[category] and self.sessionStats[category][subcategory] then
            self.sessionStats[category][subcategory] = self.sessionStats[category][subcategory] + amount
        end
    else
        if self.sessionStats[category] then
            self.sessionStats[category] = self.sessionStats[category] + amount
        end
    end
end

TRP3FW.ServiceContainer:Register(HistoryService)
