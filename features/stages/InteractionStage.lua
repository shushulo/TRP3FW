-- features/stages/InteractionStage.lua
-- Stage 4: Interaction Check (Mutual Exchange & Recent Interaction)

local addonName, TRP3FW = ...

local InteractionStage = TRP3FW.Stage:New("InteractionStage")
InteractionStage.__index = InteractionStage

function InteractionStage:Process(context)
    -- Check if is a mutual exchange (YOU initiated the query to THEM recently)
    local isMutualExchange = TRP3FW:IsUserInitiatedExchange(context.playerName)
    if isMutualExchange then
        TRP3FW:Debug("Mutual exchange detected - YOU queried "..context.playerName.." recently", "send")
    end

    -- Check if recently interacted with (mouseover/target)
    local CI = TRP3FW.CacheInterface
    local lastInteraction = CI and CI:Get("interaction", context.playerName)
    local currentZone = TRP3FW.currentZoneName

    if lastInteraction and currentZone and lastInteraction.zone and lastInteraction.zone ~= currentZone then
        if CI then
            CI:Remove("interaction", context.playerName)
        end
        lastInteraction = nil
    end
    
    local interactionDuration = context.settings.interactionCacheDuration or 600
    local hadInteractionCacheHit = false
    local interactionSource = nil
    local isLiveInteraction = false

    local historyService = TRP3FW.ServiceContainer:Get("HistoryService")

    if lastInteraction then
        local timestamp = lastInteraction.timestamp
        if timestamp and (context.now - timestamp) < interactionDuration then
            local age = context.now - timestamp
            local zoneInfo = lastInteraction.zone and (" in "..lastInteraction.zone) or ""
            TRP3FW:Debug("Sender "..context.playerName.." recently interacted with ("..string.format("%.1f", age).."s ago"..zoneInfo.."), allowing without checks", "send")
            
            -- Deduplicate by sendId: Only increment stats once per unique sendId FOR THIS CACHE TYPE
            if not TRP3FW.lastInteractionCacheSendId then TRP3FW.lastInteractionCacheSendId = {} end
            if not TRP3FW.lastInteractionCacheSendId[context.sendId] then
                if historyService then
                    historyService:IncrementStat("cacheStats", "interactionCacheHits")
                end
                TRP3FW.lastInteractionCacheSendId[context.sendId] = true
                TRP3FW.lastInteractionCacheSendIdCount = (TRP3FW.lastInteractionCacheSendIdCount or 0) + 1
            end
            
            hadInteractionCacheHit = true
            interactionSource = lastInteraction.source
        end
    end

    -- Immediate target check
    if UnitIsPlayer("target") and not UnitIsUnit("target", "player") and not TRP3FW.phaseCheckTargeting then
        local targetName = TRP3FW:CleanPlayerName(UnitName("target"))
        if targetName == context.playerName then
            local zone = TRP3FW.currentZoneName or "Unknown"
            TRP3FW:Debug("Sender "..context.playerName.." is current target, allowing without checks", "send")
            if CI then
                CI:Set("interaction", context.playerName, { timestamp = context.now, zone = zone, source = "target" })
            end
            interactionSource = "target"
            hadInteractionCacheHit = true
            isLiveInteraction = true
        end
    end

    -- Live mouseover fallback
    if not hadInteractionCacheHit and UnitIsPlayer("mouseover") and not UnitIsUnit("mouseover", "player") then
        local mouseName = TRP3FW:CleanPlayerName(UnitName("mouseover"))
        if mouseName == context.playerName then
            local zone = TRP3FW.currentZoneName or "Unknown"
            if CI then
                CI:Set("interaction", context.playerName, { timestamp = context.now, zone = zone, source = "mouseover_live" })
            end
            TRP3FW:Debug("Sender "..context.playerName.." is current mouseover, allowing without checks", "send")
            interactionSource = "mouseover_live"
            hadInteractionCacheHit = true
            isLiveInteraction = true
        end
    end

    if not hadInteractionCacheHit then
        -- Track miss stats
        if not TRP3FW.lastInteractionCacheSendId then TRP3FW.lastInteractionCacheSendId = {} end
        if not TRP3FW.lastInteractionCacheSendId[context.sendId] then
            if historyService then
                historyService:IncrementStat("cacheStats", "interactionCacheMisses")
            end
            TRP3FW.lastInteractionCacheSendId[context.sendId] = true
            TRP3FW.lastInteractionCacheSendIdCount = (TRP3FW.lastInteractionCacheSendIdCount or 0) + 1
        end
        
        return {handled = false}
    end

    -- Hit!
    TRP3FW:Debug("Interaction cache hit, skipping location checks", "send")
    TRP3FW:TrackAddonRequest(context.addon, context.sendId)

    local suppressInteractionNotification = isLiveInteraction or isMutualExchange

    -- Notification logic
    if not suppressInteractionNotification and not isMutualExchange then
        local notificationService = TRP3FW.ServiceContainer:Get("NotificationService")
        if notificationService then
            notificationService:Notify(context.playerName, {
                type = "allow",
                addon = context.addon,
                reason = "interaction_cache",
                isWhisper = context.isWhisper,
                settings = context.settings,
                cacheInfo = {interactionCache = "hit"}
            })
        end
    end

    -- Record history
    if historyService then
        historyService:RecordHistory(context.playerName, context.addon, false, false)
    end

    -- Call original function
    if context.originalFunc then
        pcall(context.originalFunc, unpack(context.originalArgs))
    end

    -- Process queued burst requests
    TRP3FW:ProcessBurstAllows(context.playerName)

    return {handled = true, allowed = true, reason = "interaction_cache"}
end

TRP3FW.InteractionStage = InteractionStage
