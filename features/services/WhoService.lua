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
    
    -- Zone Truncation State
    self.zoneLimitState = { zoneName = nil, hits = 0, untilTs = 0, lastHit = 0 }

    self:InitializeSuppression()

    -- Register for events
    local ES = TRP3FW.ServiceContainer:Get("EventService")
    if ES then
        ES:RegisterCallback("WHO_LIST_UPDATE", function() self:OnWhoListUpdate() end)
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
    local cached = CI and (CI:Get("whoName", playerName) or CI:Get("whoZone", playerName))
    
    if cached then
        local age = now - cached.timestamp
        -- Background Refresh logic if aging
        local ttl = TRP3FW.Prefs.whoNameCacheDuration or 180
        local refreshThreshold = TRP3FW.Prefs.whoCacheRefreshThreshold or 50
        
        if age > (ttl * (refreshThreshold / 100)) then
             TRP3FW:Debug("[WhoService] Cache entry aging - triggering background refresh for "..playerName, "who")
             self:CheckPlayer(playerName, nil, nil, false, true, "who_refresh_low")
        end

        if callback then callback(cached.found, "cached", age, cached.zone) end
        return
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

        table.insert(self.queryQueue, { playerName = playerName, sendId = sendId, callback = callback, trackStats = trackStats, forceNameOnly = forceNameOnly, priority = priority, timestamp = now })
        return
    end

    -- 3. Execute WHO Query
    local zoneName = TRP3FW.currentZoneName
    local useZoneQuery = not forceNameOnly and zoneName and zoneName ~= "" and zoneName ~= "Unknown"
    
    -- Zone query cooldown check
    if useZoneQuery and (now - self.lastZoneQueryTime) < (TRP3FW.Prefs.whoZoneQueryCooldown or 20) then
        useZoneQuery = false
    end

    -- Construction
    local whoQuery = useZoneQuery and ('z-"'..zoneName..'"') or ('n-"'..sanitizedName..'"')
    local category = priority or (useZoneQuery and "who_zone_query" or "who_name_query")
    local privilegedCode = 'C_FriendList.SetWhoToUi(false) C_FriendList.SendWho([['..whoQuery..']])'

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

    local success, err = TRP3FW:RunPrivilegedSafe(privilegedCode, category)
    if not success then
        TRP3FW:Debug("[WhoService] RunPrivileged failed: "..tostring(err), "who")
        self.pendingQuery = nil
        self.cooldownActive = false
        if callback then callback(false, err or "error") end
        self:ProcessQueue()
        return
    end

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
    if not self.pendingQuery then return end
    
    local start = debugprofilestop()
    local pending = self.pendingQuery
    self.pendingQuery = nil
    self.cooldownActive = false
    
    local success, numWho, totalWho = pcall(C_FriendList.GetNumWhoResults)
    if not success or not numWho or numWho < 0 then
        if pending.callback then pending.callback(false, "api_error") end
        self:ProcessQueue()
        return
    end

    local found = false
    local zone = nil
    local playerList = {} -- For scanMode
    local now = TRP3FW:GetCurrentTime()
    local CI = TRP3FW.CacheInterface
    local myName = UnitName("player")

    for i = 1, numWho do
        local ok, info = pcall(C_FriendList.GetWhoInfo, i)
        if ok and info and info.fullName then
            local name = TRP3FW:CleanPlayerName(info.fullName)
            if name and name ~= myName then
                if pending.scanMode then
                    table.insert(playerList, name)
                end

                if name == pending.playerName then
                    found = true
                    zone = info.area
                end

                -- Cache results
                if CI then
                    local cacheName = (pending.isNameQuery or pending.scanMode) and "whoName" or "whoZone"
                    CI:Set(cacheName, name, {
                        found = true,
                        zone = info.area,
                        timestamp = now
                    })
                end
            end
        end
    end

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
    local privilegedCode = 'C_FriendList.SetWhoToUi(false) C_FriendList.SendWho([['..whoQuery..']])'

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
