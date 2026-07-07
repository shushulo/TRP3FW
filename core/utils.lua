-- core/utils.lua
-- Utility functions for TRP3FW

local addonName, TRP3FW = ...

-- OPTIMIZATION: Count character occurrences without creating temporary strings
-- Replaces select(2, str:gsub(char, "")) which allocates a new string on every call
-- ~20-30% faster than gsub-based counting, zero string allocations
local function countChar(str, char)
	local count = 0
	local charByte = string.byte(char)
	for i = 1, #str do
		if string.byte(str, i) == charByte then
			count = count + 1
		end
	end
	return count
end

-- Constants for sanitization
local SANITIZE_ZONE_PATTERN = "^([%w%s'%-\128-\255]+)$"
local CONTROL_CHAR_PATTERN = "%z"
local CONTROL_CLASS_PATTERN = "%c"

-- Timestamp for debug messages
function TRP3FW:NowStamp()
    return TRP3FW.Prefs.debugTimestamp and date("[%H:%M:%S] ") or ""
end

-- Colored printing
function TRP3FW:PrintColored(level, msg)
    print(string.format("|cff%s[TRP3FW]|r %s%s", self.COLOR[level] or self.COLOR.white, self:NowStamp(), tostring(msg)))
end

function TRP3FW:Info(msg)
    self:PrintColored("info", msg)
end

function TRP3FW:Success(msg)
    self:PrintColored("info", msg)
end

function TRP3FW:Warn(msg)
    self:PrintColored("warn", msg)
end

function TRP3FW:Error(msg)
    self:PrintColored("err", msg)
end

-- Debug category to setting key mapping (for O(1) lookup instead of O(n) if-chain)
local DEBUG_CATEGORIES = {
    channel = "debugChannel",
    whisper = "debugWhisper",
    who = "debugWho",
    phase = "debugPhase",
    location = "debugLocation",
    decision = "debugDecision",
    hooks = "debugHooks",
    cache = "debugCache",
    send = "debugSend",
    ui = "debugUI",
    utils = "debugUtils",
    security = "debugSecurity",  -- Security-related messages (sanitization, cache limits, queue limits)
    ghost = "debugGhost",  -- Ghost mode execution flow and exchange hook calls
    spvp = "debugSPVP",  -- SPVP (Secure Phase Verification Protocol) handshake and verification
    cleanname = "debugCleanName",  -- Player name normalization (toggle was previously orphaned)
    -- Core infrastructure categories. Previously unmapped, so they bypassed the filter and
    -- printed unconditionally; route them through debugUtils so debugfilter can silence them.
    init = "debugUtils",
    core = "debugUtils",
    pipeline = "debugUtils",
    queue = "debugUtils",
    refactor = "debugUtils"
}

-- SECURITY: Redact sensitive information from debug messages
local function RedactSensitiveData(text)
    local service = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("SecurityService")
    if service then
        return service:RedactSensitiveData(text)
    end
    return text
end

-- Public redaction helper for any user-facing string
function TRP3FW:Redact(text)
    if type(text) ~= "string" then return text end
    return RedactSensitiveData(text)
end

-- OPTIMIZATION: Lazy evaluation for debug messages
-- SECURITY: Automatically redacts sensitive information (GUIDs, IPs, emails)
-- Supports both string and function arguments to eliminate string construction overhead when debug disabled
-- Usage:
--   TRP3FW:Debug("Simple message", "category")  -- String (backwards compatible)
--   TRP3FW:Debug(function() return "Expensive: "..complexCalculation() end, "category")  -- Function (lazy)
function TRP3FW:Debug(msg, category)
    if not TRP3FW.Prefs.debug then return end

    -- Check category filter if specified (optimized table lookup)
    if category then
        local settingKey = DEBUG_CATEGORIES[category]
        if settingKey and not TRP3FW.Prefs[settingKey] then return end
    end

    -- OPTIMIZATION: Lazy evaluation - only evaluate function if debug is actually enabled
    local debugMsg
    if type(msg) == "function" then
        -- Lazy evaluation: call function only when needed
        local success, result = pcall(msg)
        if success then
            debugMsg = "[DEBUG] "..tostring(result)
        else
            debugMsg = "[DEBUG] <Error evaluating debug message: "..tostring(result)..">"
        end
    else
        -- Backwards compatible: string message
        debugMsg = "[DEBUG] "..tostring(msg)
    end

    -- SECURITY: Redact sensitive information before output
    debugMsg = RedactSensitiveData(debugMsg)

    -- Determine output destination
    local outputToChat = TRP3FW.Prefs.debugOutputChat or TRP3FW.Prefs.debugOutputBoth
    local outputToWindow = TRP3FW.Prefs.debugOutputWindow or TRP3FW.Prefs.debugOutputBoth

    -- Output to chat if enabled
    if outputToChat then
        self:PrintColored("debug", debugMsg)
    end

    -- Output to debug window if enabled
    if outputToWindow and self.AddDebugMessage then
        self:AddDebugMessage(debugMsg, category)
    end
end

-- Time utilities
-- OPTIMIZATION: Cache monotonic time per frame (millisecond key) to avoid repeat syscalls in the same frame
-- Uses GetTimePreciseSec when available to stay monotonic and immune to system clock changes
function TRP3FW:GetCurrentTime()
    local now = (GetTimePreciseSec and GetTimePreciseSec() or GetTime())
    local frameStamp = math.floor(now * 1000)

    if TRP3FW.cachedTimeFrame ~= frameStamp then
        TRP3FW.cachedTime = now
        TRP3FW.cachedTimeFrame = frameStamp
    end

    return TRP3FW.cachedTime or now
end

function TRP3FW:FormatTime(s)
    if s < 60 then
        return s.."s"
    elseif s < 3600 then
        return string.format("%dm %ds", math.floor(s/60), s % 60)
    else
        return string.format("%dh %dm", math.floor(s/3600), math.floor((s % 3600)/60))
    end
end

-- Player name utilities
-- OPTIMIZATION: Delegated to SecurityService
function TRP3FW:CleanPlayerName(name)
    local service = self.ServiceContainer and self.ServiceContainer:Get("SecurityService")
    if service then
        return service:CleanPlayerName(name)
    end
    return nil
end

-- SECURITY: Sanitize player names for use in RunPrivileged() calls
-- Prevents command injection using STRICT WHITELIST validation
-- FIXED: CRITICAL-2 - Now uses whitelist instead of blacklist to prevent injection
-- OPTIMIZATION: Delegated to SecurityService
function TRP3FW:SanitizePlayerName(name)
    local service = self.ServiceContainer and self.ServiceContainer:Get("SecurityService")
    if service then
        return service:SanitizePlayerName(name)
    end
    return nil
end

-- SECURITY: Sanitize zone names for use in WHO queries and RunPrivileged() calls
-- Prevents command injection using STRICT WHITELIST validation
-- FIXED: CRITICAL-1 - Now uses whitelist to prevent all injection vectors
function TRP3FW:SanitizeZoneName(zone)
    if not zone or type(zone) ~= "string" then return nil end

    -- OPTIMIZATION: Fast-path combined check (single validation before expensive regex)
    -- Validates length + control chars in one cheap pass before pattern matching
    if #zone > 100 or #zone < 1 or zone:find("%c") then
        if #zone > 100 or #zone < 1 then
            self:Debug("[SECURITY] Rejected zone name with invalid length: "..#zone, "security")
        else
            self:Debug("[SECURITY] Rejected zone name with control characters", "security")
        end
        return nil
    end

    -- WHITELIST: Only allow alphanumeric, spaces, apostrophes, hyphens
    -- Pattern: ^[A-Za-z0-9 '\-]+$
    -- This blocks ALL special characters that could be used for injection
    -- Examples: "Stormwind City", "Dire Maul", "Ahn'Qiraj", "The Barrens"
    local sanitized = zone:match(SANITIZE_ZONE_PATTERN)

    if not sanitized or #sanitized == 0 then
        self:Debug("[SECURITY] Rejected malformed zone name: "..tostring(zone), "security")
        return nil
    end

    -- Additional validation: Prevent excessive apostrophes/hyphens (abuse prevention)
    local apostropheCount = countChar(sanitized, "'")
    local hyphenCount = countChar(sanitized, "-")

    if apostropheCount > 3 or hyphenCount > 3 then
        self:Debug("[SECURITY] Rejected zone name with excessive special chars: "..tostring(zone), "security")
        return nil
    end

    -- Prevent leading/trailing spaces or special chars
    sanitized = sanitized:match("^%s*(.-)%s*$")  -- Trim whitespace

    if #sanitized == 0 then
        self:Debug("[SECURITY] Rejected empty zone name after trimming", "security")
        return nil
    end

    if sanitized ~= zone then
        self:Debug("[SECURITY] Sanitized zone name: '"..zone.."' -> '"..sanitized.."'", "security")
    end

    return sanitized
end

-- ===================== Burst Queue Processing =====================

function TRP3FW:ProcessBurstQueue(queueName, playerName, processor)
    --[[
        Generic burst queue processor - processes all queued requests

        @param queueName string - Name of queue table (e.g., "trp3PendingSends")
        @param playerName string - Player to process queue for
        @param processor function - Function to call for each request
                                   Signature: processor(request)
    --]]

    local queue = self[queueName]
    if not queue or not queue[playerName] then
        return 0 -- No queue for this player
    end

    local requests = queue[playerName].queuedRequests or {}
    local count = #requests

    self:Debug(function()
        return string.format("[BurstQueue] Processing %d queued requests from %s (queue: %s)",
            count, playerName, queueName)
    end, "queue")

    for i, request in ipairs(requests) do
        local ok, err = pcall(processor, request)
        if not ok then
            self:Error("Error processing burst request "..i.."/"..count..": "..tostring(err))
        end
    end

    -- Clear queue for this player
    queue[playerName] = nil

    return count
end

local RATE_LIMIT = 10 -- Max tokens per second for RunPrivileged API

-- FileDataIDs of the sounds WoW plays when the target changes (select / lost). We mute
-- these FILES, and only while our automated phase-check targeting is in flight, so
-- manual targeting keeps its sound and no other SFX is affected.
--
-- TAINT NOTE: we do NOT wrap the global PlaySound (that taints Blizzard's secure
-- logout/exit path). MuteSoundFile is taint-free and file-scoped.
--
-- FileDataIDs confirmed on Epsilon 9.2.5 (identified with Leatrix Sounds +
-- MuteSoundFile). The trailing number in a sound path like
-- "sound/interface/iselecttarget.ogg#567453" is the FileDataID, which is what
-- MuteSoundFile takes. There is no in-game API to resolve a SOUNDKIT to its files, so
-- if a build/server plays a different file, use `/trp3fw soundids` to help locate it and
-- `/trp3fw soundadd <id>` to add it. Empty is safe (mute no-ops).
local TARGET_SELECT_SOUND_FILES = {
    567453,  -- sound/interface/iselecttarget.ogg   (target select)
    567520,  -- sound/interface/ideselecttarget.ogg (target deselect)
}

-- Candidate sound-kit NAMES used by the /trp3fw soundids discovery command to help
-- confirm/extend the file list above on servers whose IDs differ.
local TARGET_SELECT_SOUNDKIT_NAMES = {
    "IG_CREATURE_NEUTRAL_SELECT",
    "IG_CREATURE_AGGRO_SELECT",
    "IG_CREATURE_SPECIAL_SELECT",
    "IG_CHARACTER_NPC_SELECT",
}
TRP3FW.TARGET_SELECT_SOUNDKIT_NAMES = TARGET_SELECT_SOUNDKIT_NAMES

-- Prepare the target-select mute (once). No hooks, no global replacement — just seeds
-- the file list. Idempotent.
function TRP3FW:InstallTargetSoundMute()
    if self._targetSoundMuteInstalled then return end

    -- Files we mute during automated targeting: the built-in list plus any the user
    -- added via saved settings (TRP3FW_Settings.extraTargetSoundFiles).
    local files = {}
    for _, fid in ipairs(TARGET_SELECT_SOUND_FILES) do files[fid] = true end
    if self.Prefs and type(self.Prefs.extraTargetSoundFiles) == "table" then
        for _, fid in ipairs(self.Prefs.extraTargetSoundFiles) do
            if type(fid) == "number" then files[fid] = true end
        end
    end
    self.targetSoundFiles = files
    self.targetSoundFilesMuted = false

    self._targetSoundMuteInstalled = true
    self:Debug(function()
        local n = 0; for _ in pairs(files) do n = n + 1 end
        return "[Sound] Target-select mute ready ("..n.." files)"
    end, "utils")
end

-- Mute/unmute the target-select files. Called around automated targeting so the mute
-- is scoped to our windows and never silences manual target selection. Taint-free.
function TRP3FW:SetTargetSoundMuted(muted)
    if not self._targetSoundMuteInstalled then return end
    if type(MuteSoundFile) ~= "function" or type(UnmuteSoundFile) ~= "function" then return end
    if muted == self.targetSoundFilesMuted then return end
    self.targetSoundFilesMuted = muted
    for fid in pairs(self.targetSoundFiles) do
        if muted then MuteSoundFile(fid) else UnmuteSoundFile(fid) end
    end
end

-- SECURITY: Peek token bucket without consuming (mirrors RunPrivilegedSafe defaults)
function TRP3FW:GetAvailablePrivilegedTokens()
    if not self.privilegedRate then
        return RATE_LIMIT -- Default max if not initialized
    end

    local now = self:GetCurrentTime()
    local elapsed = now - self.privilegedRate.lastRefill
    local refill = elapsed * RATE_LIMIT
    local tokens = math.min(RATE_LIMIT, (self.privilegedRate.tokens or RATE_LIMIT) + refill)

    return tokens
end

-- ===================== Optimization #9: Three-Tier Priority System =====================

-- Validate settings to prevent impossible configurations and ensure safe defaults.
-- This function is called once at init, and if settings are changed.
local function ValidatePrioritySettings(privilegedReservedTokens, privilegedLowPriorityThreshold)
    local reserved = privilegedReservedTokens or 2
    local lowThreshold = privilegedLowPriorityThreshold or 4

    -- Clamp to valid ranges
    reserved = math.max(0, math.min(5, reserved))
    lowThreshold = math.max(2, math.min(8, lowThreshold))

    -- Ensure reserved + lowThreshold <= RATE_LIMIT. If not, auto-correct to safe defaults.
    if reserved + lowThreshold > RATE_LIMIT then
        TRP3FW:Debug(function()
            return "[PRIORITY] Invalid settings: reserved("..reserved..") + lowThreshold("..lowThreshold..") > "..RATE_LIMIT..". Auto-correcting to defaults (2 reserved, 4 lowThreshold)."
        end, "security")
        reserved = 2
        lowThreshold = 4
        -- Update settings if they were invalid (this happens on reload/init, not on every call)
        if TRP3FW.Prefs then
            TRP3FW.Prefs.privilegedReservedTokens = reserved
            TRP3FW.Prefs.privilegedLowPriorityThreshold = lowThreshold
        end
    end

    return reserved, lowThreshold
end

-- Initialize validated priority settings from TRP3FW.Prefs, or use default if not available yet.
-- These will be updated when TRP3FW.Prefs is fully loaded.
local RESERVED_TOKENS, LOW_PRIORITY_THRESHOLD = ValidatePrioritySettings(TRP3FW.Prefs and TRP3FW.Prefs.privilegedReservedTokens, TRP3FW.Prefs and TRP3FW.Prefs.privilegedLowPriorityThreshold)

-- Function to update the locally cached validated priority settings if they change at runtime
function TRP3FW:UpdateValidatedPrioritySettings()
    RESERVED_TOKENS, LOW_PRIORITY_THRESHOLD = ValidatePrioritySettings(TRP3FW.Prefs.privilegedReservedTokens, TRP3FW.Prefs.privilegedLowPriorityThreshold)
    TRP3FW:Debug(function()
        return "[PRIORITY] Updated validated settings: Reserved="..RESERVED_TOKENS..", LOW Threshold="..LOW_PRIORITY_THRESHOLD
    end, "security")
end

-- Numerical priority levels for sorting
local PRIORITY_LEVELS = {
    HIGH = 1,
    NORMAL = 2,
    LOW = 3
}

-- Configuration for each priority level, including categories they apply to
local PRIORITY_CONFIG = {
    HIGH = {
        canUseReserved = true,
        numericLevel = PRIORITY_LEVELS.HIGH,
        categories = {
            "phase_restore_target",         -- Restore target after phase check
            "phase_restore_target_by_name", -- Restore target by name after phase check
            "phase_clear_target",           -- Clear target after phase check
            "who_name_query",               -- Direct WHO name queries (player-initiated)
            "who_name_query_fallback",      -- WHO name queries (fallback from phase/map)
            "sync_request"                  -- High priority sync requests (e.g., critical data)
        }
    },
    NORMAL = {
        canUseReserved = false,
        numericLevel = PRIORITY_LEVELS.NORMAL,
        categories = {
            "phase_check_target",           -- Regular phase checks (player-initiated or direct)
            "who_zone_query",               -- Direct WHO zone queries
            "map_scan_init",                -- Initializing map scan
            "map_scan_query"                -- Querying map scan results
        }
    },
    LOW = {
        canUseReserved = false,
        numericLevel = PRIORITY_LEVELS.LOW,
        deferOnScarcity = true,
        scarcityThreshold = LOW_PRIORITY_THRESHOLD, -- Uses validated setting
        categories = {
            "phase_check_target_low",       -- Cache refresh for phase checks (Optimization #1)
            "who_zone_query_prepopulate",   -- Pre-population of WHO cache (Optimization #6)
            "cache_prune_background",       -- Background cache pruning (if RunPrivileged is ever used for it)
            "who_map_verification"          -- Low-priority verification of map ID when phase check succeeds
        }
    }
}

-- Helper function to get priority configuration for a given category
function TRP3FW:GetCategoryPriority(category)
    for pName, config in pairs(PRIORITY_CONFIG) do
        for _, cat in ipairs(config.categories) do
            if cat == category then
                return pName, config
            end
        end
    end
    -- Default to NORMAL if category not explicitly defined
    return "NORMAL", PRIORITY_CONFIG.NORMAL
end

-- OPTIMIZATION #5: Token Refund
-- Refund a token if a privileged call was "wasted" (e.g., phase check on non-existent player didn't change target).
-- SECURITY WARNING: This increases throughput for failed calls. Disabled by default.
function TRP3FW:RefundToken(category, amount)
    amount = amount or 1
    if not self.privilegedRate then return end

    local before = self.privilegedRate.tokens
    self.privilegedRate.tokens = math.min(RATE_LIMIT, self.privilegedRate.tokens + amount)
    local after = self.privilegedRate.tokens
    local actualRefund = after - before

    -- Track refund statistics
    if self.privilegedCallStats then
        self.privilegedCallStats.refunded = (self.privilegedCallStats.refunded or 0) + actualRefund
        if category then
            self.privilegedCallStats.refundedByCategory = self.privilegedCallStats.refundedByCategory or {}
            self.privilegedCallStats.refundedByCategory[category] = (self.privilegedCallStats.refundedByCategory[category] or 0) + actualRefund
        end
    end

    -- Debug logging (always logged to security category)
    if actualRefund > 0 then
        self:Debug(function()
            return "[Token Refund] Refunded "..actualRefund.." token(s) for "..tostring(category).." (tokens: "..string.format("%.1f", before).." -> "..string.format("%.1f", after)..")"
        end, "security")
    else
        -- Token bucket was already full, no refund occurred
        self:Debug(function()
            return "[Token Refund] Attempted refund for "..tostring(category).." but bucket already full ("..string.format("%.1f", before).."/"..RATE_LIMIT..")"
        end, "security")
    end
end

-- Returns true when the player has the armory/inspect window open. Automated
-- phase-check targeting retargets the player, which pulls inspect data out from
-- under InspectFrame, so callers skip targeting while this is true (gated by the
-- pausePhaseCheckOnInspect setting at the call sites).
function TRP3FW:IsInspectActive()
    local f = _G.InspectFrame
    return f ~= nil and f:IsShown()
end

-- SECURITY: Rate-limited wrapper for C_Epsilon.RunPrivileged() calls
-- FIXED: CRITICAL-3 - Prevents privilege escalation via flooding attacks
-- Enforces strict rate limit of 10 privileged calls per second using a token bucket.
-- OPTIMIZATION #9: Incorporates three-tier priority system with adaptive deferral for LOW priority.
function TRP3FW:RunPrivilegedSafe(code, category)
    if not self.hasEpsilonAPI then
        self:Debug(function() return "[SECURITY] RunPrivileged not available (Epsilon API missing, tried: "..tostring(category)..")" end, "security")
        return false, "api_unavailable"
    end

    if not code or type(code) ~= "string" then
        self:Debug(function() return "[SECURITY] RunPrivileged rejected: invalid code parameter (tried: "..tostring(category)..")" end, "security")
        return false, "invalid_code"
    end

    -- Validate code length (prevent oversized code injection)
    if #code > 1000 then
        self:Debug(function() return "[SECURITY] RunPrivileged rejected: code too long ("..#code.." chars) (tried: "..tostring(category)..")" end, "security")
        return false, "code_too_long"
    end

    local now = self:GetCurrentTime()  -- Monotonic for rate limiting

    -- Initialize counters if needed
    if not self.privilegedCallStats then
        self.privilegedCallStats = {
            total = 0,
            blocked = 0,
            errors = 0,
            byCategory = {},
            deferred = 0, -- OPTIMIZATION #9: Track deferred LOW priority calls
            refunded = 0, -- OPTIMIZATION #5: Track refunded tokens
            refundedByCategory = {} -- OPTIMIZATION #5: Track refunded tokens by category
        }
    end
    if not self.privilegedRate then
        self.privilegedRate = {
            tokens = RATE_LIMIT, -- Start with full bucket
            lastRefill = now,
        }
    end
    -- self.privilegedWindowStart/privilegedWindowCalls were for old debugging, replaced by category stats

    -- Token bucket refill (RATE_LIMIT tokens per second, cap at RATE_LIMIT)
    local elapsed = now - self.privilegedRate.lastRefill
    if elapsed > 0 then
        local refill = elapsed * RATE_LIMIT
        self.privilegedRate.tokens = math.min(RATE_LIMIT, self.privilegedRate.tokens + refill)
        self.privilegedRate.lastRefill = now
    end

    local pName, pConfig = self:GetCategoryPriority(category)

    -- Calculate truly available tokens based on priority
    local availableTokens = self.privilegedRate.tokens
    if not pConfig.canUseReserved then
        -- If this priority cannot use reserved tokens, subtract them from available
        availableTokens = availableTokens - RESERVED_TOKENS
    end

    -- OPTIMIZATION #9: LOW priority adaptive deferral when tokens are scarce
    if pConfig.deferOnScarcity and availableTokens < pConfig.scarcityThreshold then
        -- Calculate optimal wait time to reach scarcityThreshold tokens
        local tokensNeeded = pConfig.scarcityThreshold - availableTokens
        -- Ensure waitTime is not negative if availableTokens are somehow already above threshold
        -- Clamp to a minimum of 0.1s to avoid rapid-fire retries that could spam timers
        local waitTime = math.max(0.1, tokensNeeded / RATE_LIMIT)

        self:Debug(function()
            return "[PRIORITY - LOW] Deferring '"..category.."' for "..
                    string.format("%.2f", waitTime).."s (tokens: "..
                    string.format("%.1f", self.privilegedRate.tokens).."/"..RATE_LIMIT..
                    ", effective: "..string.format("%.1f", availableTokens).."/"..RATE_LIMIT..
                    ", threshold: "..pConfig.scarcityThreshold..")"
        end, "security")
        self.privilegedCallStats.deferred = self.privilegedCallStats.deferred + 1
        return false, "deferred_low_priority", waitTime
    end

    -- Enforce rate limit: Check if enough tokens are available for THIS priority level
    if availableTokens < 1 then
        self:Debug(function()
            return "[SECURITY] RunPrivileged RATE LIMIT EXCEEDED for category '"..category.."' ("..pName.."). Blocking call."..
                    " (Tokens: "..string.format("%.1f", self.privilegedRate.tokens).."/"..RATE_LIMIT..
                    ", Effective: "..string.format("%.1f", availableTokens).."/"..RATE_LIMIT..")"
        end, "security")
        self.privilegedCallStats.blocked = self.privilegedCallStats.blocked + 1
        return false, "rate_limit"
    end

    -- Consume token BEFORE call (prevent race conditions if API is async or re-entrant)
    self.privilegedRate.tokens = self.privilegedRate.tokens - 1
    self.privilegedCallStats.total = self.privilegedCallStats.total + 1

    -- Track by category for auditing
    if category then
        self.privilegedCallStats.byCategory[category] = (self.privilegedCallStats.byCategory[category] or 0) + 1
    end

    -- Execute privileged code with error handling.
    -- Automated phase-check targeting (TargetUnit/ClearTarget/restore) triggers WoW's
    -- "target acquired" sound. Suppression is handled surgically by the PlaySound hook
    -- (InstallTargetSoundMute), gated on the phaseCheckTargeting flag, so only OUR
    -- automated selects are silenced — manual targeting and all other SFX are untouched.
    local success, result = pcall(C_Epsilon.RunPrivileged, code)

    if not success then
        -- SECURITY: Do NOT log `code` here — it contains interpolated player/zone names
        -- (TargetUnit("Name"), z-"Zone") that the redaction layer does not scrub, partially
        -- defeating debug redaction. The category + error is enough to diagnose failures.
        self:Debug(function() return "[SECURITY] RunPrivileged FAILED for category '"..category.."': "..tostring(result) end, "security")
        self.privilegedCallStats.errors = self.privilegedCallStats.errors + 1
        return false, "execution_error"
    end

    self:Debug(function()
        return "[RunPrivileged] SUCCESS ("..pName.."): '"..category.."' (Tokens: "..string.format("%.1f", self.privilegedRate.tokens).."/"..RATE_LIMIT..")"
    end, "security")

    return true, result
end

-- SECURITY: Create verified sendId with HMAC-like signature
-- FIXED: HIGH-6 - Prevents sendId spoofing attacks
function TRP3FW:CreateVerifiedSendId()
    self.pendingSendId = (self.pendingSendId or 0) + 1
    local sendId = self.pendingSendId
    local timestamp = self:GetCurrentTime()

    -- Create signature: (sendId * 31 + timestamp * 17 + salt) % 1000000
    -- This creates a cheap HMAC-like verification without requiring crypto libraries
    local signature = (sendId * 31 + math.floor(timestamp * 100) * 17 + self.sendIdSalt) % 1000000

    return {
        id = sendId,
        timestamp = timestamp,
        signature = signature
    }
end

-- SECURITY: Verify sendId signature
-- FIXED: HIGH-6 - Validates sendId hasn't been spoofed
function TRP3FW:VerifySendId(sendIdObj)
    if type(sendIdObj) ~= "table" then
        self:Debug("[SECURITY] SendId verification failed: not a table", "security")
        return false
    end

    if not sendIdObj.id or not sendIdObj.timestamp or not sendIdObj.signature then
        self:Debug("[SECURITY] SendId verification failed: missing fields", "security")
        return false
    end

    -- Recalculate expected signature
    local expectedSig = (sendIdObj.id * 31 + math.floor(sendIdObj.timestamp * 100) * 17 + self.sendIdSalt) % 1000000

    local isValid = sendIdObj.signature == expectedSig
    if not isValid then
        self:Debug("[SECURITY] SendId verification FAILED: signature mismatch (expected "..expectedSig..", got "..sendIdObj.signature..")", "security")
    end

    return isValid
end

-- SECURITY: Validate configuration settings
-- FIXED: LOW-5 - Validates numeric ranges for all settings
function TRP3FW:ValidateSettings()
    if not TRP3FW.Prefs then return end

    -- M7: Bounds only. Defaults are pulled from `TRP3FW.defaultSettings` so there's a
    -- single source of truth — bad input now resets to the documented default rather
    -- than a separate (often stale) value local to this function.
    local numericSettings = {
        {name = "suppressionTime", min = 0, max = 3600},
        {name = "scanCacheDuration", min = 10, max = 600},
        {name = "sendCacheDuration", min = 60, max = 7200},
        {name = "phaseCacheDuration", min = 30, max = 600},
        {name = "whoZoneCacheDuration", min = 10, max = 300},
        {name = "whoNameCacheDuration", min = 10, max = 300},
        {name = "interactionCacheDuration", min = 30, max = 1800},
        {name = "cacheSizeLimit", min = 50, max = 10000},
        {name = "whoQueueLimit", min = 10, max = 500},
        {name = "interactionRefreshRate", min = 0, max = 100},
        {name = "sendCacheRefreshRate", min = 0, max = 100},
        {name = "whoCacheRefreshThreshold", min = 0, max = 100},
        {name = "phaseRefreshCooldown", min = 0, max = 300},
        {name = "statusRefreshRate", min = 2, max = 120},
        {name = "validatedNamesCacheDuration", min = 86400, max = 2592000}, -- 1-30 days (in seconds)
        {name = "validatedNamesCacheLimit", min = 500, max = 10000},        -- 500-10000 entries
    }

    local defaults = TRP3FW.defaultSettings or {}
    for _, setting in ipairs(numericSettings) do
        local value = TRP3FW.Prefs[setting.name]
        if type(value) ~= "number" or value < setting.min or value > setting.max then
            local fallback = defaults[setting.name]
            if type(fallback) ~= "number" then
                -- Last-ditch fallback if defaults table is missing this entry: clamp to range.
                fallback = setting.min
            end
            self:Debug("[SECURITY] Invalid "..setting.name..": "..tostring(value)..", resetting to "..tostring(fallback), "security")
            TRP3FW.Prefs[setting.name] = fallback
        end
    end
end

-- Whitelist helpers ---------------------------------------------------------
function TRP3FW:RefreshWhitelistCache()
    self.whitelistCache = {}
    local rawEntries = (TRP3FW.Prefs and TRP3FW.Prefs.whitelistEntries) or ""
    if type(rawEntries) ~= "string" then
        rawEntries = ""
    end
    self.whitelistCacheRaw = rawEntries

    if not TRP3FW.Prefs or not TRP3FW.Prefs.whitelistEnabled then
        return
    end

    local count = 0
    for line in string.gmatch(self.whitelistCacheRaw or "", "[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            local clean = self:SanitizePlayerName(trimmed) or self:CleanPlayerName(trimmed)
            if clean then
                self.whitelistCache[clean:lower()] = true
                count = count + 1
            else
                self:Debug("[Whitelist] Ignored invalid whitelist entry: "..tostring(trimmed), "security")
            end
        end
    end

    self:Debug("[Whitelist] Parsed "..count.." whitelist entries", "security")
end

function TRP3FW:IsPlayerWhitelisted(playerName)
    if not TRP3FW.Prefs or not TRP3FW.Prefs.whitelistEnabled then
        return false
    end

    local clean = self:SanitizePlayerName(playerName) or self:CleanPlayerName(playerName)
    if not clean then
        return false
    end

    local raw = (type(TRP3FW.Prefs.whitelistEntries) == "string") and TRP3FW.Prefs.whitelistEntries or ""
    if (not self.whitelistCache) or (raw ~= self.whitelistCacheRaw) then
        self:RefreshWhitelistCache()
    end

    local isListed = self.whitelistCache and self.whitelistCache[clean:lower()] or false
    if isListed then
        self:Debug("[Whitelist] "..clean.." is whitelisted - bypassing protections", "security")
    end

    return isListed
end

-- OPTIMIZATION: Get cached phase ID (eliminates redundant C_Epsilon.GetPhaseId() API calls)
-- Phase ID is cached with 1-second TTL to balance freshness with performance
-- Reduces 4-8 API calls per ghost mode profile send to 1 call per second max
function TRP3FW:GetCachedPhaseID()
    if not self.hasEpsilonAPI then
        return nil
    end

    local now = time()  -- Use time() for wall-clock cache expiry (not GetTime() which freezes when AFK)

    -- Check if cache is valid
    if not self.cachedPhaseID or (now - self.cachedPhaseTimestamp) > self.PHASE_CACHE_TTL then
        -- Cache miss or expired - fetch fresh phase ID
        self.cachedPhaseID = tonumber(C_Epsilon.GetPhaseId())
        self.cachedPhaseTimestamp = now
        self:Debug("[Phase Cache] Cache MISS - fetched fresh phase ID: "..tostring(self.cachedPhaseID), "cache")
    else
        -- Cache hit
        local age = now - self.cachedPhaseTimestamp
        self:Debug("[Phase Cache] Cache HIT - age: "..string.format("%.3f", age).."s, phase ID: "..tostring(self.cachedPhaseID), "cache")
    end

    return self.cachedPhaseID
end

-- ShouldBlockForStartPhase moved to features/ghostmode.lua in Phase 7


-- Addon utilities
function TRP3FW:GetAddonColor(addon)
    local colors = {
        TRP3 = "ff6600",
        MRP  = "00ccff",
        XRP  = "ff00ff",
        MSP  = "ffff00",
        RPMapScan = "00ff99"
    }
    return colors[addon] or self.COLOR.white
end

function TRP3FW:GetAddonName(addon)
    local names = {
        TRP3 = "TotalRP3",
        MRP  = "MyRolePlay",
        XRP  = "XRP",
        MSP  = "MSP",
        RPMapScan = "RP Map Scanner"
    }
    return names[addon] or addon
end

-- Status display helpers
function TRP3FW:EnabledDisabled(val)
    return val and "|cff00ff00Enabled|r" or "|cffaaaaaaDisabled|r"
end

function TRP3FW:OnOff(val)
    return val and "|cff00ff00On|r" or "|cffaaaaaaOff|r"
end

function TRP3FW:GetDetectedAddonsString()
    local addons = {}
    if self.detectedAddons.TRP3 then self.tinsert(addons, "TRP3") end
    if self.detectedAddons.MRP then self.tinsert(addons, "MRP") end
    if self.detectedAddons.XRP then self.tinsert(addons, "XRP") end
    if self.detectedAddons.MSP then self.tinsert(addons, "MSP") end
    return #addons > 0 and table.concat(addons, ", ") or "None"
end

-- Gradient removal functions
function TRP3FW:StripAllColorCodes(text)
    if not text or type(text) ~= "string" then
        return text
    end

    -- OPTIMIZATION: Reduce from 6 regex passes to 3 passes (still optimized, but more accurate)
    -- FIX: Previous pattern used %x?%x? which would consume text characters that are valid hex (A-F)
    -- Now using separate patterns for exact digit counts to prevent over-matching

    -- Pass 1: Strip complete color codes (|cXXXXXXXX....|r) - handles all color+content+reset combinations
    -- This covers three WoW color code formats:
    text = text:gsub("|c f%x%x%x%x%x%x(.-)|r", "%1")  -- Gradient: |c fRRGGBB (space + literal f + 6 hex)
    text = text:gsub("|c%x%x%x%x%x%x%x%x(.-)|r", "%1")  -- Standard with alpha: |cAARRGGBB (8 hex)
    text = text:gsub("|c%x%x%x%x%x%x(.-)|r", "%1")      -- Standard no alpha: |cRRGGBB (6 hex)

    -- Pass 2: Clean up all orphaned/malformed codes (no |r closing tag)
    text = text:gsub("|c f%x%x%x%x%x%x", "")  -- Orphaned gradient prefix
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")  -- Orphaned 8-digit
    text = text:gsub("|c%x%x%x%x%x%x", "")      -- Orphaned 6-digit

    -- Pass 3: Clean up orphaned reset tags
    text = text:gsub("|r", "")

    return text
end

-- Icon removal functions
function TRP3FW:StripAllIcons(text)
    if not text or type(text) ~= "string" then
        return text
    end

    -- Strip WoW texture tags: |Tpath:size...|t
    -- Pattern matches: |T (or |t) followed by anything until |t (or |T)
    -- Non-greedy match (.-) ensures we don't consume multiple icons as one
    text = text:gsub("|[Tt].-|[Tt]", "")

    return text
end

-- OPTIMIZATION: Helper function to count table entries efficiently
function TRP3FW:CountTableEntries(tbl)
    if not tbl or type(tbl) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

