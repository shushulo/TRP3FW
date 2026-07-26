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

    -- Run location checks asynchronously to surface alerts.
    -- N17: `options` must be passed. It was built and then dropped here (LocationStage
    -- passes its equivalent), so the alert-only path discarded SPVPStage's decision and
    -- cascading's late-resolution re-derived `spvpEnabled` from live prefs - running SPVP
    -- in phases the user had explicitly opted out of.
    TRP3FW:CheckLocationCascading(context.playerName, context.sendId, function(locationOK, alertType, source, mapCacheAge, theirZone, myZone, cacheInfo, recentTransition, timeSinceTransition, checkDetails)
        -- Process alerts only
        local shouldAlert = (locationOK == false) and (source ~= "disabled")
        local notificationService = TRP3FW.ServiceContainer:Get("NotificationService")

        if shouldAlert then
            -- Update suppression
            local historyService = TRP3FW.ServiceContainer:Get("HistoryService")
            if historyService then
                local existing = historyService:GetSendHistory(context.playerName)
                if existing then
                    existing.timestamp = context.now
                else
                    historyService:RecordSend(context.playerName, context.now)
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
        end
        -- N13: No delayed-allow notification. Alert-only mode is opt-in-quiet-on-success.
        -- A "Profile sent" toast 1-2s after the actual send is detached from the action that
        -- triggered it and looks like a stuck/duplicate event. If users want delayed allow
        -- notifications, that should be a separate explicit setting.

        -- Process burst allows
        TRP3FW:ProcessBurstAllows(context.playerName)
    end, options)

    return {handled = true, allowed = true, reason = "alert_fast_path"}
end

TRP3FW.AlertFastPathStage = AlertFastPathStage
