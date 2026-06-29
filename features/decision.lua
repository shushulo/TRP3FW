-- features/decision.lua
-- Core allow/block decision logic

local addonName, TRP3FW = ...

-- Fallback burst helpers (ensure availability even if decision_helpers.lua hasn't loaded yet)
local BURST_MAX_AGE = 2.0
local function burstSettingsFingerprint_local()
    return table.concat({
        tostring(TRP3FW.Prefs and TRP3FW.Prefs.phaseCheckMode or "nil"),
        tostring(TRP3FW.Prefs and TRP3FW.Prefs.mapCheckMode or "nil"),
        tostring(TRP3FW.Prefs and TRP3FW.Prefs.blockStartPhase),
        tostring(TRP3FW.Prefs and TRP3FW.Prefs.ghostOnStartPhase),
        tostring(TRP3FW.Prefs and TRP3FW.Prefs.ghostProfileID or "")
    }, "|")
end

if not TRP3FW.GetBurstSettingsFingerprint then
    function TRP3FW:GetBurstSettingsFingerprint()
        return burstSettingsFingerprint_local()
    end
end

if not TRP3FW.IsBurstRequestStale then
    function TRP3FW:IsBurstRequestStale(queuedReq)
        local now = self:GetCurrentTime()
        local age = now - (queuedReq.queuedAt or now)
        if age > BURST_MAX_AGE then
            return true, "age"
        end

        if queuedReq.zoneSnapshot and self.lastZoneChangeTime and queuedReq.zoneSnapshot ~= self.lastZoneChangeTime then
            return true, "zone_change"
        end

        if queuedReq.phaseSnapshot and self.lastPhaseChangeTime and queuedReq.phaseSnapshot ~= self.lastPhaseChangeTime then
            return true, "phase_change"
        end

        local currentFingerprint = (self.GetBurstSettingsFingerprint and self:GetBurstSettingsFingerprint()) or burstSettingsFingerprint_local()
        if queuedReq.settingsFingerprint and queuedReq.settingsFingerprint ~= currentFingerprint then
            return true, "settings_change"
        end

        return false, nil
    end
end

-- Shallow-copy `locationResult` (and inner `cacheInfo`/`checkDetails`) so per-queued-request
-- mutations in ApplyLocationDecision don't leak across burst siblings.
local function CloneLocationResult(src)
    if not src then return nil end
    local copy = {}
    for k, v in pairs(src) do copy[k] = v end
    if src.cacheInfo then
        copy.cacheInfo = {}
        for k, v in pairs(src.cacheInfo) do copy.cacheInfo[k] = v end
    end
    if src.checkDetails then
        copy.checkDetails = {}
        for k, v in pairs(src.checkDetails) do copy.checkDetails[k] = v end
    end
    return copy
end

-- Build a context for a queued burst request, inheriting `isUserInitiated` from the
-- original burst (M8: avoid re-evaluating, since the userInitiatedQueries TTL may have
-- expired between the original request and the queued replay).
local function BuildQueuedContext(originalContext, req)
    return {
        now = req.timestamp,
        settings = originalContext.settings,
        playerName = originalContext.playerName,
        addon = req.addon,
        isWhisper = req.isWhisper,
        sendId = req.sendId,
        originalFunc = req.originalFunc,
        originalArgs = req.originalArgs,
        isFirstTime = req.isFirstTime,
        suppressedCount = req.suppressedCount,
        isUserInitiated = originalContext.isUserInitiated,
        isMSPAutoReply = originalContext.isMSPAutoReply
    }
end

-- N15: Replay queued burst requests with the same decision the original request resolved
-- to. Consolidates three near-identical loops (SPVP-rescue verified, SPVP-rescue failed,
-- no-rescue path). Each queued request gets its own locationResult clone so per-request
-- mutations in ApplyLocationDecision don't leak across burst siblings.
function TRP3FW:ReplayQueuedRequests(playerName, originalContext, locationResult, shouldBlock, shouldAlert, useGhost, label)
    if not (self.pendingLocationChecks and self.pendingLocationChecks[playerName]) then return end
    local queuedRequests = self.pendingLocationChecks[playerName].queuedRequests
    self.pendingLocationChecks[playerName] = nil
    if not queuedRequests or #queuedRequests == 0 then return end

    label = label or "queued"
    self:Debug("Batch processing "..#queuedRequests.." "..label.." requests for "..playerName, "send")

    for _, req in ipairs(queuedRequests) do
        local stale, reason = self:IsBurstRequestStale(req)
        if stale then
            self:Debug("Dropping stale "..label.." request for "..playerName.." ("..tostring(reason)..")", "send")
        else
            local queuedContext = BuildQueuedContext(originalContext, req)
            self:ApplyLocationDecision(queuedContext, shouldBlock, shouldAlert, useGhost, CloneLocationResult(locationResult))
        end
    end
end

-- ===================== Profile Send Handling =====================

function TRP3FW:TrackAddonRequest(addon, sendId)
    local service = self.ServiceContainer:Get("HistoryService")
    if service then
        service:TrackAddonRequest(addon, sendId)
    end
end

function TRP3FW:AllowSender(playerName, reason)
    local now = self:GetCurrentTime()
    local cleanName = self:SanitizePlayerName(playerName) or self:CleanPlayerName(playerName)
    if not cleanName then
        self:Debug("[AllowSender] Rejected invalid player name: "..tostring(playerName), "security")
        return
    end
    -- MSP debounce: prevent rapid repeat allow from the same target
    self.mspAllowDebounce = self.mspAllowDebounce or {}
    local last = self.mspAllowDebounce[cleanName]
    if last and (now - last) < 3 then
        self:Debug("[AllowSender] Debounced MSP allow for "..cleanName.." (too recent)", "security")
        return
    end
    self.mspAllowDebounce[cleanName] = now

    -- MSP rolling window throttle: cap per-target auto replies in a short window to reduce spam
    self.mspTargetWindow = self.mspTargetWindow or {}
    local window = self.mspTargetWindow[cleanName]
    if not window or (now - (window.start or 0)) > 10 then
        window = { start = now, count = 0 }
        self.mspTargetWindow[cleanName] = window
    end
    if window.count >= 5 then
        self:Debug("[AllowSender] Throttled MSP replies to "..cleanName.." (5 per 10s limit)", "security")
        return
    end
    window.count = window.count + 1

    -- Use CacheInterface
    local CI = self.CacheInterface
    if CI then
        -- OPTIMIZATION: Only refresh cache if it's stale (prevents write churn on every packet)
        -- Refresh threshold: percentage of TTL (default 10%)
        local ttl = TRP3FW.Prefs.sendCacheDuration or 600
        local refreshPercent = TRP3FW.Prefs.sendCacheRefreshRate or 10
        local refreshThreshold = ttl * (refreshPercent / 100)

        local cached = CI:Get("allowedSenders", cleanName)
        if cached and (now - cached.timestamp) < refreshThreshold then
            self:Debug("[AllowSender] Skipping cache update for '"..cleanName.."' (age < "..string.format("%.1f", refreshThreshold).."s)", "cache")
            return
        end

        CI:Set("allowedSenders", cleanName, {
            timestamp = now,
            reason = reason or "manual"
        })
    end

    local duration = TRP3FW.Prefs.sendCacheDuration
    self:Debug("[AllowSender] ADDED to cache: '"..cleanName.."' (reason: "..(reason or "manual")..", duration: "..duration.."s)", "cache")
    self:Debug("[Send Cache] Added: "..cleanName.." (reason: "..(reason or "manual")..")", "send")
end



-- =====================================================================================
-- FINAL VERSION (V2 Standard)
-- =====================================================================================

function TRP3FW:CheckLocationAndNotify(playerName, addon, isWhisper, sendId, originalFunc, originalArgs)
    if self:IsFeatureEnabled("enableRefactorLogging") then
        self:DebugRefactor("CheckLocationAndNotify (Pipeline) called", "DECISION")
    end

    -- Cache time once per request to avoid repeated syscalls along the pipeline.
    local now = self:GetCurrentTime()

    -- CRITICAL: Create context object ONCE (TOCTOU fix)
    local context = self:CreateDecisionContext(playerName, addon, isWhisper, sendId, originalFunc, originalArgs, now)

    self:Debug("=== CheckLocationAndNotify START for "..playerName.." ===", "send")
    self:Debug("  addon: "..tostring(addon)..", isWhisper: "..tostring(isWhisper)..", sendId: "..tostring(sendId), "send")

    -- Flag MSP automatic replies (e.g., mutual exchanges triggered by MSP callbacks) to suppress allow spam
    if addon == "MSP" and self.IsPendingMSPAutoReply then
        context.isMSPAutoReply = self:IsPendingMSPAutoReply(playerName)
        if context.isMSPAutoReply then
            self:Debug("[MSP Auto Reply] Suppressing allow notification for "..playerName, "send")
        end
    end

    -- Track whether this send follows a user-initiated query (mouse over / target / manual request)
    context.isUserInitiated = self:IsUserInitiatedExchange(playerName)

    -- Run Pipeline
    local result = self.DecisionPipeline:Run(context)

    return result.allowed
end

-- =====================================================================================
-- CONTEXT FACTORY
-- =====================================================================================

function TRP3FW:CreateDecisionContext(playerName, addon, isWhisper, sendId, originalFunc, originalArgs, now)
    local snapshotNow = now or self:GetCurrentTime()
    return {
        -- Time snapshot (prevents TOCTOU)
        now = snapshotNow,

        -- Settings snapshot (prevents TOCTOU)
        settings = {
            notifyEnabled = TRP3FW.Prefs.notifyEnabled,
            notifyOnAllow = TRP3FW.Prefs.notifyOnAllow,
            notifyOnWhisper = TRP3FW.Prefs.notifyOnWhisper,
            notifyOnBroadcast = TRP3FW.Prefs.notifyOnBroadcast,
            notifyOnStartPhaseBlock = TRP3FW.Prefs.notifyOnStartPhaseBlock,
            showOnScreen = TRP3FW.Prefs.showOnScreen,
            playSound = TRP3FW.Prefs.playSound,
            showGhostNotifications = TRP3FW.Prefs.showGhostNotifications,
            refreshSuppression = TRP3FW.Prefs.refreshSuppression,
            suppressionTime = TRP3FW.Prefs.suppressionTime,
            phaseInDelay = TRP3FW.Prefs.phaseInDelay,
            phaseCheckMode = TRP3FW.Prefs.phaseCheckMode,
            mapCheckMode = TRP3FW.Prefs.mapCheckMode,
            blockStartPhase = TRP3FW.Prefs.blockStartPhase,
            ghostOnStartPhase = TRP3FW.Prefs.ghostOnStartPhase,
            ghostProfileID = TRP3FW.Prefs.ghostProfileID,
            spvpEnabled = TRP3FW.Prefs.spvpEnabled,
            spvpMode = TRP3FW.Prefs.spvpMode,
            spvpAutoInitialize = TRP3FW.Prefs.spvpAutoInitialize,
            spvpBlockDuration = TRP3FW.Prefs.spvpBlockDuration,
            spvpSaltCacheDuration = TRP3FW.Prefs.spvpSaltCacheDuration,
            spvpPerPhaseOverrides = TRP3FW.Prefs.spvpPerPhaseOverrides,
            interactionCacheDuration = TRP3FW.Prefs.interactionCacheDuration,
        },

        -- Request parameters
        playerName = playerName,
        addon = addon,
        isWhisper = isWhisper,
        sendId = sendId,
        originalFunc = originalFunc,
        originalArgs = originalArgs,
    }
end

-- ===================== BURST PROCESSING HELPERS =====================

function TRP3FW:ProcessBurstAllows(playerName)
    -- 1. Process MSP queued requests
    if self.pendingMSPReplies and self.pendingMSPReplies[playerName] then
        local queuedRequests = self.pendingMSPReplies[playerName].queuedRequests or {}
        for _, queuedReq in ipairs(queuedRequests) do
            self:Debug("Processing queued MSP request for "..playerName.." with ALLOW decision", "send")
            if self.originalMSPReply then
                local success, err = pcall(self.originalMSPReply, queuedReq.sender, queuedReq.fields)
                if not success then
                    self:Debug("ERROR calling original MSP Reply for queued request: "..tostring(err), "send")
                end
            end
        end
        self.pendingMSPReplies[playerName] = nil
    end

    -- 2. Process TRP3/Chomp queued requests
    local queues = {
        { tbl = self.pendingTRP3Sends, orig = self.originalTRP3Send, label = "TRP3" },
        { tbl = self.pendingChompSends, orig = self.originalChompSend, label = "Chomp" }
    }

    for _, q in ipairs(queues) do
        if q.tbl and q.tbl[playerName] then
            local queuedRequests = q.tbl[playerName].queuedRequests or {}
            for _, queuedReq in ipairs(queuedRequests) do
                local stale, reason = self:IsBurstRequestStale(queuedReq)
                if stale then
                    self:Debug("Dropping stale "..q.label.." burst allow for "..playerName.." ("..tostring(reason)..")", "send")
                else
                    self:Debug("Processing queued "..q.label.." request for "..playerName.." with ALLOW decision", "send")
                    if q.orig then
                        local success, err
                        if q.label == "TRP3" then
                            success, err = pcall(q.orig, queuedReq.self, queuedReq.messageType, queuedReq.data, queuedReq.target, queuedReq.priority)
                        else
                            success, err = pcall(q.orig, queuedReq.prefix, queuedReq.text, queuedReq.chatType, queuedReq.target, queuedReq.priority, queuedReq.queue, queuedReq.callback, queuedReq.callbackArg)
                        end
                        if not success then
                            self:Debug("ERROR calling original "..q.label.." for queued request: "..tostring(err), "send")
                        end
                    end
                end
            end
            q.tbl[playerName] = nil
        end
    end
end

function TRP3FW:ProcessBurstBlocks(playerName, useGhostMode)
    -- 1. Process MSP queued requests
    if self.pendingMSPReplies and self.pendingMSPReplies[playerName] then
        local queuedRequests = self.pendingMSPReplies[playerName].queuedRequests or {}
        for _, queuedReq in ipairs(queuedRequests) do
            if useGhostMode then
                local stale, reason = self:IsBurstRequestStale(queuedReq)
                if stale then
                    self:Debug("Dropping stale MSP burst ghost/block for "..playerName.." ("..tostring(reason)..")", "send")
                else
                    self:Debug("Processing queued MSP request for "..playerName.." with GHOST decision", "send")
                    local success = self:EnableGhostForNextSend(playerName, TRP3FW.Prefs.ghostProfileID)
                    if success and self.originalMSPReply then
                        pcall(self.originalMSPReply, queuedReq.sender, queuedReq.fields)
                    end
                end
            end
        end
        self.pendingMSPReplies[playerName] = nil
    end

    -- 2. Process TRP3/Chomp queued requests
    local queues = {
        { tbl = self.pendingTRP3Sends, orig = self.originalTRP3Send, label = "TRP3" },
        { tbl = self.pendingChompSends, orig = self.originalChompSend, label = "Chomp" }
    }

    for _, q in ipairs(queues) do
        if q.tbl and q.tbl[playerName] then
            local queuedRequests = q.tbl[playerName].queuedRequests or {}
            for _, queuedReq in ipairs(queuedRequests) do
                if useGhostMode and self.hasTRP3ExchangeHooks then
                    local stale, reason = self:IsBurstRequestStale(queuedReq)
                    if not stale then
                        self:Debug("Processing queued "..q.label.." request for "..playerName.." with GHOST decision", "send")
                        local success = self:EnableGhostForNextSend(playerName, TRP3FW.Prefs.ghostProfileID)
                        if success and q.orig then
                            if q.label == "TRP3" then
                                pcall(q.orig, queuedReq.self, queuedReq.messageType, queuedReq.data, queuedReq.target, queuedReq.priority)
                            else
                                pcall(q.orig, queuedReq.prefix, queuedReq.text, queuedReq.chatType, queuedReq.target, queuedReq.priority, queuedReq.queue, queuedReq.callback, queuedReq.callbackArg)
                            end
                        end
                    end
                end
            end
            q.tbl[playerName] = nil
        end
    end
end

-- =====================================================================================
-- LOCATION DECISION LOGIC
-- =====================================================================================

-- =====================================================================================
-- LOCATION DECISION LOGIC
-- =====================================================================================

function TRP3FW:ApplyLocationDecision(context, shouldBlock, shouldAlert, useGhostMode, locationResult)
    local alertType = locationResult.alertType
    local shouldNotify = false

    if context.settings.notifyEnabled then
        if shouldBlock then
            if alertType == "start_phase_block" then
                shouldNotify = context.settings.notifyOnStartPhaseBlock
            elseif shouldAlert then
                shouldNotify = true
            end
        elseif shouldAlert then
            shouldNotify = true
        else
            shouldNotify = context.settings.notifyOnAllow
        end
    end

    local isMSPUserInitiated = (context.addon == "MSP") and context.isUserInitiated
    if not shouldAlert and not shouldBlock and isMSPUserInitiated then
        -- Mouseover/target-driven MSP queries we initiated; suppress allow spam
        self:Debug("[MSP User Initiated] Suppressing allow notification for "..tostring(context.playerName), "send")
        -- Refresh suppression window so repeated mouseovers stay quiet, but avoid excessive churn (<10% of window)
        local notificationService = self.ServiceContainer:Get("NotificationService")
        if notificationService then
            local history = notificationService.suppressionHistory and notificationService.suppressionHistory[context.playerName]
            local now = self:GetCurrentTime()
            local threshold = (context.settings.suppressionTime or 10) / 10
            if not history or not history.lastNotification or (now - history.lastNotification) >= threshold then
                notificationService:ShouldSuppress(context.playerName, "allow", context.settings)
            end
        end
        shouldNotify = false
    end

    -- Ensure alert+block modes always notify (even if shouldAlert was not set due to edge cases),
    -- but still honor the master notify toggle.
    if context.settings.notifyEnabled and shouldBlock and alertType and (self:ShouldAlertOnPhase() or self:ShouldAlertOnMap()) then
        shouldNotify = true
    end

    if shouldNotify then
        if context.isWhisper and not context.settings.notifyOnWhisper then shouldNotify = false end
        if not context.isWhisper and not context.settings.notifyOnBroadcast then shouldNotify = false end
    end

    -- Check suppression (NotificationService handles suppression state)
    local isFirstTime = context.isFirstTime
    local suppressedCount = context.suppressedCount

    -- Allow ghost-mode notifications when explicitly enabled.
    local ghostNotificationBlocked = shouldBlock and useGhostMode and not context.settings.showGhostNotifications

    -- LOGGING: Trace final notification decision
    local debugType = shouldBlock and "block" or (shouldAlert and "alert" or "allow")
    TRP3FW:Debug("[Decision] Notify check: shouldNotify="..tostring(shouldNotify)..", blocked="..tostring(ghostNotificationBlocked)..", type="..debugType, "send")

    if shouldNotify and not ghostNotificationBlocked then
        local notificationService = self.ServiceContainer:Get("NotificationService")
        local notifType
        if shouldBlock then
            notifType = useGhostMode and "ghost" or "block"
        elseif shouldAlert then
            notifType = "alert"
        else
            notifType = "allow"
        end

        TRP3FW:Debug("[Decision] Dispatching notification: type="..tostring(notifType), "send")

        if notificationService then
            notificationService:Notify(context.playerName, {
                type = notifType,
                addon = context.addon,
                reason = alertType or (locationResult.locationOK and "location_ok") or nil,
                isWhisper = context.isWhisper,
                settings = context.settings,
                locationResult = locationResult,
                cacheInfo = locationResult.cacheInfo,
                checkDetails = locationResult.checkDetails,
                contextDetails = nil,
            })
        else
            -- Fallback: preserve legacy direct notification if service unavailable
            self:ShowChatNotification(
                context.playerName,
                context.addon,
                isFirstTime,
                suppressedCount,
                shouldAlert,
                nil,
                nil,
                locationResult.theirZone,
                locationResult.myZone,
                alertType,
                shouldBlock,
                locationResult.mapCacheAge,
                locationResult.cacheInfo,
                locationResult.recentTransition,
                locationResult.timeSinceTransition,
                useGhostMode,
                locationResult.checkDetails
            )
        end
    end

    -- All session-stat increments (alerts/blocks/ghostSends/phaseAlerts/mapAlerts/
    -- startPhaseBlocks) happen inside RecordHistory. Do NOT IncrementStat them here.
    self:RecordHistory(context.playerName, context.addon, shouldAlert, shouldBlock, useGhostMode, alertType)

    if shouldBlock then
        if useGhostMode then
             local alternateProfileID = TRP3FW.Prefs.ghostProfileID
             self:EnableGhostForNextSend(context.playerName, alternateProfileID)
             if context.originalFunc then
                 pcall(context.originalFunc, unpack(context.originalArgs))
             end
        end

        -- Process queued burst requests (BLOCK/GHOST)
        -- Note: These process pendingMSPReplies/pendingTRP3Sends/pendingChompSends
        -- which are separate from the pendingLocationChecks queue
        self:ProcessBurstBlocks(context.playerName, useGhostMode)
    else
        self:AllowSender(context.playerName, "location_ok")
        if context.originalFunc then
            pcall(context.originalFunc, unpack(context.originalArgs))
        end

        -- Process queued burst requests (ALLOW)
        self:ProcessBurstAllows(context.playerName)
    end
end

function TRP3FW:ProcessLocationDecision(context, locationResult)
    -- locationResult: { locationOK, alertType, source, mapCacheAge, theirZone, myZone, cacheInfo, recentTransition, timeSinceTransition, checkDetails }

    local shouldAlert = false
    local shouldBlock = false
    local alertType = locationResult.alertType
    local locationOK = locationResult.locationOK

    if locationOK == false and alertType then
        if alertType == "start_phase_block" then
            shouldBlock = true
        elseif alertType:find("phase") then
            if self:ShouldAlertOnPhase() then shouldAlert = true end
            if self:ShouldBlockOnPhase() then shouldBlock = true end
        end
        if alertType:find("map") then
            if self:ShouldAlertOnMap() then shouldAlert = true end
            if self:ShouldBlockOnMap() then shouldBlock = true end
        end
    end

    local useGhostModeForThisSend = false
    if shouldBlock then
        if alertType == "start_phase_block" then
             useGhostModeForThisSend = context.settings.ghostOnStartPhase
        else
            useGhostModeForThisSend = (
                (alertType and alertType:find("phase") and self:ShouldGhostOnPhase()) or
                (alertType and alertType:find("map") and self:ShouldGhostOnMap())
            )
        end
    end

    -- SPVP Fallback: If location checks failed, try cryptographic verification as last resort
    if shouldBlock and context.settings.spvpEnabled and self.hasEpsilonAPI then
        local currentPhaseID = self:GetCurrentPhaseID()

        -- Check if SPVP was already verified in the pipeline (but we are still blocking, e.g. strict map check)
        local spvpDetails = locationResult.checkDetails and locationResult.checkDetails.spvp
        local alreadyVerified = spvpDetails and spvpDetails.result == true

        if alreadyVerified then
             self:Debug("SPVP already verified but block persists (Strict Map Check) - Skipping rescue", "spvp")
             -- Do NOT attempt rescue, fall through to ApplyLocationDecision (BLOCK)
        -- Hard exclusion: Never use SPVP in Phase 169 (Start Phase)
        elseif currentPhaseID and currentPhaseID ~= 169 then
            -- Check if phase has SPVP salt configured (use cached salt)
            local phaseSalt = self:GetPhaseSalt(currentPhaseID, false)
            local hasSalt = (phaseSalt and phaseSalt ~= "")

            if hasSalt then
                self:Debug(string.format("SPVP fallback: Location failed for %s, trying crypto", context.playerName), "spvp")

                -- Initiate SPVP handshake (async with timeout/retry)
                self:CheckPlayerViaSPVP(context.playerName, context.sendId, function(verified, reason)
                    -- Mark location result
                    locationResult.spvpAttempted = true
                    locationResult.spvpReason = reason

                    if verified then
                        -- SPVP verification passed! Override location failure
                        self:Debug(string.format("SPVP rescue: %s VERIFIED, overriding block", context.playerName), "spvp")
                        locationResult.spvpRescue = true

                        -- Allow the request (override shouldBlock)
                        self:ApplyLocationDecision(context, false, false, false, locationResult)
                        self:ReplayQueuedRequests(context.playerName, context, locationResult, false, false, false, "SPVP-rescue allow")
                    else
                        -- SPVP failed/timed out - proceed with block/ghost
                        self:Debug(string.format("SPVP rescue: %s FAILED (%s), blocking", context.playerName, reason or "unknown"), "spvp")
                        locationResult.spvpFailed = true

                        -- Apply original block/ghost decision
                        self:ApplyLocationDecision(context, shouldBlock, shouldAlert, useGhostModeForThisSend, locationResult)
                        self:ReplayQueuedRequests(context.playerName, context, locationResult, shouldBlock, shouldAlert, useGhostModeForThisSend, "SPVP-rescue block/ghost")
                    end
                end)

                -- Return early - decision will be applied in SPVP callback
                return
            end
        end
    end

    -- No SPVP fallback - apply normal decision
    self:ApplyLocationDecision(context, shouldBlock, shouldAlert, useGhostModeForThisSend, locationResult)
    self:ReplayQueuedRequests(context.playerName, context, locationResult, shouldBlock, shouldAlert, useGhostModeForThisSend, "burst")
end

-- Alias for LocationStage to call
function TRP3FW:Pipeline_DecisionStage(context, locationResult)
    self:ProcessLocationDecision(context, locationResult)
end
