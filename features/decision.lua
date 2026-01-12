-- features/decision.lua
-- Core allow/block decision logic

local addonName, TRP3FW = ...

-- Fallback burst helpers (ensure availability even if decision_helpers.lua hasn't loaded yet)
local BURST_MAX_AGE = 2.0
local function burstSettingsFingerprint_local()
    return table.concat({
        tostring(TRP3FW_Settings and TRP3FW_Settings.phaseCheckMode or "nil"),
        tostring(TRP3FW_Settings and TRP3FW_Settings.mapCheckMode or "nil"),
        tostring(TRP3FW_Settings and TRP3FW_Settings.blockStartPhase),
        tostring(TRP3FW_Settings and TRP3FW_Settings.ghostOnStartPhase),
        tostring(TRP3FW_Settings and TRP3FW_Settings.ghostProfileID or "")
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

-- ===================== Profile Send Handling =====================

function TRP3FW:TrackAddonRequest(addon, sendId)
    -- Track requests by addon with sendId deduplication
    -- FIXED: LOW-3 - Validate addon parameter type and value
    if not addon or type(addon) ~= "string" then
        self:Debug("[SECURITY] Invalid addon parameter in TrackAddonRequest", "security")
        return
    end

    -- Whitelist of valid addons
    local validAddons = {TRP3 = true, MRP = true, XRP = true, MSP = true}

    local addonKey = addon:upper()
    if not validAddons[addonKey] then
        self:Debug("[SECURITY] Rejected invalid addon type: "..tostring(addon), "security")
        return
    end

    if not self.sessionStats.requestsByAddon[addonKey] then
        return -- Stats not initialized for this addon yet
    end

    -- Deduplicate by sendId
    if not self.lastAddonRequestSendId then
        self.lastAddonRequestSendId = {}
    end

    if not self.lastAddonRequestSendId[sendId] then
        -- First time seeing this sendId - count it
        self.sessionStats.requestsByAddon[addonKey] = self.sessionStats.requestsByAddon[addonKey] + 1
        self.lastAddonRequestSendId[sendId] = true
        self.lastAddonRequestSendIdCount = (self.lastAddonRequestSendIdCount or 0) + 1
        self:Debug("Tracked addon request: "..addon.." (sendId: "..tostring(sendId)..")", "send")
    else
        -- Already counted this sendId
        self:Debug("Duplicate sendId "..tostring(sendId).." for addon "..addon..", skipping addon stat increment", "send")
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
        local ttl = TRP3FW_Settings.sendCacheDuration or 600
        local refreshPercent = TRP3FW_Settings.sendCacheRefreshRate or 10
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

    local duration = TRP3FW_Settings.sendCacheDuration
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
            notifyEnabled = TRP3FW_Settings.notifyEnabled,
            notifyOnAllow = TRP3FW_Settings.notifyOnAllow,
            notifyOnWhisper = TRP3FW_Settings.notifyOnWhisper,
            notifyOnBroadcast = TRP3FW_Settings.notifyOnBroadcast,
            notifyOnStartPhaseBlock = TRP3FW_Settings.notifyOnStartPhaseBlock,
            showOnScreen = TRP3FW_Settings.showOnScreen,
            playSound = TRP3FW_Settings.playSound,
            showGhostNotifications = TRP3FW_Settings.showGhostNotifications,
            refreshSuppression = TRP3FW_Settings.refreshSuppression,
            suppressionTime = TRP3FW_Settings.suppressionTime,
            phaseInDelay = TRP3FW_Settings.phaseInDelay,
            phaseCheckMode = TRP3FW_Settings.phaseCheckMode,
            mapCheckMode = TRP3FW_Settings.mapCheckMode,
            blockStartPhase = TRP3FW_Settings.blockStartPhase,
            ghostOnStartPhase = TRP3FW_Settings.ghostOnStartPhase,
            ghostProfileID = TRP3FW_Settings.ghostProfileID,
            spvpEnabled = TRP3FW_Settings.spvpEnabled,
            spvpMode = TRP3FW_Settings.spvpMode,
            spvpAutoInitialize = TRP3FW_Settings.spvpAutoInitialize,
            spvpBlockDuration = TRP3FW_Settings.spvpBlockDuration,
            spvpSaltCacheDuration = TRP3FW_Settings.spvpSaltCacheDuration,
            spvpPerPhaseOverrides = TRP3FW_Settings.spvpPerPhaseOverrides,
            interactionCacheDuration = TRP3FW_Settings.interactionCacheDuration,
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

-- =====================================================================================
-- BURST PROCESSING HELPERS
-- =====================================================================================

function TRP3FW:ProcessMSPBurstAllows(playerName)
    -- Process queued MSP burst requests
    if self.pendingMSPReplies and self.pendingMSPReplies[playerName] then
        local queuedRequests = self.pendingMSPReplies[playerName].queuedRequests or {}
        for _, queuedReq in ipairs(queuedRequests) do
            self:Debug("Processing queued MSP request for "..playerName.." with ALLOW decision", "send")
            if self.originalMSPReply then
                local success, err = pcall(self.originalMSPReply, queuedReq.sender, queuedReq.fields)
                if not success then
                    self:Debug("ERROR calling original MSP Reply for queued request: "..tostring(err), "send")
                else
                    self:Debug("Queued MSP request allowed and sent successfully", "send")
                end
            end
        end
        self.pendingMSPReplies[playerName] = nil
    end
end

function TRP3FW:ProcessTRP3BurstAllows(playerName)
    -- Process queued TRP3 Send Hook queued requests
    if self.pendingTRP3Sends and self.pendingTRP3Sends[playerName] then
        local queuedRequests = self.pendingTRP3Sends[playerName].queuedRequests or {}
        for _, queuedReq in ipairs(queuedRequests) do
            local stale, reason = self:IsBurstRequestStale(queuedReq)
            if stale then
                self:Debug("Dropping stale TRP3 burst allow for "..playerName.." ("..tostring(reason)..")", "send")
            else
                self:Debug("Processing queued TRP3 Send request for "..playerName.." with ALLOW decision (from burst)", "send")
                if self.originalTRP3Send then
                    local success, err = pcall(self.originalTRP3Send, queuedReq.self, queuedReq.messageType, queuedReq.data, queuedReq.target, queuedReq.priority)
                    if not success then
                        self:Debug("ERROR calling original TRP3 Send for queued request: "..tostring(err), "send")
                    else
                        self:Debug("Queued TRP3 Send request allowed and sent successfully", "send")
                    end
                end
            end
        end
        self.pendingTRP3Sends[playerName] = nil
    end

    -- Process Chomp Hook queued requests
    if self.pendingChompSends and self.pendingChompSends[playerName] then
        local queuedRequests = self.pendingChompSends[playerName].queuedRequests or {}
        for _, queuedReq in ipairs(queuedRequests) do
            local stale, reason = self:IsBurstRequestStale(queuedReq)
            if stale then
                self:Debug("Dropping stale Chomp burst allow for "..playerName.." ("..tostring(reason)..")", "send")
            else
                self:Debug("Processing queued Chomp request for "..playerName.." with ALLOW decision (from burst)", "send")
                if self.originalChompSend then
                    local success, err = pcall(self.originalChompSend, queuedReq.prefix, queuedReq.text, queuedReq.chatType, queuedReq.target, queuedReq.priority, queuedReq.queue, queuedReq.callback, queuedReq.callbackArg)
                    if not success then
                        self:Debug("ERROR calling original Chomp for queued request: "..tostring(err), "send")
                    else
                        self:Debug("Queued Chomp request allowed and sent successfully", "send")
                    end
                end
            end
        end
        self.pendingChompSends[playerName] = nil
    end
end

function TRP3FW:ProcessTRP3BurstBlocks(playerName, useGhostMode)
    -- Process TRP3 Send Hook queued requests
    if self.pendingTRP3Sends and self.pendingTRP3Sends[playerName] then
        local queuedRequests = self.pendingTRP3Sends[playerName].queuedRequests or {}
        for _, queuedReq in ipairs(queuedRequests) do
            if useGhostMode and self.hasTRP3ExchangeHooks then
                local stale, reason = self:IsBurstRequestStale(queuedReq)
                if stale then
                    self:Debug("Dropping stale TRP3 burst ghost/block for "..playerName.." ("..tostring(reason)..")", "send")
                else
                    self:Debug("Processing queued TRP3 Send request for "..playerName.." with GHOST decision (from burst)", "send")
                    local alternateProfileID = TRP3FW_Settings.ghostProfileID
                    local success = self:EnableGhostForNextSend(playerName, alternateProfileID)
                    if success and self.originalTRP3Send then
                        local callSuccess, err = pcall(self.originalTRP3Send, queuedReq.self, queuedReq.messageType, queuedReq.data, queuedReq.target, queuedReq.priority)
                        if not callSuccess then
                            self:Debug("ERROR sending ghost profile for queued TRP3 Send request: "..tostring(err), "send")
                        else
                            self:Debug("Queued TRP3 Send request sent with ghost profile", "send")
                        end
                    else
                        self:Debug("Queued TRP3 Send request blocked (ghost mode failed)", "send")
                    end
                end
            else
                self:Debug("Processing queued TRP3 Send request for "..playerName.." with BLOCK decision (from burst)", "send")
            end
        end
        self.pendingTRP3Sends[playerName] = nil
    end

    -- Process Chomp Hook queued requests
    if self.pendingChompSends and self.pendingChompSends[playerName] then
        local queuedRequests = self.pendingChompSends[playerName].queuedRequests or {}
        for _, queuedReq in ipairs(queuedRequests) do
            if useGhostMode and self.hasTRP3ExchangeHooks then
                local stale, reason = self:IsBurstRequestStale(queuedReq)
                if stale then
                    self:Debug("Dropping stale Chomp burst ghost/block for "..playerName.." ("..tostring(reason)..")", "send")
                else
                    self:Debug("Processing queued Chomp request for "..playerName.." with GHOST decision (from burst)", "send")
                    local alternateProfileID = TRP3FW_Settings.ghostProfileID
                    local success = self:EnableGhostForNextSend(playerName, alternateProfileID)
                    if success and self.originalChompSend then
                        local callSuccess, err = pcall(self.originalChompSend, queuedReq.prefix, queuedReq.text, queuedReq.chatType, queuedReq.target, queuedReq.priority, queuedReq.queue, queuedReq.callback, queuedReq.callbackArg)
                        if not callSuccess then
                            self:Debug("ERROR sending ghost profile for queued Chomp request: "..tostring(err), "send")
                        else
                            self:Debug("Queued Chomp request sent with ghost profile", "send")
                        end
                    else
                        self:Debug("Queued Chomp request blocked (ghost mode failed)", "send")
                    end
                end
            else
                self:Debug("Processing queued Chomp request for "..playerName.." with BLOCK decision (from burst)", "send")
            end
        end
        self.pendingChompSends[playerName] = nil
    end
end

function TRP3FW:ProcessMSPBurstBlocks(playerName, useGhostMode)
    if self.pendingMSPReplies and self.pendingMSPReplies[playerName] then
        local mspQueuedRequests = self.pendingMSPReplies[playerName].queuedRequests or {}
        for _, queuedReq in ipairs(mspQueuedRequests) do
            if useGhostMode then
                local stale, reason = self:IsBurstRequestStale(queuedReq)
                if stale then
                    self:Debug("Dropping stale MSP burst ghost/block for "..playerName.." ("..tostring(reason)..")", "send")
                else
                    self:Debug("Processing queued MSP request for "..playerName.." with GHOST decision (from burst)", "send")
                    local alternateProfileID = TRP3FW_Settings.ghostProfileID
                    local ghostEnabled = self:EnableGhostForNextSend(playerName, alternateProfileID)
                    if ghostEnabled and self.originalMSPReply then
                        local success, err = pcall(self.originalMSPReply, queuedReq.sender, queuedReq.fields)
                        if not success then
                            self:Debug("ERROR sending ghost profile for queued MSP request: "..tostring(err), "send")
                        else
                            self:Debug("Queued MSP request sent with ghost profile", "send")
                        end
                    else
                        self:Debug("Queued MSP request blocked (ghost mode unavailable)", "send")
                    end
                end
            else
                self:Debug("Processing queued MSP request for "..playerName.." with BLOCK decision (from burst)", "send")
            end
        end
        self.pendingMSPReplies[playerName] = nil
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

    self:RecordHistory(context.playerName, context.addon, shouldAlert, shouldBlock)

    if shouldBlock then
        if useGhostMode then
             local alternateProfileID = TRP3FW_Settings.ghostProfileID
             self:EnableGhostForNextSend(context.playerName, alternateProfileID)
             if context.originalFunc then
                 pcall(context.originalFunc, unpack(context.originalArgs))
             end
        end

        -- Process queued burst requests (BLOCK/GHOST)
        -- Note: These process pendingMSPReplies/pendingTRP3Sends/pendingChompSends
        -- which are separate from the pendingLocationChecks queue
        self:ProcessMSPBurstBlocks(context.playerName, useGhostMode)
        self:ProcessTRP3BurstBlocks(context.playerName, useGhostMode)
    else
        self:AllowSender(context.playerName, "location_ok")
        if context.originalFunc then
            pcall(context.originalFunc, unpack(context.originalArgs))
        end

        -- Process queued burst requests (ALLOW)
        self:ProcessMSPBurstAllows(context.playerName)
        self:ProcessTRP3BurstAllows(context.playerName)
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

                        -- Process queued burst requests with ALLOW
                        if self.pendingLocationChecks and self.pendingLocationChecks[context.playerName] then
                            local queuedRequests = self.pendingLocationChecks[context.playerName].queuedRequests
                            self.pendingLocationChecks[context.playerName] = nil

                            if queuedRequests and #queuedRequests > 0 then
                                for _, req in ipairs(queuedRequests) do
                                    local stale = self:IsBurstRequestStale(req)
                                    if not stale then
                                        local queuedContext = {
                                            now = req.timestamp,
                                            settings = context.settings,
                                            playerName = context.playerName,
                                            addon = req.addon,
                                            isWhisper = req.isWhisper,
                                            sendId = req.sendId,
                                            originalFunc = req.originalFunc,
                                            originalArgs = req.originalArgs,
                                            isFirstTime = req.isFirstTime,
                                            suppressedCount = req.suppressedCount,
                                            isUserInitiated = self:IsUserInitiatedExchange(context.playerName),
                                            isMSPAutoReply = context.isMSPAutoReply
                                        }
                                        self:ApplyLocationDecision(queuedContext, false, false, false, locationResult)
                                    end
                                end
                            end
                        end
                    else
                        -- SPVP failed/timed out - proceed with block/ghost
                        self:Debug(string.format("SPVP rescue: %s FAILED (%s), blocking", context.playerName, reason or "unknown"), "spvp")
                        locationResult.spvpFailed = true

                        -- Apply original block/ghost decision
                        self:ApplyLocationDecision(context, shouldBlock, shouldAlert, useGhostModeForThisSend, locationResult)

                        -- Process queued burst requests with BLOCK/GHOST
                        if self.pendingLocationChecks and self.pendingLocationChecks[context.playerName] then
                            local queuedRequests = self.pendingLocationChecks[context.playerName].queuedRequests
                            self.pendingLocationChecks[context.playerName] = nil

                            if queuedRequests and #queuedRequests > 0 then
                                for _, req in ipairs(queuedRequests) do
                                    local stale = self:IsBurstRequestStale(req)
                                    if not stale then
                                        local queuedContext = {
                                            now = req.timestamp,
                                            settings = context.settings,
                                            playerName = context.playerName,
                                            addon = req.addon,
                                            isWhisper = req.isWhisper,
                                            sendId = req.sendId,
                                            originalFunc = req.originalFunc,
                                            originalArgs = req.originalArgs,
                                            isFirstTime = req.isFirstTime,
                                            suppressedCount = req.suppressedCount,
                                            isUserInitiated = self:IsUserInitiatedExchange(context.playerName),
                                            isMSPAutoReply = context.isMSPAutoReply
                                        }
                                        self:ApplyLocationDecision(queuedContext, shouldBlock, shouldAlert, useGhostModeForThisSend, locationResult)
                                    end
                                end
                            end
                        end
                    end
                end)

                -- Return early - decision will be applied in SPVP callback
                return
            end
        end
    end

    -- No SPVP fallback - apply normal decision
    self:ApplyLocationDecision(context, shouldBlock, shouldAlert, useGhostModeForThisSend, locationResult)

    -- Process queued requests efficiently
    if self.pendingLocationChecks and self.pendingLocationChecks[context.playerName] then
        local queuedRequests = self.pendingLocationChecks[context.playerName].queuedRequests
        self.pendingLocationChecks[context.playerName] = nil -- Clear pending check

        if queuedRequests and #queuedRequests > 0 then
            self:Debug("Batch processing "..#queuedRequests.." queued requests for "..context.playerName, "send")
            
            for _, req in ipairs(queuedRequests) do
                local stale, reason = self:IsBurstRequestStale(req)
                if stale then
                    self:Debug("Dropping stale queued request for "..context.playerName.." ("..tostring(reason)..")", "send")
                else
                    -- OPTIMIZATION: Instead of re-submitting to the pipeline (which triggers overhead and recursion),
                    -- apply the SAME decision we just reached to all valid queued requests from this burst.
                    -- They are from the same player, same time window, and same settings snapshot.
                    
                    local queuedContext = {
                        now = req.timestamp,
                        settings = context.settings, -- Safe because fingerprint matched
                        playerName = context.playerName,
                        addon = req.addon,
                        isWhisper = req.isWhisper,
                        sendId = req.sendId,
                        originalFunc = req.originalFunc,
                        originalArgs = req.originalArgs,
                        isFirstTime = req.isFirstTime,
                        suppressedCount = req.suppressedCount,
                        -- Re-evaluate dynamic flags if needed, but for burst they are likely consistent
                        isUserInitiated = self:IsUserInitiatedExchange(context.playerName),
                        isMSPAutoReply = context.isMSPAutoReply
                    }
                    
                    self:Debug("Applying batch decision to queued request (sendId: "..tostring(req.sendId)..")", "send")
                    self:ApplyLocationDecision(queuedContext, shouldBlock, shouldAlert, useGhostModeForThisSend, locationResult)
                end
            end
        end
    end
end

-- Alias for LocationStage to call
function TRP3FW:Pipeline_DecisionStage(context, locationResult)
    self:ProcessLocationDecision(context, locationResult)
end
