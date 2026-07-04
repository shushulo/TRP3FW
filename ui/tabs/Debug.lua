-- ui/tabs/Debug.lua
-- Cache & Debug settings tab for TRP3FW

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

local function CreateDebugTab(container)
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()

    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 3550)
    local uiElements = TabManager:GetUI()
    local y = -15

    local function setupEditBox(eb, key, min, max, isPercentage)
        local function save()
            local val = tonumber(eb:GetText())
            if val and (not min or val >= min) and (not max or val <= max) then
                if isPercentage then TRP3FW.Prefs[key] = val / 100
                else TRP3FW.Prefs[key] = val end
            else eb:SetText(tostring(TRP3FW.Prefs[key] or 0)) end
        end
        eb:SetScript("OnEnterPressed", function(self) save(); self:ClearFocus() end)
        eb:SetScript("OnEditFocusLost", save)
    end

    TabManager:CreateSectionHeader(content, "Profile Exchange Cache", y)
    y = y - 55
    uiElements.sendCacheDuration = TabManager:CreateEditBox(content, "Send Cache Duration (s)", "How long to remember allowed senders.", 80, "sendCacheDuration"); uiElements.sendCacheDuration:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.sendCacheDuration, "sendCacheDuration", 0)
    y = y - 55
    uiElements.sendCacheRefreshRate = TabManager:CreateEditBox(content, "Send Refresh Threshold (%)", "TTL percentage to trigger refresh.", 80, "sendCacheRefreshRate"); uiElements.sendCacheRefreshRate:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.sendCacheRefreshRate, "sendCacheRefreshRate", 0, 100, true)
    y = y - 75

    TabManager:CreateSectionHeader(content, "Interaction Cache", y)
    y = y - 55
    uiElements.interactionCacheDuration = TabManager:CreateEditBox(content, "Interaction Cache Duration (s)", "How long to keep interaction records.", 80, "interactionCacheDuration"); uiElements.interactionCacheDuration:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.interactionCacheDuration, "interactionCacheDuration", 0)
    y = y - 55
    uiElements.interactionRefreshRate = TabManager:CreateEditBox(content, "Interaction Refresh Threshold (%)", "TTL percentage to trigger refresh.", 80, "interactionRefreshRate"); uiElements.interactionRefreshRate:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.interactionRefreshRate, "interactionRefreshRate", 0, 100, true)
    y = y - 75

    TabManager:CreateSectionHeader(content, "WHO & Zone Cache", y)
    y = y - 55
    uiElements.whoZoneCacheDuration = TabManager:CreateEditBox(content, "WHO Zone Cache (s)", "How long to cache WHO zone results.", 80, "whoZoneCacheDuration"); uiElements.whoZoneCacheDuration:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.whoZoneCacheDuration, "whoZoneCacheDuration", 0)
    y = y - 55
    uiElements.whoNameCacheDuration = TabManager:CreateEditBox(content, "WHO Name Cache (s)", "How long to cache WHO name results.", 80, "whoNameCacheDuration"); uiElements.whoNameCacheDuration:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.whoNameCacheDuration, "whoNameCacheDuration", 0)
    y = y - 55
    uiElements.whoZoneQueryCooldown = TabManager:CreateEditBox(content, "Zone Query Cooldown (s)", "Min seconds between WHO queries.", 80, "whoZoneQueryCooldown"); uiElements.whoZoneQueryCooldown:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.whoZoneQueryCooldown, "whoZoneQueryCooldown", 0, 120)
    y = y - 55
    uiElements.whoCacheRefreshThreshold = TabManager:CreateEditBox(content, "WHO Refresh Threshold (%)", "TTL percentage to trigger refresh.", 80, "whoCacheRefreshThreshold"); uiElements.whoCacheRefreshThreshold:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.whoCacheRefreshThreshold, "whoCacheRefreshThreshold", 0, 100, true)
    y = y - 50

    uiElements.prepopulateWhoCache = TabManager:CreateCheckbox(content, "Prepopulate WHO Cache", "Run WHO queries automatically after area changes.", "prepopulateWhoCache"); uiElements.prepopulateWhoCache:SetPoint("TOPLEFT", 20, y)
    uiElements.prepopulateWhoCache:SetScript("OnClick", function(self) TRP3FW.Prefs.prepopulateWhoCache = self:GetChecked(); TRP3FW:RefreshUI() end)
    y = y - 35
    uiElements.prepopulateWhoOnPhase = TabManager:CreateCheckbox(content, "  On Phase Change", "Warp-up cache after scenario updates.", "prepopulateWhoOnPhase"); uiElements.prepopulateWhoOnPhase:SetPoint("TOPLEFT", 45, y)
    uiElements.prepopulateWhoOnPhase:SetScript("OnClick", function(self) TRP3FW.Prefs.prepopulateWhoOnPhase = self:GetChecked() end)
    y = y - 30
    uiElements.prepopulateWhoOnZone = TabManager:CreateCheckbox(content, "  On Zone Change", "Warm-up cache after zone changes.", "prepopulateWhoOnZone"); uiElements.prepopulateWhoOnZone:SetPoint("TOPLEFT", 45, y)
    uiElements.prepopulateWhoOnZone:SetScript("OnClick", function(self) TRP3FW.Prefs.prepopulateWhoOnZone = self:GetChecked() end)
    y = y - 65

    TabManager:CreateSectionHeader(content, "Phase & Scan Cache", y)
    y = y - 55
    uiElements.phaseCacheDuration = TabManager:CreateEditBox(content, "Phase Success TTL (s)", "Success cache duration.", 80, "phaseCacheDuration"); uiElements.phaseCacheDuration:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.phaseCacheDuration, "phaseCacheDuration", 0)
    y = y - 55
    uiElements.phaseCacheFailureDuration = TabManager:CreateEditBox(content, "Phase Failure TTL (s)", "Failure cache duration.", 80, "phaseCacheFailureDuration"); uiElements.phaseCacheFailureDuration:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.phaseCacheFailureDuration, "phaseCacheFailureDuration", 0)
    y = y - 55
    uiElements.scanCacheDuration = TabManager:CreateEditBox(content, "Scan Success TTL (s)", "Scan result duration.", 80, "scanCacheDuration"); uiElements.scanCacheDuration:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.scanCacheDuration, "scanCacheDuration", 0)
    y = y - 55
    uiElements.scanCacheFailureDuration = TabManager:CreateEditBox(content, "Scan Failure TTL (s)", "Failure cache duration.", 80, "scanCacheFailureDuration"); uiElements.scanCacheFailureDuration:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.scanCacheFailureDuration, "scanCacheFailureDuration", 0)
    y = y - 55
    uiElements.mapScanMinInterval = TabManager:CreateEditBox(content, "Min Scan Interval (s)", "Wait time between scans.", 100, "mapScanMinInterval"); uiElements.mapScanMinInterval:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.mapScanMinInterval, "mapScanMinInterval", 10, 600)
    y = y - 55
    uiElements.phaseCacheRefreshThreshold = TabManager:CreateEditBox(content, "Phase Refresh Threshold (%)", "TTL percentage to refresh.", 80, "phaseCacheRefreshThreshold"); uiElements.phaseCacheRefreshThreshold:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.phaseCacheRefreshThreshold, "phaseCacheRefreshThreshold", 0, 100, true)
    y = y - 75

    TabManager:CreateSectionHeader(content, "SPVP Cache Settings", y)
    y = y - 55
    uiElements.spvpVerifiedCacheDuration = TabManager:CreateEditBox(content, "Verification TTL (s)", "How long verification lasts.", 80, "spvpVerifiedCacheDuration"); uiElements.spvpVerifiedCacheDuration:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.spvpVerifiedCacheDuration, "spvpVerifiedCacheDuration", 10, 3600)
    y = y - 55
    uiElements.spvpVerifiedRefreshRate = TabManager:CreateEditBox(content, "Verification Refresh (%)", "TTL percentage to trigger re-check.", 80, "spvpVerifiedRefreshRate"); uiElements.spvpVerifiedRefreshRate:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.spvpVerifiedRefreshRate, "spvpVerifiedRefreshRate", 10, 90, true)
    y = y - 55
    uiElements.spvpPhaseSaltRefreshRate = TabManager:CreateEditBox(content, "Phase Salt Refresh (%)", "TTL percentage to refetch salt.", 80, "spvpPhaseSaltRefreshRate"); uiElements.spvpPhaseSaltRefreshRate:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.spvpPhaseSaltRefreshRate, "spvpPhaseSaltRefreshRate", 10, 90, true)
    y = y - 75

    TabManager:CreateSectionHeader(content, "Batching & Rate Limiting", y)
    y = y - 45
    uiElements.phaseCheckBatchMode = TabManager:CreateCheckbox(content, "Enable Phase Batching", "Bundle checks into single actions.", "phaseCheckBatchMode"); uiElements.phaseCheckBatchMode:SetPoint("TOPLEFT", 20, y)
    uiElements.phaseCheckBatchMode:SetScript("OnClick", function(self) TRP3FW.Prefs.phaseCheckBatchMode = self:GetChecked() end)
    y = y - 70

            local function setupSlider(slider, key, minVal, maxVal, step, formatStr)
                slider:SetMinMaxValues(minVal, maxVal); slider:SetValueStep(step); slider:SetObeyStepOnDrag(true); slider:SetValue(TRP3FW.Prefs[key] or minVal)
                local low, high, text = slider.Low or getglobal(slider:GetName().."Low"), slider.High or getglobal(slider:GetName().."High"), slider.Text or getglobal(slider:GetName().."Text")
                if low then low:SetText(tostring(minVal)) end
                if high then high:SetText(tostring(maxVal)) end
                slider:SetScript("OnValueChanged", function(self, value)
                    if step < 1 then value = math.floor(value * (1/step) + 0.5) / (1/step) else value = math.floor(value) end
                    TRP3FW.Prefs[key] = value
                    local displayVal = value; if key:find("Inter") then displayVal = value * 1000 end
                    local t = self.Text or getglobal(self:GetName().."Text")
                    if t then t:SetText(string.format(formatStr, displayVal)) end
                end)
                TabManager:AddComplexityWidget(slider, key)
            end

    local batchSize = CreateFrame("Slider", "TRP3FW_BatchSizeSlider", content, "OptionsSliderTemplate"); batchSize:SetPoint("TOPLEFT", 40, y); batchSize:SetWidth(200); setupSlider(batchSize, "phaseCheckBatchSize", 2, 10, 1, "Batch Size: %d"); uiElements.phaseCheckBatchSizeSlider = batchSize
    local batchDelay = CreateFrame("Slider", "TRP3FW_BatchDelaySlider", content, "OptionsSliderTemplate"); batchDelay:SetPoint("TOPLEFT", 280, y); batchDelay:SetWidth(200); setupSlider(batchDelay, "phaseCheckBatchDelay", 0.1, 2.0, 0.1, "Batch Delay: %.1fs"); uiElements.phaseCheckBatchDelaySlider = batchDelay
    y = y - 65
    local minBatch = CreateFrame("Slider", "TRP3FW_MinBatchSlider", content, "OptionsSliderTemplate"); minBatch:SetPoint("TOPLEFT", 40, y); minBatch:SetWidth(200); setupSlider(minBatch, "phaseCheckBatchMinSize", 2, 10, 1, "Min Batch Size: %d"); uiElements.phaseCheckBatchMinSizeSlider = minBatch
    local interDelay = CreateFrame("Slider", "TRP3FW_InterDelaySlider", content, "OptionsSliderTemplate"); interDelay:SetPoint("TOPLEFT", 280, y); interDelay:SetWidth(200); setupSlider(interDelay, "phaseCheckInterTargetDelay", 0.01, 0.2, 0.01, "Target Delay: %.0fms"); uiElements.phaseCheckInterTargetDelaySlider = interDelay
    y = y - 75

    uiElements.privilegedReservedTokens = TabManager:CreateEditBox(content, "API Reserved Tokens", "Reserved for HIGH priority.", 80, "privilegedReservedTokens"); uiElements.privilegedReservedTokens:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.privilegedReservedTokens, "privilegedReservedTokens", 0, 5)
    y = y - 55
    uiElements.privilegedLowPriorityThreshold = TabManager:CreateEditBox(content, "API Low Threshold", "Tokens needed for LOW priority.", 80, "privilegedLowPriorityThreshold"); uiElements.privilegedLowPriorityThreshold:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.privilegedLowPriorityThreshold, "privilegedLowPriorityThreshold", 2, 8)
    y = y - 50
    uiElements.phaseCheckRefundOnNoChange = TabManager:CreateCheckbox(content, "Refund Tokens on Fail", "Refund if target is missing.", "phaseCheckRefundOnNoChange"); uiElements.phaseCheckRefundOnNoChange:SetPoint("TOPLEFT", 20, y)
    uiElements.phaseCheckRefundOnNoChange:SetScript("OnClick", function(self) TRP3FW.Prefs.phaseCheckRefundOnNoChange = self:GetChecked() end)
    y = y - 75

    TabManager:CreateSectionHeader(content, "Cache Limits & Timing", y)
    y = y - 55
    uiElements.cacheSizeLimit = TabManager:CreateEditBox(content, "Global Cache Entry Limit", "Max entries per cache.", 80, "cacheSizeLimit"); uiElements.cacheSizeLimit:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.cacheSizeLimit, "cacheSizeLimit", 100, 10000)
    y = y - 55
    uiElements.phaseInDelay = TabManager:CreateEditBox(content, "Phase-In Delay (s)", "Wait time after phasing.", 80, "phaseInDelay"); uiElements.phaseInDelay:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.phaseInDelay, "phaseInDelay", 0, 10)
    y = y - 55
    uiElements.transitionGracePeriod = TabManager:CreateEditBox(content, "Transition Grace (s)", "Race condition protection window.", 80, "transitionGracePeriod"); uiElements.transitionGracePeriod:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.transitionGracePeriod, "transitionGracePeriod", 0, 30)
    y = y - 55
    uiElements.validatedNamesCacheDuration = TabManager:CreateEditBox(content, "Name Cache TTL (days)", "TTL for persistent names.", 80, "validatedNamesCacheDuration"); uiElements.validatedNamesCacheDuration:SetPoint("TOPLEFT", 20, y)

    local function saveNameTTL(self)
        local d = tonumber(self:GetText())
        if d and d >= 1 and d <= 30 then
            TRP3FW.Prefs.validatedNamesCacheDuration = d * 86400
        else
            local current = TRP3FW.Prefs.validatedNamesCacheDuration or 604800
            self:SetText(tostring(math.floor(current / 86400)))
        end
    end
    uiElements.validatedNamesCacheDuration:SetScript("OnEnterPressed", function(self) saveNameTTL(self); self:ClearFocus() end)
    uiElements.validatedNamesCacheDuration:SetScript("OnEditFocusLost", saveNameTTL)

    y = y - 55
    uiElements.validatedNamesCacheLimit = TabManager:CreateEditBox(content, "Name Cache Entry Limit", "Max persistent entries.", 80, "validatedNamesCacheLimit"); uiElements.validatedNamesCacheLimit:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.validatedNamesCacheLimit, "validatedNamesCacheLimit", 500, 10000)
    y = y - 75

    TabManager:CreateSectionHeader(content, "Area Change Cache Clearing", y)
    y = y - 45
    uiElements.clearCacheOnPhaseChange = TabManager:CreateCheckbox(content, "Clear All on Phase Change", "Master toggle for phase changes.", "clearCacheOnPhaseChange"); uiElements.clearCacheOnPhaseChange:SetPoint("TOPLEFT", 20, y)
    uiElements.clearCacheOnPhaseChange:SetScript("OnClick", function(self) TRP3FW.Prefs.clearCacheOnPhaseChange = self:GetChecked(); TRP3FW:RefreshUI() end)
    y = y - 35
    local pClear = { "clearPhaseCheckOnPhaseChange", "clearAllowedSendersOnPhaseChange", "clearInteractionOnPhaseChange", "clearSuppressionOnPhaseChange", "clearRecentBroadcastsOnPhaseChange", "clearRecentScansOnPhaseChange", "clearWhoZoneOnPhaseChange", "clearWhoNameOnPhaseChange", "clearSpvpOnPhaseChange" }
    local pLabels = { "  Phase Check Cache", "  Allowed Senders Cache", "  Interaction Cache", "  Suppression Timers", "  Recent Broadcasts", "  Recent Scans", "  WHO Zone Results", "  WHO Name Results", "  SPVP Handshakes" }
    for i, k in ipairs(pClear) do uiElements[k] = TabManager:CreateCheckbox(content, pLabels[i], "Clear on phase change.", k); uiElements[k]:SetPoint("TOPLEFT", 45, y); y = y - 30; uiElements[k]:SetScript("OnClick", function(self) TRP3FW.Prefs[k] = self:GetChecked() end) end
    y = y - 20
    uiElements.clearCacheOnZoneChange = TabManager:CreateCheckbox(content, "Clear All on Zone Change", "Master toggle for zone changes.", "clearCacheOnZoneChange"); uiElements.clearCacheOnZoneChange:SetPoint("TOPLEFT", 20, y)
    uiElements.clearCacheOnZoneChange:SetScript("OnClick", function(self) TRP3FW.Prefs.clearCacheOnZoneChange = self:GetChecked(); TRP3FW:RefreshUI() end)
    y = y - 35
    local zClear = { "clearPhaseCheckOnZoneChange", "clearAllowedSendersOnZoneChange", "clearInteractionOnZoneChange", "clearSuppressionOnZoneChange", "clearRecentBroadcastsOnZoneChange", "clearRecentScansOnZoneChange", "clearWhoZoneOnZoneChange", "clearWhoNameOnZoneChange", "clearSpvpOnZoneChange" }
    for i, k in ipairs(zClear) do uiElements[k] = TabManager:CreateCheckbox(content, pLabels[i]:gsub("Phase","Zone"), "Clear on zone change.", k); uiElements[k]:SetPoint("TOPLEFT", 45, y); y = y - 30; uiElements[k]:SetScript("OnClick", function(self) TRP3FW.Prefs[k] = self:GetChecked() end) end
    y = y - 65

    TabManager:CreateSectionHeader(content, "History & Redaction", y)
    y = y - 45
    uiElements.trackHistory = TabManager:CreateCheckbox(content, "Enable Event Tracking", "Save alerts/blocks to history.", "trackHistory"); uiElements.trackHistory:SetPoint("TOPLEFT", 20, y); uiElements.trackHistory:SetScript("OnClick", function(self) TRP3FW.Prefs.trackHistory = self:GetChecked() end)
    y = y - 55
    uiElements.maxHistorySize = TabManager:CreateEditBox(content, "Max Event Log Size", "Max history entries.", 80, "maxHistorySize"); uiElements.maxHistorySize:SetPoint("TOPLEFT", 20, y); setupEditBox(uiElements.maxHistorySize, "maxHistorySize", 10, 1000)
    y = y - 65
    uiElements.redactEnabled = TabManager:CreateCheckbox(content, "Enable Global Redaction", "Mask sensitive data in output.", "redactEnabled"); uiElements.redactEnabled:SetPoint("TOPLEFT", 20, y)
    uiElements.redactEnabled:SetScript("OnClick", function(self) TRP3FW.Prefs.redactEnabled = self:GetChecked(); TRP3FW:RefreshUI() end)
    y = y - 35
    local rKeys = { "redactNames", "redactLocations", "redactNetwork", "redactSPVP" }; local rLabels = { "  Redact Names/IDs", "  Redact Locations", "  Redact IPs/Network", "  Redact SPVP Keys" }
    for i, k in ipairs(rKeys) do uiElements[k] = TabManager:CreateCheckbox(content, rLabels[i], "Mask this category.", k); uiElements[k]:SetPoint("TOPLEFT", 45, y); y = y - 30; uiElements[k]:SetScript("OnClick", function(self) TRP3FW.Prefs[k] = self:GetChecked() end) end
    y = y - 65

    TabManager:CreateSectionHeader(content, "Advanced Debug Controls", y)
    y = y - 45
    uiElements.debug = TabManager:CreateCheckbox(content, "Master Debug Mode", "Display verbose technical logs.", "debug"); uiElements.debug:SetPoint("TOPLEFT", 20, y)
    uiElements.debug:SetScript("OnClick", function(self) TRP3FW.Prefs.debug = self:GetChecked(); TRP3FW:RefreshUI() end)
    y = y - 35
    uiElements.debugTimestamp = TabManager:CreateCheckbox(content, "  Prefix Timestamps", "Include server time in debug.", "debugTimestamp"); uiElements.debugTimestamp:SetPoint("TOPLEFT", 45, y)
    uiElements.debugTimestamp:SetScript("OnClick", function(self) TRP3FW.Prefs.debugTimestamp = self:GetChecked() end)
    y = y - 65

    local dOut = TabManager:CreateDropdown(content, "Debug Output Destination", "Target frame for logs.", 200, "debugOutputBoth"); dOut:SetPoint("TOPLEFT", 20, y); uiElements.debugOutputDropdown = dOut
    UIDropDownMenu_Initialize(dOut, function()
        local l = { {t="Chat", f=function() TRP3FW.Prefs.debugOutputChat=true; TRP3FW.Prefs.debugOutputWindow=false; TRP3FW.Prefs.debugOutputBoth=false end}, {t="Window", f=function() TRP3FW.Prefs.debugOutputChat=false; TRP3FW.Prefs.debugOutputWindow=true; TRP3FW.Prefs.debugOutputBoth=false end}, {t="Both", f=function() TRP3FW.Prefs.debugOutputChat=true; TRP3FW.Prefs.debugOutputWindow=true; TRP3FW.Prefs.debugOutputBoth=true end} }
        for _, it in ipairs(l) do local info = UIDropDownMenu_CreateInfo(); info.text=it.t; info.func=function() it.f(); UIDropDownMenu_SetText(dOut, it.t) end; UIDropDownMenu_AddButton(info) end
    end); y = y - 50

    -- Debug Window toggle button
    local debugWindowButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    debugWindowButton:SetSize(150, 22)
    debugWindowButton:SetPoint("TOPLEFT", 40, y)
    debugWindowButton:SetText("Toggle Debug Window")
    debugWindowButton:SetScript("OnClick", function()
        if TRP3FW.ToggleDebugWindow then
            TRP3FW:ToggleDebugWindow()
        else
            TRP3FW:Warn("Debug window not loaded yet")
        end
    end)
    y = y - 50

    local dCats = { "debugChannel", "debugWhisper", "debugWho", "debugPhase", "debugCleanName", "debugLocation", "debugDecision", "debugHooks", "debugCache", "debugSend", "debugUI", "debugUtils", "debugSecurity", "debugGhost", "debugSPVP" }
    local dLabels = { "Channel", "Whisper", "WHO", "Phase", "Names", "Location", "Decision", "Hooks", "Cache", "Send", "UI", "Utils", "Security", "Ghost", "SPVP" }
    for i, k in ipairs(dCats) do
        uiElements[k] = TabManager:CreateCheckbox(content, dLabels[i].." Verbosity", "Toggle logs.", k); uiElements[k]:SetPoint("TOPLEFT", 20, y); y = y - 30; uiElements[k]:SetScript("OnClick", function(self) TRP3FW.Prefs[k] = self:GetChecked() end)
        if i % 3 == 0 then y = y - 10 end
    end

    y = y - 15
    TabManager:CreateSectionHeader(content, "Addon Monitoring", y)
    y = y - 40
    uiElements.monitorTRP3 = TabManager:CreateCheckbox(content, "Monitor Total RP 3", "Enable protections for TRP3.", "monitorTRP3")
    uiElements.monitorTRP3:SetPoint("TOPLEFT", 20, y)
    uiElements.monitorTRP3:SetScript("OnClick", function(self) TRP3FW.Prefs.monitorTRP3 = self:GetChecked() end)
    y = y - 30

    uiElements.monitorMRP = TabManager:CreateCheckbox(content, "Monitor MyRolePlay", "Enable protections for MRP.", "monitorMRP")
    uiElements.monitorMRP:SetPoint("TOPLEFT", 20, y)
    uiElements.monitorMRP:SetScript("OnClick", function(self) TRP3FW.Prefs.monitorMRP = self:GetChecked() end)
    y = y - 30

    uiElements.monitorXRP = TabManager:CreateCheckbox(content, "Monitor XRP", "Enable protections for XRP.", "monitorXRP")
    uiElements.monitorXRP:SetPoint("TOPLEFT", 20, y)
    uiElements.monitorXRP:SetScript("OnClick", function(self) TRP3FW.Prefs.monitorXRP = self:GetChecked() end)
    y = y - 30

    uiElements.monitorMSP = TabManager:CreateCheckbox(content, "Monitor MSP/Other", "Monitor other compatible addons.", "monitorMSP")
    uiElements.monitorMSP:SetPoint("TOPLEFT", 20, y)
    uiElements.monitorMSP:SetScript("OnClick", function(self) TRP3FW.Prefs.monitorMSP = self:GetChecked() end)
    y = y - 45

    TabManager:CreateSectionHeader(content, "Hook Safety", y)
    y = y - 40
    uiElements.strictHookMode = TabManager:CreateCheckbox(content, "Strict hook mode", "Refuse to install when another addon hooks core functions.", "strictHookMode")
    uiElements.strictHookMode:SetPoint("TOPLEFT", 20, y)
    uiElements.strictHookMode:SetScript("OnClick", function(self) TRP3FW.Prefs.strictHookMode = self:GetChecked() end)
    y = y - 30

    uiElements.logHookConflicts = TabManager:CreateCheckbox(content, "Log hook conflicts", "Warn when hooks are already wrapped.", "logHookConflicts")
    uiElements.logHookConflicts:SetPoint("TOPLEFT", 20, y)
    uiElements.logHookConflicts:SetScript("OnClick", function(self) TRP3FW.Prefs.logHookConflicts = self:GetChecked() end)
    y = y - 30

    uiElements.abortOnMultipleRPAddons = TabManager:CreateCheckbox(content, "Abort on multiple RP addons", "Disable TRP3FW if multiple RP addons detected.", "abortOnMultipleRPAddons")
    uiElements.abortOnMultipleRPAddons:SetPoint("TOPLEFT", 20, y)
    uiElements.abortOnMultipleRPAddons:SetScript("OnClick", function(self) TRP3FW.Prefs.abortOnMultipleRPAddons = self:GetChecked() end)
    y = y - 30

    uiElements.disableMapScanOnTRP3 = TabManager:CreateCheckbox(content, "Disable map scan when TRP3 + RPMapScan", "Skip map-scan hooks in this specific combo.", "disableMapScanOnTRP3")
    uiElements.disableMapScanOnTRP3:SetPoint("TOPLEFT", 20, y)
    uiElements.disableMapScanOnTRP3:SetScript("OnClick", function(self) TRP3FW.Prefs.disableMapScanOnTRP3 = self:GetChecked() end)

    return scrollFrame
end

TabManager:RegisterTab("debug", "Advanced", "Advanced Settings", CreateDebugTab, function() TRP3FW:RefreshUI() end, "Interface\\Icons\\Trade_Engineering")
