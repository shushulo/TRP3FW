-- features/stages/location_stage.lua
-- Stage 6: Location Check & Burst Handling

local addonName, TRP3FW = ...

function TRP3FW:Pipeline_LocationCheck(context)
    if not self.pendingLocationChecks then
        self.pendingLocationChecks = {}
    end

    local locationChecksEnabled = self:IsPhaseCheckEnabled() or self:IsMapCheckEnabled()

    if not locationChecksEnabled then
        -- No checks enabled - just allow
        self:TrackAddonRequest(context.addon, context.sendId)
        self:RecordHistory(context.playerName, context.addon, false, false)
        self:AllowSender(context.playerName, "no_alerts")
        if context.originalFunc then
            pcall(context.originalFunc, unpack(context.originalArgs))
        end
        return {handled = true, allowed = true, reason = "no_checks"}
    end

    -- Burst handling is now done in Pipeline_BurstStage
    -- We assume that if we are here, no check is in progress or we are the one starting it

    -- Start new check
    if not self.pendingLocationChecks then
        self.pendingLocationChecks = {}
    end
    
    self.pendingLocationChecks[context.playerName] = {
        timestamp = context.now,
        zoneSnapshot = self.lastZoneChangeTime,
        phaseSnapshot = self.lastPhaseChangeTime,
        settingsFingerprint = self:GetBurstSettingsFingerprint(),
        queuedRequests = {}
    }

    -- Store pending send
    local history = self.profileSendHistory[context.playerName]
    local isFirstTime = not history or (context.now - history.timestamp) > context.settings.suppressionTime
    local suppressedCount = history and history.suppressedCount or 0

    self.pendingSends[context.sendId] = {
        playerName = context.playerName,
        addon = context.addon,
        isWhisper = context.isWhisper,
        timestamp = context.now,
        isFirstTime = isFirstTime,
        suppressedCount = suppressedCount,
        originalFunc = context.originalFunc,
        originalArgs = context.originalArgs
    }

    -- Timeout
    C_Timer.After(30, function()
        if self.pendingSends[context.sendId] then
            self.pendingSends[context.sendId] = nil
            -- Also clear pending check if it timed out?
            if self.pendingLocationChecks and self.pendingLocationChecks[context.playerName] then
                 -- Only clear if it's still the same check? 
                 -- Hard to know without ID, but 30s is long enough.
                 self.pendingLocationChecks[context.playerName] = nil
            end
        end
    end)

    -- Start phase check (Phase 7.1: Moved from utils.lua to ghostmode.lua, called here)
    -- This takes priority over location checks
    local shouldBlockStartPhase, blockType = self:ShouldBlockForStartPhase(context.playerName, true)
    if shouldBlockStartPhase then
        self:Debug("Start phase block triggered for "..context.playerName.." (type: "..tostring(blockType)..")", "send")
        
        local locationResult = {
            locationOK = false,
            alertType = "start_phase_block",
            source = "start_phase",
            mapCacheAge = 0,
            theirZone = "Unknown",
            myZone = TRP3FW.currentZoneName or "Unknown",
            cacheInfo = {},
            recentTransition = false,
            timeSinceTransition = 0,
            checkDetails = {}
        }
        
        -- Merge sendInfo context (isFirstTime, suppressedCount)
        context.isFirstTime = isFirstTime
        context.suppressedCount = suppressedCount
        
        self:Pipeline_DecisionStage(context, locationResult)
        
        -- Clear pending sends
        self.pendingSends[context.sendId] = nil
        if self.pendingLocationChecks then
             self.pendingLocationChecks[context.playerName] = nil
        end
        
        return {handled = true, async = false}
    end

    -- Perform Check
    self:CheckLocationCascading(context.playerName, context.sendId, function(locationOK, alertType, source, mapCacheAge, theirZone, myZone, cacheInfo, recentTransition, timeSinceTransition, checkDetails)
        local sendInfo = self.pendingSends[context.sendId]
        if not sendInfo then return end
        
        -- Construct location result object
        local locationResult = {
            locationOK = locationOK,
            alertType = alertType,
            source = source,
            mapCacheAge = mapCacheAge,
            theirZone = theirZone,
            myZone = myZone,
            cacheInfo = cacheInfo,
            recentTransition = recentTransition,
            timeSinceTransition = timeSinceTransition,
            checkDetails = checkDetails
        }
        
        -- Delegate to Decision Stage
        -- We need to pass the context stored in sendInfo because the original context might be stale?
        -- Actually sendInfo IS the context snapshot we stored.
        -- But Pipeline_DecisionStage expects a context object. sendInfo has the fields.
        -- We also need 'settings' which is in the original context.
        -- sendInfo doesn't have 'settings'.
        
        -- We should store the FULL context in pendingSends or reconstruct it.
        -- The original context is available in the closure if we use it?
        -- Yes, 'context' variable is available in the closure.
        -- But sendInfo has isFirstTime and suppressedCount which were calculated at start.
        
        -- Let's merge sendInfo into context or pass sendInfo as context override.
        context.isFirstTime = sendInfo.isFirstTime
        context.suppressedCount = sendInfo.suppressedCount
        
        self:Pipeline_DecisionStage(context, locationResult)

        self.pendingSends[context.sendId] = nil
        -- pendingLocationChecks is cleared in Pipeline_DecisionStage
    end)

    return {handled = true, async = true}
end
