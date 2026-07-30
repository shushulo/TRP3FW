-- features/stages/WhitelistStage.lua
-- Stage 1: Checks if player is whitelisted

local addonName, TRP3FW = ...

local WhitelistStage = TRP3FW.Stage:New("WhitelistStage")
WhitelistStage.__index = WhitelistStage

function WhitelistStage:Process(context)
    -- Not whitelisted - continue pipeline
    if not TRP3FW:IsPlayerWhitelisted(context.playerName) then
        return {handled = false, allowed = false, reason = "not_whitelisted"}
    end

    -- Player IS whitelisted - allow immediately
    TRP3FW:Debug("[Whitelist] "..context.playerName.." is whitelisted - bypassing all checks", "send")

    -- Track addon request
    TRP3FW:TrackAddonRequest(context.addon, context.sendId)

    -- Notify
    local notificationService = TRP3FW.ServiceContainer:Get("NotificationService")
    if notificationService then
        notificationService:Notify(context.playerName, {
            type = "allow",
            addon = context.addon,
            reason = "whitelist",
            isWhisper = context.isWhisper,
            settings = context.settings,
            cacheInfo = {whitelist = "hit"}
        })
    end

    -- Record history
    local historyService = TRP3FW.ServiceContainer:Get("HistoryService")
    if historyService then
        historyService:RecordHistory(context.playerName, context.addon, false, false)
    end

    -- Call original function
    if context.originalFunc then
        pcall(context.originalFunc, unpack(context.originalArgs))
    end

    -- Process queued burst requests
    TRP3FW:ProcessBurstAllows(context.playerName)

    return {handled = true, allowed = true, reason = "whitelist"}
end

TRP3FW.WhitelistStage = WhitelistStage
