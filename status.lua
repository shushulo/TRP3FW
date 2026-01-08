-- status.lua
-- Status display and help text

local addonName, TRP3FW = ...

-- Note: Helper formatting functions (EnabledDisabled, OnOff, GetDetectedAddonsString) are in core/utils.lua

function TRP3FW:ShowStats()
    print("|cffaaaaaa━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
    print("|cff00ffffTRP3 Firewall v"..self.VERSION.." - Session Statistics|r")
    print("|cffaaaaaa━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")

    -- Session stats
    local alertsShown = (self.sessionStats.phaseAlerts or 0) + (self.sessionStats.mapAlerts or 0)
    local blocksTotal = (self.sessionStats.phaseBlocks or 0) + (self.sessionStats.mapBlocks or 0) + (self.sessionStats.startPhaseBlocks or 0)
    local ghostsTotal = (self.sessionStats.phaseGhost or 0) + (self.sessionStats.mapGhost or 0) + (self.sessionStats.startPhaseGhost or 0)

    print("|cff00ccffAlerts Shown:|r |cffffff00"..alertsShown.."|r")
    print("  Phase alerts: |cffffff00"..(self.sessionStats.phaseAlerts or 0).."|r")
    print("  Map alerts: |cffffff00"..(self.sessionStats.mapAlerts or 0).."|r")

    print("|cff00ccffBlocks:|r |cffff0000"..blocksTotal.."|r")
    print("  Phase blocks: |cffff0000"..(self.sessionStats.phaseBlocks or 0).."|r")
    print("  Map blocks: |cffff0000"..(self.sessionStats.mapBlocks or 0).."|r")
    print("  Start phase blocks: |cffff0000"..(self.sessionStats.startPhaseBlocks or 0).."|r")

    print("|cff00ccffGhost Profiles:|r |cffffaa00"..ghostsTotal.."|r")
    print("  Phase ghost: |cffffaa00"..(self.sessionStats.phaseGhost or 0).."|r")
    print("  Map ghost: |cffffaa00"..(self.sessionStats.mapGhost or 0).."|r")
    print("  Start phase ghost: |cffffaa00"..(self.sessionStats.startPhaseGhost or 0).."|r")

    local addonStats = self.sessionStats.requestsByAddon or {}
    print("|cff00ccffRequests by Addon:|r")
    print("  TRP3: |cffffff00"..(addonStats.TRP3 or 0).."|r")
    print("  MRP: |cffffff00"..(addonStats.MRP or 0).."|r")
    print("  XRP: |cffffff00"..(addonStats.XRP or 0).."|r")
    print("  MSP/Other: |cffffff00"..(addonStats.MSP or 0).."|r")

    -- RunPrivileged Statistics (Optimization #9)
    if self.privilegedCallStats then
        local stats = self.privilegedCallStats
        local total = stats.total or 0
        local blocked = stats.blocked or 0
        local errors = stats.errors or 0
        local refunded = stats.refunded or 0
        local deferred = stats.deferred or 0
        local successful = total - errors

        print("|cff00ccffRunPrivileged API:|r")
        print("  Total calls: |cffffff00"..total.."|r")
        print("  Successful: |cff00ff00"..successful.."|r")
        if blocked > 0 then print("  Rate limited: |cffff0000"..blocked.."|r") end
        if errors > 0 then print("  Errors: |cffff0000"..errors.."|r") end
        if deferred > 0 then print("  Deferred (LOW): |cffffff00"..deferred.."|r") end
        
        if refunded > 0 then
            local refundPct = total > 0 and (refunded / total * 100) or 0
            print("  Tokens refunded: |cffffaa00"..refunded.." ("..(string.format("%.1f", refundPct)).."%)|r")
        end

        if self.sessionStats.privilegedStats then
            local batches = self.sessionStats.privilegedStats.phaseCheckBatches or 0
            local saved = self.sessionStats.privilegedStats.phaseCheckTokensSaved or 0
            if batches > 0 then
                print("  Batches processed: |cff00ff00"..batches.."|r")
            end
            if saved > 0 then
                print("  Tokens saved (batching): |cff00ff00"..saved.."|r")
            end
        end

        -- Token bucket state
        if self.privilegedRate then
            local tokens = math.floor(self.privilegedRate.tokens * 10) / 10
            local color = tokens >= 7 and "00ff00" or (tokens >= 4 and "ffff00" or "ff0000")
            print("  Token bucket: |cff"..color..tokens.."/10|r")
        end

        -- Category breakdown (Top 5)
        if stats.byCategory and next(stats.byCategory) then
            print("  |cffaaaaaaTop Categories:|r")
            local categories = {}
            for cat, count in pairs(stats.byCategory) do
                table.insert(categories, {name = cat, count = count})
            end
            table.sort(categories, function(a, b) return a.count > b.count end)
            for i = 1, math.min(5, #categories) do
                print("    "..categories[i].name..": |cffffff00"..categories[i].count.."|r")
            end
        end
    end

    print("|cffaaaaaa━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
    print("|cffaaaaaaView full details in |r|cff00ff00/trp3fwui|r|cffaaaaaa Status tab|r")
end

function TRP3FW:ShowStatus()
    print("|cffaaaaaa━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
    print("|cff00ffffTRP3 Firewall v"..self.VERSION.."|r")
    print("|cffaaaaaa━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")

    -- Core settings
    print("|cff00ffffCore Settings:|r")
    UpdateAddOnMemoryUsage()
    local memKB = GetAddOnMemoryUsage("TRP3FW")
    local memStr = (memKB > 1024) and string.format("%.2f MB", memKB/1024) or string.format("%.0f KB", memKB)
    print("  Memory Usage: |cffffff00"..memStr.."|r")

    local perfStats = self.sessionStats.performance
    
    -- Instant (Last 1s)
    local instLatency = perfStats.lastSecondRequests > 0 and (perfStats.lastSecondTime / perfStats.lastSecondRequests) or 0
    local instLoad = (perfStats.lastSecondTime / 1000) * 100
    local instThroughput = perfStats.lastSecondRequests

    -- Window Avg/Peak (Last Interval)
    local lastInt = perfStats.lastInterval
    local duration = lastInt and lastInt.duration or 1
    
    local avgLatency = (lastInt and lastInt.requests > 0) and (lastInt.time / lastInt.requests) or 0
    local avgLoad = (lastInt and lastInt.time > 0) and ((lastInt.time / (duration * 1000)) * 100) or 0
    local avgThroughput = (lastInt and lastInt.requests > 0) and (lastInt.requests / duration) or 0
    
    local peakLatency = lastInt and lastInt.peakLatency or 0
    local peakLoad = lastInt and lastInt.peakLoad or 0
    local peakThroughput = lastInt and lastInt.peakThroughput or 0

    print("  Latency (Inst/Avg/Peak): |cffffff00"..string.format("%.2f / %.2f / %.2f", instLatency, avgLatency, peakLatency).." ms|r")
    print("  CPU Load (Inst/Avg/Peak): |cffffff00"..string.format("%.2f / %.2f / %.2f", instLoad, avgLoad, peakLoad).." %|r")
    print("  Throughput (Inst/Avg/Peak): |cffffff00"..string.format("%.2f / %.2f / %.2f", instThroughput, avgThroughput, peakThroughput).." req/s|r")
    print("  Notifications: "..self:EnabledDisabled(TRP3FW_Settings.notifyEnabled))
    print("  Suppression: |cffffff00"..TRP3FW_Settings.suppressionTime.."s|r")
    print("  Chat: "..self:OnOff(TRP3FW_Settings.showInChat))
    print("  Screen: "..self:OnOff(TRP3FW_Settings.showOnScreen))
    print("  Sound: "..self:OnOff(TRP3FW_Settings.playSound))
    print("  Show addon source: "..self:OnOff(TRP3FW_Settings.showAddonSource))
    print("  Cache info in notifications: "..self:OnOff(TRP3FW_Settings.showCacheInfo))
    print("  Check results in notifications: "..self:OnOff(TRP3FW_Settings.showCheckResults))
    print("  Ghost notifications: "..self:OnOff(TRP3FW_Settings.showGhostNotifications))

    -- Location check settings
    print("|cff00ffffLocation Check Settings:|r")
    local modeNames = {
        ["off"] = "|cffaaaaaa Off",
        ["statistics"] = "|cffffff00 Statistics Only",
        ["alert"] = "|cffff8800 Alert",
        ["block"] = "|cffff0000 Block",
        ["ghost"] = "|cffffaa00 Ghost",
        ["alert_block"] = "|cffff0000 Alert + Block",
        ["alert_ghost"] = "|cffffaa00 Alert + Ghost"
    }
    local phaseMode = TRP3FW_Settings.phaseCheckMode or "off"
    local mapMode = TRP3FW_Settings.mapCheckMode or "off"
    print("  Phase check mode: "..(modeNames[phaseMode] or "|cffaaaaaa unknown").."|r"..(self.hasEpsilonAPI and " |cff00ff00(API available)|r" or " |cffff0000(API not available)|r"))
    print("  Map check mode: "..(modeNames[mapMode] or "|cffaaaaaa unknown").."|r")
    print("  Use WHO query: "..self:OnOff(TRP3FW_Settings.useWhoQuery)..(self.hasEpsilonAPI and " |cff00ff00(API available)|r" or " |cffff0000(API not available)|r"))
    print("  Block in start phase: "..self:OnOff(TRP3FW_Settings.blockStartPhase).." |cffaaaaaa(Phase 169)|r")
    print("  Ghost in start phase: "..self:OnOff(TRP3FW_Settings.ghostOnStartPhase).." |cffaaaaaa(Phase 169)|r")
    print("  Party/raid auto-allow: "..self:OnOff(TRP3FW_Settings.allowGroupPhaseBypass).." |cffaaaaaa(group members skip checks when enabled)|r")

    -- Notification types
    print("|cff00ffffNotification Types:|r")
    print("  Broadcasts: "..self:EnabledDisabled(TRP3FW_Settings.notifyOnBroadcast))
    print("  Whispers: "..self:EnabledDisabled(TRP3FW_Settings.notifyOnWhisper))

    -- Cache settings
    print("|cff00ffffCache Settings:|r")
    print("  Phase cache: |cffffff00"..TRP3FW_Settings.phaseCacheDuration.."s|r")
    print("  Phase fail cache: |cffffff00"..(TRP3FW_Settings.phaseCacheFailureDuration or 10).."s|r")
    print("  Scan cache: |cffffff00"..TRP3FW_Settings.scanCacheDuration.."s|r")
    print("  WHO zone cache: |cffffff00"..(TRP3FW_Settings.whoZoneCacheDuration or 180).."s|r")
    print("  WHO name cache: |cffffff00"..(TRP3FW_Settings.whoNameCacheDuration or 180).."s|r")
    print("  Send cache: |cffffff00"..TRP3FW_Settings.sendCacheDuration.."s|r")
    print("  Interaction cache: |cffffff00"..(TRP3FW_Settings.interactionCacheDuration or 600).."s|r (mouseover/target)")
    print("  Cache size limit: |cffffff00"..(TRP3FW_Settings.cacheSizeLimit or 1000).."|r entries")

    -- Addon monitoring
    print("|cff00ffffAddon Monitoring:|r")
    print("  Detected addons: |cffffff00"..self:GetDetectedAddonsString().."|r")
    print("  TotalRP3: "..self:EnabledDisabled(TRP3FW_Settings.monitorTRP3)..(self.detectedAddons.TRP3 and " |cff00ff00(Found)|r" or " |cffaaaaaa(Not Found)|r"))
    print("  MyRolePlay: "..self:EnabledDisabled(TRP3FW_Settings.monitorMRP)..(self.detectedAddons.MRP and " |cff00ff00(Found)|r" or " |cffaaaaaa(Not Found)|r"))
    print("  XRP: "..self:EnabledDisabled(TRP3FW_Settings.monitorXRP)..(self.detectedAddons.XRP and " |cff00ff00(Found)|r" or " |cffaaaaaa(Not Found)|r"))
    print("  MSP/Other: "..self:EnabledDisabled(TRP3FW_Settings.monitorMSP)..(self.detectedAddons.MSP and " |cff00ff00(Found)|r" or " |cffaaaaaa(Not Found)|r"))
    print("  Map Scanner: "..(self.detectedAddons.MapScanner and "|cff00ff00"..self.detectedAddons.MapScanner.."|r" or "|cffff0000Not Available|r"))

    -- Filter settings
    print("|cff00ffffFilters:|r")
    print("  Gradient filter: "..self:EnabledDisabled(TRP3FW_Settings.filterGradients))
    print("  Font size filter: "..self:EnabledDisabled(TRP3FW_Settings.filterMinimumFontSize))
    print("    Font size level: |cffffff00"..(TRP3FW_Settings.minimumFontSizeLevel or "h3").."|r")

    -- Debug settings
    print("|cff00ffffDebug:|r")
    print("  Debug mode: "..self:OnOff(TRP3FW_Settings.debug))
    print("  Debug timestamps: "..self:OnOff(TRP3FW_Settings.debugTimestamp))

    print("|cffaaaaaa━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
end

function TRP3FW:ShowWelcomeMessage()
    -- Only show once per character
    if TRP3FW_Settings.hasSeenWelcome then return end

    TRP3FW_Settings.hasSeenWelcome = true

    print("|cffaaaaaa━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
    print("|cff00ffffWelcome to TRP3 Firewall v"..self.VERSION.."!|r")
    print("|cffaaaaaa━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
    print("|cff00ccffQuick Start:|r")
    print("• |cff00ff00/trp3fwui|r - Open settings (recommended)")
    print("• |cff00ff00/trp3fw status|r - View current configuration")
    print("• |cff00ff00/trp3fw stats|r - View session statistics")
    print("• |cff00ff00/trp3fw test|r - Test notifications")
    print("• |cff00ff00/trp3fw help|r - Full command list")
    print("")
    print("|cffaaaaaaPhase & Map checking are set to |cffffff00ALERT|r|cffaaaaaa by default.|r")
    print("|cffaaaaaaUse the UI to configure Location Checking modes.|r")
    print("|cffaaaaaa━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
end

function TRP3FW:TestNotifications()
    self:Info("Testing notifications...")
    print("|cffaaaaaa━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")

    -- Test 1: Allow notification
    print("|cff00ccff[Test 1/5]|r Normal allow notification:")
    C_Timer.After(1, function()
        if TRP3FW_Settings.showInChat then
            print("Your profile was sent to |cff00ccffTestPlayer|r via |cff00ff00TRP3|r")
        end
        if TRP3FW_Settings.showOnScreen then
            RaidNotice_AddMessage(RaidWarningFrame, "Profile sent: |cff00ff00TestPlayer|r", ChatTypeInfo["RAID_WARNING"])
        end
        self:PlayNotificationSound()
    end)

    -- Test 2: Phase alert
    print("|cff00ccff[Test 2/5]|r Phase alert notification:")
    C_Timer.After(3, function()
        if TRP3FW_Settings.showInChat then
            print("|cffff0000[ALERT]|r Your profile was sent to |cff00ccffTestPlayer|r via |cff00ff00TRP3|r |cffff0000(NOT IN YOUR PHASE)|r")
        end
        if TRP3FW_Settings.showOnScreen then
            RaidNotice_AddMessage(RaidWarningFrame, "[ALERT]: |cff00ff00TestPlayer|r\n|cffff0000Not in your phase!|r", ChatTypeInfo["RAID_WARNING"])
        end
        self:PlayNotificationSound()
    end)

    -- Test 3: Map alert
    print("|cff00ccff[Test 3/5]|r Map alert notification:")
    C_Timer.After(5, function()
        if TRP3FW_Settings.showInChat then
            print("|cffff0000[ALERT]|r Your profile was sent to |cff00ccffTestPlayer|r via |cff00ff00TRP3|r |cffff0000(They're in Stormwind City, you're in Elwynn Forest)|r")
        end
        if TRP3FW_Settings.showOnScreen then
            RaidNotice_AddMessage(RaidWarningFrame, "[ALERT]: |cff00ff00TestPlayer|r\n|cffff0000They're in Stormwind City, you're in Elwynn Forest|r", ChatTypeInfo["RAID_WARNING"])
        end
        self:PlayNotificationSound()
    end)

    -- Test 4: Block notification
    print("|cff00ccff[Test 4/5]|r Block notification:")
    C_Timer.After(7, function()
        if TRP3FW_Settings.showInChat then
            print("|cffff0000[BLOCKED]|r Your profile was blocked for |cff00ccffTestPlayer|r via |cff00ff00TRP3|r |cffff0000(NOT IN YOUR PHASE)|r")
        end
        if TRP3FW_Settings.showOnScreen then
            RaidNotice_AddMessage(RaidWarningFrame, "[BLOCKED]: |cff00ff00TestPlayer|r\n|cffff0000Not in your phase!|r", ChatTypeInfo["RAID_WARNING"])
        end
        self:PlayNotificationSound()
    end)

    -- Test 5: Ghost mode notification
    print("|cff00ccff[Test 5/5]|r Ghost mode notification:")
    C_Timer.After(9, function()
        if TRP3FW_Settings.showInChat then
            print("|cffffaa00[GHOST MODE]|r Your profile was sent BLANK profile to |cff00ccffTestPlayer|r via |cff00ff00TRP3|r |cffff0000(NOT IN YOUR PHASE)|r")
        end
        if TRP3FW_Settings.showOnScreen then
            RaidNotice_AddMessage(RaidWarningFrame, "[GHOST MODE]: |cff00ff00TestPlayer|r\n|cffff0000Not in your phase!|r", ChatTypeInfo["RAID_WARNING"])
        end
        self:PlayNotificationSound()
    end)

    print("|cffaaaaaa━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
    print("|cffaaaaaaTest complete in 10 seconds. Check your display settings:|r")
    print("|cffaaaaaa  Chat: "..(TRP3FW_Settings.showInChat and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    print("|cffaaaaaa  Screen: "..(TRP3FW_Settings.showOnScreen and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    print("|cffaaaaaa  Sound: "..(TRP3FW_Settings.playSound and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

function TRP3FW:ShowHelp()
    self:Info("TRP3 Firewall v"..self.VERSION)
    print("|cffaaaaaa━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
    print("|cff00ccff=== Getting Started ===|r")
    print("|cff00ff00/trp3fwui|r - Open settings UI (recommended)")
    print("|cff00ff00/trp3fw status|r - Show current settings and statistics")
    print("|cff00ff00/trp3fw stats|r - Show session stats (alerts/blocks/ghosts)")
    print("|cff00ff00/trp3fw test|r - Test notifications (see what alerts look like)")
    print("")
    print("|cff00ccff=== Quick Configuration ===|r")
    print("|cff00ff00/trp3fw notify toggle|r - Toggle all notifications on/off")
    print("|cff00ff00/trp3fw notify broadcast|r - Toggle broadcast notifications")
    print("|cff00ff00/trp3fw notify whisper|r - Toggle whisper notifications")
    print("|cff00ff00/trp3fw notify startphase|r - Toggle start-phase block notifications")
    print("|cff00ff00/trp3fw display chat|r - Show notifications in chat")
    print("|cff00ff00/trp3fw display screen|r - Show on-screen alerts")
    print("|cff00ff00/trp3fw display sound|r - Toggle notification sounds")
    print("|cff00ff00/trp3fw suppress <seconds>|r - Set notification suppression time (0-3600)")
    print("")
    print("|cff00ccff=== Start Phase Protection ===|r")
    print("|cff00ff00/trp3fw suppresswho|r - Hide WHO output (prevent chat spam)")
    print("")
    print("|cff00ccff=== Filters ===|r")
    print("|cff00ff00/trp3fw filter gradient|r - Toggle color gradient stripping")
    print("|cff00ff00/trp3fw filter fontsize|r - Toggle minimum font size injection")
    print("|cff00ff00/trp3fw fontsize [on|off|h1|h2|h3|p]|r - Configure font size filter")
    print("  |cffaaaaaaon/off: Enable/disable filter, h1-h3: Set size level|r")
    print("")
    print("|cff00ccff=== Advanced ===|r")
    print("|cff00ff00/trp3fw phasecheck [verbose]|r - Scan zone for players in your phase (Epsilon only)")
    print("  |cffaaaaaaverbose: List all players found|r")
    print("|cff00ff00/trp3fw cache <type> <seconds>|r - Set cache duration")
    print("  |cffaaaaaa<type>: phase, scan, whozone, whoname, send, interaction|r")
    print("|cff00ff00/trp3fw clearcache [cache]|r - Clear specific cache")
    print("  |cffaaaaaaTypes: phasecheck, allowed, interaction, broadcasts, scans, whozone, whoname, all|r")
    print("|cff00ff00/trp3fw phasedelay <seconds>|r - Phase-in delay (0-10, default: 3)")
    print("")
    print("|cff00ccff=== Debugging ===|r")
    print("|cff00ff00/trp3fw debug|r - Toggle debug mode")
    print("|cff00ff00/trp3fw debugtime|r - Toggle debug timestamps")
    print("|cff00ff00/trp3fw debugfilter <category>|r - Filter debug output")
    print("|cff00ff00/trp3fw reloadhooks|r - Reinstall addon hooks")
    print("")
    print("|cff00ccff=== Other ===|r")
    print("|cff00ff00/trp3fw minimap|r - Toggle minimap button")
    print("|cff00ff00/trp3fw reset|r - Reset all settings to defaults")
    print("|cffaaaaaa━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
    print("|cffaaaaaaFor full control, use |r|cff00ff00/trp3fwui|r|cffaaaaaa or click the minimap button|r")
    print("|cffaaaaaaBug reports: https://github.com/[your-repo]/issues|r")
end
