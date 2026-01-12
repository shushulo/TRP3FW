-- core/init.lua
-- Core initialization, settings, and shared namespace for TRP3FW

local addonName, TRP3FW = ...

-- Version info
TRP3FW.VERSION = "2.9.2-hotfix"
TRP3FW.ADDON_NAME = addonName

-- FIXED: HIGH-6 - SendId verification system (prevents spoofing)
-- Random salt generated once per session for HMAC-like signatures
TRP3FW.sendIdSalt = math.random(1000000, 9999999)

-- Color constants
TRP3FW.COLOR = {
    white = "ffffff",
    green = "00ff00",
    red   = "ff0000",
    yellow = "ffff00",
    blue  = "00ccff",
    orange = "ff6600",
    gray  = "aaaaaa",
    info  = "00ff00",
    warn  = "ffff00",
    err   = "ff0000",
    debug = "aaaaaa",
}

-- Safe globals
TRP3FW.tinsert = tinsert or table.insert
TRP3FW.tremove = tremove or table.remove

-- Default settings
TRP3FW.defaultSettings = {
    notifyEnabled    = true,
    suppressionTime  = 600,
    refreshSuppression = true, -- Extend suppression duration on new activity (sliding window)
    showInChat       = true,
    showOnScreen     = false,
    playSound        = false,
    trackHistory     = true,
    maxHistorySize   = 100,
    uiComplexityLevel = 2, -- 1=Basic, 2=Intermediate, 3=Advanced, 4=Everything

    -- Granular notification controls
    notifyOnAllow    = true,   -- Show notifications for allowed profile sends
    notifyOnStartPhaseBlock = true,  -- Show notifications for start phase (169) blocks
    -- Note: notifyOnAlert and notifyOnBlock removed - now controlled by phaseCheckMode/mapCheckMode dropdowns
    notifyOnScanAllow = true,  -- Show notifications when scan replies are allowed/sent

    monitorTRP3     = true,
    monitorMRP      = true,
    monitorXRP      = true,
    monitorMSP      = true,
    showAddonSource = true,

    -- Hook/install safety
    strictHookMode = false,            -- Refuse to install hooks when another addon already wrapped the target
    logHookConflicts = true,           -- Log hook conflicts even when chaining is allowed
    abortOnMultipleRPAddons = true,    -- Disable TRP3FW if more than one of TRP3/MRP/XRP is detected
    disableMapScanOnTRP3 = true,       -- Disable map-scan hooks when TRP3 and RPMapScan/RPMapScanner coexist

    -- Always-allow whitelist (bypasses phase/map/ghost checks)
    whitelistEnabled = false,
    whitelistEntries = "",

    -- Dropdown settings for location checking
    -- Options: "off", "statistics", "alert", "block", "ghost", "alert_block", "alert_ghost"
    phaseCheckMode = "alert",  -- Phase checking behavior
    mapCheckMode   = "alert",  -- Map/WHO checking behavior

    -- Start phase settings
    useWhoQuery       = true,
    ghostOnStartPhase = false,  -- Ghost mode in start phase (DISABLED BY DEFAULT - enable if you want to send blank profiles instead of blocking)
    ghostProfileSwitch = false,  -- Switch to blank profile in phase 169, map 1605 (DISABLED BY DEFAULT - alerts only)
    ghostProfileWhitelistEnabled = false, -- Additional phase/map whitelist for profile switching
    ghostProfileWhitelist = "",           -- One entry per line: <phase> or <phase>,<map>
    ghostProfileOverrides = {},           -- Phase/map-specific profile override entries
    ghostProfileName = "TRP3FW_BLANK",

    notifyOnBroadcast = false,
    notifyOnWhisper   = true,
    ignoreMapScan     = true,
    notifyOnScanResponse = false, -- Show notification when TRP3 responds to map scans (only if RPMapScan not installed)
    scanResponsePhaseMode = "alert", -- Phase mismatch behavior for scan replies: "alert" or "block"
    scanResponseMapMode = "alert", -- Map/zone mismatch behavior for scan replies: "alert" or "block"
    scanResponseRequireNonce = false, -- Require map scan replies to include the issued nonce (compat off by default)
    scanResponseCacheEnabled = true, -- Cache WHO results (name/zone) when a WHO query runs for scan replies
    scanResponseAllowCacheBypass = true, -- Allow scan replies to bypass WHO if interaction/send/phase cache has a valid entry
    scanResponsePhaseCheckEnabled = true, -- Use phase check before WHO for scan replies (only applies if WHO gate is on)
    scanResponseAllowGroupBypass = true, -- Allow map scan replies to party/raid without phase/map/WHO gates (default on)
    scanResponseWhitelistEnabled = true,

    showCheckResults = false,   -- Show pass/fail/method details for phase/map checks in notifications
    allowGroupPhaseBypass = false, -- Party/raid members skip phase check (legacy behavior) when enabled

    showCacheInfo     = false,    -- Append cache hit/miss info to allow notifications
    showGhostNotifications = true, -- Display chat/on-screen messages when ghost profiles are sent
    prepopulateWhoCache = true, -- Prepopulate WHO cache after zone/phase changes
    prepopulateWhoOnPhase = true, -- Run WHO pre-population on phase change
    prepopulateWhoOnZone = true, -- Run WHO pre-population on zone change
    -- Phase cache prepopulation removed (relies on live targeting only)

    scanCacheDuration  = 120,
    scanCacheFailureDuration = 10, -- Short TTL for failed/mismatched scan/broadcast entries
    mapScanMinInterval = 60,   -- Minimum seconds between map scans (manual or automatic)
    sendCacheDuration  = 600,

    spvpVerifiedCacheDuration = 300,    -- 5 minutes (cryptographic verification)
    spvpVerifiedRefreshRate = 50,       -- Refresh when age > 50% of TTL
    spvpPhaseSaltRefreshRate = 50,      -- Refresh when salt age > 50% of TTL

    phaseCacheDuration = 300,    -- 5 minutes (up from 120s)
    phaseCacheRefreshThreshold = 0.5, -- Refresh when age > 50% of TTL (150s)
    phaseCacheFailureDuration = 10, -- Short cache duration for failed phase checks (allows quick retries)
    
    -- Batch Phase Check Settings (Optimization #2)
    phaseCheckBatchMode = true,         -- Enable batched phase checks
    phaseCheckBatchSize = 5,            -- Max batch size (2-10)
    phaseCheckBatchDelay = 1.0,         -- Delay before batching (0.1-2.0s)
    phaseCheckBatchMinSize = 3,         -- Only batch if queue >= 3
    phaseCheckInterTargetDelay = 0.1,   -- Delay between targets (0.01-0.2s, default: 0.1 = 100ms)

    -- Token Refund (Optimization #5) - SECURITY WARNING: Disabled by default
    phaseCheckRefundOnNoChange = false, -- Refund restoration token when target doesn't change

    -- Priority System (Optimization #9)
    privilegedReservedTokens = 2,       -- Tokens reserved for high-priority (0-5)
    privilegedLowPriorityThreshold = 4, -- Defer low-priority if tokens < 4 (2-8)

    whoZoneCacheDuration = 180,  -- Cache WHO zone lookups longer for stability (configurable via UI/command)
    whoNameCacheDuration = 180,  -- Cache WHO name lookups longer for stability (configurable via UI/command)
    whoCacheRefreshThreshold = 50, -- Refresh when age > 50% of TTL (0-100%)
    whoZoneQueryCooldown = 20,   -- Increased from 15s to be more server-friendly (configurable via UI/command)
    

    suppressAllWhoOutput = true, -- Suppress ALL WHO output (not just TRP3FW queries) - helps reduce spam
    interactionCacheDuration = 600, -- LONG duration: Skip location checks for people you've interacted with (mouseover/target)
    interactionRefreshRate = 10,    -- Refresh threshold percentage (0-100% of duration). Default 10% means refresh if entry is older than 10% of TTL.
    sendCacheRefreshRate = 10,      -- Refresh threshold percentage (0-100% of duration). Default 10% means refresh if entry is older than 10% of TTL.

    -- Cache size limits (configurable for different memory/performance needs)
    cacheSizeLimit = 1000,       -- General cache size limit (interaction, phase, WHO zone/name)
    whoQueueLimit = 100,         -- Maximum WHO query queue size
    cleanNameCacheSize = 500,    -- CleanPlayerName cache size
    sanitizedNameCacheSize = 500, -- SanitizePlayerName cache size
    validatedNamesCacheDuration = 604800, -- Validated names cache TTL in seconds (default: 7 days = 604800s)
    validatedNamesCacheLimit = 5000, -- Validated names cache size limit (default: 5000, range: 500-10000)

    phaseInDelay = 4,            -- Seconds to delay profile request processing after phasing (0-10, prevents false alerts during player load-in)
    transitionGracePeriod = 3,  -- Seconds after map/phase change to warn about potential false alerts (0-30, helps identify race conditions)

    -- Cache clearing on phase change (SCENARIO_UPDATE event)
    clearCacheOnPhaseChange = true,  -- Master toggle for phase change clearing
    clearPhaseCheckOnPhaseChange = true,         -- Clear phase check cache
    clearAllowedSendersOnPhaseChange = true,     -- Clear allowed senders cache
    clearInteractionOnPhaseChange = true,        -- Clear interaction cache
    clearSuppressionOnPhaseChange = true,        -- Clear notification suppression timers
    clearRecentBroadcastsOnPhaseChange = false,  -- Clear recent broadcasts cache
    clearRecentScansOnPhaseChange = false,       -- Clear recent scans cache
    clearWhoZoneOnPhaseChange = false,           -- Clear WHO zone cache
    clearWhoNameOnPhaseChange = false,           -- Clear WHO name cache
    clearSpvpOnPhaseChange = true,               -- Clear SPVP verification cache

    -- Cache clearing on zone change (ZONE_CHANGED_NEW_AREA event)
    clearCacheOnZoneChange = true,   -- Master toggle for zone change clearing
    clearPhaseCheckOnZoneChange = true,          -- Clear phase check cache
    clearAllowedSendersOnZoneChange = true,      -- Clear allowed senders cache
    clearInteractionOnZoneChange = true,         -- Clear interaction cache
    clearSuppressionOnZoneChange = true,         -- Clear notification suppression timers
    clearWhoZoneOnZoneChange = true,             -- Clear WHO zone cache
    clearRecentBroadcastsOnZoneChange = false,   -- Clear recent broadcasts cache
    clearRecentScansOnZoneChange = false,        -- Clear recent scans cache
    clearWhoNameOnZoneChange = false,            -- Clear WHO name cache
    clearSpvpOnZoneChange = false,               -- Clear SPVP verification cache

    statusRefreshRate = 30,  -- Seconds between Status tab updates (2-120)
    performanceHistoryEnabled = false, -- Enable tracking of performance metrics over time

    blockStartPhase = false,

    -- SPVP (Secure Phase Verification Protocol) v2.5
    spvpEnabled = true,              -- Master toggle for SPVP (ENABLED BY DEFAULT)
    spvpMode = "optional",           -- "off", "optional", "preferred", "required"
    spvpAutoInitialize = false,       -- Auto-generate salts when entering phase (phase owners only)
    spvpBlockDuration = 60,           -- Block duration after failed verification (seconds, 10-3600)
    spvpSaltCacheDuration = 10800,    -- Phase salt cache duration (seconds, default 3 hours = 10800s)
    spvpPerPhaseOverrides = {},       -- Per-phase SPVP enable/disable overrides

    debug           = false,
    debugTimestamp  = false,
    debugChannel    = true,
    debugWhisper    = true,
    debugWho        = true,
    debugPhase      = true,
    debugCleanName  = false,
    debugLocation   = true,
    debugDecision   = true,
    debugHooks      = true,
    debugCache      = true,
    debugSend       = true,
    debugUI         = true,
    debugUtils      = true,
    debugSecurity   = true,  -- Security enforcement messages (sanitization, cache limits, spoofing detection)
    debugGhost      = true,  -- Ghost mode execution flow and exchange hook calls
    debugSPVP       = true,  -- SPVP (Secure Phase Verification Protocol) handshake and verification

    -- Redaction controls
    redactEnabled   = true,
    redactNames     = true,
    redactLocations = true,
    redactNetwork   = true,
    redactSPVP      = true,

    -- Debug output settings
    debugOutputWindow = false,  -- Show debug window
    debugOutputChat   = true,   -- Output to chat
    debugOutputBoth   = false,  -- Output to both

    -- WHO backend selection (Epsilon)
    useLibWhoBackend = true,   -- Use UI-bucket WHO queries (LibWho-style) when Epsilon API is available
    whoQueuePolicy = "addon_first", -- addon_first | user_first | fifo
    cacheUserWhoResults = false, -- Cache results from user /who queries (zone/name with map)

	filterGradients = false,
	filterMinimumFontSize = false,  -- Inject minimum font size into incoming profiles
	minimumFontSizeLevel = "h3",    -- Font size level to inject (h1, h2, h3, p)

    -- Scan reply whitelist (one player per line)
    scanResponseWhitelist = "",

    -- Ghosting via Chomp (TRP3/MSP payloads serialized through Chomp)
    enableChompGhost = true,
}

-- Hook state containers (recursion/replay guards and original proxies)
TRP3FW.hookState = TRP3FW.hookState or {}
TRP3FW.hookState.chomp = TRP3FW.hookState.chomp or {
    replayingPhaseInSend = false,
    sendingGhostProfile = false,
}
TRP3FW.hookState.exchange = TRP3FW.hookState.exchange or {}
TRP3FW.hookState.originals = TRP3FW.hookState.originals or {}
TRP3FW.hookConflicts = TRP3FW.hookConflicts or {}  -- records detected hook conflicts
TRP3FW.hookStatus = TRP3FW.hookStatus or {}        -- per-hook install outcomes

-- ===================== Dropdown Settings Helper Functions =====================
-- These functions read the unified dropdown setting and return boolean values
-- for use throughout the codebase

function TRP3FW:IsPhaseCheckEnabled()
    return TRP3FW_Settings.phaseCheckMode ~= "off"
end

function TRP3FW:IsMapCheckEnabled()
    return TRP3FW_Settings.mapCheckMode ~= "off"
end

function TRP3FW:ShouldAlertOnPhase()
    local mode = TRP3FW_Settings.phaseCheckMode
    return mode == "alert" or mode == "alert_block" or mode == "alert_ghost"
end

function TRP3FW:ShouldAlertOnMap()
    local mode = TRP3FW_Settings.mapCheckMode
    return mode == "alert" or mode == "alert_block" or mode == "alert_ghost"
end

function TRP3FW:ShouldBlockOnPhase()
    local mode = TRP3FW_Settings.phaseCheckMode
    return mode == "block" or mode == "ghost" or mode == "alert_block" or mode == "alert_ghost"
end

function TRP3FW:ShouldBlockOnMap()
    local mode = TRP3FW_Settings.mapCheckMode
    return mode == "block" or mode == "ghost" or mode == "alert_block" or mode == "alert_ghost"
end

function TRP3FW:ShouldGhostOnPhase()
    local mode = TRP3FW_Settings.phaseCheckMode
    return mode == "ghost" or mode == "alert_ghost"
end

function TRP3FW:ShouldGhostOnMap()
    local mode = TRP3FW_Settings.mapCheckMode
    return mode == "ghost" or mode == "alert_ghost"
end

function TRP3FW:IsProfileSwitchOverrideActive()
    if not TRP3FW_Settings.ghostProfileSwitch then
        return false
    end

    if self.isBlankProfileActive then
        return true
    end

    if type(self.ShouldUseBlankProfile) == "function" then
        local ok, result = pcall(self.ShouldUseBlankProfile, self)
        if ok and result then
            return true
        end
    end

    return false
end

function TRP3FW:IsGhostModeEnabled()
    -- Ghost mode is enabled if ANY check type is configured for ghost OR start phase ghost is enabled
    local phaseGhost = (TRP3FW_Settings.phaseCheckMode == "ghost" or TRP3FW_Settings.phaseCheckMode == "alert_ghost")
    local mapGhost = (TRP3FW_Settings.mapCheckMode == "ghost" or TRP3FW_Settings.mapCheckMode == "alert_ghost")
    return phaseGhost or mapGhost or TRP3FW_Settings.ghostOnStartPhase
end

-- Runtime state
TRP3FW.detectedAddons = {}
-- TRP3FW.notificationHistory managed by HistoryService
-- TRP3FW.profileSendHistory managed by HistoryService
TRP3FW.scanNotificationHistory = {}
TRP3FW.hookInstalled = false
TRP3FW.hasEpsilonAPI = false
TRP3FW.hasTRP3ExchangeHooks = false  -- Track if TRP3 exchange hooks installed successfully

-- Saved settings for when dependencies are missing (restored when available)
TRP3FW.savedSettings = {}  -- Stores user's actual preference when dependency is missing

-- Session statistics
-- Now managed by HistoryService (features/services/HistoryService.lua)
-- TRP3FW.sessionStats is aliased by the service upon initialization.

-- ===================== Performance Profiling System =====================
-- High-precision profiling using debugprofilestop() for performance analysis
-- Usage:
--   TRP3FW.profiler.start("functionName")
--   ... code to measure ...
--   TRP3FW.profiler.stop("functionName")
--   TRP3FW.profiler.report() -- Print statistics

TRP3FW.profiler = {
    enabled = false,  -- Toggle profiling on/off (disabled by default for production)
    active = {},      -- Currently active timers: [name] = startTime
    stats = {},       -- Collected statistics: [name] = {count, totalTime, minTime, maxTime, calls}
}

-- Start profiling a function/block
function TRP3FW.profiler.start(name)
    if not TRP3FW.profiler.enabled then return end
    TRP3FW.profiler.active[name] = debugprofilestop()
end

-- Stop profiling and record statistics
function TRP3FW.profiler.stop(name)
    if not TRP3FW.profiler.enabled then return end

    local startTime = TRP3FW.profiler.active[name]
    if not startTime then
        -- Warning: stop called without start
        return
    end

    local elapsed = debugprofilestop() - startTime
    TRP3FW.profiler.active[name] = nil

    -- Initialize stats for this function if first call
    if not TRP3FW.profiler.stats[name] then
        TRP3FW.profiler.stats[name] = {
            count = 0,
            totalTime = 0,
            minTime = math.huge,
            maxTime = 0,
            calls = {}  -- Store recent calls for percentile calculations
        }
    end

    local stats = TRP3FW.profiler.stats[name]
    stats.count = stats.count + 1
    stats.totalTime = stats.totalTime + elapsed
    stats.minTime = math.min(stats.minTime, elapsed)
    stats.maxTime = math.max(stats.maxTime, elapsed)

    -- Keep last 1000 calls for percentile calculations
    table.insert(stats.calls, elapsed)
    if #stats.calls > 1000 then
        -- FIXED: MEDIUM-2 - Use random eviction instead of FIFO to prevent timing attacks
        local randomIndex = math.random(1, #stats.calls)
        table.remove(stats.calls, randomIndex)
    end
end

-- Calculate percentile from sorted array
local function calculatePercentile(sortedArray, percentile)
    if #sortedArray == 0 then return 0 end
    local index = math.ceil(#sortedArray * percentile / 100)
    return sortedArray[index]
end

-- Generate profiling report
function TRP3FW.profiler.report()
    if not TRP3FW.profiler.enabled then
        print("|cffff6600[TRP3FW Profiler]|r Profiling is disabled. Enable with: /trp3fw profile on")
        return
    end

    print("|cffff6600========================================|r")
    print("|cffff6600    TRP3FW Performance Profile Report|r")
    print("|cffff6600========================================|r")

    -- Collect and sort by total time (descending)
    local sortedFunctions = {}
    for name, stats in pairs(TRP3FW.profiler.stats) do
        table.insert(sortedFunctions, {name = name, stats = stats})
    end
    table.sort(sortedFunctions, function(a, b)
        return a.stats.totalTime > b.stats.totalTime
    end)

    -- Print header
    print(string.format("|cff00ccff%-30s %8s %10s %10s %10s %10s %10s|r",
        "Function", "Calls", "Total(ms)", "Avg(ms)", "Min(ms)", "Max(ms)", "P95(ms)"))
    print("|cffaaaaaa-----------------------------------------------------------------------------------|r")

    -- Print each function's stats
    for _, entry in ipairs(sortedFunctions) do
        local name = entry.name
        local stats = entry.stats
        local avgTime = stats.count > 0 and (stats.totalTime / stats.count) or 0

        -- Calculate P95 (95th percentile)
        local sortedCalls = {}
        for _, t in ipairs(stats.calls) do
            table.insert(sortedCalls, t)
        end
        table.sort(sortedCalls)
        local p95 = calculatePercentile(sortedCalls, 95)

        print(string.format("%-30s %8d %10.3f %10.3f %10.3f %10.3f %10.3f",
            name:sub(1, 30),  -- Truncate long names
            stats.count,
            stats.totalTime,
            avgTime,
            stats.minTime == math.huge and 0 or stats.minTime,
            stats.maxTime,
            p95
        ))
    end

    print("|cffaaaaaa-----------------------------------------------------------------------------------|r")
    print(string.format("|cff00ff00Total functions profiled: %d|r", #sortedFunctions))
end

-- Reset profiling statistics
function TRP3FW.profiler.reset()
    TRP3FW.profiler.stats = {}
    TRP3FW.profiler.active = {}
    print("|cff00ff00[TRP3FW Profiler]|r Statistics reset.")
end

-- Enable/disable profiling
function TRP3FW.profiler.toggle(enable)
    TRP3FW.profiler.enabled = enable
    if enable then
        print("|cff00ff00[TRP3FW Profiler]|r Profiling enabled. Use /trp3fw profile report to see results.")
    else
        print("|cffaaaaaa[TRP3FW Profiler]|r Profiling disabled.")
    end
end

-- ===================== Refactor Logging =====================
-- Used to log transitions and debug messages during the refactoring process
function TRP3FW:DebugRefactor(message, category)
    if not self:IsFeatureEnabled("enableRefactorLogging") then
        return
    end

    local formatted = string.format("[REFACTOR] [%s] %s", category or "GENERAL", message)
    self:Debug(formatted, "refactor")

    if self.AddDebugMessage then
        self:AddDebugMessage(formatted, "refactor")
    end
end

function TRP3FW:LogRefactorTransition(functionName, version, context)
    if not self:IsFeatureEnabled("enableRefactorLogging") then
        return
    end

    local contextStr = "none"
    if context and type(context) == "table" then
        contextStr = string.format("playerName=%s, addon=%s, sendId=%s",
            tostring(context.playerName),
            tostring(context.addon),
            tostring(context.sendId))
    end

    self:DebugRefactor(string.format(
        "Function: %s | Version: %s | Context: %s",
        functionName,
        version,
        contextStr
    ), "TRANSITION")
end

-- Pending sends
TRP3FW.pendingSends = {}
TRP3FW.pendingSendId = 0

-- Caches (DEPRECATED: Migrated to CacheInterface - kept for backwards compatibility)
-- All cache access now goes through TRP3FW.CacheInterface with O(1) LRU eviction
TRP3FW.allowedSendersCache = {}  -- DEPRECATED: Use CacheInterface:Get/Set("allowedSenders", ...)
TRP3FW.recentScans = {}  -- DEPRECATED: Use CacheInterface:Get/Set("mapScan", ...)
TRP3FW.recentBroadcasts = {}  -- DEPRECATED: Use CacheInterface:Get/Set("broadcast", ...)
TRP3FW.phaseCheckCache = {}  -- DEPRECATED: Use CacheInterface:Get/Set("phaseCheck", ...)
TRP3FW.whoZoneCache = {}  -- DEPRECATED: Use CacheInterface:Get/Set("whoZone", ...)
TRP3FW.whoNameCache = {}  -- DEPRECATED: Use CacheInterface:Get/Set("whoName", ...)
TRP3FW.interactionCache = {}  -- DEPRECATED: Use CacheInterface:Get/Set("interaction", ...)

-- Performance: Frame-based monotonic time caching (eliminates ~95 syscalls per request)
TRP3FW.cachedTime = nil
TRP3FW.cachedTimeFrame = 0

-- OPTIMIZATION: Phase ID caching (eliminates redundant C_Epsilon.GetPhaseId() calls in ghost mode)
-- Phase changes are rare relative to profile sends, so cache with 1-second TTL
-- Reduces 4-8 API calls per ghost mode profile send to 1 call per second
TRP3FW.cachedPhaseID = nil
TRP3FW.cachedPhaseTimestamp = 0
TRP3FW.PHASE_CACHE_TTL = 1  -- Cache phase ID for 1 second (balance between freshness and performance)

-- DEPRECATED: Hash-based player name normalization caches (migrated to CacheInterface)
-- These tables are kept for backwards compatibility but are no longer used
-- CleanPlayerName() and SanitizePlayerName() now use CacheInterface:Get/Set("cleanName"/"sanitizedName", ...)
TRP3FW.cleanNameCache = {}  -- DEPRECATED
TRP3FW.cleanNameCacheTimestamps = {}  -- DEPRECATED
TRP3FW.sanitizedNameCache = {}  -- DEPRECATED
TRP3FW.sanitizedNameCacheTimestamps = {}  -- DEPRECATED
TRP3FW.cleanNameCacheCount = 0  -- DEPRECATED
TRP3FW.sanitizedNameCacheCount = 0  -- DEPRECATED

-- Performance: Object pools for WHO query results (reduces GC pressure)
-- Removed pool (unused) - cache entries are created on demand

-- OPTIMIZATION: MSP conversion cache (eliminates redundant TRP3→MSP conversions in ghost mode)
-- TRP3 profile conversion is expensive (155 lines of string processing, table operations)
-- Cache persists for session (profiles rarely change during play session)
TRP3FW.mspConversionCache = {}  -- [profileID] = {mspFields, timestamp}

-- Ghost mode state (REFACTORED: Single active ghost flag to eliminate target ambiguity)
-- BEFORE: ghostNextSend = {["PlayerA"] = {expires, addon}, ["PlayerB"] = {...}}
-- AFTER:  ghostNextSend = {target = "PlayerA", expires = time, profileID = nil}
-- This ensures GetCurrentGhostTarget() always knows the correct recipient
TRP3FW.ghostNextSend = nil  -- Single ghost flag: {target, expires, addon, timestamp, profileID}
TRP3FW.ghostCleanupTimer = nil  -- Timer for auto-cleanup (cancelled when new ghost flag is set)

-- Whitelist cache
TRP3FW.whitelistCache = {}
TRP3FW.whitelistCacheRaw = ""

-- WHO query state
TRP3FW.whoQueryActive = false
TRP3FW.pendingWhoQueries = {}
TRP3FW.lastWhoQueryTime = 0
TRP3FW.lastZoneQueryTime = 0  -- Timestamp of last z- zone query (for cooldown)
TRP3FW.suppressWhoOutput = false
TRP3FW.whoQuerySentTime = 0  -- Timestamp-based suppression for WHO queries
TRP3FW.whoQueryRequestId = 0  -- Unique ID for each query to prevent timeout conflicts

-- FIXED: HIGH-2 - Phase check targeting mutex (prevents race conditions)
TRP3FW.targetingInProgress = false  -- Mutex lock for target manipulation
TRP3FW.phaseCheckTargeting = false  -- Marks automated targeting during phase checks
TRP3FW.pendingPhaseChecks = {}  -- Queue for phase checks waiting for lock

-- Zone change state
TRP3FW.lastZoneChangeTime = 0  -- Timestamp of last zone change (for phase-in delay)
TRP3FW.lastPhaseChangeTime = 0  -- Timestamp of last phase change (for deduplication)
TRP3FW.lastZoneEventTime = 0    -- Timestamp of last zone event (for deduplication)
TRP3FW.pendingPhaseInRequests = {}  -- Queued profile requests during phase-in delay (DEPRECATED - use pendingPhaseInSends)
TRP3FW.pendingPhaseInSends = {}  -- Queued Chomp sends during phase-in delay
TRP3FW.PHASE_IN_QUEUE_LIMIT = 200

-- Original function references (for hooks)
TRP3FW.originalMSPSend = nil
TRP3FW.originalMSPReply = nil

-- Initialize settings
function TRP3FW:InitializeSettings()
    TRP3FW_Settings = TRP3FW_Settings or {}

    for k, v in pairs(self.defaultSettings) do
        if TRP3FW_Settings[k] == nil then
            TRP3FW_Settings[k] = v
        end
    end

    -- Set cache size constants from settings (allows runtime configuration)
    TRP3FW.CLEAN_NAME_CACHE_MAX = TRP3FW_Settings.cleanNameCacheSize
    TRP3FW.SANITIZED_NAME_CACHE_MAX = TRP3FW_Settings.sanitizedNameCacheSize

    -- OPTIMIZATION: Initialize validated names cache (persistent across sessions)
    -- This cache stores validated player names to skip expensive regex validation on repeat encounters
    TRP3FW_ValidatedNames = TRP3FW_ValidatedNames or {}

    -- MIGRATION: Force enable SPVP for Epsilon users who haven't explicitly disabled it
    if self.hasEpsilonAPI and TRP3FW_Settings.spvpEnabled == false then
        if not TRP3FW_Settings.spvpExplicitlyDisabled then
            TRP3FW_Settings.spvpEnabled = true
            self:Debug("Migration: Force-enabled SPVP for Epsilon user", "init")
        end
    end
end

-- Disable settings that require missing dependencies (save original values)
function TRP3FW:HandleDependencySettings()
    -- Settings requiring Epsilon API
    local epsilonSettings = {
        { key = "phaseCheckMode", disableValue = "off" },
        { key = "useWhoQuery", disableValue = false },
        { key = "prepopulateWhoCache", disableValue = false },
        { key = "prepopulateWhoOnPhase", disableValue = false },
        { key = "prepopulateWhoOnZone", disableValue = false },
        { key = "scanResponsePhaseCheckEnabled", disableValue = false },
        { key = "scanResponsePhaseMode", disableValue = "off" },
        { key = "scanResponseMapMode", disableValue = "off" },
        { key = "blockStartPhase", disableValue = false },
        { key = "ghostOnStartPhase", disableValue = false },
        { key = "ghostProfileSwitch", disableValue = false },
    }

    -- Settings requiring TRP3
    local trp3Settings = {
        -- Note: ghostMode works for MSP/MRP/XRP without TRP3, only TRP3-specific ghost needs TRP3 hooks
    }

    local function applyDependency(hasDependency, settings, dependencyName)
        for _, entry in ipairs(settings) do
            local key = entry.key
            local disableValue = entry.disableValue

            if not hasDependency then
                if TRP3FW_Settings[key] ~= disableValue then
                    -- Save the user's preference
                    self.savedSettings[key] = TRP3FW_Settings[key]
                    -- Temporarily disable
                    TRP3FW_Settings[key] = disableValue
                    self:Debug("Disabled "..key.." ("..dependencyName.." not available, saved: "..tostring(self.savedSettings[key])..")", "init")
                end
            else
                if self.savedSettings[key] ~= nil then
                    TRP3FW_Settings[key] = self.savedSettings[key]
                    self:Debug("Restored "..key.." to "..tostring(self.savedSettings[key]).." ("..dependencyName.." now available)", "init")
                    self.savedSettings[key] = nil
                end
            end
        end
    end

    applyDependency(self.hasEpsilonAPI, epsilonSettings, "Epsilon API")
    applyDependency(self.hasTRP3ExchangeHooks, trp3Settings, "TRP3")
end

-- Call initialization
TRP3FW:InitializeSettings()

-- Create main frame
TRP3FW.frame = CreateFrame("Frame", "TRP3FW_MainFrame")

-- Ensure settings persist after ADDON_LOADED
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addon)
    if addon == addonName then
        TRP3FW:InitializeSettings()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
