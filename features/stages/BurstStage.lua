-- features/stages/BurstStage.lua
-- Stage: Burst Handling
-- Handles queuing of requests when a location check is already in progress

local addonName, TRP3FW = ...

local BurstStage = TRP3FW.Stage:New("BurstStage")
BurstStage.__index = BurstStage

function BurstStage:Process(context)
    if not TRP3FW.pendingLocationChecks then
        TRP3FW.pendingLocationChecks = {}
    end

    -- Check if a location check is already in progress for this player
    if TRP3FW.pendingLocationChecks[context.playerName] then
        TRP3FW:Debug("Location check already in progress for "..context.playerName..", queuing this request", "send")
        
        -- Check suppression state for queued request
        local historyService = TRP3FW.ServiceContainer:Get("HistoryService")
        local isFirstTime, suppressedCount = true, 0
        if historyService then
            isFirstTime, suppressedCount = historyService:IsFirstSend(context.playerName, context.now, context.settings.suppressionTime)
        end

        table.insert(TRP3FW.pendingLocationChecks[context.playerName].queuedRequests, {
            sendId = context.sendId,
            addon = context.addon,
            isWhisper = context.isWhisper,
            timestamp = context.now,
            queuedAt = context.now,
            zoneSnapshot = TRP3FW.lastZoneChangeTime,
            phaseSnapshot = TRP3FW.lastPhaseChangeTime,
            settingsFingerprint = TRP3FW:GetBurstSettingsFingerprint(),
            isFirstTime = isFirstTime,
            suppressedCount = suppressedCount,
            originalFunc = context.originalFunc,
            originalArgs = context.originalArgs
        })
        return {handled = true, queued = true, reason = "burst_queued"}
    end

    return {handled = false}
end

TRP3FW.BurstStage = BurstStage
