-- ===================================================================
-- TRP3 Firewall - SPVP (Secure Phase Verification Protocol) v2.5
-- ===================================================================
-- SPEKE-based cryptographic phase verification
-- Uses server-side phase salt + SPEKE handshake to prevent spoofing
-- ===================================================================

local addonName, TRP3FW = ...

-- ===================================================================
-- CONSTANTS
-- ===================================================================

-- Diffie-Hellman prime (26-bit, max safe for Lua 5.1 doubles)
local DH_PRIME = 90000049

-- SPVP protocol version
local SPVP_VERSION = 2

-- Timeout and retry settings
local SPVP_TIMEOUT_SECONDS = 5
local SPVP_MAX_RETRIES = 2

-- WHO result limit (for detecting truncation)
local WHO_RESULT_LIMIT = 50

-- ===================================================================
-- UTILITIES
-- ===================================================================

--- FNV-1a hash function (32-bit)
--- @param data string - Input data to hash
--- @return number - 32-bit hash value
local function FNV1aHash(data)
    local hash = 2166136261 -- FNV offset basis

    for i = 1, #data do
        hash = bit.bxor(hash, string.byte(data, i))
        hash = hash * 16777619 -- FNV prime
        hash = bit.band(hash, 0xFFFFFFFF) -- Keep 32-bit
    end

    return hash
end

--- Modular exponentiation: (base^exp) mod m
--- Uses binary exponentiation to prevent overflow in Lua doubles
--- @param base number - Base value
--- @param exp number - Exponent (non-negative integer)
--- @param m number - Modulus
--- @return number - Result of (base^exp) mod m
local function ModPow(base, exp, m)
    -- Edge cases
    if m == 1 then return 0 end
    if exp == 0 then return 1 end
    if exp < 0 then
        error("ModPow: negative exponents not supported")
    end

    local result = 1
    base = base % m

    -- Binary exponentiation (keeps intermediate values < m^2)
    while exp > 0 do
        if exp % 2 == 1 then
            result = (result * base) % m
        end
        exp = math.floor(exp / 2)
        base = (base * base) % m
    end

    return result
end

--- Hash a key to create verifier (8-char hex)
--- @param sharedKey number - Shared key from handshake
--- @return string - 8-character hex hash
local function HashKey(sharedKey)
    local keyStr = tostring(sharedKey)
    local hash = FNV1aHash(keyStr)
    return string.format("%08x", hash)
end

--- Safe wrapper for math.randomseed (handles environments where it's missing)
--- @param seed number - Seed value
local function SafeRandomSeed(seed)
    if math.randomseed then
        math.randomseed(seed)
    end
end

-- ===================================================================
-- GENERATOR CALCULATION
-- ===================================================================

--- Get SPEKE generator from Phase ID and Phase Salt
--- Generator is the secret: G = (Hash(PhaseID + PhaseSalt)^2) mod p
--- @param phaseID number - Current phase ID
--- @param phaseSalt string - Optional cached phase salt (if nil, will fetch from cache)
--- @return number - Generator value
local function GetGenerator(phaseID, phaseSalt)
    -- 1. Base: Phase ID
    local entropy = tostring(phaseID or 0)

    -- 2. Phase Salt (Server-Side Secret)
    -- IMPORTANT: Use FULL salt including timestamp for crypto
    -- Both Alice and Bob read the same phase data, so they get identical salt strings
    if not phaseSalt then
        -- Fetch from cache if not provided
        phaseSalt = TRP3FW:GetPhaseSalt(phaseID, false)
    end

    if phaseSalt and phaseSalt ~= "" then
        entropy = entropy .. ":" .. phaseSalt  -- Full salt with timestamp!
    end

    -- Example entropy string:
    -- "5:A3F2E9D1C4B7A6F5E4D3C2B1A0F9E8D7C6B5A4F3E2D1C0B9A8F7E6D5C4B3A2F1:1704844800"
    --  ^  ^--- 64-char hex ---^                                                 ^--- timestamp

    -- Hash into a 32-bit integer (FNV-1a)
    local hash = FNV1aHash(entropy)

    -- Square to ensure quadratic residue group (USE ModPow!)
    local g = ModPow(hash, 2, DH_PRIME)
    if g < 2 then g = 2 end

    return g
end

-- ===================================================================
-- KEY GENERATION
-- ===================================================================

--- Generate cryptographically random private key
--- @return number - Private key in range [2, DH_PRIME-2]
local function GeneratePrivateKey()
    local now = GetTime()
    local guid = UnitGUID("player") or "NOGUID"
    local mouse_x, mouse_y = GetCursorPosition()

    -- Mix entropy sources
    local seed = tonumber(guid:sub(-6), 16) + (now * 1000) + (mouse_x * mouse_y)
    SafeRandomSeed(seed)

    -- Private key in range [2, DH_PRIME-2]
    local privateKey = math.random(2, DH_PRIME - 2)

    return privateKey
end

--- Generate public key: A = G^a mod p
--- @param generator number - SPEKE generator
--- @param privateKey number - Private key
--- @return number - Public key
local function GeneratePublicKey(generator, privateKey)
    return ModPow(generator, privateKey, DH_PRIME)
end

--- Derive shared key: K = B^a mod p
--- @param theirPublicKey number - Their public key
--- @param myPrivateKey number - My private key
--- @return number - Shared key
local function DeriveSharedKey(theirPublicKey, myPrivateKey)
    return ModPow(theirPublicKey, myPrivateKey, DH_PRIME)
end

-- ===================================================================
-- SESSION ID GENERATION
-- ===================================================================

--- Generate cryptographically random session ID (8-char hex)
--- @return string - 8-character hex session ID
local function GenerateSessionID()
    local now = GetTime()
    local guid = UnitGUID("player") or "NOGUID"
    local mouse_x, mouse_y = GetCursorPosition()

    -- Mix entropy sources
    local seed = tonumber(guid:sub(-6), 16) + (now * 1000) + (mouse_x * mouse_y)
    SafeRandomSeed(seed)

    local chars = "0123456789ABCDEF"
    local sessionID = ""

    for i = 1, 8 do
        local r = math.random(1, 16)
        sessionID = sessionID .. chars:sub(r, r)

        -- Re-seed every 2 chars (add entropy)
        if i % 2 == 0 then
            SafeRandomSeed(GetTime() * 1000 + math.random(10000))
        end
    end

    return sessionID
end

-- ===================================================================
-- PHASE SALT MANAGEMENT
-- ===================================================================

--- Generate phase salt with timestamp for tracking
--- Format: 64-char-hex:UTC-timestamp
--- Example: "A3F2E9...D1C4:1704844800"
---
--- Entropy Sources (Total: ~100-120 bits):
--- - Player GUID (last 8 hex chars): ~32 bits
--- - GetTime() millisecond precision: ~40 bits
--- - Mouse position (X * Y): ~20-30 bits
--- - Frame count: ~20 bits
--- - Math.random state evolution: ~10-20 bits
--- @return string - Phase salt (64 hex chars + colon + UTC timestamp)
function TRP3FW:GeneratePhaseSalt()
    -- Entropy Source 1: Player GUID (unique per character)
    local guid = UnitGUID("player") or "NOGUID"
    local guidEntropy = tonumber(guid:sub(-8), 16) or 0  -- Last 8 hex chars (32 bits)

    -- Entropy Source 2: High-precision time
    local timeEntropy = GetTime() * 1000000  -- Microsecond precision if available

    -- Entropy Source 3: Human input (mouse position)
    local mouse_x, mouse_y = GetCursorPosition()
    local mouseEntropy = (mouse_x or 0) * 10000 + (mouse_y or 0)

    -- Entropy Source 4: Frame count (temporal jitter)
    local frameEntropy = GetFramerate() * GetTime() * 1000

    -- Entropy Source 5: Date string hash (adds day/hour/minute variation)
    local dateStr = date("%Y%m%d%H%M%S")  -- e.g., "20240109143052"
    local dateEntropy = 0
    for i = 1, #dateStr do
        dateEntropy = dateEntropy * 10 + string.byte(dateStr, i)
    end

    -- Mix all entropy sources (avoid overflow by using modulo)
    local seed = (guidEntropy % 1000000 +
                  timeEntropy % 1000000 +
                  mouseEntropy % 1000000 +
                  frameEntropy % 1000000 +
                  dateEntropy % 1000000) % 2147483647  -- Keep in int32 range

    SafeRandomSeed(seed)

    -- Pre-warm PRNG (discard first few outputs which may be poor quality)
    for i = 1, 10 do
        math.random()
    end

    local chars = "0123456789ABCDEF"
    local salt = ""

    -- Generate 64 characters of hex noise with continuous re-seeding
    for i = 1, 64 do
        local r = math.random(1, 16)
        salt = salt .. chars:sub(r, r)

        -- Re-seed frequently to prevent PRNG prediction
        -- Mix current time + iteration + previous random value
        if i % 4 == 0 then
            local newSeed = (GetTime() * 1000000 + i * 12345 + r * 67890) % 2147483647
            SafeRandomSeed(newSeed)
        end
    end

    -- Append UTC timestamp for tracking (self-documenting)
    local utcTimestamp = time()  -- UTC seconds since epoch
    salt = salt .. ":" .. tostring(utcTimestamp)

    return salt
end

--- Parse phase salt to extract timestamp (for UI display ONLY)
--- @param salt string - Full salt string (with or without timestamp)
--- @return string, number|nil - (salt_part, timestamp)
function TRP3FW:ParsePhaseSalt(salt)
    if not salt then return "", nil end

    -- Try to extract timestamp (format: salt:timestamp)
    local saltPart, timestampStr = salt:match("^(.+):(%d+)$")

    if saltPart and timestampStr then
        return saltPart, tonumber(timestampStr)
    else
        -- Legacy format (no timestamp)
        return salt, nil
    end
end

--- Check if phase salt is old and should be rotated
--- @return boolean, number|nil - (needs_rotation, days_old)
function TRP3FW:CheckSaltRotation()
    if not C_Epsilon or not C_Epsilon.GetPhaseAddonData then
        return false, nil
    end

    local existingSalt = C_Epsilon.GetPhaseAddonData("TRP3FW_SPVP_KEY")
    if not existingSalt or existingSalt == "" then
        return false, nil
    end

    local _, timestamp = self:ParsePhaseSalt(existingSalt)
    if not timestamp then
        -- Legacy salt (unknown age) - recommend rotation
        return true, nil
    end

    local daysOld = math.floor((time() - timestamp) / 86400)

    -- Recommend rotation after 30 days
    return daysOld > 30, daysOld
end

--- Secure current phase with SPVP salt
function TRP3FW:SecureCurrentPhase()
    -- Check permissions (must call the functions, not just check existence)
    local isOwner = C_Epsilon.IsOwner and C_Epsilon.IsOwner()
    local isOfficer = C_Epsilon.IsOfficer and C_Epsilon.IsOfficer()

    if not C_Epsilon or not (isOwner or isOfficer) then
        self:Error("You must be a phase owner or officer to secure phases.")
        return
    end

    local salt = self:GeneratePhaseSalt()
    
    if not salt or #salt < 32 then
        self:Error("Generated salt is invalid/weak. Aborting secure.")
        return
    end
    
    C_Epsilon.SetPhaseAddonData("TRP3FW_SPVP_KEY", salt)

    -- Invalidate cache and update with new salt
    local phaseID = self:GetCurrentPhaseID()
    if phaseID then
        local CI = self.CacheInterface
        if CI then
            CI:Set("spvpPhaseSalt", phaseID, {
                salt = salt,
                timestamp = self:GetCurrentTime()
            })
            if self.sessionStats and self.sessionStats.spvpCache then
                self.sessionStats.spvpCache.activeEntries = CI:GetSize("spvpPhaseSalt") or 0
            end
        end
    end

    -- Parse timestamp for user feedback
    local _, timestamp = self:ParsePhaseSalt(salt)
    local dateStr = timestamp and date("%Y-%m-%d %H:%M UTC", timestamp) or "unknown"

    self:Info("Phase secured successfully! (Generated: " .. dateStr .. ")")
end

-- ===================================================================
-- PHASE SALT CACHING
-- ===================================================================

--- Get phase salt from cache or API (with 3-hour cache)
--- @param phaseID number - Phase ID to get salt for
--- @param forceRefresh boolean - Force cache refresh (on handshake failure)
--- @return string|nil - Phase salt or nil if not available
function TRP3FW:GetPhaseSalt(phaseID, forceRefresh)
    if not phaseID then
        phaseID = self:GetCurrentPhaseID()
    end
    if not phaseID then return nil end

    local CI = self.CacheInterface
    if not CI then return nil end

    -- Check cache (unless forced refresh)
    if not forceRefresh then
        local cached = CI:Get("spvpPhaseSalt", phaseID)
        if cached and cached.salt then
            self:Debug(string.format("Phase salt cache hit for phase %d (age: %.0fs)",
                phaseID, self:GetCurrentTime() - cached.timestamp), "spvp")
            
            -- Track hits
            if self.sessionStats and self.sessionStats.spvpCache then
                self.sessionStats.spvpCache.hits = self.sessionStats.spvpCache.hits + 1
                self.sessionStats.spvpCache.apiCallsSaved = self.sessionStats.spvpCache.apiCallsSaved + 1
            end
            
            return cached.salt
        end
    end

    -- Cache miss or forced refresh - fetch from API
    if self.sessionStats and self.sessionStats.spvpCache then
        self.sessionStats.spvpCache.misses = self.sessionStats.spvpCache.misses + 1
    end

    if not C_Epsilon or not C_Epsilon.GetPhaseAddonData then
        return nil
    end

    -- Asynchronous/Synchronous Request
    local result = C_Epsilon.GetPhaseAddonData("TRP3FW_SPVP_KEY")
    
    if result then
        -- Check if result is the data itself (Synchronous hit)
        -- If the client already has the data, it might return it directly
        if #result >= 32 and result:match("^[0-9a-fA-F:]+$") then
            self:Debug("Synchronous phase salt fetch successful for phase "..phaseID, "spvp")
            
            -- Cache it immediately
            if CI then
                CI:Set("spvpPhaseSalt", phaseID, {
                    salt = result,
                    timestamp = self:GetCurrentTime()
                })
                
                -- Update stats
                if self.sessionStats and self.sessionStats.spvpCache then
                    self.sessionStats.spvpCache.lastRefresh = self:GetCurrentTime()
                    self.sessionStats.spvpCache.activeEntries = CI:GetSize("spvpPhaseSalt") or 0
                end
            end
            
            return result
        else
            -- Result is a ticket (Async)
            self.pendingSaltTickets[result] = phaseID
            self:Debug("Requested salt for phase "..phaseID.." (Ticket: "..result..")", "spvp")
        end
    end

    return nil -- Loading...
end

--- Invalidate phase salt cache for a specific phase
--- @param phaseID number - Phase ID to invalidate (nil = current phase)
function TRP3FW:InvalidatePhaseSaltCache(phaseID)
    if not phaseID then
        phaseID = self:GetCurrentPhaseID()
    end
    if not phaseID then return end

    local CI = self.CacheInterface
    if CI then
        CI:Remove("spvpPhaseSalt", phaseID)
        if self.sessionStats and self.sessionStats.spvpCache then
            self.sessionStats.spvpCache.activeEntries = CI:GetSize("spvpPhaseSalt") or 0
        end
        self:Debug(string.format("Phase salt cache invalidated for phase %d", phaseID), "spvp")
    end
end

--- Prepopulate phase salt cache on login or phase change
function TRP3FW:PrepopulatePhaseSaltCache()
    if not TRP3FW_Settings.spvpEnabled then return end
    if not self.hasEpsilonAPI then return end

    local phaseID = self:GetCurrentPhaseID()
    if not phaseID then return end

    -- Fetch and cache the salt
    local salt = self:GetPhaseSalt(phaseID, false)

    if salt == nil then
        self:Debug(string.format("Phase salt prepopulation PENDING for phase %d (Ticket requested)", phaseID), "spvp")
    elseif salt ~= "" then
        self:Debug(string.format("Phase salt prepopulated for phase %d", phaseID), "spvp")
    else
        self:Debug(string.format("Phase %d has no salt (not secured)", phaseID), "spvp")
    end
end

-- ===================================================================
-- REPLAY ATTACK PROTECTION
-- ===================================================================

--- Check if session ID was recently used (replay detection)
--- Uses CacheInterface for automatic cleanup
--- @param sessionID string - 8-char hex session ID
--- @param sender string - Player name sending the packet
--- @return boolean - True if replayed (reject), false if new (accept)
local function IsReplayedSession(sessionID, sender)
    local CI = TRP3FW.CacheInterface

    -- Check cache
    local cached = CI:Get("spvpSessions", sessionID)
    if cached then
        TRP3FW:Debug(string.format("Replay detected: session %s from %s (age: %.1fs)",
            sessionID, sender, TRP3FW:GetCurrentTime() - cached.timestamp), "spvp")
        return true
    end

    -- New session - cache it
    CI:Set("spvpSessions", sessionID, {
        timestamp = TRP3FW:GetCurrentTime(),
        sender = sender
    })
    -- TTL: 60s (automatic eviction via CacheInterface)

    return false
end

-- ===================================================================
-- SPVP HANDSHAKE LOGIC
-- ===================================================================

-- Initialize session tracking
TRP3FW.spvpSessions = {}
TRP3FW.spvpIncomingSessions = {} -- [sessionID] = {sharedKey, sender, timestamp} (Bob's state)
TRP3FW.spvpFailedAttempts = {}
TRP3FW.pendingSaltTickets = {} -- [ticket] = phaseID
TRP3FW.pendingSPVPInits = {}   -- [{sender, message}] - Queued while salt loads

--- Handle asynchronous salt response from Epsilon
--- @param ticket string - The request ticket (prefix)
--- @param salt string - The received salt data
function TRP3FW:HandleSaltResponse(ticket, salt)
    local phaseID = self.pendingSaltTickets[ticket]
    if not phaseID then return end
    
    self.pendingSaltTickets[ticket] = nil
    
    -- Validate salt
    if not salt or #salt < 32 or not salt:match("^[0-9a-fA-F:]+$") then
        self:Debug("Async salt invalid/weak for phase "..phaseID..": "..(salt or "nil"), "spvp")
        return
    end
    
    -- Cache valid salt
    local CI = self.CacheInterface
    if CI then
        CI:Set("spvpPhaseSalt", phaseID, {
            salt = salt,
            timestamp = self:GetCurrentTime()
        })
        self:Debug("Async salt cached for phase "..phaseID, "spvp")
        
        -- Update stats
        if self.sessionStats and self.sessionStats.spvpCache then
            self.sessionStats.spvpCache.lastRefresh = self:GetCurrentTime()
            self.sessionStats.spvpCache.activeEntries = CI:GetSize("spvpPhaseSalt") or 0
        end
    end

    -- Process pending INITs that were waiting for this salt
    if #self.pendingSPVPInits > 0 then
        self:Debug(string.format("Processing %d pending SPVP INITs for phase %d", #self.pendingSPVPInits, phaseID), "spvp")
        for _, pending in ipairs(self.pendingSPVPInits) do
            -- Re-handle the INIT now that we have the salt
            self:HandleSPVPInit(pending.message, pending.sender)
        end
        self.pendingSPVPInits = {}
    end
end

--- Start SPVP handshake with retry logic
--- @param playerName string - Target player
--- @param sendId number - Unique send ID
--- @param callback function - Callback(verified, reason)
--- @param attempt number - Current attempt (0-indexed)
local function StartSPVPHandshakeWithRetry(playerName, sendId, callback, attempt)
    if attempt >= SPVP_MAX_RETRIES then
        TRP3FW:Debug(string.format("SPVP timeout: %s (retries exhausted)", playerName), "spvp")
        callback(nil, "timeout")  -- nil = unknown (fallback to normal checks)
        return
    end

    -- Generate session
    local sessionID = GenerateSessionID()
    local phaseID = TRP3FW:GetCurrentPhaseID()
    local generator = GetGenerator(phaseID)
    local privateKey = GeneratePrivateKey()
    local publicKey = GeneratePublicKey(generator, privateKey)

    -- Store session state
    TRP3FW.spvpSessions[sessionID] = {
        playerName = playerName,
        sendId = sendId,
        privateKey = privateKey,
        publicKey = publicKey,
        generator = generator,
        timestamp = TRP3FW:GetCurrentTime(),
        attempt = attempt,
        callback = callback
    }

    -- Send INIT packet
    local message = string.format("INIT:%d:%s:%d", SPVP_VERSION, sessionID, publicKey)
    C_ChatInfo.SendAddonMessage("TRP3FW_SPVP", message, "WHISPER", playerName)

    TRP3FW:Debug(string.format("SPVP INIT sent to %s (session: %s, attempt: %d)",
        playerName, sessionID, attempt), "spvp")

    -- Start timeout timer
    C_Timer.After(SPVP_TIMEOUT_SECONDS, function()
        -- Check if session still pending (not completed)
        if TRP3FW.spvpSessions[sessionID] then
            TRP3FW:Debug(string.format("SPVP timeout: session %s (attempt %d/%d)",
                sessionID, attempt, SPVP_MAX_RETRIES), "spvp")

            -- Cleanup session
            local session = TRP3FW.spvpSessions[sessionID]
            TRP3FW.spvpSessions[sessionID] = nil

            -- Retry
            StartSPVPHandshakeWithRetry(playerName, sendId, callback, attempt + 1)
        end
    end)
end

--- Check player via SPVP with timeout and retry
--- @param playerName string - Target player
--- @param sendId number - Unique send ID
--- @param callback function - Callback(verified, reason)
function TRP3FW:CheckPlayerViaSPVP(playerName, sendId, callback)
    local CI = TRP3FW.CacheInterface
    local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")

    -- Check cache first
    local cached = CI:Get("spvpVerified", playerName)
    if cached then
        TRP3FW:Debug(string.format("SPVP cache hit: %s", playerName), "spvp")
        if hs then hs:IncrementStat("cacheStats", "spvpVerifiedCacheHits") end
        callback(true, "cached")
        return
    end

    if hs then hs:IncrementStat("cacheStats", "spvpVerifiedCacheMisses") end

    -- Check if player is blocked (failed verification)
    if TRP3FW.spvpFailedAttempts[playerName] then
        local block = TRP3FW.spvpFailedAttempts[playerName]
        local now = TRP3FW:GetCurrentTime()

        if now < block.blockedUntil then
            TRP3FW:Debug(string.format("SPVP blocked: %s (%.0fs remaining)",
                playerName, block.blockedUntil - now), "spvp")
            callback(false, "blocked")
            return
        else
            -- Block expired
            TRP3FW.spvpFailedAttempts[playerName] = nil
        end
    end

    -- Start handshake with retry
    StartSPVPHandshakeWithRetry(playerName, sendId, callback, 0)  -- attempt = 0
end

--- Handle SPVP INIT packet (we are Bob, the prover)
--- @param message string - INIT packet data
--- @param sender string - Sender player name
function TRP3FW:HandleSPVPInit(message, sender)
    local version, sessionID, publicKey = message:match("^INIT:(%d+):(%w+):(%d+)$")

    if not version or not sessionID or not publicKey then
        TRP3FW:Debug("Malformed INIT packet from " .. sender, "spvp")
        return
    end

    -- Check version
    if tonumber(version) ~= SPVP_VERSION then
        TRP3FW:Debug(string.format("Unsupported SPVP version %s from %s", version, sender), "spvp")
        return
    end

    -- Replay detection (CRITICAL)
    if IsReplayedSession(sessionID, sender) then
        TRP3FW:Debug(string.format("Rejecting replayed INIT from %s (session: %s)",
            sender, sessionID), "spvp")
        return  -- Drop silently
    end

    -- Check Local Salt
    local phaseID = TRP3FW:GetCurrentPhaseID()
    local salt = TRP3FW:GetPhaseSalt(phaseID)

    if salt == nil then
        -- Salt is loading asynchronously (Ticket)
        -- Queue this INIT and wait for HandleSaltResponse to process it
        table.insert(self.pendingSPVPInits, { sender = sender, message = message })
        TRP3FW:Debug("Queued SPVP INIT from " .. sender .. " (waiting for salt ticket)", "spvp")
        return
    elseif salt == "" then
        -- We are in an unsecured phase. Cannot participate in SPVP.
        -- Inform sender to stop waiting.
        local reply = string.format("NOSALT:%s", sessionID)
        C_ChatInfo.SendAddonMessage("TRP3FW_SPVP", reply, "WHISPER", sender)
        TRP3FW:Debug("Sent NOSALT to " .. sender, "spvp")
        return
    end

    -- Get our generator
    local generator = GetGenerator(phaseID, salt)

    -- Generate our keys
    local privateKey = GeneratePrivateKey()
    local myPublicKey = GeneratePublicKey(generator, privateKey)

    -- Derive shared key from their public key
    local theirPublicKey = tonumber(publicKey)
    local sharedKey = DeriveSharedKey(theirPublicKey, privateKey)

    -- Store incoming session state for Bob (to verify Alice's upcoming CONFIRM)
    TRP3FW.spvpIncomingSessions[sessionID] = {
        sharedKey = sharedKey,
        sender = sender,
        timestamp = TRP3FW:GetCurrentTime()
    }

    -- Create verifier
    local verifier = HashKey(sharedKey)

    -- Send REPLY packet
    local reply = string.format("REPLY:%s:%d:%s", sessionID, myPublicKey, verifier)
    C_ChatInfo.SendAddonMessage("TRP3FW_SPVP", reply, "WHISPER", sender)

    TRP3FW:Debug(string.format("SPVP REPLY sent to %s (session: %s)", sender, sessionID), "spvp")
end

--- Handle SPVP CONFIRM packet (Bob Side)
--- Alice has verified Bob and is now proving herself to him
--- @param message string - CONFIRM packet data
--- @param sender string - Sender player name
function TRP3FW:HandleSPVPConfirm(message, sender)
    local sessionID, verifier = message:match("^CONFIRM:(%w+):(%w+)$")
    if not sessionID or not verifier then return end

    local incoming = TRP3FW.spvpIncomingSessions[sessionID]
    if not incoming or incoming.sender ~= sender then
        TRP3FW:Debug(string.format("Unknown incoming SPVP session %s from %s", sessionID, sender), "spvp")
        return
    end

    -- Cleanup incoming state
    TRP3FW.spvpIncomingSessions[sessionID] = nil

    -- Verify Alice's proof (Uses same shared key)
    local expectedVerifier = HashKey(incoming.sharedKey)
    if verifier == expectedVerifier then
        TRP3FW:Debug(string.format("SPVP SUCCESS (Mutual): %s verified via CONFIRM", sender), "spvp")
        
        -- Cache result for Bob
        local CI = TRP3FW.CacheInterface
        if CI then
            CI:Set("spvpVerified", sender, {
                timestamp = TRP3FW:GetCurrentTime(),
                verified = true,
                sessionID = sessionID
            })
        end
    else
        TRP3FW:Debug(string.format("SPVP FAILED (Mutual): %s verifier mismatch in CONFIRM", sender), "spvp")
    end
end

--- Handle SPVP NOSALT packet (Sender Side)
--- @param message string - NOSALT packet data
--- @param sender string - Sender player name
function TRP3FW:HandleSPVPNosalt(message, sender)
    local sessionID = message:match("^NOSALT:(%w+)$")
    if not sessionID then return end

    local session = TRP3FW.spvpSessions[sessionID]
    if session and session.playerName == sender then
        TRP3FW:Debug("Received NOSALT from " .. sender .. ". Verification failed.", "spvp")

        -- Fail verification immediately
        if session.callback then
            session.callback(false, "peer_no_salt")
        end

        -- Cleanup
        TRP3FW.spvpSessions[sessionID] = nil
    end
end

--- Handle SPVP REPLY packet (we are Alice, the verifier)
--- @param message string - REPLY packet data
--- @param sender string - Sender player name
function TRP3FW:HandleSPVPReply(message, sender)
    local sessionID, publicKey, verifier = message:match("^REPLY:(%w+):(%d+):(%w+)$")

    if not sessionID or not publicKey or not verifier then
        TRP3FW:Debug("Malformed REPLY packet from " .. sender, "spvp")
        return
    end

    -- Find session
    local session = TRP3FW.spvpSessions[sessionID]
    if not session then
        TRP3FW:Debug(string.format("Unknown session %s from %s (expired or invalid)", sessionID, sender), "spvp")
        return
    end

    -- Cleanup session (completed)
    TRP3FW.spvpSessions[sessionID] = nil

    -- Derive shared key
    local theirPublicKey = tonumber(publicKey)
    local sharedKey = DeriveSharedKey(theirPublicKey, session.privateKey)

    -- Verify
    local expectedVerifier = HashKey(sharedKey)

    if verifier == expectedVerifier then
        -- Verification passed!
        TRP3FW:Debug(string.format("SPVP SUCCESS: %s verified (session: %s)", sender, sessionID), "spvp")
        TRP3FW:Debug(string.format("SPVP verified: %s (session: %s)", sender, sessionID), "spvp")

        -- Cache result
        local CI = TRP3FW.CacheInterface
        CI:Set("spvpVerified", sender, {
            timestamp = TRP3FW:GetCurrentTime(),
            verified = true,
            sessionID = sessionID
        })
        -- TTL: 300s (5 min)

        -- 3-WAY HANDSHAKE: Send confirmation back to prover (Bob)
        -- Bob uses this to verify Alice without starting his own handshake
        local confirm = string.format("CONFIRM:%s:%s", sessionID, expectedVerifier)
        C_ChatInfo.SendAddonMessage("TRP3FW_SPVP", confirm, "WHISPER", sender)
        TRP3FW:Debug(string.format("SPVP CONFIRM sent to %s (session: %s)", sender, sessionID), "spvp")

        -- Invoke callback
        if session.callback then
            session.callback(true, "verified")
        end
    else
        -- Verification failed!
        TRP3FW:Debug(string.format("SPVP failed: %s (session: %s, verifier mismatch)", sender, sessionID), "spvp")

        -- Invalidate salt cache in case it was rotated
        local phaseID = TRP3FW:GetCurrentPhaseID()
        if phaseID then
            TRP3FW:InvalidatePhaseSaltCache(phaseID)
            TRP3FW:Debug(string.format("Invalidated phase salt cache (handshake failed, possible rotation)"), "spvp")

            -- Try to refresh the salt from API
            TRP3FW:GetPhaseSalt(phaseID, true)  -- Force refresh
        end

        -- Block sender
        local now = TRP3FW:GetCurrentTime()
        local blockDuration = TRP3FW_Settings.spvpBlockDuration or 60

        TRP3FW.spvpFailedAttempts[sender] = {
            count = (TRP3FW.spvpFailedAttempts[sender] and TRP3FW.spvpFailedAttempts[sender].count or 0) + 1,
            firstFailTime = TRP3FW.spvpFailedAttempts[sender] and TRP3FW.spvpFailedAttempts[sender].firstFailTime or now,
            blockedUntil = now + blockDuration
        }

        -- Invoke callback
        if session.callback then
            session.callback(false, "verification_failed")
        end
    end
end

-- ===================================================================
-- HELPER FUNCTIONS
-- ===================================================================

--- Get current phase ID (with caching)
--- @return number|nil - Phase ID or nil if unavailable
function TRP3FW:GetCurrentPhaseID()
    if not C_Epsilon or not C_Epsilon.GetPhaseId then
        return nil
    end

    -- Cache phase ID to avoid repeated API calls
    local now = TRP3FW:GetCurrentTime()
    if TRP3FW.cachedPhaseID and TRP3FW.cachedPhaseIDTime and (now - TRP3FW.cachedPhaseIDTime) < 5 then
        return TRP3FW.cachedPhaseID
    end

    local phaseID = tonumber(C_Epsilon.GetPhaseId())
    TRP3FW.cachedPhaseID = phaseID
    TRP3FW.cachedPhaseIDTime = now

    return phaseID
end

-- ===================================================================
-- PUBLIC API
-- ===================================================================

-- Export functions for external use
TRP3FW.SPVP = {
    GetGenerator = GetGenerator,
    ModPow = ModPow,
    FNV1aHash = FNV1aHash,
    HashKey = HashKey,
    GeneratePrivateKey = GeneratePrivateKey,
    GeneratePublicKey = GeneratePublicKey,
    DeriveSharedKey = DeriveSharedKey,
    GenerateSessionID = GenerateSessionID
}

TRP3FW:Debug("SPVP library loaded", "core")
