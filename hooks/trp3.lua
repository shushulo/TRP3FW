-- hooks/trp3.lua
-- TRP3 and Chomp library hooks

local addonName, TRP3FW = ...

-- Constants
local START_PHASE_ID = 169  -- Epsilon start phase ID (blocks all transmissions)

-- Track user-initiated profile requests (from sendQuery function)
TRP3FW.userInitiatedQueries = {}  -- [playerName] = timestamp

-- Get ghost data for a specific TRP3 informationType
function TRP3FW:GetGhostDataForInformationType(informationType, profileID)
    if not TRP3_API or not TRP3_API.register or not TRP3_API.register.registerInfoTypes then
        self:Warn("Cannot get ghost data - registerInfoTypes not found")
        return nil
    end

    local registerInfoTypes = TRP3_API.register.registerInfoTypes
    local ghostData = nil

    self:Debug("[GetGhostData] informationType: "..tostring(informationType)..", profileID: "..tostring(profileID), "ghost")

    -- Determine which section to fetch
    if informationType == registerInfoTypes.CHARACTERISTICS then
        -- Prefer generated blank data for the default blank profile to avoid malformed template defaults
        if profileID and self:IsDefaultBlankProfileID(profileID) then
            self:Debug("[GetGhostData] Using blank characteristics (default blank profile)", "ghost")
            ghostData = self:GetBlankCharacteristicsData()
        elseif profileID then
            self:Debug("[GetGhostData] Fetching characteristics for profile: "..tostring(profileID), "ghost")
            ghostData = self:GetProfileCharacteristics(profileID)
            if not ghostData then
                self:Debug("[GetGhostData] Profile not found, using blank characteristics", "ghost")
                ghostData = self:GetBlankCharacteristicsData()
            else
                self:Debug("[GetGhostData] Successfully retrieved profile characteristics", "ghost")
            end
        else
            self:Debug("[GetGhostData] No profileID, using blank characteristics", "ghost")
            ghostData = self:GetBlankCharacteristicsData()
        end
        -- Safety: ensure required fields exist
        if ghostData then
            if not ghostData.FN or ghostData.FN == "" then
                ghostData.FN = UnitName("player")
            end
            if not ghostData.CH or ghostData.CH == "" then
                ghostData.CH = "ffffff"  -- White color (6-char RGB hex only)
            end
        end
    elseif informationType == registerInfoTypes.ABOUT then
        if profileID and self:IsDefaultBlankProfileID(profileID) then
            self:Debug("[GetGhostData] Using blank about (default blank profile)", "ghost")
            ghostData = self:GetBlankAboutData()
        elseif profileID then
            self:Debug("[GetGhostData] Fetching about for profile: "..tostring(profileID), "ghost")
            ghostData = self:GetProfileAbout(profileID)
            if not ghostData then
                self:Debug("[GetGhostData] Profile not found, using blank about", "ghost")
                ghostData = self:GetBlankAboutData()
            else
                self:Debug("[GetGhostData] Successfully retrieved profile about", "ghost")
            end
        else
            self:Debug("[GetGhostData] No profileID, using blank about", "ghost")
            ghostData = self:GetBlankAboutData()
        end
    elseif informationType == registerInfoTypes.MISC then
        if profileID and self:IsDefaultBlankProfileID(profileID) then
            self:Debug("[GetGhostData] Using blank misc (default blank profile)", "ghost")
            ghostData = self:GetBlankMiscData()
        elseif profileID then
            self:Debug("[GetGhostData] Fetching misc for profile: "..tostring(profileID), "ghost")
            ghostData = self:GetProfileMisc(profileID)
            if not ghostData then
                self:Debug("[GetGhostData] Profile not found, using blank misc", "ghost")
                ghostData = self:GetBlankMiscData()
            else
                self:Debug("[GetGhostData] Successfully retrieved profile misc", "ghost")
            end
        else
            self:Debug("[GetGhostData] No profileID, using blank misc", "ghost")
            ghostData = self:GetBlankMiscData()
        end
    elseif informationType == registerInfoTypes.CHARACTER then
        if profileID and self:IsDefaultBlankProfileID(profileID) then
            self:Debug("[GetGhostData] Using blank character (default blank profile)", "ghost")
            ghostData = self:GetBlankCharacterData()
        elseif profileID then
            self:Debug("[GetGhostData] Fetching character for profile: "..tostring(profileID), "ghost")
            ghostData = self:GetProfileCharacter(profileID)
            if not ghostData then
                self:Debug("[GetGhostData] Profile not found, using blank character", "ghost")
                ghostData = self:GetBlankCharacterData()
            else
                self:Debug("[GetGhostData] Successfully retrieved profile character", "ghost")
            end
        else
            self:Debug("[GetGhostData] No profileID, using blank character", "ghost")
            ghostData = self:GetBlankCharacterData()
        end
    else
        self:Warn("Unknown informationType for ghost mode: "..tostring(informationType))
        return nil
    end

    -- Final safety: validate/sanitize payload before returning to callers
    if ghostData then
        local okPayload, sanitized = self:ValidateGhostTRP3Payload(informationType, ghostData)
        if not okPayload then
            self:Warn("[GetGhostData] Payload invalid for informationType "..tostring(informationType).."; using blank fallback")
            ghostData = sanitized
        else
            ghostData = sanitized
        end
    end

    return ghostData
end

-- Validate ghost payloads before sending; fall back to blank sections on malformed data
function TRP3FW:ValidateGhostTRP3Payload(informationType, payload)
    if not TRP3_API or not TRP3_API.register or not TRP3_API.register.registerInfoTypes then
        return false, nil
    end

    local registerInfoTypes = TRP3_API.register.registerInfoTypes

    local function SanitizeString(value, default)
        if type(value) == "string" then
            return value
        end
        if type(value) == "number" or type(value) == "boolean" then
            return tostring(value)
        end
        return default or ""
    end

    local function ShallowCopy(tbl)
        local out = {}
        for k, v in pairs(tbl) do
            if type(v) == "table" then
                local inner = {}
                for ck, cv in pairs(v) do
                    inner[ck] = cv
                end
                out[k] = inner
            else
                out[k] = v
            end
        end
        return out
    end

    local function GetBlankForType(infoType)
        if infoType == registerInfoTypes.CHARACTERISTICS then
            return self:GetBlankCharacteristicsData()
        elseif infoType == registerInfoTypes.ABOUT then
            return self:GetBlankAboutData()
        elseif infoType == registerInfoTypes.MISC then
            return self:GetBlankMiscData()
        elseif infoType == registerInfoTypes.CHARACTER then
            return self:GetBlankCharacterData()
        end
        return nil
    end

    local blank = GetBlankForType(informationType)
    if type(payload) ~= "table" then
        return false, blank
    end

    local sanitized = ShallowCopy(payload)

    if informationType == registerInfoTypes.CHARACTERISTICS then
        sanitized.FN = SanitizeString(sanitized.FN or (blank and blank.FN), UnitName("player"))
        sanitized.CH = SanitizeString(sanitized.CH or (blank and blank.CH), "ffffff")
        sanitized.IC = SanitizeString(sanitized.IC or (blank and blank.IC), "TEMP")
        if type(sanitized.MI) ~= "table" then sanitized.MI = {} end
        if type(sanitized.PS) ~= "table" then sanitized.PS = {} end
    elseif informationType == registerInfoTypes.ABOUT then
        sanitized.v = tonumber(sanitized.v) or (blank and blank.v) or 1
        sanitized.TE = tonumber(sanitized.TE) or (blank and blank.TE) or 1
        sanitized.BK = tonumber(sanitized.BK) or (blank and blank.BK) or 1
        sanitized.MU = SanitizeString(sanitized.MU, nil)
        if type(sanitized.T1) ~= "table" then sanitized.T1 = {} end
        sanitized.T1.TX = SanitizeString(sanitized.T1.TX or (blank and blank.T1 and blank.T1.TX), "")
    elseif informationType == registerInfoTypes.MISC then
        sanitized.v = tonumber(sanitized.v) or (blank and blank.v) or 1
        if type(sanitized.PE) ~= "table" then sanitized.PE = {} end
        if type(sanitized.ST) ~= "table" then sanitized.ST = {} end
    elseif informationType == registerInfoTypes.CHARACTER then
        sanitized.v = tonumber(sanitized.v) or (blank and blank.v) or 1
        sanitized.RP = tonumber(sanitized.RP) or (blank and blank.RP) or 2
        sanitized.XP = tonumber(sanitized.XP) or (blank and blank.XP) or 1
        sanitized.CU = SanitizeString(sanitized.CU or (blank and blank.CU), "")
        sanitized.CO = SanitizeString(sanitized.CO or (blank and blank.CO), "")
    else
        return false, blank
    end

    return true, sanitized
end

-- Install TRP3 sendQuery hook to track user-initiated requests
function TRP3FW:InstallSendQueryHook()
    if not TRP3_API or not TRP3_API.r or not TRP3_API.r.sendQuery then
        self:Debug("Cannot install sendQuery hook - TRP3_API.r.sendQuery not found", "hooks")
        return false
    end

    local conflict = self:CheckHookConflict("sendQuery", TRP3_API.r.sendQuery, self.originalSendQuery, nil)
    if conflict.action == "skip" then
        self:Debug("sendQuery hook already installed; skipping", "hooks")
        return true
    elseif conflict.action == "refuse" then
        self.hookStatus.sendQuery = "refused"
        return false
    end

    self.originalSendQuery = self.originalSendQuery or TRP3_API.r.sendQuery
    local originalSendQuery = self.originalSendQuery

    TRP3_API.r.sendQuery = function(unitID)
        -- Track this as a user-initiated query
        if unitID then
            local cleanName = TRP3FW:CleanPlayerName(unitID)
            if cleanName then
                -- STRICT INTERACTION CHECK: Only count as user-initiated if we are actually targeting/mousing over them
                -- This prevents automated background scans (e.g. from map scanners) from silencing notifications
                -- Also ignore targeting if it was caused by our own Phase Check mechanism
                local isTarget = UnitName("target") == cleanName and not TRP3FW.phaseCheckTargeting
                local isMouseover = UnitName("mouseover") == cleanName

                if isTarget or isMouseover then
                    local now = TRP3FW:GetCurrentTime()
                    TRP3FW.userInitiatedQueries[cleanName] = now
                    TRP3FW:Debug("[sendQuery Hook] User-initiated query to "..cleanName.." (via "..(isTarget and "target" or "mouseover")..") - marked for mutual exchange detection", "hooks")
                else
                    TRP3FW:Debug("[sendQuery Hook] Automated/Background query to "..cleanName.." - ignoring for mutual exchange", "hooks")
                end

                -- DO NOT pre-populate interaction cache!
                -- That bypasses blocking checks, which defeats the entire purpose of block mode
                -- The mutual exchange logic will handle notification suppression without bypassing blocking
            end
        end
        -- Call original
        return originalSendQuery(unitID)
    end

    self:Debug("Installed TRP3_API.r.sendQuery hook (tracks user-initiated requests)", "hooks")
    return true
end

-- Check if a profile send is part of a user-initiated exchange
function TRP3FW:IsUserInitiatedExchange(playerName)
    local queryTime = self.userInitiatedQueries[playerName]
    if not queryTime then
        return false
    end

    local age = self:GetCurrentTime() - queryTime
    local TTL = 5  -- 5 second window for mutual exchange to complete (MSP/TRP3 exchanges complete in 1-2s)

    if age < TTL then
        self:Debug("[IsUserInitiatedExchange] "..playerName.." was queried "..string.format("%.1f", age).."s ago - part of user-initiated exchange", "hooks")
        return true
    else
        -- Expired, clean up
        self.userInitiatedQueries[playerName] = nil
        return false
    end
end

-- Main Chomp hook pipeline (TRP3/MSP sends)
local unpack = table.unpack or unpack
function TRP3FW:ChompHookPipeline(prefix, text, chatType, target, priority, queue, callback, callbackArg, originalFunc)
    -- Stage 1: Guards
    local guardResult = self:ChompPipeline_GuardChecks_V2(prefix, text, chatType, target, priority, queue, callback, callbackArg)
    local skipPhaseIn = false

    if not guardResult.shouldContinue then
        -- Replay guard should still run the location logic but must skip re-queueing
        if guardResult.reason == "replay_guard" then
            skipPhaseIn = true
        else
            return originalFunc(prefix, text, chatType, target, priority, queue, callback, callbackArg)
        end
    end

    local playerName = target and self:CleanPlayerName(target)
    if not playerName then
        return originalFunc(prefix, text, chatType, target, priority, queue, callback, callbackArg)
    end

    local sendIdObj = self:CreateVerifiedSendId()
    local sendId = sendIdObj and sendIdObj.id or 0

    -- Stage 2: Phase-in delay (skipped for replays)
    if not skipPhaseIn then
        local phaseResult = self:ChompPipeline_PhaseInDelay_V2(playerName, prefix, text, chatType, target, priority, queue, callback, callbackArg)
        if not phaseResult.shouldContinue then
            return -- Queued for later replay
        end
    end

    -- Stage 3: Mutual exchange detection (currently just informational)
    local mutualResult = self:ChompPipeline_MutualExchange_V2(playerName)

    -- Stage 4: Start phase blocking/ghosting
    local startPhaseResult = self:ChompPipeline_StartPhaseBlock_V2(playerName, prefix, text, chatType, target, priority, queue, callback, callbackArg)
    if not startPhaseResult.shouldContinue then
        if startPhaseResult.blocked then
            return -- Blocked in start phase
        end
        -- Allowed (including ghost mode) - bypass location gating
        return originalFunc(prefix, text, chatType, target, priority, queue, callback, callbackArg)
    end

    -- Stage 5: Burst detection
    local burstResult = self:ChompPipeline_BurstDetection_V2(playerName, prefix, text, chatType, target, priority, queue, callback, callbackArg)
    if not burstResult.shouldContinue then
        return -- Queued for burst handling
    end

    -- Stage 6: Location gating
    local addon = "TRP3"
    if prefix and tostring(prefix):find("MSP") then
        addon = "MSP"
        -- Try to resolve specific addon from MSP handshake
        if TRP3FW.detectedAddons and playerName and TRP3FW.detectedAddons[playerName] then
             addon = TRP3FW.detectedAddons[playerName]
        end
    end

    local args = {prefix, text, chatType, target, priority, queue, callback, callbackArg}
    local locationResult = self:ChompPipeline_LocationGating_V2(
        playerName,
        addon,
        sendId,
        function()
            return originalFunc(unpack(args))
        end,
        args,
        { isMutual = mutualResult and mutualResult.isMutual or false }
    )

    if locationResult and locationResult.shouldGhost then
        -- If ghost mode is active, we might need to substitute the payload
        -- For TRP3, this was handled by sendObject hook (pre-serialization)
        -- For MSP (or raw MSP2 sends), we must replace it here
        if addon == "MSP" and type(text) == "string" and text:find("[:!]") then
            -- Only replace payload if it looks like data fields (contains : or !)
            -- Requests (?) are harmless and shouldn't be ghosted
            -- Tooltip requests (?TT) or partials (?) are also harmless queries
            
            -- Generate ghost payload for this target
            local ghostPayload = self:GenerateMSPGhostPayload(playerName)
            if ghostPayload and ghostPayload ~= "" then
                self:Debug("[Chomp Hook] Ghost mode: Replacing MSP payload for "..tostring(playerName), "ghost")
                -- Update args with new payload
                args[2] = ghostPayload
                -- We don't need to update locationResult.result because that's just the return value
                -- But we need to ensure the callback (originalFunc) uses the new args
                -- The callback closure above captured 'args', so updating the table works!
            else
                self:Warn("[Chomp Hook] Ghost mode enabled but failed to generate payload for "..tostring(playerName))
            end
        end
    end

    return locationResult and locationResult.result
end

-- Install Chomp hook to enforce location gating for TRP3/MSP sends
function TRP3FW:InstallChompHook()
    if not AddOn_Chomp or not AddOn_Chomp.SmartAddonMessage then
        self:Debug("Cannot install Chomp hook - AddOn_Chomp.SmartAddonMessage not found", "hooks")
        return false
    end

    self.hookState = self.hookState or {}
    self.hookState.originals = self.hookState.originals or {}
    local originals = self.hookState.originals

    local conflict = self:CheckHookConflict("chomp", AddOn_Chomp.SmartAddonMessage, originals.chompSend, self.ChompHookPipeline)
    if conflict.action == "skip" then
        self:Debug("Chomp hook already installed; skipping", "hooks")
        return true
    elseif conflict.action == "refuse" then
        self.hookStatus.chomp = "refused"
        return false
    end

    originals.chompSend = originals.chompSend or AddOn_Chomp.SmartAddonMessage
    self.originalChompSend = originals.chompSend
    local originalSend = self.originalChompSend

    AddOn_Chomp.SmartAddonMessage = function(prefix, text, chatType, target, priority, queue, callback, callbackArg)
        local start = debugprofilestop()
        local ret = TRP3FW:ChompHookPipeline(prefix, text, chatType, target, priority, queue, callback, callbackArg, originalSend)
        local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
        if hs then 
            local addon = "TRP3"
            if prefix and tostring(prefix):find("MSP") then
                addon = "MSP"
            end
            hs:RecordPerformance(debugprofilestop() - start, addon) 
        end
        return ret
    end

    self:Debug("Installed AddOn_Chomp.SmartAddonMessage hook (location gating)", "hooks")
    return true
end

-- Install hook for AddOn_TotalRP3.Communications.sendObject (BEFORE serialization)
-- This lets us intercept ghost mode sends with access to informationType
function TRP3FW:InstallSendObjectHook()
    if not AddOn_TotalRP3 or not AddOn_TotalRP3.Communications then
        self:Debug("Cannot install sendObject hook - AddOn_TotalRP3.Communications missing", "hooks")
        return false
    end

    local comms = AddOn_TotalRP3.Communications
    if type(comms.sendObject) ~= "function" then
        self:Warn("Cannot install sendObject hook - sendObject is not callable", "hooks")
        return false
    end

    self.hookState = self.hookState or {}
    self.hookState.originals = self.hookState.originals or {}
    local originals = self.hookState.originals

    local conflict = self:CheckHookConflict("sendObject", comms.sendObject, originals.sendObject, nil)
    if conflict.action == "skip" then
        self:Debug("sendObject hook already installed; skipping", "hooks")
        return true
    elseif conflict.action == "refuse" then
        self.hookStatus.sendObject = "refused"
        return false
    end

    originals.sendObject = originals.sendObject or comms.sendObject
    local originalSendObject = originals.sendObject

    AddOn_TotalRP3.Communications.sendObject = function(prefix, object, ...)
        if type(originalSendObject) ~= "function" then
            TRP3FW:Warn("[sendObject Hook] original sendObject missing or replaced; skipping call")
            return
        end

        -- Extract target from varargs - sendObject signature is (prefix, object, channel, target, priority, ...)
        -- But channel can be omitted, so we need to check if first arg is a valid channel or a target
        local arg1, arg2, arg3 = select(1, ...), select(2, ...), select(3, ...)
        local targetArg
        local VALID_CHANNELS = {"WHISPER", "PARTY", "RAID", "GUILD", "BATTLEGROUND", "CHANNEL"}

        -- If arg1 is a valid channel, target is arg2, otherwise arg1 is the target
        local isArg1Channel = false
        for _, chan in ipairs(VALID_CHANNELS) do
            if arg1 == chan then
                isArg1Channel = true
                break
            end
        end

        if isArg1Channel then
            targetArg = arg2
        else
            targetArg = arg1
        end

        local cleanTarget = targetArg and TRP3FW:CleanPlayerName(targetArg) or "unknown"
        TRP3FW:Debug("[sendObject Hook] ENTRY - prefix: "..tostring(prefix)..", target: "..cleanTarget..", monitorTRP3: "..tostring(TRP3FW.Prefs.monitorTRP3)..", ghostOnStartPhase: "..tostring(TRP3FW.Prefs.ghostOnStartPhase)..", ghostNextSend: "..tostring(TRP3FW.ghostNextSend ~= nil), "ghost")

        if not TRP3FW.Prefs.monitorTRP3 and not TRP3FW.Prefs.ghostOnStartPhase and not TRP3FW.ghostNextSend then
            TRP3FW:Debug("[sendObject Hook] Bypassing (all conditions false)", "ghost")
            return originalSendObject(prefix, object, ...)
        end

        -- Log all message types to understand the exchange flow
        if prefix == "VR" then
            TRP3FW:Debug("[sendObject Hook] VR (version response) message - TRP3 is responding with version info, actual profile data may follow via SI if needed", "ghost")
            -- Log version response details to understand if profile data will be sent
            if object and type(object) == "table" then
                local profileID = object[3] -- VERNUM_QUERY_INDEX_CHARACTER_PROFILE
                TRP3FW:Debug("[sendObject Hook] VR profileID in response: "..tostring(profileID), "ghost")
            end
        elseif prefix == "VQ" then
            TRP3FW:Debug("[sendObject Hook] VQ (version query) message - TRP3 is asking for version info", "ghost")
            -- IMPORTANT: VQ is a user-initiated REQUEST (not a profile send)
            -- Mark THIS MESSAGE (not the player) as a request, so Chomp hook can detect it
            if cleanTarget then
                -- Track that this specific message is a request (expires in 1 second - enough for Chomp hook to see it)
                if not TRP3FW.currentMessageIsRequest then
                    TRP3FW.currentMessageIsRequest = {}
                end
                TRP3FW.currentMessageIsRequest[cleanTarget] = TRP3FW:GetCurrentTime()
                TRP3FW:Debug("[sendObject Hook] Marked VQ to "..cleanTarget.." as REQUEST (not profile send)", "ghost")
            end
        elseif prefix == "SI" then
            TRP3FW:Debug("[sendObject Hook] SI (send info) message - TRP3 is sending profile data!", "ghost")
        elseif prefix == "GI" then
            TRP3FW:Debug("[sendObject Hook] GI (get info) message - TRP3 is requesting profile data", "ghost")
            -- IMPORTANT: GI is a user-initiated REQUEST (not a profile send)
            -- Mark THIS MESSAGE (not the player) as a request, so Chomp hook can detect it
            if cleanTarget then
                -- Track that this specific message is a request (expires in 1 second - enough for Chomp hook to see it)
                if not TRP3FW.currentMessageIsRequest then
                    TRP3FW.currentMessageIsRequest = {}
                end
                TRP3FW.currentMessageIsRequest[cleanTarget] = TRP3FW:GetCurrentTime()
                TRP3FW:Debug("[sendObject Hook] Marked GI to "..cleanTarget.." as REQUEST (not profile send)", "ghost")
            end
        else
            TRP3FW:Debug("[sendObject Hook] Unknown prefix: "..tostring(prefix), "ghost")
        end

        -- Check if this is a profile send in ghost mode
        local shouldGhost = false
        local ghostProfileID = nil
        -- Use the cleanTarget we already extracted above

        -- Only intercept profile sends (prefix "SI")
        if prefix == "SI" and object and type(object) == "table" and object[1] then
            local informationType = object[1]
            TRP3FW:Debug("[sendObject Hook] Processing SI message - informationType: "..tostring(informationType)..", target: "..tostring(cleanTarget), "ghost")

            -- Priority 1: decision engine ghost flag for this target
            if cleanTarget and TRP3FW:ShouldGhostSendTo(cleanTarget) then
                shouldGhost = true
                ghostProfileID = TRP3FW:GetGhostProfileID(cleanTarget)
                TRP3FW:Debug("[sendObject Hook] Ghost flag active for "..cleanTarget.." (profile: "..tostring(ghostProfileID or "blank")..")", "ghost")
            else
                TRP3FW:Debug("[sendObject Hook] No ghost flag for "..tostring(cleanTarget), "ghost")
            end

            -- Priority 2: Start phase 169 ghost mode
            if not shouldGhost and TRP3FW.hasEpsilonAPI and TRP3FW.Prefs.ghostOnStartPhase then
                local currentPhase = tonumber(C_Epsilon.GetPhaseId())
                TRP3FW:Debug("[sendObject Hook] Checking start phase: current="..tostring(currentPhase), "ghost")
                if currentPhase == 169 then
                    shouldGhost = true
                    TRP3FW:Debug("[sendObject Hook] Start phase ghost for informationType: "..tostring(informationType), "ghost")
                end
            end

            if shouldGhost then
                local profileID = ghostProfileID or TRP3FW.Prefs.ghostProfileID
                local ghostData = TRP3FW:GetGhostDataForInformationType(informationType, profileID)

                if ghostData then
                    local valid, safeGhost = TRP3FW:ValidateGhostTRP3Payload(informationType, ghostData)
                    if not valid then
                        TRP3FW:Warn("[sendObject Hook] Invalid ghost payload; falling back to blank section")
                    end

                        local payloadToSend = safeGhost or TRP3FW:GetGhostDataForInformationType(informationType, nil)
                        if not payloadToSend then
                            TRP3FW:Warn("[sendObject Hook] Could not build ghost payload; blocking send to avoid malformed data")
                            return
                        end
                    TRP3FW:Debug("[sendObject Hook] Replacing with ghost data for "..tostring(informationType), "ghost")
                    object = {informationType, payloadToSend}  -- Replace data with ghost data
                else
                    TRP3FW:Warn("[sendObject Hook] Failed to get ghost data, blocking send")
                    return  -- Block send
                end
            end
        end

        -- Call original with potentially modified object
        local okCall, result = pcall(originalSendObject, prefix, object, ...)
        if not okCall then
            TRP3FW:Warn("[sendObject Hook] original sendObject threw an error; aborting send: "..tostring(result))
            return
        end

        return result
    end

    self:Debug("Installed AddOn_TotalRP3.Communications.sendObject hook (pre-serialization ghost mode)", "hooks")
    return true
end

-- Install TRP3 communication hooks
function TRP3FW:InstallTRP3Hooks()
    -- DEPRECATED: TRP3_API.Ellyb.AddonCommunication no longer exists in modern TRP3.
    -- Logic has been moved to InstallSendObjectHook (for ghost mode) and Chomp hooks (for blocking).
    self:Debug("InstallTRP3Hooks is deprecated and has been removed.", "hooks")
end

-- Install TRP3 map scan response notification
function TRP3FW:InstallTRP3ScanNotification()
    -- Only install if a scanner is present (TRP3 or RPMapScan)
    if not TRP3_API and not _G.RPMapScan then
        self:Debug("Skipping scan notification hook - no TRP3 or RPMapScan detected", "hooks")
        return
    end

    local function HandleScanReply(targetRaw, mapID, sendFunc, contextLabel)
        return TRP3FW:HandleScanReplyPipeline(targetRaw, sendFunc, contextLabel)
    end

    local unpack = table.unpack or unpack

    -- Hook into TRP3's broadcast.sendP2PMessage for C_SCAN responses
    if AddOn_TotalRP3 and AddOn_TotalRP3.Communications and AddOn_TotalRP3.Communications.broadcast then
        local commSystem = AddOn_TotalRP3.Communications.broadcast

        if commSystem.sendP2PMessage then
            local originalSendP2P = commSystem.sendP2PMessage
            commSystem.sendP2PMessage = function(target, command, ...)
                -- Check if this is a C_SCAN response
                if command == "C_SCAN" then
                    local start = debugprofilestop()
                    local args = {...}
                    local ret = HandleScanReply(target, C_Map.GetBestMapForUnit("player"), function()
                        return originalSendP2P(target, command, unpack(args))
                    end, "TRP3")
                    local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
                    if hs then hs:RecordPerformance(debugprofilestop() - start, "Scan Reply (TRP3)") end
                    return ret
                end

                -- Call original function
                return originalSendP2P(target, command, ...)
            end
            self:Debug("Installed TRP3 scan response notification hook", "hooks")
        else
            self:Debug("Failed to install TRP3 scan notification hook - sendP2PMessage not found", "hooks")
        end
    else
        self:Debug("Failed to install TRP3 scan notification hook - broadcast system not found", "hooks")
    end

    -- Hook into RPMapScan's SendP2PResponse (whisper replies only)
    if _G.RPMapScan and RPMapScan.SendP2PResponse then
        local originalRPMSend = RPMapScan.SendP2PResponse
        RPMapScan.SendP2PResponse = function(selfRef, target, requestedMapID, ...)
            local myMapID = C_Map.GetBestMapForUnit("player")
            if not myMapID or requestedMapID ~= myMapID then
                return originalRPMSend(selfRef, target, requestedMapID, ...)
            end

            local pos = C_Map.GetPlayerMapPosition(myMapID, "player")
            if not pos then
                return originalRPMSend(selfRef, target, requestedMapID, ...)
            end

            local args = {...}
            local start = debugprofilestop()
            local ret = HandleScanReply(target, requestedMapID, function()
                return originalRPMSend(selfRef, target, requestedMapID, unpack(args))
            end, "RPMapScan")
            local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
            if hs then hs:RecordPerformance(debugprofilestop() - start, "Scan Reply (RPMapScan)") end
            return ret
        end
        self:Debug("Installed RPMapScan scan response hook (P2P replies)", "hooks")
    end
end
