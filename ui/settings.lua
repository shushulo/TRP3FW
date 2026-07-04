-- ui/settings.lua
-- Settings UI with tabs

local addonName, TRP3FW = ...

-- Helper to determine if changing to a more restrictive mode requires clearing the allowedSenders cache
function TRP3FW:ShouldClearAllowedSenders(newMode, previousMode)
    local restrictiveModes = {
        ["block"] = true,
        ["ghost"] = true,
        ["alert_block"] = true,
        ["alert_ghost"] = true,
        ["off"] = false,
        ["statistics"] = false,
        ["alert"] = false,
    }
    return restrictiveModes[newMode] and not restrictiveModes[previousMode]
end

-- UI element references
local uiElements = {}
local epsilonControls = {}
local RequestRefreshUI
local settingsFrame
local refreshScheduled = false

-- Complexity Levels
local COMPLEXITY_NAMES = { [1] = "Basic", [2] = "Intermediate", [3] = "Advanced", [4] = "Everything" }
local complexityWidgets = {}

-- Widgets with custom Enable/Disable logic in RefreshUI that should NOT be overridden by complexity
local CUSTOM_LOGIC_KEYS = {
    minimumFontSizeLevel = true,
    clearPhaseCheckOnPhaseChange = true, clearAllowedSendersOnPhaseChange = true, clearInteractionOnPhaseChange = true,
    clearSuppressionOnPhaseChange = true, clearRecentBroadcastsOnPhaseChange = true, clearRecentScansOnPhaseChange = true,
    clearWhoZoneOnPhaseChange = true, clearWhoNameOnPhaseChange = true, clearSpvpOnPhaseChange = true,
    clearPhaseCheckOnZoneChange = true, clearAllowedSendersOnZoneChange = true, clearInteractionOnZoneChange = true,
    clearSuppressionOnZoneChange = true, clearRecentBroadcastsOnZoneChange = true, clearRecentScansOnZoneChange = true,
    clearWhoZoneOnZoneChange = true, clearWhoNameOnZoneChange = true, clearSpvpOnZoneChange = true,
    debugTimestamp = true, debugChannel = true, debugWhisper = true, debugWho = true, debugPhase = true, debugCleanName = true,
    debugLocation = true, debugDecision = true, debugHooks = true, debugCache = true, debugSend = true, debugUI = true,
    debugUtils = true, debugSecurity = true, debugGhost = true, debugSPVP = true,
    scanResponseRequireNonce = true, scanResponseCacheEnabled = true, scanResponseAllowCacheBypass = true,
    scanResponseAllowGroupBypass = true, scanResponseWhitelistEnabled = true, scanResponseWhitelistEdit = true,
    scanResponseWhitelistScroll = true, scanResponsePhaseMode = true, scanResponseMapMode = true,
    notifyOnScanResponse = true, notifyOnScanAllow = true,
    redactNames = true, redactLocations = true, redactNetwork = true, redactSPVP = true,
    ghostProfileWhitelistEdit = true, ghostProfileWhitelistScroll = true,
    spvpSaltStatus = true, spvpSecureButton = true, spvpBlockDurationSlider = true, spvpSaltCacheDurationSlider = true,
    blockStartPhase = true, ghostOnStartPhase = true, ghostProfileSwitch = true, ghostProfileWhitelistEnabled = true
}

local SETTING_LEVELS = {
    -- Level 1 (Basic): Core toggles a new user immediately needs
    notifyEnabled = 1, showInChat = 1, showOnScreen = 1, playSound = 1, suppressionTime = 1,
    phaseCheckMode = 1, mapCheckMode = 1, whitelistEnabled = 1, whitelistEntries = 1,
    blockStartPhase = 1, ghostOnStartPhase = 1, ghostProfileSwitch = 1,
    allowGroupPhaseBypass = 1, useWhoQuery = 1,
    filterGradients = 1, filterIcons = 1, trackHistory = 1,
    -- Level 2 (Intermediate): Tunable behavior most regular users will eventually touch
    notifyOnAllow = 2, notifyOnStartPhaseBlock = 2, notifyOnWhisper = 2, showGhostNotifications = 2,
    ghostProfileName = 2, filterMinimumFontSize = 2, minimumFontSizeLevel = 2,
    refreshSuppression = 2, suppressAllWhoOutput = 2, spvpMode = 2,
    scanResponsePhaseMode = 2, scanResponseMapMode = 2, notifyOnScanResponse = 2,
    scanResponseAllowGroupBypass = 2, mapScanMinInterval = 2, disableMapScanOnTRP3 = 2,
    -- Level 3 (Advanced): Power-user tuning, cache durations, batching, security details
    notifyOnBroadcast = 3, showAddonSource = 3, notifyOnScanAllow = 3,
    scanResponseAllowCacheBypass = 3, scanResponseCacheEnabled = 3,
    scanResponseRequireNonce = 3, scanResponseWhitelistEnabled = 3,
    ghostProfileWhitelistEnabled = 3, ghostProfileWhitelist = 3, ghostProfileOverrides = 3,
    monitorTRP3 = 3, monitorMRP = 3, monitorXRP = 3, monitorMSP = 3, abortOnMultipleRPAddons = 3,
    phaseInDelay = 3, transitionGracePeriod = 3,
    redactLocations = 3, redactNetwork = 3, redactSPVP = 3, cacheSizeLimit = 3,
    scanCacheDuration = 3, scanCacheFailureDuration = 3,
    whoZoneQueryCooldown = 3, whoZoneCacheDuration = 3, whoNameCacheDuration = 3, whoCacheRefreshThreshold = 3,
    phaseCheckBatchMode = 3, phaseCheckBatchSize = 3, phaseCheckBatchDelay = 3,
    phaseCheckBatchMinSize = 3, phaseCheckBatchInterDelay = 3,
    spvpAutoInitialize = 3, spvpBlockDuration = 3, spvpSaltCacheDuration = 3,
    spvpVerifiedCacheDuration = 3, spvpVerifiedRefreshRate = 3,
    -- Level 4 (Everything): Developer/diagnostic
    showCacheInfo = 4, showCheckResults = 4, performanceHistoryEnabled = 4,
    spvpPhaseSaltRefreshRate = 4, phaseCheckRefundOnNoChange = 4,
    privilegedReservedTokens = 4, privilegedLowPriorityThreshold = 4,
}
TRP3FW.SETTING_LEVELS = SETTING_LEVELS

local function UpdateUIComplexity()
    if not TRP3FW.Prefs then return end
    local currentLevel = TRP3FW.Prefs.uiComplexityLevel or 2
    for _, widget in ipairs(complexityWidgets) do
        local wLevel = widget.complexityLevel or 4
        local enabled = wLevel <= currentLevel

        local hasCustomLogic = widget.settingKey and CUSTOM_LOGIC_KEYS[widget.settingKey]

        if enabled then
            -- Complexity Met: Enable ONLY if no custom logic (allow RefreshUI to handle custom ones)
            if not hasCustomLogic then
                if widget.Enable then widget:Enable() end
                if widget.EnableDropDown then widget:EnableDropDown() end
            end
            if widget.SetAlpha then widget:SetAlpha(1.0) end
            if widget.label then widget.label:SetAlpha(1.0) end
        else
            -- Complexity Unmet: Force Disable & Fade
            if widget.Disable then widget:Disable() end
            if widget.DisableDropDown then widget:DisableDropDown() end
            if widget.SetAlpha then widget:SetAlpha(0.5) end
            if widget.label then widget.label:SetAlpha(0.5) end
        end
    end
end

function TRP3FW:EnforceComplexityDefaults(newLevel)
    if not TRP3FW.Prefs or not TRP3FW.defaultSettings then return end
    for _, widget in ipairs(complexityWidgets) do
        local wLevel = widget.complexityLevel or 4
        if wLevel > newLevel and widget.settingKey then
            local key = widget.settingKey
            local default = TRP3FW.defaultSettings[key]
            if default ~= nil and TRP3FW.Prefs[key] ~= default then
                TRP3FW.Prefs[key] = default
            end
        end
    end
end

local function EnsureBlankProfilesExist()
    if not TRP3FW:IsGhostModeEnabled() then return end
    if TRP3_API and TRP3_Profiles then pcall(TRP3FW.CreateBlankProfile_TRP3, TRP3FW) end
    if mrp and mrpSaved then pcall(TRP3FW.CreateBlankProfile_MRP, TRP3FW) end
    if AddOn_XRP and xrpSaved then pcall(TRP3FW.CreateBlankProfile_XRP, TRP3FW) end
end
TRP3FW.EnsureBlankProfilesExist = EnsureBlankProfilesExist

-- Dialogs
StaticPopupDialogs["TRP3FW_CHANGE_PROFILE_NAME"] = { text = "WARNING: Changing ghost profile name to '%s' is not recommended. Use TRP3FW_BLANK for safety. Continue?", button1 = "Yes", button2 = "Cancel", OnAccept = function(self, data) TRP3FW.Prefs.ghostProfileName = data; TRP3FW:RefreshUI() end, timeout = 0, whileDead = 1, showAlert = 1 }
StaticPopupDialogs["TRP3FW_RESET_CONFIRM"] = { text = "Reset ALL settings to defaults?", button1 = "Yes", button2 = "Cancel", OnAccept = function() TRP3FW.Prefs = {}; TRP3FW:InitializeSettings(); TRP3FW:RefreshUI() end, timeout = 0, whileDead = 1, showAlert = 1 }
StaticPopupDialogs["TRP3FW_WHITELIST_CONFIRM"] = { text = "Security warning: Whitelist bypass skips ALL checks. Continue?", button1 = "Allow", button2 = "Cancel", OnAccept = function() TRP3FW.Prefs.whitelistEnabled = true; TRP3FW:RefreshUI() end, OnCancel = function() TRP3FW.Prefs.whitelistEnabled = false; TRP3FW:RefreshUI() end, timeout = 0, whileDead = 1, showAlert = 1 }
StaticPopupDialogs["TRP3FW_SPVP_ROTATE_CONFIRM"] = { text = "Rotate SPVP key? This invalidates existing verifications for all players in this phase.", button1 = "Rotate", button2 = "Cancel", OnAccept = function() if TRP3FW.SecureCurrentPhase then TRP3FW:SecureCurrentPhase(); TRP3FW:RefreshUI() end end, timeout = 0, whileDead = 1, showAlert = 1 }
StaticPopupDialogs["TRP3FW_CONFIRM_PROFILE_SWITCH"] = { text = "Switch to profile '%s'?", button1 = "Yes", button2 = "No", OnAccept = function(self, data) TRP3FW:LoadProfile(data); if TRP3FW.RefreshProfilesTab then TRP3FW.RefreshProfilesTab() end; TRP3FW:RefreshUI() end, timeout = 0, whileDead = 1 }
StaticPopupDialogs["TRP3FW_CREATE_PROFILE"] = { text = "Name for new profile:", button1 = "Create", button2 = "Cancel", hasEditBox = true, OnAccept = function(self) local n = self.editBox:GetText(); if n and n ~= "" then TRP3FW.GlobalDB.profiles[n] = CopyTable(TRP3FW.Prefs); TRP3FW:LoadProfile(n); TRP3FW:RefreshUI() end end, timeout = 0, whileDead = 1 }
StaticPopupDialogs["TRP3FW_CONFIRM_PROFILE_DELETE"] = { text = "Delete profile '%s'?", button1 = "Delete", button2 = "Cancel", OnAccept = function(self, data) if data ~= "Default" then TRP3FW.GlobalDB.profiles[data] = nil; if TRP3FW.RefreshProfilesTab then TRP3FW.RefreshProfilesTab() end end end, timeout = 0, whileDead = 1, showAlert = 1 }
StaticPopupDialogs["TRP3FW_RENAME_PROFILE"] = { text = "Rename profile '%s' to:", button1 = "Rename", button2 = "Cancel", hasEditBox = true, OnAccept = function(self, data) local n = self.editBox:GetText(); if n and n ~= "" and not TRP3FW.GlobalDB.profiles[n] then TRP3FW.GlobalDB.profiles[n] = TRP3FW.GlobalDB.profiles[data]; TRP3FW.GlobalDB.profiles[data] = nil; TRP3FW:RefreshUI() end end, timeout = 0, whileDead = 1 }

local function InitializeMinimapSettings()
    if not TRP3FW_MinimapSettings then TRP3FW_MinimapSettings = { hide = false, minimapPos = 225, radius = 80 } end
end

function TRP3FW:CreateMinimapButton()
    if TRP3FW.minimapButton or not Minimap then return end
    local b = CreateFrame("Button", "TRP3FW_MinimapButton", Minimap)
    b:SetSize(32, 32); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(20); b:RegisterForDrag("LeftButton"); b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = b:CreateTexture(nil, "BACKGROUND"); icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1); icon:SetTexture("Interface\\Icons\\Ability_Rogue_FeignDeath"); b.icon = icon
    local overlay = b:CreateTexture(nil, "OVERLAY"); overlay:SetSize(52, 52); overlay:SetPoint("TOPLEFT"); overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("TRP3 Firewall", 1, 1, 1); GameTooltip:AddLine("Left-click: Settings\nRight-click: Toggle Notifications", 0, 1, 0); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, button) if button == "LeftButton" then if settingsFrame:IsVisible() then settingsFrame:Hide() else settingsFrame:Show() end else TRP3FW.Prefs.notifyEnabled = not TRP3FW.Prefs.notifyEnabled; TRP3FW:Info("Notifications "..(TRP3FW.Prefs.notifyEnabled and "|cff00ff00on|r" or "|cffaaaaaadoff|r")); TRP3FW:RefreshUI() end end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", function() local mx, my = Minimap:GetCenter(); local px, py = GetCursorPosition(); local s = Minimap:GetEffectiveScale(); local deg = math.deg(math.atan2(py/s - my, px/s - mx)); if deg < 0 then deg = deg + 360 end; TRP3FW_MinimapSettings.minimapPos = deg; local r = TRP3FW_MinimapSettings.radius; b:SetPoint("CENTER", Minimap, "CENTER", math.cos(math.rad(deg))*r, math.sin(math.rad(deg))*r) end) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    local r = TRP3FW_MinimapSettings.radius; local d = TRP3FW_MinimapSettings.minimapPos; b:SetPoint("CENTER", Minimap, "CENTER", math.cos(math.rad(d))*r, math.sin(math.rad(d))*r)
    if TRP3FW_MinimapSettings.hide then b:Hide() else b:Show() end; TRP3FW.minimapButton = b
end

local backgroundTicker
function TRP3FW:UpdateBackgroundTracking()
    if backgroundTicker then backgroundTicker:Cancel(); backgroundTicker = nil end
    if TRP3FW.Prefs and TRP3FW.Prefs.performanceHistoryEnabled then
        backgroundTicker = C_Timer.NewTicker(TRP3FW.Prefs.statusRefreshRate or 30, function() if not settingsFrame:IsVisible() then local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService"); if hs then hs:RecordPerformance(0) end end end)
    end
end

local statusUpdateCount = 0
function TRP3FW:UpdateStatusTab()
    local start = debugprofilestop()
    if not uiElements.statusAddonsList then return end
    local now = TRP3FW:GetCurrentTime()
    statusUpdateCount = statusUpdateCount + 1

    -- Memory Usage
    local memoryQueryOverhead = 0
    if uiElements.statusMemory then
        -- Optimization: Only force GC every 4th update to reduce lag spikes (approx every 2 mins at default 30s)
        if statusUpdateCount % 4 == 0 then
            local memStart = debugprofilestop()
            UpdateAddOnMemoryUsage()
            memoryQueryOverhead = debugprofilestop() - memStart
        end
        local memKB = GetAddOnMemoryUsage("TRP3FW")
        local memStr = (memKB > 1024) and string.format("|cff00ff00%.2f MB|r", memKB/1024) or string.format("|cff00ff00%.0f KB|r", memKB)
        uiElements.statusMemory:SetText(memStr)
    end

    -- Performance Metrics
    local perfStats = TRP3FW.sessionStats.performance
    if perfStats then
        -- Instant
        local instLatency = perfStats.lastSecondRequests > 0 and (perfStats.lastSecondTime / perfStats.lastSecondRequests) or 0
        local instLoad = (perfStats.lastSecondTime / 1000) * 100
        local instThroughput = perfStats.lastSecondRequests

        -- Window
        local lastInt = perfStats.lastInterval
        local duration = lastInt and lastInt.duration or 1

        local avgLatency = (lastInt and lastInt.requests > 0) and (lastInt.time / lastInt.requests) or 0
        local avgLoad = (lastInt and lastInt.time > 0) and ((lastInt.time / (duration * 1000)) * 100) or 0
        local avgThroughput = (lastInt and lastInt.requests > 0) and (lastInt.requests / duration) or 0
        local peakLatency = lastInt and lastInt.peakLatency or 0
        local peakLoad = lastInt and lastInt.peakLoad or 0
        local peakThroughput = lastInt and lastInt.peakThroughput or 0

        if uiElements.statusLatency then
            uiElements.statusLatency:SetText(string.format("|cff00ff00%.2f / %.2f / %.2f ms|r", instLatency, avgLatency, peakLatency))
        end
        if uiElements.statusCPULoad then
            uiElements.statusCPULoad:SetText(string.format("|cff00ff00%.2f / %.2f / %.2f %%|r", instLoad, avgLoad, peakLoad))
        end
        if uiElements.statusThroughput then
            uiElements.statusThroughput:SetText(string.format("|cff00ff00%.2f / %.2f / %.2f r/s|r", instThroughput, avgThroughput, peakThroughput))
        end
    end

    -- Phase Security Indicator
    if uiElements.statusPhaseSecurity then
        if TRP3FW.hasEpsilonAPI then
            local phaseID = TRP3FW:GetCurrentPhaseID()
            local phaseSalt = TRP3FW:GetPhaseSalt(phaseID, false)
            if phaseSalt and phaseSalt ~= "" then
                local _, timestamp = TRP3FW:ParsePhaseSalt(phaseSalt)
                local ageStr = ""

                -- Validate salt format (Basic check)
                -- Expecting either "HEX:TIMESTAMP" or pure "HEX"
                -- Allow some leniency for custom salts but flag them
                local isHex = phaseSalt:match("^[0-9a-fA-F:]+$")
                local isLongEnough = #phaseSalt >= 16

                if timestamp then
                    local daysOld = math.floor((time() - timestamp) / 86400)
                    ageStr = string.format(" (Age: %d days)", daysOld)
                    uiElements.statusPhaseSecurity:SetText("|cff00ff00Secured|r" .. ageStr)
                elseif isHex and isLongEnough then
                    uiElements.statusPhaseSecurity:SetText("|cff00ff00Secured|r (Legacy Format)")
                else
                    -- Non-standard salt (short or non-hex)
                    uiElements.statusPhaseSecurity:SetText("|cffffcc00Unknown Data|r (Custom/Weak Key)")
                end
            else
                uiElements.statusPhaseSecurity:SetText("|cffff0000Unsecured|r")
            end
        else
            uiElements.statusPhaseSecurity:SetText("|cffaaaaaaN/A|r")
        end
    end

    -- Detected RP Addons (compact inline format)
    local addons = {}
    if TRP3FW.detectedAddons.TRP3 then table.insert(addons, "|cff00ff00TRP3|r") end
    if TRP3FW.detectedAddons.MRP then table.insert(addons, "|cff00ff00MRP|r") end
    if TRP3FW.detectedAddons.XRP then table.insert(addons, "|cff00ff00XRP|r") end
    if TRP3FW.detectedAddons.MSP then table.insert(addons, "|cff00ff00MSP|r") end

    if #addons > 0 then
        uiElements.statusAddonsList:SetText(table.concat(addons, "  "))  -- Space-separated
    else
        uiElements.statusAddonsList:SetText("|cffff0000None detected|r")
    end

    -- Map Scanner (compact format)
    if TRP3FW.detectedAddons.MapScanner then
        uiElements.statusMapScanner:SetText("|cff00ff00"..TRP3FW.detectedAddons.MapScanner.."|r")
    else
        uiElements.statusMapScanner:SetText("|cff888888Not available|r")
    end

    -- Epsilon API (compact format)
    if TRP3FW.hasEpsilonAPI then
        uiElements.statusEpsilonAPI:SetText("|cff00ff00Available|r")
    else
        uiElements.statusEpsilonAPI:SetText("|cff888888Unavailable|r")
    end

    -- Session Statistics (Cards)
    if uiElements.statusAlertsCard then
        uiElements.statusAlertsCard.value:SetText(tostring(TRP3FW.sessionStats.alerts))
        uiElements.statusAlertsCard.value:SetTextColor(1, 0.8, 0.2)  -- Yellow/orange
    end
    if uiElements.statusBlocksCard then
        uiElements.statusBlocksCard.value:SetText(tostring(TRP3FW.sessionStats.blocks))
        uiElements.statusBlocksCard.value:SetTextColor(0.9, 0.3, 0.3)  -- Red
    end
    if uiElements.statusGhostCard then
        uiElements.statusGhostCard.value:SetText(tostring(TRP3FW.sessionStats.ghostSends))
        uiElements.statusGhostCard.value:SetTextColor(0.5, 0.8, 1.0)  -- Light blue
    end

    -- Detection Breakdown
    uiElements.statusPhaseAlerts:SetText(TRP3FW.sessionStats.phaseAlerts.." detections")
    uiElements.statusMapAlerts:SetText(TRP3FW.sessionStats.mapAlerts.." detections")

    -- Recent events
    if uiElements.statusRecentEvents then
        local history = TRP3FW.notificationHistory or {}
        local suppressWindow = 30

        -- Optimization: Reuse display objects to prevent garbage churn
        TRP3FW.statusDisplayCache = TRP3FW.statusDisplayCache or { display = {}, seen = {} }
        local display = TRP3FW.statusDisplayCache.display
        local seen = TRP3FW.statusDisplayCache.seen
        wipe(seen)

        local displayCount = 0

        for _, entry in ipairs(history) do
            if entry then
                local key = (entry.player or "")
                local ts = entry.timestamp or 0
                local index = seen[key]

                -- Check if we've seen this player recently (using index to look up prev timestamp)
                if index and display[index] and (display[index].ts - ts) <= suppressWindow then
                    local item = display[index]
                    item.count = (item.count or 1) + 1
                else
                    displayCount = displayCount + 1
                    local item = display[displayCount]
                    if not item then
                        item = {}
                        display[displayCount] = item
                    end

                    item.entry = entry
                    item.count = 1
                    item.ts = ts

                    seen[key] = displayCount

                    if displayCount >= #uiElements.statusRecentEvents then
                        break
                    end
                end
            end
        end

        -- Clear stale entries from display reuse pool to release references
        for i = displayCount + 1, #display do
            display[i].entry = nil
        end

        local function outcomeText(entry)
            if entry.wasGhost then
                return "|cff88ccffGHOST|r"
            elseif entry.wasBlocked then
                return "|cffff4444BLOCK|r"
            elseif entry.wasAlert then
                return "|cffffcc33ALERT|r"
            else
                return "|cff66ff66ALLOW|r"
            end
        end

        for i, row in ipairs(uiElements.statusRecentEvents) do
            local item = display[i]
            if i <= displayCount and item and item.entry then
                local entry = item.entry
                local ts = entry.timestamp and date("%H:%M:%S", entry.timestamp) or "--"
                local player = entry.player or "Unknown"
                local addon = entry.addon or "?"
                local countSuffix = (item.count and item.count > 1) and string.format(" (x%d)", item.count) or ""

                if row.Time then row.Time:SetText(ts) end
                if row.Player then row.Player:SetText(player) end
                if row.Addon then row.Addon:SetText(addon) end
                if row.Result then row.Result:SetText(outcomeText(entry) .. countSuffix) end
            else
                if row.Time then row.Time:SetText("") end
                if row.Player then row.Player:SetText("") end
                if row.Addon then row.Addon:SetText("") end
                if row.Result then
                    if i == 1 and displayCount == 0 then
                        row.Result:SetText("|cff555555No recent events yet|r")
                    else
                        row.Result:SetText("")
                    end
                end
            end
        end
    end

    -- Requests by Addon (Horizontal Bar)
    if uiElements.statusRequestsBar then
        uiElements.statusRequestsBar:SetValues(TRP3FW.sessionStats.requestsByAddon)
    end

    -- Cache Performance (Progress Bars)
    local function UpdateCacheBar(bar, hits, misses)
        if not bar then return end
        local total = hits + misses
        if total == 0 then
            bar:SetValue(0, "No queries yet")
        else
            local rate = (hits / total) * 100
            bar:SetValue(rate, string.format("%.1f%% (%d/%d)", rate, hits, total))
        end
    end

    UpdateCacheBar(uiElements.statusPhaseCachePerfBar,
        TRP3FW.sessionStats.cacheStats.phaseCacheHits,
        TRP3FW.sessionStats.cacheStats.phaseCacheMisses)

    UpdateCacheBar(uiElements.statusMapCachePerfBar,
        TRP3FW.sessionStats.cacheStats.mapCacheHits,
        TRP3FW.sessionStats.cacheStats.mapCacheMisses)

    UpdateCacheBar(uiElements.statusWhoCachePerfBar,
        TRP3FW.sessionStats.cacheStats.whoCacheHits,
        TRP3FW.sessionStats.cacheStats.whoCacheMisses)

    UpdateCacheBar(uiElements.statusAllowedSendersCachePerfBar,
        TRP3FW.sessionStats.cacheStats.allowedSendersCacheHits,
        TRP3FW.sessionStats.cacheStats.allowedSendersCacheMisses)

    UpdateCacheBar(uiElements.statusInteractionCachePerfBar,
        TRP3FW.sessionStats.cacheStats.interactionCacheHits,
        TRP3FW.sessionStats.cacheStats.interactionCacheMisses)

    UpdateCacheBar(uiElements.statusBroadcastCachePerfBar,
        TRP3FW.sessionStats.cacheStats.broadcastCacheHits,
        TRP3FW.sessionStats.cacheStats.broadcastCacheMisses)

    -- Update SPVP Cache Bar (Salt)
    if TRP3FW.sessionStats.spvpCache then
        UpdateCacheBar(uiElements.statusSpvpCachePerfBar,
            TRP3FW.sessionStats.spvpCache.hits,
            TRP3FW.sessionStats.spvpCache.misses)
    end

    -- Update SPVP Verified Cache Bar
    UpdateCacheBar(uiElements.statusSpvpVerifiedCachePerfBar,
        TRP3FW.sessionStats.cacheStats.spvpVerifiedCacheHits,
        TRP3FW.sessionStats.cacheStats.spvpVerifiedCacheMisses)

    -- Cache Status (player/entry counts)
    local cacheCountState = TRP3FW.cacheCountState or { timestamp = 0, counts = nil }
    TRP3FW.cacheCountState = cacheCountState
    local function getCacheCounts()
        local now = TRP3FW:GetCurrentTime()
        if cacheCountState.counts and (now - cacheCountState.timestamp) < 5 then
            return cacheCountState.counts
        end

        local CI = TRP3FW.CacheInterface
        local counts = {
            phase = CI and CI:GetSize("phaseCheck") or 0,
            broadcast = CI and CI:GetSize("broadcast") or 0,
            scan = CI and CI:GetSize("mapScan") or 0,
            send = CI and CI:GetSize("allowedSenders") or 0,
            whoName = CI and CI:GetSize("whoName") or 0,
            whoZone = CI and CI:GetSize("whoZone") or 0,
            interaction = CI and CI:GetSize("interaction") or 0,
            spvpSalt = CI and CI:GetSize("spvpPhaseSalt") or 0,
            spvpVerified = CI and CI:GetSize("spvpVerified") or 0,
            suppression = TRP3FW:CountTableEntries(TRP3FW.profileSendHistory),
        }
        cacheCountState.counts = counts
        cacheCountState.timestamp = now
        return counts
    end

    local counts = getCacheCounts()
    if uiElements.statusPhaseCache then uiElements.statusPhaseCache:SetText((counts.phase or 0).." entries") end
    if uiElements.statusBroadcastCache then uiElements.statusBroadcastCache:SetText((counts.broadcast or 0).." entries") end
    if uiElements.statusScanCache then uiElements.statusScanCache:SetText((counts.scan or 0).." entries") end
    if uiElements.statusSendCache then uiElements.statusSendCache:SetText((counts.send or 0).." entries") end
    if uiElements.statusWhoNameCache then uiElements.statusWhoNameCache:SetText((counts.whoName or 0).." entries") end
    if uiElements.statusWhoZoneCache then uiElements.statusWhoZoneCache:SetText((counts.whoZone or 0).." entries") end
    if uiElements.statusInteractionCache then uiElements.statusInteractionCache:SetText((counts.interaction or 0).." entries") end
    if uiElements.statusSpvpCache then
        uiElements.statusSpvpCache:SetText((counts.spvpSalt or 0).." entries")
    end
    if uiElements.statusSpvpVerifiedCache then
        uiElements.statusSpvpVerifiedCache:SetText((counts.spvpVerified or 0).." entries")
    end
    if uiElements.statusSuppressionCache then
        uiElements.statusSuppressionCache:SetText((counts.suppression or 0).." entries")
    end

    -- RunPrivileged API Statistics
    if TRP3FW.privilegedCallStats then
        local stats = TRP3FW.privilegedCallStats
        local total = stats.total or 0
        local blocked = stats.blocked or 0
        local errors = stats.errors or 0
        local refunded = stats.refunded or 0
        local deferred = stats.deferred or 0
        local successful = total - errors

        local successRate = total > 0 and (successful / total * 100) or 0
        local blockRate = total > 0 and (blocked / total * 100) or 0

        if uiElements.statusPrivilegedTotal then
            uiElements.statusPrivilegedTotal:SetText(tostring(total))
        end
        if uiElements.statusPrivilegedSuccess then
            uiElements.statusPrivilegedSuccess:SetText(string.format("%d (%.1f%%)", successful, successRate))
        end
        if uiElements.statusPrivilegedBlocked then
            local color = blockRate > 10 and "|cffff0000" or "|cffffff00"
            uiElements.statusPrivilegedBlocked:SetText(string.format("%s%d (%.1f%%)|r", color, blocked, blockRate))
        end
        if uiElements.statusPrivilegedErrors then
            local color = errors > 0 and "|cffff0000" or "|cffffff00"
            uiElements.statusPrivilegedErrors:SetText(color..tostring(errors).."|r")
        end
        if uiElements.statusPrivilegedDeferred then
            local color = deferred > 0 and "|cffffff00" or "|cff888888"
            uiElements.statusPrivilegedDeferred:SetText(color..tostring(deferred).."|r")
        end
        if uiElements.statusPrivilegedRefunded then
            local color = refunded > 0 and "|cffffaa00" or "|cff888888"
            uiElements.statusPrivilegedRefunded:SetText(color..tostring(refunded).."|r")
        end
        if uiElements.statusPrivilegedBucket and TRP3FW.privilegedRate then
            local rate = TRP3FW.privilegedRate
            local storedTokens = rate.tokens or 0
            local lastRefill = rate.lastRefill or TRP3FW:GetCurrentTime()
            local now = TRP3FW:GetCurrentTime()
            local elapsed = now - lastRefill
            local currentTokens = math.min(10, storedTokens + (elapsed * 10))

            local tokens = math.floor(currentTokens * 10) / 10
            local color = tokens >= 7 and "|cff00ff00" or (tokens >= 4 and "|cffffaa00" or "|cffff0000")
            uiElements.statusPrivilegedBucket:SetText(string.format("%s%.1f/10|r", color, tokens))
        end
    end
    local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
    if hs then
        -- Subtract memory query overhead to avoid skewing performance metrics
        local totalDuration = debugprofilestop() - start
        local actualDuration = totalDuration - memoryQueryOverhead
        hs:RecordPerformance(actualDuration, "UI Refresh")
    end
end

local refreshing = false
function TRP3FW:RefreshUI()
    if refreshing or not settingsFrame or not settingsFrame:IsVisible() then refreshScheduled = false; return end
    refreshing = true

    if TRP3FW.TabManager.activeTab and TRP3FW.TabManager.activeTab.refresh then
        TRP3FW.TabManager.activeTab.refresh()
    end

    local p = self.Prefs or {}
    if uiElements.statusRefreshRate then uiElements.statusRefreshRate:SetValue(p.statusRefreshRate or 30); getglobal(uiElements.statusRefreshRate:GetName().."Text"):SetText("Refresh every " .. (p.statusRefreshRate or 30) .. " seconds") end

    local hasScanner = TRP3FW.detectedAddons.MapScanner or TRP3FW.detectedAddons.TRP3; local hasEpsilon = TRP3FW.hasEpsilonAPI

    -- Scan Reply Gating Logic
    local scanPhaseMode = p.scanResponsePhaseMode or "off"
    local scanMapMode = p.scanResponseMapMode or "off"
    local gatingActive = hasEpsilon and ((scanPhaseMode ~= "off") or (scanMapMode ~= "off"))

    local function setControlEnabled(control, enabled)
        if not control then return end
        if enabled then
            if control.Enable then control:Enable() end
            if control.EnableDropDown then control:EnableDropDown() end
            control:SetAlpha(1.0)
        else
            if control.Disable then control:Disable() end
            if control.DisableDropDown then control:DisableDropDown() end
            control:SetAlpha(0.5)
        end
    end

    if not hasScanner then
        setControlEnabled(uiElements.notifyOnScanResponse, false)
        setControlEnabled(uiElements.notifyOnScanAllow, false)
        setControlEnabled(uiElements.scanResponseRequireNonce, false)
        setControlEnabled(uiElements.scanResponseCacheEnabled, false)
        setControlEnabled(uiElements.scanResponseAllowCacheBypass, false)
        setControlEnabled(uiElements.scanResponseAllowGroupBypass, false)
        setControlEnabled(uiElements.scanResponsePhaseModeDropdown, false)
        setControlEnabled(uiElements.scanResponseWhoModeDropdown, false)
        setControlEnabled(uiElements.scanResponseWhitelistEnabled, false)
        setControlEnabled(uiElements.scanResponseWhitelistEdit, false)
        if uiElements.scanResponseWhitelistScroll then uiElements.scanResponseWhitelistScroll:SetAlpha(0.5) end
    else
        setControlEnabled(uiElements.notifyOnScanResponse, true)
        setControlEnabled(uiElements.scanResponsePhaseModeDropdown, hasEpsilon)
        setControlEnabled(uiElements.scanResponseWhoModeDropdown, hasEpsilon)

        setControlEnabled(uiElements.notifyOnScanAllow, gatingActive)
        setControlEnabled(uiElements.scanResponseRequireNonce, gatingActive)
        setControlEnabled(uiElements.scanResponseCacheEnabled, gatingActive)
        setControlEnabled(uiElements.scanResponseAllowCacheBypass, gatingActive)
        setControlEnabled(uiElements.scanResponseAllowGroupBypass, gatingActive)
        setControlEnabled(uiElements.scanResponseWhitelistEnabled, gatingActive)

        local wlEnabled = gatingActive and p.scanResponseWhitelistEnabled
        setControlEnabled(uiElements.scanResponseWhitelistEdit, wlEnabled)
        if uiElements.scanResponseWhitelistScroll then uiElements.scanResponseWhitelistScroll:SetAlpha(wlEnabled and 1 or 0.5) end
    end

    local checks = { "notifyEnabled", "notifyOnAllow", "notifyOnStartPhaseBlock", "notifyOnBroadcast", "notifyOnWhisper", "notifyOnScanResponse", "notifyOnScanAllow", "showInChat", "showGhostNotifications", "showOnScreen", "playSound", "showAddonSource", "showCacheInfo", "showCheckResults", "refreshSuppression", "allowGroupPhaseBypass", "useWhoQuery", "suppressAllWhoOutput", "blockStartPhase", "ghostOnStartPhase", "ghostProfileSwitch", "spvpEnabled", "spvpAutoInitialize", "filterGradients", "filterIcons", "filterMinimumFontSize", "monitorTRP3", "monitorMRP", "monitorXRP", "monitorMSP", "strictHookMode", "logHookConflicts", "abortOnMultipleRPAddons", "disableMapScanOnTRP3", "debug", "debugTimestamp", "redactEnabled", "redactNames", "redactLocations", "redactNetwork", "redactSPVP", "prepopulateWhoCache", "prepopulateWhoOnPhase", "prepopulateWhoOnZone", "phaseCheckBatchMode", "phaseCheckRefundOnNoChange", "trackHistory", "whitelistEnabled",
    "scanResponseRequireNonce", "scanResponseCacheEnabled", "scanResponseAllowCacheBypass", "scanResponseAllowGroupBypass", "scanResponseWhitelistEnabled",
    "clearCacheOnPhaseChange", "clearPhaseCheckOnPhaseChange", "clearAllowedSendersOnPhaseChange", "clearInteractionOnPhaseChange", "clearSuppressionOnPhaseChange", "clearRecentBroadcastsOnPhaseChange", "clearRecentScansOnPhaseChange", "clearWhoZoneOnPhaseChange", "clearWhoNameOnPhaseChange", "clearSpvpOnPhaseChange",
    "clearCacheOnZoneChange", "clearPhaseCheckOnZoneChange", "clearAllowedSendersOnZoneChange", "clearInteractionOnZoneChange", "clearSuppressionOnZoneChange", "clearRecentBroadcastsOnZoneChange", "clearRecentScansOnZoneChange", "clearWhoZoneOnZoneChange", "clearWhoNameOnZoneChange", "clearSpvpOnZoneChange",
    "debugChannel", "debugWhisper", "debugWho", "debugPhase", "debugCleanName", "debugLocation", "debugDecision", "debugHooks", "debugCache", "debugSend", "debugUI", "debugUtils", "debugSecurity", "debugGhost", "debugSPVP" }
    for _, k in ipairs(checks) do
        if uiElements[k] then
            local val = p[k]
            if val == nil then
                if TRP3FW.defaultSettings and TRP3FW.defaultSettings[k] ~= nil then
                    val = TRP3FW.defaultSettings[k]
                else
                    val = false
                end
            end
            uiElements[k]:SetChecked(val)
        end
    end

    local edits = { suppressionTime = 30, sendCacheDuration = 3600, sendCacheRefreshRate = 10, interactionCacheDuration = 600, interactionRefreshRate = 10, whoZoneCacheDuration = 45, whoNameCacheDuration = 180, whoZoneQueryCooldown = 20, whoCacheRefreshThreshold = 50, phaseCacheDuration = 300, phaseCacheFailureDuration = 10, scanCacheDuration = 300, scanCacheFailureDuration = 10, mapScanMinInterval = 60, phaseCacheRefreshThreshold = 20, spvpVerifiedCacheDuration = 300, spvpVerifiedRefreshRate = 50, spvpPhaseSaltRefreshRate = 50, cacheSizeLimit = 1000, phaseInDelay = 4, transitionGracePeriod = 10, validatedNamesCacheLimit = 5000, maxHistorySize = 100, privilegedReservedTokens = 2, privilegedLowPriorityThreshold = 4 }
    for k, d in pairs(edits) do if uiElements[k] then local v = p[k] or d; if k:find("Threshold") or k:find("RefreshRate") then if v < 1 then v = v * 100 end end; uiElements[k]:SetText(tostring(v)) end end

    if uiElements.validatedNamesCacheDuration then
        local seconds = p.validatedNamesCacheDuration or 604800
        uiElements.validatedNamesCacheDuration:SetText(tostring(math.floor(seconds / 86400)))
    end

    if uiElements.scanResponseWhitelistEdit then
        local enabled = p.scanResponseWhitelistEnabled
        if enabled then
            uiElements.scanResponseWhitelistEdit:Enable()
            uiElements.scanResponseWhitelistEdit:SetAlpha(1.0)
            if uiElements.scanResponseWhitelistScroll then uiElements.scanResponseWhitelistScroll:SetAlpha(1.0) end
        else
            uiElements.scanResponseWhitelistEdit:Disable()
            uiElements.scanResponseWhitelistEdit:SetAlpha(0.5)
            if uiElements.scanResponseWhitelistScroll then uiElements.scanResponseWhitelistScroll:SetAlpha(0.5) end
        end
        uiElements.scanResponseWhitelistEdit:SetText(p.scanResponseWhitelist or "")
    end
    if uiElements.whitelistEdit then
        if p.whitelistEnabled then
            uiElements.whitelistEdit:Enable()
            uiElements.whitelistEdit:SetAlpha(1.0)
            if uiElements.whitelistScroll then uiElements.whitelistScroll:SetAlpha(1.0) end
        else
            uiElements.whitelistEdit:Disable()
            uiElements.whitelistEdit:SetAlpha(0.5)
            if uiElements.whitelistScroll then uiElements.whitelistScroll:SetAlpha(0.5) end
        end
        uiElements.whitelistEdit:SetText(p.whitelistEntries or "")
    end
    if uiElements.ghostProfileWhitelistEdit then
        uiElements.ghostProfileWhitelistEdit:SetText(p.ghostProfileWhitelist or "")
        local wlEnabled = p.ghostProfileWhitelistEnabled
        if wlEnabled then uiElements.ghostProfileWhitelistEdit:Enable(); uiElements.ghostProfileWhitelistEdit:SetAlpha(1.0)
        else uiElements.ghostProfileWhitelistEdit:Disable(); uiElements.ghostProfileWhitelistEdit:SetAlpha(0.5) end
        if uiElements.ghostProfileWhitelistScroll then uiElements.ghostProfileWhitelistScroll:SetAlpha(wlEnabled and 1 or 0.5) end
    end

    local dropdownConfig = {
        phaseCheckMode = {
            ["off"] = "Off", ["statistics"] = "Statistics only", ["alert"] = "Notify only", ["block"] = "Block (silent)",
            ["ghost"] = "Send blank profile", ["alert_block"] = "Block (with notification)", ["alert_ghost"] = "Send blank profile (with notification)"
        },
        mapCheckMode = {
            ["off"] = "Off", ["statistics"] = "Statistics only", ["alert"] = "Notify only", ["block"] = "Block (silent)",
            ["ghost"] = "Send blank profile", ["alert_block"] = "Block (with notification)", ["alert_ghost"] = "Send blank profile (with notification)"
        },
        spvpMode = {
            ["off"] = "Off", ["optional"] = "Optional (Post-Check)", ["preferred"] = "Preferred (Pre-Check)", ["required"] = "Required (Strict)"
        },
        scanResponsePhaseMode = {
            ["off"] = "Off", ["statistics"] = "Statistics Only", ["alert"] = "Alert (send anyway)", ["block"] = "Block (silent)", ["alert_block"] = "Alert + Block"
        },
        scanResponseMapMode = {
            ["off"] = "Off", ["statistics"] = "Statistics Only", ["alert"] = "Alert (send anyway)", ["block"] = "Block (silent)", ["alert_block"] = "Alert + Block"
        },
        minimumFontSizeLevel = {
            ["h1"] = "H1 (Largest)", ["h2"] = "H2 (Large)", ["h3"] = "H3 (Medium)", ["p"] = "P (Normal)"
        }
    }

    for k, map in pairs(dropdownConfig) do
        if uiElements[k.."Dropdown"] then
            local val = p[k] or "off"
            if k == "minimumFontSizeLevel" and not p[k] then val = "h3" end
            local label = map[val] or val
            UIDropDownMenu_SetText(uiElements[k.."Dropdown"], label)
        end
    end

    if uiElements.complexityDropdown then
        local level = p.uiComplexityLevel or 2
        UIDropDownMenu_SetText(uiElements.complexityDropdown, COMPLEXITY_NAMES[level] or "Intermediate")
    end

    if uiElements.ghostProfileDropdown then
        local currentProfile = p.ghostProfileName or "TRP3FW_BLANK"
        if p.ghostProfileID then
            -- Try to resolve ID to name if available
            local profiles = TRP3FW.GetAllProfiles and TRP3FW:GetAllProfiles() or {}
            for _, profile in ipairs(profiles) do
                if profile.id == p.ghostProfileID then
                    currentProfile = profile.name
                    break
                end
            end
        end
        if currentProfile == "TRP3FW_BLANK" then
            UIDropDownMenu_SetText(uiElements.ghostProfileDropdown, "TRP3FW_BLANK |cff00ff00(Recommended)|r")
        else
            UIDropDownMenu_SetText(uiElements.ghostProfileDropdown, currentProfile)
        end
    end

    if uiElements.profileOverrides then for i, r in ipairs(uiElements.profileOverrides) do local e = (p.ghostProfileOverrides and p.ghostProfileOverrides[i]) or {}; if r.edit then r.edit:SetText(e.match or "") end; if r.dropdown then UIDropDownMenu_SetText(r.dropdown, e.profileName or "(Global)") end end end

    if uiElements.spvpBlockDurationSlider then
        uiElements.spvpBlockDurationSlider:SetValue(p.spvpBlockDuration or 60)
    end
    if uiElements.spvpSaltCacheDurationSlider then
        uiElements.spvpSaltCacheDurationSlider:SetValue(p.spvpSaltCacheDuration or 10800)
    end

    if uiElements.notificationModeSummaryNotify then
        local function modeText(val)
            local map = dropdownConfig.phaseCheckMode or {}
            return map[val] or "Off"
        end
        local function scanModeText(val)
            local map = dropdownConfig.scanResponsePhaseMode or {}
            return map[val] or "Off"
        end

        local phaseMode = p.phaseCheckMode or "alert"
        local mapMode = p.mapCheckMode or "alert"
        local whoText = "WHO: Default (user /who via UI; addon auto)"

        local lines = {}
        table.insert(lines, string.format("Profiles: Phase: %s   Map: %s   %s", modeText(phaseMode), modeText(mapMode), whoText))

        local scanPhaseMode = p.scanResponsePhaseMode or "off"
        local scanMapMode = p.scanResponseMapMode or "off"

        local gatingActive = hasScanner and (scanPhaseMode ~= "off" or scanMapMode ~= "off")

        if gatingActive then
            table.insert(lines, string.format("Scan reply: Phase: %s   Map: %s", scanModeText(scanPhaseMode), scanModeText(scanMapMode)))
        else
            table.insert(lines, "Scan reply: Protections off")
        end

        uiElements.notificationModeSummaryNotify:SetText(table.concat(lines, "\n"))
    end

    if uiElements.debugOutputDropdown then
        local text = "Chat"
        if p.debugOutputBoth then text = "Both"
        elseif p.debugOutputWindow then text = "Window"
        end
        UIDropDownMenu_SetText(uiElements.debugOutputDropdown, text)
    end

    if epsilonControls then
        local hasEpsilon = TRP3FW.hasEpsilonAPI
        for _, control in ipairs(epsilonControls) do
            if control then
                if control.SetShown then control:SetShown(hasEpsilon) end

                if hasEpsilon then
                    if control.Enable then control:Enable() end
                    if control.EnableDropDown then control:EnableDropDown() end
                    if control.SetAlpha then control:SetAlpha(1.0) end
                else
                    if control.Disable then control:Disable() end
                    if control.DisableDropDown then control:DisableDropDown() end
                    if control.SetAlpha then control:SetAlpha(0.5) end
                end
            end
        end
    end

    if uiElements.spvpSaltStatus then
        if TRP3FW.hasEpsilonAPI then
            local phaseID = TRP3FW:GetCurrentPhaseID()
            local phaseSalt = TRP3FW:GetPhaseSalt(phaseID, false)
            if phaseSalt and phaseSalt ~= "" then
                local _, timestamp = TRP3FW:ParsePhaseSalt(phaseSalt)
                local statusText
                if timestamp then
                    local daysOld = math.floor((time() - timestamp) / 86400)
                    local dateStr = date("%Y-%m-%d", timestamp)
                    if daysOld > 30 then
                        statusText = string.format("|cffffcc00✓ This phase is secured|r (Generated: %s, %d days old - |cffff6600rotation recommended|r)", dateStr, daysOld)
                    else
                        statusText = string.format("|cff00ff00✓ This phase is secured|r (Generated: %s, %d days old)", dateStr, daysOld)
                    end
                else
                    statusText = "|cff00ff00✓ This phase is secured|r (Legacy salt - rotation recommended)"
                end
                uiElements.spvpSaltStatus:SetText(statusText)
                if uiElements.spvpSecureButton then uiElements.spvpSecureButton:SetText("Rotate Security Key") end
            else
                uiElements.spvpSaltStatus:SetText("|cffff0000✗ This phase is NOT secured|r (No security key set)")
                if uiElements.spvpSecureButton then uiElements.spvpSecureButton:SetText("Secure This Phase") end
            end
            if uiElements.spvpSecureButton then
                local isOwner = C_Epsilon.IsOwner and C_Epsilon.IsOwner()
                local isOfficer = C_Epsilon.IsOfficer and C_Epsilon.IsOfficer()
                if isOwner or isOfficer then uiElements.spvpSecureButton:Enable() else uiElements.spvpSecureButton:Disable() end
            end
        else
            uiElements.spvpSaltStatus:SetText("|cffaaaaaa(Epsilon API not available)|r")
        end
    end

    if uiElements.minimumFontSizeDropdown then
        if p.filterMinimumFontSize then UIDropDownMenu_EnableDropDown(uiElements.minimumFontSizeDropdown); uiElements.minimumFontSizeDropdown:SetAlpha(1.0)
        else UIDropDownMenu_DisableDropDown(uiElements.minimumFontSizeDropdown); uiElements.minimumFontSizeDropdown:SetAlpha(0.5) end
    end

    -- Cache clearing granular logic
    local function setClearOptions(prefix, masterEnabled, hasEpsilon)
        local keys = { "clearPhaseCheckOn", "clearAllowedSendersOn", "clearInteractionOn", "clearSuppressionOn", "clearRecentBroadcastsOn", "clearRecentScansOn", "clearWhoZoneOn", "clearWhoNameOn", "clearSpvpOn" }
        local isPhase = (prefix == "Phase")
        local enabled = masterEnabled and (not isPhase or hasEpsilon)
        for _, k in ipairs(keys) do
            local key = k .. prefix .. "Change"
            if uiElements[key] then
                if enabled then uiElements[key]:Enable(); uiElements[key]:SetAlpha(1.0)
                else uiElements[key]:Disable(); uiElements[key]:SetAlpha(0.5) end
            end
        end
    end
    setClearOptions("Phase", p.clearCacheOnPhaseChange, hasEpsilon)
    setClearOptions("Zone", p.clearCacheOnZoneChange, true)

    -- Redaction granular logic
    local redactEnabled = p.redactEnabled
    local redactKeys = { "redactNames", "redactLocations", "redactNetwork", "redactSPVP" }
    for _, k in ipairs(redactKeys) do
        if uiElements[k] then
            if redactEnabled then uiElements[k]:Enable(); uiElements[k]:SetAlpha(1.0)
            else uiElements[k]:Disable(); uiElements[k]:SetAlpha(0.5) end
        end
    end

    -- WHO Prepopulation granular logic
    local prepopEnabled = p.prepopulateWhoCache ~= false
    if uiElements.prepopulateWhoOnPhase then
        if prepopEnabled then uiElements.prepopulateWhoOnPhase:Enable(); uiElements.prepopulateWhoOnPhase:SetAlpha(1.0)
        else uiElements.prepopulateWhoOnPhase:Disable(); uiElements.prepopulateWhoOnPhase:SetAlpha(0.5) end
    end
    if uiElements.prepopulateWhoOnZone then
        if prepopEnabled then uiElements.prepopulateWhoOnZone:Enable(); uiElements.prepopulateWhoOnZone:SetAlpha(1.0)
        else uiElements.prepopulateWhoOnZone:Disable(); uiElements.prepopulateWhoOnZone:SetAlpha(0.5) end
    end

    -- Debug category granular logic
    local debugEnabled = p.debug
    local debugCats = { "debugTimestamp", "debugChannel", "debugWhisper", "debugWho", "debugPhase", "debugCleanName", "debugLocation", "debugDecision", "debugHooks", "debugCache", "debugSend", "debugUI", "debugUtils", "debugSecurity", "debugGhost", "debugSPVP" }
    for _, k in ipairs(debugCats) do
        if uiElements[k] then
            if debugEnabled then uiElements[k]:Enable(); uiElements[k]:SetAlpha(1.0)
            else uiElements[k]:Disable(); uiElements[k]:SetAlpha(0.5) end
        end
    end

    if uiElements.epsilonWarning then uiElements.epsilonWarning:SetShown(not TRP3FW.hasEpsilonAPI) end

    UpdateUIComplexity()
    refreshing = false
end

RequestRefreshUI = function() if not refreshScheduled then refreshScheduled = true; C_Timer.After(0, function() refreshScheduled = false; TRP3FW:RefreshUI() end) end end

function TRP3FW:InitializeUI()
    if settingsFrame then return end
    TRP3FW.TabManager:LinkUI(uiElements, complexityWidgets, epsilonControls)
    TRP3FW:InitializeSettings(); InitializeMinimapSettings()
    settingsFrame = CreateFrame("Frame", "TRP3FW_PrefsFrame", UIParent, "BasicFrameTemplateWithInset")
    settingsFrame:SetSize(700, 550); settingsFrame:SetPoint("CENTER"); settingsFrame:SetMovable(true); settingsFrame:EnableMouse(true); settingsFrame:RegisterForDrag("LeftButton")
    settingsFrame:SetScript("OnDragStart", settingsFrame.StartMoving); settingsFrame:SetScript("OnDragStop", settingsFrame.StopMovingOrSizing); settingsFrame:Hide()
    self:CreateMinimapButton(); settingsFrame.title = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); settingsFrame.title:SetPoint("TOP", 0, -5); settingsFrame.title:SetText("TRP3 Firewall Settings v"..TRP3FW.VERSION)
    TRP3FW.TabManager:Initialize(settingsFrame); local tabs = {}
    for i, tabInfo in ipairs(TRP3FW.TabManager.orderedTabs) do
        local b = CreateFrame("Button", nil, settingsFrame); b:SetSize(88, 30); b:SetPoint("TOPLEFT", (i-1)*92+10, -30)
        b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
        b.text = b:CreateFontString(nil, "ARTWORK", "GameFontNormal"); b.text:SetPoint("CENTER"); b.text:SetText(tabInfo.name)
        b:SetScript("OnClick", function() TRP3FW.TabManager:SwitchToTab(tabInfo.id); for j, t in ipairs(tabs) do if j == i then t.bg:SetColorTexture(0.3, 0.3, 0.3, 1); t.text:SetTextColor(1, 1, 1) else t.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8); t.text:SetTextColor(0.7, 0.7, 0.7) end end end)
        tabs[i] = b
    end
    if #tabs > 0 then tabs[1]:GetScript("OnClick")(tabs[1]) end

    settingsFrame:HookScript("OnShow", function()
        local activeId = TRP3FW.TabManager.activeTab and TRP3FW.TabManager.activeTab.id
        for i, tabInfo in ipairs(TRP3FW.TabManager.orderedTabs) do
            local t = tabs[i]
            if t then
                local isActive = (tabInfo.id == activeId)
                t.bg:SetColorTexture(isActive and 0.3 or 0.2, isActive and 0.3 or 0.2, isActive and 0.3 or 0.2, isActive and 1.0 or 0.8)
                t.text:SetTextColor(isActive and 1 or 0.7, isActive and 1 or 0.7, isActive and 1 or 0.7)
            end
        end
        TRP3FW:RefreshUI()
    end)

    -- Bottom Buttons (skinned kit; Close is the gold primary action)
    local closeButton = TRP3FW.TabManager:CreateButton(settingsFrame, "Close", 100, true)
    closeButton:SetPoint("BOTTOMRIGHT", -10, 10)
    closeButton:SetOnClick(function()
        settingsFrame:Hide()
    end)

    local resetButton = TRP3FW.TabManager:CreateButton(settingsFrame, "Reset", 100, false)
    resetButton:SetPoint("RIGHT", closeButton, "LEFT", -10, 0)
    resetButton:SetOnClick(function()
        StaticPopup_Show("TRP3FW_RESET_CONFIRM")
    end)

    TRP3FW:RefreshUI()
    local ticker; TRP3FW.StartStatusUpdates = function() if ticker then ticker:Cancel() end; ticker = C_Timer.NewTicker(TRP3FW.Prefs.statusRefreshRate or 30, function() if settingsFrame:IsVisible() and TRP3FW.TabManager.activeTab and TRP3FW.TabManager.activeTab.id == "status" then TRP3FW:UpdateStatusTab() end end) end
    TRP3FW.StartStatusUpdates(); TRP3FW:Success("UI Initialized")
end

function TRP3FW:ToggleMinimapButton() if not TRP3FW.minimapButton then self:CreateMinimapButton() end; TRP3FW_MinimapSettings.hide = not TRP3FW_MinimapSettings.hide; if TRP3FW_MinimapSettings.hide then TRP3FW.minimapButton:Hide() else TRP3FW.minimapButton:Show() end end

-- Restore the minimap button to its default position/visibility.
-- Implements the function /trp3fw minimapreset expected but that was never defined
-- (the command always reported "not available"). Defaults match CreateMinimapButton's
-- first-run values (minimapPos 225, radius 80, shown).
function TRP3FW:ResetMinimapButton()
    if not TRP3FW_MinimapSettings then TRP3FW_MinimapSettings = {} end
    TRP3FW_MinimapSettings.minimapPos = 225
    TRP3FW_MinimapSettings.radius = 80
    TRP3FW_MinimapSettings.hide = false

    if not TRP3FW.minimapButton then self:CreateMinimapButton() end
    local b = TRP3FW.minimapButton
    if b then
        local r, d = TRP3FW_MinimapSettings.radius, TRP3FW_MinimapSettings.minimapPos
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(math.rad(d)) * r, math.sin(math.rad(d)) * r)
        b:Show()
    end
    self:Info("Minimap button reset to default position")
end

function TRP3FW:ShowWelcomeWizard()
    if TRP3FW.Prefs.complexitySetupDone then return end
    local f = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset"); f:SetSize(450, 420); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); f.title:SetPoint("TOP", 0, -10); f.title:SetText("Welcome to TRP3 Firewall")
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); t:SetPoint("TOP", 0, -60); t:SetText("Please select settings complexity level:")
    local levels = { {1, "Basic"}, {2, "Intermediate"}, {3, "Advanced"}, {4, "Everything"} }
    for i, l in ipairs(levels) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); b:SetSize(300, 40); b:SetPoint("TOP", 0, -100 - (i-1)*50); b:SetText(l[2])
        b:SetScript("OnClick", function()
            TRP3FW.Prefs.uiComplexityLevel = l[1]
            TRP3FW.Prefs.complexitySetupDone = true
            TRP3FW:EnforceComplexityDefaults(l[1])
            if settingsFrame then TRP3FW:RefreshUI() end
            f:Hide()
            -- Auto-open settings so the user knows where to configure (Phase 1 UX restructure 6.1)
            if settingsFrame then settingsFrame:Show() end
        end)
    end
    local skipBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    skipBtn:SetSize(200, 30); skipBtn:SetPoint("BOTTOM", 0, 15); skipBtn:SetText("Skip (Use Defaults)")
    skipBtn:SetScript("OnClick", function() TRP3FW.Prefs.complexitySetupDone = true; f:Hide() end)
end
