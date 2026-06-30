-- features/services/WhoService.lua
-- WHO Engine: Manages WHO queries, queuing, and result processing

local addonName, TRP3FW = ...

local WhoService = TRP3FW.Service:New("WhoService")

-- Constants (Mirrored from location/who.lua)
local WHO_RESULT_LIMIT = 50
local WHO_TIMEOUT_SECONDS = 5
local WHO_QUERY_DELAY = 0.5
local WHO_BACKOFF_SECONDS = 10
local WHO_ZONE_LIMIT_WINDOW = 60
local WHO_ZONE_LIMIT_HITS = 2

function WhoService:Initialize()
    TRP3FW.Service.Initialize(self)

    self.pendingQuery = nil
    self.queryQueue = {}
    self.queueHead = 1
    self.lastZoneQueryTime = 0
    self.nextBackoffUntil = 0
    self.requestId = 0
    self.cooldownActive = false

    self.zoneLimitState = { zoneName = nil, hits = 0, untilTs = 0, lastHit = 0 }
    self.lastZoneQueryTime = 0
    self.lastZoneResultCount = 0

    self:InitializeSuppression()

    -- NOTE: Caches are already registered in core/init.lua:InitializeCaches()
    -- No need to re-register here as it would overwrite the configuration

    -- Register for events
    local ES = TRP3FW.ServiceContainer:Get("EventService")
    if ES then
        ES:RegisterCallback("WHO_LIST_UPDATE", function() self:OnWhoListUpdate() end)
        ES:RegisterCallback("CHAT_MSG_SYSTEM", function(event, msg) self:OnChatMsgSystem(msg) end)
    end
end

function WhoService:OnChatMsgSystem(msg)
    if not self.pendingQuery then return end

    TRP3FW:Debug("[WhoService] CHAT_MSG_SYSTEM (pending query): "..tostring(msg), "who")

    -- Check for "Players found" or "Online Players" patterns which indicate results are ready
    if msg:find("found") or msg:find("Players") or msg:find("Online") then
        TRP3FW:Debug("[WhoService] Detected WHO results via chat message, triggering OnWhoListUpdate", "who")
        -- Small delay to ensure C_FriendList has the data
        C_Timer.After(0.1, function() self:OnWhoListUpdate() end)
    end
end

-- ===================== Suppression Logic =====================

function WhoService:InitializeSuppression()
    local WHO_SUPPRESSION_WINDOW = 5
    local originalWhoListUpdate = WhoList_Update

    local function ShouldSuppressChatOutput()
        if TRP3FW.Prefs and TRP3FW.Prefs.suppressAllWhoOutput then return true end
        local timeSinceQuery = TRP3FW:GetCurrentTime() - (TRP3FW.whoQuerySentTime or 0)
        return timeSinceQuery < WHO_SUPPRESSION_WINDOW
    end

    local function ShouldSuppressWhoOutput()
        local timeSinceQuery = TRP3FW:GetCurrentTime() - (TRP3FW.whoQuerySentTime or 0)
        return timeSinceQuery < WHO_SUPPRESSION_WINDOW
    end

    -- SECURITY: Class/race set for WHO message filtering
    local CLASS_RACE_SET = {
        ["Death Knight"] = true, ["Demon Hunter"] = true, ["Night Elf"] = true, ["Void Elf"] = true,
        ["Lightforged Draenei"] = true, ["Dark Iron Dwarf"] = true, ["Kul Tiran"] = true, ["Earthen"] = true,
        ["Blood Elf"] = true, ["Highmountain Tauren"] = true, ["Mag'har Orc"] = true, ["Zandalari Troll"] = true,
        ["Druid"] = true, ["Evoker"] = true, ["Hunter"] = true, ["Mage"] = true, ["Monk"] = true,
        ["Paladin"] = true, ["Priest"] = true, ["Rogue"] = true, ["Shaman"] = true, ["Warlock"] = true,
        ["Warrior"] = true, ["Human"] = true, ["Dwarf"] = true, ["Gnome"] = true, ["Draenei"] = true,
        ["Worgen"] = true, ["Mechagnome"] = true, ["Dracthyr"] = true, ["Orc"] = true, ["Undead"] = true,
        ["Tauren"] = true, ["Troll"] = true, ["Goblin"] = true, ["Nightborne"] = true, ["Vulpera"] = true,
        ["Pandaren"] = true
    }

    local function ContainsClassOrRace(msg)
        local msgLower = msg:lower()
        for classOrRace in pairs(CLASS_RACE_SET) do
            if msgLower:find(classOrRace:lower(), 1, true) then return true end
        end
        return false
    end

    WhoList_Update = function()
        if not ShouldSuppressWhoOutput() then
            if originalWhoListUpdate then originalWhoListUpdate() end
        end
    end

    local function FilterWhoMessages(self, event, msg, ...)
        if ShouldSuppressChatOutput() then
            if (msg:find("player") and (msg:find("total") or msg:find("found"))) then return true end
            if msg:match("^%d+%. [%w]+") then return true end
            if msg:find("^%[", 1, false) and msg:find("%]: Level ", 1, false) and msg:find(" %- ", 1, false) then
                if ContainsClassOrRace(msg) then return true end
            end
            if msg:find("Online Players") or msg:find("Players found") then return true end
            if msg:match("[Ww]ho [Ll]ist") or msg:match("WHO") then return true end
            if msg:find(" %- Level ", 1, false) and msg:find("%(", 1, false) and msg:find("%)$", 1, false) then
                if ContainsClassOrRace(msg) then return true end
            end
            if msg:find("Level %d", 1, false) and ContainsClassOrRace(msg) and (msg:find(" %- ", 1, false) or msg:find("%(", 1, false)) then
                return true
            end
        end
        return false
    end

    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", FilterWhoMessages)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_TEXT_EMOTE", FilterWhoMessages)
end

-- ===================== Queue Management =====================

function WhoService:GetQueueSize()
    local tail = #self.queryQueue
    if tail < self.queueHead then return 0 end
    return tail - self.queueHead + 1
end

function WhoService:AdvanceQueue(newHead)
    self.queueHead = newHead
    local tail = #self.queryQueue

    -- Compact when head has advanced far enough
    if newHead > 64 and newHead > (tail / 2) then
        local compacted = {}
        for i = newHead, tail do
            compacted[#compacted + 1] = self.queryQueue[i]
        end
        self.queryQueue = compacted
        self.queueHead = 1
    end
end

function WhoService:ProcessQueue()
    if self.pendingQuery or self.cooldownActive then return end

    local size = self:GetQueueSize()
    if size == 0 then return end

    local nextQuery = self.queryQueue[self.queueHead]
    self:AdvanceQueue(self.queueHead + 1)

    -- Check if stale
    local now = TRP3FW:GetCurrentTime()
    if (now - nextQuery.timestamp) > 60 then
        TRP3FW:Debug("[WhoService] Dropping stale queued query for "..tostring(nextQuery.playerName), "who")
        if nextQuery.callback then nextQuery.callback(false, "queue_timeout") end
        self:ProcessQueue()
        return
    end

    -- Execute
    TRP3FW:Debug("[WhoService] Processing queued query for "..tostring(nextQuery.playerName), "who")
    self:CheckPlayer(nextQuery.playerName, nextQuery.sendId, nextQuery.callback, nextQuery.trackStats, nextQuery.forceNameOnly, nextQuery.priority)
end

-- ===================== Core Engine =====================

function WhoService:CheckPlayer(playerName, sendId, callback, trackStats, forceNameOnly, priority)
    if not TRP3FW.hasEpsilonAPI then
        if callback then callback(false, "unavailable") end
        return
    end

    -- SECURITY: Canonicalize/sanitize input once; reuse everywhere to avoid unsanitized WHO payloads
    local cleanName = TRP3FW:CleanPlayerName(playerName)
    local sanitizedName = cleanName and TRP3FW:SanitizePlayerName(cleanName) or nil
    if not cleanName or not sanitizedName then
        if callback then callback(false, "invalid_name") end
        return
    end
    playerName = cleanName

    local now = TRP3FW:GetCurrentTime()

    -- 1. Check caches first (Delegated to a helper similar to who.lua)
    local CI = TRP3FW.CacheInterface
    local cached = CI and CI:Get("whoName", playerName)

    if cached then
        local age = now - cached.timestamp
        -- Background Refresh logic if aging
        local ttl = TRP3FW.Prefs.whoNameCacheDuration or 180
        local refreshThreshold = TRP3FW.Prefs.whoCacheRefreshThreshold or 50

        if age > (ttl * (refreshThreshold / 100)) then
             TRP3FW:Debug("[WhoService] Cache entry aging - triggering background refresh for "..playerName, "who")
             self:CheckPlayer(playerName, nil, nil, false, true, "who_refresh_low")
        end

        -- Track cache hit stats (deduplicate by sendId)
        if not TRP3FW.lastWhoCacheSendId then
            TRP3FW.lastWhoCacheSendId = {}
        end

        if sendId and not TRP3FW.lastWhoCacheSendId[sendId] then
            -- First time seeing this sendId for WHO cache - count it
            TRP3FW.sessionStats.cacheStats.whoCacheHits = TRP3FW.sessionStats.cacheStats.whoCacheHits + 1
            TRP3FW.lastWhoCacheSendId[sendId] = true
            TRP3FW:Debug("whoCache HIT for "..playerName.." (sendId: "..tostring(sendId)..")", "cache")
        elseif sendId then
            -- Already counted this sendId for WHO cache - skip
            TRP3FW:Debug("Duplicate sendId "..tostring(sendId).." already counted for whoCache, skipping stat increment", "cache")
        end

        if callback then callback(cached.found, "cached", age, cached.zone) end
        return
    end

    -- NEW: Reliable Zone Truncation check
    -- If we have a fresh whoZone result for the current zone, and it wasn't truncated ( < 50 results),
    -- we can assume a "Not Found" in whoName is a definitive "Not in Zone" without a new query.
    local currentZone = TRP3FW.currentZoneName
    if currentZone and currentZone ~= "" and currentZone ~= "Unknown" then
        local zoneCache = CI and CI:Get("whoZone", playerName) -- This actually checks if PLAYER is in zone cache
        -- We need to know if the ZONE ITSELF was scanned recently.
        -- WhoService tracks this via self.lastZoneQueryTime and self.lastZoneResultCount
        local zoneAge = now - (self.lastZoneQueryTime or 0)
        local zoneTTL = 60 -- Only trust "completeness" of a zone scan for 60 seconds

        if zoneAge < zoneTTL and self.lastZoneResultCount and self.lastZoneResultCount < WHO_RESULT_LIMIT then
             -- The last zone scan was recent and complete. If they aren't in whoName/whoZone cache, they aren't here.
             TRP3FW:Debug("[WhoService] Zone scan was recent ("..zoneAge.."s) and complete ("..self.lastZoneResultCount.." results). Skipping query for "..playerName, "who")

             -- Track cache hit stats (zone completeness is a cached result)
             if not TRP3FW.lastWhoCacheSendId then
                 TRP3FW.lastWhoCacheSendId = {}
             end

             if sendId and not TRP3FW.lastWhoCacheSendId[sendId] then
                 -- First time seeing this sendId for WHO cache - count it
                 TRP3FW.sessionStats.cacheStats.whoCacheHits = TRP3FW.sessionStats.cacheStats.whoCacheHits + 1
                 TRP3FW.lastWhoCacheSendId[sendId] = true
                 TRP3FW:Debug("whoCache HIT (zone complete) for "..playerName.." (sendId: "..tostring(sendId)..")", "cache")
             elseif sendId then
                 -- Already counted this sendId for WHO cache - skip
                 TRP3FW:Debug("Duplicate sendId "..tostring(sendId).." already counted for whoCache, skipping stat increment", "cache")
             end

             if callback then callback(false, "cached_zone_complete", zoneAge, nil) end
             return
        end
    end

    -- 2. If query already pending or on cooldown, queue it
    if self.pendingQuery or self.cooldownActive then
        -- Enforce queue size limit
        if self:GetQueueSize() >= (TRP3FW.Prefs.whoQueueLimit or 100) then
            TRP3FW:Debug("[WhoService] Queue full, rejecting query for "..playerName, "security")
            if callback then callback(false, "queue_full") end
            return
        end

        -- Dedupe existing entry
        for i = self.queueHead, #self.queryQueue do
            if self.queryQueue[i].playerName == playerName then
                self.queryQueue[i] = { playerName = playerName, sendId = sendId, callback = callback, trackStats = trackStats, forceNameOnly = forceNameOnly, priority = priority, timestamp = now }
                return
            end
        end

        -- Priority Insertion: HIGH priority jumps to the front of the queue
        if priority == "HIGH" then
            table.insert(self.queryQueue, self.queueHead, { playerName = playerName, sendId = sendId, callback = callback, trackStats = trackStats, forceNameOnly = forceNameOnly, priority = priority, timestamp = now })
            TRP3FW:Debug("[WhoService] Enqueued HIGH priority query for "..playerName.." at head of queue", "who")
        else
            table.insert(self.queryQueue, { playerName = playerName, sendId = sendId, callback = callback, trackStats = trackStats, forceNameOnly = forceNameOnly, priority = priority, timestamp = now })
        end
        return
    end

    -- Cache miss - will execute fresh query
    -- Track cache miss stats (deduplicate by sendId)
    if not TRP3FW.lastWhoCacheSendId then
        TRP3FW.lastWhoCacheSendId = {}
    end

    if sendId and not TRP3FW.lastWhoCacheSendId[sendId] then
        -- First time seeing this sendId for WHO cache - count it
        TRP3FW.sessionStats.cacheStats.whoCacheMisses = TRP3FW.sessionStats.cacheStats.whoCacheMisses + 1
        TRP3FW.lastWhoCacheSendId[sendId] = true
        TRP3FW:Debug("whoCache MISS for "..playerName.." (sendId: "..tostring(sendId)..")", "cache")
    elseif sendId then
        -- Already counted this sendId for WHO cache - skip
        TRP3FW:Debug("Duplicate sendId "..tostring(sendId).." already counted for whoCache, skipping stat increment", "cache")
    end

    -- 3. Execute WHO Query
    local zoneName = TRP3FW.currentZoneName
    local useZoneQuery = not forceNameOnly and zoneName and zoneName ~= "" and zoneName ~= "Unknown"

    TRP3FW:Debug("[WhoService] Query decision - forceNameOnly="..tostring(forceNameOnly)..", zoneName="..tostring(zoneName)..", useZoneQuery="..tostring(useZoneQuery), "who")

    -- NEW: Prioritize whozone if stale, not truncated, and cooldown is up
    -- This allows us to refresh knowledge of the whole zone (better for multiple scanners)
    -- rather than just querying one person, provided the zone is small enough to not be truncated.
    if not useZoneQuery and zoneName and zoneName ~= "" and zoneName ~= "Unknown" then
        local zoneAge = now - (self.lastZoneQueryTime or 0)
        local cooldown = TRP3FW.Prefs.whoZoneQueryCooldown or 20
        -- "not truncated" check (last result count < 50)
        local wasNotTruncated = (not self.lastZoneResultCount or self.lastZoneResultCount < WHO_RESULT_LIMIT)

        if zoneAge >= cooldown and wasNotTruncated then
            TRP3FW:Debug("[WhoService] Prioritizing zone refresh over name query (Stale/Not Truncated)", "who")
            useZoneQuery = true
        end
    end

    -- Zone query cooldown check
    if useZoneQuery and (now - (self.lastZoneQueryTime or 0)) < (TRP3FW.Prefs.whoZoneQueryCooldown or 20) then
        useZoneQuery = false
    end

    -- Construction
    -- Use obfuscated call from Epsilon diagnostics manual to bypass potential string-matching filters
    -- Standard Blizzard WHO query format (z- for zone, n- for name)
    local whoQuery = useZoneQuery and ('z-"'..zoneName..'"') or ('n-"'..sanitizedName..'"')
    local category = priority or (useZoneQuery and "who_zone_query" or "who_name_query")

    -- Execute SetWhoToUi and SendWho as separate statements with semicolon separator
    local privilegedCode = 'C_FriendList.SetWhoToUi(false); C_FriendList.SendWho([['..whoQuery..']])'

    self.requestId = self.requestId + 1
    local currentReqId = self.requestId

    self.pendingQuery = {
        playerName = playerName,
        callback = callback,
        timestamp = now,
        requestId = currentReqId,
        isNameQuery = not useZoneQuery,
        zoneName = useZoneQuery and zoneName or nil
    }
    self.cooldownActive = true
    if useZoneQuery then self.lastZoneQueryTime = now end

    TRP3FW.whoQuerySentTime = now -- For suppression

    TRP3FW:Debug("[WhoService] Executing WHO query: "..whoQuery.." (useZoneQuery="..tostring(useZoneQuery)..")", "who")
    TRP3FW:Debug("[WhoService] Privileged code: "..privilegedCode, "who")

    local success, err = TRP3FW:RunPrivilegedSafe(privilegedCode, category)
    if not success then
        TRP3FW:Debug("[WhoService] RunPrivileged failed: "..tostring(err), "who")
        self.pendingQuery = nil
        self.cooldownActive = false
        if callback then callback(false, err or "error") end
        self:ProcessQueue()
        return
    end

    TRP3FW:Debug("[WhoService] RunPrivileged succeeded, waiting for WHO_LIST_UPDATE event", "who")

    -- DIAGNOSTIC: Check if results are immediately available (testing if WHO_LIST_UPDATE fires)
    C_Timer.After(0.5, function()
        if self.pendingQuery and self.pendingQuery.requestId == currentReqId then
            local ok, numWho = pcall(C_FriendList.GetNumWhoResults)
            if ok and numWho and numWho > 0 then
                TRP3FW:Debug("[WhoService] DIAGNOSTIC: WHO results available ("..tostring(numWho)..") but WHO_LIST_UPDATE hasn't fired yet!", "who")
                -- Manually trigger processing since event didn't fire
                self:OnWhoListUpdate()
            else
                TRP3FW:Debug("[WhoService] DIAGNOSTIC: No results yet after 0.5s", "who")
            end
        end
    end)

    -- Timeout handling
    C_Timer.After(WHO_TIMEOUT_SECONDS, function()
        if self.pendingQuery and self.pendingQuery.requestId == currentReqId then
            TRP3FW:Debug("[WhoService] Query timeout for "..self.pendingQuery.playerName, "who")
            local cb = self.pendingQuery.callback
            self.pendingQuery = nil
            self.cooldownActive = false
            if cb then cb(false, "timeout") end
            self:ProcessQueue()
        end
    end)
end

function WhoService:OnWhoListUpdate()
    if not self.pendingQuery then
        TRP3FW:Debug("[WhoService] OnWhoListUpdate called but no pending query", "who")
        return
    end

    local start = debugprofilestop()
    local pending = self.pendingQuery
    self.pendingQuery = nil
    self.cooldownActive = false

    TRP3FW:Debug("[WhoService] OnWhoListUpdate processing results for "..tostring(pending.playerName), "who")

    local now = TRP3FW:GetCurrentTime()
    local CI = TRP3FW.CacheInterface
    local currentZone = pending.zoneName or TRP3FW.currentZoneName

    local success, numWho, totalWho = pcall(C_FriendList.GetNumWhoResults)
    if not success or not numWho or numWho < 0 then
        TRP3FW:Debug("[WhoService] GetNumWhoResults failed or returned invalid count", "who")
        if pending.callback then pending.callback(false, "api_error") end
        self:ProcessQueue()
        return
    end

    TRP3FW:Debug("[WhoService] WHO results: "..tostring(numWho).." players found", "who")

    -- Update last zone scan state if applicable
    if not pending.isNameQuery or pending.scanMode then
        self.lastZoneResultCount = numWho
        TRP3FW:Debug("[WhoService] Last zone scan found "..numWho.." players.", "who")

        -- NEW: Store an entry in whoZone cache for the zone itself
        -- This marks the zone as "scanned" and populates the Status tab count.
        if CI and not pending.isNameQuery and currentZone then
            CI:Set("whoZone", currentZone, {
                timestamp = now,
                count = numWho,
                isFull = (numWho >= WHO_RESULT_LIMIT)
            })
            TRP3FW:Debug("[WhoService] Cached zone metadata for "..tostring(currentZone).." (count="..tostring(numWho)..")", "cache")
        end
    end

    local found = false
    local zone = nil
    local playerList = {} -- For scanMode
    local myName = UnitName("player")

    local cachedCount = 0
    for i = 1, numWho do
        local ok, info = pcall(C_FriendList.GetWhoInfo, i)
        if ok and info and info.fullName then
            local name = TRP3FW:CleanPlayerName(info.fullName)
            if name then
                -- Update caches
                if CI then
                    -- Always update whoName cache for any result found
                    CI:Set("whoName", name, { found = true, zone = info.area, timestamp = now, mapID = nil })

                    -- Populate whoZone if this was a zone-wide scan (prepopulate or scanMode)
                    if not pending.isNameQuery or pending.scanMode then
                        CI:Set("whoZone", name, { found = true, zone = info.area, timestamp = now, mapID = nil })
                    end
                    cachedCount = cachedCount + 1
                end

                -- Collect names for zone scans (scanMode consumers iterate this list)
                if pending.scanMode and name ~= myName then
                    playerList[#playerList + 1] = name
                end

                if name == pending.playerName then
                    found = true
                    zone = info.area
                end
            end
        end
    end

    TRP3FW:Debug("[WhoService] Cached "..tostring(cachedCount).." player results", "cache")

    -- Handle callback
    if pending.scanMode then
        if pending.callback then pending.callback(true, playerList) end
        self:ProcessQueue()
    elseif not found and not pending.isNameQuery and numWho >= WHO_RESULT_LIMIT then
        -- Truncated results - need name query
        TRP3FW:Debug("[WhoService] Zone results truncated, scheduling name query for "..pending.playerName, "who")
        C_Timer.After(2.0, function()
            self:CheckPlayer(pending.playerName, nil, pending.callback, false, true, "who_name_fallback")
        end)
    else
        -- Cache negative results (player not found)
        if not found and CI and pending.playerName then
            -- Cache as not found in whoName cache
            CI:Set("whoName", pending.playerName, {
                found = false,
                zone = currentZone,
                timestamp = now,
                mapID = nil
            })
            TRP3FW:Debug("[WhoService] Cached negative result for "..pending.playerName, "who")
        end

        if pending.callback then
            pending.callback(found, "who_query", 0, zone)
        end
        self:ProcessQueue()
    end

    local hs = TRP3FW.ServiceContainer:Get("HistoryService")
    if hs then hs:RecordPerformance(debugprofilestop() - start, "WHO Result Processing") end
end

function WhoService:ScanZoneForPlayers(callback)
    if not TRP3FW.hasEpsilonAPI then
        if callback then callback(false, {}, "unavailable") end
        return
    end

    if self.pendingQuery then
        if callback then callback(false, {}, "query_pending") end
        return
    end

    local zoneName = TRP3FW.currentZoneName
    if not zoneName or zoneName == "" or zoneName == "Unknown" then
        if callback then callback(false, {}, "unknown_zone") end
        return
    end

    local sanitizedZone = TRP3FW:SanitizeZoneName(zoneName)
    if not sanitizedZone then
        if callback then callback(false, {}, "invalid_zone") end
        return
    end

    local now = TRP3FW:GetCurrentTime()
    self.requestId = self.requestId + 1
    local currentReqId = self.requestId

    self.pendingQuery = {
        playerName = "__ZONE_SCAN__",
        callback = callback,
        timestamp = now,
        requestId = currentReqId,
        isNameQuery = false,
        scanMode = true,
        zoneName = zoneName
    }
    self.cooldownActive = true
    self.lastZoneQueryTime = now
    TRP3FW.whoQuerySentTime = now

    local whoQuery = 'z-"'..sanitizedZone..'"'
    local privilegedCode = 'C_FriendList.SetWhoToUi(false); C_FriendList.SendWho([['..whoQuery..']])'

    local success, err = TRP3FW:RunPrivilegedSafe(privilegedCode, "who_zone_scan")
    if not success then
        self.pendingQuery = nil
        self.cooldownActive = false
        if callback then callback(false, {}, err or "error") end
        return
    end

    C_Timer.After(WHO_TIMEOUT_SECONDS, function()
        if self.pendingQuery and self.pendingQuery.requestId == currentReqId then
            local cb = self.pendingQuery.callback
            self.pendingQuery = nil
            self.cooldownActive = false
            if cb then cb(false, {}, "timeout") end
        end
    end)
end

TRP3FW.ServiceContainer:Register(WhoService)
