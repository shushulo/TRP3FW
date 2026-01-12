-- features/stages/LocationStage.lua
-- Stage 6: Location Check & Burst Handling

local addonName, TRP3FW = ...

local LocationStage = TRP3FW.Stage:New("LocationStage")
LocationStage.__index = LocationStage

function LocationStage:Process(context)
    if not TRP3FW.pendingLocationChecks then
        TRP3FW.pendingLocationChecks = {}
    end

    local phaseCheckEnabled = TRP3FW:IsPhaseCheckEnabled()
    local mapCheckEnabled = TRP3FW:IsMapCheckEnabled()

    if not phaseCheckEnabled and not mapCheckEnabled then
        -- No checks enabled - just allow
        TRP3FW:TrackAddonRequest(context.addon, context.sendId)
        
        local historyService = TRP3FW.ServiceContainer:Get("HistoryService")
        if historyService then
            historyService:RecordHistory(context.playerName, context.addon, false, false)
        end
        
        TRP3FW:AllowSender(context.playerName, "no_alerts")
        if context.originalFunc then
            pcall(context.originalFunc, unpack(context.originalArgs))
        end
        return {handled = true, allowed = true, reason = "no_checks"}
    end

    -- Start new check
    TRP3FW.pendingLocationChecks[context.playerName] = {
        timestamp = context.now,
        queuedRequests = {}
    }

    -- Store pending send
    local historyService = TRP3FW.ServiceContainer:Get("HistoryService")
    local history = historyService and historyService.profileSendHistory[context.playerName]
    local isFirstTime = not history or (context.now - history.timestamp) > context.settings.suppressionTime
    local suppressedCount = history and history.suppressedCount or 0

    -- Propagate suppression context so the decision stage can notify correctly.
    context.isFirstTime = isFirstTime
    context.suppressedCount = suppressedCount

    TRP3FW.pendingSends[context.sendId] = {
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
        if TRP3FW.pendingSends[context.sendId] then
            TRP3FW.pendingSends[context.sendId] = nil
            if TRP3FW.pendingLocationChecks and TRP3FW.pendingLocationChecks[context.playerName] then
                 TRP3FW.pendingLocationChecks[context.playerName] = nil
            end
        end
    end)

    -- Start phase check
    local shouldBlockStartPhase, blockType = TRP3FW:ShouldBlockForStartPhase(context.playerName, true)
    if shouldBlockStartPhase then
        TRP3FW:Debug("Start phase block triggered for "..context.playerName.." (type: "..tostring(blockType)..")", "send")
        
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
        
        -- Merge sendInfo context
        context.isFirstTime = isFirstTime
        context.suppressedCount = suppressedCount
        
        -- Call Decision Stage directly (or via pipeline if we restructure)
        -- For now, we'll call the legacy helper which will be converted later
        TRP3FW:Pipeline_DecisionStage(context, locationResult)
        
        -- Clear pending sends
        TRP3FW.pendingSends[context.sendId] = nil
        if TRP3FW.pendingLocationChecks then
             TRP3FW.pendingLocationChecks[context.playerName] = nil
        end
        
        return {handled = true, async = false, reason = "start_phase_block"}
    end

    -- Perform Check
    local options = {
        spvpEnabled = context.spvpEnabled,
        spvpPhaseID = context.spvpPhaseID,
        spvpSalt = context.spvpSalt
    }

    TRP3FW:CheckLocationCascading(context.playerName, context.sendId, function(locationOK, alertType, source, mapCacheAge, theirZone, myZone, cacheInfo, recentTransition, timeSinceTransition, checkDetails)
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
        
        -- Call Decision Stage
        TRP3FW:ProcessLocationDecision(context, locationResult)
    end, options)

    return {handled = true, async = true, reason = "check_started"}
end

TRP3FW.LocationStage = LocationStage
