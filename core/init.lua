-- core/init.lua
-- Core initialization, settings, and shared namespace for TRP3FW

local addonName, TRP3FW = ...

-- Version info. This is the single source of truth for the addon version:
-- TRP3FW.toc, the README badge and the release tag are all checked against it
-- by scripts/make-release.sh, which refuses to build if they disagree.
--
-- Numbering unified with the release branch line as of 1.6.0 (branch v1.6 ->
-- version 1.6.0, tag v1.6.0). This is a deliberate step DOWN from the previous
-- 2.9.x line: existing installs carry TRP3FW_DB.global.lastVersion = "2.9.2-hotfix",
-- so any future upgrade check must not assume versions increase monotonically
-- across this boundary.
TRP3FW.VERSION = "1.6.0"
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
    -- INERT: declared here but read nowhere (verified repo-wide). Kept so an existing
    -- SavedVariables entry is not silently dropped; changing it has no effect on behaviour.
    -- Map-scan handling is gated by disableMapScanOnTRP3 and the scanResponse* settings.
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
    -- TRP3->MSP ghost-profile conversion cache. There is no profile-edited event anywhere in
    -- the addon to invalidate on, so this TTL is what bounds how long an edit to the ghost
    -- profile keeps transmitting the pre-edit version.
    mspConversionCacheDuration = 300,

    spvpVerifiedCacheDuration = 300,    -- 5 minutes (cryptographic verification)
    spvpVerifiedRefreshRate = 50,       -- Refresh when age > 50% of TTL
    spvpPhaseSaltRefreshRate = 50,      -- Refresh when salt age > 50% of TTL

    phaseCacheDuration = 300,    -- 5 minutes (up from 120s)
    phaseCacheRefreshThreshold = 0.5, -- Refresh when age > 50% of TTL (150s)
    phaseCacheFailureDuration = 10, -- Short cache duration for failed phase checks (allows quick retries)

    -- Phase-check targeting side-effect mitigations
    muteTargetSound = true,             -- Suppress WoW's target-acquired sound during automated phase-check targeting
    pausePhaseCheckOnInspect = false,   -- Skip/defer automated phase-check targeting while the armory/inspect frame is open
    -- When paused for inspect, retry once/second for up to 10s. If inspect is still
    -- open after that, resolve the check as this phase result (then the normal phase/map
    -- modes and SPVP fallback decide the action): "in_phase" or "out_of_phase".
    inspectTimeoutResolution = "out_of_phase",

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
    --
    -- INERT: all three are declared here and read NOWHERE (verified repo-wide). They describe a
    -- configurable WHO backend that was never built -- WhoService has a single code path, and
    -- its queue ordering is fixed rather than policy-driven. Left in place so existing
    -- SavedVariables entries survive and so the intent is not lost, but nothing reads them:
    -- changing any of these has no effect. Wire them up in WhoService before documenting them
    -- as functional.
    useLibWhoBackend = true,   -- Use UI-bucket WHO queries (LibWho-style) when Epsilon API is available
    whoQueuePolicy = "addon_first", -- addon_first | user_first | fifo
    cacheUserWhoResults = false, -- Cache results from user /who queries (zone/name with map)

	filterGradients = false,
	filterIcons = false,
	filterMinimumFontSize = false,  -- Inject minimum font size into incoming profiles
	minimumFontSizeLevel = "h3",    -- Font size level to inject (h1, h2, h3, p)

    -- Scan reply whitelist (one player per line)
    scanResponseWhitelist = "",
}

-- Fallback for early access, until LoadProfile repoints this at the real profile table.
--
-- This used to be a bare alias (`TRP3FW.Prefs = TRP3FW.defaultSettings`). If anything wrote a
-- setting while the alias was live, it mutated defaultSettings itself -- and since LoadProfile
-- backfills missing keys FROM defaultSettings, every profile created afterwards was born with
-- the polluted value. That window is not hypothetical: TRP3FW.lua pcall-wraps
-- InitializeSettings precisely because a throw there leaves this alias in place for the whole
-- session (see the section-9 finding).
--
-- A copy costs one table at load and closes the hole. Table-valued defaults are deep-copied,
-- for the same reason LoadProfile's copyDefault exists: a shallow copy would still share
-- ghostProfileOverrides/spvpPerPhaseOverrides with defaultSettings, and the UI mutates those
-- in place. (copyDefault itself is declared further down, next to LoadProfile, so this does
-- the recursion inline rather than forward-referencing it.)
do
    local function deepCopy(value)
        if type(value) ~= "table" then return value end
        local copy = {}
        for k, v in pairs(value) do copy[k] = deepCopy(v) end
        return copy
    end

    TRP3FW.Prefs = deepCopy(TRP3FW.defaultSettings)
end

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
    return TRP3FW.Prefs.phaseCheckMode ~= "off"
end

function TRP3FW:IsMapCheckEnabled()
    return TRP3FW.Prefs.mapCheckMode ~= "off"
end

-- Scan-reply nonce verification is HARD-DISABLED: the half of the feature that would make it
-- work does not exist.
--
-- MapScan generates a per-scan nonce and stores it on the activeScanCallbacks entry, but
-- NOTHING EVER TRANSMITS IT. The scan request is TRP3's own MapScannersManager.launch
-- ("playerScan") broadcast, which knows nothing about a TRP3FW nonce; and TRP3FW's own scan
-- REPLY hook (hooks/trp3.lua) wraps TRP3's sendP2PMessage and forwards unpack(args) verbatim,
-- appending nothing. So no responder -- not even another TRP3FW user -- can echo a nonce back,
-- every reply lands in the "missing nonce" branch, and every cached entry has verified=false.
--
-- With the pref on, that means every scan reply is ignored and map checking fails SHUT. The
-- pref, its checkbox (ui/tabs/Security.lua) and `/trp3fw scanreply nonce` are all still
-- reachable, so gating on the raw pref anywhere is a live footgun. Every consumer must go
-- through this accessor instead.
--
-- Wiring the nonce up needs protocol cooperation (a handshake that tells the responder which
-- nonce to echo), which is a design decision, not a defect fix -- so the verification code is
-- left intact and merely inert, ready for that work.
function TRP3FW:IsScanNonceVerificationAvailable()
    return false
end

function TRP3FW:ShouldAlertOnPhase()
    local mode = TRP3FW.Prefs.phaseCheckMode
    return mode == "alert" or mode == "alert_block" or mode == "alert_ghost"
end

function TRP3FW:ShouldAlertOnMap()
    local mode = TRP3FW.Prefs.mapCheckMode
    return mode == "alert" or mode == "alert_block" or mode == "alert_ghost"
end

function TRP3FW:ShouldBlockOnPhase()
    local mode = TRP3FW.Prefs.phaseCheckMode
    return mode == "block" or mode == "ghost" or mode == "alert_block" or mode == "alert_ghost"
end

function TRP3FW:ShouldBlockOnMap()
    local mode = TRP3FW.Prefs.mapCheckMode
    return mode == "block" or mode == "ghost" or mode == "alert_block" or mode == "alert_ghost"
end

function TRP3FW:ShouldGhostOnPhase()
    local mode = TRP3FW.Prefs.phaseCheckMode
    return mode == "ghost" or mode == "alert_ghost"
end

function TRP3FW:ShouldGhostOnMap()
    local mode = TRP3FW.Prefs.mapCheckMode
    return mode == "ghost" or mode == "alert_ghost"
end

function TRP3FW:IsProfileSwitchOverrideActive()
    if not TRP3FW.Prefs.ghostProfileSwitch then
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
    local phaseGhost = (TRP3FW.Prefs.phaseCheckMode == "ghost" or TRP3FW.Prefs.phaseCheckMode == "alert_ghost")
    local mapGhost = (TRP3FW.Prefs.mapCheckMode == "ghost" or TRP3FW.Prefs.mapCheckMode == "alert_ghost")
    return phaseGhost or mapGhost or TRP3FW.Prefs.ghostOnStartPhase
end

-- Runtime state
-- Which RP addons/capabilities are present locally. Keyed by capability name:
-- TRP3 / MRP / XRP / MSP (booleans) and MapScanner (the string "TRP3"/"RPMapScan").
-- Written by hooks/installer.lua, read by status.lua, ui/, core/utils.lua, location/.
TRP3FW.detectedAddons = {}
-- Which RP addon a given REMOTE PLAYER is running, inferred from their MSP handshake.
-- Keyed by cleaned player name, values are "TRP3"/"MRP"/"XRP"/"MSP".
--
-- Deliberately separate from detectedAddons: these were one table, and the two keyspaces
-- collided on any player whose name happened to be a capability key. A player named
-- "MapScanner" set detectedAddons.MapScanner to a truthy value, so location/maps.lua:361
-- and location/cascading.lua:214 believed a map scanner existed when none did (and the
-- Status tab reported one). In the other direction, a send to a player named "MSP" read
-- back the installer's `detectedAddons.MSP = true` as that player's addon, putting a
-- BOOLEAN where a string was expected: HistoryService:TrackAddonRequest type-guards and
-- silently skips it, but NotificationService (:279, :506) formats it with "%s", which is a
-- hard error in Lua 5.1.
TRP3FW.playerAddonProtocol = {}
TRP3FW.playerAddonProtocolCount = 0
TRP3FW.PLAYER_ADDON_PROTOCOL_LIMIT = 500
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

-- How many recent samples each profiled name retains for percentile math. Held in a ring
-- buffer (see profiler.stop), so this is also the buffer's fixed size.
local PROFILER_SAMPLE_LIMIT = 1000

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
            calls = {},      -- Ring buffer of recent samples for percentile calculations
            callCursor = 0   -- Write position within `calls`
        }
    end

    local stats = TRP3FW.profiler.stats[name]
    stats.count = stats.count + 1
    stats.totalTime = stats.totalTime + elapsed
    stats.minTime = math.min(stats.minTime, elapsed)
    stats.maxTime = math.max(stats.maxTime, elapsed)

    -- Keep last 1000 calls for percentile calculations (FIFO; the previous random
    -- eviction biased P95/P99 toward older outliers).
    --
    -- RING BUFFER, not table.insert + table.remove(calls, 1). The old form shifted 1000
    -- elements on every single measurement once the buffer filled -- O(n) per sample, inside
    -- the profiler itself, which is the one place added overhead corrupts the thing being
    -- measured. Overwriting one slot is O(1). The only reader (profiler.report) copies the
    -- array and sorts it, so slot order is irrelevant.
    stats.callCursor = (stats.callCursor or 0) + 1
    if stats.callCursor > PROFILER_SAMPLE_LIMIT then stats.callCursor = 1 end
    stats.calls[stats.callCursor] = elapsed
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
    -- Debug() feeds both chat and the debug window buffer, so no direct AddDebugMessage here.
    self:Debug(formatted, "refactor")
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

-- [playerName] = timestamp. AlertFastPathStage's dedup markers: alert-only mode sits before
-- BurstStage, so a burst never queues and would otherwise start one location check per
-- request. Cleared by the cascading callback; swept by CacheService as a backstop.
TRP3FW.alertOnlyChecksInFlight = {}
TRP3FW.pendingSendId = 0

-- L3: legacy cache table proxies removed. All cache access goes through
-- TRP3FW.CacheInterface (O(1) LRU eviction). The deprecation-warning proxies
-- previously here are no longer referenced anywhere outside their own declaration.

-- (TRP3FW.cachedTime / cachedTimeFrame removed: the "frame cache" they backed read the clock
-- unconditionally before consulting itself, so it saved no syscalls and cost extra work on
-- every call. See TRP3FW:GetCurrentTime in core/utils.lua.)

-- OPTIMIZATION: Phase ID caching (eliminates redundant C_Epsilon.GetPhaseId() calls in ghost mode)
-- Phase changes are rare relative to profile sends, so cache with 1-second TTL
-- Reduces 4-8 API calls per ghost mode profile send to 1 call per second
TRP3FW.cachedPhaseID = nil
TRP3FW.cachedPhaseTimestamp = 0
TRP3FW.PHASE_CACHE_TTL = 1  -- Cache phase ID for 1 second (balance between freshness and performance)

-- Performance: Object pools for WHO query results (reduces GC pressure)
-- Removed pool (unused) - cache entries are created on demand

-- OPTIMIZATION: MSP conversion cache (eliminates redundant TRP3→MSP conversions in ghost mode)
-- TRP3 profile conversion is expensive (155 lines of string processing, table operations)
-- Cache persists for session (profiles rarely change during play session)
TRP3FW.mspConversionCache = {}  -- [profileID] = {mspFields, timestamp}

-- Ghost mode state: single active ghost flag to eliminate target ambiguity.
-- Shape: { target = "PlayerA", expires = time, addon, timestamp, profileID }
-- Consumed by ShouldGhostSendTo / EnableGhostForNextSend (features/ghostmode_trp3.lua).
TRP3FW.ghostNextSend = nil
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
TRP3FW.pendingPhaseInSends = {}  -- Queued Chomp sends during phase-in delay
TRP3FW.PHASE_IN_QUEUE_LIMIT = 200

-- Cap on BurstStage's per-player queue of requests waiting on an in-flight location check.
-- This was the one unbounded collection in the addon, against CLAUDE.md's stated rule that
-- every cache has a maxSize to prevent DoS. Bounded in practice by the check window (~2s via
-- cascading's deadline), but a hung check widens that to 30s -- and each entry retains a full
-- profile payload in originalArgs.
TRP3FW.BURST_QUEUE_LIMIT = 100
TRP3FW.burstQueueDrops = 0  -- Diagnostic counter; surfaced by /trp3fw stats

-- Original function references (for hooks)
TRP3FW.originalMSPSend = nil
TRP3FW.originalMSPReply = nil

function TRP3FW:GetCharacterKey()
    return UnitName("player") .. " - " .. GetRealmName()
end

function TRP3FW:MigrateSettings()
    -- Ensure Root DB exists
    TRP3FW_DB = TRP3FW_DB or {}
    TRP3FW_DB.profiles = TRP3FW_DB.profiles or {}
    TRP3FW_DB.profileKeys = TRP3FW_DB.profileKeys or {}
    TRP3FW_DB.global = TRP3FW_DB.global or { version = TRP3FW.VERSION }

    -- `version` previously recorded the INSTALL-time version forever: it was set once, in the
    -- table constructor above, and never written again. Nothing reads it today, but any future
    -- migration keyed off it would have read a stale value and concluded no migration was
    -- needed. Keep both halves, since they answer different questions:
    --   * lastVersion  - the version that last ran. This is what a migration should compare
    --                    against, and it is updated below AFTER migrations have had their
    --                    chance to see the old value.
    --   * firstVersion - the version that created this DB, preserved for diagnostics.
    local g = TRP3FW_DB.global
    g.firstVersion = g.firstVersion or g.version or TRP3FW.VERSION
    g.previousVersion = g.lastVersion or g.version  -- what the migrations below should read

    -- Check if we have legacy data to migrate
    -- TRP3FW_Settings (legacy global) might contain data if it was just loaded
    if TRP3FW_Settings and next(TRP3FW_Settings) and not TRP3FW_Settings.profiles then
        self:Debug("Migration: Found legacy flat settings. Migrating to 'Default' profile.", "init")

        -- Copy flat data to Default profile
        TRP3FW_DB.profiles["Default"] = CopyTable(TRP3FW_Settings)

        -- Wipe legacy container (to avoid double-saving or confusion)
        for k in pairs(TRP3FW_Settings) do TRP3FW_Settings[k] = nil end
    end

    -- Ensure at least one profile exists
    if not next(TRP3FW_DB.profiles) then
        TRP3FW_DB.profiles["Default"] = CopyTable(self.defaultSettings)
    end

    -- Stamp LAST, so anything above can still read `previousVersion` to detect an upgrade.
    -- `version` is kept in sync as the current version for anything already reading it.
    TRP3FW_DB.global.lastVersion = TRP3FW.VERSION
    TRP3FW_DB.global.version = TRP3FW.VERSION
end

-- Table-valued defaults must be copied, never aliased, when backfilled into a
-- profile -- see the comment in LoadProfile below.
local function copyDefault(value)
    if type(value) ~= "table" then return value end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = copyDefault(v)
    end
    return copy
end

function TRP3FW:LoadProfile(profileName)
    local db = TRP3FW_DB
    if not db.profiles[profileName] then
        self:Debug("Profile '" .. profileName .. "' not found. Falling back to 'Default'.", "init")
        profileName = "Default"
    end

    -- Point Prefs to the active profile table
    self.Prefs = db.profiles[profileName]

    -- Ensure all default keys exist in the profile.
    -- Table-valued defaults (ghostProfileOverrides, spvpPerPhaseOverrides) are copied
    -- rather than assigned: assigning shares one table between defaultSettings and every
    -- profile that backfills the key. Profiles saved before those settings existed all
    -- lack them, so upgrading users hit this on the first profile switch -- and the UI
    -- mutates these tables in place (ui/tabs/Alerts.lua writes ghostProfileOverrides
    -- element-by-element), so an override set on one profile showed up on all of them
    -- and on every profile later created from defaultSettings.
    for k, v in pairs(self.defaultSettings) do
        if self.Prefs[k] == nil then
            self.Prefs[k] = copyDefault(v)
        end
    end

    -- Update current character's key
    local charKey = self:GetCharacterKey()
    db.profileKeys[charKey] = profileName

    -- Store reference to Global DB
    TRP3FW.GlobalDB = db

    self:Debug("Loaded profile: " .. profileName, "init")
end

-- ===================== Cache Initialization =====================

function TRP3FW:InitializeCaches()
    local CI = TRP3FW.CacheInterface
    if not CI then
        TRP3FW:Error("CacheInterface not loaded!")
        return
    end

    -- Send Cache (Allowed Senders)
    CI:Register("allowedSenders", {
        ttl = TRP3FW.Prefs.sendCacheDuration,
        maxSize = 1000
    })

    -- Interaction Cache
    CI:Register("interaction", {
        ttl = TRP3FW.Prefs.interactionCacheDuration,
        maxSize = TRP3FW.Prefs.cacheSizeLimit or 1000
    })

    -- Phase Check Cache
    CI:Register("phaseCheck", {
        ttl = TRP3FW.Prefs.phaseCacheDuration,
        maxSize = TRP3FW.Prefs.cacheSizeLimit or 1000
    })

    -- WHO Name Cache
    CI:Register("whoName", {
        ttl = TRP3FW.Prefs.whoNameCacheDuration,
        maxSize = TRP3FW.Prefs.cacheSizeLimit or 1000
    })

    -- WHO Zone Cache
    CI:Register("whoZone", {
        ttl = TRP3FW.Prefs.whoZoneCacheDuration,
        maxSize = TRP3FW.Prefs.cacheSizeLimit or 1000
    })

    -- Map Scan Cache (recentScans)
    CI:Register("mapScan", {
        ttl = TRP3FW.Prefs.scanCacheDuration,
        maxSize = 1000
    })

    -- Broadcast Cache (recentBroadcasts)
    CI:Register("broadcast", {
        ttl = TRP3FW.Prefs.scanCacheDuration,
        maxSize = 1000
    })

    -- SPVP Verified Cache
    CI:Register("spvpVerified", {
        ttl = TRP3FW.Prefs.spvpVerifiedCacheDuration or 300,
        maxSize = 1000
    })

    -- SPVP Phase Salt Cache
    CI:Register("spvpPhaseSalt", {
        ttl = TRP3FW.Prefs.spvpSaltCacheDuration or 10800,
        maxSize = 500
    })

    -- SPVP Session Cache (replay-attack protection; short-lived)
    CI:Register("spvpSessions", {
        ttl = 60,
        maxSize = 1000
    })

    -- Name Normalization Caches (Utility)
    CI:Register("cleanName", {
        maxSize = TRP3FW.Prefs.cleanNameCacheSize or 500
    })
    CI:Register("sanitizedName", {
        maxSize = TRP3FW.Prefs.sanitizedNameCacheSize or 500
    })

    -- Map Name Cache
    CI:Register("mapName", {
        ttl = 3600, -- 1 hour
        maxSize = 200
    })

    TRP3FW:Debug("[Init] Core caches registered with CacheInterface", "cache")
end

-- Initialize settings
function TRP3FW:InitializeSettings()
    -- 1. Perform Migration
    self:MigrateSettings()

    -- 2. Identify active profile for current character
    local charKey = self:GetCharacterKey()
    local profileName = TRP3FW_DB.profileKeys[charKey] or "Default"

    -- 3. Load the profile
    self:LoadProfile(profileName)

    -- 4. Initialize Caches (Migrated from CacheService)
    self:InitializeCaches()

    -- 5. Set cache size constants
    TRP3FW.CLEAN_NAME_CACHE_MAX = self.Prefs.cleanNameCacheSize
    TRP3FW.SANITIZED_NAME_CACHE_MAX = self.Prefs.sanitizedNameCacheSize

    -- 6. Persistent global caches
    TRP3FW_ValidatedNames = TRP3FW_ValidatedNames or {}

    -- 7. SPVP Migration (from InitializeSettings)
    if self.hasEpsilonAPI and self.Prefs.spvpEnabled == false then
        if not self.Prefs.spvpExplicitlyDisabled then
            self.Prefs.spvpEnabled = true
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

    local function applyDependency(hasDependency, settings, dependencyName)
        for _, entry in ipairs(settings) do
            local key = entry.key
            local disableValue = entry.disableValue

            if not hasDependency then
                if self.Prefs[key] ~= disableValue then
                    -- Save the user's preference
                    self.savedSettings[key] = self.Prefs[key]
                    -- Temporarily disable
                    self.Prefs[key] = disableValue
                    self:Debug("Disabled "..key.." ("..dependencyName.." not available, saved: "..tostring(self.savedSettings[key])..")", "init")
                end
            else
                if self.savedSettings[key] ~= nil then
                    self.Prefs[key] = self.savedSettings[key]
                    self:Debug("Restored "..key.." to "..tostring(self.savedSettings[key]).." ("..dependencyName.." now available)", "init")
                    self.savedSettings[key] = nil
                end
            end
        end
    end

    applyDependency(self.hasEpsilonAPI, epsilonSettings, "Epsilon API")
end

-- Create main frame
TRP3FW.frame = CreateFrame("Frame", "TRP3FW_MainFrame")
