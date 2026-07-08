-- hooks/trp3_scan_pipeline.lua
-- Scan reply decision pipeline

local addonName, TRP3FW = ...

-- ===================== Stage 1: Whitelist Check =====================

local function CheckWhitelist(self, playerName)
    if self:IsPlayerWhitelisted(playerName) then
        self:Debug("[Scan Reply] Player "..playerName.." is whitelisted - immediate allow", "hooks")
        return "allow", "whitelist"
    end
    return "continue", nil
end

-- ===================== Stage 2: Cache Check =====================

local function CheckCache(self, playerName)
    local CI = self.CacheInterface
    if not CI then return "continue", nil, nil end

    local mapCheckEnabled = self:IsMapCheckEnabled()
    local myMapID = self:GetCurrentMapID()
    local myZone = TRP3FW.currentZoneName or GetRealZoneText()

    -- Optimization: Bypass if already known trusted/interactive (if setting enabled)
    if TRP3FW.Prefs.scanResponseAllowCacheBypass then
        local allowed = CI:Get("allowedSenders", playerName)
        if allowed then
            self:Debug("[Scan Reply] Allowed senders cache hit - allowing scan reply to "..playerName, "hooks")
            return "allow", "allowed_cache"
        end

        local interaction = CI:Get("interaction", playerName)
        if interaction then
            self:Debug("[Scan Reply] Interaction cache hit - allowing scan reply to "..playerName, "hooks")
            return "allow", "interaction_cache"
        end
    end

    -- Check phase cache
    local now = self:GetCurrentTime()
    local phaseCache = CI:Get("phaseCheck", playerName)

    -- BUG FIX: A fresh, explicit phase FAILURE must veto the independent WHO-cache
    -- allow-fast-path below. Previously each cache (phase, WHO) only ever said "allow"
    -- or "continue" - a known phaseCheck.inPhase == false (e.g. the player changed phase
    -- after an earlier WHO/zone hit was cached) never prevented the WHO cache hit further
    -- down from allowing anyway. Only applies when phase checking is actually meaningful
    -- for scan replies (scanResponsePhaseCheckEnabled + scanResponsePhaseMode ~= "off");
    -- otherwise phase isn't a signal this pipeline cares about at all.
    local phaseCheckMattersForScan = (TRP3FW.Prefs.scanResponsePhaseCheckEnabled ~= false)
        and (TRP3FW.Prefs.scanResponsePhaseMode and TRP3FW.Prefs.scanResponsePhaseMode ~= "off")
    local freshPhaseFailure = false
    if phaseCheckMattersForScan and phaseCache and phaseCache.inPhase == false then
        local failAge = now - phaseCache.timestamp
        local failTTL = TRP3FW.Prefs.phaseCacheFailureDuration or 10
        if failAge < failTTL then
            freshPhaseFailure = true
            self:Debug("[Scan Reply] Fresh phase cache FAILURE for "..playerName.." - vetoing WHO/other cache allows, continuing to real check", "hooks")
        end
    end

    if phaseCache then
        local age = now - phaseCache.timestamp

        if age < TRP3FW.Prefs.phaseCacheDuration and phaseCache.inPhase then
            -- If map checking is enabled, we must also verify the map ID matches
            local mapMatch = true
            if mapCheckEnabled and phaseCache.mapID and myMapID then
                if phaseCache.mapID ~= myMapID then
                    mapMatch = false
                end
            end

            if mapMatch then
                self:Debug("[Scan Reply] Phase cache hit - allowing scan reply to "..playerName, "hooks")
                return "allow", "phase_cache", age
            else
                self:Debug("[Scan Reply] Phase cache hit but map mismatch (cached: "..tostring(phaseCache.mapID)..", mine: "..tostring(myMapID)..") - continuing", "hooks")
            end
        end
    end

    -- Check WHO cache (skipped entirely if a fresh phase failure already vetoed this player)
    local whoCache = not freshPhaseFailure and CI:Get("whoName", playerName)
    if whoCache then
        local age = now - whoCache.timestamp

        if age < TRP3FW.Prefs.whoNameCacheDuration and whoCache.found then
            -- If map checking is enabled, we must verify the zone matches
            local zoneMatch = true
            if mapCheckEnabled and whoCache.zone and myZone then
                if whoCache.zone ~= myZone then
                    zoneMatch = false
                end
            end

            if zoneMatch then
                self:Debug("[Scan Reply] WHO cache hit - allowing scan reply to "..playerName, "hooks")
                return "allow", "who_cache", age
            else
                self:Debug("[Scan Reply] WHO cache hit but zone mismatch (cached: "..tostring(whoCache.zone)..", mine: "..tostring(myZone)..") - continuing", "hooks")
            end
        end
    end

    return "continue", nil, nil
end

-- ===================== Stage 3: Group Check =====================

local function CheckGroup(self, playerName)
    if TRP3FW.Prefs.scanResponseAllowGroupBypass then
        local isGroupMember = UnitInParty(playerName) or UnitInRaid(playerName)
        if isGroupMember then
            self:Debug("[Scan Reply] Group member - allowing scan reply to "..playerName, "hooks")
            return "allow", "group_member"
        end
    end
    return "continue", nil
end

-- ===================== Stage 4: Location Check =====================

local function PerformLocationCheck(self, playerName, callback, options)
    -- Create sendId for tracking
    local sendIdObj = self:CreateVerifiedSendId()
    local sendId = sendIdObj and sendIdObj.id or 0

    -- Merge default options with provided options
    -- Intelligent WHO query selection for scan replies (3-second TRP3 window):
    -- 1. Check whoZone cache - if fresh and complete, use it
    -- 2. If stale or truncated, prefer whozone query (faster, more data)
    -- 3. Only fall back to whoname if zone is truncated or map scan active
    local currentSPVPMode = TRP3FW.Prefs.spvpMode or "off"
    local effectiveSPVPMode = (currentSPVPMode == "required") and "required" or "optional"

    -- Intelligent WHO query mode selection
    local whoNameOnly = false  -- Default: allow whozone queries
    local now = self:GetCurrentTime()
    local whoService = self.ServiceContainer:Get("WhoService")

    if whoService then
        local zoneAge = now - (whoService.lastZoneQueryTime or 0)
        local zoneTTL = 60  -- Same as zone completeness check
        local wasNotTruncated = (not whoService.lastZoneResultCount or whoService.lastZoneResultCount < 50)
        local lastMapScanAge = now - (self.lastMapScanAt or 0)
        local recentMapScan = lastMapScanAge < 5  -- Map scan in last 5 seconds

        -- Decide query type based on zone cache state and map scan activity
        if zoneAge < zoneTTL and wasNotTruncated then
            -- Zone cache is fresh and complete - zone completeness optimization will handle it
            -- UNLESS a map scan is actively running (need specific location for scan window)
            if recentMapScan then
                whoNameOnly = true  -- Do whoname to get their specific location fast
                self:Debug("[Scan Reply] WHO zone cache fresh but map scan active, using whoname query", "hooks")
            else
                whoNameOnly = true  -- Zone completeness check will handle it
                self:Debug("[Scan Reply] WHO zone cache fresh and complete, using zone completeness check", "hooks")
            end
        elseif not wasNotTruncated then
            -- Zone was truncated - MUST use whoname to find specific player
            whoNameOnly = true
            self:Debug("[Scan Reply] WHO zone truncated (>=50 results), forcing whoname query", "hooks")
        elseif zoneAge >= zoneTTL then
            -- Zone cache is stale - prefer whozone refresh (better data for multiple scanners)
            -- UNLESS a map scan is active (tight 3s window needs fast whoname)
            if recentMapScan then
                whoNameOnly = true
                self:Debug("[Scan Reply] Map scan active, using fast whoname query", "hooks")
            else
                whoNameOnly = false
                self:Debug("[Scan Reply] WHO zone cache stale, allowing whozone refresh", "hooks")
            end
        else
            -- Default: allow whozone if it's beneficial
            whoNameOnly = false
        end
    else
        -- No WhoService, fall back to name queries
        whoNameOnly = true
    end

    local checkOptions = {
        whoNameOnly = whoNameOnly,
        spvpMode = effectiveSPVPMode,
        priority = "HIGH"
    }
    if options then
        for k, v in pairs(options) do
            checkOptions[k] = v
        end
    end

    -- Run cascading location check
    self:CheckLocationCascading(playerName, sendId, callback, checkOptions)
end

-- ===================== Stage 5: Decision Making =====================

local function MakeDecision(locationOK, alertType, source, cacheInfo, theirZone, myZone)
    local decision = {
        action = "allow",
        reason = source,
        shouldNotify = false,
        shouldAlert = false,
        shouldBlock = false,
        alertType = nil,
        cacheInfo = cacheInfo,
        theirZone = theirZone,
        myZone = myZone
    }

    if locationOK then
        decision.action = "allow"
        decision.reason = source
    else
        local mode = "off"
        if alertType and alertType:find("phase") then
            mode = TRP3FW.Prefs.scanResponsePhaseMode or "off"
        elseif alertType and alertType:find("map") then
            mode = TRP3FW.Prefs.scanResponseMapMode or "off"
        end

        if mode == "statistics" then
            -- Allow, no alert, but track stats (handled by logging/history if integrated)
            decision.action = "allow"
            decision.reason = "statistics_only"
        elseif mode == "alert" then
            decision.shouldAlert = true
            decision.action = "alert"
        elseif mode == "block" then
            decision.shouldBlock = true
            decision.action = "block"
        elseif mode == "alert_block" then
            decision.shouldAlert = true
            decision.shouldBlock = true
            decision.action = "block"
        else
            -- Off or unknown
            decision.action = "allow"
        end

        decision.alertType = alertType
        decision.shouldNotify = decision.shouldAlert or decision.shouldBlock
    end

    return decision
end

-- ===================== Notification Helper =====================

function TRP3FW:ShowScanNotification(targetName, outcome, detail, age, contextLabel, locationInfo)
    if not TRP3FW.Prefs.notifyOnScanResponse then return end
    if outcome == "allow" and not TRP3FW.Prefs.notifyOnScanAllow then return end

    local isAlert = (outcome == "alert")
    local isBlock = (outcome == "block")
    local loc = locationInfo or {}

    -- Propagate cache hits from the location check so chat output reflects cached decisions.
    local cacheInfo = {}
    if loc.cacheInfo then
        for k, v in pairs(loc.cacheInfo) do
            cacheInfo[k] = v
        end
    end
    cacheInfo.scan = cacheInfo.scan or outcome

    -- Construct context details to ensure correct message ("scan reply" instead of "profile")
    local contextDetails = {
        context = "scan",
        subject = "scan reply",
        prefix = "|cff00ccff[SCAN]|r "
    }

    self:ShowChatNotification(
        targetName,
        contextLabel or "TRP3", -- addon
        true, -- isFirstTime
        0, -- suppressedCount
        isAlert,
        nil, -- theirMap (not available here)
        nil, -- ourMap (not available here)
        loc.theirZone, -- theirZone
        loc.myZone, -- ourZone
        detail, -- alertType (contains reason like "phase_mismatch")
        isBlock, -- wasBlocked
        age, -- mapCacheAge (or cache age)
        cacheInfo, -- cacheInfo (include hits so we don't show "[cache: miss]")
        nil, -- recentTransition
        nil, -- timeSinceTransition
        false, -- isGhost
        nil, -- checkDetails
        contextDetails -- contextDetails (CRITICAL FIX)
    )
end

-- ===================== Main Scan Reply Handler =====================

function TRP3FW:HandleScanReplyPipeline(playerName, originalFunc, contextLabel, ...)
    local cleanName = self:CleanPlayerName(playerName)
    if not cleanName then
        -- Invalid name, allow
        return originalFunc(...)
    end

    self:Debug("[Scan Reply] Processing scan reply to "..cleanName, "hooks")

    -- Stage 1: Whitelist
    local action, reason, age = CheckWhitelist(self, cleanName)
    if action == "allow" then
        self:ShowScanNotification(cleanName, "allow", reason, 0, contextLabel, {cacheInfo = {whitelist = "hit"}})
        return originalFunc(...)
    end

    -- Stage 2: Cache
    action, reason, age = CheckCache(self, cleanName)
    if action == "allow" then
        local cacheInfo = {}
        if reason == "phase_cache" then
            cacheInfo.phaseCache = "hit"
        elseif reason == "who_cache" then
            cacheInfo.whoCache = "hit"
        end
        self:ShowScanNotification(cleanName, "allow", reason, age, contextLabel, {cacheInfo = cacheInfo})
        return originalFunc(...)
    end

    -- Stage 3: Group
    action, reason = CheckGroup(self, cleanName)
    if action == "allow" then
        self:ShowScanNotification(cleanName, "allow", reason, 0, contextLabel)
        return originalFunc(...)
    end

    -- Stage 4: Location Check (async)
    -- Optimization: If both scan response modes are "off", skip expensive location checks
    local phaseMode = TRP3FW.Prefs.scanResponsePhaseMode
    local mapMode = TRP3FW.Prefs.scanResponseMapMode

    if (not phaseMode or phaseMode == "off") and (not mapMode or mapMode == "off") then
        self:Debug("[Scan Reply] All scan checks disabled - skipping location check", "hooks")
        -- Treat as allowed
        self:ShowScanNotification(cleanName, "allow", "checks_disabled", 0, contextLabel)
        return originalFunc(unpack({...}))
    end

    -- We need to pass ... arguments to originalFunc in the callback
    local args = {...}

    -- Calculate enabled flags for cascading check
    -- Scan response phase check has an extra master toggle: scanResponsePhaseCheckEnabled
    local phaseEnabled = (phaseMode and phaseMode ~= "off")
    if TRP3FW.Prefs.scanResponsePhaseCheckEnabled == false then
         phaseEnabled = false
    end
    local mapEnabled = (mapMode and mapMode ~= "off")

    PerformLocationCheck(self, cleanName, function(locationOK, alertType, source, mapCacheAge, theirZone, myZone, cacheInfo)
        -- Stage 5: Make Decision
        local decision = MakeDecision(locationOK, alertType, source, cacheInfo, theirZone, myZone)

        -- Record history via HistoryService. All session-stat increments are handled
        -- inside RecordHistory; do NOT IncrementStat them here (was double-counting).
        local historyService = TRP3FW.ServiceContainer:Get("HistoryService")
        if historyService then
            historyService:RecordHistory(cleanName, contextLabel or "TRP3", decision.shouldAlert, decision.shouldBlock, false, decision.alertType)
        end

        -- Execute decision
        if decision.shouldBlock then
            if decision.shouldAlert then
                -- Alert + Block
                self:ShowScanNotification(cleanName, "block", decision.alertType, 0, contextLabel, {
                    theirZone = decision.theirZone,
                    myZone = decision.myZone,
                    cacheInfo = decision.cacheInfo,
                })
            else
                -- Silent Block (no notification call)
                self:Debug("[Scan Reply] Silently blocked scan reply to "..cleanName.." ("..tostring(decision.alertType)..")", "hooks")
            end
            -- Block: Do NOT call originalFunc
        else
            -- Allow (with or without alert)
            if decision.shouldAlert then
                self:ShowScanNotification(cleanName, "alert", decision.alertType, 0, contextLabel, {
                    theirZone = decision.theirZone,
                    myZone = decision.myZone,
                    cacheInfo = decision.cacheInfo,
                })
            else
                -- Normal Allow (or Statistics Only)
                -- Pass reason (e.g. "statistics_only" or source)
                self:ShowScanNotification(cleanName, "allow", decision.reason, 0, contextLabel, {
                    theirZone = decision.theirZone,
                    myZone = decision.myZone,
                    cacheInfo = decision.cacheInfo,
                })
            end
            originalFunc(unpack(args))
        end
    end, {
        phaseCheckEnabled = phaseEnabled,
        mapCheckEnabled = mapEnabled
    })
end

return {
    CheckWhitelist = CheckWhitelist,
    CheckCache = CheckCache,
    CheckGroup = CheckGroup,
    PerformLocationCheck = PerformLocationCheck,
    MakeDecision = MakeDecision,
}
