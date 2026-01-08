-- hooks/msp.lua
-- LibMSP protocol hooks

local addonName, TRP3FW = ...

-- Constants
local START_PHASE_ID = 169  -- Epsilon start phase ID (blocks all transmissions)

-- Ensure LibMSP has a non-nil NA field for a given player entry
local function EnsureMSPNA(rawName)
    if not rawName or rawName == "" then return end
    local cleanName = TRP3FW and TRP3FW.CleanPlayerName and TRP3FW:CleanPlayerName(rawName) or rawName

    local candidates = {rawName, cleanName and cleanName:lower() or nil, cleanName}
    for _, key in ipairs(candidates) do
        if key and msp and msp.char then
            local entry = msp.char[key]
            if entry then
                entry.field = entry.field or {}
                if entry.field.NA == nil then
                    entry.field.NA = rawName
                    if TRP3FW and TRP3FW.Debug then
                        TRP3FW:Debug("[MSP NA Guard] Filled missing NA for "..tostring(key).." (source=existing)", "hooks")
                    end
                    return
                end
            end
        end
    end

    if msp and msp.char then
        local key = cleanName or rawName
        if key then
            msp.char[key] = msp.char[key] or { field = {} }
            if msp.char[key].field.NA == nil then
                msp.char[key].field.NA = rawName
                if TRP3FW and TRP3FW.Debug then
                    TRP3FW:Debug("[MSP NA Guard] Created entry and set NA for "..tostring(key).." (source=new)", "hooks")
                end
            end
        end
    end
end

-- Install MSP request tracking hook
function TRP3FW:InstallMSPRequestHook()
    if not msp or not msp.Request then
        self:Debug("Cannot install MSP Request hook - msp.Request not found", "hooks")
        return false
    end

    self.hookState = self.hookState or {}
    self.hookState.originals = self.hookState.originals or {}
    local originals = self.hookState.originals

    local conflict = self:CheckHookConflict("mspRequest", msp.Request, originals.mspRequest, nil)
    if conflict.action == "skip" then
        self:Debug("msp.Request hook already installed; skipping", "hooks")
        return true
    elseif conflict.action == "refuse" then
        self.hookStatus.mspRequest = "refused"
        return false
    end

    self.originalMSPRequest = originals.mspRequest or msp.Request
    originals.mspRequest = self.originalMSPRequest
    local originalMSPRequest = self.originalMSPRequest

    -- Wrap msp:Request to track user-initiated requests
    msp.Request = function(self, name, fields)
        -- Track this as a user-initiated query
        if name then
            local cleanName = TRP3FW:CleanPlayerName(name)
            if cleanName then
                -- STRICT INTERACTION CHECK: Only count as user-initiated if we are actually targeting/mousing over them
                -- This prevents automated background scans (e.g. from map scanners) from silencing notifications
                -- Also ignore targeting if it was caused by our own Phase Check mechanism
                local isTarget = UnitName("target") == cleanName and not TRP3FW.phaseCheckTargeting
                local isMouseover = UnitName("mouseover") == cleanName

                local fieldList = (type(fields) == "table" and table.concat(fields, ",")) or tostring(fields)

                if isTarget or isMouseover then
                    local now = TRP3FW:GetCurrentTime()
                    TRP3FW.userInitiatedQueries[cleanName] = now
                    TRP3FW:Debug("[MSP Request Hook] User-initiated query to "..cleanName.." (via "..(isTarget and "target" or "mouseover")..") (fields: "..fieldList..") - marked for mutual exchange detection", "hooks")
                else
                    TRP3FW:Debug("[MSP Request Hook] Automated/Background query to "..cleanName.." (fields: "..fieldList..") - ignoring for mutual exchange", "hooks")
                end

                -- Pre-seed NA so inbound replies for this target have a name before chat filters run
                EnsureMSPNA(cleanName)

                -- DO NOT pre-populate interaction cache here!
                -- The mutual exchange logic in CheckLocationAndNotify will handle it,
                -- and it will only suppress notifications, NOT bypass blocking checks
            end
        end
        -- Call original
        return originalMSPRequest(self, name, fields)
    end

    self:Debug("Installed msp.Request hook (tracks user-initiated MSP requests)", "hooks")
    return true
end

-- Determine if the next MSP send is an automatic reply (used for notification suppression)
function TRP3FW:IsPendingMSPAutoReply(playerName)
    local cleanName = playerName and self:CleanPlayerName(playerName)
    if not cleanName or not self.pendingMSPAutoReplies then
        return false
    end

    local entry = self.pendingMSPAutoReplies[cleanName]
    if not entry then
        return false
    end

    local now = self:GetCurrentTime()
    if entry.expires and now > entry.expires then
        self.pendingMSPAutoReplies[cleanName] = nil
        return false
    end

    return true
end

-- Install LibMSP hooks
function TRP3FW:InstallMSPHooks()
    -- Ensure LibMSP has minimal required fields to avoid Update aborts
    if msp and msp.my then
        msp.my.VA = msp.my.VA or ""
    end

    -- Always guard incoming MSP data so NA is never nil (prevents downstream addon crashes)
    local function ensureNA(rawName)
        EnsureMSPNA(rawName)
    end

    local function sweepExistingEntries()
        if not msp or not msp.char then return end
        for key, entry in pairs(msp.char) do
            if entry and type(entry) == "table" then
                entry.field = entry.field or {}
                if entry.field.NA == nil then
                    entry.field.NA = key
                end
            end
        end
    end

    if not self.mspNameGuardInstalled then
        local function tryInstallNameGuard(attempt)
            if self.mspNameGuardInstalled then return end
            if not msp or not msp.callback then
                if attempt < 10 then
                    C_Timer.After(0.5, function() tryInstallNameGuard((attempt or 1) + 1) end)
                end
                return
            end

            msp.callback.received = msp.callback.received or {}
            table.insert(msp.callback.received, 1, function(senderName)
                ensureNA(senderName)
            end)
            sweepExistingEntries()
            self.mspNameGuardInstalled = true
        end

        tryInstallNameGuard(1)
    else
        sweepExistingEntries()
    end

    -- Chat guard: ensure NA is present for chat speakers before other filters run
    -- Also verifies msp.my metatable integrity to prevent chat message drops
    if not self.mspChatGuardInstalled then
        local lastIntegrityCheck = 0
        local recentNAChecks = {}  -- Track recent NA checks per player
        local maxRecentChecks = 100  -- Limit cache size

        local function ChatEnsureNA(_, event, message, author, ...)
            -- SECURITY: Throttled integrity check (max 2/sec) to prevent MRP chat crashes
            -- This prevents "attempt to index field 'NA' (a nil value)" in MyRolePlay/Chat.lua:108
            -- when metatable is dropped and MRP tries to access msp.my["NA"]:find()
            local now = GetTime()
            if (now - lastIntegrityCheck) >= 0.5 then
                if TRP3FW and TRP3FW.VerifyMSPIntegrity then
                    TRP3FW:VerifyMSPIntegrity()
                end
                lastIntegrityCheck = now

                -- Periodic cleanup of NA check cache (prevent unbounded growth)
                local count = 0
                for _ in pairs(recentNAChecks) do count = count + 1 end
                if count > maxRecentChecks then
                    for name, timestamp in pairs(recentNAChecks) do
                        if (now - timestamp) > 60 then  -- Clear entries older than 60s
                            recentNAChecks[name] = nil
                        end
                    end
                end
            end

            -- OPTIMIZATION: Per-player throttling for EnsureMSPNA (prevents redundant checks)
            -- Safe to throttle because EnsureMSPNA has early returns and only fills if missing
            if author and author ~= "" then
                local lastCheck = recentNAChecks[author]
                if not lastCheck or (now - lastCheck) > 5 then
                    EnsureMSPNA(author)
                    recentNAChecks[author] = now
                end
            end
            return false
        end

        local chatEvents = {
            "CHAT_MSG_SAY",
            "CHAT_MSG_YELL",
            "CHAT_MSG_EMOTE",
            "CHAT_MSG_TEXT_EMOTE",
            "CHAT_MSG_WHISPER",
            "CHAT_MSG_WHISPER_INFORM",
            "CHAT_MSG_PARTY",
            "CHAT_MSG_PARTY_LEADER",
            "CHAT_MSG_RAID",
            "CHAT_MSG_RAID_LEADER",
            "CHAT_MSG_GUILD",
            "CHAT_MSG_OFFICER",
            "CHAT_MSG_INSTANCE_CHAT",
            "CHAT_MSG_INSTANCE_CHAT_LEADER",
        }

        for _, ev in ipairs(chatEvents) do
            ChatFrame_AddMessageEventFilter(ev, ChatEnsureNA)
        end

        self.mspChatGuardInstalled = true
    end

    -- Hook LibMSP callback system (this catches ALL MSP sends, including TRP3 → MRP)
    if msp and msp.callback and msp.callback.received and TRP3FW_Settings.monitorMSP then
        -- The "received" callback fires when LibMSP receives a REQUEST
        -- After processing it, LibMSP automatically sends a REPLY
        -- We can't block the reply, but we can detect it and notify

        -- Store original callback table
        local originalCallbacks = {}
        for i, callback in ipairs(msp.callback.received) do
            originalCallbacks[i] = callback
        end

        -- Track recent requests to avoid duplicates (with cleanup)
        local recentRequests = {}
        local maxRecentRequests = 100

        -- Cleanup old entries periodically
        local function CleanupRecentRequests()
            local now = TRP3FW:GetCurrentTime()
            local count = 0
            for name in pairs(recentRequests) do
                count = count + 1
            end

            if count > maxRecentRequests then
                -- Remove entries older than 5 seconds
                for name, timestamp in pairs(recentRequests) do
                    if (now - timestamp) > 5 then
                        recentRequests[name] = nil
                    end
                end
            end
        end

        -- Insert our hook at the beginning
        table.insert(msp.callback.received, 1, function(senderName)
            if not senderName or senderName == "" then return end

            -- Periodic cleanup of old entries
            CleanupRecentRequests()

            -- Check if we're in start phase (this is always an automatic reply)
            local shouldBlock, blockAction = TRP3FW:ShouldBlockForStartPhase(senderName, true)
            if shouldBlock then
                local cleanName = TRP3FW:CleanPlayerName(senderName)

                -- Phase 169 detected - handle blocking or ghost mode
                if TRP3FW_Settings.ghostOnStartPhase then
                    -- Ghost mode enabled - set ghost flag BEFORE LibMSP prepares reply
                    if cleanName and (TRP3FW.hasTRP3ExchangeHooks or TRP3FW.hasMSPExchangeHooks) then
                        local alternateProfileID = TRP3FW_Settings.ghostProfileID
                        local success = TRP3FW:EnableGhostForNextSend(cleanName, alternateProfileID)
                        if success then
                            if alternateProfileID then
                                TRP3FW:Debug("[LibMSP Callback] Phase 169 ghost mode enabled, sending alternate profile: "..tostring(alternateProfileID), "hooks")
                            else
                                TRP3FW:Debug("[LibMSP Callback] Phase 169 ghost mode enabled, sending blank profile", "hooks")
                            end
                            -- Show notification if enabled
                            if TRP3FW_Settings.notifyOnStartPhaseBlock then
                                -- Continue to show notification below
                            else
                                return -- Ghost send without notification
                            end
                        else
                            TRP3FW:Debug("[LibMSP Callback] Failed to enable ghost flag, falling back to block", "hooks")
                            -- Fall through to block below
                        end
                    else
                        TRP3FW:Debug("[LibMSP Callback] Ghost mode enabled but exchange hooks not available, falling back to block", "hooks")
                        -- Fall through to block below
                    end
                elseif TRP3FW_Settings.blockStartPhase then
                    -- Block mode - prevent the send entirely
                    TRP3FW:Debug("[LibMSP Callback] Phase 169 block enabled, will block send", "hooks")

                    -- Safety check: cleanName must be valid
                    if not cleanName then
                        TRP3FW:Debug("[LibMSP Callback] Failed to clean sender name: "..tostring(senderName)..", cannot block", "hooks")
                        return
                    end

                    -- Mark this player for blocking in Chomp hook
                    if not TRP3FW.startPhaseBlockList then
                        TRP3FW.startPhaseBlockList = {}
                    end
                    local now = TRP3FW:GetCurrentTime()
                    TRP3FW.startPhaseBlockList[cleanName] = {
                        timestamp = now,
                        expires = now + 5  -- Short TTL
                    }

                    -- Show notification if enabled
                    if TRP3FW_Settings.notifyOnStartPhaseBlock then
                        -- Continue to show notification below
                    else
                        return -- Block without notification
                    end
                else
                    -- Neither ghost nor block enabled, just show notification
                    TRP3FW:Debug("[LibMSP Callback] Phase 169 detected but no block/ghost enabled, allowing send", "hooks")
                end
            end

            TRP3FW:Debug("[LibMSP Callback] Raw senderName from LibMSP: "..tostring(senderName), "hooks")

            local name = TRP3FW:CleanPlayerName(senderName)
            TRP3FW:Debug("[LibMSP Callback] After CleanPlayerName: "..tostring(name), "hooks")

            -- Safety check: If CleanPlayerName returns nil, skip this request
            if not name then
                TRP3FW:Debug("[LibMSP Callback] Failed to clean sender name: "..tostring(senderName)..", ignoring request", "hooks")
                return
            end

            -- Check if we just processed this player (within 1 second)
            local now = TRP3FW:GetCurrentTime()
            if recentRequests[name] and (now - recentRequests[name]) < 1 then
                TRP3FW:Debug("[LibMSP Callback] Ignoring duplicate request from "..name.." (already processed "..string.format("%.1f", now - recentRequests[name]).."s ago)", "hooks")
                return
            end
            recentRequests[name] = now

            TRP3FW.pendingSendId = TRP3FW.pendingSendId + 1
            local sendId = TRP3FW.pendingSendId

            -- Store sendId for this player so Chomp hook can reuse it (prevent double counting)
            -- IMPORTANT: MSP sends MULTIPLE messages per exchange (safe reply + unsafe reply)
            -- Both messages should reuse the same sendId since they're part of one exchange
            -- The Chomp hook will increment reuseCount for each message in the burst
            if not TRP3FW.mspCallbackSendIds then
                TRP3FW.mspCallbackSendIds = {}
            end
            TRP3FW.mspCallbackSendIds[name] = {
                sendId = sendId,
                timestamp = now,
                reuseCount = 0  -- Will be incremented by Chomp hook for each reply message
            }

            -- Try to detect which addon protocol is being used
            -- Check if sender's MSP data indicates a specific addon
            local detectedAddon = "MSP" -- Default to generic MSP

            if msp and msp.char and msp.char[senderName] then
                local senderData = msp.char[senderName]
                -- Check for addon-specific fields/signatures
                -- We check both legacy/internal 'client' field and standard MSP 'VA' field (Version Addon)
                local client = senderData.client
                local va = senderData.field and senderData.field.VA

                local checkString = (client or "") .. " " .. (va or "")
                checkString = checkString:lower()

                if checkString:find("myroleplay") or checkString:find("mrp") then
                    detectedAddon = "MRP"
                elseif checkString:find("xrp") then
                    detectedAddon = "XRP"
                elseif checkString:find("totalrp") or checkString:find("trp") then
                    detectedAddon = "TRP3"
                end
            end

            -- Store detected addon for use in Chomp hook (send)
            if not TRP3FW.detectedAddons then TRP3FW.detectedAddons = {} end
            TRP3FW.detectedAddons[name] = detectedAddon

            TRP3FW:Debug(detectedAddon.." profile request detected from: "..name.." (sendId: "..sendId..") via LibMSP callback", "hooks")

            -- Note: MSP Callback hook fires when THEY request OUR profile
            -- The Chomp hook (in hooks/trp3.lua) fires when WE send our profile to them
            -- Mark this as a pending automatic reply so Chomp hook knows it's not user-initiated
            if not TRP3FW.pendingMSPAutoReplies then
                TRP3FW.pendingMSPAutoReplies = {}
            end
            -- Track that we're about to send an automatic reply to this person
            -- This expires quickly (5 seconds) since the reply is sent almost immediately
            TRP3FW.pendingMSPAutoReplies[name] = {
                timestamp = now,
                expires = now + 5  -- Short TTL since reply happens within milliseconds
            }
            TRP3FW:Debug("[LibMSP Callback] Request received from "..name..", marked as pending auto-reply for Chomp hook", "hooks")
        end)

        self:Debug("Installed LibMSP callback hook (notification only - cannot block)", "hooks")
    end

    -- Note: MSP profile sends are intercepted via the Chomp hook in hooks/trp3.lua
    -- LibMSP uses AddOn_Chomp.SmartAddonMessage() to send profiles, not msp.Reply()
    -- The Chomp hook handles both TRP3 and MSP2 messages
end
