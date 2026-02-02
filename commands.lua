-- commands.lua
-- Slash command handlers

local addonName, TRP3FW = ...

-- Register slash command
SLASH_TRP3FW1 = "/trp3fw"
SlashCmdList.TRP3FW = function(msg)
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = (cmd or ""):lower()
    rest = rest or ""

    if cmd == "" or cmd == "help" then
        TRP3FW:ShowHelp()
        return
    end

    if cmd == "status" then
        TRP3FW:ShowStatus()
        return

    elseif cmd == "stats" then
        TRP3FW:ShowStats()
        return

    elseif cmd == "test" then
        TRP3FW:TestNotifications()
        return

    elseif cmd == "location" or cmd == "where" then
        -- Show current map ID and zone name
        local mapID = TRP3FW:GetCurrentMapID()
        local zoneName = TRP3FW.currentZoneName or GetRealZoneText() or GetZoneText() or "Unknown"
        local subZone = GetSubZoneText() or ""
        local minimapZone = GetMinimapZoneText() or ""

        TRP3FW:Info("|cff00ffffCurrent Location Information|r")
        TRP3FW:Info("|cff00ccffMap ID:|r " .. (mapID and tostring(mapID) or "|cffff0000[Not Available]|r"))
        if mapID then
            local mapName = TRP3FW:GetMapName(mapID)
            if mapName then
                TRP3FW:Info("|cff00ccffMap Name:|r " .. mapName)
            end
        end
        TRP3FW:Info("|cff00ccffZone:|r " .. zoneName)
        if subZone and subZone ~= "" then
            TRP3FW:Info("|cff00ccffSubzone:|r " .. subZone)
        end
        if minimapZone and minimapZone ~= "" and minimapZone ~= zoneName then
            TRP3FW:Info("|cff00ccffMinimap Zone:|r " .. minimapZone)
        end

        -- Show Epsilon phase info if available
        if TRP3FW.hasEpsilonAPI then
            local phaseID = TRP3FW:GetCurrentPhaseID()
            if phaseID then
                TRP3FW:Info("|cff00ccffEpsilon Phase ID:|r " .. tostring(phaseID))
            end
        end

        TRP3FW:Info("|cffaaaaaa━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
        TRP3FW:Info("|cffaaaaaaDifference:|r |cff00ff00Map ID|r = numeric ID used by WoW's map system")
        TRP3FW:Info("           |cff00ff00Zone|r = text name of the area you're in")
        return

    elseif cmd == "notify" then
        local arg = rest:lower()
        local function b(flag) return flag and "|cff00ff00ON|r" or "|cffaaaaaaOFF|r" end
        if arg == "" then
            TRP3FW:Info("Notifications: "..b(TRP3FW_Settings.notifyEnabled))
            TRP3FW:Info("  Broadcasts: "..b(TRP3FW_Settings.notifyOnBroadcast))
            TRP3FW:Info("  Whispers: "..b(TRP3FW_Settings.notifyOnWhisper))
            TRP3FW:Info("  Start phase blocks: "..b(TRP3FW_Settings.notifyOnStartPhaseBlock))
        elseif arg == "toggle" then
            TRP3FW_Settings.notifyEnabled = not TRP3FW_Settings.notifyEnabled
            TRP3FW:Info("Notifications "..b(TRP3FW_Settings.notifyEnabled))
        elseif arg == "allow" then
            TRP3FW_Settings.notifyEnabled = true
            TRP3FW:Info("Notifications forced ON")
        elseif arg == "broadcast" then
            TRP3FW_Settings.notifyOnBroadcast = not TRP3FW_Settings.notifyOnBroadcast
            TRP3FW:Info("Broadcast notifications "..b(TRP3FW_Settings.notifyOnBroadcast))
        elseif arg == "whisper" then
            TRP3FW_Settings.notifyOnWhisper = not TRP3FW_Settings.notifyOnWhisper
            TRP3FW:Info("Whisper notifications "..b(TRP3FW_Settings.notifyOnWhisper))
        elseif arg == "startphase" then
            TRP3FW_Settings.notifyOnStartPhaseBlock = not TRP3FW_Settings.notifyOnStartPhaseBlock
            TRP3FW:Info("Start-phase block notifications "..b(TRP3FW_Settings.notifyOnStartPhaseBlock))
        else
            TRP3FW:Warn("Usage: /trp3fw notify [toggle|allow|broadcast|whisper|startphase]")
        end
        return

    elseif cmd == "suppress" then
        local secs = tonumber(rest)
        if secs == nil then
            TRP3FW:Info("Suppression time: "..tostring(TRP3FW_Settings.suppressionTime or 0).." seconds")
        elseif secs >= 0 and secs <= 3600 then
            TRP3FW_Settings.suppressionTime = secs
            TRP3FW:Info("Notification suppression set to "..secs.." seconds")
        else
            TRP3FW:Warn("Usage: /trp3fw suppress <0-3600>")
        end
        return

    elseif cmd == "display" then
        local arg = rest:lower()
        if arg == "" then
            -- Show status
            TRP3FW:Info("Display settings:")
            TRP3FW:Info("  Chat: "..(TRP3FW_Settings.showInChat and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            TRP3FW:Info("  Screen: "..(TRP3FW_Settings.showOnScreen and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            TRP3FW:Info("  Sound: "..(TRP3FW_Settings.playSound and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            TRP3FW:Info("  Source: "..(TRP3FW_Settings.showAddonSource and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            TRP3FW:Info("  Cache info: "..(TRP3FW_Settings.showCacheInfo and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            TRP3FW:Info("  Check results: "..(TRP3FW_Settings.showCheckResults and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            TRP3FW:Info("  Ghost notifications: "..(TRP3FW_Settings.showGhostNotifications and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif arg == "toggle" then
            -- Toggle all display settings on/off together
            local newState = not (TRP3FW_Settings.showInChat or TRP3FW_Settings.showOnScreen or TRP3FW_Settings.playSound)
            TRP3FW_Settings.showInChat = newState
            TRP3FW_Settings.showOnScreen = newState
            TRP3FW_Settings.playSound = newState
            TRP3FW:Info("All display settings "..(newState and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif arg == "chat" then
            TRP3FW_Settings.showInChat = not TRP3FW_Settings.showInChat
            TRP3FW:Info("Chat notifications "..(TRP3FW_Settings.showInChat and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif arg == "screen" then
            TRP3FW_Settings.showOnScreen = not TRP3FW_Settings.showOnScreen
            TRP3FW:Info("On-screen notifications "..(TRP3FW_Settings.showOnScreen and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif arg == "sound" then
            TRP3FW_Settings.playSound = not TRP3FW_Settings.playSound
            TRP3FW:Info("Notification sound "..(TRP3FW_Settings.playSound and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif arg == "source" then
            TRP3FW_Settings.showAddonSource = not TRP3FW_Settings.showAddonSource
            TRP3FW:Info("Addon source display "..(TRP3FW_Settings.showAddonSource and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif arg == "cache" or arg == "cacheinfo" then
            TRP3FW_Settings.showCacheInfo = not TRP3FW_Settings.showCacheInfo
            TRP3FW:Info("Cache info in notifications "..(TRP3FW_Settings.showCacheInfo and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif arg == "checks" or arg == "checkresults" then
            TRP3FW_Settings.showCheckResults = not TRP3FW_Settings.showCheckResults
            TRP3FW:Info("Check result details in notifications "..(TRP3FW_Settings.showCheckResults and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif arg == "ghost" then
            TRP3FW_Settings.showGhostNotifications = not TRP3FW_Settings.showGhostNotifications
            TRP3FW:Info("Ghost notifications "..(TRP3FW_Settings.showGhostNotifications and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        else
            TRP3FW:Warn("Usage: /trp3fw display [toggle | chat | screen | sound | source | cache | checks]")
        end

    elseif cmd == "alert" or cmd == "enable" or cmd == "disable" or cmd == "block" then
        TRP3FW:Warn("|cffffff00DEPRECATED:|r This command has been replaced by the new dropdown system")
        TRP3FW:Info("Please use |cff00ff00/trp3fwui|r to configure Phase Check Mode and Map Check Mode dropdowns")

	elseif cmd == "whobackend" or cmd == "who-ui" then
		TRP3FW:Warn("WHO backend selection is no longer supported; using default WHO behavior.")

	elseif cmd == "whoqueue" then
		TRP3FW:Warn("WHO queue policy is no longer configurable; using default behavior.")

	elseif cmd == "whocache" then
		TRP3FW:Warn("Caching user /who results is no longer configurable; using default behavior.")

	elseif cmd == "scanreply" or cmd == "scan" then
		local arg = rest:lower()
		if arg == "" then
			TRP3FW:Info("Scan reply settings:")
                local phaseMode = TRP3FW_Settings.scanResponsePhaseMode or "off"
                local mapMode = TRP3FW_Settings.scanResponseMapMode or "off"
                local protectionsOn = TRP3FW.hasEpsilonAPI and (phaseMode ~= "off" or mapMode ~= "off")
				TRP3FW:Info("  Protections: "..(protectionsOn and "|cff00ff00on|r (phase/map mode not off)" or "|cffaaaaaaoff|r (phase/map modes off or no Epsilon)"))
				TRP3FW:Info("  Notify: "..(TRP3FW_Settings.notifyOnScanResponse and "|cff00ff00on|r" or "|cffaaaaaaoff|r"))
	            TRP3FW:Info("  Phase mode: "..phaseMode)
	            TRP3FW:Info("  Map mode: "..mapMode)
                TRP3FW:Info("  Strict nonce: "..(TRP3FW_Settings.scanResponseRequireNonce and "|cff00ff00on|r (reject missing nonces)" or "|cffaaaaaaoff|r (accept missing for compatibility)"))
	            TRP3FW:Info("  Cache scan WHO results: "..(TRP3FW_Settings.scanResponseCacheEnabled and "|cff00ff00on|r" or "|cffaaaaaaoff|r").." (only when WHO runs)")
	            TRP3FW:Info("  Cache bypass (allowed/interaction/phase): "..(TRP3FW_Settings.scanResponseAllowCacheBypass and "|cff00ff00on|r" or "|cffaaaaaaoff|r"))
                TRP3FW:Info("Usage: /trp3fw scanreply notify|phasemode <off|alert|block>|mapmode <off|alert|block>|nonce|cache|bypass")
	        elseif arg == "notify" then
	            TRP3FW_Settings.notifyOnScanResponse = not TRP3FW_Settings.notifyOnScanResponse
	            TRP3FW:Info("Scan reply notifications "..(TRP3FW_Settings.notifyOnScanResponse and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif arg == "nonce" then
            TRP3FW_Settings.scanResponseRequireNonce = not TRP3FW_Settings.scanResponseRequireNonce
            if TRP3FW_Settings.scanResponseRequireNonce then
                TRP3FW:Info("Scan replies now require nonce tokens (older scanners without nonce will be ignored)")
            else
                TRP3FW:Info("Scan replies accept missing nonce tokens (compatibility mode)")
            end
        elseif arg:match("^phasemode%s+") then
            local mode = arg:match("^phasemode%s+(%S+)")
            if mode == "alert" or mode == "block" or mode == "off" then
                TRP3FW_Settings.scanResponsePhaseMode = mode
                TRP3FW:Info("Scan reply phase mode set to "..mode)
            else
                TRP3FW:Warn("Usage: /trp3fw scanreply phasemode <off|alert|block>")
            end
        elseif arg:match("^mapmode%s+") then
            local mode = arg:match("^mapmode%s+(%S+)")
            if mode == "alert" or mode == "block" or mode == "off" then
                local previous = TRP3FW_Settings.scanResponseMapMode or "off"
                TRP3FW_Settings.scanResponseMapMode = mode
                TRP3FW:Info("Scan reply map mode set to "..mode)
                if mode == "block" and previous ~= "block" then
                    if wipe then
                        wipe(TRP3FW.interactionCache)
                    else
                        TRP3FW.interactionCache = {}
                    end
                    TRP3FW:Debug("[Scan Reply] Cleared interactionCache after enabling map block mode (scan replies)", "cache")
                end
            else
                TRP3FW:Warn("Usage: /trp3fw scanreply mapmode <off|alert|block>")
            end
        elseif arg == "cache" then
            TRP3FW_Settings.scanResponseCacheEnabled = not TRP3FW_Settings.scanResponseCacheEnabled
            TRP3FW:Info("Scan reply WHO caching "..(TRP3FW_Settings.scanResponseCacheEnabled and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif arg == "bypass" then
            TRP3FW_Settings.scanResponseAllowCacheBypass = not TRP3FW_Settings.scanResponseAllowCacheBypass
            TRP3FW:Info("Scan reply cache bypass "..(TRP3FW_Settings.scanResponseAllowCacheBypass and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            else
                TRP3FW:Warn("Usage: /trp3fw scanreply [notify|phasemode <off|alert|block>|mapmode <off|alert|block>|nonce|cache|bypass]")
        end

    elseif cmd == "mapscaninterval" or cmd == "scaninterval" then
        local val = tonumber(rest)
        if not val then
            TRP3FW:Info(string.format("Map scan minimum interval: %s seconds", tostring(TRP3FW_Settings.mapScanMinInterval or 60)))
            TRP3FW:Info("Usage: /trp3fw mapscaninterval <10-600>")
        elseif val >= 10 and val <= 600 then
            TRP3FW_Settings.mapScanMinInterval = val
            TRP3FW:Info("Map scan minimum interval set to "..val.." seconds")
        else
            TRP3FW:Warn("Invalid value (must be 10-600)")
        end

    elseif cmd == "groupbypass" or cmd == "group" then
        TRP3FW_Settings.allowGroupPhaseBypass = not TRP3FW_Settings.allowGroupPhaseBypass
        TRP3FW:Info("Party/raid auto-allow "..(TRP3FW_Settings.allowGroupPhaseBypass and "|cff00ff00enabled|r (group members skip checks)" or "|cffaaaaaadisabled|r (group members require full checks)"))

    elseif cmd == "hooks" then
        local arg = rest:lower()
        local function b(v) return v and "|cff00ff00on|r" or "|cffaaaaaaoff|r" end
        if arg == "" or arg == "status" then
            TRP3FW:Info("Hook settings:")
            TRP3FW:Info("  Strict: "..b(TRP3FW_Settings.strictHookMode))
            TRP3FW:Info("  Log conflicts: "..b(TRP3FW_Settings.logHookConflicts))
            TRP3FW:Info("  Abort on multiple RP addons: "..b(TRP3FW_Settings.abortOnMultipleRPAddons))
            TRP3FW:Info("  Disable map scan on TRP3+RPMapScan: "..b(TRP3FW_Settings.disableMapScanOnTRP3))
            if TRP3FW.disabledReason then
                TRP3FW:Warn("TRP3FW disabled: "..tostring(TRP3FW.disabledReason))
            end
            if TRP3FW.mapScanDisabledReason then
                TRP3FW:Warn("Map scan disabled: "..tostring(TRP3FW.mapScanDisabledReason))
            end
            if TRP3FW.hookConflicts and next(TRP3FW.hookConflicts) then
                TRP3FW:Info("Hook conflicts detected:")
                for name, data in pairs(TRP3FW.hookConflicts) do
                    TRP3FW:Info(string.format("  %s: reason=%s action=%s source=%s", name, tostring(data.reason), tostring(data.action), tostring(data.source)))
                end
            end
        elseif arg == "strict" then
            TRP3FW_Settings.strictHookMode = not TRP3FW_Settings.strictHookMode
            TRP3FW:Info("Strict hook mode "..(TRP3FW_Settings.strictHookMode and "enabled" or "disabled"))
        elseif arg == "conflicts" then
            TRP3FW_Settings.logHookConflicts = not TRP3FW_Settings.logHookConflicts
            TRP3FW:Info("Hook conflict logging "..(TRP3FW_Settings.logHookConflicts and "enabled" or "disabled"))
        elseif arg == "abortmulti" then
            TRP3FW_Settings.abortOnMultipleRPAddons = not TRP3FW_Settings.abortOnMultipleRPAddons
            TRP3FW:Info("Abort on multiple RP addons "..(TRP3FW_Settings.abortOnMultipleRPAddons and "enabled" or "disabled"))
        elseif arg == "mapscan" or arg == "trp3mapscan" then
            TRP3FW_Settings.disableMapScanOnTRP3 = not TRP3FW_Settings.disableMapScanOnTRP3
            TRP3FW:Info("Map scan disable for TRP3+RPMapScan "..(TRP3FW_Settings.disableMapScanOnTRP3 and "enabled" or "disabled"))
        else
            TRP3FW:Warn("Usage: /trp3fw hooks [status|strict|conflicts|abortmulti|mapscan]")
        end

    elseif cmd == "redact" then
        local arg = rest:lower()
        local function showStatus()
            TRP3FW:Info("Redaction: "..(TRP3FW_Settings.redactEnabled and "|cff00ff00on|r" or "|cffaaaaaaoff|r"))
            TRP3FW:Info("  Names: "..(TRP3FW_Settings.redactNames and "|cff00ff00on|r" or "|cffaaaaaaoff|r"))
            TRP3FW:Info("  Locations: "..(TRP3FW_Settings.redactLocations and "|cff00ff00on|r" or "|cffaaaaaaoff|r"))
            TRP3FW:Info("  Network: "..(TRP3FW_Settings.redactNetwork and "|cff00ff00on|r" or "|cffaaaaaaoff|r"))
        end

        local function toggle(key)
            TRP3FW_Settings[key] = not TRP3FW_Settings[key]
            TRP3FW:Info(key.." "..(TRP3FW_Settings[key] and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        end

        if arg == "" then
            showStatus()
        elseif arg == "toggle" or arg == "on" or arg == "off" then
            if arg == "on" then TRP3FW_Settings.redactEnabled = true
            elseif arg == "off" then TRP3FW_Settings.redactEnabled = false
            else TRP3FW_Settings.redactEnabled = not TRP3FW_Settings.redactEnabled end
            TRP3FW:Info("Redaction "..(TRP3FW_Settings.redactEnabled and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif arg == "names" then
            toggle("redactNames")
        elseif arg == "locations" or arg == "location" then
            toggle("redactLocations")
        elseif arg == "network" then
            toggle("redactNetwork")
        else
            TRP3FW:Warn("Usage: /trp3fw redact [toggle|on|off|names|locations|network]")
        end

        return

    elseif cmd == "ghost" then
        TRP3FW:Warn("|cffffff00DEPRECATED:|r Ghost mode is now integrated into Phase/Map Check Mode dropdowns")
        TRP3FW:Info("Please use |cff00ff00/trp3fwui|r and select 'Ghost' or 'Alert + Ghost' in the dropdowns")

    elseif cmd == "profileswitch" then
        -- Toggle ghostProfileSwitch setting
        TRP3FW_Settings.ghostProfileSwitch = not TRP3FW_Settings.ghostProfileSwitch
        if TRP3FW_Settings.ghostProfileSwitch then
            TRP3FW:Warn("Profile switching |cff00ff00enabled|r")
            TRP3FW:Warn("|cffffff00WARNING:|r This is EXPERIMENTAL and may cause errors in other TRP3 addons!")
            TRP3FW:Info("TRP3FW will switch to blank profile in Phase 169 + Map 1605")
        else
            TRP3FW:Info("Profile switching |cffaaaaaadisabled|r")
            TRP3FW:Info("Ghost mode will use exchange hooks instead (recommended)")
        end

    elseif cmd == "ghostprofile" then
        local arg = rest:lower()

        if arg == "" then
            -- Show current ghost profile
            local addonName = TRP3FW:GetDetectedAddonName()
            if addonName then
                TRP3FW:Info("Detected RP addon: |cff00ff00"..addonName.."|r")
            else
                TRP3FW:Warn("No RP addon detected (TRP3, MRP, XRP)")
                TRP3FW:Info("Install an RP addon to use alternate ghost profiles")
                return
            end

            if TRP3FW_Settings.ghostProfileID then
                local profile = TRP3FW:GetProfileByID(TRP3FW_Settings.ghostProfileID)
                if profile then
                    TRP3FW:Info("Current ghost profile: |cff00ff00"..profile.name.."|r")
                    TRP3FW:Info("  Addon: "..profile.addon)
                    TRP3FW:Info("  ID: "..profile.id)
                    if profile.isCurrent then
                        TRP3FW:Info("  |cffffff00(This is your current active profile)|r")
                    end
                else
                    TRP3FW:Warn("Ghost profile not found: "..TRP3FW_Settings.ghostProfileID)
                    TRP3FW:Info("Use '/trp3fw ghostprofile list' to see available profiles")
                end
            else
                TRP3FW:Info("Current ghost profile: |cffffff00Blank (empty)|r")
            end
            TRP3FW:Info("Use '/trp3fw ghostprofile list' to see all profiles")
            TRP3FW:Info("Use '/trp3fw ghostprofile <name>' to select a profile")
            TRP3FW:Info("Use '/trp3fw ghostprofile blank' to use blank profile")

        elseif arg == "list" then
            -- List all available profiles
            local addonName = TRP3FW:GetDetectedAddonName()
            if not addonName then
                TRP3FW:Warn("No RP addon detected (TRP3, MRP, XRP)")
                TRP3FW:Info("Install an RP addon to use alternate ghost profiles")
                return
            end

            TRP3FW:Info("Detected RP addon: |cff00ff00"..addonName.."|r")

            local profiles = TRP3FW:GetAllProfiles()
            if #profiles == 0 then
                TRP3FW:Warn("No profiles found")
                return
            end

            TRP3FW:Info("Available profiles ("..#profiles.."):")
            for _, profile in ipairs(profiles) do
                local marker = ""
                if profile.isCurrent then
                    marker = " |cffffff00(current)|r"
                end
                if TRP3FW_Settings.ghostProfileID == profile.id then
                    marker = marker.." |cff00ff00[GHOST]|r"
                end
                TRP3FW:Info("  "..profile.name..marker)
            end
            TRP3FW:Info("Use '/trp3fw ghostprofile <name>' to select a profile")

        elseif arg == "blank" then
            -- Set to blank profile mode
            TRP3FW_Settings.ghostProfileID = nil
            TRP3FW:Info("Ghost profile set to: |cffffff00Blank (empty)|r")

        else
            -- Try to find profile by name (case-insensitive)
            local addonName = TRP3FW:GetDetectedAddonName()
            if not addonName then
                TRP3FW:Warn("No RP addon detected (TRP3, MRP, XRP)")
                TRP3FW:Info("Install an RP addon to use alternate ghost profiles")
                return
            end

            local profiles = TRP3FW:GetAllProfiles()
            local found = nil

            -- Search for profile by name (case-insensitive)
            for _, profile in ipairs(profiles) do
                if profile.name:lower() == arg or profile.name:lower():find(arg, 1, true) then
                    if found then
                        -- Multiple matches
                        TRP3FW:Warn("Multiple profiles match '"..rest.."':")
                        TRP3FW:Info("  "..found.name)
                        TRP3FW:Info("  "..profile.name)
                        TRP3FW:Info("Please be more specific")
                        return
                    end
                    found = profile
                end
            end

            if found then
                TRP3FW_Settings.ghostProfileID = found.id
                TRP3FW:Info("Ghost profile set to: |cff00ff00"..found.name.."|r")
                if found.isCurrent then
                    TRP3FW:Warn("Note: This is your current active profile!")
                    TRP3FW:Info("Consider using a different profile for ghost mode")
                end
            else
                TRP3FW:Warn("Profile not found: "..rest)
                TRP3FW:Info("Use '/trp3fw ghostprofile list' to see available profiles")
            end
        end

    elseif cmd == "cache" then
        local args = {}
        for word in rest:gmatch("%S+") do
            table.insert(args, word)
        end
        local cacheType = args[1]
        local secs = tonumber(args[2])

        -- SECURITY: Validate bounds to prevent resource exhaustion
        -- Maximum cache duration: 1 hour (3600s), minimum: 0 (disable)
        if not cacheType or not secs or secs < 0 or secs > 3600 then
            TRP3FW:Warn("Usage: /trp3fw cache <phase|phasefail|scan|scanfail|whozone|whoname|send|interaction> <seconds>")
            TRP3FW:Info("Valid range: 0-3600 seconds (0-60 minutes)")
            return
        end

        cacheType = cacheType:lower()

        if cacheType == "phase" then
            TRP3FW_Settings.phaseCacheDuration = secs
            TRP3FW:Info("Phase cache duration set to "..secs.." seconds")
        elseif cacheType == "phasefail" then
            TRP3FW_Settings.phaseCacheFailureDuration = secs
            TRP3FW:Info("Phase cache failure duration set to "..secs.." seconds")
        elseif cacheType == "scan" then
            TRP3FW_Settings.scanCacheDuration = secs
            TRP3FW:Info("Scan cache duration set to "..secs.." seconds")
        elseif cacheType == "scanfail" then
            TRP3FW_Settings.scanCacheFailureDuration = secs
            TRP3FW:Info("Scan failure cache duration set to "..secs.." seconds")
        elseif cacheType == "whozone" then
            TRP3FW_Settings.whoZoneCacheDuration = secs
            TRP3FW:Info("WHO zone cache duration set to "..secs.." seconds")
        elseif cacheType == "whoname" then
            TRP3FW_Settings.whoNameCacheDuration = secs
            TRP3FW:Info("WHO name cache duration set to "..secs.." seconds")
        elseif cacheType == "send" then
            TRP3FW_Settings.sendCacheDuration = secs
            TRP3FW:Info("Send cache duration set to "..secs.." seconds")
        elseif cacheType == "interaction" then
            TRP3FW_Settings.interactionCacheDuration = secs
            TRP3FW:Info("Interaction cache duration set to "..secs.." seconds")
        else
            TRP3FW:Warn("Usage: /trp3fw cache <phase|phasefail|scan|scanfail|whozone|whoname|send|interaction> <seconds>")
        end

    elseif cmd == "clearcache" then
        local args = {}
        for word in rest:gmatch("%S+") do
            table.insert(args, word)
        end
        local eventType = args[1]  -- "phase" or "zone"
        local cacheType = args[2]  -- "phasecheck", "broadcasts", "scans", "whozone", or "all"
        local value = args[3]      -- "on" or "off"

        if not eventType or eventType == "" then
            -- Show current status
            TRP3FW:Info("Cache clearing settings:")
            TRP3FW:Info("|cff00ccff=== Phase Change (SCENARIO_UPDATE) ===|r")
            TRP3FW:Info("  Master: "..(TRP3FW_Settings.clearCacheOnPhaseChange and "|cff00ff00On|r" or "|cffaaaaaaOff|r"))
            TRP3FW:Info("    Phase Check: "..(TRP3FW_Settings.clearPhaseCheckOnPhaseChange and "|cff00ff00On|r" or "|cffaaaaaaOff|r"))
            TRP3FW:Info("    Allowed Senders: "..(TRP3FW_Settings.clearAllowedSendersOnPhaseChange and "|cff00ff00On|r" or "|cffaaaaaaOff|r"))
            TRP3FW:Info("    Interaction: "..(TRP3FW_Settings.clearInteractionOnPhaseChange and "|cff00ff00On|r" or "|cffaaaaaaOff|r"))
            TRP3FW:Info("    Broadcasts: "..(TRP3FW_Settings.clearRecentBroadcastsOnPhaseChange and "|cff00ff00On|r" or "|cffaaaaaaOff|r"))
            TRP3FW:Info("    Scans: "..(TRP3FW_Settings.clearRecentScansOnPhaseChange and "|cff00ff00On|r" or "|cffaaaaaaOff|r"))
            TRP3FW:Info("    WHO Zone: "..(TRP3FW_Settings.clearWhoZoneOnPhaseChange and "|cff00ff00On|r" or "|cffaaaaaaOff|r"))
            TRP3FW:Info("    WHO Name: "..(TRP3FW_Settings.clearWhoNameOnPhaseChange and "|cff00ff00On|r" or "|cffaaaaaaOff|r"))
            TRP3FW:Info("|cff00ccff=== Zone Change (ZONE_CHANGED_NEW_AREA) ===|r")
            TRP3FW:Info("  Master: "..(TRP3FW_Settings.clearCacheOnZoneChange and "|cff00ff00On|r" or "|cffaaaaaaOff|r"))
            TRP3FW:Info("    Phase Check: "..(TRP3FW_Settings.clearPhaseCheckOnZoneChange and "|cff00ff00On|r" or "|cffaaaaaaOff|r"))
            TRP3FW:Info("    Allowed Senders: "..(TRP3FW_Settings.clearAllowedSendersOnZoneChange and "|cff00ff00On|r" or "|cffaaaaaaOff|r"))
            TRP3FW:Info("    Interaction: "..(TRP3FW_Settings.clearInteractionOnZoneChange and "|cff00ff00On|r" or "|cffaaaaaaOff|r"))
            TRP3FW:Info("    Broadcasts: "..(TRP3FW_Settings.clearRecentBroadcastsOnZoneChange and "|cff00ff00On|r" or "|cffaaaaaaOff|r"))
            TRP3FW:Info("    Scans: "..(TRP3FW_Settings.clearRecentScansOnZoneChange and "|cff00ff00On|r" or "|cffaaaaaaOff|r"))
            TRP3FW:Info("    WHO Zone: "..(TRP3FW_Settings.clearWhoZoneOnZoneChange and "|cff00ff00On|r" or "|cffaaaaaaOff|r"))
            TRP3FW:Info("    WHO Name: "..(TRP3FW_Settings.clearWhoNameOnZoneChange and "|cff00ff00On|r" or "|cffaaaaaaOff|r"))
            return
        end

        eventType = eventType:lower()

        -- Master toggle (no cache type specified)
        if not cacheType or cacheType == "" then
            if eventType == "phase" then
                if value and (value:lower() == "on" or value:lower() == "off") then
                    TRP3FW_Settings.clearCacheOnPhaseChange = (value:lower() == "on")
                else
                    TRP3FW_Settings.clearCacheOnPhaseChange = not TRP3FW_Settings.clearCacheOnPhaseChange
                end
                TRP3FW:Info("Clear cache on phase change "..(TRP3FW_Settings.clearCacheOnPhaseChange and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            elseif eventType == "zone" then
                if value and (value:lower() == "on" or value:lower() == "off") then
                    TRP3FW_Settings.clearCacheOnZoneChange = (value:lower() == "on")
                else
                    TRP3FW_Settings.clearCacheOnZoneChange = not TRP3FW_Settings.clearCacheOnZoneChange
                end
                TRP3FW:Info("Clear cache on zone change "..(TRP3FW_Settings.clearCacheOnZoneChange and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            else
                -- Check for manual clear command: /trp3fw clearcache <name>
                local validCaches = {
                    ["phasecheck"] = "phaseCheck",
                    ["allowed"] = "allowedSenders",
                    ["allowedsenders"] = "allowedSenders",
                    ["interaction"] = "interaction",
                    ["broadcasts"] = "broadcast",
                    ["scans"] = "mapScan",
                    ["whozone"] = "whoZone",
                    ["whoname"] = "whoName",
                    ["all"] = "all"
                }
                
                if validCaches[eventType] then
                    local target = validCaches[eventType]
                    if TRP3FW.CacheInterface then
                        if target == "all" then
                            for name, _ in pairs(TRP3FW.CacheInterface.caches) do
                                TRP3FW.CacheInterface:Clear(name)
                            end
                            TRP3FW:Info("Cleared ALL caches.")
                        else
                            TRP3FW.CacheInterface:Clear(target)
                            TRP3FW:Info("Cleared cache: "..target)
                        end
                    else
                        TRP3FW:Error("CacheInterface not loaded.")
                    end
                    return
                end

                TRP3FW:Warn("Usage: /trp3fw clearcache [phase|zone] [cache_type] [on|off]")
                TRP3FW:Info("OR: /trp3fw clearcache [cache_name] (to clear immediately)")
                TRP3FW:Info("cache_type: phasecheck, allowed, interaction, broadcasts, scans, whozone, whoname, all")
            end
            return
        end

        cacheType = cacheType:lower()

        -- Granular cache type controls
        if eventType == "phase" then
            local settingKey = nil
            local cacheName = nil

            if cacheType == "phasecheck" then
                settingKey = "clearPhaseCheckOnPhaseChange"
                cacheName = "Phase Check"
            elseif cacheType == "allowed" or cacheType == "allowedsenders" then
                settingKey = "clearAllowedSendersOnPhaseChange"
                cacheName = "Allowed Senders"
            elseif cacheType == "interaction" then
                settingKey = "clearInteractionOnPhaseChange"
                cacheName = "Interaction"
            elseif cacheType == "broadcasts" then
                settingKey = "clearRecentBroadcastsOnPhaseChange"
                cacheName = "Recent Broadcasts"
            elseif cacheType == "scans" then
                settingKey = "clearRecentScansOnPhaseChange"
                cacheName = "Recent Scans"
            elseif cacheType == "whozone" then
                settingKey = "clearWhoZoneOnPhaseChange"
                cacheName = "WHO Zone"
            elseif cacheType == "whoname" then
                settingKey = "clearWhoNameOnPhaseChange"
                cacheName = "WHO Name"
            elseif cacheType == "all" then
                -- Set all phase change granular settings
                local enabled = true
                if value and value:lower() == "off" then
                    enabled = false
                end
                TRP3FW_Settings.clearPhaseCheckOnPhaseChange = enabled
                TRP3FW_Settings.clearAllowedSendersOnPhaseChange = enabled
                TRP3FW_Settings.clearInteractionOnPhaseChange = enabled
                TRP3FW_Settings.clearRecentBroadcastsOnPhaseChange = enabled
                TRP3FW_Settings.clearRecentScansOnPhaseChange = enabled
                TRP3FW_Settings.clearWhoZoneOnPhaseChange = enabled
                TRP3FW_Settings.clearWhoNameOnPhaseChange = enabled
                TRP3FW:Info("All phase change cache clearing "..(enabled and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
                return
            else
                TRP3FW:Warn("Unknown cache type: "..cacheType)
                TRP3FW:Info("Valid types: phasecheck, allowed, interaction, broadcasts, scans, whozone, whoname, all")
                return
            end

            if settingKey then
                if value and (value:lower() == "on" or value:lower() == "off") then
                    TRP3FW_Settings[settingKey] = (value:lower() == "on")
                else
                    TRP3FW_Settings[settingKey] = not TRP3FW_Settings[settingKey]
                end
                TRP3FW:Info(cacheName.." cache clearing on phase change "..(TRP3FW_Settings[settingKey] and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            end

        elseif eventType == "zone" then
            local settingKey = nil
            local cacheName = nil

            if cacheType == "phasecheck" then
                settingKey = "clearPhaseCheckOnZoneChange"
                cacheName = "Phase Check"
            elseif cacheType == "allowed" or cacheType == "allowedsenders" then
                settingKey = "clearAllowedSendersOnZoneChange"
                cacheName = "Allowed Senders"
            elseif cacheType == "interaction" then
                settingKey = "clearInteractionOnZoneChange"
                cacheName = "Interaction"
            elseif cacheType == "broadcasts" then
                settingKey = "clearRecentBroadcastsOnZoneChange"
                cacheName = "Recent Broadcasts"
            elseif cacheType == "scans" then
                settingKey = "clearRecentScansOnZoneChange"
                cacheName = "Recent Scans"
            elseif cacheType == "whozone" then
                settingKey = "clearWhoZoneOnZoneChange"
                cacheName = "WHO Zone"
            elseif cacheType == "whoname" then
                settingKey = "clearWhoNameOnZoneChange"
                cacheName = "WHO Name"
            elseif cacheType == "all" then
                -- Set all zone change granular settings
                local enabled = true
                if value and value:lower() == "off" then
                    enabled = false
                end
                TRP3FW_Settings.clearPhaseCheckOnZoneChange = enabled
                TRP3FW_Settings.clearAllowedSendersOnZoneChange = enabled
                TRP3FW_Settings.clearInteractionOnZoneChange = enabled
                TRP3FW_Settings.clearRecentBroadcastsOnZoneChange = enabled
                TRP3FW_Settings.clearRecentScansOnZoneChange = enabled
                TRP3FW_Settings.clearWhoZoneOnZoneChange = enabled
                TRP3FW_Settings.clearWhoNameOnZoneChange = enabled
                TRP3FW:Info("All zone change cache clearing "..(enabled and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
                return
            else
                TRP3FW:Warn("Unknown cache type: "..cacheType)
                TRP3FW:Info("Valid types: phasecheck, allowed, interaction, broadcasts, scans, whozone, whoname, all")
                return
            end

            if settingKey then
                if value and (value:lower() == "on" or value:lower() == "off") then
                    TRP3FW_Settings[settingKey] = (value:lower() == "on")
                else
                    TRP3FW_Settings[settingKey] = not TRP3FW_Settings[settingKey]
                end
                TRP3FW:Info(cacheName.." cache clearing on zone change "..(TRP3FW_Settings[settingKey] and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            end
        else
            TRP3FW:Warn("Usage: /trp3fw clearcache [phase|zone] [cache_type] [on|off]")
            TRP3FW:Info("cache_type: phasecheck, allowed, interaction, broadcasts, scans, whozone, whoname, all")
        end

    elseif cmd == "cachesize" then
        local size = tonumber(rest)
        if size and size >= 100 and size <= 10000 then
            TRP3FW_Settings.cacheSizeLimit = size
            TRP3FW:Info("Cache size limit set to "..size.." entries")
            TRP3FW:Warn("Please /reload for this to take full effect on all caches")
        else
            TRP3FW:Warn("Usage: /trp3fw cachesize <number>")
            TRP3FW:Info("Current: "..(TRP3FW_Settings.cacheSizeLimit or 1000))
            TRP3FW:Info("Valid range: 100-10000")
        end

    elseif cmd == "validatednamescache" or cmd == "namecachettl" or cmd == "namecache" then
        local days = tonumber(rest)
        if days and days >= 1 and days <= 30 then
            local seconds = days * 86400
            TRP3FW_Settings.validatedNamesCacheDuration = seconds
            TRP3FW:Info("Validated names cache duration set to "..days.." days ("..seconds.." seconds)")
            TRP3FW:Info("Validated player names will be kept for "..days.." days before re-validation")
        else
            local currentSeconds = TRP3FW_Settings.validatedNamesCacheDuration or 604800
            local currentDays = math.floor(currentSeconds / 86400)
            TRP3FW:Warn("Usage: /trp3fw namecache <days>")
            TRP3FW:Info("Current: "..currentDays.." days ("..currentSeconds.." seconds)")
            TRP3FW:Info("Valid range: 1-30 days")
            TRP3FW:Info("Lower = fresher validation, Higher = better performance")
        end

    elseif cmd == "namecachelimit" or cmd == "validatednameslimit" then
        local limit = tonumber(rest)
        if limit and limit >= 500 and limit <= 10000 then
            TRP3FW_Settings.validatedNamesCacheLimit = limit
            TRP3FW:Info("Validated names cache size limit set to "..limit.." entries")
            TRP3FW:Info("Oldest entries will be pruned when cache exceeds this size")
        else
            local currentLimit = TRP3FW_Settings.validatedNamesCacheLimit or 5000
            TRP3FW:Warn("Usage: /trp3fw namecachelimit <entries>")
            TRP3FW:Info("Current: "..currentLimit.." entries")
            TRP3FW:Info("Valid range: 500-10000 entries")
            TRP3FW:Info("Higher = better performance, Lower = less SavedVariables bloat")
        end

    elseif cmd == "whozonecooldown" or cmd == "zonecooldown" then
        local secs = tonumber(rest)
        if secs and secs >= 0 and secs <= 120 then
            TRP3FW_Settings.whoZoneQueryCooldown = secs
            TRP3FW:Info("WHO zone query cooldown set to "..secs.." seconds")
            if secs == 0 then
                TRP3FW:Warn("Cooldown disabled - zone queries will fire on every request!")
            end
        else
            TRP3FW:Warn("Usage: /trp3fw whozonecooldown <seconds>")
            TRP3FW:Info("Current: "..tostring(TRP3FW_Settings.whoZoneQueryCooldown or 20).." seconds")
            TRP3FW:Info("Valid range: 0-120 seconds (0 = no cooldown, default = 20)")
        end

    elseif cmd == "nameplaterange" or cmd == "nameplate" then
        TRP3FW:Warn("Nameplate range configuration has been removed.")
        TRP3FW:Info("TRP3FW no longer manages nameplate distance.")

    elseif cmd == "phasedelay" or cmd == "phasein" then
        local seconds = tonumber(rest)
        if seconds and seconds >= 0 and seconds <= 10 then
            local original = seconds
            if seconds < 3 and seconds ~= 0 then
                TRP3FW:Warn("Phase-in delay values below 3 seconds are treated as 0 (no delay).")
                seconds = 0
            end
            TRP3FW_Settings.phaseInDelay = seconds
            TRP3FW:Info("Phase-in delay set to "..seconds.." seconds")
            if seconds == 0 then
                TRP3FW:Warn("Delay disabled - may get false alerts during zone changes")
            end
        else
            local current = TRP3FW_Settings.phaseInDelay or 4
            TRP3FW:Warn("Usage: /trp3fw phasedelay <seconds>")
            TRP3FW:Info("Current: "..current.." seconds")
            TRP3FW:Info("Valid range: 0-10 seconds (0 = disabled, default = 4)")
        end

    elseif cmd == "prepopulate" then
        local arg = rest:lower()
        if arg == "who" then
            local current = TRP3FW_Settings.prepopulateWhoCache ~= false
            local newValue = not current
            TRP3FW_Settings.prepopulateWhoCache = newValue
            if newValue then
                TRP3FW:Info("WHO cache prepopulation |cff00ff00enabled|r - will warm up automatically after zone/phase changes.")
            else
                TRP3FW:Info("WHO cache prepopulation |cffaaaaaadisabled|r - cache will only update when requests arrive.")
            end
        elseif arg == "phase" then
            TRP3FW:Warn("Phase cache prepopulation has been removed. Phase checks now rely on on-demand targeting only.")
        else
            TRP3FW:Warn("Usage: /trp3fw prepopulate who")
            local whoState = TRP3FW_Settings.prepopulateWhoCache ~= false and "ENABLED" or "DISABLED"
            local whoPhaseState = TRP3FW_Settings.prepopulateWhoOnPhase ~= false and "ON" or "OFF"
            local whoZoneState = TRP3FW_Settings.prepopulateWhoOnZone ~= false and "ON" or "OFF"
            TRP3FW:Info("Current WHO prepopulation: "..whoState.." (phase: "..whoPhaseState..", zone: "..whoZoneState..")")
        end

	elseif cmd == "suppresswho" or cmd == "who" then
        if cmd == "who" then
            TRP3FW:Warn("WHO query toggle is no longer configurable; this command now toggles WHO output suppression (use /trp3fw suppresswho).")
        end
        TRP3FW_Settings.suppressAllWhoOutput = not TRP3FW_Settings.suppressAllWhoOutput
        if TRP3FW_Settings.suppressAllWhoOutput then
            TRP3FW:Info("WHO output suppression: |cff00ff00ENABLED|r - all WHO results will be hidden")
        else
            TRP3FW:Info("WHO output suppression: |cffaaaaaaDISABLED|r - only TRP3FW queries will be hidden")
        end

    elseif cmd == "addons" or cmd == "addon" then
        local arg = rest:lower()
        if arg == "" then
            -- Show current addon monitoring status
            TRP3FW:Info("Detected add-ons: "..TRP3FW:GetDetectedAddonsString())
            TRP3FW:Info(string.format("TotalRP3: %s %s", TRP3FW_Settings.monitorTRP3 and "|cff00ff00On|r" or "|cffaaaaaaOff|r", TRP3FW.detectedAddons.TRP3 and "|cff00ff00(Detected)|r" or "|cffff0000(Not Found)|r"))
            TRP3FW:Info(string.format("MyRolePlay: %s %s", TRP3FW_Settings.monitorMRP and "|cff00ff00On|r" or "|cffaaaaaaOff|r", TRP3FW.detectedAddons.MRP and "|cff00ff00(Detected)|r" or "|cffff0000(Not Found)|r"))
            TRP3FW:Info(string.format("XRP: %s %s", TRP3FW_Settings.monitorXRP and "|cff00ff00On|r" or "|cffaaaaaaOff|r", TRP3FW.detectedAddons.XRP and "|cff00ff00(Detected)|r" or "|cffff0000(Not Found)|r"))
            TRP3FW:Info(string.format("MSP (Other): %s %s", TRP3FW_Settings.monitorMSP and "|cff00ff00On|r" or "|cffaaaaaaOff|r", TRP3FW.detectedAddons.MSP and "|cff00ff00(Detected)|r" or "|cffff0000(Not Found)|r"))
        else
            if arg == "trp3" then
                TRP3FW_Settings.monitorTRP3 = not TRP3FW_Settings.monitorTRP3
                TRP3FW:Info("TotalRP3 monitoring "..(TRP3FW_Settings.monitorTRP3 and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            elseif arg == "mrp" or arg == "myroleplay" then
                TRP3FW_Settings.monitorMRP = not TRP3FW_Settings.monitorMRP
                TRP3FW:Info("MyRolePlay monitoring "..(TRP3FW_Settings.monitorMRP and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            elseif arg == "xrp" then
                TRP3FW_Settings.monitorXRP = not TRP3FW_Settings.monitorXRP
                TRP3FW:Info("XRP monitoring "..(TRP3FW_Settings.monitorXRP and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            elseif arg == "msp" then
                TRP3FW_Settings.monitorMSP = not TRP3FW_Settings.monitorMSP
                TRP3FW:Info("Generic MSP monitoring "..(TRP3FW_Settings.monitorMSP and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            else
                TRP3FW:Warn("Usage: /trp3fw addons [trp3|mrp|xrp|msp]")
            end
        end

    elseif cmd == "filter" then
        local filter = rest:lower()
        if filter == "gradient" or filter == "gradients" then
            TRP3FW_Settings.filterGradients = not TRP3FW_Settings.filterGradients
            TRP3FW:Info("Gradient filter "..(TRP3FW_Settings.filterGradients and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            if TRP3FW_Settings.filterGradients then
                TRP3FW:Info("Color gradients will be stripped from incoming profiles")
                TRP3FW:Warn("Please /reload for gradient filter to take effect")
            else
                TRP3FW:Info("Color gradients will be displayed normally")
                TRP3FW:Warn("Please /reload to disable gradient filter")
            end
        elseif filter == "fontsize" or filter == "font" then
            TRP3FW_Settings.filterMinimumFontSize = not TRP3FW_Settings.filterMinimumFontSize
            TRP3FW:Info("Minimum font size filter "..(TRP3FW_Settings.filterMinimumFontSize and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            if TRP3FW_Settings.filterMinimumFontSize then
                TRP3FW:Info("Minimum font size ({" .. (TRP3FW_Settings.minimumFontSizeLevel or "h3") .. "}) will be injected into incoming profiles")
            else
                TRP3FW:Info("Font sizes will be displayed as-is")
            end
        elseif filter == "icon" or filter == "icons" then
            TRP3FW_Settings.filterIcons = not TRP3FW_Settings.filterIcons
            TRP3FW:Info("Icon filter "..(TRP3FW_Settings.filterIcons and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            if TRP3FW_Settings.filterIcons then
                TRP3FW:Info("Icons will be stripped from incoming profiles")
                TRP3FW:Warn("Please /reload for icon filter to take effect")
            else
                TRP3FW:Info("Icons will be displayed normally")
                TRP3FW:Warn("Please /reload to disable icon filter")
            end
        else
            TRP3FW:Warn("Usage: /trp3fw filter [gradient|fontsize|icon]")
        end

    elseif cmd == "fontsize" then
        local arg = rest:lower()
        if arg == "" then
            -- Show status
            TRP3FW:Info("Minimum font size filter: "..(TRP3FW_Settings.filterMinimumFontSize and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
            TRP3FW:Info("  Current level: |cff00ccff" .. (TRP3FW_Settings.minimumFontSizeLevel or "h3") .. "|r")
        elseif arg == "on" or arg == "enable" then
            TRP3FW_Settings.filterMinimumFontSize = true
            TRP3FW:Info("Minimum font size filter |cff00ff00enabled|r - will apply to newly viewed profiles")
        elseif arg == "off" or arg == "disable" then
            TRP3FW_Settings.filterMinimumFontSize = false
            TRP3FW:Info("Minimum font size filter |cffaaaaaadisabled|r")
        elseif arg == "h1" or arg == "h2" or arg == "h3" or arg == "p" then
            TRP3FW_Settings.minimumFontSizeLevel = arg
            TRP3FW:Info("Minimum font size level set to: |cff00ccff" .. arg .. "|r")
            if not TRP3FW_Settings.filterMinimumFontSize then
                TRP3FW:Info("Note: Filter is currently disabled. Use '/trp3fw fontsize on' to enable.")
            end
        else
            TRP3FW:Warn("Usage: /trp3fw fontsize [on|off|h1|h2|h3|p]")
            TRP3FW:Info("  on/off - Enable or disable the filter")
            TRP3FW:Info("  h1/h2/h3/p - Set the font size level (h1=largest, p=normal)")
        end

    elseif cmd == "debug" then
        TRP3FW_Settings.debug = not TRP3FW_Settings.debug
        TRP3FW:Info("Debug mode "..(TRP3FW_Settings.debug and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))

    elseif cmd == "spvpdebug" then
        if not TRP3FW.hasEpsilonAPI then
            TRP3FW:Error("Epsilon API not available.")
            return
        end

        local phaseID = TRP3FW:GetCurrentPhaseID() or "Unknown"
        local salt = C_Epsilon.GetPhaseAddonData("TRP3FW_SPVP_KEY")
        local isTicket = salt and #salt < 32
        
        local cachedSalt = "None"
        local timestamp = "None"
        
        if TRP3FW.CacheInterface then
            local cached = TRP3FW.CacheInterface:Get("spvpPhaseSalt", phaseID)
            if cached then
                cachedSalt = cached.salt or "Empty"
                if cached.timestamp then
                    timestamp = string.format("%.1fs ago", TRP3FW:GetCurrentTime() - cached.timestamp)
                end
            end
        end

        local transitionTime = "None"
        if TRP3FW.lastPhaseChangeTime then
            transitionTime = string.format("%.1fs ago", TRP3FW:GetCurrentTime() - TRP3FW.lastPhaseChangeTime)
        end

        local isOwner = C_Epsilon.IsOwner and C_Epsilon.IsOwner()
        local isOfficer = C_Epsilon.IsOfficer and C_Epsilon.IsOfficer()
        
        -- Check for Ticket ID correlation
        local ticketID = "Unknown"
        local saltMatchesTicket = false
        if C_Epsilon.GetPhaseTicket then
            ticketID = C_Epsilon.GetPhaseTicket() or "Nil"
            if ticketID ~= "Nil" and salt == ticketID then
                saltMatchesTicket = true
            end
        end

        TRP3FW:Info("=== SPVP Debug Info ===")
        TRP3FW:Info("Current Phase ID: " .. tostring(phaseID))
        TRP3FW:Info("Ticket ID: " .. tostring(ticketID))
        TRP3FW:Info("SPVP Mode: " .. (TRP3FW_Settings.spvpMode or "off"))
        TRP3FW:Info("Player Status: " .. (isOwner and "|cff00ff00Owner|r" or (isOfficer and "|cff00ff00Officer|r" or "|cffaaaaaaMember|r")))
        TRP3FW:Info("Auto-Init Setting: " .. (TRP3FW_Settings.spvpAutoInitialize and "|cff00ff00ENABLED|r" or "|cffaaaaaaDISABLED|r"))
        
        local apiStatus = "Nil"
        if salt then
            if salt == "" then apiStatus = "Empty String"
            elseif isTicket then apiStatus = "|cffffff00Ticket ID (Async Fetch)|r (Preview: "..salt..")"
            else apiStatus = "Present (Len: "..#salt..", Preview: "..salt:sub(1,8).."...)"
            end
        end
        TRP3FW:Info("API Salt: " .. apiStatus)
        
        if saltMatchesTicket then
            TRP3FW:Info("|cffff0000WARNING: API Salt matches Phase Ticket ID! This is insecure/default behavior.|r")
        end
        TRP3FW:Info("Cached Salt: " .. (cachedSalt == "Empty" and "Empty String" or (cachedSalt == "None" and "None" or "Present (Preview: "..cachedSalt:sub(1,8).."...)")))
        TRP3FW:Info("Cache Age: " .. timestamp)
        TRP3FW:Info("Time Since Phase Change: " .. transitionTime)
        
        if isTicket then
            TRP3FW:Info("Salt Mismatch: |cff888888N/A (Async Wait)|r")
        else
            local apiVal = (salt == "" or salt == nil) and nil or salt
            local cacheVal = (cachedSalt == "None" or cachedSalt == "Empty") and nil or cachedSalt
            TRP3FW:Info("Salt Mismatch: " .. ((apiVal ~= cacheVal) and "|cffff0000YES|r" or "|cff00ff00NO|r"))
        end

    elseif cmd == "dumpcache" or cmd == "dumpcaches" then
        local CI = TRP3FW.CacheInterface
        if not CI then
            TRP3FW:Error("CacheInterface not loaded.")
            return
        end

        local function formatValue(v)
            if type(v) ~= "table" then
                return tostring(v)
            end
            local parts = {}
            if v.mapID then table.insert(parts, "mapID="..tostring(v.mapID)) end
            if v.zone then table.insert(parts, "zone="..tostring(v.zone)) end
            if v.inPhase ~= nil then table.insert(parts, "inPhase="..tostring(v.inPhase)) end
            if v.found ~= nil then table.insert(parts, "found="..tostring(v.found)) end
            if v.reason then table.insert(parts, "reason="..tostring(v.reason)) end
            return #parts > 0 and table.concat(parts, ", ") or "table"
        end

        local args = {}
        for word in rest:gmatch("%S+") do table.insert(args, word) end
        local target = args[1] and args[1]:lower() or ""
        local limit = tonumber(args[2]) or 15
        if limit < 1 then limit = 1 elseif limit > 100 then limit = 100 end

        local function dump(name)
            local cache = CI.caches[name]
            if not cache then
                TRP3FW:Warn("Cache not found: "..tostring(name))
                return
            end
            TRP3FW:Info(string.format("Cache '%s': size=%d hits=%d misses=%d ttl=%s", name, cache.size or 0, (cache.stats and cache.stats.hits) or 0, (cache.stats and cache.stats.misses) or 0, tostring(cache.options and cache.options.ttl)))
            local shown = 0
            for key, value in CI:Iterator(name) do
                if shown >= limit then break end
                local age
                if type(value) == "table" and value.timestamp then
                    age = TRP3FW:GetCurrentTime() - value.timestamp
                end
                local ageStr = age and string.format("%.1fs", age) or "n/a"
                TRP3FW:Info(string.format("  %s | age=%s | %s", tostring(key), ageStr, formatValue(value)))
                shown = shown + 1
            end
            if shown == 0 then
                TRP3FW:Info("  (empty)")
            end
        end

        if target ~= "" then
            dump(target)
        else
            for name, _ in pairs(CI.caches) do
                dump(name)
            end
        end

    elseif cmd == "debugtime" or cmd == "debugtimestamp" then
        TRP3FW_Settings.debugTimestamp = not TRP3FW_Settings.debugTimestamp
        TRP3FW:Info("Debug timestamps "..(TRP3FW_Settings.debugTimestamp and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))

    elseif cmd == "debugwindow" or cmd == "debugwin" then
        if TRP3FW.ToggleDebugWindow then
            TRP3FW:ToggleDebugWindow()
            TRP3FW:Info("Debug window "..(TRP3FW.debugWindow:IsShown() and "|cff00ff00shown|r" or "|cffaaaaaahidden|r"))
        else
            TRP3FW:Warn("Debug window not loaded yet. Try after a /reload")
        end

    elseif cmd == "debugfilter" then
        local filter = rest:lower()
        if filter == "channel" then
            TRP3FW_Settings.debugChannel = not TRP3FW_Settings.debugChannel
            TRP3FW:Info("Channel debug messages "..(TRP3FW_Settings.debugChannel and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif filter == "whisper" then
            TRP3FW_Settings.debugWhisper = not TRP3FW_Settings.debugWhisper
            TRP3FW:Info("Whisper debug messages "..(TRP3FW_Settings.debugWhisper and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif filter == "who" then
            TRP3FW_Settings.debugWho = not TRP3FW_Settings.debugWho
            TRP3FW:Info("WHO query debug messages "..(TRP3FW_Settings.debugWho and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif filter == "phase" then
            TRP3FW_Settings.debugPhase = not TRP3FW_Settings.debugPhase
            TRP3FW:Info("Phase check debug messages "..(TRP3FW_Settings.debugPhase and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif filter == "location" then
            TRP3FW_Settings.debugLocation = not TRP3FW_Settings.debugLocation
            TRP3FW:Info("Location check debug messages "..(TRP3FW_Settings.debugLocation and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif filter == "decision" then
            TRP3FW_Settings.debugDecision = not TRP3FW_Settings.debugDecision
            TRP3FW:Info("Decision logic debug messages "..(TRP3FW_Settings.debugDecision and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif filter == "hooks" then
            TRP3FW_Settings.debugHooks = not TRP3FW_Settings.debugHooks
            TRP3FW:Info("Hook debug messages "..(TRP3FW_Settings.debugHooks and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif filter == "cache" then
            TRP3FW_Settings.debugCache = not TRP3FW_Settings.debugCache
            TRP3FW:Info("Cache debug messages "..(TRP3FW_Settings.debugCache and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif filter == "send" then
            TRP3FW_Settings.debugSend = not TRP3FW_Settings.debugSend
            TRP3FW:Info("Send cache debug messages "..(TRP3FW_Settings.debugSend and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif filter == "ui" then
            TRP3FW_Settings.debugUI = not TRP3FW_Settings.debugUI
            TRP3FW:Info("UI debug messages "..(TRP3FW_Settings.debugUI and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif filter == "utils" then
            TRP3FW_Settings.debugUtils = not TRP3FW_Settings.debugUtils
            TRP3FW:Info("Utility debug messages "..(TRP3FW_Settings.debugUtils and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif filter == "cleanname" then
            TRP3FW_Settings.debugCleanName = not TRP3FW_Settings.debugCleanName
            TRP3FW:Info("CleanPlayerName debug messages "..(TRP3FW_Settings.debugCleanName and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        elseif filter == "security" then
            TRP3FW_Settings.debugSecurity = not TRP3FW_Settings.debugSecurity
            TRP3FW:Info("Security debug messages "..(TRP3FW_Settings.debugSecurity and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        else
            TRP3FW:Warn("Usage: /trp3fw debugfilter <channel | whisper | who | phase | location | decision | hooks | cache | send | ui | utils | cleanname | security>")
            TRP3FW:Info("Current filters:")
            TRP3FW:Info("  channel="..(TRP3FW_Settings.debugChannel and "ON" or "OFF")..", whisper="..(TRP3FW_Settings.debugWhisper and "ON" or "OFF")..", who="..(TRP3FW_Settings.debugWho and "ON" or "OFF")..", phase="..(TRP3FW_Settings.debugPhase and "ON" or "OFF"))
            TRP3FW:Info("  location="..(TRP3FW_Settings.debugLocation and "ON" or "OFF")..", decision="..(TRP3FW_Settings.debugDecision and "ON" or "OFF")..", hooks="..(TRP3FW_Settings.debugHooks and "ON" or "OFF"))
            TRP3FW:Info("  cache="..(TRP3FW_Settings.debugCache and "ON" or "OFF")..", send="..(TRP3FW_Settings.debugSend and "ON" or "OFF")..", ui="..(TRP3FW_Settings.debugUI and "ON" or "OFF")..", utils="..(TRP3FW_Settings.debugUtils and "ON" or "OFF")..", cleanname="..(TRP3FW_Settings.debugCleanName and "ON" or "OFF"))
            TRP3FW:Info("  security="..(TRP3FW_Settings.debugSecurity and "ON" or "OFF"))
        end

    elseif cmd == "reloadhooks" or cmd == "reinstall" then
        TRP3FW.hookInstalled = false
        TRP3FW:Info("Reinstalling hooks...")
        TRP3FW:InstallHooks()
        TRP3FW:Info("Hooks reinstalled")

    elseif cmd == "minimap" then
        TRP3FW:ToggleMinimapButton()

    elseif cmd == "reset" then
        TRP3FW_Settings = {}
        TRP3FW:InitializeSettings()
        TRP3FW:Info("|cff00ff00All settings reset to defaults!|r")
        TRP3FW:Info("Use '/trp3fw status' to see current settings")

    elseif cmd == "profile" or cmd == "profiler" then
        local arg = rest:lower()
        if arg == "" or arg == "status" then
            -- Show profiler status
            TRP3FW:Info("Profiler: "..(TRP3FW.profiler.enabled and "|cff00ff00Enabled|r" or "|cffaaaaaaDisabled|r"))
            if TRP3FW.profiler.enabled then
                local count = 0
                for _ in pairs(TRP3FW.profiler.stats) do
                    count = count + 1
                end
                TRP3FW:Info("Functions profiled: "..count)
                TRP3FW:Info("Use '/trp3fw profile report' to see detailed statistics")
            else
                TRP3FW:Info("Use '/trp3fw profile on' to enable profiling")
            end
        elseif arg == "on" or arg == "enable" then
            TRP3FW.profiler.toggle(true)
        elseif arg == "off" or arg == "disable" then
            TRP3FW.profiler.toggle(false)
        elseif arg == "report" or arg == "show" then
            TRP3FW.profiler.report()
        elseif arg == "reset" or arg == "clear" then
            TRP3FW.profiler.reset()
        else
            TRP3FW:Warn("Usage: /trp3fw profile [on|off|report|reset|status]")
            TRP3FW:Info("  on     - Enable performance profiling")
            TRP3FW:Info("  off    - Disable performance profiling")
            TRP3FW:Info("  report - Show profiling statistics")
            TRP3FW:Info("  reset  - Clear profiling data")
            TRP3FW:Info("  status - Show profiler status")
        end

    -- Phase Check Command - Scan zone for players in same phase
    elseif cmd == "phasecheck" then
        -- Duplicate prevention
        if TRP3FW.phaseCheckInProgress then
            TRP3FW:Error("Phase check already in progress. Please wait.")
            return
        end

        -- Check Epsilon API availability
        if not TRP3FW.hasEpsilonAPI then
            TRP3FW:Error("Phase check requires Epsilon API (not available on this server)")
            return
        end

        -- Parse verbose flag
        local verbose = (rest and rest:match("verbose"))

        -- Get current zone name
        local zone = TRP3FW.currentZoneName or GetRealZoneText()
        if not zone or zone == "" then
            TRP3FW:Error("Cannot determine current zone")
            return
        end

        TRP3FW:Info("Starting phase check for zone: " .. zone)

        -- Token awareness warning
        if TRP3FW.pendingPhaseChecks and #TRP3FW.pendingPhaseChecks > 20 then
            TRP3FW:Warn("Phase check queue is busy. This may take longer than usual.")
        end

        TRP3FW.phaseCheckInProgress = true

        TRP3FW:ScanZoneForPlayers(function(success, players, err)
            if not success then
                TRP3FW:Error("Zone scan failed: " .. tostring(err))
                TRP3FW.phaseCheckInProgress = false
                return
            end

            local total = #players
            if total == 0 then
                TRP3FW:Info("No other players found in zone.")
                TRP3FW.phaseCheckInProgress = false
                return
            end

            TRP3FW:Info("Found " .. total .. " players. Checking phases...")

            local passed = 0
            local checked = 0
            local uniqueMaps = {}

            for _, name in ipairs(players) do
                TRP3FW:CheckPlayerPhase(name, nil, function(inPhase, reason, mapID)
                    checked = checked + 1

                    if inPhase then
                        passed = passed + 1
                        if mapID then
                            uniqueMaps[mapID] = true
                        end
                        if verbose then
                            TRP3FW:Info("|cff00ff00✓|r " .. name)
                        end
                    end

                    -- Progress indicator every 10 players
                    if checked % 10 == 0 and checked < total then
                        TRP3FW:Info("Progress: " .. checked .. "/" .. total .. " checked...")
                    end

                    -- Final summary
                    if checked >= total then
                        local mapCount = 0
                        for _ in pairs(uniqueMaps) do
                            mapCount = mapCount + 1
                        end

                        TRP3FW:Info("Phase check complete. " .. passed .. "/" .. total ..
                                    " in phase. (Maps: " .. mapCount .. ")")
                        TRP3FW.phaseCheckInProgress = false
                    end
                end, "LOW") -- Use LOW priority to avoid blocking active RP
            end
        end)

    -- Batch Phase Check Configuration
    elseif cmd == "batch" then
        local subcommand = args[1]

        if subcommand == "enable" then
            TRP3FW_Settings.phaseCheckBatchMode = true
            TRP3FW:Success("Batch phase check processing enabled")
        elseif subcommand == "disable" then
            TRP3FW_Settings.phaseCheckBatchMode = false
            TRP3FW:Warn("Batch phase check processing disabled")
        elseif subcommand == "size" then
            local value = tonumber(args[2])
            if not value then
                TRP3FW:Info("Current batch size: " .. (TRP3FW_Settings.phaseCheckBatchSize or 5))
                TRP3FW:Info("Usage: /trp3fw batch size <2-10>")
                return
            end
            value = math.max(2, math.min(10, math.floor(value)))
            TRP3FW_Settings.phaseCheckBatchSize = value
            TRP3FW:Info("Batch size set to: " .. value)
        elseif subcommand == "delay" then
            local value = tonumber(args[2])
            if not value then
                TRP3FW:Info("Current batch delay: " .. string.format("%.1fs", TRP3FW_Settings.phaseCheckBatchDelay or 1.0))
                TRP3FW:Info("Usage: /trp3fw batch delay <0.1-2.0>")
                return
            end
            value = math.max(0.1, math.min(2.0, value))
            value = math.floor(value * 10 + 0.5) / 10
            TRP3FW_Settings.phaseCheckBatchDelay = value
            TRP3FW:Info("Batch accumulation delay set to: " .. string.format("%.1fs", value))
        elseif subcommand == "min" then
            local value = tonumber(args[2])
            if not value then
                TRP3FW:Info("Current minimum batch size: " .. (TRP3FW_Settings.phaseCheckBatchMinSize or 3))
                TRP3FW:Info("Usage: /trp3fw batch min <2-10>")
                return
            end
            value = math.max(2, math.min(10, math.floor(value)))
            TRP3FW_Settings.phaseCheckBatchMinSize = value
            TRP3FW:Info("Minimum batch size set to: " .. value)
       elseif subcommand == "interdelay" then
           local value = tonumber(args[2])
           if not value then
               self:Info("Current inter-target delay: " .. string.format("%dms", (TRP3FW_Settings.phaseCheckInterTargetDelay or 0.1) * 1000))
               self:Info("Usage: /trp3fw batch interdelay <10-200> (milliseconds)")
               return
           end

           -- Convert ms to seconds
           value = value / 1000
           value = math.max(0.01, math.min(0.2, value)) -- Lower bound changed to 0.01
           value = math.floor(value * 100 + 0.5) / 100  -- Round to 0.01
           TRP3FW_Settings.phaseCheckInterTargetDelay = value
           self:Info("Inter-target delay set to: " .. string.format("%dms", value * 1000))
        elseif subcommand == "status" or not subcommand then
            local enabled = TRP3FW_Settings.phaseCheckBatchMode
            TRP3FW:Info("=== Batch Phase Check Configuration ===")
            TRP3FW:Info("Status: " .. (enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"))
            TRP3FW:Info("Max batch size: " .. (TRP3FW_Settings.phaseCheckBatchSize or 5))
            TRP3FW:Info("Accumulation delay: " .. string.format("%.1fs", TRP3FW_Settings.phaseCheckBatchDelay or 1.0))
            TRP3FW:Info("Minimum batch size: " .. (TRP3FW_Settings.phaseCheckBatchMinSize or 3))
            TRP3FW:Info("Inter-target delay: " .. string.format("%dms", (TRP3FW_Settings.phaseCheckInterTargetDelay or 0.1) * 1000))
        else
            TRP3FW:Info("Usage: /trp3fw batch [enable|disable|size|delay|min|interdelay|status]")
        end

    -- Priority System Configuration
    elseif cmd == "priority" then
        local subcommand = args[1]
        
        if subcommand == "reserved" then
            local value = tonumber(args[2])
            if not value then
                TRP3FW:Info("Reserved tokens: " .. (TRP3FW_Settings.privilegedReservedTokens or 2) .. "/10")
                TRP3FW:Info("Usage: /trp3fw priority reserved <0-5>")
                return
            end
            value = math.max(0, math.min(5, math.floor(value)))
            TRP3FW_Settings.privilegedReservedTokens = value
            TRP3FW:Info("Reserved tokens set to: " .. value)
            if TRP3FW.UpdateValidatedPrioritySettings then TRP3FW:UpdateValidatedPrioritySettings() end
        elseif subcommand == "low" then
            local value = tonumber(args[2])
            if not value then
                TRP3FW:Info("LOW priority threshold: " .. (TRP3FW_Settings.privilegedLowPriorityThreshold or 4))
                TRP3FW:Info("Usage: /trp3fw priority low <2-8>")
                return
            end
            value = math.max(2, math.min(8, math.floor(value)))
            TRP3FW_Settings.privilegedLowPriorityThreshold = value
            TRP3FW:Info("LOW priority threshold set to: " .. value)
            if TRP3FW.UpdateValidatedPrioritySettings then TRP3FW:UpdateValidatedPrioritySettings() end
        elseif subcommand == "status" or not subcommand then
            local reserved = TRP3FW_Settings.privilegedReservedTokens or 2
            local lowThreshold = TRP3FW_Settings.privilegedLowPriorityThreshold or 4
            TRP3FW:Info("=== Priority System Configuration ===")
            TRP3FW:Info("Reserved tokens (HIGH): " .. reserved .. "/10")
            TRP3FW:Info("LOW priority threshold: " .. lowThreshold .. " tokens")
            if TRP3FW.privilegedRate then
                local tokens = math.floor(TRP3FW.privilegedRate.tokens * 10) / 10
                local color = tokens >= 7 and "00ff00" or (tokens >= 4 and "ffff00" or "ff0000")
                TRP3FW:Info("Current bucket: |cff"..color..tokens.."/10|r")
            end
        else
            TRP3FW:Info("Usage: /trp3fw priority [reserved|low|status]")
        end

    -- Token Refund Configuration
    elseif cmd == "refund" then
        local subcommand = args[1]
        if subcommand == "enable" then
            TRP3FW_Settings.phaseCheckRefundOnNoChange = true
            TRP3FW:Warn("Token refund enabled. |cffff0000SECURITY WARNING:|r Potential abuse throughput doubled.")
        elseif subcommand == "disable" then
            TRP3FW_Settings.phaseCheckRefundOnNoChange = false
            TRP3FW:Success("Token refund disabled (Recommended).")
        elseif subcommand == "status" or not subcommand then
            local enabled = TRP3FW_Settings.phaseCheckRefundOnNoChange
            TRP3FW:Info("=== Token Refund Configuration ===")
            TRP3FW:Info("Status: " .. (enabled and "|cffffaa00Enabled (SECURITY RISK)|r" or "|cff00ff00Disabled (Safe)|r"))
            if TRP3FW.privilegedCallStats and TRP3FW.privilegedCallStats.refunded then
                TRP3FW:Info("Total refunds this session: " .. TRP3FW.privilegedCallStats.refunded)
            end
        else
            TRP3FW:Info("Usage: /trp3fw refund [enable|disable|status]")
        end

    -- Token Bucket Debug
    elseif cmd == "tokens" then
        if TRP3FW.privilegedRate then
            local tokens = TRP3FW.privilegedRate.tokens or 0
            local lastRefill = TRP3FW.privilegedRate.lastRefill or 0
            local now = TRP3FW:GetCurrentTime()
            local elapsed = now - lastRefill
            -- Calculate current (visual only, logic updates on access)
            local current = math.min(10, tokens + (elapsed * 10))
            local color = current >= 7 and "00ff00" or (current >= 4 and "ffff00" or "ff0000")
            TRP3FW:Info(string.format("Token Bucket: |cff%s%.2f / 10|r", color, current))
            TRP3FW:Info(string.format("  Stored: %.2f", tokens))
            TRP3FW:Info(string.format("  Time since update: %.3fs", elapsed))
        else
            TRP3FW:Warn("Token bucket not initialized yet.")
        end

    -- Memory Usage Debug
    elseif cmd == "memory" or cmd == "mem" then
        UpdateAddOnMemoryUsage()
        local kb = GetAddOnMemoryUsage("TRP3FW")
        if kb > 1024 then
            TRP3FW:Info(string.format("Memory Usage: |cff00ff00%.2f MB|r", kb / 1024))
        else
            TRP3FW:Info(string.format("Memory Usage: |cff00ff00%.0f KB|r", kb))
        end

    elseif cmd == "reset" then
        TRP3FW_Settings = {}
        TRP3FW:InitializeSettings()
        TRP3FW:Info("|cff00ff00All settings reset to defaults!|r")
        TRP3FW:Info("Use '/trp3fw status' to see current settings")

    else
        TRP3FW:Warn("Unknown command. Use '/trp3fw help' for options.")
    end
end
