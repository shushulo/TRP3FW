-- features/stages/AlertFastPathStage.lua
-- Stage 5: Alert-Only Fast Path

local addonName, TRP3FW = ...

local AlertFastPathStage = TRP3FW.Stage:New("AlertFastPathStage")
AlertFastPathStage.__index = AlertFastPathStage

function AlertFastPathStage:Process(context)
    -- Alert-only fast path
    local startPhaseActive = context.settings.blockStartPhase or context.settings.ghostOnStartPhase
    local alertOnlyPhase = TRP3FW:ShouldAlertOnPhase() and not TRP3FW:ShouldBlockOnPhase()
    local alertOnlyMap   = TRP3FW:ShouldAlertOnMap()   and not TRP3FW:ShouldBlockOnMap()
    local noPhaseChecks  = not TRP3FW:IsPhaseCheckEnabled()
    local noMapChecks    = not TRP3FW:IsMapCheckEnabled()
    
    local alertOnly = (alertOnlyPhase or noPhaseChecks) and (alertOnlyMap or noMapChecks) and not startPhaseActive and not TRP3FW:IsProfileSwitchOverrideActive()

    if not alertOnly then
        return {handled = false}
    end

    TRP3FW:Debug("[Fast Allow] Alert-only mode, sending immediately and deferring checks", "send")
    TRP3FW:TrackAddonRequest(context.addon, context.sendId)
    
    -- Call original function immediately
    if context.originalFunc then
        pcall(context.originalFunc, unpack(context.originalArgs))
    end
    
    local historyService = TRP3FW.ServiceContainer:Get("HistoryService")
    if historyService then
        historyService:RecordHistory(context.playerName, context.addon, false, false)
    end
    
    TRP3FW:AllowSender(context.playerName, "alert_only_allow")
    
    -- Perform Check with SPVP context
    local options = {
        spvpEnabled = context.spvpEnabled,
        spvpPhaseID = context.spvpPhaseID,
        spvpSalt = context.spvpSalt
    }

    -- Run location checks asynchronously to surface alerts
    TRP3FW:CheckLocationCascading(context.playerName, context.sendId, function(locationOK, alertType, source, mapCacheAge, theirZone, myZone, cacheInfo, recentTransition, timeSinceTransition, checkDetails)
        -- Process alerts only
        local shouldAlert = (locationOK == false) and (source ~= "disabled")
        local notificationService = TRP3FW.ServiceContainer:Get("NotificationService")

        if shouldAlert then
            -- Update suppression
            local historyService = TRP3FW.ServiceContainer:Get("HistoryService")
            if historyService then
                local history = historyService.profileSendHistory[context.playerName]
                if not history then
                    historyService.profileSendHistory[context.playerName] = { timestamp = context.now, suppressedCount = 0 }
                else
                    historyService.profileSendHistory[context.playerName].timestamp = context.now
                end
            end
            
            TRP3FW:Debug("[Fast Allow] Alert-only async result for "..context.playerName..": ALERT", "send")
            
            if notificationService then
                notificationService:Notify(context.playerName, {
                    type = "alert",
                    addon = context.addon,
                    alertType = alertType,
                    reason = alertType,
                    isWhisper = context.isWhisper,
                    settings = context.settings,
                    cacheInfo = cacheInfo,
                    checkDetails = checkDetails,
                    location = {
                        theirZone = theirZone,
                        ourZone = myZone,
                        mapCacheAge = mapCacheAge,
                        recentTransition = recentTransition,
                        timeSinceTransition = timeSinceTransition
                    }
                })
            end
        elseif context.settings.notifyOnAllow and notificationService then
             -- Notification for successful allowed checks (delayed)
             notificationService:Notify(context.playerName, {
                type = "allow",
                addon = context.addon,
                reason = "location_ok",
                isWhisper = context.isWhisper,
                settings = context.settings,
                cacheInfo = cacheInfo,
                checkDetails = checkDetails
            })
        end
        
        -- Process burst allows
        TRP3FW:ProcessMSPBurstAllows(context.playerName)
        TRP3FW:ProcessTRP3BurstAllows(context.playerName)
    end)

    return {handled = true, allowed = true, reason = "alert_fast_path"}
end

TRP3FW.AlertFastPathStage = AlertFastPathStage
