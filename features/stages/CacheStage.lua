-- features/stages/CacheStage.lua
-- Stage 5: Cache Check (Phase, Map, WHO)

local addonName, TRP3FW = ...

local CacheStage = TRP3FW.Stage:New("CacheStage")
CacheStage.__index = CacheStage

function CacheStage:Process(context)
    local CI = TRP3FW.CacheInterface
    if not CI then return {handled = false} end

    -- 1. Phase Check Cache
    -- Cache shape (written by location/phase.lua): { inPhase = bool, mapID, timestamp, method }.
    -- Earlier code here read `isSamePhase`, a field that does not exist — so the same-phase
    -- branch never fired and (post-N5) the different-phase fast-fail blocked every cached
    -- entry, including ones cached just after a successful "IN PHASE" check.
    if TRP3FW:IsPhaseCheckEnabled() then
        local phaseResult = CI:Get("phaseCheck", context.playerName)
        if phaseResult and phaseResult.inPhase ~= nil then
            if phaseResult.inPhase then
                TRP3FW:Debug("Phase cache hit: "..context.playerName.." is in same phase", "send")
                -- If map check is disabled, we can allow immediately
                if not TRP3FW:IsMapCheckEnabled() then
                    TRP3FW:TrackAddonRequest(context.addon, context.sendId)

                    local historyService = TRP3FW.ServiceContainer:Get("HistoryService")
                    if historyService then
                        historyService:IncrementStat("cacheStats", "phaseCacheHits")
                        historyService:RecordHistory(context.playerName, context.addon, false, false)
                    end

                    TRP3FW:AllowSender(context.playerName, "phase_cache")

                    -- Notify
                    local notificationService = TRP3FW.ServiceContainer:Get("NotificationService")
                    if notificationService then
                        notificationService:Notify(context.playerName, {
                            type = "allow",
                            addon = context.addon,
                            reason = "phase_cache",
                            isWhisper = context.isWhisper,
                            settings = context.settings,
                            cacheInfo = {phaseCache = "hit"}
                        })
                    end

                    if context.originalFunc then
                        pcall(context.originalFunc, unpack(context.originalArgs))
                    end
                    return {handled = true, allowed = true, reason = "phase_cache"}
                end
                -- If map check is enabled, we continue to map cache check
            else
                -- N5: Cached as DIFFERENT phase. Fast-fail by synthesizing a failed
                -- locationResult and dispatching the decision stage directly. Saves a full
                -- CheckLocationCascading round-trip (phase query + map scan) on every
                -- subsequent request from a known out-of-phase sender — exactly the case
                -- where caching matters most (incoming spam from one player).
                TRP3FW:Debug("Phase cache hit: "..context.playerName.." is in DIFFERENT phase, fast-fail", "send")

                local historyService = TRP3FW.ServiceContainer:Get("HistoryService")
                if historyService then
                    historyService:IncrementStat("cacheStats", "phaseCacheHits")
                end

                local locationResult = {
                    locationOK = false,
                    alertType = "phase",
                    source = "phase_cache",
                    mapCacheAge = 0,
                    theirZone = "Unknown",  -- phaseCheck cache stores mapID, not zone text
                    myZone = TRP3FW.currentZoneName or "Unknown",
                    cacheInfo = { phaseCache = "hit" },
                    recentTransition = false,
                    timeSinceTransition = 0,
                    checkDetails = {
                        phase = {
                            result = false,
                            source = "cached",
                            method = phaseResult.method or "cached",
                            theirMapID = phaseResult.mapID,
                        }
                    }
                }
                TRP3FW:Pipeline_DecisionStage(context, locationResult)
                return {handled = true, allowed = false, reason = "phase_cache_fail"}
            end
        end
    end

    -- 2. Allowed Senders Cache (General)
    local allowedEntry = CI:Get("allowedSenders", context.playerName)
    if allowedEntry then
        -- Skip alert-only fast path entries so we still run location checks and surface alerts
        if allowedEntry.reason == "alert_only_allow" then
            TRP3FW:Debug("Allowed senders cache hit (alert_only_allow) ignored for "..context.playerName, "send")
            return {handled = false}
        end

        TRP3FW:Debug("Allowed senders cache hit for "..context.playerName, "send")
        TRP3FW:TrackAddonRequest(context.addon, context.sendId)

        local historyService = TRP3FW.ServiceContainer:Get("HistoryService")
        if historyService then
            historyService:IncrementStat("cacheStats", "allowedSendersCacheHits")
            historyService:RecordHistory(context.playerName, context.addon, false, false)
        end

        TRP3FW:AllowSender(context.playerName, "allowed_cache")

        -- Notify
        local notificationService = TRP3FW.ServiceContainer:Get("NotificationService")
        if notificationService then
            notificationService:Notify(context.playerName, {
                type = "allow",
                addon = context.addon,
                reason = allowedEntry.reason or "allowed_cache",
                isWhisper = context.isWhisper,
                settings = context.settings,
                cacheInfo = {allowedSenders = "hit", allowedSendersReason = allowedEntry.reason}
            })
        end

        if context.originalFunc then
            pcall(context.originalFunc, unpack(context.originalArgs))
        end
        return {handled = true, allowed = true, reason = "allowed_cache"}
    end

    -- 3. SPVP Verified Cache (Cryptographic verification)
    if TRP3FW.hasEpsilonAPI then
        local spvpEntry = CI:Get("spvpVerified", context.playerName)
        if spvpEntry and spvpEntry.verified then
            TRP3FW:Debug("SPVP verified cache hit for "..context.playerName, "spvp")
            TRP3FW:TrackAddonRequest(context.addon, context.sendId)

            local historyService = TRP3FW.ServiceContainer:Get("HistoryService")
            if historyService then
                historyService:IncrementStat("cacheStats", "spvpVerifiedCacheHits")
                historyService:RecordHistory(context.playerName, context.addon, false, false)
            end

            TRP3FW:AllowSender(context.playerName, "spvp_verified")

            -- Notify
            local notificationService = TRP3FW.ServiceContainer:Get("NotificationService")
            if notificationService then
                notificationService:Notify(context.playerName, {
                    type = "allow",
                    addon = context.addon,
                    reason = "spvp_verified",
                    isWhisper = context.isWhisper,
                    settings = context.settings,
                    cacheInfo = {spvpCache = "hit"}
                })
            end

            if context.originalFunc then
                pcall(context.originalFunc, unpack(context.originalArgs))
            end
            return {handled = true, allowed = true, reason = "spvp_verified"}
        end
    end

    -- REMOVED: WHO/Map cache fast-paths (Stage 3/4)
    -- These are now handled exclusively by LocationStage to ensure proper Phase Check sequencing.
    -- Bypassing Phase Check via map cache was a security loophole.

    return {handled = false}
end

TRP3FW.CacheStage = CacheStage
