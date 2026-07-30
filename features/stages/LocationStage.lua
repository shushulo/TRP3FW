-- features/stages/LocationStage.lua
-- Stage 7: Location Check (final stage - always returns handled = true)

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

    -- Start new check (with staleness snapshots for BurstStage / IsBurstRequestStale)
    -- `sendId` tags the entry with the request that owns it, so the housekeeping timer
    -- below can tell "my check is still running" from "a later check for the same player
    -- now owns this slot".
    TRP3FW.pendingLocationChecks[context.playerName] = {
        sendId = context.sendId,
        timestamp = context.now,
        zoneSnapshot = TRP3FW.lastZoneChangeTime,
        phaseSnapshot = TRP3FW.lastPhaseChangeTime,
        settingsFingerprint = TRP3FW.GetBurstSettingsFingerprint and TRP3FW:GetBurstSettingsFingerprint() or nil,
        queuedRequests = {}
    }

    -- Store pending send
    local historyService = TRP3FW.ServiceContainer:Get("HistoryService")
    local isFirstTime, suppressedCount = true, 0
    if historyService then
        isFirstTime, suppressedCount = historyService:IsFirstSend(context.playerName, context.now, context.settings.suppressionTime)
    end

    -- Propagate suppression context so the decision stage can notify correctly.
    context.isFirstTime = isFirstTime
    context.suppressedCount = suppressedCount

    -- pendingSends is an EXISTENCE SET, not a payload store. Every consumer tests only
    -- whether the key is present (`if not pendingSends[sendId] then return end`) or clears it;
    -- nothing anywhere reads a field off the entry except CacheService's age sweep, which
    -- needs `timestamp`. The richer entry this used to build (playerName, addon, isWhisper,
    -- isFirstTime, suppressedCount, originalFunc, originalArgs) was write-only -- and holding
    -- originalArgs meant every in-flight check pinned a full profile payload for no reason.
    -- `playerName` is kept purely because it makes a debug dump of this table readable.
    TRP3FW.pendingSends[context.sendId] = {
        playerName = context.playerName,
        timestamp = context.now,
    }

    -- Timeout
    -- N8: Also clear hook-layer burst queues. Without this, a hung location check leaves
    -- pendingChompSends/pendingTRP3Sends/pendingMSPReplies populated until their own 30s
    -- timers (started at different times) or the 60s CacheService backstop. A new request
    -- arriving in that gap would queue into the abandoned old burst.
    --
    -- N16: This is a give-up path for a check that never resolved, and it must fire ONLY
    -- then. Two guards enforce that, because each one alone is insufficient:
    --   1. `pendingSends[sendId]` still set - the callback below retires it on resolution
    --      (the start-phase branch already did). Without that retirement every request's
    --      timer fired at t+30 as though it had hung.
    --   2. The in-flight check for this player is still OURS. A resolved-then-replaced
    --      check leaves a live entry under the same player key; tearing that down dropped
    --      the newer check's queued sends outright - they were never sent and never
    --      ghosted, so the profile silently never arrived.
    C_Timer.After(30, function()
        if not TRP3FW.pendingSends[context.sendId] then return end
        TRP3FW.pendingSends[context.sendId] = nil

        local inFlight = TRP3FW.pendingLocationChecks and TRP3FW.pendingLocationChecks[context.playerName]
        if not inFlight or inFlight.sendId ~= context.sendId then return end

        TRP3FW.pendingLocationChecks[context.playerName] = nil
        if TRP3FW.pendingChompSends then
            TRP3FW.pendingChompSends[context.playerName] = nil
        end
        if TRP3FW.pendingTRP3Sends then
            TRP3FW.pendingTRP3Sends[context.playerName] = nil
        end
        if TRP3FW.pendingMSPReplies then
            TRP3FW.pendingMSPReplies[context.playerName] = nil
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

        return {handled = true, async = false, allowed = false, reason = "start_phase_block"}
    end

    -- Perform Check
    local options = {
        spvpEnabled = context.spvpEnabled,
        spvpPhaseID = context.spvpPhaseID,
        spvpSalt = context.spvpSalt
    }

    TRP3FW:CheckLocationCascading(context.playerName, context.sendId, function(locationOK, alertType, source, mapCacheAge, theirZone, myZone, cacheInfo, recentTransition, timeSinceTransition, checkDetails)
        -- Retire this send: the check resolved, so the housekeeping timer above must not
        -- later mistake it for a hung request. (The start-phase branch does the same.)
        TRP3FW.pendingSends[context.sendId] = nil

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
