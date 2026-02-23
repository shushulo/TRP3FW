-- location/who.lua
-- WHO query system for Epsilon API

local addonName, TRP3FW = ...

-- ===================== WHO Query System (Epsilon API) =====================

-- Constants
local WHO_RESULT_LIMIT = 50  -- WoW's WHO query result limit
local WHO_TIMEOUT_SECONDS = 5  -- Timeout for WHO query responses
local WHO_SUPPRESSION_WINDOW = 5  -- Only suppress WHO output for 5 seconds after addon query
local WHO_QUERY_DELAY = 0.5  -- Brief delay between queries to avoid rate limiting
local PRIV_RATE_LIMIT = 10  -- Max RunPrivileged calls/sec (token bucket peek)
local WHO_BACKOFF_SECONDS = 10  -- Backoff window after timeout/rate-limit/truncation
local WHO_ZONE_LIMIT_WINDOW = 15  -- Window to avoid repeated zone queries after truncation
local WHO_ZONE_LIMIT_HITS = 2     -- Require this many truncations in the same zone before throttling

-- Forward declaration
local CheckPlayerViaWho

-- Helper: Check WHO caches (name cache first, then zone cache)
-- Returns: cached_entry, cache_type ("name" or "zone"), age
local function CheckWhoCaches(playerName)
    local now = TRP3FW:GetCurrentTime()
    local currentZoneName = TRP3FW.currentZoneName
    local CI = TRP3FW.CacheInterface
    if not CI then return nil, nil, nil end

    -- Check name cache first (longest duration, most authoritative)
    local cached = CI:Get("whoName", playerName)
    if cached then
        -- CacheInterface handles TTL internally via Get(), so if we got it, it's valid
        local age = now - cached.timestamp
        return cached, "name", age
    end

    -- Check zone cache
    cached = CI:Get("whoZone", playerName)
    if cached then
        local age = now - cached.timestamp
        return cached, "zone", age
    end

    return nil, nil, nil
end

-- Helper: track WHO cache stats with sendId deduplication
local function TrackWhoCacheStat(sendId, isHit, playerName)
    -- Only track when caller explicitly opts in
    if not sendId then return end
    if not TRP3FW or not TRP3FW.sessionStats or not TRP3FW.sessionStats.cacheStats then return end

    if not TRP3FW.lastWhoCacheSendId then
        TRP3FW.lastWhoCacheSendId = {}
    end

    if TRP3FW.lastWhoCacheSendId[sendId] then
        TRP3FW:Debug("Duplicate sendId "..tostring(sendId).." already counted for whoCache, skipping stat increment", "cache")
        return
    end

    local field = isHit and "whoCacheHits" or "whoCacheMisses"
    TRP3FW.sessionStats.cacheStats[field] = TRP3FW.sessionStats.cacheStats[field] + 1
    TRP3FW.lastWhoCacheSendId[sendId] = true
    TRP3FW.lastWhoCacheSendIdCount = (TRP3FW.lastWhoCacheSendIdCount or 0) + 1

    local suffix = playerName and (" for "..tostring(playerName)) or ""
    TRP3FW:Debug("whoCache "..(isHit and "HIT" or "MISS")..suffix.." (sendId: "..tostring(sendId)..")", "cache")
end

-- Zone truncation tracking: scope by zone, require multiple hits in a short window
local function RegisterZoneTruncation(zoneName)
    if not zoneName or zoneName == "" then return end
    local now = TRP3FW:GetCurrentTime()
    local state = TRP3FW.whoZoneLimitState or { zoneName = nil, hits = 0, untilTs = 0, lastHit = 0 }

    if state.zoneName ~= zoneName or (now - (state.lastHit or 0)) > WHO_ZONE_LIMIT_WINDOW then
        state = { zoneName = zoneName, hits = 0, untilTs = 0, lastHit = 0 }
    end

    state.hits = (state.hits or 0) + 1
    state.lastHit = now
    if state.hits >= WHO_ZONE_LIMIT_HITS then
        state.untilTs = now + WHO_ZONE_LIMIT_WINDOW
    end

    TRP3FW.whoZoneLimitState = state
end

local function IsZoneTruncationActive(zoneName)
    if not zoneName or zoneName == "" then return false end
    local state = TRP3FW.whoZoneLimitState
    if not state or state.zoneName ~= zoneName then return false end
    if not state.untilTs or state.untilTs <= TRP3FW:GetCurrentTime() then return false end
    return true
end

-- Helper: try map/broadcast cache or a map scan when WHO cannot run
local function TryMapFallbackForWho(playerName, sendId, callback, reasonTag)
    if not callback or playerName == "__PREPOPULATE__" then
        return false
    end

    local nowTs = TRP3FW:GetCurrentTime()
    local CI = TRP3FW.CacheInterface
    local cacheDuration = (TRP3FW.Prefs and TRP3FW.Prefs.scanCacheDuration) or 120
    local cacheFailDuration = (TRP3FW.Prefs and TRP3FW.Prefs.scanCacheFailureDuration) or 10
    local strictNonceRequired = TRP3FW.Prefs and TRP3FW.Prefs.scanResponseRequireNonce
    local myMapID = TRP3FW:GetCurrentMapID()

    local function checkEntry(entry, sourceBase, mismatchSource)
        if not entry then return false end
        local ts = type(entry) == "table" and entry.timestamp or entry
        local mapID = type(entry) == "table" and entry.mapID or nil
        local verified = type(entry) == "table" and entry.verified or nil
        local foundFlag = type(entry) == "table" and entry.found
        if not ts then return false end

        local duration = cacheDuration
        if foundFlag == false then
            duration = cacheFailDuration
        end
        if mapID and myMapID and mapID ~= myMapID then
            duration = cacheFailDuration
        end

        local age = nowTs - ts
        if age > duration then return false end
        if strictNonceRequired and verified == false then return false end

        local source = sourceBase
        local result = foundFlag
        if mapID and myMapID and mapID ~= myMapID then
            result = false
            source = mismatchSource or (sourceBase.."_mismatch")
        elseif result == nil then
            result = (mapID and myMapID and mapID == myMapID) or true
        end

        callback(result, source, age, nil, mapID)
        TRP3FW:Debug("[WHO Fallback] Resolved via "..source.." ("..tostring(reasonTag)..") for "..playerName.." age="..string.format("%.1f", age).."s", "who")
        return true
    end

    local cached = CI and CI:Get("mapScan", playerName)
    local broadcast = CI and CI:Get("broadcast", playerName)

    if checkEntry(cached, "map_cache_match", "map_cache_mismatch") then
        return true
    end

    if checkEntry(broadcast, "map_cache_match_broadcast", "map_cache_mismatch_broadcast") then
        return true
    end

    if not TRP3FW:IsMapCheckEnabled() then
        return false
    end

    TRP3FW:Debug("[WHO Fallback] Attempting map scan ("..tostring(reasonTag)..") for "..playerName, "who")
    TRP3FW:MapScan(playerName, sendId, function(found, source, cacheAge)
        callback(found, source or "map_scan", cacheAge, nil, nil)
    end)
    return true
end

-- Suppress WHO results from appearing in chat
local originalWhoListUpdate = WhoList_Update
TRP3FW.suppressWhoOutput = false  -- Kept for backward compatibility, but not used
TRP3FW.whoQuerySentTime = 0  -- Timestamp of last addon WHO query

local function ShouldSuppressWhoOutput()
    -- Only suppress if we sent a query recently (within suppression window)
    local timeSinceQuery = TRP3FW:GetCurrentTime() - TRP3FW.whoQuerySentTime
    return timeSinceQuery < WHO_SUPPRESSION_WINDOW
end

local function ShouldSuppressChatOutput()
    -- If suppressAllWhoOutput is enabled, suppress chat messages
    if TRP3FW.Prefs and TRP3FW.Prefs.suppressAllWhoOutput then
        return true
    end

    -- Otherwise, only suppress if we sent a query recently (within suppression window)
    local timeSinceQuery = TRP3FW:GetCurrentTime() - TRP3FW.whoQuerySentTime
    return timeSinceQuery < WHO_SUPPRESSION_WINDOW
end

-- Queue hygiene helpers
local function IsQueueEntryStale(entry)
    if not entry or not entry.timestamp then return true end
    local now = TRP3FW:GetCurrentTime()
    local ttl = math.max(TRP3FW.Prefs.whoNameCacheDuration or 0, TRP3FW.Prefs.whoZoneCacheDuration or 0, 60)
    return (now - entry.timestamp) > ttl
end

-- Lightweight ring-buffer style helpers to avoid table.remove churn
local function EnsureWhoQueue()
    if not TRP3FW.pendingWhoQueries then
        TRP3FW.pendingWhoQueries = {}
    end
    if not TRP3FW.pendingWhoQueueHead then
        TRP3FW.pendingWhoQueueHead = 1
    end
end

local function GetWhoQueueSize()
    EnsureWhoQueue()
    local tail = #TRP3FW.pendingWhoQueries
    local head = TRP3FW.pendingWhoQueueHead
    if tail < head then return 0 end
    return tail - head + 1
end

local function AdvanceWhoQueue(newHead)
    EnsureWhoQueue()
    TRP3FW.pendingWhoQueueHead = newHead
    local queue = TRP3FW.pendingWhoQueries
    local tail = #queue

    -- Compact when head has advanced far enough to avoid unbounded growth
    if newHead > 64 and newHead > (tail / 2) then
        local compacted = {}
        for i = newHead, tail do
            compacted[#compacted + 1] = queue[i]
        end
        TRP3FW.pendingWhoQueries = compacted
        TRP3FW.pendingWhoQueueHead = 1
    end
end

-- SECURITY: Peek token bucket without consuming (mirrors RunPrivilegedSafe defaults)
local function HasPrivilegedCapacity(category)
    local rate = TRP3FW.privilegedRate
    if not rate then return true end  -- Not initialized yet; allow first call

    local now = TRP3FW:GetCurrentTime()
    local tokens = math.min(PRIV_RATE_LIMIT, (rate.tokens or PRIV_RATE_LIMIT) + ((now - (rate.lastRefill or now)) * PRIV_RATE_LIMIT))
    
    -- Optimization #9: Check against reserved tokens if this category isn't high priority
    if TRP3FW.GetCategoryPriority then
        local _, config = TRP3FW:GetCategoryPriority(category)
        if config and not config.canUseReserved then
            local reserved = (TRP3FW.Prefs and TRP3FW.Prefs.privilegedReservedTokens) or 2
            tokens = tokens - reserved
        end
    end

    if tokens < 1 then
        TRP3FW:Debug("[WHO Query] RATE LIMIT (preflight) blocking privileged call: "..tostring(category), "security")
        return false
    end
    return true
end

-- SECURITY: Class/race set for WHO message filtering
-- Using table lookup instead of regex to prevent ReDoS attacks
-- Plain text search is immune to catastrophic backtracking
local CLASS_RACE_SET = {
    -- Multi-word classes
    ["Death Knight"] = true,
    ["Demon Hunter"] = true,
    -- Multi-word races (Alliance)
    ["Night Elf"] = true,
    ["Void Elf"] = true,
    ["Lightforged Draenei"] = true,
    ["Dark Iron Dwarf"] = true,
    ["Kul Tiran"] = true,
    ["Earthen"] = true,  -- The War Within (TWW)
    -- Multi-word races (Horde)
    ["Blood Elf"] = true,
    ["Highmountain Tauren"] = true,
    ["Mag'har Orc"] = true,
    ["Zandalari Troll"] = true,
    -- Single-word classes
    ["Druid"] = true,
    ["Evoker"] = true,
    ["Hunter"] = true,
    ["Mage"] = true,
    ["Monk"] = true,
    ["Paladin"] = true,
    ["Priest"] = true,
    ["Rogue"] = true,
    ["Shaman"] = true,
    ["Warlock"] = true,
    ["Warrior"] = true,
    -- Single-word races (Alliance)
    ["Human"] = true,
    ["Dwarf"] = true,
    ["Gnome"] = true,
    ["Draenei"] = true,
    ["Worgen"] = true,
    ["Mechagnome"] = true,
    ["Dracthyr"] = true,  -- Dragonflight
    -- Single-word races (Horde)
    ["Orc"] = true,
    ["Undead"] = true,
    ["Tauren"] = true,
    ["Troll"] = true,
    ["Goblin"] = true,
    ["Nightborne"] = true,
    ["Vulpera"] = true,
    -- Neutral races
    ["Pandaren"] = true
}

-- Helper function: Check if message contains any class or race (case-insensitive plain text search)
local function ContainsClassOrRace(msg)
    local msgLower = msg:lower()  -- Convert message to lowercase once
    for classOrRace in pairs(CLASS_RACE_SET) do
        -- Use plain text find with lowercase comparison (4th param = true to avoid regex backtracking)
        if msgLower:find(classOrRace:lower(), 1, true) then
            return true
        end
    end
    return false
end

local function SuppressWhoMessages()
    -- Hook WhoList_Update to suppress WHO window ONLY for TRP3FW queries
    -- This allows manual /who to still show in the WHO frame
    WhoList_Update = function()
        if not ShouldSuppressWhoOutput() then
            originalWhoListUpdate()
        end
    end

    -- NOTE: We do NOT hook FriendsFrame_Update because it's used for the entire
    -- friends frame (friends list, guild, etc.), not just WHO results.
    -- Blocking it breaks the friends list UI.

    -- Filter chat messages to suppress WHO output
    -- Filter both CHAT_MSG_SYSTEM and CHAT_MSG_TEXT_EMOTE (Epsilon may use different channel)
    local function FilterWhoMessages(self, event, msg, ...)
        if ShouldSuppressChatOutput() then
            -- Block WHO result summary patterns
            -- "5 players total" / "5 player total" / "0 players found"
            if (msg:find("player") and (msg:find("total") or msg:find("found"))) then
                TRP3FW:Debug("[WHO Suppression] Blocked summary: "..msg, "who")
                return true
            end

            -- Block numbered player lines (format: "1. PlayerName-ServerName")
            if msg:match("^%d+%. [%w]+") then
                TRP3FW:Debug("[WHO Suppression] Blocked numbered line: "..msg, "who")
                return true
            end

            -- Block bracketed player lines (format: "[PlayerName]: Level X Race Class <Optional: Guild> - Zone")
            -- Examples:
            --   [Iriden]: Level 60 Vulpera Mage <The Crypt Seekers> - Crypthaven
            --   [Elliandra]: Level 60 Blood Elf Mage - Crypthaven
            -- Format: [Name]: Level XX ... - ZoneName (must have " - " to indicate zone separator)
            -- FIXED: HIGH-5 - Use plain text checks first to prevent ReDoS (avoid catastrophic backtracking)
            if msg:find("^%[", 1, false) and msg:find("%]: Level ", 1, false) and msg:find(" %- ", 1, false) then
                -- Plain text checks passed, now verify it's a WHO line (not player chat)
                if ContainsClassOrRace(msg) then
                    TRP3FW:Debug("[WHO Suppression] Blocked bracketed WHO line: "..msg, "who")
                    return true
                end
            end

            -- Block "Online Players" header
            if msg:find("Online Players") or msg:find("Players found") then
                TRP3FW:Debug("[WHO Suppression] Blocked header: "..msg, "who")
                return true
            end

            -- Block any message containing "Who List" or "WHO"
            if msg:match("[Ww]ho [Ll]ist") or msg:match("WHO") then
                TRP3FW:Debug("[WHO Suppression] Blocked WHO-related: "..msg, "who")
                return true
            end

            -- Block Epsilon-specific format: "PlayerName - Level X Race ClassName (Zone)"
            -- Must have " - " separator AND end with zone in parentheses to avoid false positives
            -- FIXED: HIGH-5 - Use plain text checks first to prevent ReDoS
            if msg:find(" %- Level ", 1, false) and msg:find("%(", 1, false) and msg:find("%)$", 1, false) then
                -- Format: "PlayerName - Level 60 Vulpera Mage (Crypthaven)"
                -- NOT matched: "PlayerName - Level 60 rocks" (no zone in parentheses)
                -- Plain text checks passed, verify it's a WHO line
                if ContainsClassOrRace(msg) then
                    TRP3FW:Debug("[WHO Suppression] Blocked Epsilon format: "..msg, "who")
                    return true
                end
            end

            -- Block any message that looks like a player listing (has level + class/race + zone separator)
            -- Must have " - " or "(" to indicate proper WHO format (prevents matching casual chat)
            -- FIXED: HIGH-5 - Simplified pattern to prevent ReDoS (no greedy quantifiers)
            if msg:find("Level %d", 1, false) and ContainsClassOrRace(msg) and (msg:find(" %- ", 1, false) or msg:find("%(", 1, false)) then
                TRP3FW:Debug("[WHO Suppression] Blocked class/level line: "..msg, "who")
                return true
            end
        end
        return false
    end

    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", FilterWhoMessages)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_TEXT_EMOTE", FilterWhoMessages)
end

-- Initialize suppression
function TRP3FW:InitializeWhoSuppression()
    SuppressWhoMessages()
end

-- Frame for processing WHO results
local whoFrame = CreateFrame("Frame")
whoFrame:RegisterEvent("WHO_LIST_UPDATE")

whoFrame:SetScript("OnEvent", function(self, event)
    local start = debugprofilestop()
    if event == "WHO_LIST_UPDATE" and TRP3FW.whoQueryPending then
        local pendingQuery = TRP3FW.whoQueryPending
        local isNameQuery = pendingQuery.isNameQuery or false
        local isScanMode = pendingQuery.scanMode or false  -- NEW: Check for scan mode
        local pendingZoneName = pendingQuery.zoneName
        local zoneQueryContext = pendingQuery.zoneQueryContext  -- Carries zone query details into name query fallback
        TRP3FW:Debug("[WHO Query] Processing WHO results for: "..tostring(pendingQuery.playerName).." (name query: "..tostring(isNameQuery)..", scan mode: "..tostring(isScanMode)..")", "who")

        local playerName = pendingQuery.playerName
        local callback = pendingQuery.callback
        TRP3FW.whoQueryPending = nil
        TRP3FW.whoQueryCooldown = false

        -- Disable WHO output suppression after processing
        TRP3FW.suppressWhoOutput = false

        -- Get WHO results using privileged calls
        local numResults, totalCount = 0, 0
        local found = false
        local zone = nil

        if TRP3FW.hasEpsilonAPI then
            -- Get WHO results - these calls work after SendWho() was called with RunPrivileged
            local success, numWho, totalWho = pcall(C_FriendList.GetNumWhoResults)

            -- FIXED: MEDIUM-7 - Validate API return values before use
            if not success or not numWho or type(numWho) ~= "number" or numWho < 0 then
                TRP3FW:Debug("[WHO Query] ERROR: Invalid WHO results count: "..tostring(numWho), "who")
                if callback then callback(false, "api_error", 0, nil) end
                return  -- ABORT instead of continuing with bad data
            end

            if numWho > 0 then
                numResults = numWho
                totalCount = totalWho or numWho
                TRP3FW:Debug("[WHO Query] Got "..numResults.." results (total: "..totalCount..")", "who")

                local now = TRP3FW:GetCurrentTime()
                local cachedCount = 0

                -- Get our own character name to skip it
                local myName = UnitName("player")

                -- SCAN MODE: Collect all player names for zone scan
                if isScanMode then
                    local playerList = {}
                    for i = 1, numResults do
                        local success, info = pcall(C_FriendList.GetWhoInfo, i)
                        if not success then
                            TRP3FW:Debug("[WHO Zone Scan] ERROR: Failed to get WHO info for index "..i..": "..tostring(info), "who")
                            info = nil
                        end

                        if info and info.fullName then
                            local name = TRP3FW:CleanPlayerName(info.fullName)
                            local playerZone = info.area or nil

                            -- Skip invalid names and self
                            if name and name ~= myName then
                                table.insert(playerList, name)

                                -- Also cache in zone cache for future queries
                                local cacheEntry = TRP3FW:AcquireWhoResult()
                                cacheEntry.found = true
                                cacheEntry.zone = playerZone
                                cacheEntry.timestamp = now

                                local CI = TRP3FW.CacheInterface
                                if CI then
                                    CI:Set("whoZone", name, cacheEntry)
                                    TRP3FW:Debug("[Cache Add] whoZoneCache: Added "..name.." (zone scan)", "cache")
                                end
                                cachedCount = cachedCount + 1
                            end
                        end
                    end

                    TRP3FW:Debug("[WHO Zone Scan] Collected "..#playerList.." players (cached "..cachedCount..")", "who")

                    -- Return player list to callback
                    if callback then
                        callback(true, playerList, nil)
                    end

                    -- Process queued queries
                    EnsureWhoQueue()
                    local queueIndex = TRP3FW.pendingWhoQueueHead
                    local queue = TRP3FW.pendingWhoQueries
                    while queueIndex <= #queue do
                        local nextQuery = queue[queueIndex]
                        queueIndex = queueIndex + 1

                        if IsQueueEntryStale(nextQuery) then
                            TRP3FW:Debug("[WHO Query] Dropping stale queued request for "..tostring(nextQuery.playerName), "who")
                        else
                            local cached, cacheType, age = CheckWhoCaches(nextQuery.playerName)
                            if cached then
                                TRP3FW:Debug("[WHO Query] Queued player "..nextQuery.playerName.." found in "..cacheType.." cache, executing callback immediately", "who")
                                if nextQuery.callback then
                                    local ageNow = TRP3FW:GetCurrentTime() - cached.timestamp
                                    nextQuery.callback(cached.found, "cached", ageNow, cached.zone)
                                end
                            else
                                TRP3FW:Debug("[WHO Query] Queued player "..nextQuery.playerName.." not cached, scheduling WHO query", "who")
                                C_Timer.After(WHO_QUERY_DELAY, function()
                                    CheckPlayerViaWho(nextQuery.playerName, nextQuery.sendId or 0, nextQuery.callback, false, nextQuery.forceNameQuery, nextQuery.priority)
                                end)
                                break
                            end
                        end
                    end
                    AdvanceWhoQueue(queueIndex)

                    local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
                    if hs then hs:RecordPerformance(debugprofilestop() - start, "WHO Query") end
                    return  -- Exit early for scan mode
                end

                -- For zone queries: cache ALL results
                -- For name queries: only cache the specific player
                for i = 1, numResults do
                    local success, info = pcall(C_FriendList.GetWhoInfo, i)
                    if not success then
                        TRP3FW:Debug("[WHO Query] ERROR: Failed to get WHO info for index "..i..": "..tostring(info), "who")
                        info = nil
                    end

                    if info and info.fullName then
                        local name = TRP3FW:CleanPlayerName(info.fullName)
                        local playerZone = info.area or nil

                        -- Safety check: Skip if CleanPlayerName returned nil (invalid name format)
                        if not name then
                            TRP3FW:Debug(function()
                                return "[WHO Query] WARNING: CleanPlayerName returned nil for fullName: "..tostring(info.fullName).." (class: "..tostring(info.classStr)..", race: "..tostring(info.raceStr)..")"
                            end, "who")
                        -- Skip our own character
                        elseif name == myName then
                            TRP3FW:Debug(function()
                                return "[WHO Query] Skipping self: "..name
                            end, "who")
                        else
                            -- Check if this is the player we're looking for
                            if name == playerName then
                                found = true
                                zone = playerZone
                                TRP3FW:Debug(function()
                                    return "[WHO Query] FOUND target player: "..playerName.." in zone: "..tostring(playerZone)
                                end, "who")
                            end

                            -- Cache based on query type
                            if isNameQuery then
                                -- Name query: only cache the target player in name cache
                                if name == playerName then
                                    -- OPTIMIZATION: Use object pool to reduce GC pressure
                                    local cacheEntry = TRP3FW:AcquireWhoResult()
                                    cacheEntry.found = true
                                    cacheEntry.zone = playerZone
                                    cacheEntry.timestamp = now
                                    
                                    local CI = TRP3FW.CacheInterface
                                    if CI then
                                        CI:Set("whoName", name, cacheEntry)
                                        TRP3FW:Debug(function()
                                            return "[Cache Add] whoNameCache: Added "..name.." (zone: "..tostring(playerZone)..")"
                                        end, "cache")
                                    end

                                    cachedCount = cachedCount + 1
                                    TRP3FW:Debug(function()
                                        return "[WHO Query] Cached name query result: "..tostring(name).." in zone: "..tostring(playerZone)
                                    end, "who")
                                end
                            else
                                                                -- Zone query: cache everyone in zone cache (except self)
                                                                -- OPTIMIZATION: Use object pool to reduce GC pressure
                                                                local cacheEntry = TRP3FW:AcquireWhoResult()
                                                                cacheEntry.found = true
                                                                cacheEntry.zone = playerZone
                                                                cacheEntry.timestamp = now
                                                                
                                                                local CI = TRP3FW.CacheInterface
                                                                if CI then
                                                                    CI:Set("whoZone", name, cacheEntry)
                                                                    TRP3FW:Debug("[Cache Add] whoZoneCache: Added "..name.." (zone: "..tostring(playerZone)..")", "cache")
                                                                end
                                
                                                                cachedCount = cachedCount + 1
                                                                TRP3FW:Debug("[WHO Query] Cached zone query result "..i..": "..tostring(name).. " in zone: "..tostring(playerZone), "who")
                                                            end
                                                        end
                                                    end
                                                end

                TRP3FW:Debug("[WHO Query] Cached "..cachedCount.." players from WHO results ("..(isNameQuery and "name" or "zone").." query)", "who")
            else
                TRP3FW:Debug("[WHO Query] No WHO results returned", "who")
            end
        end

        -- If not found and this was a zone query, try a name-specific query
        -- If this was already a name query, just cache negative and callback
        -- ALSO fallback to name query if we got 50+ results (WHO limit reached, might have been truncated)
        -- SKIP name query for pre-population dummy name
        local shouldFallbackToName = not found and not isNameQuery and (numResults >= WHO_RESULT_LIMIT or totalCount >= WHO_RESULT_LIMIT)
        local isPrepopulation = playerName == "__PREPOPULATE__"
        if not found and not isNameQuery and not isPrepopulation then
            if shouldFallbackToName then
                TRP3FW:Debug("[WHO Query] Got "..numResults.." results (total: "..totalCount.."), WHO limit likely reached. Target player "..playerName.." not found in truncated results, trying name query...", "who")
                TRP3FW.nextWhoBackoffUntil = TRP3FW:GetCurrentTime() + WHO_BACKOFF_SECONDS
                RegisterZoneTruncation(pendingZoneName)

                            local zoneContext = {
                                zoneName = pendingZoneName,
                                numResults = numResults,
                                totalCount = totalCount,
                                limitReached = shouldFallbackToName
                            }
                
                            -- Generate new request ID for name query
                            TRP3FW.whoQueryRequestId = TRP3FW.whoQueryRequestId + 1
                            local nameRequestId = TRP3FW.whoQueryRequestId
                            
                            -- Set cooldown immediately to block other queries during the delay
                            TRP3FW.whoQueryCooldown = true
                            TRP3FW:Debug("[WHO Query] Scheduling fallback name query for "..playerName.." in 3 seconds (server throttle compliance)", "who")
                
                            -- DELAY: Wait 3 seconds before sending fallback query to avoid server throttle
                            C_Timer.After(3.0, function()
                                -- Check if request was cancelled or superseded (though unlikely with cooldown active)
                                -- We can proceed with setting up the pending query
                                
                                -- Set up for name query (mark as pending again)
                                TRP3FW.whoQueryPending = {
                                    playerName = playerName,
                                    callback = callback,
                                    timestamp = TRP3FW:GetCurrentTime(),
                                    isNameQuery = true,  -- Flag to indicate this is a name-based query
                                    requestId = nameRequestId,  -- New request ID for name query
                                    zoneQueryContext = zoneContext -- Preserve zone query context for result interpretation
                                }
                                
                                TRP3FW:Debug("[WHO Query] Executing delayed name query (ID: "..nameRequestId..")", "who")
                
                                -- Enable WHO output suppression again
                                TRP3FW.whoQuerySentTime = TRP3FW:GetCurrentTime()
                
                                -- Since we are falling back to a name query for the CURRENT request,
                                -- the zone query "slot" is effectively freed up for the next queued item.
                                -- Process the next item in the queue immediately to avoid stalls.
                                EnsureWhoQueue()
                                local queueIndex = TRP3FW.pendingWhoQueueHead
                                local queue = TRP3FW.pendingWhoQueries
                                while queueIndex <= #queue do
                                    local nextQuery = queue[queueIndex]
                                    queueIndex = queueIndex + 1
                
                                    if IsQueueEntryStale(nextQuery) then
                                        TRP3FW:Debug("[WHO Query] Dropping stale queued request for "..tostring(nextQuery.playerName), "who")
                                    else
                                        local cached, cacheType, age = CheckWhoCaches(nextQuery.playerName)
                                        if cached then
                                            TRP3FW:Debug("[WHO Query] Queued player "..nextQuery.playerName.." found in "..cacheType.." cache, executing callback immediately", "who")
                                            if nextQuery.callback then
                                                local ageNow = TRP3FW:GetCurrentTime() - cached.timestamp
                                                nextQuery.callback(cached.found, "cached", ageNow, cached.zone)
                                            end
                                        else
                                            TRP3FW:Debug("[WHO Query] Queued player "..nextQuery.playerName.." not cached, scheduling WHO query (concurrent with fallback)", "who")
                                            C_Timer.After(WHO_QUERY_DELAY, function()
                                                CheckPlayerViaWho(nextQuery.playerName, nextQuery.sendId or 0, nextQuery.callback, false, nextQuery.forceNameQuery, nextQuery.priority)
                                            end)
                                            break
                                        end
                                    end
                                end
                                AdvanceWhoQueue(queueIndex)
                
                                -- SECURITY: Sanitize name before constructing query (Fixes nil global error)
                                local sanitizedName = TRP3FW:SanitizePlayerName(playerName)
                                if not sanitizedName then
                                    TRP3FW:Debug("[WHO Query] ERROR: Invalid player name for fallback query: "..tostring(playerName), "who")
                                    if callback then callback(false, "invalid_name", 0, nil) end
                                    TRP3FW.whoQueryPending = nil
                                    TRP3FW.whoQueryCooldown = false
                                    return
                                end
                
                                -- Send name-based WHO query
                                local whoQuery = 'n-"'..sanitizedName..'"'
                                TRP3FW:Debug("[WHO Query] Sending name query: "..whoQuery, "who")
                
                                -- Use double brackets to avoid escaping issues
                                local privilegedCode = 'C_FriendList.SetWhoToUi(false) C_FriendList.SendWho([['..whoQuery..']])'
                
                                -- FIXED: CRITICAL-3 - Use rate-limited safe wrapper (with preflight)
                                if not HasPrivilegedCapacity(nameCategory) then
                                    TRP3FW:Debug("[WHO Query] Name query blocked by rate limit preflight ("..tostring(nameCategory)..")", "who")
                                    TRP3FW.nextWhoBackoffUntil = TRP3FW:GetCurrentTime() + WHO_BACKOFF_SECONDS
                                    TRP3FW.whoQueryPending = nil
                                    TRP3FW.whoQueryCooldown = false
                                    TRP3FW.suppressWhoOutput = false
                                    if not TryMapFallbackForWho(playerName, nil, callback, "rate_limit_name") and callback then
                                        callback(false, "rate_limit", 0, nil)
                                    end
                                    return
                                end
                
                                local success, err = TRP3FW:RunPrivilegedSafe(privilegedCode, nameCategory)
                
                                if not success then
                                    TRP3FW:Debug("[WHO Query] ERROR: Failed to send name query: "..tostring(err), "who")
                                    TRP3FW.whoQueryPending = nil
                                    TRP3FW.whoQueryCooldown = false
                                    TRP3FW.suppressWhoOutput = false
                
                                    -- Cache negative result in name cache (since zone query already failed)
                                    local CI = TRP3FW.CacheInterface
                                    if CI then
                                        CI:Set("whoName", playerName, {
                                            found = false,
                                            zone = nil,
                                            timestamp = TRP3FW:GetCurrentTime()
                                        })
                                        TRP3FW:Debug("[Cache Add] whoNameCache: Added "..playerName.." (NOT FOUND)", "cache")
                                    end
                
                                    local reason = (err == "rate_limit") and "rate_limit" or "error"
                                    if not TryMapFallbackForWho(playerName, nil, callback, "name_sendfail_"..reason) and callback then
                                        callback(false, reason, 0, nil)
                                    end
                                    return
                                end
                
                                TRP3FW:Debug("[WHO Query] Name query sent successfully", "who")
                
                                -- Try to get results immediately
                                C_Timer.After(0.5, function()
                                    if TRP3FW.whoQueryPending and TRP3FW.whoQueryPending.requestId == nameRequestId then
                                        TRP3FW:Debug("[WHO Query] Checking for immediate name query results (request "..nameRequestId..")...", "who")
                                        local success, numWho = pcall(C_FriendList.GetNumWhoResults)
                                        if not success then
                                            TRP3FW:Debug("[WHO Query] ERROR: Failed to get WHO results count: "..tostring(numWho), "who")
                                            numWho = 0
                                        end
                                        if numWho and numWho > 0 then
                                            TRP3FW:Debug("[WHO Query] Found immediate results! Triggering event manually", "who")
                                            whoFrame:GetScript("OnEvent")(whoFrame, "WHO_LIST_UPDATE")
                                            return
                                        end
                                    end
                                end)
                
                                -- Set timeout
                                C_Timer.After(WHO_TIMEOUT_SECONDS, function()
                                    if TRP3FW.whoQueryPending and TRP3FW.whoQueryPending.requestId == nameRequestId then
                                        TRP3FW:Debug("[WHO Query] Name query timeout for "..playerName.." (request "..nameRequestId..")", "who")
                                        TRP3FW.nextWhoBackoffUntil = TRP3FW:GetCurrentTime() + WHO_BACKOFF_SECONDS
                                        TRP3FW.whoQueryPending = nil
                                        TRP3FW.whoQueryCooldown = false
                                        TRP3FW.suppressWhoOutput = false
                
                                        -- Cache negative result in name cache (timeout on name query)
                                        local CI = TRP3FW.CacheInterface
                                        if CI then
                                            CI:Set("whoName", playerName, {
                                                found = false,
                                                zone = nil,
                                                timestamp = TRP3FW:GetCurrentTime()
                                            })
                                            TRP3FW:Debug("[Cache Add] whoNameCache: Added "..playerName.." (NOT FOUND - timeout)", "cache")
                                        end
                
                                        if not TryMapFallbackForWho(playerName, nil, callback, "name_timeout") and callback then
                                            callback(false, "timeout", 0, nil)
                                        end
                                    end
                                end)
                            end)            else
                -- OPTIMIZATION: Zone query was NOT truncated, so the list is complete.
                -- If player wasn't found, they are definitely not in the zone.
                -- Skip the extra name query.
                TRP3FW:Debug("[WHO Query] Target player "..playerName.." not found in COMPLETE zone query ("..numResults.." results). Skipping name query.", "who")
                
                -- Cache negative result in name cache
                local CI = TRP3FW.CacheInterface
                if CI then
                    CI:Set("whoName", playerName, {
                        found = false,
                        zone = nil,
                        timestamp = TRP3FW:GetCurrentTime()
                    })
                    TRP3FW:Debug("[Cache Add] whoNameCache: Added "..playerName.." (NOT FOUND - complete zone query)", "cache")
                end

                if callback then
                    callback(false, "who_not_found", 0, nil)
                end
            end
        elseif not found and isNameQuery then
            -- Name query failed - player not found anywhere
            TRP3FW:Debug("[WHO Query] Target player "..playerName.." not found in name query either", "who")
            TRP3FW.nextWhoBackoffUntil = TRP3FW:GetCurrentTime() + WHO_BACKOFF_SECONDS

            -- Cache negative result in name cache (name query failed)
            local CI = TRP3FW.CacheInterface
            if CI then
                CI:Set("whoName", playerName, {
                    found = false,
                    zone = nil,
                    timestamp = TRP3FW:GetCurrentTime()
                })
                TRP3FW:Debug("[Cache Add] whoNameCache: Added "..playerName.." (NOT FOUND - name query failed)", "cache")
            end

            if callback then
                local sourceReason = "who_not_found"
                if zoneQueryContext and zoneQueryContext.limitReached == false then
                    sourceReason = "who_query_zone_mismatch"
                    TRP3FW:Debug("[WHO Query] Treating as zone mismatch (zone query: "..tostring(zoneQueryContext.zoneName)..", results="..tostring(zoneQueryContext.numResults)..")", "who")
                end
                callback(false, sourceReason, 0, nil)
            end
        elseif isPrepopulation then
            -- Pre-population query completed - zone cache is now populated
            TRP3FW:Debug("[WHO Query] Zone cache pre-population complete ("..numResults.." players cached)", "who")
            if callback then
                callback(false, "prepopulation_complete", 0, nil)
            end
        else
            -- Found (in either zone or name query), cache and callback
            if callback then
                callback(found, "who_query", 0, zone)
            end
        end

        -- Process queued queries - check cache first for each (uses head index to avoid shifts)
            EnsureWhoQueue()
            local queueIndex = TRP3FW.pendingWhoQueueHead
            local queue = TRP3FW.pendingWhoQueries
            while queueIndex <= #queue do
                local nextQuery = queue[queueIndex]
                queueIndex = queueIndex + 1

                -- Drop stale queued entries
                if IsQueueEntryStale(nextQuery) then
                    TRP3FW:Debug("[WHO Query] Dropping stale queued request for "..tostring(nextQuery.playerName), "who")
                else
                    -- Check if this queued player was just cached
                    local cached, cacheType, age = CheckWhoCaches(nextQuery.playerName)

                    if cached then
                        -- Already cached! Execute callback immediately
                        TRP3FW:Debug("[WHO Query] Queued player "..nextQuery.playerName.." found in "..cacheType.." cache, executing callback immediately", "who")
                        if nextQuery.callback then
                            local ageNow = TRP3FW:GetCurrentTime() - cached.timestamp
                            nextQuery.callback(cached.found, "cached", ageNow, cached.zone)
                        end
                        -- Continue to next queued query
                    else
                        -- Not cached in either, need to do WHO query
                        TRP3FW:Debug("[WHO Query] Queued player "..nextQuery.playerName.." not cached, scheduling WHO query", "who")
                        C_Timer.After(WHO_QUERY_DELAY, function() -- Brief delay between queries
                            CheckPlayerViaWho(nextQuery.playerName, nextQuery.sendId or 0, nextQuery.callback, false, nextQuery.forceNameQuery, nextQuery.priority)
                        end)
                        break -- Only schedule one query at a time
                    end
                end
            end

        -- Advance head; compaction handled by helper
        AdvanceWhoQueue(queueIndex)
    end

    local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
    if hs then hs:RecordPerformance(debugprofilestop() - start, "WHO Query") end
end)

-- Check if player is online using WHO query
-- trackStats: if true, track cache hits/misses in session statistics
-- forceNameQuery: if true, skip the zone query and go straight to a name query (useful when current zone is unknown)
-- priority: optional override for RunPrivilegedSafe category (e.g. "who_map_verification")
CheckPlayerViaWho = function(playerName, sendId, callback, trackStats, forceNameQuery, priority)
    forceNameQuery = forceNameQuery or false
    if not TRP3FW.hasEpsilonAPI then
        TRP3FW:Debug("[WHO Query] Epsilon API not available", "who")
        if callback then callback(false, "unavailable") end
        return
    end

    -- Select priority category (defaulting to standard categories if not provided)
    local zoneCategory = priority or "who_zone_query"
    local nameCategory = priority or "who_name_query"
    local nameFallbackCategory = priority or "who_name_query_fallback"

    -- SECURITY: Canonicalize/sanitize input once; reuse everywhere to avoid unsanitized WHO payloads
    local originalName = playerName
    local cleanName = TRP3FW:CleanPlayerName(playerName)
    local sanitizedName = cleanName and TRP3FW:SanitizePlayerName(cleanName) or nil
    if not cleanName or not sanitizedName then
        TRP3FW:Debug("[WHO Query] ERROR: Invalid player name rejected: "..tostring(originalName), "who")
        if callback then callback(false, "invalid_name") end
        return
    end
    playerName = cleanName

    local now = TRP3FW:GetCurrentTime()

    local function fallbackToMap(reasonTag, defaultReason)
        local used = TryMapFallbackForWho(playerName, sendId, callback, reasonTag)
        if used then
            return true
        end
        if callback and defaultReason then
            callback(false, defaultReason, 0, nil)
            return true
        end
        return false
    end

    -- Check caches first
    local cached, cacheType, age = CheckWhoCaches(playerName)
    if cached then
        TRP3FW:Debug("[WHO Query] "..cacheType:upper().." cache hit for "..playerName.." (cached "..string.format("%.1f", age).."s ago) in zone: "..tostring(cached.zone), "who")
        
        -- NEW LOGIC: Background Refresh
        -- If cache entry is valid but aging, trigger a low-priority refresh
        if cached.found and playerName ~= "__PREPOPULATE__" then
            local ttl = (cacheType == "name") and (TRP3FW.Prefs.whoNameCacheDuration or 180) or (TRP3FW.Prefs.whoZoneCacheDuration or 180)
            local thresholdPercent = TRP3FW.Prefs.whoCacheRefreshThreshold or 50
            if age > (ttl * (thresholdPercent / 100)) then
                 TRP3FW:Debug("[WHO Query] Cache entry aging ("..string.format("%.1f", age).."s / "..ttl.."s) - triggering background refresh for "..playerName, "who")
                 -- Low priority background refresh (no callback)
                 -- Use a custom category to ensure it doesn't block high-priority WHO queries
                 TRP3FW:CheckPlayerViaWho(playerName, nil, nil, false, true, "who_refresh_low")
            end
        end

        if trackStats then
            TrackWhoCacheStat(sendId, true, playerName)
        end
        if callback then callback(cached.found, "cached", age, cached.zone) end
        return
    end

    -- Check if zone query is off cooldown
    EnsureWhoQueue()
    local zoneQueryAge = now - TRP3FW.lastZoneQueryTime
    local zoneQueryOnCooldown = zoneQueryAge < TRP3FW.Prefs.whoZoneQueryCooldown
    local whoBackoffActive = TRP3FW.nextWhoBackoffUntil and TRP3FW.nextWhoBackoffUntil > now
    local zoneLimitActive = currentZoneName and IsZoneTruncationActive(currentZoneName)

    if zoneQueryOnCooldown or whoBackoffActive or zoneLimitActive then
        local failIfMapFallbackFails = false

        if whoBackoffActive then
            local remaining = TRP3FW.nextWhoBackoffUntil - now
            TRP3FW:Debug("[WHO Query] Backoff active ("..string.format("%.1f", remaining).."s left) - skipping zone query for "..playerName, "who")
            failIfMapFallbackFails = true
        elseif zoneLimitActive then
            TRP3FW:Debug("[WHO Query] Zone truncation window active for zone="..tostring(currentZoneName).." - forcing name/cache fallback for "..playerName, "who")
            forceNameQuery = true
        else
            TRP3FW:Debug("[WHO Query] Zone query on cooldown ("..string.format("%.1f", zoneQueryAge).."s / "..TRP3FW.Prefs.whoZoneQueryCooldown.."s), skipping to name query for "..playerName, "who")
        end
        
        local reasonTag = whoBackoffActive and "who_backoff" or (zoneLimitActive and "zone_truncation") or "zone_cooldown"
        local defaultReason = failIfMapFallbackFails and "who_backoff" or nil

        if fallbackToMap(reasonTag, defaultReason) then
            return
        end
        -- Skip zone query, will try name query below
    end

    -- Cache miss - will do fresh WHO query
    if trackStats then
        TrackWhoCacheStat(sendId, false, playerName)
    end

    -- If query already pending or on cooldown, queue it (dedupe by player, refresh timestamp)
    if TRP3FW.whoQueryPending or TRP3FW.whoQueryCooldown then
        local nowTs = TRP3FW:GetCurrentTime()

        if zoneLimitActive then
            TRP3FW:Debug("[WHO Query] Zone truncation window active - dropping queued zone request for "..playerName, "who")
            if fallbackToMap("zone_truncation_pending", "zone_truncation") then
                return
            end
            if callback then callback(false, "zone_truncation", 0, nil) end
            return
        end

        -- SECURITY: Enforce queue size limit to prevent resource exhaustion
        EnsureWhoQueue()
        local queueSize = GetWhoQueueSize()
        if queueSize >= TRP3FW.Prefs.whoQueueLimit then
            TRP3FW:Debug("[SECURITY] WHO query queue full ("..queueSize.." queries), rejecting new query for "..playerName, "security")
            TRP3FW.nextWhoBackoffUntil = now + WHO_BACKOFF_SECONDS
            if not fallbackToMap("queue_full", "queue_full") then
                if callback then callback(false, "queue_full", 0, nil) end
            end
            return
        end

        -- Dedupe existing entry for same player
        local existingIndex = nil
        local queue = TRP3FW.pendingWhoQueries
        local head = TRP3FW.pendingWhoQueueHead
        for i = head, #queue do
            local entry = queue[i]
            if entry and entry.playerName == playerName then
                existingIndex = i
                break
            end
        end

        if existingIndex then
            local entry = queue[existingIndex]
            entry.sendId = sendId
            entry.callback = callback
            entry.forceNameQuery = forceNameQuery
            entry.trackStats = trackStats
            entry.timestamp = nowTs
            entry.priority = priority -- Update priority if changed
            TRP3FW:Debug("[WHO Query] Updated existing queued request for "..playerName.." (forceNameQuery="..tostring(forceNameQuery)..")", "who")
        else
            TRP3FW:Debug("[WHO Query] Query pending/cooldown, queuing request for "..playerName, "who")
            table.insert(queue, {
                playerName = playerName, 
                sendId = sendId, 
                callback = callback, 
                forceNameQuery = forceNameQuery, 
                trackStats = trackStats, 
                timestamp = nowTs,
                priority = priority -- Store priority
            })
        end
        return
    end

    -- Step 4: Try zone query (if not on cooldown), otherwise fall back to name query
    if not zoneQueryOnCooldown and not forceNameQuery and not whoBackoffActive and not zoneLimitActive then
        TRP3FW:Debug("[WHO Query] Starting zone query for: "..playerName, "who")

        -- Enable WHO output suppression
        TRP3FW.whoQuerySentTime = now

        -- Get current zone for zone-based search
        -- OPTIMIZATION: Use cached zone name instead of API calls
        local zoneName = TRP3FW.currentZoneName
        if not zoneName or zoneName == "" or zoneName == "Unknown" then
            -- Best-effort fallback: resolve from map info and cache it
            local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
            if mapID then
                local info = C_Map.GetMapInfo(mapID)
                if info and info.name and info.name ~= "" then
                    zoneName = info.name
                    if not TRP3FW.currentZoneName then
                        TRP3FW.currentZoneName = zoneName
                    end
                    TRP3FW:Debug("[WHO Query] Resolved zone from map info: "..zoneName, "who")
                end
            end
        end

        if not zoneName or zoneName == "" or zoneName == "Unknown" then
            TRP3FW:Debug("[WHO Query] Zone unknown/stale - forcing name query for "..playerName, "who")
            forceNameQuery = true
        end

        -- Re-evaluate truncation window with the resolved zone name
        zoneLimitActive = IsZoneTruncationActive(zoneName)

        if zoneName and zoneName ~= "" and zoneName ~= "Unknown" and not forceNameQuery and not zoneLimitActive then
            TRP3FW:Debug("[WHO Query] Searching zone: "..zoneName, "who")

            -- Generate unique request ID
            TRP3FW.whoQueryRequestId = TRP3FW.whoQueryRequestId + 1
            local requestId = TRP3FW.whoQueryRequestId

            -- Set pending query
            TRP3FW.whoQueryPending = {
                playerName = playerName,
                callback = callback,
                timestamp = now,
                zoneName = zoneName,
                requestId = requestId,
                isNameQuery = false  -- This is a zone query
            }
            TRP3FW.whoQueryCooldown = true

            TRP3FW:Debug("[WHO Query] Zone request ID: "..requestId, "who")

            -- Update zone query timestamp
            TRP3FW.lastZoneQueryTime = now

            -- SECURITY: Sanitize zone name before use in RunPrivileged
            local sanitizedZone = TRP3FW:SanitizeZoneName(zoneName)
            if not sanitizedZone then
                TRP3FW:Debug("[WHO Query] ERROR: Invalid zone name rejected: "..tostring(zoneName), "who")
                TRP3FW.whoQueryPending = nil
                TRP3FW.whoQueryCooldown = false
                if callback then callback(false, "invalid_zone") end
                return
            end

            -- Send WHO query using privileged call
            -- Query format: z-"ZoneName" searches everyone in that zone
            local whoQuery = 'z-"'..sanitizedZone..'"'
            TRP3FW:Debug("[WHO Query] Sending zone query: "..whoQuery, "who")

            -- Use double brackets to avoid escaping issues
            local privilegedCode = 'C_FriendList.SetWhoToUi(false) C_FriendList.SendWho([['..whoQuery..']])'
            TRP3FW:Debug("[WHO Query] RunPrivileged code: "..privilegedCode, "who")

            -- FIXED: CRITICAL-3 - Use rate-limited safe wrapper (with preflight)
            if not HasPrivilegedCapacity(zoneCategory) then
                TRP3FW:Debug("[WHO Query] Zone query blocked by rate limit preflight ("..tostring(zoneCategory)..")", "who")
                TRP3FW.nextWhoBackoffUntil = now + WHO_BACKOFF_SECONDS
                TRP3FW.whoQueryPending = nil
                TRP3FW.whoQueryCooldown = false
                TRP3FW.suppressWhoOutput = false
                if not fallbackToMap("rate_limit_zone", "rate_limit") and callback then
                    callback(false, "rate_limit", 0, nil)
                end
                return
            end

            local success, err = TRP3FW:RunPrivilegedSafe(privilegedCode, zoneCategory)

            if not success then
                TRP3FW:Debug("[WHO Query] ERROR: Failed to send zone query: "..tostring(err), "who")
                TRP3FW.whoQueryPending = nil
                TRP3FW.whoQueryCooldown = false
                TRP3FW.suppressWhoOutput = false

                local reason = (err == "rate_limit") and "rate_limit" or "error"
                if not fallbackToMap("zone_sendfail_"..reason, reason) and callback then
                    callback(false, reason)
                end
                return
            end

            TRP3FW:Debug("[WHO Query] Zone query sent successfully", "who")

            -- Try to get results immediately (might be synchronous on Epsilon)
            C_Timer.After(0.5, function()
                if TRP3FW.whoQueryPending and TRP3FW.whoQueryPending.requestId == requestId then
                    TRP3FW:Debug("[WHO Query] Checking for immediate results (request "..requestId..")...", "who")
                    local success, numWho = pcall(C_FriendList.GetNumWhoResults)
                    if not success then
                        TRP3FW:Debug("[WHO Query] ERROR: Failed to get WHO results count: "..tostring(numWho), "who")
                        numWho = 0
                    end
                    if numWho and numWho > 0 then
                        TRP3FW:Debug("[WHO Query] Found immediate results! Triggering event manually", "who")
                        -- Manually trigger the event handler since WHO_LIST_UPDATE might not fire on Epsilon
                        whoFrame:GetScript("OnEvent")(whoFrame, "WHO_LIST_UPDATE")
                        return
                    end
                end
            end)

            -- Set timeout (5 seconds)
            C_Timer.After(WHO_TIMEOUT_SECONDS, function()
                if TRP3FW.whoQueryPending and TRP3FW.whoQueryPending.requestId == requestId then
                    TRP3FW:Debug("[WHO Query] Timeout for "..playerName, "who")
                    TRP3FW.nextWhoBackoffUntil = TRP3FW:GetCurrentTime() + WHO_BACKOFF_SECONDS
                    TRP3FW.whoQueryPending = nil
                    TRP3FW.whoQueryCooldown = false

                    -- Disable WHO output suppression on timeout
                    TRP3FW.suppressWhoOutput = false

                    -- Treat timeout as unknown location (don't cache negative result)
                    if not fallbackToMap("zone_timeout", nil) and callback then
                        callback(nil, "timeout", 0, nil)
                    end

                    -- Process queued queries - check cache first for each (uses head index)
                    EnsureWhoQueue()
                    local queueIndex = TRP3FW.pendingWhoQueueHead
                    local queue = TRP3FW.pendingWhoQueries
                    while queueIndex <= #queue do
                        local nextQuery = queue[queueIndex]
                        queueIndex = queueIndex + 1

                        -- Drop stale queued entries
                        if IsQueueEntryStale(nextQuery) then
                            TRP3FW:Debug("[WHO Query] Dropping stale queued request for "..tostring(nextQuery.playerName), "who")
                        else
                            -- Check if this queued player is already cached
                            local cached, cacheType, age = CheckWhoCaches(nextQuery.playerName)

                            if cached then
                                -- Already cached! Execute callback immediately and track stats if requested
                                TRP3FW:Debug("[WHO Query] Queued player "..nextQuery.playerName.." found in "..cacheType.." cache after timeout, executing callback immediately", "who")
                                if nextQuery.trackStats then
                                    TrackWhoCacheStat(nextQuery.sendId or 0, true, nextQuery.playerName)
                                end
                                if nextQuery.callback then
                                    local ageNow = TRP3FW:GetCurrentTime() - cached.timestamp
                                    nextQuery.callback(cached.found, "cached", ageNow)
                                end
                                -- Continue to next queued query
                            else
                                -- Not cached, need to do WHO query
                                TRP3FW:Debug("[WHO Query] Queued player "..nextQuery.playerName.." not cached after timeout, scheduling WHO query", "who")
                                C_Timer.After(WHO_QUERY_DELAY, function()
                                    CheckPlayerViaWho(nextQuery.playerName, nextQuery.sendId or 0, nextQuery.callback, nextQuery.trackStats, nextQuery.forceNameQuery, nextQuery.priority)
                                end)
                                break -- Only schedule one query at a time
                            end
                        end
                    end

                    -- Advance head and compact when needed
                    AdvanceWhoQueue(queueIndex)
                end
            end)
        else
            -- Zone still unknown after fallback
            forceNameQuery = true
        end
    end

    if zoneQueryOnCooldown or forceNameQuery then
        -- Step 5: Zone query is on cooldown or explicitly skipped, go directly to name query
        TRP3FW:Debug("[WHO Query] "..(forceNameQuery and "Forcing" or "Zone on cooldown, sending").." name query for: "..playerName, "who")

        -- Generate new request ID for name query
        TRP3FW.whoQueryRequestId = TRP3FW.whoQueryRequestId + 1
        local nameRequestId = TRP3FW.whoQueryRequestId

        -- Enable WHO output suppression
        TRP3FW.whoQuerySentTime = now

        -- Set up for name query
        TRP3FW.whoQueryPending = {
            playerName = playerName,
            callback = callback,
            timestamp = now,
            isNameQuery = true,  -- Flag to indicate this is a name-based query
            requestId = nameRequestId
        }
        TRP3FW.whoQueryCooldown = true

        TRP3FW:Debug("[WHO Query] Name request ID: "..nameRequestId, "who")

        -- Send name-based WHO query
        local whoQuery = 'n-"'..sanitizedName..'"'
        TRP3FW:Debug("[WHO Query] Sending name query: "..whoQuery, "who")

        -- Use double brackets to avoid escaping issues
        local privilegedCode = 'C_FriendList.SetWhoToUi(false) C_FriendList.SendWho([['..whoQuery..']])'

        -- FIXED: CRITICAL-3 - Use rate-limited safe wrapper (with preflight)
        if not HasPrivilegedCapacity(nameFallbackCategory) then
            TRP3FW:Debug("[WHO Query] Name query fallback blocked by rate limit preflight ("..tostring(nameFallbackCategory)..")", "who")
            TRP3FW.whoQueryPending = nil
            TRP3FW.whoQueryCooldown = false
            TRP3FW.suppressWhoOutput = false
            if not fallbackToMap("rate_limit_name", "rate_limit") and callback then
                callback(false, "rate_limit", 0, nil)
            end
            return
        end

        local success, err = TRP3FW:RunPrivilegedSafe(privilegedCode, nameFallbackCategory)

        if not success then
            TRP3FW:Debug("[WHO Query] ERROR: Failed to send name query: "..tostring(err), "who")
            TRP3FW.whoQueryPending = nil
            TRP3FW.whoQueryCooldown = false
            TRP3FW.suppressWhoOutput = false

            -- Cache negative result in name cache
            local CI = TRP3FW.CacheInterface
            if CI then
                CI:Set("whoName", playerName, {
                    found = false,
                    zone = nil,
                    timestamp = now
                })
                TRP3FW:Debug("[Cache Add] whoNameCache: Added "..playerName.." (NOT FOUND - error)", "cache")
            end

            local reason = (err == "rate_limit") and "rate_limit" or "error"
            if callback then callback(false, reason, 0, nil) end
            return
        end

        TRP3FW:Debug("[WHO Query] Name query sent successfully", "who")

        -- Try to get results immediately
        C_Timer.After(0.5, function()
            if TRP3FW.whoQueryPending and TRP3FW.whoQueryPending.requestId == nameRequestId then
                TRP3FW:Debug("[WHO Query] Checking for immediate name query results (request "..nameRequestId..")...", "who")
                local success, numWho = pcall(C_FriendList.GetNumWhoResults)
                if not success then
                    TRP3FW:Debug("[WHO Query] ERROR: Failed to get WHO results count: "..tostring(numWho), "who")
                    numWho = 0
                end
                if numWho and numWho > 0 then
                    TRP3FW:Debug("[WHO Query] Found immediate results! Triggering event manually", "who")
                    whoFrame:GetScript("OnEvent")(whoFrame, "WHO_LIST_UPDATE")
                    return
                end
            end
        end)

        -- Set timeout (5 seconds)
        C_Timer.After(WHO_TIMEOUT_SECONDS, function()
            if TRP3FW.whoQueryPending and TRP3FW.whoQueryPending.requestId == nameRequestId then
                TRP3FW:Debug("[WHO Query] Name query timeout for "..playerName.." (request "..nameRequestId..")", "who")
                TRP3FW.whoQueryPending = nil
                TRP3FW.whoQueryCooldown = false
                TRP3FW.suppressWhoOutput = false

                -- Cache negative result in name cache (timeout on name query)
                local CI = TRP3FW.CacheInterface
                if CI then
                    CI:Set("whoName", playerName, {
                        found = false,
                        zone = nil,
                        timestamp = now
                    })
                    TRP3FW:Debug("[Cache Add] whoNameCache: Added "..playerName.." (NOT FOUND - timeout)", "cache")
                end

                if callback then callback(false, "timeout", 0, nil) end
            end
        end)
    end
end

-- Scan zone for all players (for /trp3fw phasecheck command)
function TRP3FW:ScanZoneForPlayers(callback)
    if not self.hasEpsilonAPI then
        TRP3FW:Debug("[WHO Zone Scan] Epsilon API not available", "who")
        if callback then callback(false, {}, "unavailable") end
        return
    end

    -- Check if a query is already pending
    if self.whoQueryPending then
        TRP3FW:Debug("[WHO Zone Scan] Query already pending, cannot start zone scan", "who")
        if callback then callback(false, {}, "query_pending") end
        return
    end

    -- Get current zone name
    local zoneName = self.currentZoneName
    if not zoneName or zoneName == "" or zoneName == "Unknown" then
        -- Fallback: resolve from map info
        local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if mapID then
            local info = C_Map.GetMapInfo(mapID)
            if info and info.name and info.name ~= "" then
                zoneName = info.name
                self.currentZoneName = zoneName
                TRP3FW:Debug("[WHO Zone Scan] Resolved zone from map info: "..zoneName, "who")
            end
        end
    end

    if not zoneName or zoneName == "" or zoneName == "Unknown" then
        TRP3FW:Debug("[WHO Zone Scan] Cannot determine current zone", "who")
        if callback then callback(false, {}, "unknown_zone") end
        return
    end

    -- Generate unique request ID
    self.whoQueryRequestId = self.whoQueryRequestId + 1
    local requestId = self.whoQueryRequestId

    local now = self:GetCurrentTime()

    -- Set up scan mode query
    self.whoQueryPending = {
        playerName = "__ZONE_SCAN__",  -- Special marker for zone scans
        callback = callback,
        timestamp = now,
        zoneName = zoneName,
        requestId = requestId,
        isNameQuery = false,
        scanMode = true,  -- NEW: Flag for zone scan mode
        results = {}      -- NEW: Collect all player names here
    }
    self.whoQueryCooldown = true
    self.whoQuerySentTime = now

    TRP3FW:Debug("[WHO Zone Scan] Zone scan request ID: "..requestId.." for zone: "..zoneName, "who")

    -- Update zone query timestamp
    self.lastZoneQueryTime = now

    -- SECURITY: Sanitize zone name
    local sanitizedZone = self:SanitizeZoneName(zoneName)
    if not sanitizedZone then
        TRP3FW:Debug("[WHO Zone Scan] ERROR: Invalid zone name rejected: "..tostring(zoneName), "who")
        self.whoQueryPending = nil
        self.whoQueryCooldown = false
        if callback then callback(false, {}, "invalid_zone") end
        return
    end

    -- Send WHO query
    local whoQuery = 'z-"'..sanitizedZone..'"'
    TRP3FW:Debug("[WHO Zone Scan] Sending zone scan query: "..whoQuery, "who")

    local privilegedCode = 'C_FriendList.SetWhoToUi(false) C_FriendList.SendWho([['..whoQuery..']])'

    -- Check token capacity
    if not HasPrivilegedCapacity("who_zone_scan") then
        TRP3FW:Debug("[WHO Zone Scan] Blocked by rate limit preflight", "who")
        self.whoQueryPending = nil
        self.whoQueryCooldown = false
        self.suppressWhoOutput = false
        if callback then callback(false, {}, "rate_limit") end
        return
    end

    local success, err = self:RunPrivilegedSafe(privilegedCode, "who_zone_scan")

    if not success then
        TRP3FW:Debug("[WHO Zone Scan] ERROR: Failed to send zone scan query: "..tostring(err), "who")
        self.whoQueryPending = nil
        self.whoQueryCooldown = false
        self.suppressWhoOutput = false
        if callback then callback(false, {}, err or "error") end
        return
    end

    TRP3FW:Debug("[WHO Zone Scan] Zone scan query sent successfully", "who")

    -- Try to get results immediately
    C_Timer.After(0.5, function()
        if self.whoQueryPending and self.whoQueryPending.requestId == requestId then
            TRP3FW:Debug("[WHO Zone Scan] Checking for immediate results (request "..requestId..")...", "who")
            local success, numWho = pcall(C_FriendList.GetNumWhoResults)
            if success and numWho and numWho > 0 then
                TRP3FW:Debug("[WHO Zone Scan] Found immediate results! Triggering event manually", "who")
                whoFrame:GetScript("OnEvent")(whoFrame, "WHO_LIST_UPDATE")
                return
            end
        end
    end)

    -- Set timeout
    C_Timer.After(WHO_TIMEOUT_SECONDS, function()
        if self.whoQueryPending and self.whoQueryPending.requestId == requestId then
            TRP3FW:Debug("[WHO Zone Scan] Timeout for zone scan (request "..requestId..")", "who")
            self.whoQueryPending = nil
            self.whoQueryCooldown = false
            self.suppressWhoOutput = false
            if callback then callback(false, {}, "timeout") end
        end
    end)
end

-- Export the function
function TRP3FW:CheckPlayerViaWho(playerName, sendId, callback, trackStats, forceNameQuery)
    return CheckPlayerViaWho(playerName, sendId, callback, trackStats, forceNameQuery)
end
