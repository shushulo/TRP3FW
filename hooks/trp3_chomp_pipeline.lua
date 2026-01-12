-- hooks/trp3_chomp_pipeline.lua
-- Pipeline stages for Chomp hook (Phase 1b refactoring)

local addonName, TRP3FW = ...

local function getBurstFingerprintSafe()
    if TRP3FW and TRP3FW.GetBurstSettingsFingerprint then
        return TRP3FW:GetBurstSettingsFingerprint()
    end
    return table.concat({
        tostring(TRP3FW_Settings and TRP3FW_Settings.phaseCheckMode or "nil"),
        tostring(TRP3FW_Settings and TRP3FW_Settings.mapCheckMode or "nil"),
        tostring(TRP3FW_Settings and TRP3FW_Settings.blockStartPhase),
        tostring(TRP3FW_Settings and TRP3FW_Settings.ghostOnStartPhase),
        tostring(TRP3FW_Settings and TRP3FW_Settings.ghostProfileID or "")
    }, "|")
end

-- =====================================================================================
-- CHOMP HOOK PIPELINE STAGES
-- =====================================================================================

function TRP3FW:ChompPipeline_GuardChecks_V2(prefix, text, chatType, target, priority, queue, callback, callbackArg)
    --[[
        Stage 1: Guard checks
        - Verify addon enabled
        - Check if we should process this request
        - Recursion guards

        Returns: {shouldContinue=bool, reason=string}
    ]]

    -- Ensure hook state table exists
    self.hookState = self.hookState or {}
    self.hookState.chomp = self.hookState.chomp or {}
    local chompState = self.hookState.chomp

    -- Check recursion guard
    if chompState.sendingGhostProfile then
        self:Debug("[Chomp Hook] Recursion guard active - skipping", "hooks")
        return {shouldContinue = false, reason = "recursion_guard"}
    end

    -- Check replay guard
    if chompState.replayingPhaseInSend then
        self:Debug("[Chomp Hook] Replay guard active - skipping", "hooks")
        return {shouldContinue = false, reason = "replay_guard"}
    end

    -- Check if addon is enabled
    if not TRP3FW_Settings.enabled then -- Assumes global enabled setting exists, otherwise check specific modules
        -- For now, just continue as there isn't a global 'enabled' toggle in defaultSettings
    end

    -- Check if TRP3 is available (implied by Chomp hook existence, but safe to check)
    if not AddOn_Chomp then
        return {shouldContinue = false, reason = "chomp_not_available"}
    end

    return {shouldContinue = true, reason = "guards_passed"}
end

function TRP3FW:ChompPipeline_PhaseInDelay_V2(playerName, prefix, text, chatType, target, priority, queue, callback, callbackArg)
    --[[
        Stage 2: Phase-in delay handling
        Similar to decision.lua phase-in delay, but for Chomp specifically

        Returns: {shouldContinue=bool, queued=bool}
    ]]

    self.hookState = self.hookState or {}
    self.hookState.chomp = self.hookState.chomp or {}
    local chompState = self.hookState.chomp

    local phaseInDelay = TRP3FW_Settings.phaseInDelay or 4
    if phaseInDelay > 0 and not chompState.replayingPhaseInSend then
        local now = self:GetCurrentTime()
        local timeSinceZoneChange = now - self.lastZoneChangeTime
        if timeSinceZoneChange < phaseInDelay then
            local delayRemaining = phaseInDelay - timeSinceZoneChange
            self:Debug(function()
                return "[Chomp Hook] Within phase-in delay window ("..string.format("%.1f", delayRemaining).."s remaining), queueing send to "..playerName
            end, "hooks")

            -- Bound queue size and evict stale entries before enqueue
            local queueList = self.pendingPhaseInSends
            local queueLimit = self.PHASE_IN_QUEUE_LIMIT or 200
            local ttl = math.max((TRP3FW_Settings.phaseInDelay or 4) * 3, 10)

            for i = #queueList, 1, -1 do
                local age = now - (queueList[i].queuedAt or 0)
                if age > ttl then
                    table.remove(queueList, i)
                end
            end

            if #queueList >= queueLimit then
                local dropped = table.remove(queueList, 1)
                self:Warn("[Chomp Hook] Phase-in queue full, dropping oldest queued send to "..tostring(dropped and self:CleanPlayerName(dropped.target) or "unknown"))
            end

            -- Queue this send to replay after delay
            table.insert(queueList, {
                prefix = prefix,
                text = text,
                chatType = chatType,
                target = target,
                priority = priority,
                queue = queue,
                callback = callback,
                callbackArg = callbackArg,
                queuedAt = now
            })

            -- Set timer to replay this send after delay
            C_Timer.After(delayRemaining, function()
                -- Find and replay this send
                for i = #self.pendingPhaseInSends, 1, -1 do
                    local queuedSend = self.pendingPhaseInSends[i]
                    if queuedSend.target == target and queuedSend.queuedAt == now then
                        self:Debug(function()
                            return "[Chomp Hook] Replaying queued send to "..tostring(self:CleanPlayerName(target) or target).." after phase-in delay"
                        end, "hooks")
                        table.remove(self.pendingPhaseInSends, i)

                        -- Set replay flag to prevent re-queueing
                        chompState.replayingPhaseInSend = true

                        -- Replay the send - it will go through all normal logic (phase check, ghost mode, etc.)
                        AddOn_Chomp.SmartAddonMessage(queuedSend.prefix, queuedSend.text, queuedSend.chatType, queuedSend.target, queuedSend.priority, queuedSend.queue, queuedSend.callback, queuedSend.callbackArg)

                        -- Clear replay flag
                        chompState.replayingPhaseInSend = false
                        break
                    end
                end
            end)

            return {shouldContinue = false, queued = true}
        end
    end

    return {shouldContinue = true, queued = false}
end

function TRP3FW:ChompPipeline_MutualExchange_V2(playerName)
    --[[
        Stage 3: Detect mutual exchanges (both players sending profiles)

        Returns: {shouldContinue=bool, isMutual=bool}
    ]]

    -- Check if this is a user-initiated exchange
    local isUserInitiated = self:IsUserInitiatedExchange(playerName)

    -- Check if this is a pending automatic MSP reply (non-time-based detection)
    -- This part requires access to pendingMSPAutoReplies which is in hooks/trp3.lua
    -- Since we are inside TRP3FW, we can access self.pendingMSPAutoReplies

    -- Logic for TRP3 auto-replies is inferred: if NOT user-initiated, it's likely auto
    -- But we can't be 100% sure without inspecting message content deeper, which we do in main loop

    -- For the pipeline, we just return the status. The decision to "allow without location check"
    -- happens in the main hook logic or can be moved here.
    -- In the original code, IsUserInitiatedExchange checks are scattered.

    -- If it is a user initiated exchange, we might want to suppress notifications but still check blocks.
    -- However, the original code says: "Check if this is a user-initiated exchange... determine if this is a REQUEST or REPLY"

    return {shouldContinue = true, isMutual = isUserInitiated}
end

function TRP3FW:ChompPipeline_StartPhaseBlock_V2(playerName, prefix, text, chatType, target, priority, queue, callback, callbackArg)
    --[[
        Stage 4: Check if we should block due to start phase

        Returns: {shouldContinue=bool, blocked=bool, ghost=bool}
    ]]

    -- Determine if this send actually includes our profile data
    local isRequest = false
    if self.currentMessageIsRequest and self.currentMessageIsRequest[playerName] then
        local messageTime = self.currentMessageIsRequest[playerName]
        local now = self:GetCurrentTime()
        if (now - messageTime) < 1 then  -- 1 second window
            isRequest = true
            -- Clear the flag immediately to prevent reuse
            self.currentMessageIsRequest[playerName] = nil
        else
            -- Expired
            self.currentMessageIsRequest[playerName] = nil
        end
    end

    if isRequest then
        self:Debug("[Chomp Hook] Request message (no profile data) - allowing without location check", "hooks")
        return {shouldContinue = false, blocked = false, ghost = false} -- Allow original call
    end

    -- This is a profile send
    local isProfileSend = true

    -- Check if we should block for start phase (phase 169)
    local shouldBlock, blockAction = self:ShouldBlockForStartPhase(target, isProfileSend)

    if shouldBlock then
        local isMSPMessage = prefix and (prefix:find("MSP") or prefix == "MSP2")
        local addonType = isMSPMessage and "MSP" or "TRP3"
        local cleanTarget = self:CleanPlayerName(target)

        if blockAction == "ghost" then
            if isMSPMessage then
                -- MSP GHOST MODE: Let the send through normally (metatable handled it)
                self:Debug("[Chomp Hook] MSP ghost mode - letting send through", "hooks")
                if TRP3FW_Settings.notifyOnStartPhaseBlock and cleanTarget then
                    self:ShowStartPhaseBlockNotification(cleanTarget, "MSP (ghost)")
                end
                self.sessionStats.ghostSends = self.sessionStats.ghostSends + 1
                return {shouldContinue = false, blocked = false, ghost = true} -- Allow original call
            else
                -- TRP3 GHOST MODE: Enable ghost flag
                self:Debug("[Chomp Hook] TRP3 start phase ghost mode - enabling ghost flag for "..cleanTarget, "ghost")
                local alternateProfileID = TRP3FW_Settings.ghostProfileID
                local success = self:EnableGhostForNextSend(cleanTarget, alternateProfileID)

                if success then
                    if TRP3FW_Settings.notifyOnStartPhaseBlock and cleanTarget then
                        self:ShowStartPhaseBlockNotification(cleanTarget, "TRP3 (ghost)")
                    end
                    self.sessionStats.ghostSends = self.sessionStats.ghostSends + 1
                    return {shouldContinue = false, blocked = false, ghost = true} -- Allow original call
                else
                    self:Debug("[Chomp Hook] Failed to enable ghost flag, blocking send", "ghost")
                    return {shouldContinue = false, blocked = true, ghost = false} -- Block
                end
            end
        end

        -- Block the send
        self:Debug("[Chomp Hook] Blocking transmission in start phase", "hooks")
        if TRP3FW_Settings.notifyOnStartPhaseBlock and cleanTarget then
            self:ShowStartPhaseBlockNotification(cleanTarget, addonType)
        end
        return {shouldContinue = false, blocked = true, ghost = false} -- Block
    end

    return {shouldContinue = true, blocked = false, ghost = false}
end

function TRP3FW:ChompPipeline_BurstDetection_V2(playerName, prefix, text, chatType, target, priority, queue, callback, callbackArg)
    --[[
        Stage 5: Detect bursts and queue for batch processing

        Returns: {shouldContinue=bool, queued=bool}
    ]]

    local blockingPossible = self:ShouldBlockOnPhase() or self:ShouldBlockOnMap() or TRP3FW_Settings.blockStartPhase or TRP3FW_Settings.ghostOnStartPhase

    if blockingPossible then
        -- Burst detection
        if not self.pendingChompSends then
            self.pendingChompSends = {}
        end

        if self.pendingChompSends[playerName] then
            local timeSinceFirst = self:GetCurrentTime() - self.pendingChompSends[playerName].timestamp
            if timeSinceFirst < 2 then
                self:Debug("[Chomp Hook] Request already in progress for "..playerName.." ("..string.format("%.2f", timeSinceFirst).."s ago), queueing burst request", "hooks")
                -- Queue this request
                table.insert(self.pendingChompSends[playerName].queuedRequests, {
                    prefix = prefix,
                    text = text,
                    chatType = chatType,
                    target = target,
                    priority = priority,
                    queue = queue,
                    callback = callback,
                    callbackArg = callbackArg,
                    timestamp = self:GetCurrentTime(),
                    queuedAt = self:GetCurrentTime(),
                    zoneSnapshot = self.lastZoneChangeTime,
                    phaseSnapshot = self.lastPhaseChangeTime,
                    settingsFingerprint = getBurstFingerprintSafe()
                })
                return {shouldContinue = false, queued = true}
            else
                -- Old pending request, clear it
                self.pendingChompSends[playerName] = nil
            end
        end

        -- Mark as pending
        self.pendingChompSends[playerName] = {
            timestamp = self:GetCurrentTime(),
            zoneSnapshot = self.lastZoneChangeTime,
            phaseSnapshot = self.lastPhaseChangeTime,
            settingsFingerprint = getBurstFingerprintSafe(),
            queuedRequests = {}
        }

        -- Timeout
        C_Timer.After(30, function()
            if self.pendingChompSends and self.pendingChompSends[playerName] then
                self.pendingChompSends[playerName] = nil
            end
        end)
    end

    return {shouldContinue = true, queued = false}
end

function TRP3FW:ChompPipeline_LocationGating_V2(playerName, addon, sendId, originalFunc, originalArgs, context)
    --[[
        Stage 6: Final stage - call CheckLocationAndNotify

        Returns: {result=any}
    ]]

    -- Call decision engine
    -- isWhisper is true for Chomp sends generally (target is specific player)
    -- We assume Chomp sends are whispers or specific channel sends that behave like whispers for our purposes
    -- The original code passed 'true' for isWhisper in CheckLocationAndNotify calls from hooks
    local result = self:CheckLocationAndNotify(playerName, addon, true, sendId, originalFunc, originalArgs)

    return {result = result}
end

print("TRP3FW Chomp Pipeline (V2) loaded")
