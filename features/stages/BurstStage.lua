-- features/stages/BurstStage.lua
-- Stage 6: Burst Handling
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

        local queue = TRP3FW.pendingLocationChecks[context.playerName].queuedRequests

        -- Bound the queue. Each entry retains originalArgs (a full profile payload), and a
        -- hung check keeps the window open for up to 30s, so an unbounded queue was the one
        -- collection in the addon without the maxSize CLAUDE.md requires of the rest. Drop the
        -- OLDEST rather than refusing the newest: the newest request is the one whose sender
        -- is still actively waiting, and stale entries are the ones ProcessBurst* would
        -- discard as stale anyway.
        local limit = TRP3FW.BURST_QUEUE_LIMIT or 100
        while #queue >= limit do
            table.remove(queue, 1)
            TRP3FW.burstQueueDrops = (TRP3FW.burstQueueDrops or 0) + 1
            TRP3FW:Debug("Burst queue for "..context.playerName.." at cap ("..limit..
                ") - dropped oldest queued request", "send")
        end

        table.insert(queue, {
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
        -- Count the queued request too. Only the burst LEADER reached TrackAddonRequest (via
        -- the stage that eventually resolves it), so every sibling of a burst was invisible to
        -- the addon-request stats -- i.e. the stats under-reported exactly during the traffic
        -- spikes they exist to show.
        TRP3FW:TrackAddonRequest(context.addon, context.sendId)

        return {handled = true, queued = true, reason = "burst_queued"}
    end

    return {handled = false}
end

TRP3FW.BurstStage = BurstStage
