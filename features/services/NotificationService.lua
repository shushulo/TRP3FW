-- features/services/NotificationService.lua
-- Notification Service: Handles user notifications, suppression, and sound

local addonName, TRP3FW = ...

local NotificationService = TRP3FW.Service:New("NotificationService")

local function Redact(text)
    return TRP3FW:Redact(text)
end

function NotificationService:Initialize()
    TRP3FW.Service.Initialize(self)

    self.suppressionHistory = {} -- playerName -> {lastNotification, suppressedCount, lastType}
    self.startPhaseNotifications = {}
    self.lastGhostScreenNotification = {}
    self.lastGhostChatNotification = {}

    -- Register legacy alias for suppressor
    TRP3FW.NotificationSuppressor = {
        ShouldSuppress = function(_, playerName, notificationType, settings)
            return self:ShouldSuppress(playerName, notificationType, settings)
        end,
        Clear = function(_, playerName) self:ClearSuppression(playerName) end,
        ClearAll = function(_) self:ClearAllSuppression() end
    }
end

-- ===================== Suppression Logic =====================

function NotificationService:ShouldSuppress(playerName, notificationType, settings)
    local now = TRP3FW:GetCurrentTime()
    local history = self.suppressionHistory[playerName]

    -- Priority order: allow < alert < ghost/block. Higher priority should break suppression.
    local priority = { allow = 1, alert = 2, ghost = 3, block = 3 }
    local function priorityOf(t)
        return priority[t] or 0
    end

    if not history then
        -- First notification for this player
        self.suppressionHistory[playerName] = {
            lastNotification = now,
            suppressedCount = 0,
            lastType = notificationType
        }
        return false, 0
    end

    local timeSinceLastNotification = now - history.lastNotification

    -- If severity increased (e.g., allow -> alert/block/ghost), show immediately and reset suppression window
    if priorityOf(notificationType) > priorityOf(history.lastType) then
        history.lastNotification = now
        history.suppressedCount = 0
        history.lastType = notificationType
        return false, 0
    end

    if timeSinceLastNotification < settings.suppressionTime then
        -- Within suppression window - suppress
        history.suppressedCount = (history.suppressedCount or 0) + 1
        -- Refresh the timer so repeated spam keeps the window sliding (if enabled)
        if settings.refreshSuppression ~= false then
            history.lastNotification = now
        end
        history.lastType = notificationType
        return true, history.suppressedCount
    else
        -- Outside suppression window - show and reset counter
        local suppressedCount = history.suppressedCount
        history.lastNotification = now
        history.suppressedCount = 0
        history.lastType = notificationType
        return false, suppressedCount
    end
end

function NotificationService:ClearSuppression(playerName)
    self.suppressionHistory[playerName] = nil
end

function NotificationService:ClearAllSuppression()
    self.suppressionHistory = {}
end

-- ===================== Main Notify Entry Point =====================

function NotificationService:Notify(playerName, context)
    --[[
        context = {
            type = "allow" | "alert" | "block" | "ghost",
            addon = "TRP3",
            reason = string,
            isWhisper = boolean,
            location = {theirZone, ourZone, ...},
            settings = table (snapshot),
            cacheInfo = table
        }
    ]]

    local settings = context.settings or TRP3FW.Prefs -- Fallback if not snapshotted

    -- Back-compat: accept locationResult payloads
    if context.location == nil and context.locationResult then
        local lr = context.locationResult
        context.location = {
            theirZone = lr.theirZone,
            ourZone = lr.myZone,
            mapCacheAge = lr.mapCacheAge,
            recentTransition = lr.recentTransition,
            timeSinceTransition = lr.timeSinceTransition
        }
        context.cacheInfo = context.cacheInfo or lr.cacheInfo
        context.checkDetails = context.checkDetails or lr.checkDetails
    end

    -- 1. Check settings toggles
    if not self:ShouldNotifyType(context.type, context.isWhisper, settings) then
        return
    end

    -- 2. Check suppression
    local shouldSuppress, count = self:ShouldSuppress(playerName, context.type, settings)

    if shouldSuppress then
        TRP3FW:Debug("Notification suppressed for "..playerName.." ("..count..")", "send")
        return
    end

    -- 3. Update History Timestamp (via HistoryService)
    local historyService = TRP3FW.ServiceContainer:Get("HistoryService")
    if historyService then
        historyService:RecordSend(playerName)
    end

    -- 4. Display
    local isAlert = (context.type == "alert")
    local isBlock = (context.type == "block")
    local isGhost = (context.type == "ghost")
    local location = context.location or {}

    self:ShowChatNotification(
        playerName,
        context.addon,
        true, -- isFirstTime (since we passed suppression check)
        count,
        isAlert,
        location.theirMap,
        location.ourMap,
        location.theirZone,
        location.ourZone,
        context.alertType,
        isBlock or isGhost,
        location.mapCacheAge or 0,
        context.cacheInfo,
        location.recentTransition,
        location.timeSinceTransition,
        isGhost,
        context.checkDetails,
        context.contextDetails
    )

    if settings.showOnScreen then
        self:ShowOnScreenNotification(
            playerName,
            context.addon,
            true,
            isAlert,
            location.theirMap,
            location.ourMap,
            location.theirZone,
            location.ourZone,
            context.alertType,
            isBlock or isGhost,
            location.recentTransition,
            location.timeSinceTransition,
            isGhost
        )
    end

    if settings.playSound then
        self:PlayNotificationSound()
    end
end

function NotificationService:ShouldNotifyType(type, isWhisper, settings)
    if not settings.notifyEnabled then return false end

    if type == "allow" then
        if not settings.notifyOnAllow then return false end
    elseif type == "alert" then
        -- Alert mode implied enabled if alerts are generating
    elseif type == "block" then
        -- Block mode implied
    elseif type == "ghost" then
        -- Ghost mode implied
    end

    return true
end

-- ===================== Display Logic =====================

function NotificationService:PlayNotificationSound()
    if TRP3FW.Prefs.playSound then PlaySound(8959) end
end

function NotificationService:ShowStartPhaseBlockNotification(playerName, addon)
    -- Honor master notification toggle
    if not TRP3FW.Prefs.notifyEnabled then return end

    -- Check suppression
    if not self.startPhaseNotifications then
        self.startPhaseNotifications = {}
    end

    local now = TRP3FW:GetCurrentTime()
    local lastNotification = self.startPhaseNotifications[playerName]
    local suppressionTime = TRP3FW.Prefs.suppressionTime
    local isFirstTime = true
    local suppressedCount = 0

    if lastNotification then
        local timeSince = now - lastNotification.timestamp
        if timeSince < suppressionTime then
            -- Within suppression window
            lastNotification.suppressedCount = lastNotification.suppressedCount + 1
            TRP3FW:Debug("Suppressing start phase block notification for "..playerName.." (already notified "..string.format("%.1f", timeSince).."s ago, suppressed count: "..lastNotification.suppressedCount..")", "send")
            return
        else
            -- Outside suppression window, this is a new "first time"
            isFirstTime = false
            suppressedCount = lastNotification.suppressedCount
        end
    end

    -- Update suppression tracking
    self.startPhaseNotifications[playerName] = {
        timestamp = now,
        suppressedCount = 0
    }

    -- Determine if this is a ghost mode send for start phase
    local isGhostMode = TRP3FW.Prefs.ghostOnStartPhase and
                        TRP3FW.hasTRP3ExchangeHooks

    local prefix, action
    if isGhostMode then
        -- Get profile name for ghost mode
        local profileLabel = "BLANK"
        if TRP3FW.Prefs.ghostProfileID then
            local profile = TRP3FW:GetProfileByID(TRP3FW.Prefs.ghostProfileID)
            profileLabel = (profile and profile.name) or TRP3FW.Prefs.ghostProfileID
        end
        prefix = "|cffffaa00[GHOST MODE]|r (Profile: "..profileLabel..") "
        action = "sent alternate profile to"
    else
        prefix = "|cffff0000[BLOCKED]|r "
        action = "blocked for"
    end

    -- Chat notification
    if TRP3FW.Prefs.showInChat then
        local msg = string.format("%sYour profile was %s |cff00ccff%s|r", prefix, action, playerName)
        if TRP3FW.Prefs.showAddonSource and addon then
            msg = msg .. string.format(" via |cff%s%s|r", TRP3FW:GetAddonColor(addon), TRP3FW:GetAddonName(addon))
        end
        if not isFirstTime and suppressedCount > 0 then
            msg = msg .. string.format(" |cffaaaaaa(+%d suppressed in last %s)|r", suppressedCount, TRP3FW:FormatTime(suppressionTime))
        end
        msg = msg .. " |cffff0000(START PHASE BLOCK)|r"
        print(Redact(msg))
    end

    -- On-screen notification
    if TRP3FW.Prefs.notifyEnabled and TRP3FW.Prefs.showOnScreen then
        local screenPrefix
        if isGhostMode then
            local ghostProfileLabel = "BLANK"
            if TRP3FW.Prefs.ghostProfileID then
                local ghostProfile = TRP3FW:GetProfileByID(TRP3FW.Prefs.ghostProfileID)
                if ghostProfile and ghostProfile.name then
                    ghostProfileLabel = ghostProfile.name
                else
                    ghostProfileLabel = TRP3FW.Prefs.ghostProfileID
                end
            end
            screenPrefix = "[GHOST MODE] (Profile: "..ghostProfileLabel..")"
        else
            screenPrefix = "[BLOCKED]"
        end

        local screenMsg
        if TRP3FW.Prefs.showAddonSource and addon then
            screenMsg = string.format("%s: |cff00ff00%s|r via |cff%s%s|r\n|cffff0000Start Phase Block|r",
                screenPrefix, playerName, TRP3FW:GetAddonColor(addon), TRP3FW:GetAddonName(addon))
        else
            screenMsg = string.format("%s: |cff00ff00%s|r\n|cffff0000Start Phase Block|r", screenPrefix, playerName)
        end
        screenMsg = Redact(screenMsg)
        RaidNotice_AddMessage(RaidWarningFrame, screenMsg, ChatTypeInfo["RAID_WARNING"])
    end

    -- Sound
    if TRP3FW.Prefs.notifyEnabled then
        self:PlayNotificationSound()
    end
end

function NotificationService:ShowOnScreenNotification(playerName, addon, isFirstTime, isAlert, theirMap, ourMap, theirZone, ourZone, alertType, wasBlocked, recentTransition, timeSinceTransition, isGhost)
    if not TRP3FW.Prefs.notifyEnabled or not TRP3FW.Prefs.showOnScreen then return end
    local prefix

    -- Check if this was a ghost mode send (passed as parameter or check cache for backwards compatibility)
    local isGhostMode = isGhost
    if not isGhostMode then
        local CI = TRP3FW.CacheInterface
        local entry = CI and CI:Peek("allowedSenders", playerName) or nil
        isGhostMode = entry and entry.reason == "ghost_mode_blank_profile"
    end

    -- Also check if this is a start phase block with ghost mode enabled
    local isStartPhaseGhost = (alertType == "start_phase_block" and
                               TRP3FW.Prefs.ghostOnStartPhase and
                               TRP3FW.hasTRP3ExchangeHooks)

    local ghostProfileLabel = "BLANK"
    if TRP3FW.Prefs.ghostProfileID then
        local ghostProfile = TRP3FW:GetProfileByID(TRP3FW.Prefs.ghostProfileID)
        if ghostProfile and ghostProfile.name then
            ghostProfileLabel = ghostProfile.name
        else
            ghostProfileLabel = TRP3FW.Prefs.ghostProfileID
        end
    end

    if wasBlocked then
        if isGhostMode or isStartPhaseGhost then
            prefix = "[GHOST MODE] (Profile: "..ghostProfileLabel..")"
        else
            prefix = "[BLOCKED]"
        end
    elseif isAlert then
        prefix = "[ALERT]"
    else
        prefix = "Profile sent"
    end

    if wasBlocked and (isGhostMode or isStartPhaseGhost) then
        self.lastGhostScreenNotification = self.lastGhostScreenNotification or {}
        local now = GetTime()
        local last = self.lastGhostScreenNotification[playerName]
        if last and (now - last) < 2 then
            TRP3FW:Debug("[Notifications] Skipping duplicate on-screen ghost notification for "..playerName.." (ghost)", "ghost")
            return
        end
        self.lastGhostScreenNotification[playerName] = now
    end

    local color  = isFirstTime and "00ff00" or "ffff00"
    local msg
    if TRP3FW.Prefs.showAddonSource and addon then
        msg = string.format("%s: |cff%s%s|r via |cff%s%s|r", prefix, color, playerName, TRP3FW:GetAddonColor(addon), TRP3FW:GetAddonName(addon))
        if not isFirstTime then msg = msg .. " (again)" end
    else
        msg = string.format("%s: |cff%s%s|r", prefix, color, playerName)
        if not isFirstTime then msg = msg .. " (again)" end
    end

    -- Add alert details based on type
    if isAlert and alertType then
        local hasPhase = alertType:find("phase")
        local hasPhaseUnknown = alertType:find("phase_unknown")
        local hasMap = alertType:find("map")

        if hasPhaseUnknown then
            msg = msg .. "\n|cffff0000Phase verification failed (API Error)|r"
        elseif hasPhase and hasMap then
            -- Both checks failed - they're in different phase AND not found on map
            msg = msg .. "\n|cffff0000Not in your phase and on different map|r"
        elseif hasPhase then
            -- Phase check failed only - can't target them (different phase or not loaded yet)
            msg = msg .. "\n|cffff0000Not in your phase (or not loaded yet)|r"
        elseif hasMap then
            -- Map check failed but phase passed - shouldn't happen if we can target them
            -- This likely means same phase but different map
            -- Prefer zone names; fall back to map names/IDs
            local fromZone = TRP3FW:FormatLocation(ourZone, ourMap)
            local toZone   = TRP3FW:FormatLocation(theirZone, theirMap)
            msg = msg .. string.format("\n|cffff0000They're in %s, you're in %s|r", toZone, fromZone)
        elseif alertType == "noscan" then
            msg = msg .. "\n|cffff0000Location could not be verified|r"
        end

        -- Add warning about recent transition (race condition possibility)
        if recentTransition and timeSinceTransition then
            msg = msg .. string.format("\n|cffffff00Warning: You changed maps/phases %ds ago|r", math.floor(timeSinceTransition))
            msg = msg .. "\n|cffffff00This may be a false alert (loading delay)|r"
        end
    end

    msg = Redact(msg)
    RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    if isAlert or wasBlocked then
        C_Timer.After(0.5, function()
            RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
        end)
    end
end

function NotificationService:ShowChatNotification(playerName, addon, isFirstTime, suppressedCount, isAlert, theirMap, ourMap, theirZone, ourZone, alertType, wasBlocked, mapCacheAge, cacheInfo, recentTransition, timeSinceTransition, isGhost, checkDetails, contextDetails)
    TRP3FW:Debug("[NOTIF] Calling ShowChatNotification for "..playerName, "send")
	TRP3FW:Debug(function()
		return string.format("[Notifications] ShowChatNotification enter: showInChat=%s player=%s addon=%s isAlert=%s wasBlocked=%s isFirstTime=%s",
			tostring(TRP3FW.Prefs.showInChat), tostring(playerName), tostring(addon), tostring(isAlert), tostring(wasBlocked), tostring(isFirstTime))
	end, "send")

	if not TRP3FW.Prefs.showInChat then
		self:DebugNotificationSuppression("showInChat=false", playerName, addon, nil, {showInChat=false, isAlert=isAlert, wasBlocked=wasBlocked})
		return
	end
	local contextInfo = contextDetails or {}
	local contextType = contextInfo.context or contextInfo.type or "profile"
	local subjectLabel = contextInfo.subject or (contextType == "scan" and "scan reply" or "profile")
	local subjectDetail = contextInfo.subjectDetail
	local contextPrefix = contextInfo.prefix
	if contextPrefix == nil then
		contextPrefix = (contextType == "scan") and "|cff00ccff[SCAN]|r " or ""
	end
	local contextNote = contextInfo.note
	local prefix
	local action

	-- Check if this was a ghost mode send (passed as parameter or check cache for backwards compatibility)
	local isGhostMode = isGhost
    if not isGhostMode then
        local CI = TRP3FW.CacheInterface
        local entry = CI and CI:Peek("allowedSenders", playerName) or nil
        isGhostMode = entry and entry.reason == "ghost_mode_blank_profile"
    end

    -- Also check if this is a start phase block with ghost mode enabled
    local isStartPhaseGhost = (alertType == "start_phase_block" and
                               TRP3FW.Prefs.ghostOnStartPhase and
                               TRP3FW.hasTRP3ExchangeHooks)

    if wasBlocked then
        if isGhostMode or isStartPhaseGhost then
            local profileLabel = "BLANK"
            if TRP3FW.Prefs.ghostProfileID then
                local profile = TRP3FW:GetProfileByID(TRP3FW.Prefs.ghostProfileID)
                profileLabel = (profile and profile.name) or TRP3FW.Prefs.ghostProfileID
            end
            prefix = "|cffffaa00[GHOST MODE]|r (Profile: "..profileLabel..") "
            action = "sent alternate profile to"
        else
            prefix = "|cffff0000[BLOCKED]|r "
            action = "blocked for"
        end
    elseif isAlert then
        prefix = "|cffff0000[ALERT]|r "
        action = "sent to"
    else
        prefix = ""
        action = "sent to"
    end

    if isGhostMode or isStartPhaseGhost then
        self.lastGhostChatNotification = self.lastGhostChatNotification or {}
        local now = GetTime()
        local last = self.lastGhostChatNotification[playerName]
        if last and (now - last) < 2 then
            TRP3FW:Debug("[Notifications] Skipping duplicate ghost chat notification for "..playerName.." (ghost)", "ghost")
            return
        end
		self.lastGhostChatNotification[playerName] = now
	end

	local function GetSubjectText()
		if subjectDetail and subjectDetail ~= "" then
			return subjectLabel.." ("..subjectDetail..")"
		end
		return subjectLabel
	end

	local msg = string.format("%s%sYour %s was %s |cff00ccff%s|r", contextPrefix, prefix, GetSubjectText(), action, playerName)
	if TRP3FW.Prefs.showAddonSource and addon then
		msg = msg .. string.format(" via |cff%s%s|r", TRP3FW:GetAddonColor(addon), TRP3FW:GetAddonName(addon))
	end
	if contextNote and contextNote ~= "" then
		msg = msg .. string.format(" |cffaaaaaa(%s)|r", contextNote)
	end
	if not isFirstTime and suppressedCount > 0 then
		msg = msg .. string.format(" |cffaaaaaa(+%d suppressed in last %s)|r", suppressedCount, TRP3FW:FormatTime(TRP3FW.Prefs.suppressionTime))
	end

    -- Add alert details
    if (isAlert or wasBlocked) and alertType then
        local hasPhase = alertType:find("phase")
        local hasPhaseUnknown = alertType:find("phase_unknown")
        local hasMap = alertType:find("map")

        -- Helper to decide if map failure was a confirmed mismatch vs inconclusive/timeout
        local mapMismatch = false
        if checkDetails and checkDetails.map and checkDetails.map.source then
            local src = checkDetails.map.source
            if src:find("mismatch", 1, true) or src:find("phase_check", 1, true) then
                mapMismatch = true
            end
        end

        if hasPhaseUnknown then
            msg = msg .. " |cffff0000(Phase verification failed/error)|r"
        elseif hasPhase and hasMap then
            -- Both checks failed; only claim different map when we have evidence
            if mapMismatch or (theirZone and ourZone and theirZone ~= ourZone) or (theirMap and ourMap and theirMap ~= ourMap) then
                msg = msg .. " |cffff0000(Not in your phase and on different map)|r"
            else
                msg = msg .. " |cffff0000(Not in your phase; map check inconclusive)|r"
            end
        elseif hasPhase then
            -- Phase check failed only - can't target them (different phase or not loaded yet)
            msg = msg .. " |cffff0000(Not in your phase or not loaded yet)|r"
        elseif hasMap then
            -- Map check failed but phase passed
            if theirZone or ourZone then
                local fromZone = ourZone or (ourMap and TRP3FW:GetMapName(ourMap)) or "?"
                local toZone   = theirZone or (theirMap and TRP3FW:GetMapName(theirMap)) or "?"
                if toZone == "?" and fromZone ~= "?" then
                    msg = msg .. string.format(" |cffff0000(Location unknown; you're in %s)|r", fromZone)
                else
                    msg = msg .. string.format(" |cffff0000(They're in %s, you're in %s)|r", toZone, fromZone)
                end
            elseif theirMap and ourMap then
                local fromZone = TRP3FW:GetMapName(ourMap)
                local toZone   = TRP3FW:GetMapName(theirMap)
                msg = msg .. string.format(" |cffff0000(They're in %s, you're in %s)|r", toZone or "?", fromZone or "?")
            else
                msg = msg .. " |cffff0000(Location unknown from map check)|r"
            end
            if mapCacheAge and mapCacheAge > 0 then
                msg = msg .. string.format(" |cffaaaaaa(scanned %ds ago)|r", math.floor(mapCacheAge))
            end
        elseif alertType == "noscan" then
            msg = msg .. " |cffff0000(Location unknown)|r"
        end

        -- Add warning about recent transition (race condition possibility)
        if recentTransition and timeSinceTransition then
            msg = msg .. string.format(" |cffffff00[WARNING: Map/phase changed %ds ago - possible false alert]|r", math.floor(timeSinceTransition))
        end
    end

    -- Append check result details if enabled
    if TRP3FW.Prefs.showCheckResults and checkDetails then
        local parts = {}

        local function formatResult(label, info)
            if not info then return end
            local status
            if info.disabled then
                status = "off"
            elseif info.skippedBecausePhase then
                status = "skip"
            elseif info.result == true then
                status = "pass"
            elseif info.result == false then
                status = "fail"
            else
                status = "unknown"
            end

            local method = info.method or info.source
            if info.skippedBecausePhase then
                method = "phase pass"
            elseif info.disabled then
                method = method or "disabled"
            end

            if method then
                table.insert(parts, string.format("%s=%s (%s)", label, status, method))
            else
                table.insert(parts, string.format("%s=%s", label, status))
            end
        end

        formatResult("phase", checkDetails.phase)
        formatResult("map", checkDetails.map)

        if #parts > 0 then
            msg = msg .. string.format(" |cffaaaaaa[checks: %s]|r", table.concat(parts, ", "))
        end
    end

    -- Append cache info if enabled and not an alert/block
    if TRP3FW.Prefs.showCacheInfo and not isAlert and not wasBlocked and cacheInfo then
        local caches = {}

        -- Check which caches were hit
        if cacheInfo.interactionCache == "hit" then
            table.insert(caches, "interaction")
        end
        if cacheInfo.allowedSenders == "hit" then
            -- Show the reason for being allowed (what cache led to allowedSenders cache)
            if cacheInfo.allowedSendersReason then
                -- Make reasons more readable and verbose
                local reasonMap = {
                    ["recent_interaction"] = "reason: interaction cache",
                    ["current_target"] = "reason: current target",
                    ["mouseover_interaction"] = "reason: mouseover",
                    ["target_interaction"] = "reason: target interaction",
                    ["user_interaction"] = "reason: user interaction",
                    ["location_ok"] = "reason: location check passed",
                    ["location_ok_or_not_checked"] = "reason: location check passed",
                    ["no_alerts"] = "reason: no checks enabled",
                    ["whitelist"] = "reason: whitelist"
                }
                local displayReason = reasonMap[cacheInfo.allowedSendersReason] or ("reason: "..cacheInfo.allowedSendersReason)
                table.insert(caches, displayReason)
            else
                table.insert(caches, "allowed")
            end
        end
        if cacheInfo.phaseCache == "hit" then
            table.insert(caches, "phase")
        end
        if cacheInfo.whoCache == "hit" then
            table.insert(caches, "WHO")
        end
        if cacheInfo.mapCache == "hit" then
            table.insert(caches, "map")
        end
        if cacheInfo.whitelist == "hit" then
            table.insert(caches, "whitelist")
        end

        -- Display cache info
        if #caches > 0 then
            msg = msg .. string.format(" |cffaaaaaa[cache: %s]|r", table.concat(caches, ", "))
        else
            msg = msg .. " |cffaaaaaa[cache: miss]|r"
        end
    end

    msg = Redact(msg)
    TRP3FW:PrintColored(isAlert and "warn" or (isFirstTime and "info" or "debug"), msg)
	TRP3FW:Debug("[NOTIF] Chat notification printed: "..tostring(msg), "send")
end

function NotificationService:DebugNotificationSuppression(context, playerName, addon, isWhisper, reasonTable)
    if not TRP3FW.Prefs.debug then return end
    local parts = {}
    for k, v in pairs(reasonTable or {}) do
        table.insert(parts, k..":"..tostring(v))
    end
    TRP3FW:Debug(string.format("[Notifications] Suppressed (%s) for %s via %s | reasons: %s", context or "unknown", tostring(playerName), tostring(addon), table.concat(parts, ", ")), "send")
end

TRP3FW.ServiceContainer:Register(NotificationService)
