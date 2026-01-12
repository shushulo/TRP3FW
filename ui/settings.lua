-- ui/settings.lua
-- Settings UI with tabs

local addonName, TRP3FW = ...

-- Helper to determine if changing to a more restrictive mode requires clearing the allowedSenders cache
local function ShouldClearAllowedSenders(newMode, previousMode)
    local restrictiveModes = {
        ["block"] = true,
        ["ghost"] = true,
        ["alert_block"] = true,
        ["alert_ghost"] = true,
        ["off"] = false, -- Explicitly not restrictive
        ["statistics"] = false,
        ["alert"] = false,
    }
    -- Clear if newMode is restrictive AND previousMode was not restrictive
    return restrictiveModes[newMode] and not restrictiveModes[previousMode]
end

-- UI element references (defined early so popups capture the local table)
local uiElements = {}
local RequestRefreshUI

-- Complexity Levels
local COMPLEXITY = {
    BASIC = 1,
    INTERMEDIATE = 2,
    ADVANCED = 3,
    EVERYTHING = 4
}

local COMPLEXITY_NAMES = {
    [1] = "Basic",
    [2] = "Intermediate",
    [3] = "Advanced",
    [4] = "Everything"
}

-- UI Widgets managed by complexity system
local complexityWidgets = {}

    -- Mapping setting keys to complexity levels
local SETTING_LEVELS = {
    -- Basic
    notifyEnabled = 1,
    showInChat = 1,
    showOnScreen = 1,
    playSound = 1,
    suppressionTime = 1,
    phaseCheckMode = 1,
    mapCheckMode = 1,
    whitelistEnabled = 1,
    whitelistEntries = 1,

    -- Intermediate
    notifyOnAllow = 2,
    notifyOnStartPhaseBlock = 2,
    notifyOnWhisper = 2,
    notifyOnBroadcast = 2,
    showGhostNotifications = 2,
    showAddonSource = 2,
    showCacheInfo = 2,
    allowGroupPhaseBypass = 2,
    blockStartPhase = 2,
    ghostOnStartPhase = 2,
    ghostProfileSwitch = 2,
    ghostProfileName = 2,
    filterGradients = 2,
    filterMinimumFontSize = 2,
    minimumFontSizeLevel = 2,
    trackHistory = 2,

    -- Advanced
    refreshSuppression = 3,
    notifyOnScanResponse = 3,
    notifyOnScanAllow = 3,
    showCheckResults = 3,
    ghostProfileWhitelistEnabled = 3,
    ghostProfileWhitelist = 3,
    ghostProfileOverrides = 3,
    suppressAllWhoOutput = 3,
    monitorTRP3 = 3,
    monitorMRP = 3,
    monitorXRP = 3,
    monitorMSP = 3,
    abortOnMultipleRPAddons = 3,
    disableMapScanOnTRP3 = 3,
    performanceHistoryEnabled = 3,
    phaseInDelay = 3,
    transitionGracePeriod = 3,
    redactLocations = 3,
    redactNetwork = 3,
    redactSPVP = 3,
    cacheSizeLimit = 3,
    mapScanMinInterval = 3, -- Moved from Everything
    whoZoneQueryCooldown = 3, -- Moved from Everything

    -- Batching settings (related to phaseCheckBatchMode, Advanced)
    phaseCheckBatchMode = 3,
    phaseCheckBatchSize = 3,
    phaseCheckBatchDelay = 3,
    phaseCheckBatchMinSize = 3,
    phaseCheckBatchInterDelay = 3,

    -- SPVP settings (Advanced)
    spvpMode = 3,
    spvpAutoInitialize = 3,
    spvpBlockDuration = 3,
    spvpSaltCacheDuration = 3,
    spvpVerifiedCacheDuration = 3,
    spvpVerifiedRefreshRate = 3,
    spvpPhaseSaltRefreshRate = 4,

    -- Everything (Default for unmatched, and explicitly listed for clarity)
    phaseCheckRefundOnNoChange = 4,
    privilegedReservedTokens = 4,
    privilegedLowPriorityThreshold = 4,
    
    -- All debug, cache durations, specific scan reply protocols, etc. (will default to 4 if not listed here)
}
-- Widgets with custom Enable/Disable logic in RefreshUI
local CUSTOM_LOGIC_KEYS = {
    minimumFontSizeLevel = true,
    clearPhaseCheckOnPhaseChange = true, clearAllowedSendersOnPhaseChange = true, clearInteractionOnPhaseChange = true, 
    clearSuppressionOnPhaseChange = true, clearRecentBroadcastsOnPhaseChange = true, clearRecentScansOnPhaseChange = true,
    clearWhoZoneOnPhaseChange = true, clearWhoNameOnPhaseChange = true,
    clearPhaseCheckOnZoneChange = true, clearAllowedSendersOnZoneChange = true, clearInteractionOnZoneChange = true, 
    clearSuppressionOnZoneChange = true, clearRecentBroadcastsOnZoneChange = true, clearRecentScansOnZoneChange = true,
    clearWhoZoneOnZoneChange = true, clearWhoNameOnZoneChange = true,
    debugTimestamp = true, debugChannel = true, debugWhisper = true, debugWho = true, debugPhase = true, debugCleanName = true,
    debugLocation = true, debugDecision = true, debugHooks = true, debugCache = true, debugSend = true, debugUI = true,
    debugUtils = true, debugSecurity = true, debugGhost = true, debugSPVP = true,
    scanResponseRequireNonce = true, scanResponseCacheEnabled = true, scanResponseAllowCacheBypass = true, 
    scanResponseAllowGroupBypass = true, scanResponseWhitelistEnabled = true, scanResponseWhitelistEdit = true, 
    scanResponseWhitelistScroll = true, scanResponsePhaseMode = true, scanResponseMapMode = true, 
    notifyOnScanResponse = true, notifyOnScanAllow = true,
    redactNames = true, redactLocations = true, redactNetwork = true, redactSPVP = true,
    ghostProfileWhitelistEdit = true, ghostProfileWhitelistScroll = true,
    spvpSaltStatus = true, spvpSecureButton = true, spvpBlockDurationSlider = true, spvpSaltCacheDurationSlider = true
}

-- Function to update UI based on complexity level
local function UpdateUIComplexity()
    if not TRP3FW_Settings then return end
    local currentLevel = TRP3FW_Settings.uiComplexityLevel or 2
    local shouldRefresh = false
    
    for _, widget in ipairs(complexityWidgets) do
        local wLevel = widget.complexityLevel or 4
        local enabled = wLevel <= currentLevel
        
        local hasCustomLogic = widget.settingKey and CUSTOM_LOGIC_KEYS[widget.settingKey]
        
        -- Apply visual state
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
    
    if shouldRefresh and RequestRefreshUI then
        RequestRefreshUI()
    end
end

-- Enforce defaults for settings hidden by the new complexity level
function TRP3FW:EnforceComplexityDefaults(newLevel)
    if not TRP3FW_Settings or not TRP3FW.defaultSettings then return end
    local shouldRefresh = false
    
    for _, widget in ipairs(complexityWidgets) do
        local wLevel = widget.complexityLevel or 4
        -- If widget is becoming (or staying) hidden
        if wLevel > newLevel then
            if widget.settingKey then
                local key = widget.settingKey
                local default = TRP3FW.defaultSettings[key]
                local current = TRP3FW_Settings[key]
                
                -- Reset non-default values to default
                if default ~= nil and current ~= default then
                    TRP3FW_Settings[key] = default
                    TRP3FW:Debug("[Complexity] Reset hidden setting '"..key.."' to default", "ui")
                    shouldRefresh = true
                end
            end
        end
    end
    
    if shouldRefresh and RequestRefreshUI then
        RequestRefreshUI()
    end
end

-- Helper function to ensure blank profiles exist and are valid when ghost mode is enabled
local function EnsureBlankProfilesExist()
    -- Only create if ANY ghost mode setting is enabled
    local ghostModeEnabled = TRP3FW:IsGhostModeEnabled()

    if not ghostModeEnabled then
        return
    end

    -- Create/validate TRP3 blank profile
    if TRP3_API and TRP3_Profiles then
        local success, err = pcall(TRP3FW.CreateBlankProfile_TRP3, TRP3FW)
        if success then
            TRP3FW:Debug("[UI] Validated TRP3 blank profile", "ui")
        else
            TRP3FW:Warn("Failed to create TRP3 blank profile: " .. tostring(err))
        end
    end

    -- Create/validate MRP blank profile
    if mrp and mrpSaved then
        local success, err = pcall(TRP3FW.CreateBlankProfile_MRP, TRP3FW)
        if success then
            TRP3FW:Debug("[UI] Validated MRP blank profile", "ui")
        else
            TRP3FW:Warn("Failed to create MRP blank profile: " .. tostring(err))
        end
    end

    -- Create/validate XRP blank profile
    if AddOn_XRP and xrpSaved then
        local success, err = pcall(TRP3FW.CreateBlankProfile_XRP, TRP3FW)
        if success then
            TRP3FW:Debug("[UI] Validated XRP blank profile", "ui")
        else
            TRP3FW:Warn("Failed to create XRP blank profile: " .. tostring(err))
        end
    end
end

-- StaticPopup dialog for profile name change warning
StaticPopupDialogs["TRP3FW_CHANGE_PROFILE_NAME"] = {
    text = "|cffff6600WARNING:|r You are about to change the ghost profile name from the default 'TRP3FW_BLANK' to '%s'.\n\n|cffff0000This is NOT recommended unless you know what you're doing.|r\n\nThe default 'TRP3FW_BLANK' profile is automatically validated to ensure it's truly blank. Custom profile names bypass some safety checks.\n\nAre you sure you want to make this change?",
    button1 = "Yes, Change It",
    button2 = "Cancel",
    OnAccept = function(self, data)
        TRP3FW_Settings.ghostProfileName = data
        TRP3FW:Info("Profile switch set to: " .. data)
        -- Update the dropdown UI
        if uiElements and uiElements.ghostProfileDropdown then
            UIDropDownMenu_SetText(uiElements.ghostProfileDropdown, data)
        end
    end,
    OnCancel = function(self, data)
        -- Revert the dropdown to current setting
        if uiElements and uiElements.ghostProfileDropdown then
            local current = TRP3FW_Settings.ghostProfileName or "TRP3FW_BLANK"
            if current == "TRP3FW_BLANK" then
                UIDropDownMenu_SetText(uiElements.ghostProfileDropdown, "TRP3FW_BLANK |cff00ff00(Recommended)|r")
            else
                UIDropDownMenu_SetText(uiElements.ghostProfileDropdown, current)
            end
        end
        TRP3FW:Info("Profile name change cancelled")
    end,
    hideOnEscape = 1,
    timeout = 0,
    whileDead = 1,
    showAlert = 1,
}

StaticPopupDialogs["TRP3FW_RESET_CONFIRM"] = {
    text = "|cffff0000WARNING:|r Are you sure you want to reset ALL settings to defaults?\n\nThis action cannot be undone.",
    button1 = "Yes, Reset Everything",
    button2 = "Cancel",
    OnAccept = function()
        TRP3FW_Settings = {}
        TRP3FW:InitializeSettings()
        RequestRefreshUI()
        TRP3FW:Info("All settings reset to defaults")
    end,
    hideOnEscape = 1,
    timeout = 0,
    whileDead = 1,
    showAlert = 1,
}

StaticPopupDialogs["TRP3FW_WHITELIST_CONFIRM"] = {
    text = "|cffff0000Security warning:|r Enabling the whitelist bypass will send your |cffffff00active profile|r to listed players without phase/map checks, alerts, blocking, or ghost mode (even in start phase).\n\nOnly use this if you fully trust everyone on the list.",
    button1 = "Allow Bypass",
    button2 = "Cancel",
    OnAccept = function()
        TRP3FW_Settings.whitelistEnabled = true
        TRP3FW:RefreshWhitelistCache()
        if uiElements and uiElements.whitelistBypassEnabled then
            uiElements.whitelistBypassEnabled:SetChecked(true)
        end
        if uiElements and uiElements.whitelistEdit then
            uiElements.whitelistEdit:SetEnabled(true)
            uiElements.whitelistEdit:SetAlpha(1)
        end
        if uiElements and uiElements.whitelistScroll then
            uiElements.whitelistScroll:SetAlpha(1)
        end
    end,
    OnCancel = function()
        TRP3FW_Settings.whitelistEnabled = false
        TRP3FW:RefreshWhitelistCache()
        if uiElements and uiElements.whitelistBypassEnabled then
            uiElements.whitelistBypassEnabled:SetChecked(false)
        end
        if uiElements and uiElements.whitelistEdit then
            uiElements.whitelistEdit:SetEnabled(false)
            uiElements.whitelistEdit:SetAlpha(0.5)
        end
        if uiElements and uiElements.whitelistScroll then
            uiElements.whitelistScroll:SetAlpha(0.5)
        end
    end,
    hideOnEscape = 1,
    timeout = 0,
    whileDead = 1,
    showAlert = 1,
}

StaticPopupDialogs["TRP3FW_SPVP_ROTATE_CONFIRM"] = {
    text = "|cffffcc00Rotate SPVP Security Key?|r\n\nThis phase already has a security key. Rotating it will:\n\n• Generate a new cryptographic salt\n• Invalidate all existing SPVP verifications\n• Require players to re-verify with the new key\n\nOnly rotate if you suspect the current key is compromised or want to refresh security.",
    button1 = "Rotate Key",
    button2 = "Cancel",
    OnAccept = function()
        TRP3FW:SecureCurrentPhase()
        if RequestRefreshUI then
            RequestRefreshUI()
        end
    end,
    hideOnEscape = 1,
    timeout = 0,
    whileDead = 1,
    showAlert = 1,
}

-- Main settings frame
local settingsFrame

local epsilonControls = {}
local refreshScheduled = false
local cacheCountState = {
    timestamp = 0,
    counts = nil
}

-- Minimap button
local minimapButton

-- Initialize minimap settings (saved globally)
local function InitializeMinimapSettings()
    if not TRP3FW_MinimapSettings then
        TRP3FW_MinimapSettings = {
            hide = false,
            minimapPos = 225,
            radius = 80,
        }
    end
    -- Ensure all keys exist (migration-safe)
    if TRP3FW_MinimapSettings.minimapPos == nil then TRP3FW_MinimapSettings.minimapPos = 225 end
    if TRP3FW_MinimapSettings.radius == nil then TRP3FW_MinimapSettings.radius = 80 end
    if TRP3FW_MinimapSettings.hide == nil then TRP3FW_MinimapSettings.hide = false end
end

-- Helper function to create section headers
local function CreateSectionHeader(parent, text, yOffset)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 20, yOffset)
    header:SetText(text)
    header:SetTextColor(0, 1, 1) -- Cyan

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -5)
    line:SetPoint("RIGHT", parent, -20, 0)
    line:SetColorTexture(0.3, 0.3, 0.3, 1)

    return header
end

-- Helper function to create checkboxes
local function AppendDefaultToTooltip(tooltipText, settingKey, level)
    local text = tooltipText or ""
    
    -- Append default value
    if settingKey and TRP3FW and TRP3FW.defaultSettings then
        local defaultVal = TRP3FW.defaultSettings[settingKey]
        if defaultVal ~= nil then
            local suffix
            if type(defaultVal) == "boolean" then
                suffix = defaultVal and "Default: On." or "Default: Off."
            elseif type(defaultVal) == "number" then
                if settingKey == "validatedNamesCacheDuration" then
                    local days = math.floor(defaultVal / 86400)
                    suffix = string.format("Default: %d days.", days)
                else
                    suffix = string.format("Default: %s.", tostring(defaultVal))
                end
            else
                suffix = "Default set."
            end
            
            if text ~= "" then
                text = text .. " " .. suffix
            else
                text = suffix
            end
        end
    end
    
    -- Append Complexity Level
    if level and level > 1 then
        local color = "00ff00" -- Basic/Green (unused here as >1)
        if level == 2 then color = "ffff00" -- Intermediate/Yellow
        elseif level == 3 then color = "ff8800" -- Advanced/Orange
        elseif level == 4 then color = "ff0000" -- Everything/Red
        end
        
        local levelName = COMPLEXITY_NAMES[level] or "Unknown"
        text = text .. string.format("\n|cff%s[%s Setting]|r", color, levelName)
    end
    
    return text
end

-- Helper function to create checkboxes
local function CreateCheckbox(parent, labelText, tooltipText, settingKey)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)

    local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 5, 0)
    label:SetText(labelText)
    check.label = label -- Store reference for dimming

    -- Complexity handling
    local level = SETTING_LEVELS[settingKey] or 4 -- Default to Everything if unknown
    check.complexityLevel = level
    check.settingKey = settingKey
    table.insert(complexityWidgets, check)

    local tooltip = AppendDefaultToTooltip(tooltipText, settingKey, level)
    if tooltipText or level > 1 then
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end

    return check
end

-- Helper function to create text input boxes with labels
local function CreateEditBox(parent, labelText, tooltipText, width, settingKey)
    width = width or 100

    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetText(labelText)

    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetSize(width, 20)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)
    editBox:SetMaxLetters(6)
    editBox.label = label -- Store reference

    -- Position label above editbox
    label:SetPoint("BOTTOMLEFT", editBox, "TOPLEFT", 0, 5)

    -- Complexity handling
    local level = SETTING_LEVELS[settingKey] or 4
    editBox.complexityLevel = level
    editBox.settingKey = settingKey
    table.insert(complexityWidgets, editBox)

    local tooltip = AppendDefaultToTooltip(tooltipText, settingKey, level)
    if tooltipText or level > 1 then
        editBox:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        editBox:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end

    return editBox, label
end

-- Helper function to create dropdown menus
local function CreateDropdown(parent, labelText, tooltipText, width, settingKey)
    width = width or 200

    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetText(labelText)

    local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dropdown, width)
    dropdown.label = label -- Store reference

    -- Position label above dropdown
    label:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 20, 5)

    -- Complexity handling
    local level = (settingKey and SETTING_LEVELS[settingKey]) or 4
    dropdown.complexityLevel = level
    dropdown.settingKey = settingKey
    
    -- Method shims for uniform handling
    dropdown.EnableDropDown = function(self) UIDropDownMenu_EnableDropDown(self) end
    dropdown.DisableDropDown = function(self) UIDropDownMenu_DisableDropDown(self) end
    
    table.insert(complexityWidgets, dropdown)

    local tooltip = AppendDefaultToTooltip(tooltipText, settingKey, level)
    if tooltipText or level > 1 then
        dropdown:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        dropdown:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end

    return dropdown, label
end

-- Helper function to create tab buttons
local function CreateTab(parent, index, text)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(110, 30)  -- Reduced from 120 to 110
    tab:SetPoint("TOPLEFT", (index - 1) * 115 + 10, -30)  -- Reduced spacing from 125 to 115

    -- Background
    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)

    -- Highlight
    tab.highlight = tab:CreateTexture(nil, "HIGHLIGHT")
    tab.highlight:SetAllPoints()
    tab.highlight:SetColorTexture(0.3, 0.3, 0.3, 0.5)

    -- Text
    tab.text = tab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    tab.text:SetPoint("CENTER")
    tab.text:SetText(text)

    return tab
end

-- Helper function to create scroll frame for tab content
local function CreateScrollFrame(parent, contentHeight)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -70)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    -- Set height based on actual content, default to 1000 if not specified
    scrollChild:SetSize(scrollFrame:GetWidth(), contentHeight or 1000)
    scrollFrame:SetScrollChild(scrollChild)

    return scrollFrame, scrollChild
end

-- Helper function to create a progress bar with color coding
local function CreateProgressBar(parent, width, height)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, height or 20)

    -- Background
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    bar.bg = bg

    -- Progress fill
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT")
    fill:SetHeight(height or 20)
    fill:SetColorTexture(0, 1, 0, 0.8)  -- Default green
    bar.fill = fill

    -- Border
    local border = bar:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetColorTexture(0.5, 0.5, 0.5, 0.3)
    border:SetDrawLayer("OVERLAY", 7)

    -- Text overlay
    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    bar.text = text

    -- Update function
    function bar:SetValue(percent, displayText)
        percent = math.max(0, math.min(100, percent))

        -- Set fill width
        local fillWidth = (width * percent) / 100
        self.fill:SetWidth(fillWidth)

        -- Color code based on percentage
        if percent >= 80 then
            self.fill:SetColorTexture(0, 0.8, 0, 0.8)  -- Green
        elseif percent >= 50 then
            self.fill:SetColorTexture(1, 0.8, 0, 0.8)  -- Yellow
        else
            self.fill:SetColorTexture(0.9, 0.2, 0, 0.8)  -- Red
        end

        -- Set text
        if displayText then
            self.text:SetText(displayText)
        else
            self.text:SetText(string.format("%.1f%%", percent))
        end
    end

    return bar
end

-- Helper function to create a stat card (box with background)
local function CreateStatCard(parent, width, height)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(width, height)

    -- Background
    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.15, 0.18, 0.9)

    -- Border (using BackdropTemplate for 9.0+ compatibility)
    local border = CreateFrame("Frame", nil, card, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    border:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

    -- Title
    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -8)
    title:SetTextColor(0.7, 0.7, 0.7)
    card.title = title

    -- Value (large number)
    local value = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    value:SetPoint("CENTER", 0, -5)
    card.value = value

    -- Subtext
    local subtext = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtext:SetPoint("BOTTOM", 0, 8)
    subtext:SetTextColor(0.6, 0.6, 0.6)
    card.subtext = subtext

    return card
end

-- Helper function to create horizontal stacked bars for addon comparison
local function CreateHorizontalStackedBar(parent, width, height)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, height or 25)

    -- Background
    local bg = container:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)

    container.segments = {} -- Pool of reusable segment objects {texture, text}

    -- Update function to set segment values
    function container:SetValues(values)
        -- Calculate total
        local total = 0
        for _, v in pairs(values) do
            total = total + v
        end

        if total == 0 then
            -- Show "No data" message
            if not self.noDataText then
                self.noDataText = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                self.noDataText:SetPoint("CENTER")
                self.noDataText:SetTextColor(0.5, 0.5, 0.5)
            end
            self.noDataText:SetText("No requests yet")
            self.noDataText:Show()
            
            -- Hide all segments
            for _, seg in ipairs(self.segments) do
                seg.texture:Hide()
                if seg.text then seg.text:Hide() end
            end
            return
        end

        if self.noDataText then
            self.noDataText:Hide()
        end

        -- Color map for different addons
        local colors = {
            TRP3 = {0.3, 0.6, 1.0},    -- Blue
            MRP = {0.8, 0.3, 0.8},     -- Purple
            XRP = {1.0, 0.6, 0.2},     -- Orange
            MSP = {0.2, 0.8, 0.4}      -- Green
        }

        -- Convert dictionary to sorted list for consistent ordering
        local dataList = {}
        for name, value in pairs(values) do
            if value > 0 then
                table.insert(dataList, {name = name, value = value})
            end
        end
        -- Sort by name to keep colors stable in position
        table.sort(dataList, function(a,b) return a.name < b.name end)

        local currentX = 0
        
        -- Update segments recycling existing ones
        for i, data in ipairs(dataList) do
            -- Create new segment if needed
            if not self.segments[i] then
                local segTexture = self:CreateTexture(nil, "ARTWORK")
                local text = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                self.segments[i] = {texture = segTexture, text = text}
            end
            
            local seg = self.segments[i]
            local segWidth = (width * data.value) / total
            
            -- Update Texture
            seg.texture:ClearAllPoints()
            seg.texture:SetPoint("LEFT", currentX, 0)
            seg.texture:SetSize(segWidth, height or 25)
            local color = colors[data.name] or {0.5, 0.5, 0.5}
            seg.texture:SetColorTexture(color[1], color[2], color[3], 0.9)
            seg.texture:Show()
            
            -- Update Text
            if segWidth > 40 then
                seg.text:ClearAllPoints()
                seg.text:SetPoint("CENTER", self, "LEFT", currentX + (segWidth / 2), 0)
                seg.text:SetText(data.value)
                seg.text:SetTextColor(1, 1, 1)
                seg.text:Show()
            else
                seg.text:Hide()
            end
            
            currentX = currentX + segWidth
        end
        
        -- Hide unused segments
        for i = #dataList + 1, #self.segments do
            self.segments[i].texture:Hide()
            self.segments[i].text:Hide()
        end
    end

    return container
end


-- Update minimap button position
local function UpdateMinimapButtonPosition()
    if not minimapButton then return end

    local angle = math.rad(TRP3FW_MinimapSettings.minimapPos)
    local x = math.cos(angle) * TRP3FW_MinimapSettings.radius
    local y = math.sin(angle) * TRP3FW_MinimapSettings.radius

    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Create minimap button
local function CreateMinimapButton()
    if minimapButton then
        TRP3FW:Debug("Minimap button already exists", "ui")
        return
    end

    TRP3FW:Debug("Creating minimap button...", "ui")
    minimapButton = CreateFrame("Button", "TRP3FW_MinimapButton", Minimap)
    TRP3FW:Debug("Minimap button frame created", "ui")
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Icon
    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\Ability_Rogue_FeignDeath") -- Stealth icon, appropriate for firewall
    minimapButton.icon = icon

    -- Border
    local overlay = minimapButton:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(52, 52)
    overlay:SetPoint("TOPLEFT")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Tooltip
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("TRP3 Firewall", 1, 1, 1)
        GameTooltip:AddLine("Left-click: Open settings", 0, 1, 0)
        GameTooltip:AddLine("Right-click: Toggle notifications", 0, 1, 0)
        GameTooltip:AddLine("Drag: Move button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    minimapButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Click handlers
    minimapButton:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            -- Open settings UI
            if settingsFrame:IsVisible() then
                settingsFrame:Hide()
            else
                settingsFrame:Show()
            end
        elseif button == "RightButton" then
            -- Toggle notifications
            TRP3FW_Settings.notifyEnabled = not TRP3FW_Settings.notifyEnabled
            TRP3FW:Info("Notifications "..(TRP3FW_Settings.notifyEnabled and "|cff00ff00enabled|r" or "|cffaaaaaadisabled|r"))
        end
    end)

    -- Drag handlers
    minimapButton:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale

            local angle = math.deg(math.atan2(py - my, px - mx))
            if angle < 0 then
                angle = angle + 360
            end

            TRP3FW_MinimapSettings.minimapPos = angle
            UpdateMinimapButtonPosition()
        end)
    end)

    minimapButton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        -- Save position when drag stops
        TRP3FW:Debug("Minimap button position saved: "..string.format("%.1f", TRP3FW_MinimapSettings.minimapPos).." degrees", "ui")
    end)

    UpdateMinimapButtonPosition()

    if TRP3FW_MinimapSettings.hide then
        minimapButton:Hide()
        TRP3FW:Debug("Minimap button created (hidden by settings)", "ui")
    else
        TRP3FW:Debug("Minimap button created and visible", "ui")
    end
end

-- Background performance tracking
local backgroundTicker
local function UpdateBackgroundTracking()
    local enabled = TRP3FW_Settings and TRP3FW_Settings.performanceHistoryEnabled
    local rate = TRP3FW_Settings and TRP3FW_Settings.statusRefreshRate or 30
    
    if backgroundTicker then
        backgroundTicker:Cancel()
        backgroundTicker = nil
    end

    if enabled then
        backgroundTicker = C_Timer.NewTicker(rate, function()
            -- Only run if window is NOT visible (UpdateStatusTab handles it when visible)
            -- Note: Redundant calls are safe (idempotent interval logic), but we skip to avoid overhead
            if settingsFrame and settingsFrame:IsVisible() then return end
            
            local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
            if hs then 
                hs:RecordPerformance(0) 
            end
        end)
    end
end

-- Update status tab with current runtime information
local statusUpdateCount = 0
local function UpdateStatusTab()
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
            if entry.wasBlocked then
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
    uiElements.statusPhaseCache:SetText((counts.phase or 0).." entries")
    uiElements.statusBroadcastCache:SetText((counts.broadcast or 0).." entries")
    uiElements.statusScanCache:SetText((counts.scan or 0).." entries")
    uiElements.statusSendCache:SetText((counts.send or 0).." entries")
    uiElements.statusWhoNameCache:SetText((counts.whoName or 0).." entries")
    uiElements.statusWhoZoneCache:SetText((counts.whoZone or 0).." entries")
    uiElements.statusInteractionCache:SetText((counts.interaction or 0).." entries")
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

-- Refresh UI from current settings
local function RefreshUI()
    -- Ensure defaults are applied before reading settings
    if TRP3FW and TRP3FW.InitializeSettings then
        TRP3FW:InitializeSettings()
    end
    TRP3FW_Settings = TRP3FW_Settings or {}
    if TRP3FW and TRP3FW.defaultSettings then
        for k, v in pairs(TRP3FW.defaultSettings) do
            if TRP3FW_Settings[k] == nil then
                TRP3FW_Settings[k] = v
            end
        end
    end
    if TRP3FW and TRP3FW.ValidateSettings then
        TRP3FW:ValidateSettings()
    end
    if TRP3FW and TRP3FW.HandleDependencySettings then
        TRP3FW:HandleDependencySettings()
    end
    if TRP3FW and TRP3FW.ValidateSettings then
        TRP3FW:ValidateSettings()
    end
    if not settingsFrame or not settingsFrame:IsVisible() then
        refreshScheduled = false
        return
    end

    -- Update status tab
    local ok, err = pcall(UpdateStatusTab)
    if not ok then
        TRP3FW:Error("Status tab update failed: "..tostring(err))
    end

    -- Status tab settings
    if uiElements.statusRefreshRate then
        uiElements.statusRefreshRate:SetValue(TRP3FW_Settings.statusRefreshRate)
    end
    if uiElements.performanceHistoryEnabled then
        uiElements.performanceHistoryEnabled:SetChecked(TRP3FW_Settings.performanceHistoryEnabled)
    end
    
    -- Ensure background tracking matches settings
    UpdateBackgroundTracking()

    -- Notifications tab
    uiElements.notifyEnabled:SetChecked(TRP3FW_Settings.notifyEnabled)
    uiElements.notifyOnAllow:SetChecked(TRP3FW_Settings.notifyOnAllow)
    uiElements.notifyOnStartPhaseBlock:SetChecked(TRP3FW_Settings.notifyOnStartPhaseBlock)
    uiElements.notifyBroadcast:SetChecked(TRP3FW_Settings.notifyOnBroadcast)
    uiElements.notifyWhisper:SetChecked(TRP3FW_Settings.notifyOnWhisper)
    uiElements.notifyOnScanResponse:SetChecked(TRP3FW_Settings.notifyOnScanResponse)
    if uiElements.notifyOnScanAllow then
        uiElements.notifyOnScanAllow:SetChecked(TRP3FW_Settings.notifyOnScanAllow)
    end
    if uiElements.scanResponseRequireNonce then
        uiElements.scanResponseRequireNonce:SetChecked(TRP3FW_Settings.scanResponseRequireNonce)
    end
    uiElements.scanResponseCacheEnabled:SetChecked(TRP3FW_Settings.scanResponseCacheEnabled)
    uiElements.scanResponseAllowCacheBypass:SetChecked(TRP3FW_Settings.scanResponseAllowCacheBypass)
    uiElements.scanResponseAllowGroupBypass:SetChecked(TRP3FW_Settings.scanResponseAllowGroupBypass)
    if uiElements.scanResponseWhitelistEnabled then
        uiElements.scanResponseWhitelistEnabled:SetChecked(TRP3FW_Settings.scanResponseWhitelistEnabled)
        local enabled = TRP3FW_Settings.scanResponseWhitelistEnabled
        uiElements.scanResponseWhitelistEdit:SetEnabled(enabled)
        uiElements.scanResponseWhitelistEdit:SetAlpha(enabled and 1 or 0.5)
        if uiElements.scanResponseWhitelistScroll then
            uiElements.scanResponseWhitelistScroll:SetAlpha(enabled and 1 or 0.5)
        end
    end
    uiElements.scanResponseWhitelistEdit:SetText(TRP3FW_Settings.scanResponseWhitelist or "")
    local phaseMode = TRP3FW_Settings.scanResponsePhaseMode or "alert"
    local mapMode = TRP3FW_Settings.scanResponseMapMode or "alert"
    local function setModeText(dropdown, mode)
        local label = "Alert (send anyway)"
        if mode == "block" then label = "Block (silent)" end
        if mode == "off" then label = "Off" end
        if mode == "statistics" then label = "Statistics Only" end
        if mode == "alert_block" then label = "Alert + Block" end
        UIDropDownMenu_SetText(dropdown, label)
    end
    setModeText(uiElements.scanResponsePhaseModeDropdown, phaseMode)
    setModeText(uiElements.scanResponseWhoModeDropdown, mapMode)

    -- Disable scan response controls based on availability and notify state
    local hasScanner = TRP3FW.detectedAddons and (TRP3FW.detectedAddons.MapScanner or TRP3FW.detectedAddons.TRP3)
    local hasEpsilon = TRP3FW.hasEpsilonAPI
    local gatingActive = hasEpsilon and ((phaseMode ~= "off") or (mapMode ~= "off"))

    local function setDropdownEnabled(dropdown, enabled)
        if enabled then
            UIDropDownMenu_EnableDropDown(dropdown)
            dropdown:SetAlpha(1.0)
        else
            UIDropDownMenu_DisableDropDown(dropdown)
            dropdown:SetAlpha(0.5)
        end
    end

    if not hasScanner then
        uiElements.notifyOnScanResponse:Disable()
        uiElements.notifyOnScanResponse:SetAlpha(0.5)
        uiElements.scanResponseCacheEnabled:SetAlpha(0.5)
        uiElements.scanResponseAllowCacheBypass:SetAlpha(0.5)
        uiElements.scanResponseAllowGroupBypass:SetAlpha(0.5)
        if uiElements.scanResponseRequireNonce then
            uiElements.scanResponseRequireNonce:SetAlpha(0.5)
            uiElements.scanResponseRequireNonce:Disable()
        end
        if uiElements.notifyOnScanAllow then
            uiElements.notifyOnScanAllow:SetAlpha(0.5)
            uiElements.notifyOnScanAllow:Disable()
        end
        setDropdownEnabled(uiElements.scanResponsePhaseModeDropdown, false)
        setDropdownEnabled(uiElements.scanResponseWhoModeDropdown, false)
        uiElements.scanResponseCacheEnabled:Disable()
        uiElements.scanResponseAllowCacheBypass:Disable()
        uiElements.scanResponseAllowGroupBypass:Disable()
        if uiElements.scanResponseWhitelistEnabled then
            uiElements.scanResponseWhitelistEnabled:Disable()
            uiElements.scanResponseWhitelistEnabled:SetAlpha(0.5)
            uiElements.scanResponseWhitelistEdit:SetEnabled(false)
            uiElements.scanResponseWhitelistEdit:SetAlpha(0.5)
            if uiElements.scanResponseWhitelistScroll then
                uiElements.scanResponseWhitelistScroll:SetAlpha(0.5)
            end
        end
    else
        uiElements.notifyOnScanResponse:Enable()
        uiElements.notifyOnScanResponse:SetAlpha(1.0)
        local gatingAlpha = gatingActive and 1.0 or 0.5
        uiElements.scanResponseCacheEnabled:SetAlpha(gatingAlpha)
        uiElements.scanResponseAllowCacheBypass:SetAlpha(gatingAlpha)
        uiElements.scanResponseAllowGroupBypass:SetAlpha(gatingAlpha)
        if uiElements.scanResponseRequireNonce then
            uiElements.scanResponseRequireNonce:SetAlpha(gatingAlpha)
            if gatingActive then
                uiElements.scanResponseRequireNonce:Enable()
            else
                uiElements.scanResponseRequireNonce:Disable()
            end
        end
        if gatingActive then
            uiElements.scanResponseCacheEnabled:Enable()
            uiElements.scanResponseAllowCacheBypass:Enable()
            uiElements.scanResponseAllowGroupBypass:Enable()
        else
            uiElements.scanResponseCacheEnabled:Disable()
            uiElements.scanResponseAllowCacheBypass:Disable()
            uiElements.scanResponseAllowGroupBypass:Disable()
        end

        if uiElements.notifyOnScanAllow then
            uiElements.notifyOnScanAllow:SetAlpha(gatingAlpha)
            if gatingActive then
                uiElements.notifyOnScanAllow:Enable()
            else
                uiElements.notifyOnScanAllow:Disable()
            end
        end
        if uiElements.scanResponseWhitelistEnabled then
            if gatingActive then
                uiElements.scanResponseWhitelistEnabled:Enable()
                uiElements.scanResponseWhitelistEnabled:SetAlpha(1.0)
            else
                uiElements.scanResponseWhitelistEnabled:Disable()
                uiElements.scanResponseWhitelistEnabled:SetAlpha(0.5)
            end
            local enabled = gatingActive and TRP3FW_Settings.scanResponseWhitelistEnabled
            uiElements.scanResponseWhitelistEdit:SetEnabled(enabled)
            uiElements.scanResponseWhitelistEdit:SetAlpha(enabled and 1 or 0.5)
            if uiElements.scanResponseWhitelistScroll then
                uiElements.scanResponseWhitelistScroll:SetAlpha(enabled and 1 or 0.5)
            end
        end

        setDropdownEnabled(uiElements.scanResponsePhaseModeDropdown, hasEpsilon)
        setDropdownEnabled(uiElements.scanResponseWhoModeDropdown, hasEpsilon)
    end
    uiElements.showInChat:SetChecked(TRP3FW_Settings.showInChat)
    if uiElements.showGhostNotifications then
        uiElements.showGhostNotifications:SetChecked(TRP3FW_Settings.showGhostNotifications)
    end
    uiElements.showOnScreen:SetChecked(TRP3FW_Settings.showOnScreen)
    uiElements.playSound:SetChecked(TRP3FW_Settings.playSound)
    uiElements.showAddonSource:SetChecked(TRP3FW_Settings.showAddonSource)
    uiElements.showCacheInfo:SetChecked(TRP3FW_Settings.showCacheInfo)
    uiElements.showCheckResults:SetChecked(TRP3FW_Settings.showCheckResults)
    uiElements.suppressionTime:SetText(TRP3FW_Settings.suppressionTime)
    uiElements.refreshSuppression:SetChecked(TRP3FW_Settings.refreshSuppression ~= false)

    -- Alerts & Blocking tab
    -- Set phase and map check mode dropdowns
    local modeMap = {
        ["off"] = "Off",
        ["statistics"] = "Statistics Only",
        ["alert"] = "Alert",
        ["block"] = "Block",
        ["ghost"] = "Ghost (Blank Profile)",
        ["alert_block"] = "Alert + Block",
        ["alert_ghost"] = "Alert + Ghost"
    }

    local phaseMode = TRP3FW_Settings.phaseCheckMode or "off"
    UIDropDownMenu_SetText(uiElements.phaseCheckModeDropdown, modeMap[phaseMode] or "Off")

    local mapMode = TRP3FW_Settings.mapCheckMode or "off"
    UIDropDownMenu_SetText(uiElements.mapCheckModeDropdown, modeMap[mapMode] or "Off")

    if uiElements.notificationModeSummary then
        local function modeText(val)
            return modeMap[val] or "Off"
        end
        local function scanModeText(val)
            if val == "statistics" then return "Statistics Only" end
            if val == "alert" then return "Alert" end
            if val == "block" then return "Block (silent)" end
            if val == "alert_block" then return "Alert + Block" end
            return "Off"
        end
        local whoText = "WHO: Default (user /who via UI; addon auto)"
        local lines = {}
        table.insert(lines, string.format("Profiles: Phase: %s   Map: %s   %s", modeText(phaseMode), modeText(mapMode), whoText))

        local scanPhaseMode = TRP3FW_Settings.scanResponsePhaseMode or "off"
        local scanMapMode = TRP3FW_Settings.scanResponseMapMode or "off"
        if gatingActive then
            table.insert(lines, string.format("Scan reply: Phase: %s   Map: %s", scanModeText(scanPhaseMode), scanModeText(scanMapMode)))
        else
            table.insert(lines, "Scan reply: Protections off")
        end

        uiElements.notificationModeSummary:SetText(table.concat(lines, "\n"))
    end

    if uiElements.whitelistBypassEnabled then
        uiElements.whitelistBypassEnabled:SetChecked(TRP3FW_Settings.whitelistEnabled)
    end
	if uiElements.whitelistEdit then
		uiElements.whitelistEdit:SetText(TRP3FW_Settings.whitelistEntries or "")
		local enabled = TRP3FW_Settings.whitelistEnabled
		uiElements.whitelistEdit:SetEnabled(enabled)
		uiElements.whitelistEdit:SetAlpha(enabled and 1 or 0.5)
        if uiElements.whitelistScroll then
            uiElements.whitelistScroll:SetAlpha(enabled and 1 or 0.5)
        end
	end

	uiElements.suppressAllWhoOutput:SetChecked(TRP3FW_Settings.suppressAllWhoOutput)
	uiElements.allowGroupPhaseBypass:SetChecked(TRP3FW_Settings.allowGroupPhaseBypass)
	uiElements.blockStartPhase:SetChecked(TRP3FW_Settings.blockStartPhase)
    uiElements.ghostOnStartPhase:SetChecked(TRP3FW_Settings.ghostOnStartPhase)
    uiElements.ghostProfileSwitch:SetChecked(TRP3FW_Settings.ghostProfileSwitch)
    if uiElements.ghostProfileWhitelistEnabled then
        uiElements.ghostProfileWhitelistEnabled:SetChecked(TRP3FW_Settings.ghostProfileWhitelistEnabled)
    end
    if uiElements.ghostProfileWhitelistEdit then
        uiElements.ghostProfileWhitelistEdit:SetText(TRP3FW_Settings.ghostProfileWhitelist or "")
        local enabled = TRP3FW_Settings.ghostProfileWhitelistEnabled
        uiElements.ghostProfileWhitelistEdit:SetEnabled(enabled)
        uiElements.ghostProfileWhitelistEdit:SetAlpha(enabled and 1 or 0.5)
        if uiElements.ghostProfileWhitelistScroll then
            uiElements.ghostProfileWhitelistScroll:SetAlpha(enabled and 1 or 0.5)
        end
    end
    if uiElements.profileOverrides then
        TRP3FW_Settings.ghostProfileOverrides = TRP3FW_Settings.ghostProfileOverrides or {}
        for idx, refs in ipairs(uiElements.profileOverrides) do
            TRP3FW_Settings.ghostProfileOverrides[idx] = TRP3FW_Settings.ghostProfileOverrides[idx] or {}
            local entry = TRP3FW_Settings.ghostProfileOverrides[idx]
            if refs.edit then
                refs.edit:SetText(entry.match or "")
            end
            if refs.dropdown then
                local overrideLabel = entry.profileName or (entry.profileID and tostring(entry.profileID)) or "(Use global profile)"
                UIDropDownMenu_SetText(refs.dropdown, overrideLabel)
            end
        end
    end

    -- Update profile switch dropdown
    if uiElements.ghostProfileDropdown then
        local currentProfile = TRP3FW_Settings.ghostProfileName or "TRP3FW_BLANK"
        if currentProfile == "TRP3FW_BLANK" then
            UIDropDownMenu_SetText(uiElements.ghostProfileDropdown, "TRP3FW_BLANK |cff00ff00(Recommended)|r")
        else
            UIDropDownMenu_SetText(uiElements.ghostProfileDropdown, currentProfile)
        end
    end

    -- Update SPVP controls
    if uiElements.spvpModeDropdown then
        local mode = TRP3FW_Settings.spvpMode or "off"
        local text = "Off"
        if mode == "optional" then text = "Optional (Post-Check)" end
        if mode == "preferred" then text = "Preferred (Pre-Check)" end
        if mode == "required" then text = "Required (Strict)" end
        UIDropDownMenu_SetText(uiElements.spvpModeDropdown, text)
    end
    if uiElements.spvpAutoInitialize then
        uiElements.spvpAutoInitialize:SetChecked(TRP3FW_Settings.spvpAutoInitialize)
    end
    if uiElements.spvpSaltCacheDurationSlider then
        local duration = TRP3FW_Settings.spvpSaltCacheDuration or 10800
        uiElements.spvpSaltCacheDurationSlider:SetValue(duration)
    end

    -- SPVP Cache Refresh Settings
    if uiElements.spvpVerifiedCacheDuration then
        local durationSec = TRP3FW_Settings.spvpVerifiedCacheDuration or 300
        uiElements.spvpVerifiedCacheDuration:SetText(durationSec)
    end
    if uiElements.spvpVerifiedRefreshRate then
        uiElements.spvpVerifiedRefreshRate:SetText(TRP3FW_Settings.spvpVerifiedRefreshRate or 50)
    end
    if uiElements.spvpPhaseSaltRefreshRate then
        uiElements.spvpPhaseSaltRefreshRate:SetText(TRP3FW_Settings.spvpPhaseSaltRefreshRate or 50)
    end

    if uiElements.spvpSaltStatus then
        -- Update salt status display
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

                if uiElements.spvpSecureButton then
                    uiElements.spvpSecureButton:SetText("Rotate Security Key")
                end
            else
                uiElements.spvpSaltStatus:SetText("|cffff0000✗ This phase is NOT secured|r (No security key set)")

                if uiElements.spvpSecureButton then
                    uiElements.spvpSecureButton:SetText("Secure This Phase")
                end
            end

            -- Update button state based on permissions
            if uiElements.spvpSecureButton then
                local isOwner = C_Epsilon.IsOwner and C_Epsilon.IsOwner()
                local isOfficer = C_Epsilon.IsOfficer and C_Epsilon.IsOfficer()
                if isOwner or isOfficer then
                    uiElements.spvpSecureButton:Enable()
                else
                    uiElements.spvpSecureButton:Disable()
                end
            end
        else
            uiElements.spvpSaltStatus:SetText("|cffaaaaaa(Epsilon API not available)|r")
        end
    end

    -- Disable Epsilon-specific features if API not available
    for _, control in ipairs(epsilonControls) do
        if control and control.SetShown then
            control:SetShown(TRP3FW.hasEpsilonAPI)
        end
    end
    if uiElements.epsilonWarning then
        uiElements.epsilonWarning:SetShown(not TRP3FW.hasEpsilonAPI)
    end

    if not TRP3FW.hasEpsilonAPI then
        if uiElements.spvpModeDropdown then
            UIDropDownMenu_DisableDropDown(uiElements.spvpModeDropdown)
            uiElements.spvpModeDropdown:SetAlpha(0.5)
        end
        uiElements.blockStartPhase:Disable()
        uiElements.blockStartPhase:SetAlpha(0.5)
        uiElements.ghostOnStartPhase:Disable()
        uiElements.ghostOnStartPhase:SetAlpha(0.5)
        uiElements.ghostProfileSwitch:Disable()
        uiElements.ghostProfileSwitch:SetAlpha(0.5)
        if uiElements.ghostProfileWhitelistEnabled then
            uiElements.ghostProfileWhitelistEnabled:Disable()
            uiElements.ghostProfileWhitelistEnabled:SetAlpha(0.5)
        end
        if uiElements.ghostProfileWhitelistEdit then
            uiElements.ghostProfileWhitelistEdit:SetEnabled(false)
            uiElements.ghostProfileWhitelistEdit:SetAlpha(0.5)
            if uiElements.ghostProfileWhitelistScroll then
                uiElements.ghostProfileWhitelistScroll:SetAlpha(0.5)
            end
        end
        if uiElements.profileOverrides then
            for _, refs in ipairs(uiElements.profileOverrides) do
                if refs.edit then
                    refs.edit:Disable()
                    refs.edit:SetAlpha(0.5)
                end
                if refs.dropdown then
                    UIDropDownMenu_DisableDropDown(refs.dropdown)
                    refs.dropdown:SetAlpha(0.5)
                end
            end
        end
    end

    -- Filters & Addons tab
    uiElements.filterGradients:SetChecked(TRP3FW_Settings.filterGradients)
    uiElements.filterMinimumFontSize:SetChecked(TRP3FW_Settings.filterMinimumFontSize)

    -- Set dropdown text based on current setting
    local fontSizeLevel = TRP3FW_Settings.minimumFontSizeLevel or "h3"
    if fontSizeLevel == "h1" then
        UIDropDownMenu_SetText(uiElements.minimumFontSizeDropdown, "H1 (Largest)")
    elseif fontSizeLevel == "h2" then
        UIDropDownMenu_SetText(uiElements.minimumFontSizeDropdown, "H2 (Large)")
    elseif fontSizeLevel == "h3" then
        UIDropDownMenu_SetText(uiElements.minimumFontSizeDropdown, "H3 (Medium)")
    elseif fontSizeLevel == "p" then
        UIDropDownMenu_SetText(uiElements.minimumFontSizeDropdown, "P (Normal)")
    end

    -- Enable/disable dropdown based on checkbox state
    if TRP3FW_Settings.filterMinimumFontSize then
        UIDropDownMenu_EnableDropDown(uiElements.minimumFontSizeDropdown)
        uiElements.minimumFontSizeDropdown:SetAlpha(1.0)
    else
        UIDropDownMenu_DisableDropDown(uiElements.minimumFontSizeDropdown)
        uiElements.minimumFontSizeDropdown:SetAlpha(0.5)
    end

    uiElements.monitorTRP3:SetChecked(TRP3FW_Settings.monitorTRP3)
    uiElements.monitorMRP:SetChecked(TRP3FW_Settings.monitorMRP)
    uiElements.monitorXRP:SetChecked(TRP3FW_Settings.monitorXRP)
    uiElements.monitorMSP:SetChecked(TRP3FW_Settings.monitorMSP)

    if uiElements.strictHookMode then
        uiElements.strictHookMode:SetChecked(TRP3FW_Settings.strictHookMode)
    end
    if uiElements.logHookConflicts then
        uiElements.logHookConflicts:SetChecked(TRP3FW_Settings.logHookConflicts)
    end
    if uiElements.abortOnMultipleRPAddons then
        uiElements.abortOnMultipleRPAddons:SetChecked(TRP3FW_Settings.abortOnMultipleRPAddons)
    end
    if uiElements.disableMapScanOnTRP3 then
        uiElements.disableMapScanOnTRP3:SetChecked(TRP3FW_Settings.disableMapScanOnTRP3)
    end

    -- Cache & Debug tab
    if uiElements.phaseCheckBatchMode then
        uiElements.phaseCheckBatchMode:SetChecked(TRP3FW_Settings.phaseCheckBatchMode)
    end
    if uiElements.phaseCheckRefundOnNoChange then
        uiElements.phaseCheckRefundOnNoChange:SetChecked(TRP3FW_Settings.phaseCheckRefundOnNoChange)
    end
    if uiElements.privilegedReservedTokens then
        uiElements.privilegedReservedTokens:SetText(TRP3FW_Settings.privilegedReservedTokens or 2)
    end
    if uiElements.privilegedLowPriorityThreshold then
        uiElements.privilegedLowPriorityThreshold:SetText(TRP3FW_Settings.privilegedLowPriorityThreshold or 4)
    end
    uiElements.phaseCacheDuration:SetText(TRP3FW_Settings.phaseCacheDuration)
    if uiElements.phaseCacheRefreshThreshold then
        local val = (TRP3FW_Settings.phaseCacheRefreshThreshold or 0.2) * 100
        uiElements.phaseCacheRefreshThreshold:SetText(val)
    end
    uiElements.phaseCacheFailureDuration:SetText(TRP3FW_Settings.phaseCacheFailureDuration or 10)
    uiElements.scanCacheDuration:SetText(TRP3FW_Settings.scanCacheDuration)
    if uiElements.scanCacheFailureDuration then
        uiElements.scanCacheFailureDuration:SetText(TRP3FW_Settings.scanCacheFailureDuration or 10)
    end
    if uiElements.mapScanMinInterval then
        uiElements.mapScanMinInterval:SetText(TRP3FW_Settings.mapScanMinInterval or 60)
    end
    uiElements.cacheSizeLimit:SetText(TRP3FW_Settings.cacheSizeLimit or 1000)
    uiElements.maxHistorySize:SetText(TRP3FW_Settings.maxHistorySize or 100)
    uiElements.whoZoneCacheDuration:SetText(TRP3FW_Settings.whoZoneCacheDuration or 45)
    uiElements.whoNameCacheDuration:SetText(TRP3FW_Settings.whoNameCacheDuration or 180)
    uiElements.whoZoneQueryCooldown:SetText(TRP3FW_Settings.whoZoneQueryCooldown or 20)
    uiElements.whoCacheRefreshThreshold:SetText(TRP3FW_Settings.whoCacheRefreshThreshold or 50)
    uiElements.sendCacheDuration:SetText(TRP3FW_Settings.sendCacheDuration)
    uiElements.interactionCacheDuration:SetText(TRP3FW_Settings.interactionCacheDuration or 600)
    uiElements.interactionRefreshRate:SetText(TRP3FW_Settings.interactionRefreshRate or 60)
    uiElements.sendCacheRefreshRate:SetText(TRP3FW_Settings.sendCacheRefreshRate or 60)
    uiElements.phaseInDelay:SetText(TRP3FW_Settings.phaseInDelay or 4)
    uiElements.transitionGracePeriod:SetText(TRP3FW_Settings.transitionGracePeriod or 10)
    -- Convert seconds to days for display
    local validatedNamesCacheSeconds = TRP3FW_Settings.validatedNamesCacheDuration or 604800
    local validatedNamesCacheDays = math.floor(validatedNamesCacheSeconds / 86400)
    uiElements.validatedNamesCacheDuration:SetText(validatedNamesCacheDays)
    uiElements.validatedNamesCacheLimit:SetText(TRP3FW_Settings.validatedNamesCacheLimit or 5000)

    -- Cache clearing master toggles
    uiElements.clearCacheOnPhaseChange:SetChecked(TRP3FW_Settings.clearCacheOnPhaseChange)
    uiElements.clearCacheOnZoneChange:SetChecked(TRP3FW_Settings.clearCacheOnZoneChange)

    -- Disable clearCacheOnPhaseChange if Epsilon API not available
    if not TRP3FW.hasEpsilonAPI then
        uiElements.clearCacheOnPhaseChange:Disable()
        uiElements.clearCacheOnPhaseChange:SetAlpha(0.5)
    end

    -- Phase change granular settings
    uiElements.clearPhaseCheckOnPhaseChange:SetChecked(TRP3FW_Settings.clearPhaseCheckOnPhaseChange)
    uiElements.clearAllowedSendersOnPhaseChange:SetChecked(TRP3FW_Settings.clearAllowedSendersOnPhaseChange)
    uiElements.clearInteractionOnPhaseChange:SetChecked(TRP3FW_Settings.clearInteractionOnPhaseChange)
    uiElements.clearSuppressionOnPhaseChange:SetChecked(TRP3FW_Settings.clearSuppressionOnPhaseChange)
    uiElements.clearRecentBroadcastsOnPhaseChange:SetChecked(TRP3FW_Settings.clearRecentBroadcastsOnPhaseChange)
    uiElements.clearRecentScansOnPhaseChange:SetChecked(TRP3FW_Settings.clearRecentScansOnPhaseChange)
    uiElements.clearWhoZoneOnPhaseChange:SetChecked(TRP3FW_Settings.clearWhoZoneOnPhaseChange)
    uiElements.clearWhoNameOnPhaseChange:SetChecked(TRP3FW_Settings.clearWhoNameOnPhaseChange)
    if uiElements.clearSpvpOnPhaseChange then
        uiElements.clearSpvpOnPhaseChange:SetChecked(TRP3FW_Settings.clearSpvpOnPhaseChange)
    end

    -- Zone change granular settings
    uiElements.clearPhaseCheckOnZoneChange:SetChecked(TRP3FW_Settings.clearPhaseCheckOnZoneChange)
    uiElements.clearAllowedSendersOnZoneChange:SetChecked(TRP3FW_Settings.clearAllowedSendersOnZoneChange)
    uiElements.clearInteractionOnZoneChange:SetChecked(TRP3FW_Settings.clearInteractionOnZoneChange)
    uiElements.clearSuppressionOnZoneChange:SetChecked(TRP3FW_Settings.clearSuppressionOnZoneChange)
    uiElements.clearRecentBroadcastsOnZoneChange:SetChecked(TRP3FW_Settings.clearRecentBroadcastsOnZoneChange)
    uiElements.clearRecentScansOnZoneChange:SetChecked(TRP3FW_Settings.clearRecentScansOnZoneChange)
    uiElements.clearWhoZoneOnZoneChange:SetChecked(TRP3FW_Settings.clearWhoZoneOnZoneChange)
    uiElements.clearWhoNameOnZoneChange:SetChecked(TRP3FW_Settings.clearWhoNameOnZoneChange)
    if uiElements.clearSpvpOnZoneChange then
        uiElements.clearSpvpOnZoneChange:SetChecked(TRP3FW_Settings.clearSpvpOnZoneChange)
    end

    -- Enable/disable granular options based on master toggles AND Epsilon API availability
    if TRP3FW_Settings.clearCacheOnPhaseChange and TRP3FW.hasEpsilonAPI then
        uiElements.clearPhaseCheckOnPhaseChange:Enable()
        uiElements.clearAllowedSendersOnPhaseChange:Enable()
        uiElements.clearInteractionOnPhaseChange:Enable()
        uiElements.clearSuppressionOnPhaseChange:Enable()
        uiElements.clearRecentBroadcastsOnPhaseChange:Enable()
        uiElements.clearRecentScansOnPhaseChange:Enable()
        uiElements.clearWhoZoneOnPhaseChange:Enable()
        uiElements.clearWhoNameOnPhaseChange:Enable()
        if uiElements.clearSpvpOnPhaseChange then uiElements.clearSpvpOnPhaseChange:Enable() end
    else
        uiElements.clearPhaseCheckOnPhaseChange:Disable()
        uiElements.clearAllowedSendersOnPhaseChange:Disable()
        uiElements.clearInteractionOnPhaseChange:Disable()
        uiElements.clearSuppressionOnPhaseChange:Disable()
        uiElements.clearRecentBroadcastsOnPhaseChange:Disable()
        uiElements.clearRecentScansOnPhaseChange:Disable()
        uiElements.clearWhoZoneOnPhaseChange:Disable()
        uiElements.clearWhoNameOnPhaseChange:Disable()
        if uiElements.clearSpvpOnPhaseChange then uiElements.clearSpvpOnPhaseChange:Disable() end
    end

    -- Grey out phase change granular options if Epsilon API not available
    if not TRP3FW.hasEpsilonAPI then
        uiElements.clearPhaseCheckOnPhaseChange:SetAlpha(0.5)
        uiElements.clearAllowedSendersOnPhaseChange:SetAlpha(0.5)
        uiElements.clearInteractionOnPhaseChange:SetAlpha(0.5)
        uiElements.clearSuppressionOnPhaseChange:SetAlpha(0.5)
        uiElements.clearRecentBroadcastsOnPhaseChange:SetAlpha(0.5)
        uiElements.clearRecentScansOnPhaseChange:SetAlpha(0.5)
        uiElements.clearWhoZoneOnPhaseChange:SetAlpha(0.5)
        uiElements.clearWhoNameOnPhaseChange:SetAlpha(0.5)
        if uiElements.clearSpvpOnPhaseChange then uiElements.clearSpvpOnPhaseChange:SetAlpha(0.5) end
    end

    if TRP3FW_Settings.clearCacheOnZoneChange then
        uiElements.clearPhaseCheckOnZoneChange:Enable()
        uiElements.clearAllowedSendersOnZoneChange:Enable()
        uiElements.clearInteractionOnZoneChange:Enable()
        uiElements.clearSuppressionOnZoneChange:Enable()
        uiElements.clearRecentBroadcastsOnZoneChange:Enable()
        uiElements.clearRecentScansOnZoneChange:Enable()
        uiElements.clearWhoZoneOnZoneChange:Enable()
        uiElements.clearWhoNameOnZoneChange:Enable()
        if uiElements.clearSpvpOnZoneChange then uiElements.clearSpvpOnZoneChange:Enable() end
    else
        uiElements.clearPhaseCheckOnZoneChange:Disable()
        uiElements.clearAllowedSendersOnZoneChange:Disable()
        uiElements.clearInteractionOnZoneChange:Disable()
        uiElements.clearSuppressionOnZoneChange:Disable()
        uiElements.clearRecentBroadcastsOnZoneChange:Disable()
        uiElements.clearRecentScansOnZoneChange:Disable()
        uiElements.clearWhoZoneOnZoneChange:Disable()
        uiElements.clearWhoNameOnZoneChange:Disable()
        if uiElements.clearSpvpOnZoneChange then uiElements.clearSpvpOnZoneChange:Disable() end
    end

    -- History Settings
    uiElements.trackHistory:SetChecked(TRP3FW_Settings.trackHistory)

    -- Debug Settings
    uiElements.debug:SetChecked(TRP3FW_Settings.debug)
    uiElements.debugTimestamp:SetChecked(TRP3FW_Settings.debugTimestamp)

    -- Redaction Settings
    uiElements.redactEnabled:SetChecked(TRP3FW_Settings.redactEnabled)
    uiElements.redactNames:SetChecked(TRP3FW_Settings.redactNames)
    uiElements.redactLocations:SetChecked(TRP3FW_Settings.redactLocations)
    uiElements.redactNetwork:SetChecked(TRP3FW_Settings.redactNetwork)
    if uiElements.redactSPVP then
        uiElements.redactSPVP:SetChecked(TRP3FW_Settings.redactSPVP)
    end

    local redactOn = TRP3FW_Settings.redactEnabled ~= false
    local function setRedactEnabled(enabled)
        local alpha = enabled and 1 or 0.5
        if enabled then
            uiElements.redactNames:Enable()
            uiElements.redactLocations:Enable()
            uiElements.redactNetwork:Enable()
            if uiElements.redactSPVP then uiElements.redactSPVP:Enable() end
        else
            uiElements.redactNames:Disable()
            uiElements.redactLocations:Disable()
            uiElements.redactNetwork:Disable()
            if uiElements.redactSPVP then uiElements.redactSPVP:Disable() end
        end
        uiElements.redactNames:SetAlpha(alpha)
        uiElements.redactLocations:SetAlpha(alpha)
        uiElements.redactNetwork:SetAlpha(alpha)
        if uiElements.redactSPVP then uiElements.redactSPVP:SetAlpha(alpha) end
    end
    setRedactEnabled(redactOn)

    -- Set debug output dropdown
    if TRP3FW_Settings.debugOutputBoth then
        UIDropDownMenu_SetText(uiElements.debugOutputDropdown, "Both")
    elseif TRP3FW_Settings.debugOutputWindow then
        UIDropDownMenu_SetText(uiElements.debugOutputDropdown, "Window")
    else
        UIDropDownMenu_SetText(uiElements.debugOutputDropdown, "Chat")
    end
    uiElements.debugChannel:SetChecked(TRP3FW_Settings.debugChannel)
    uiElements.debugWhisper:SetChecked(TRP3FW_Settings.debugWhisper)
    uiElements.debugWho:SetChecked(TRP3FW_Settings.debugWho)
    uiElements.debugPhase:SetChecked(TRP3FW_Settings.debugPhase)
    uiElements.debugCleanName:SetChecked(TRP3FW_Settings.debugCleanName)
    uiElements.debugLocation:SetChecked(TRP3FW_Settings.debugLocation)
    uiElements.debugDecision:SetChecked(TRP3FW_Settings.debugDecision)
    uiElements.debugHooks:SetChecked(TRP3FW_Settings.debugHooks)
    uiElements.debugCache:SetChecked(TRP3FW_Settings.debugCache)
    uiElements.debugSend:SetChecked(TRP3FW_Settings.debugSend)
    uiElements.debugUI:SetChecked(TRP3FW_Settings.debugUI)
    uiElements.debugUtils:SetChecked(TRP3FW_Settings.debugUtils)
    uiElements.debugSecurity:SetChecked(TRP3FW_Settings.debugSecurity)
    uiElements.debugGhost:SetChecked(TRP3FW_Settings.debugGhost)
    if uiElements.debugSPVP then uiElements.debugSPVP:SetChecked(TRP3FW_Settings.debugSPVP) end

    -- Enable/disable debug options based on debug mode
    if TRP3FW_Settings.debug then
        uiElements.debugChannel:Enable()
        uiElements.debugWhisper:Enable()
        uiElements.debugWho:Enable()
        uiElements.debugPhase:Enable()
        uiElements.debugCleanName:Enable()
        uiElements.debugLocation:Enable()
        uiElements.debugDecision:Enable()
        uiElements.debugHooks:Enable()
        uiElements.debugCache:Enable()
        uiElements.debugSend:Enable()
        uiElements.debugUI:Enable()
        uiElements.debugUtils:Enable()
        uiElements.debugSecurity:Enable()
        uiElements.debugGhost:Enable()
        if uiElements.debugSPVP then uiElements.debugSPVP:Enable() end
    else
        uiElements.debugChannel:Disable()
        uiElements.debugWhisper:Disable()
        uiElements.debugWho:Disable()
        uiElements.debugPhase:Disable()
        uiElements.debugCleanName:Disable()
        uiElements.debugLocation:Disable()
        uiElements.debugDecision:Disable()
        uiElements.debugHooks:Disable()
        uiElements.debugCache:Disable()
        uiElements.debugSend:Disable()
        uiElements.debugUI:Disable()
        uiElements.debugUtils:Disable()
        uiElements.debugSecurity:Disable()
        uiElements.debugGhost:Disable()
        if uiElements.debugSPVP then uiElements.debugSPVP:Disable() end
    end

    -- Timestamp toggle should be usable even when debug output is off (affects notifications too)
    uiElements.debugTimestamp:Enable()

    -- Enforce complexity levels (must run last to override logic where necessary)
    UpdateUIComplexity()
end

-- Debounced refresh to coalesce rapid changes
RequestRefreshUI = function()
    if refreshScheduled then return end
    refreshScheduled = true
    C_Timer.After(0, function()
        refreshScheduled = false
        RefreshUI()
    end)
end

-- Create the main settings frame
-- Refactored Tab 3 creation to avoid local variable limit
local function CreateAlertsTab(tab3)
    -- Re-bind tab3 if needed or just use arg
    local y3 = -10

    -- Quick presets
    local function ApplyPreset(preset)
        if preset == "relaxed" then
            TRP3FW_Settings.phaseCheckMode = "off"
            TRP3FW_Settings.mapCheckMode = "alert"
            TRP3FW_Settings.useWhoQuery = false
            TRP3FW_Settings.blockStartPhase = false
            TRP3FW_Settings.ghostOnStartPhase = false
            TRP3FW_Settings.phaseCheckBatchMode = true
            TRP3FW_Settings.phaseCheckRefundOnNoChange = false

        elseif preset == "balanced" then
            TRP3FW_Settings.phaseCheckMode = "alert"
            TRP3FW_Settings.mapCheckMode = "alert"
            TRP3FW_Settings.useWhoQuery = true
            TRP3FW_Settings.blockStartPhase = false
            TRP3FW_Settings.ghostOnStartPhase = false

        elseif preset == "recommended" then
            TRP3FW_Settings.phaseCheckMode = "alert_block"
            TRP3FW_Settings.mapCheckMode = "alert_block"
            TRP3FW_Settings.useWhoQuery = true
            TRP3FW_Settings.blockStartPhase = true
            TRP3FW_Settings.ghostOnStartPhase = false
            TRP3FW_Settings.spvpEnabled = true

        elseif preset == "strict" then
            TRP3FW_Settings.phaseCheckMode = "alert_block"
            TRP3FW_Settings.mapCheckMode = "alert_block"
            TRP3FW_Settings.useWhoQuery = true
            TRP3FW_Settings.blockStartPhase = true
            TRP3FW_Settings.ghostOnStartPhase = false
            TRP3FW_Settings.spvpEnabled = true
            TRP3FW_Settings.scanResponsePhaseMode = "block"
            TRP3FW_Settings.scanResponseMapMode = "block"
            TRP3FW_Settings.scanResponseRequireNonce = false  -- stay off by request

        elseif preset == "ghost" then
            TRP3FW_Settings.phaseCheckMode = "alert_ghost"
            TRP3FW_Settings.mapCheckMode = "alert_ghost"
            TRP3FW_Settings.useWhoQuery = true
            TRP3FW_Settings.blockStartPhase = false
            TRP3FW_Settings.ghostOnStartPhase = true
            TRP3FW_Settings.ghostProfileSwitch = true
            TRP3FW_Settings.spvpEnabled = true
            TRP3FW_Settings.scanResponsePhaseMode = "block"
            TRP3FW_Settings.scanResponseMapMode = "block"
            TRP3FW_Settings.scanResponseRequireNonce = false  -- stay off by request
            EnsureBlankProfilesExist()
        end

        local function isBlocky(mode)
            return mode == "block" or mode == "ghost" or mode == "alert_block" or mode == "alert_ghost"
        end

        if preset == "strict" or preset == "recommended" or preset == "ghost" or preset == "balanced" or preset == "relaxed" then
            TRP3FW_Settings.phaseCheckBatchMode = true
        end

        if preset == "strict" or preset == "recommended" or preset == "relaxed" then
            TRP3FW_Settings.phaseCheckRefundOnNoChange = false
        end

        -- Clear allowed senders cache only if the new mode is more restrictive than the previous one
        local prevPhaseMode = TRP3FW_Settings.phaseCheckMode
        local prevMapMode = TRP3FW_Settings.mapCheckMode
        
        -- Update the settings with the preset values
        TRP3FW_Settings.phaseCheckMode = newPhaseMode
        TRP3FW_Settings.mapCheckMode = newMapMode

        -- Check if either phase or map mode became more restrictive
        if ShouldClearAllowedSenders(TRP3FW_Settings.phaseCheckMode, prevPhaseMode) or 
           ShouldClearAllowedSenders(TRP3FW_Settings.mapCheckMode, prevMapMode) then
            local CI = TRP3FW.CacheInterface
            if CI then CI:Clear("allowedSenders") else TRP3FW.allowedSendersCache = {} end
            TRP3FW:Debug("Flushed allowedSendersCache after preset changed to a more restrictive mode", "cache")
        end

        RequestRefreshUI()
        TRP3FW:Info("Applied preset: "..preset)
    end

    CreateSectionHeader(tab3, "Quick Presets", y3)
    y3 = y3 - 35

    local presets = {
        { key = "relaxed", label = "Relaxed", tooltip = "Phase Off, Map Alert, WHO Off, Batching On, Token Refund Off" },
        { key = "balanced", label = "Balanced", tooltip = "Phase Alert, Map Alert, WHO On, Batching On" },
        { key = "recommended", label = "Recommended", tooltip = "Phase/Map Alert+Block, WHO On, Start-phase block, Batching On, Token Refund Off" },
        { key = "strict", label = "Strict", tooltip = "Phase/Map Alert+Block, WHO On, Start-phase block, Scan replies block, Batching On, Token Refund Off" },
        { key = "ghost", label = "Ghosty", tooltip = "Phase/Map Alert+Ghost, WHO On, Start-phase ghost+switch, Scan replies block, Batching On" },
    }

    local presetX = 20
    for _, preset in ipairs(presets) do
        local btn = CreateFrame("Button", nil, tab3, "UIPanelButtonTemplate")
        btn:SetSize(100, 24)  -- Reduced width to fit all buttons
        btn:SetPoint("TOPLEFT", presetX, y3)
        btn:SetText(preset.label)
        if preset.tooltip then
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(preset.label, 1, 1, 1)
                GameTooltip:AddLine(preset.tooltip, nil, nil, nil, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        btn:SetScript("OnClick", function()
            ApplyPreset(preset.key)
        end)
        presetX = presetX + 110  -- Reduced spacing to fit all buttons
    end

    y3 = y3 - 40

    CreateSectionHeader(tab3, "Location Checking", y3)
    y3 = y3 - 45

    -- Phase check mode dropdown
    uiElements.phaseCheckModeDropdown, uiElements.phaseCheckModeLabel = CreateDropdown(tab3, "Phase Check Mode", "How should TRP3FW respond when someone from a different phase requests your profile? Default: Alert.", 200, "phaseCheckMode")
    uiElements.phaseCheckModeDropdown:SetPoint("TOPLEFT", 20, y3)

    UIDropDownMenu_Initialize(uiElements.phaseCheckModeDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        -- Off
        info.text = "Off"
        info.value = "off"
        info.tooltipTitle = "Off"
        info.tooltipText = "No phase checking (all profile requests allowed)"
        info.func = function()
            TRP3FW_Settings.phaseCheckMode = "off"
            UIDropDownMenu_SetText(uiElements.phaseCheckModeDropdown, "Off")
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        -- Statistics
        info.text = "Statistics Only"
        info.value = "statistics"
        info.tooltipTitle = "Statistics Only"
        info.tooltipText = "Check phase but don't alert or block (for statistics tracking only)"
        info.func = function()
            TRP3FW_Settings.phaseCheckMode = "statistics"
            UIDropDownMenu_SetText(uiElements.phaseCheckModeDropdown, "Statistics Only")
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        -- Alert
        info.text = "Alert"
        info.value = "alert"
        info.tooltipTitle = "Alert"
        info.tooltipText = "Show alert when phase check fails, but still send profile"
        info.func = function()
            TRP3FW_Settings.phaseCheckMode = "alert"
            UIDropDownMenu_SetText(uiElements.phaseCheckModeDropdown, "Alert")
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        -- Block
        info.text = "Block"
        info.value = "block"
        info.tooltipTitle = "Block"
        info.tooltipText = "Block profile send (no profile sent at all)"
        info.func = function()
            local previous = TRP3FW_Settings.phaseCheckMode
            TRP3FW_Settings.phaseCheckMode = "block"
            UIDropDownMenu_SetText(uiElements.phaseCheckModeDropdown, "Block")
            if previous ~= "block" then
                TRP3FW.allowedSendersCache = {}
                TRP3FW:Debug("Flushed allowedSendersCache after phase mode changed to block", "cache")
            end
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        -- Ghost
        info.text = "Ghost (Blank Profile)"
        info.value = "ghost"
        info.tooltipTitle = "Ghost (Blank Profile)"
        info.tooltipText = "Send blank/empty profile instead of blocking"
        info.func = function()
            local previous = TRP3FW_Settings.phaseCheckMode
            TRP3FW_Settings.phaseCheckMode = "ghost"
            UIDropDownMenu_SetText(uiElements.phaseCheckModeDropdown, "Ghost (Blank Profile)")
            if previous ~= "ghost" then
                TRP3FW.allowedSendersCache = {}
                TRP3FW:Debug("Flushed allowedSendersCache after phase mode changed to ghost", "cache")
            end
            EnsureBlankProfilesExist()
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        -- Alert + Block
        info.text = "Alert + Block"
        info.value = "alert_block"
        info.tooltipTitle = "Alert + Block"
        info.tooltipText = "Show alert AND block profile send"
        info.func = function()
            local previous = TRP3FW_Settings.phaseCheckMode
            TRP3FW_Settings.phaseCheckMode = "alert_block"
            UIDropDownMenu_SetText(uiElements.phaseCheckModeDropdown, "Alert + Block")
            if previous ~= "alert_block" then
                TRP3FW.allowedSendersCache = {}
                TRP3FW:Debug("Flushed allowedSendersCache after phase mode changed to alert+block", "cache")
            end
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        -- Alert + Ghost
        info.text = "Alert + Ghost"
        info.value = "alert_ghost"
        info.tooltipTitle = "Alert + Ghost"
        info.tooltipText = "Show alert AND send blank profile"
        info.func = function()
            local previous = TRP3FW_Settings.phaseCheckMode
            TRP3FW_Settings.phaseCheckMode = "alert_ghost"
            UIDropDownMenu_SetText(uiElements.phaseCheckModeDropdown, "Alert + Ghost")
            if previous ~= "alert_ghost" then
                TRP3FW.allowedSendersCache = {}
                TRP3FW:Debug("Flushed allowedSendersCache after phase mode changed to alert+ghost", "cache")
            end
            EnsureBlankProfilesExist()
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)
    end)
    
    -- Map check mode dropdown (Side-by-side)
    uiElements.mapCheckModeDropdown, uiElements.mapCheckModeLabel = CreateDropdown(tab3, "Map Check Mode", "How should TRP3FW respond when someone from a different map requests your profile? Default: Alert.", 200, "mapCheckMode")
    uiElements.mapCheckModeDropdown:SetPoint("TOPLEFT", 300, y3)

    UIDropDownMenu_Initialize(uiElements.mapCheckModeDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        -- Off
        info.text = "Off"
        info.value = "off"
        info.tooltipTitle = "Off"
        info.tooltipText = "No map checking (all profile requests allowed)"
        info.func = function()
            TRP3FW_Settings.mapCheckMode = "off"
            UIDropDownMenu_SetText(uiElements.mapCheckModeDropdown, "Off")
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        -- Statistics
        info.text = "Statistics Only"
        info.value = "statistics"
        info.tooltipTitle = "Statistics Only"
        info.tooltipText = "Check map but don't alert or block (for statistics tracking only)"
        info.func = function()
            TRP3FW_Settings.mapCheckMode = "statistics"
            UIDropDownMenu_SetText(uiElements.mapCheckModeDropdown, "Statistics Only")
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        -- Alert
        info.text = "Alert"
        info.value = "alert"
        info.tooltipTitle = "Alert"
        info.tooltipText = "Show alert when map check fails, but still send profile"
        info.func = function()
            TRP3FW_Settings.mapCheckMode = "alert"
            UIDropDownMenu_SetText(uiElements.mapCheckModeDropdown, "Alert")
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        -- Block
        info.text = "Block"
        info.value = "block"
        info.tooltipTitle = "Block"
        info.tooltipText = "Block profile send (no profile sent at all)"
        info.func = function()
            local previousMode = TRP3FW_Settings.mapCheckMode
            TRP3FW_Settings.mapCheckMode = "block"
            UIDropDownMenu_SetText(uiElements.mapCheckModeDropdown, "Block")
            if ShouldClearAllowedSenders(TRP3FW_Settings.mapCheckMode, previousMode) then
                local CI = TRP3FW.CacheInterface
                if CI then CI:Clear("allowedSenders") else TRP3FW.allowedSendersCache = {} end
                TRP3FW:Debug("Flushed allowedSendersCache after map mode changed to block", "cache")
            end
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        -- Ghost
        info.text = "Ghost (Blank Profile)"
        info.value = "ghost"
        info.tooltipTitle = "Ghost (Blank Profile)"
        info.tooltipText = "Send blank/empty profile instead of blocking"
        info.func = function()
            local previous = TRP3FW_Settings.mapCheckMode
            TRP3FW_Settings.mapCheckMode = "ghost"
            UIDropDownMenu_SetText(uiElements.mapCheckModeDropdown, "Ghost (Blank Profile)")
            if previous ~= "ghost" then
                TRP3FW.allowedSendersCache = {}
                TRP3FW:Debug("Flushed allowedSendersCache after map mode changed to ghost", "cache")
            end
            EnsureBlankProfilesExist()
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        -- Alert + Block
        info.text = "Alert + Block"
        info.value = "alert_block"
        info.tooltipTitle = "Alert + Block"
        info.tooltipText = "Show alert AND block profile send"
        info.func = function()
            local previousMode = TRP3FW_Settings.mapCheckMode
            TRP3FW_Settings.mapCheckMode = "alert_block"
            UIDropDownMenu_SetText(uiElements.mapCheckModeDropdown, "Alert + Block")
            if ShouldClearAllowedSenders(TRP3FW_Settings.mapCheckMode, previousMode) then
                local CI = TRP3FW.CacheInterface
                if CI then CI:Clear("allowedSenders") else TRP3FW.allowedSendersCache = {} end
                TRP3FW:Debug("Flushed allowedSendersCache after map mode changed to alert+block", "cache")
            end
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        -- Alert + Ghost
        info.text = "Alert + Ghost"
        info.value = "alert_ghost"
        info.tooltipTitle = "Alert + Ghost"
        info.tooltipText = "Show alert AND send blank profile"
        info.func = function()
            local previousMode = TRP3FW_Settings.mapCheckMode
            TRP3FW_Settings.mapCheckMode = "alert_ghost"
            UIDropDownMenu_SetText(uiElements.mapCheckModeDropdown, "Alert + Ghost")
            if ShouldClearAllowedSenders(TRP3FW_Settings.mapCheckMode, previousMode) then
                local CI = TRP3FW.CacheInterface
                if CI then CI:Clear("allowedSenders") else TRP3FW.allowedSendersCache = {} end
                TRP3FW:Debug("Flushed allowedSendersCache after map mode changed to alert+ghost", "cache")
            end
            EnsureBlankProfilesExist()
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)
    end)
    y3 = y3 - 65

    uiElements.allowGroupPhaseBypass = CreateCheckbox(tab3, "Allow Party/Raid Auto-Allow", "When enabled, party/raid members automatically count as in-phase and skip normal phase/map checks (legacy behavior). Disable to require full checks and alerts for group members.", "allowGroupPhaseBypass")
    uiElements.allowGroupPhaseBypass:SetPoint("TOPLEFT", 20, y3)
    uiElements.allowGroupPhaseBypass:SetScript("OnClick", function(self)
        TRP3FW_Settings.allowGroupPhaseBypass = self:GetChecked()
    end)
    y3 = y3 - 35

    y3 = y3 - 10
    CreateSectionHeader(tab3, "Map Scan Replies", y3)
    y3 = y3 - 45

    uiElements.scanResponsePhaseModeDropdown, uiElements.scanResponsePhaseModeLabel = CreateDropdown(tab3, "Different-Phase Behavior", "What to do when phase check shows the scanner is in another phase", 200, "scanResponsePhaseMode")
    uiElements.scanResponsePhaseModeDropdown:SetPoint("TOPLEFT", 20, y3)

    UIDropDownMenu_Initialize(uiElements.scanResponsePhaseModeDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()

        info.text = "Off"
        info.tooltipText = "Do not phase-check scan requesters"
        info.func = function()
            TRP3FW_Settings.scanResponsePhaseMode = "off"
            UIDropDownMenu_SetText(uiElements.scanResponsePhaseModeDropdown, "Off")
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        info.text = "Statistics Only"
        info.tooltipText = "Check phase for statistics, but always allow (no alert)"
        info.func = function()
            TRP3FW_Settings.scanResponsePhaseMode = "statistics"
            UIDropDownMenu_SetText(uiElements.scanResponsePhaseModeDropdown, "Statistics Only")
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        info.text = "Alert (send anyway)"
        info.tooltipText = "Send the scan reply but warn in chat when the scanner is in another phase"
        info.func = function()
            TRP3FW_Settings.scanResponsePhaseMode = "alert"
            UIDropDownMenu_SetText(uiElements.scanResponsePhaseModeDropdown, "Alert (send anyway)")
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        info.text = "Block (silent)"
        info.tooltipText = "Block the scan reply silently (no notification)"
        info.func = function()
            local previousMode = TRP3FW_Settings.scanResponsePhaseMode
            TRP3FW_Settings.scanResponsePhaseMode = "block"
            UIDropDownMenu_SetText(uiElements.scanResponsePhaseModeDropdown, "Block (silent)")
            if ShouldClearAllowedSenders(TRP3FW_Settings.scanResponsePhaseMode, previousMode) then
                local CI = TRP3FW.CacheInterface
                if CI then CI:Clear("allowedSenders") else TRP3FW.allowedSendersCache = {} end
                TRP3FW:Debug("[Scan Reply] Flushed allowedSendersCache after scan phase mode changed to block", "cache")
            end
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        info.text = "Alert + Block"
        info.tooltipText = "Block the scan reply and show an alert"
        info.func = function()
            local previousMode = TRP3FW_Settings.scanResponsePhaseMode
            TRP3FW_Settings.scanResponsePhaseMode = "alert_block"
            UIDropDownMenu_SetText(uiElements.scanResponsePhaseModeDropdown, "Alert + Block")
            if ShouldClearAllowedSenders(TRP3FW_Settings.scanResponsePhaseMode, previousMode) then
                local CI = TRP3FW.CacheInterface
                if CI then CI:Clear("allowedSenders") else TRP3FW.allowedSendersCache = {} end
                TRP3FW:Debug("[Scan Reply] Flushed allowedSendersCache after scan phase mode changed to alert_block", "cache")
            end
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)
    end)

    y3 = y3 - 50

    uiElements.scanResponseWhoModeDropdown, uiElements.scanResponseWhoModeLabel = CreateDropdown(tab3, "Different-Map Behavior", "What to do when WHO shows the scanner is in another zone/map", 200, "scanResponseMapMode")
    uiElements.scanResponseWhoModeDropdown:SetPoint("TOPLEFT", 20, y3)

    UIDropDownMenu_Initialize(uiElements.scanResponseWhoModeDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()

        info.text = "Off"
        info.tooltipText = "Do not WHO-check scan requesters"
        info.func = function()
            TRP3FW_Settings.scanResponseMapMode = "off"
            UIDropDownMenu_SetText(uiElements.scanResponseWhoModeDropdown, "Off")
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        info.text = "Statistics Only"
        info.tooltipText = "Check map for statistics, but always allow (no alert)"
        info.func = function()
            TRP3FW_Settings.scanResponseMapMode = "statistics"
            UIDropDownMenu_SetText(uiElements.scanResponseWhoModeDropdown, "Statistics Only")
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        info.text = "Alert (send anyway)"
        info.tooltipText = "Send the scan reply but warn in chat when the scanner is in another zone/map"
        info.func = function()
            TRP3FW_Settings.scanResponseMapMode = "alert"
            UIDropDownMenu_SetText(uiElements.scanResponseWhoModeDropdown, "Alert (send anyway)")
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        info.text = "Block (silent)"
        info.tooltipText = "Block the scan reply silently (no notification)"
        info.func = function()
            local previousMode = TRP3FW_Settings.scanResponseMapMode
            TRP3FW_Settings.scanResponseMapMode = "block"
            UIDropDownMenu_SetText(uiElements.scanResponseWhoModeDropdown, "Block (silent)")
            if ShouldClearAllowedSenders(TRP3FW_Settings.scanResponseMapMode, previousMode) then
                local CI = TRP3FW.CacheInterface
                if CI then CI:Clear("allowedSenders") else TRP3FW.allowedSendersCache = {} end
                TRP3FW:Debug("[Scan Reply] Flushed allowedSendersCache after scan map mode changed to block", "cache")
            end
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        info.text = "Alert + Block"
        info.tooltipText = "Block the scan reply and show an alert"
        info.func = function()
            local previousMode = TRP3FW_Settings.scanResponseMapMode
            TRP3FW_Settings.scanResponseMapMode = "alert_block"
            UIDropDownMenu_SetText(uiElements.scanResponseWhoModeDropdown, "Alert + Block")
            if ShouldClearAllowedSenders(TRP3FW_Settings.scanResponseMapMode, previousMode) then
                local CI = TRP3FW.CacheInterface
                if CI then CI:Clear("allowedSenders") else TRP3FW.allowedSendersCache = {} end
                TRP3FW:Debug("[Scan Reply] Flushed allowedSendersCache after scan map mode changed to alert_block", "cache")
            end
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)
    end)

    y3 = y3 - 50

    uiElements.scanResponseRequireNonce = CreateCheckbox(tab3, "Require Nonce on Scan Replies", "When enabled, ignore map scan replies that do not include the issued nonce token (older scanners may be ignored).", "scanResponseRequireNonce")
    uiElements.scanResponseRequireNonce:SetPoint("TOPLEFT", 20, y3)
    uiElements.scanResponseRequireNonce:SetScript("OnClick", function(self)
        TRP3FW_Settings.scanResponseRequireNonce = self:GetChecked()
    end)
    y3 = y3 - 30

    uiElements.scanResponseCacheEnabled = CreateCheckbox(tab3, "Cache Scan Requesters", "When replying to map scans, cache WHO results (if a WHO query ran). Does not add to interaction/send caches.", "scanResponseCacheEnabled")
    uiElements.scanResponseCacheEnabled:SetPoint("TOPLEFT", 20, y3)
    uiElements.scanResponseCacheEnabled:SetScript("OnClick", function(self)
        TRP3FW_Settings.scanResponseCacheEnabled = self:GetChecked()
    end)
    y3 = y3 - 30

    uiElements.scanResponseAllowCacheBypass = CreateCheckbox(tab3, "Bypass with Existing Caches", "If scan requester is already in allowed or interaction cache (unrefreshed), skip the WHO gate and reply immediately.", "scanResponseAllowCacheBypass")
    uiElements.scanResponseAllowCacheBypass:SetPoint("TOPLEFT", 20, y3)
    uiElements.scanResponseAllowCacheBypass:SetScript("OnClick", function(self)
        TRP3FW_Settings.scanResponseAllowCacheBypass = self:GetChecked()
    end)
    y3 = y3 - 30

    uiElements.scanResponseAllowGroupBypass = CreateCheckbox(tab3, "Always Allow Party/Raid", "If the scan requester is in your party or raid, always reply (skips phase/map/WHO gates).", "scanResponseAllowGroupBypass")
    uiElements.scanResponseAllowGroupBypass:SetPoint("TOPLEFT", 20, y3)
    uiElements.scanResponseAllowGroupBypass:SetScript("OnClick", function(self)
        TRP3FW_Settings.scanResponseAllowGroupBypass = self:GetChecked()
    end)
    y3 = y3 - 30

    uiElements.scanResponseWhitelistEnabled = CreateCheckbox(tab3, "Enable Scan Reply Whitelist", "If disabled, names in the whitelist are ignored (no bypass).", "scanResponseWhitelistEnabled")
    uiElements.scanResponseWhitelistEnabled:SetPoint("TOPLEFT", 20, y3)
    uiElements.scanResponseWhitelistEnabled:SetScript("OnClick", function(self)
        TRP3FW_Settings.scanResponseWhitelistEnabled = self:GetChecked()
        RequestRefreshUI()
    end)
    y3 = y3 - 30

    local scanWhitelistLabel = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scanWhitelistLabel:SetPoint("TOPLEFT", 20, y3)
    scanWhitelistLabel:SetText("Scan Reply Whitelist (one name per line):")
    y3 = y3 - 20

    local scanWhitelistScroll = CreateFrame("ScrollFrame", nil, tab3, "UIPanelScrollFrameTemplate")
    scanWhitelistScroll:SetPoint("TOPLEFT", 20, y3)
    scanWhitelistScroll:SetSize(500, 90)
    uiElements.scanResponseWhitelistScroll = scanWhitelistScroll

    local scanWhitelistEdit = CreateFrame("EditBox", nil, scanWhitelistScroll)
    scanWhitelistEdit:SetMultiLine(true)
    scanWhitelistEdit:SetFontObject(ChatFontNormal)
    scanWhitelistEdit:SetWidth(480)
    scanWhitelistEdit:SetHeight(90)
    scanWhitelistEdit:SetAutoFocus(false)
    scanWhitelistEdit:SetMaxLetters(3000)
    local function sanitizeScanWhitelist(text)
        local seen = {}
        local out = {}
        for line in string.gmatch(text or "", "[^\r\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
                local clean = TRP3FW:SanitizePlayerName(trimmed) or TRP3FW:CleanPlayerName(trimmed)
                if clean and not seen[clean:lower()] then
                    seen[clean:lower()] = true
                    table.insert(out, clean)
                end
            end
        end
        return table.concat(out, "\n")
    end

    scanWhitelistEdit:SetText(TRP3FW_Settings.scanResponseWhitelist or "")
    scanWhitelistEdit:SetScript("OnTextChanged", function(self)
        TRP3FW_Settings.scanResponseWhitelist = self:GetText()
    end)
    scanWhitelistEdit:SetScript("OnEditFocusLost", function(self)
        local cleaned = sanitizeScanWhitelist(self:GetText())
        if cleaned ~= self:GetText() then
            self:SetText(cleaned)
        end
        TRP3FW_Settings.scanResponseWhitelist = cleaned
    end)
    scanWhitelistScroll:SetScrollChild(scanWhitelistEdit)

    local scanWhitelistBG = CreateFrame("Frame", nil, tab3, BackdropTemplateMixin and "BackdropTemplate")
    scanWhitelistBG:SetPoint("TOPLEFT", scanWhitelistScroll, -6, 6)
    scanWhitelistBG:SetPoint("BOTTOMRIGHT", scanWhitelistScroll, 26, -6)
    scanWhitelistBG:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    scanWhitelistBG:SetBackdropColor(0, 0, 0, 0.25)
    scanWhitelistBG:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    uiElements.scanResponseWhitelistEdit = scanWhitelistEdit

    y3 = y3 - 120
    y3 = y3 - 20
    y3 = y3 - 10  -- Extra spacing before whitelist section
    local whitelistSectionTop = y3
    CreateSectionHeader(tab3, "Whitelist Bypass (Advanced)", y3)
    y3 = y3 - 35

    local whitelistInfo = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    whitelistInfo:SetPoint("TOPLEFT", 20, y3)
    whitelistInfo:SetWidth(520)
    whitelistInfo:SetJustifyH("LEFT")
    whitelistInfo:SetText("|cffff6600Warning:|r Players listed below will |cffffff00always|r receive your current profile. Phase/map checks, alerts, blocking, ghost mode, and start-phase protections are skipped for them.")
    y3 = y3 - 45

    uiElements.whitelistBypassEnabled = CreateCheckbox(tab3, "Enable Whitelist Bypass", "Allow listed names to bypass all security checks and always receive your active profile.", "whitelistEnabled")
    uiElements.whitelistBypassEnabled:SetPoint("TOPLEFT", 20, y3)
    uiElements.whitelistBypassEnabled:SetScript("OnClick", function(self)
        if self:GetChecked() then
            -- Require confirmation before enabling
            self:SetChecked(false)
            StaticPopup_Show("TRP3FW_WHITELIST_CONFIRM")
        else
            TRP3FW_Settings.whitelistEnabled = false
            TRP3FW:RefreshWhitelistCache()
            if uiElements.whitelistEdit then
                uiElements.whitelistEdit:SetEnabled(false)
                uiElements.whitelistEdit:SetAlpha(0.5)
            end
            if uiElements.whitelistScroll then
                uiElements.whitelistScroll:SetAlpha(0.5)
            end
        end
    end)
    y3 = y3 - 35

    local whitelistNameLabel = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    whitelistNameLabel:SetPoint("TOPLEFT", 20, y3)
    whitelistNameLabel:SetText("Names (one per line):")
    y3 = y3 - 20

    local whitelistScroll = CreateFrame("ScrollFrame", nil, tab3, "UIPanelScrollFrameTemplate")
    whitelistScroll:SetPoint("TOPLEFT", 20, y3)
    whitelistScroll:SetSize(500, 100)
    uiElements.whitelistScroll = whitelistScroll

    local whitelistEdit = CreateFrame("EditBox", nil, whitelistScroll)
    whitelistEdit:SetMultiLine(true)
    whitelistEdit:SetFontObject(ChatFontNormal)
    whitelistEdit:SetWidth(480)
    whitelistEdit:SetHeight(90)
    whitelistEdit:SetAutoFocus(false)
    whitelistEdit:SetMaxLetters(3000)
    whitelistEdit:SetText(TRP3FW_Settings.whitelistEntries or "")
    local function sanitizeWhitelist(text)
        local seen = {}
        local out = {}
        for line in string.gmatch(text or "", "[^\r\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
                local clean = TRP3FW:SanitizePlayerName(trimmed) or TRP3FW:CleanPlayerName(trimmed)
                if clean and not seen[clean:lower()] then
                    seen[clean:lower()] = true
                    table.insert(out, clean)
                end
            end
        end
        return table.concat(out, "\n")
    end

    whitelistEdit:SetScript("OnTextChanged", function(self)
        TRP3FW_Settings.whitelistEntries = self:GetText()
    end)
    whitelistEdit:SetScript("OnEditFocusLost", function(self)
        local cleaned = sanitizeWhitelist(self:GetText())
        if cleaned ~= self:GetText() then
            self:SetText(cleaned)
        end
        TRP3FW_Settings.whitelistEntries = cleaned
    end)
    whitelistScroll:SetScrollChild(whitelistEdit)

    local whitelistBG = CreateFrame("Frame", nil, tab3, BackdropTemplateMixin and "BackdropTemplate")
    whitelistBG:SetPoint("TOPLEFT", whitelistScroll, -6, 6)
    whitelistBG:SetPoint("BOTTOMRIGHT", whitelistScroll, 26, -6) -- account for scrollbar width
    whitelistBG:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    whitelistBG:SetBackdropColor(0, 0, 0, 0.25)
    whitelistBG:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    uiElements.whitelistEdit = whitelistEdit

    -- Apply enabled state based on current setting
    do
        local enabled = TRP3FW_Settings.whitelistEnabled
        whitelistEdit:SetEnabled(enabled)
        whitelistEdit:SetAlpha(enabled and 1 or 0.5)
        whitelistScroll:SetAlpha(enabled and 1 or 0.5)
    end

    y3 = y3 - 120

    local whitelistSectionBottom = y3
    local whitelistHeight = (whitelistSectionTop - whitelistSectionBottom) + 30
    local whitelistDanger = CreateFrame("Frame", nil, tab3, BackdropTemplateMixin and "BackdropTemplate")
    whitelistDanger:SetPoint("TOPLEFT", tab3, "TOPLEFT", 10, whitelistSectionTop + 20)
    whitelistDanger:SetPoint("RIGHT", tab3, "RIGHT", -2, 0)
    whitelistDanger:SetHeight(whitelistHeight)
    whitelistDanger:SetFrameStrata("BACKGROUND")
    whitelistDanger:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    whitelistDanger:SetBackdropColor(0.2, 0, 0, 0.2)
    whitelistDanger:SetBackdropBorderColor(0.8, 0.2, 0.2, 0.8)

    y3 = y3 - 10
    CreateSectionHeader(tab3, "Other Options", y3)
    y3 = y3 - 35
    y3 = y3 - 15  -- Push controls below the header line



    -- Ghost profile dropdown (for MSP ghost mode)
    uiElements.ghostProfileDropdown, uiElements.ghostProfileLabel = CreateDropdown(tab3, "Ghost Profile", "Choose which profile to send in ghost mode (blank = send empty profile)", 300, "ghostProfileName")
    uiElements.ghostProfileDropdown:SetPoint("TOPLEFT", 20, y3)

    -- Initialize dropdown on open
    UIDropDownMenu_Initialize(uiElements.ghostProfileDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        -- Add detected RP addon name as section header
        local addonName = TRP3FW:GetDetectedAddonName()
        if addonName then
            info.text = "--- "..addonName.." Profiles ---"
            info.isTitle = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info)
            info.isTitle = nil
            info.notCheckable = nil

            -- Get all profiles from adapter
            local profiles = TRP3FW:GetAllProfiles()

            if #profiles > 0 then
                -- Add each profile
                for _, profile in ipairs(profiles) do
                    -- Create fresh info for each profile to avoid field carryover
                    info = UIDropDownMenu_CreateInfo()
                    info.text = profile.name
                    if profile.isCurrent then
                        info.text = info.text .. " (current)"
                    end
                    info.value = profile.id
                    info.func = function()
                        TRP3FW_Settings.ghostProfileID = profile.id
                        UIDropDownMenu_SetText(uiElements.ghostProfileDropdown, profile.name)
                        TRP3FW:Debug("Ghost profile set to: "..profile.name.." (ID: "..tostring(profile.id)..")", "ui")

                        -- If TRP3FW_BLANK is selected, validate/create it
                        if profile.name == "TRP3FW_BLANK" then
                            EnsureBlankProfilesExist()
                        end
                    end
                    info.checked = (TRP3FW_Settings.ghostProfileID == profile.id)
                    UIDropDownMenu_AddButton(info)
                end
            else
                -- No profiles found
                info.text = "(No profiles found)"
                info.disabled = true
                info.notCheckable = true
                UIDropDownMenu_AddButton(info)
            end
        else
            -- No RP addon detected
            info.text = "(No RP addon detected)"
            info.disabled = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Set initial display text
    if TRP3FW_Settings.ghostProfileID then
        local profile = TRP3FW:GetProfileByID(TRP3FW_Settings.ghostProfileID)
        if profile then
            UIDropDownMenu_SetText(uiElements.ghostProfileDropdown, profile.name)
        else
            UIDropDownMenu_SetText(uiElements.ghostProfileDropdown, "TRP3FW_BLANK")
        end
    else
        UIDropDownMenu_SetText(uiElements.ghostProfileDropdown, "TRP3FW_BLANK")
    end
    y3 = y3 - 35  -- Tighter spacing before the warning label


    uiElements.epsilonWarning = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    uiElements.epsilonWarning:SetPoint("TOPLEFT", 20, y3)
    uiElements.epsilonWarning:SetText("|cffff6600Epsilon-only options hidden (API unavailable)|r")
    uiElements.epsilonWarning:Hide()
    y3 = y3 - 25

    -- WHO behavior is fixed in the current build; leave a note instead of toggles
    local whoLocked = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    whoLocked:SetPoint("TOPLEFT", 20, y3)
    whoLocked:SetText("|cffffff00WHO behavior uses default UI for user /who; addon WHO is automatic.|r")
    y3 = y3 - 25

	uiElements.suppressAllWhoOutput = CreateCheckbox(tab3, "Suppress WHO Output", "Hide all WHO results in chat (prevents spam from manual /who or TRP3 scans).", "suppressAllWhoOutput")
	uiElements.suppressAllWhoOutput:SetPoint("TOPLEFT", 20, y3)
	uiElements.suppressAllWhoOutput:SetScript("OnClick", function(self)
		TRP3FW_Settings.suppressAllWhoOutput = self:GetChecked()
	end)
    table.insert(epsilonControls, uiElements.suppressAllWhoOutput)
    y3 = y3 - 30

    uiElements.blockStartPhase = CreateCheckbox(tab3, "Block in Start Phase", "Block all transmissions in start phase (169).", "blockStartPhase")
    uiElements.blockStartPhase:SetPoint("TOPLEFT", 20, y3)
    uiElements.blockStartPhase:SetScript("OnClick", function(self)
        TRP3FW_Settings.blockStartPhase = self:GetChecked()
        -- If ghost mode in start phase is also enabled, ensure blank profiles exist
        if TRP3FW_Settings.ghostOnStartPhase then
            EnsureBlankProfilesExist()
        end
    end)
    table.insert(epsilonControls, uiElements.blockStartPhase)
    y3 = y3 - 30

    uiElements.ghostOnStartPhase = CreateCheckbox(tab3, "Ghost Mode in Start Phase", "Send blank profile instead of blocking in start phase (169).", "ghostOnStartPhase")
    uiElements.ghostOnStartPhase:SetPoint("TOPLEFT", 40, y3)  -- Indent to show it's a sub-option
    uiElements.ghostOnStartPhase:SetScript("OnClick", function(self)
        TRP3FW_Settings.ghostOnStartPhase = self:GetChecked()
        EnsureBlankProfilesExist()
    end)
    table.insert(epsilonControls, uiElements.ghostOnStartPhase)
    y3 = y3 - 30

    uiElements.ghostProfileSwitch = CreateCheckbox(tab3, "Auto-Switch to Blank Profile", "Automatically switch to blank profile in start phase (169) and map 1605.", "ghostProfileSwitch")
    uiElements.ghostProfileSwitch:SetPoint("TOPLEFT", 20, y3)
    uiElements.ghostProfileSwitch:SetScript("OnClick", function(self)
        TRP3FW_Settings.ghostProfileSwitch = self:GetChecked()
        EnsureBlankProfilesExist()
    end)
    table.insert(epsilonControls, uiElements.ghostProfileSwitch)
    y3 = y3 - 45

    -- Info box explaining the safety feature
    local safetyInfoBox = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    safetyInfoBox:SetPoint("TOPLEFT", 20, y3)
    safetyInfoBox:SetWidth(560)
    safetyInfoBox:SetJustifyH("LEFT")
    safetyInfoBox:SetText("|cff00ccffℹ Info:|r This safety feature automatically switches your RP profile when entering phase 169 and map 1605. Using 'TRP3FW_BLANK' (recommended) ensures the profile is completely blank and auto-validated. Custom profiles bypass validation - use at your own risk.")
    y3 = y3 - 60

    -- Exclusion list (optional)
    uiElements.ghostProfileWhitelistEnabled = CreateCheckbox(tab3, "Exclude Phases/Maps (Keep Real Profile)", "When enabled, TRP3FW will auto-switch to the blank profile everywhere on Epsilon except the phases/maps listed below (those keep your real profile). One entry per line: '169' (phase only) or '169,1605' (phase+map). Map is optional; if omitted, any map in that phase is excluded from auto-switching.", "ghostProfileWhitelistEnabled")
    uiElements.ghostProfileWhitelistEnabled:SetPoint("TOPLEFT", 20, y3)
    uiElements.ghostProfileWhitelistEnabled:SetScript("OnClick", function(self)
        TRP3FW_Settings.ghostProfileWhitelistEnabled = self:GetChecked()
        if uiElements.ghostProfileWhitelistEdit then
            local enabled = self:GetChecked()
            uiElements.ghostProfileWhitelistEdit:SetEnabled(enabled)
            uiElements.ghostProfileWhitelistEdit:SetAlpha(enabled and 1 or 0.5)
            uiElements.ghostProfileWhitelistScroll:SetAlpha(enabled and 1 or 0.5)
        end
    end)
    table.insert(epsilonControls, uiElements.ghostProfileWhitelistEnabled)
    y3 = y3 - 35

    local whitelistLabel = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    whitelistLabel:SetPoint("TOPLEFT", 40, y3)
    whitelistLabel:SetText("Exclusion entries (one per line):")
    y3 = y3 - 20

    -- Scrollable multi-line edit box for whitelist entries
    local whitelistScroll = CreateFrame("ScrollFrame", nil, tab3, "UIPanelScrollFrameTemplate")
    whitelistScroll:SetPoint("TOPLEFT", 40, y3)
    whitelistScroll:SetSize(520, 100)
    uiElements.ghostProfileWhitelistScroll = whitelistScroll
    table.insert(epsilonControls, whitelistScroll)

    local whitelistEdit = CreateFrame("EditBox", nil, whitelistScroll)
    whitelistEdit:SetMultiLine(true)
    whitelistEdit:SetFontObject(ChatFontNormal)
    whitelistEdit:SetWidth(500)
    whitelistEdit:SetHeight(100)
    whitelistEdit:SetAutoFocus(false)
    whitelistEdit:SetMaxLetters(3000)
    whitelistEdit:SetText(TRP3FW_Settings.ghostProfileWhitelist or "")
    whitelistEdit:SetScript("OnTextChanged", function(self)
        TRP3FW_Settings.ghostProfileWhitelist = self:GetText()
    end)
    whitelistEdit:SetScript("OnEditFocusLost", function(self)
        local seen = {}
        local out = {}
        for line in string.gmatch(self:GetText() or "", "[^\r\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
                -- Accept patterns like "169" or "169,1605"
                local phase, map = trimmed:match("^(%d+)%s*,%s*(%d+)$")
                if not phase then
                    phase = trimmed:match("^(%d+)$")
                end
                if phase then
                    local key = phase .. (map or "")
                    if not seen[key] then
                        seen[key] = true
                        if map then
                            table.insert(out, phase..","..map)
                        else
                            table.insert(out, phase)
                        end
                    end
                end
            end
        end
        local cleaned = table.concat(out, "\n")
        if cleaned ~= self:GetText() then
            self:SetText(cleaned)
        end
        TRP3FW_Settings.ghostProfileWhitelist = cleaned
    end)
    whitelistScroll:SetScrollChild(whitelistEdit)

    -- Simple backdrop for readability
    local whitelistBG = CreateFrame("Frame", nil, tab3, BackdropTemplateMixin and "BackdropTemplate")
    whitelistBG:SetPoint("TOPLEFT", whitelistScroll, -6, 6)
    whitelistBG:SetPoint("BOTTOMRIGHT", whitelistScroll, 26, -6) -- account for scrollbar width
    whitelistBG:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    whitelistBG:SetBackdropColor(0, 0, 0, 0.25)
    whitelistBG:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    uiElements.ghostProfileWhitelistEdit = whitelistEdit
    table.insert(epsilonControls, whitelistEdit)

    -- Apply enabled state based on current setting
    do
        local enabled = TRP3FW_Settings.ghostProfileWhitelistEnabled
        whitelistEdit:SetEnabled(enabled)
        whitelistEdit:SetAlpha(enabled and 1 or 0.5)
        whitelistScroll:SetAlpha(enabled and 1 or 0.5)
    end

    y3 = y3 - 120

    -- ========== SPVP (Secure Phase Verification Protocol) v2.5 ==========
    CreateSectionHeader(tab3, "SPVP (Cryptographic Phase Verification)", y3)
    y3 = y3 - 35

    -- Info box explaining SPVP
    local spvpInfoBox = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spvpInfoBox:SetPoint("TOPLEFT", 20, y3)
    spvpInfoBox:SetWidth(560)
    spvpInfoBox:SetJustifyH("LEFT")
    spvpInfoBox:SetText("|cff00ccffℹ SPVP Info:|r SPVP uses cryptographic phase verification as a fallback when normal location checks fail. Requires phase owners to set a security key (salt). Players in the same phase can prove it cryptographically without physical proximity checks.")
    y3 = y3 - 50

    uiElements.spvpModeDropdown, uiElements.spvpModeLabel = CreateDropdown(tab3, "SPVP Mode", "Control how Secure Phase Verification Protocol is used.\n\n|cff00ff00SPVP verifies phase presence cryptographically using a shared secret (salt).|r\n\n|cffffcc00Modes:|r\n• |cffffffffOptional:|r Verify after standard checks (Audit)\n• |cffffffffPreferred:|r Verify before checks (Performance)\n• |cffffffffRequired:|r Strict verification (Security)", 220, "spvpMode")
    uiElements.spvpModeDropdown:SetPoint("TOPLEFT", 20, y3)

    UIDropDownMenu_Initialize(uiElements.spvpModeDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()

        info.text = "Off"
        info.value = "off"
        info.tooltipTitle = "Off"
        info.tooltipText = "Disable Secure Phase Verification Protocol. Only standard location checks (targeting, WHO queries, map scans) will be used."
        info.func = function()
            TRP3FW_Settings.spvpMode = "off"
            TRP3FW_Settings.spvpEnabled = false
            UIDropDownMenu_SetText(uiElements.spvpModeDropdown, "Off")
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        info.text = "Optional (Post-Check)"
        info.value = "optional"
        info.tooltipTitle = "Optional"
        info.tooltipText = "Run standard location checks first. If the request is allowed, an SPVP handshake is performed in the background to 'upgrade' the trust level for future requests. Best for non-intrusive auditing without risk of protocol delays."
        info.func = function()
            TRP3FW_Settings.spvpMode = "optional"
            TRP3FW_Settings.spvpEnabled = true
            UIDropDownMenu_SetText(uiElements.spvpModeDropdown, "Optional (Post-Check)")
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        info.text = "Preferred (Pre-Check)"
        info.value = "preferred"
        info.tooltipTitle = "Preferred"
        info.tooltipText = "Perform an SPVP handshake before standard checks. If cryptographically verified, standard phase checks are skipped, significantly improving performance. Falls back to standard checks if SPVP fails or times out (Recommended)."
        info.func = function()
            TRP3FW_Settings.spvpMode = "preferred"
            TRP3FW_Settings.spvpEnabled = true
            UIDropDownMenu_SetText(uiElements.spvpModeDropdown, "Preferred (Pre-Check)")
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)

        info.text = "Required (Strict)"
        info.value = "required"
        info.tooltipTitle = "Required"
        info.tooltipText = "Strictly require cryptographic proof of phase presence. If SPVP fails or times out, the request is blocked immediately. Offers the highest security against remote spoofing but requires the peer to also have TRP3FW."
        info.func = function()
            TRP3FW_Settings.spvpMode = "required"
            TRP3FW_Settings.spvpEnabled = true
            UIDropDownMenu_SetText(uiElements.spvpModeDropdown, "Required (Strict)")
            RequestRefreshUI()
        end
        UIDropDownMenu_AddButton(info)
    end)
    table.insert(epsilonControls, uiElements.spvpModeDropdown)
    y3 = y3 - 50

    uiElements.spvpAutoInitialize = CreateCheckbox(tab3, "Auto-Initialize Salts", "Automatically generate security keys when you enter phases you own (phase owners/officers only).", "spvpAutoInitialize")
    uiElements.spvpAutoInitialize:SetPoint("TOPLEFT", 40, y3)  -- Indent
    uiElements.spvpAutoInitialize:SetScript("OnClick", function(self)
        TRP3FW_Settings.spvpAutoInitialize = self:GetChecked()
    end)
    table.insert(epsilonControls, uiElements.spvpAutoInitialize)
    y3 = y3 - 35

    -- Block Duration slider
    local spvpBlockLabel = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spvpBlockLabel:SetPoint("TOPLEFT", 40, y3)
    spvpBlockLabel:SetText("Failed Verification Block Duration:")
    y3 = y3 - 35  -- Increased from 20

    uiElements.spvpBlockDurationSlider = CreateFrame("Slider", nil, tab3, "OptionsSliderTemplate")
    uiElements.spvpBlockDurationSlider:SetPoint("TOPLEFT", 40, y3)
    uiElements.spvpBlockDurationSlider:SetWidth(300)
    uiElements.spvpBlockDurationSlider:SetMinMaxValues(10, 600)
    uiElements.spvpBlockDurationSlider:SetValueStep(10)
    uiElements.spvpBlockDurationSlider:SetObeyStepOnDrag(true)
    uiElements.spvpBlockDurationSlider.Low:SetText("10s")
    uiElements.spvpBlockDurationSlider.High:SetText("10m")
    uiElements.spvpBlockDurationSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 10) * 10  -- Round to nearest 10
        TRP3FW_Settings.spvpBlockDuration = value
        local text
        if value >= 60 then
            text = string.format("%dm", math.floor(value / 60))
        else
            text = string.format("%ds", value)
        end
        uiElements.spvpBlockDurationSlider.Text:SetText("Block Duration: " .. text)
    end)
    table.insert(epsilonControls, uiElements.spvpBlockDurationSlider)
    y3 = y3 - 60  -- Increased from 45

    -- Salt Cache Duration slider
    local spvpSaltCacheLabel = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spvpSaltCacheLabel:SetPoint("TOPLEFT", 40, y3)
    spvpSaltCacheLabel:SetText("Salt Cache Duration:")
    y3 = y3 - 35  -- Increased from 20

    uiElements.spvpSaltCacheDurationSlider = CreateFrame("Slider", nil, tab3, "OptionsSliderTemplate")
    uiElements.spvpSaltCacheDurationSlider:SetPoint("TOPLEFT", 40, y3)
    uiElements.spvpSaltCacheDurationSlider:SetWidth(300)
    uiElements.spvpSaltCacheDurationSlider:SetMinMaxValues(300, 43200)  -- 5 min to 12 hours
    uiElements.spvpSaltCacheDurationSlider:SetValueStep(300)  -- 5-minute increments
    uiElements.spvpSaltCacheDurationSlider:SetObeyStepOnDrag(true)
    uiElements.spvpSaltCacheDurationSlider.Low:SetText("5m")
    uiElements.spvpSaltCacheDurationSlider.High:SetText("12h")
    uiElements.spvpSaltCacheDurationSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 300) * 300  -- Round to nearest 5 min
        TRP3FW_Settings.spvpSaltCacheDuration = value

        -- Update cache TTL
        local CI = TRP3FW.CacheInterface
        if CI and CI.caches and CI.caches.spvpPhaseSalt then
            CI.caches.spvpPhaseSalt.options.ttl = value
        end

        local text
        if value >= 3600 then
            text = string.format("%.1fh", value / 3600)
        else
            text = string.format("%dm", math.floor(value / 60))
        end
        uiElements.spvpSaltCacheDurationSlider.Text:SetText("Salt Cache: " .. text)
    end)
    table.insert(epsilonControls, uiElements.spvpSaltCacheDurationSlider)
    y3 = y3 - 60  -- Increased from 45

    -- Phase Owner Tools
    local spvpOwnerLabel = tab3:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    spvpOwnerLabel:SetPoint("TOPLEFT", 20, y3)
    spvpOwnerLabel:SetText("|cffffcc00Phase Owner Tools|r")
    y3 = y3 - 25

    -- Salt status display
    uiElements.spvpSaltStatus = tab3:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    uiElements.spvpSaltStatus:SetPoint("TOPLEFT", 40, y3)
    uiElements.spvpSaltStatus:SetJustifyH("LEFT")
    uiElements.spvpSaltStatus:SetWidth(500)
    uiElements.spvpSaltStatus:SetText("Loading phase status...")
    table.insert(epsilonControls, uiElements.spvpSaltStatus)
    y3 = y3 - 30

    -- Secure/Rotate button
    uiElements.spvpSecureButton = CreateFrame("Button", nil, tab3, "UIPanelButtonTemplate")
    uiElements.spvpSecureButton:SetSize(200, 24)
    uiElements.spvpSecureButton:SetPoint("TOPLEFT", 40, y3)
    uiElements.spvpSecureButton:SetText("Secure This Phase")
    uiElements.spvpSecureButton:SetScript("OnClick", function(self)
        -- Check if user is owner/officer
        if not C_Epsilon or not (C_Epsilon.IsOwner and C_Epsilon.IsOwner() or C_Epsilon.IsOfficer and C_Epsilon.IsOfficer()) then
            TRP3FW:Error("You must be a phase owner or officer to secure phases.")
            return
        end

        -- Check if salt exists (use cached check)
        local phaseID = TRP3FW:GetCurrentPhaseID()
        local existingSalt = TRP3FW:GetPhaseSalt(phaseID, false)
        if existingSalt and existingSalt ~= "" then
            -- Rotate confirmation
            StaticPopup_Show("TRP3FW_SPVP_ROTATE_CONFIRM")
        else
            -- Generate new salt
            TRP3FW:SecureCurrentPhase()
            RequestRefreshUI()
        end
    end)
    table.insert(epsilonControls, uiElements.spvpSecureButton)
    y3 = y3 - 40

    -- Overrides section
    CreateSectionHeader(tab3, "Overrides (Phase/Map → Profile)", y3)
    y3 = y3 - 35

    uiElements.profileOverrides = {}
    TRP3FW_Settings.ghostProfileOverrides = TRP3FW_Settings.ghostProfileOverrides or {}

    local overridesStartY = y3
    local rowHeight = 34
    local labelX = 40
    local conditionX = 80
    local dropdownX = conditionX + 140 + 12  -- keep consistent horizontal spacing
    for i = 1, 20 do
        TRP3FW_Settings.ghostProfileOverrides[i] = TRP3FW_Settings.ghostProfileOverrides[i] or {}
        local entry = TRP3FW_Settings.ghostProfileOverrides[i]

        local column = 1
        local row = (i - 1)
        local yRow = overridesStartY - (row * rowHeight)

        local rowLabel = tab3:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        rowLabel:SetPoint("TOPLEFT", labelX, yRow)
        rowLabel:SetText(string.format("#%02d", i))

        local conditionBox = CreateFrame("EditBox", nil, tab3, "InputBoxTemplate")
        conditionBox:SetSize(140, 20)
        conditionBox:SetAutoFocus(false)
        conditionBox:SetPoint("TOPLEFT", tab3, "TOPLEFT", conditionX, yRow - 2)
        conditionBox:SetText(entry.match or "")
        conditionBox:SetCursorPosition(0)
        conditionBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        local function saveCondition()
            entry.match = conditionBox:GetText() or ""
        end
        conditionBox:SetScript("OnEditFocusLost", saveCondition)
        conditionBox:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                saveCondition()
            end
        end)

        local overrideDropdown = CreateFrame("Frame", nil, tab3, "UIDropDownMenuTemplate")
        overrideDropdown:SetPoint("TOPLEFT", tab3, "TOPLEFT", dropdownX, yRow - 2)  -- align consistently per row
        UIDropDownMenu_SetWidth(overrideDropdown, 170)

        UIDropDownMenu_Initialize(overrideDropdown, function(self, level)
            local info = UIDropDownMenu_CreateInfo()

            info.text = "(Use global profile)"
            info.func = function()
                entry.profileID = nil
                entry.profileName = nil
                UIDropDownMenu_SetText(overrideDropdown, "(Use global profile)")
            end
            info.notCheckable = true
            UIDropDownMenu_AddButton(info)

            local profiles = TRP3FW:GetAllProfiles()
            if #profiles == 0 then
                info = UIDropDownMenu_CreateInfo()
                info.text = "(No profiles found)"
                info.notCheckable = true
                info.disabled = true
                UIDropDownMenu_AddButton(info)
            else
                for _, profile in ipairs(profiles) do
                    info = UIDropDownMenu_CreateInfo()
                    info.text = profile.name
                    if profile.isCurrent then
                        info.text = info.text .. " (current)"
                    end
                    info.func = function()
                        entry.profileID = profile.id
                        entry.profileName = profile.name
                        UIDropDownMenu_SetText(overrideDropdown, profile.name)
                    end
                    info.notCheckable = true
                    UIDropDownMenu_AddButton(info)
                end
            end
        end)

        local overrideLabel = entry.profileName or (entry.profileID and tostring(entry.profileID)) or "(Use global profile)"
        UIDropDownMenu_SetText(overrideDropdown, overrideLabel)

        table.insert(uiElements.profileOverrides, {
            edit = conditionBox,
            dropdown = overrideDropdown,
        })
    end

    -- Advance y3 to below the tallest column
    y3 = overridesStartY - (rowHeight * 20) - 40

end

function TRP3FW:InitializeUI()
    if settingsFrame then
        TRP3FW:Debug("UI already initialized", "ui")
        return
    end

    -- Ensure settings are initialized before building UI
    if TRP3FW.InitializeSettings then
        TRP3FW:InitializeSettings()
    end

    TRP3FW:Debug("Starting UI initialization...", "ui")

    -- Initialize minimap settings from SavedVariables
    local success, err = pcall(InitializeMinimapSettings)
    if not success then
        print("|cffff0000TRP3FW Error:|r Failed to initialize minimap settings: "..tostring(err))
        return
    end
    TRP3FW:Debug("Minimap settings initialized", "ui")

    TRP3FW:Debug("Creating settings frame...", "ui")

    -- Main frame
    success, err = pcall(function()
        settingsFrame = CreateFrame("Frame", "TRP3FW_SettingsFrame", UIParent, "BasicFrameTemplateWithInset")
    end)

    if not success then
        print("|cffff0000TRP3FW Error:|r Failed to create settings frame: "..tostring(err))
        print("|cffffff00TRP3FW:|r UI will not be available. Attempting to create minimap button only...")
        -- Still try to create minimap button even if UI frame fails
        local btnSuccess, btnErr = pcall(CreateMinimapButton)
        if not btnSuccess then
            print("|cffff0000TRP3FW Error:|r Failed to create minimap button: "..tostring(btnErr))
        end
        return
    end
    TRP3FW:Debug("Settings frame created successfully", "ui")
    settingsFrame:SetSize(600, 550)
    settingsFrame:SetPoint("CENTER")
    settingsFrame:SetMovable(true)
    settingsFrame:EnableMouse(true)
    settingsFrame:RegisterForDrag("LeftButton")
    settingsFrame:SetScript("OnDragStart", settingsFrame.StartMoving)
    settingsFrame:SetScript("OnDragStop", settingsFrame.StopMovingOrSizing)
    settingsFrame:Hide()

    -- Title
    settingsFrame.title = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    settingsFrame.title:SetPoint("TOP", 0, -5)
    settingsFrame.title:SetText("TRP3 Firewall Settings v"..TRP3FW.VERSION)

    -- Tab system
    local tabs = {}
    local tabContents = {}

    -- Create 5 tabs
    tabs[1] = CreateTab(settingsFrame, 1, "Status")
    tabs[2] = CreateTab(settingsFrame, 2, "Notifications")
    tabs[3] = CreateTab(settingsFrame, 3, "Alerts & Blocking")
    tabs[4] = CreateTab(settingsFrame, 4, "Filters & Addons")
    tabs[5] = CreateTab(settingsFrame, 5, "Cache & Debug")

    -- Create content frames for each tab with appropriate heights
    -- Heights calculated based on content (absolute value of final y-offset + padding for slider/elements)
    local tabHeights = {
        1000,   -- Tab 1 (Status) - includes recent activity list
        470,   -- Tab 2 (Notifications)
        1500,  -- Tab 3 (Alerts & Blocking) - expanded Safety/overrides
        280,   -- Tab 4 (Filters & Addons)
        950    -- Tab 5 (Cache & Debug)
    }

    for i = 1, 5 do
        local scrollFrame, scrollChild = CreateScrollFrame(settingsFrame, tabHeights[i])
        tabContents[i] = { scrollFrame = scrollFrame, scrollChild = scrollChild }
        scrollFrame:Hide()
    end

    -- Tab click handler
    local currentTab = 1 -- Track currently selected tab

    -- Periodic update timer for Status tab (only when visible)
    local statusUpdateTimer = nil
    local function StartStatusUpdates()
        if statusUpdateTimer then return end -- Already running
        local refreshRate = TRP3FW_Settings.statusRefreshRate or 30
        statusUpdateTimer = C_Timer.NewTicker(refreshRate, function()
            if settingsFrame:IsVisible() and currentTab == 1 then
                UpdateStatusTab()
            else
                -- Stop timer if frame hidden or different tab
                if statusUpdateTimer then
                    statusUpdateTimer:Cancel()
                    statusUpdateTimer = nil
                end
            end
        end)
    end

    local function SelectTab(tabIndex)
        currentTab = tabIndex

        for i = 1, 5 do
            if i == tabIndex then
                tabs[i].bg:SetColorTexture(0.3, 0.3, 0.3, 1)
                tabs[i].text:SetTextColor(1, 1, 1)
                tabContents[i].scrollFrame:Show()
            else
                tabs[i].bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
                tabs[i].text:SetTextColor(0.7, 0.7, 0.7)
                tabContents[i].scrollFrame:Hide()
            end
        end

        -- Update Status tab immediately when switching to it
        if tabIndex == 1 then
            UpdateStatusTab()
            StartStatusUpdates() -- Restart the periodic timer
        end
    end

    for i = 1, 5 do
        tabs[i]:SetScript("OnClick", function() SelectTab(i) end)
    end

    -- ========== TAB 1: STATUS ==========
    local tab1 = tabContents[1].scrollChild
    local y1 = -10

    CreateSectionHeader(tab1, "Environment", y1)
    y1 = y1 - 30

    -- Single line showing all detected addons with badges
    local addonsLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    addonsLabel:SetPoint("TOPLEFT", 20, y1)
    addonsLabel:SetText("RP Addons:")
    addonsLabel:SetTextColor(0.8, 0.8, 0.8)

    local addonsList = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    addonsList:SetPoint("LEFT", addonsLabel, "RIGHT", 10, 0)
    addonsList:SetJustifyH("LEFT")
    addonsList:SetWidth(460)
    uiElements.statusAddonsList = addonsList
    y1 = y1 - 22

    -- Map Scanner (inline)
    local mapScannerLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mapScannerLabel:SetPoint("TOPLEFT", 20, y1)
    mapScannerLabel:SetText("Map Scanner:")
    mapScannerLabel:SetTextColor(0.8, 0.8, 0.8)

    local mapScannerValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mapScannerValue:SetPoint("LEFT", mapScannerLabel, "RIGHT", 10, 0)
    uiElements.statusMapScanner = mapScannerValue
    y1 = y1 - 22

    -- Epsilon API (inline)
    local epsilonAPILabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    epsilonAPILabel:SetPoint("TOPLEFT", 20, y1)
    epsilonAPILabel:SetText("Epsilon API:")
    epsilonAPILabel:SetTextColor(0.8, 0.8, 0.8)

    local epsilonAPIValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    epsilonAPIValue:SetPoint("LEFT", epsilonAPILabel, "RIGHT", 10, 0)
    uiElements.statusEpsilonAPI = epsilonAPIValue
    y1 = y1 - 22

    -- Memory Usage (inline)
    local memoryLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    memoryLabel:SetPoint("TOPLEFT", 20, y1)
    memoryLabel:SetText("Memory Usage:")
    memoryLabel:SetTextColor(0.8, 0.8, 0.8)

    local memoryValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    memoryValue:SetPoint("LEFT", memoryLabel, "RIGHT", 10, 0)
    uiElements.statusMemory = memoryValue

    -- Column 2: Performance Metrics (Avg Latency, CPU Load, Throughput)
    local col2X = 200
    local perfLabelY = y1 + 66 -- Align with top of section

    -- Avg Latency
    local latencyLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    latencyLabel:SetPoint("TOPLEFT", col2X, perfLabelY)
    latencyLabel:SetText("Latency (Inst/Avg/Peak):")
    latencyLabel:SetTextColor(0.8, 0.8, 0.8)

    local latencyValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    latencyValue:SetPoint("LEFT", latencyLabel, "RIGHT", 10, 0)
    uiElements.statusLatency = latencyValue
    perfLabelY = perfLabelY - 22

    -- CPU Load
    local cpuLoadLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cpuLoadLabel:SetPoint("TOPLEFT", col2X, perfLabelY)
    cpuLoadLabel:SetText("CPU Load (Inst/Avg/Peak):")
    cpuLoadLabel:SetTextColor(0.8, 0.8, 0.8)

    local cpuLoadValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cpuLoadValue:SetPoint("LEFT", cpuLoadLabel, "RIGHT", 10, 0)
    uiElements.statusCPULoad = cpuLoadValue
    perfLabelY = perfLabelY - 22

    -- Throughput
    local throughputLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    throughputLabel:SetPoint("TOPLEFT", col2X, perfLabelY)
    throughputLabel:SetText("Throughput (Inst/Avg/Peak):")
    throughputLabel:SetTextColor(0.8, 0.8, 0.8)

    local throughputValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    throughputValue:SetPoint("LEFT", throughputLabel, "RIGHT", 10, 0)
    uiElements.statusThroughput = throughputValue
    perfLabelY = perfLabelY - 22

    -- Phase Security Indicator
    local phaseSecurityLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    phaseSecurityLabel:SetPoint("TOPLEFT", col2X, perfLabelY)
    phaseSecurityLabel:SetText("Phase Security:")
    phaseSecurityLabel:SetTextColor(0.8, 0.8, 0.8)

    local phaseSecurityValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    phaseSecurityValue:SetPoint("LEFT", phaseSecurityLabel, "RIGHT", 10, 0)
    uiElements.statusPhaseSecurity = phaseSecurityValue

    -- History Checkbox (shifted down to accommodate indicator)
    local histCheck = CreateCheckbox(tab1, "Track History", "Enable performance history tracking (avg/max per refresh interval).\n\n|cffff0000Warning:|r Tracking while closed keeps the performance monitor active. This will force GC every auto-refresh due to the memory usage stat.", "performanceHistoryEnabled")
    histCheck:SetPoint("TOPLEFT", col2X, perfLabelY - 25)
    uiElements.performanceHistoryEnabled = histCheck
    histCheck:SetScript("OnClick", function(self)
        TRP3FW_Settings.performanceHistoryEnabled = self:GetChecked()
        UpdateBackgroundTracking()
    end)

    -- Show History Button
    local showHistoryBtn = CreateFrame("Button", nil, tab1, "UIPanelButtonTemplate")
    showHistoryBtn:SetSize(100, 22)
    showHistoryBtn:SetPoint("TOPLEFT", histCheck, "TOPRIGHT", 100, 0) -- Position relative to checkbox, 100px to the right
    showHistoryBtn:SetText("Show Graphs")
    showHistoryBtn:SetScript("OnClick", function()
        if TRP3FW.ToggleHistoryWindow then
            TRP3FW:ToggleHistoryWindow()
        end
    end)

    y1 = y1 - 35

    CreateSectionHeader(tab1, "Session Statistics", y1)
    y1 = y1 - 30

    -- Create 3 stat cards in a row (520px total width: 3 cards + 2 gaps)
    local cardWidth = (520 - 20) / 3  -- ~167px per card
    local alertsCard = CreateStatCard(tab1, cardWidth, 75)
    alertsCard:SetPoint("TOPLEFT", 20, y1)
    alertsCard.title:SetText("ALERTS SHOWN")
    uiElements.statusAlertsCard = alertsCard

    local blocksCard = CreateStatCard(tab1, cardWidth, 75)
    blocksCard:SetPoint("LEFT", alertsCard, "RIGHT", 10, 0)
    blocksCard.title:SetText("BLOCKS")
    uiElements.statusBlocksCard = blocksCard

    local ghostCard = CreateStatCard(tab1, cardWidth, 75)
    ghostCard:SetPoint("LEFT", blocksCard, "RIGHT", 10, 0)
    ghostCard.title:SetText("GHOST PROFILES")
    uiElements.statusGhostCard = ghostCard

    y1 = y1 - 85

    CreateSectionHeader(tab1, "Detection Breakdown", y1)
    y1 = y1 - 30

    -- Phase Alerts
    local phaseAlertsText = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    phaseAlertsText:SetPoint("TOPLEFT", 20, y1)
    phaseAlertsText:SetText("Different Phase Detections:")
    y1 = y1 - 25

    local phaseAlertsValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    phaseAlertsValue:SetPoint("TOPLEFT", 40, y1)
    uiElements.statusPhaseAlerts = phaseAlertsValue
    y1 = y1 - 40

    -- Map Alerts
    local mapAlertsText = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    mapAlertsText:SetPoint("TOPLEFT", 20, y1)
    mapAlertsText:SetText("Different Map Detections:")
    y1 = y1 - 25

    local mapAlertsValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mapAlertsValue:SetPoint("TOPLEFT", 40, y1)
    uiElements.statusMapAlerts = mapAlertsValue
    y1 = y1 - 50

    CreateSectionHeader(tab1, "Recent Activity", y1)
    y1 = y1 - 30

    -- Header Row
    local hTime = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hTime:SetPoint("TOPLEFT", 20, y1)
    hTime:SetWidth(60)
    hTime:SetJustifyH("LEFT")
    hTime:SetText("Time")
    hTime:SetTextColor(0.6, 0.6, 0.6)

    local hPlayer = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hPlayer:SetPoint("LEFT", hTime, "RIGHT", 5, 0)
    hPlayer:SetWidth(150)
    hPlayer:SetJustifyH("LEFT")
    hPlayer:SetText("Player")
    hPlayer:SetTextColor(0.6, 0.6, 0.6)

    local hAddon = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hAddon:SetPoint("LEFT", hPlayer, "RIGHT", 5, 0)
    hAddon:SetWidth(60)
    hAddon:SetJustifyH("LEFT")
    hAddon:SetText("Addon")
    hAddon:SetTextColor(0.6, 0.6, 0.6)

    local hResult = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hResult:SetPoint("LEFT", hAddon, "RIGHT", 5, 0)
    hResult:SetWidth(100)
    hResult:SetJustifyH("LEFT")
    hResult:SetText("Result")
    hResult:SetTextColor(0.6, 0.6, 0.6)

    y1 = y1 - 20

    uiElements.statusRecentEvents = {}
    for i = 1, 8 do
        local row = CreateFrame("Frame", nil, tab1)
        row:SetSize(540, 18)
        row:SetPoint("TOPLEFT", 20, y1)

        -- Alternating background
        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.05)
        end

        local tTime = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tTime:SetPoint("LEFT", 0, 0)
        tTime:SetWidth(60)
        tTime:SetJustifyH("LEFT")
        row.Time = tTime

        local tPlayer = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tPlayer:SetPoint("LEFT", tTime, "RIGHT", 5, 0)
        tPlayer:SetWidth(150)
        tPlayer:SetJustifyH("LEFT")
        row.Player = tPlayer

        local tAddon = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tAddon:SetPoint("LEFT", tPlayer, "RIGHT", 5, 0)
        tAddon:SetWidth(60)
        tAddon:SetJustifyH("LEFT")
        row.Addon = tAddon

        local tResult = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tResult:SetPoint("LEFT", tAddon, "RIGHT", 5, 0)
        tResult:SetWidth(200)
        tResult:SetJustifyH("LEFT")
        row.Result = tResult

        uiElements.statusRecentEvents[i] = row
        y1 = y1 - 18
    end

    y1 = y1 - 10

    CreateSectionHeader(tab1, "Requests by Addon", y1)
    y1 = y1 - 30

    -- Horizontal stacked bar showing relative addon usage (520px to match separator)
    local requestsBar = CreateHorizontalStackedBar(tab1, 520, 30)
    requestsBar:SetPoint("TOPLEFT", 20, y1)
    uiElements.statusRequestsBar = requestsBar
    y1 = y1 - 35

    -- Legend for the bar chart
    local legendFrame = CreateFrame("Frame", nil, tab1)
    legendFrame:SetPoint("TOPLEFT", 20, y1)
    legendFrame:SetSize(520, 20)

    local legendText = legendFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legendText:SetPoint("LEFT", 0, 0)
    legendText:SetTextColor(0.7, 0.7, 0.7)
    legendText:SetText("|cff4D99FFTRP3|r  |cffCC4DCCMRP|r  |cffFF9933XRP|r  |cff33CC66MSP|r")

    y1 = y1 - 30

    CreateSectionHeader(tab1, "Cache Performance", y1)
    y1 = y1 - 30

    -- Cache Performance bars with aligned labels (520px to match separator)
    local perfLabelWidth = 120
    local perfBarX = 20 + perfLabelWidth + 10
    local perfBarWidth = 520 - perfLabelWidth - 10  -- 390px bar width

    -- Phase Cache Performance Bar
    local phaseCachePerfLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    phaseCachePerfLabel:SetPoint("TOPLEFT", 20, y1)
    phaseCachePerfLabel:SetWidth(perfLabelWidth)
    phaseCachePerfLabel:SetJustifyH("LEFT")
    phaseCachePerfLabel:SetText("Phase Cache:")
    phaseCachePerfLabel:SetTextColor(0.8, 0.8, 0.8)

    local phaseCachePerfBar = CreateProgressBar(tab1, perfBarWidth, 18)
    phaseCachePerfBar:SetPoint("TOPLEFT", perfBarX, y1)
    uiElements.statusPhaseCachePerfBar = phaseCachePerfBar
    y1 = y1 - 25

    -- Map Cache Performance Bar
    local mapCachePerfLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mapCachePerfLabel:SetPoint("TOPLEFT", 20, y1)
    mapCachePerfLabel:SetWidth(perfLabelWidth)
    mapCachePerfLabel:SetJustifyH("LEFT")
    mapCachePerfLabel:SetText("Map Scan:")
    mapCachePerfLabel:SetTextColor(0.8, 0.8, 0.8)

    local mapCachePerfBar = CreateProgressBar(tab1, perfBarWidth, 18)
    mapCachePerfBar:SetPoint("TOPLEFT", perfBarX, y1)
    uiElements.statusMapCachePerfBar = mapCachePerfBar
    y1 = y1 - 25

    -- WHO Cache Performance Bar
    local whoCachePerfLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    whoCachePerfLabel:SetPoint("TOPLEFT", 20, y1)
    whoCachePerfLabel:SetWidth(perfLabelWidth)
    whoCachePerfLabel:SetJustifyH("LEFT")
    whoCachePerfLabel:SetText("WHO Query:")
    whoCachePerfLabel:SetTextColor(0.8, 0.8, 0.8)

    local whoCachePerfBar = CreateProgressBar(tab1, perfBarWidth, 18)
    whoCachePerfBar:SetPoint("TOPLEFT", perfBarX, y1)
    uiElements.statusWhoCachePerfBar = whoCachePerfBar
    y1 = y1 - 25

    -- Allowed Senders Cache Performance Bar
    local allowedSendersCachePerfLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    allowedSendersCachePerfLabel:SetPoint("TOPLEFT", 20, y1)
    allowedSendersCachePerfLabel:SetWidth(perfLabelWidth)
    allowedSendersCachePerfLabel:SetJustifyH("LEFT")
    allowedSendersCachePerfLabel:SetText("Allowed Senders:")
    allowedSendersCachePerfLabel:SetTextColor(0.8, 0.8, 0.8)

    local allowedSendersCachePerfBar = CreateProgressBar(tab1, perfBarWidth, 18)
    allowedSendersCachePerfBar:SetPoint("TOPLEFT", perfBarX, y1)
    uiElements.statusAllowedSendersCachePerfBar = allowedSendersCachePerfBar
    y1 = y1 - 25

    -- Interaction Cache Performance Bar
    local interactionCachePerfLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    interactionCachePerfLabel:SetPoint("TOPLEFT", 20, y1)
    interactionCachePerfLabel:SetWidth(perfLabelWidth)
    interactionCachePerfLabel:SetJustifyH("LEFT")
    interactionCachePerfLabel:SetText("Interaction:")
    interactionCachePerfLabel:SetTextColor(0.8, 0.8, 0.8)

    local interactionCachePerfBar = CreateProgressBar(tab1, perfBarWidth, 18)
    interactionCachePerfBar:SetPoint("TOPLEFT", perfBarX, y1)
    uiElements.statusInteractionCachePerfBar = interactionCachePerfBar
    y1 = y1 - 25

    -- Broadcast Cache Performance Bar
    local broadcastCachePerfLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    broadcastCachePerfLabel:SetPoint("TOPLEFT", 20, y1)
    broadcastCachePerfLabel:SetWidth(perfLabelWidth)
    broadcastCachePerfLabel:SetJustifyH("LEFT")
    broadcastCachePerfLabel:SetText("Broadcasts:")
    broadcastCachePerfLabel:SetTextColor(0.8, 0.8, 0.8)

    local broadcastCachePerfBar = CreateProgressBar(tab1, perfBarWidth, 18)
    broadcastCachePerfBar:SetPoint("TOPLEFT", perfBarX, y1)
    uiElements.statusBroadcastCachePerfBar = broadcastCachePerfBar
    y1 = y1 - 25

    -- SPVP Cache Performance Bar
    local spvpCachePerfLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spvpCachePerfLabel:SetPoint("TOPLEFT", 20, y1)
    spvpCachePerfLabel:SetWidth(perfLabelWidth)
    spvpCachePerfLabel:SetJustifyH("LEFT")
    spvpCachePerfLabel:SetText("SPVP Salt:")
    spvpCachePerfLabel:SetTextColor(0.8, 0.8, 0.8)

    local spvpCachePerfBar = CreateProgressBar(tab1, perfBarWidth, 18)
    spvpCachePerfBar:SetPoint("TOPLEFT", perfBarX, y1)
    uiElements.statusSpvpCachePerfBar = spvpCachePerfBar
    y1 = y1 - 25

    -- SPVP Verified Cache Performance Bar
    local spvpVerifiedCachePerfLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spvpVerifiedCachePerfLabel:SetPoint("TOPLEFT", 20, y1)
    spvpVerifiedCachePerfLabel:SetWidth(perfLabelWidth)
    spvpVerifiedCachePerfLabel:SetJustifyH("LEFT")
    spvpVerifiedCachePerfLabel:SetText("SPVP Verified:")
    spvpVerifiedCachePerfLabel:SetTextColor(0.8, 0.8, 0.8)

    local spvpVerifiedCachePerfBar = CreateProgressBar(tab1, perfBarWidth, 18)
    spvpVerifiedCachePerfBar:SetPoint("TOPLEFT", perfBarX, y1)
    uiElements.statusSpvpVerifiedCachePerfBar = spvpVerifiedCachePerfBar
    y1 = y1 - 35

    CreateSectionHeader(tab1, "Cache Status", y1)
    y1 = y1 - 30

    -- 2-column grid layout for cache counts with aligned labels
    local statusLabelWidth = 140
    local col1LabelX = 20
    local col1ValueX = col1LabelX + statusLabelWidth
    local col2LabelX = 310
    local col2ValueX = col2LabelX + statusLabelWidth

    -- Row 1: Phase Cache | Broadcast Cache
    local phaseCacheLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    phaseCacheLabel:SetPoint("TOPLEFT", col1LabelX, y1)
    phaseCacheLabel:SetWidth(statusLabelWidth)
    phaseCacheLabel:SetJustifyH("LEFT")
    phaseCacheLabel:SetText("Phase Cache:")
    phaseCacheLabel:SetTextColor(0.8, 0.8, 0.8)

    local phaseCacheValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    phaseCacheValue:SetPoint("TOPLEFT", col1ValueX, y1)
    phaseCacheValue:SetJustifyH("LEFT")
    uiElements.statusPhaseCache = phaseCacheValue

    local broadcastCacheLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    broadcastCacheLabel:SetPoint("TOPLEFT", col2LabelX, y1)
    broadcastCacheLabel:SetWidth(statusLabelWidth)
    broadcastCacheLabel:SetJustifyH("LEFT")
    broadcastCacheLabel:SetText("Broadcast Cache:")
    broadcastCacheLabel:SetTextColor(0.8, 0.8, 0.8)

    local broadcastCacheValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    broadcastCacheValue:SetPoint("TOPLEFT", col2ValueX, y1)
    broadcastCacheValue:SetJustifyH("LEFT")
    uiElements.statusBroadcastCache = broadcastCacheValue
    y1 = y1 - 22

    -- Row 2: Map Scan Cache | Send Cache
    local scanCacheLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scanCacheLabel:SetPoint("TOPLEFT", col1LabelX, y1)
    scanCacheLabel:SetWidth(statusLabelWidth)
    scanCacheLabel:SetJustifyH("LEFT")
    scanCacheLabel:SetText("Map Scan Cache:")
    scanCacheLabel:SetTextColor(0.8, 0.8, 0.8)

    local scanCacheValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scanCacheValue:SetPoint("TOPLEFT", col1ValueX, y1)
    scanCacheValue:SetJustifyH("LEFT")
    uiElements.statusScanCache = scanCacheValue

    local sendCacheLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sendCacheLabel:SetPoint("TOPLEFT", col2LabelX, y1)
    sendCacheLabel:SetWidth(statusLabelWidth)
    sendCacheLabel:SetJustifyH("LEFT")
    sendCacheLabel:SetText("Send Cache:")
    sendCacheLabel:SetTextColor(0.8, 0.8, 0.8)

    local sendCacheValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sendCacheValue:SetPoint("TOPLEFT", col2ValueX, y1)
    sendCacheValue:SetJustifyH("LEFT")
    uiElements.statusSendCache = sendCacheValue
    y1 = y1 - 22

    -- Row 3: WHO Name Cache | WHO Zone Cache
    local whoNameCacheLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    whoNameCacheLabel:SetPoint("TOPLEFT", col1LabelX, y1)
    whoNameCacheLabel:SetWidth(statusLabelWidth)
    whoNameCacheLabel:SetJustifyH("LEFT")
    whoNameCacheLabel:SetText("WHO Name Cache:")
    whoNameCacheLabel:SetTextColor(0.8, 0.8, 0.8)

    local whoNameCacheValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    whoNameCacheValue:SetPoint("TOPLEFT", col1ValueX, y1)
    whoNameCacheValue:SetJustifyH("LEFT")
    uiElements.statusWhoNameCache = whoNameCacheValue

    local whoZoneCacheLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    whoZoneCacheLabel:SetPoint("TOPLEFT", col2LabelX, y1)
    whoZoneCacheLabel:SetWidth(statusLabelWidth)
    whoZoneCacheLabel:SetJustifyH("LEFT")
    whoZoneCacheLabel:SetText("WHO Zone Cache:")
    whoZoneCacheLabel:SetTextColor(0.8, 0.8, 0.8)

    local whoZoneCacheValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    whoZoneCacheValue:SetPoint("TOPLEFT", col2ValueX, y1)
    whoZoneCacheValue:SetJustifyH("LEFT")
    uiElements.statusWhoZoneCache = whoZoneCacheValue
    y1 = y1 - 22

    -- Row 4: Interaction Cache
    local interactionCacheLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    interactionCacheLabel:SetPoint("TOPLEFT", col1LabelX, y1)
    interactionCacheLabel:SetWidth(statusLabelWidth)
    interactionCacheLabel:SetJustifyH("LEFT")
    interactionCacheLabel:SetText("Interaction Cache:")
    interactionCacheLabel:SetTextColor(0.8, 0.8, 0.8)

    local interactionCacheValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    interactionCacheValue:SetPoint("TOPLEFT", col1ValueX, y1)
    interactionCacheValue:SetJustifyH("LEFT")
    uiElements.statusInteractionCache = interactionCacheValue

    -- Row 4 (col 2): Suppression Timers
    local suppressionCacheLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    suppressionCacheLabel:SetPoint("TOPLEFT", col2LabelX, y1)
    suppressionCacheLabel:SetWidth(statusLabelWidth)
    suppressionCacheLabel:SetJustifyH("LEFT")
    suppressionCacheLabel:SetText("Suppression Timers:")
    suppressionCacheLabel:SetTextColor(0.8, 0.8, 0.8)

    local suppressionCacheValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    suppressionCacheValue:SetPoint("TOPLEFT", col2ValueX, y1)
    suppressionCacheValue:SetJustifyH("LEFT")
    uiElements.statusSuppressionCache = suppressionCacheValue
    y1 = y1 - 22

    -- Row 5: SPVP Salt Cache | SPVP Verified Cache
    local spvpCacheLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spvpCacheLabel:SetPoint("TOPLEFT", col1LabelX, y1)
    spvpCacheLabel:SetWidth(statusLabelWidth)
    spvpCacheLabel:SetJustifyH("LEFT")
    spvpCacheLabel:SetText("SPVP Salt Cache:")
    spvpCacheLabel:SetTextColor(0.8, 0.8, 0.8)

    local spvpCacheValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    spvpCacheValue:SetPoint("TOPLEFT", col1ValueX, y1)
    spvpCacheValue:SetJustifyH("LEFT")
    uiElements.statusSpvpCache = spvpCacheValue

    local spvpVerifiedCacheLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spvpVerifiedCacheLabel:SetPoint("TOPLEFT", col2LabelX, y1)
    spvpVerifiedCacheLabel:SetWidth(statusLabelWidth)
    spvpVerifiedCacheLabel:SetJustifyH("LEFT")
    spvpVerifiedCacheLabel:SetText("SPVP Verified Cache:")
    spvpVerifiedCacheLabel:SetTextColor(0.8, 0.8, 0.8)

    local spvpVerifiedCacheValue = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    spvpVerifiedCacheValue:SetPoint("TOPLEFT", col2ValueX, y1)
    spvpVerifiedCacheValue:SetJustifyH("LEFT")
    uiElements.statusSpvpVerifiedCache = spvpVerifiedCacheValue
    y1 = y1 - 35

    -- ============================================
    -- RunPrivileged API Statistics
    -- ============================================
    CreateSectionHeader(tab1, "RunPrivileged API Statistics", y1)
    y1 = y1 - 30

    local privStatLabelWidth = 140
    local privStatValueX = 20 + privStatLabelWidth

    local privTotalLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    privTotalLabel:SetPoint("TOPLEFT", 20, y1)
    privTotalLabel:SetWidth(privStatLabelWidth)
    privTotalLabel:SetJustifyH("LEFT")
    privTotalLabel:SetText("Total Calls:")
    uiElements.statusPrivilegedTotal = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    uiElements.statusPrivilegedTotal:SetPoint("LEFT", privStatValueX, 0)
    uiElements.statusPrivilegedTotal:SetPoint("TOP", privTotalLabel, "TOP", 0, 0) -- Align vertically with label
    y1 = y1 - 20

    local privSuccessLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    privSuccessLabel:SetPoint("TOPLEFT", 20, y1)
    privSuccessLabel:SetWidth(privStatLabelWidth)
    privSuccessLabel:SetJustifyH("LEFT")
    privSuccessLabel:SetText("Successful:")
    uiElements.statusPrivilegedSuccess = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    uiElements.statusPrivilegedSuccess:SetPoint("LEFT", privStatValueX, 0)
    uiElements.statusPrivilegedSuccess:SetPoint("TOP", privSuccessLabel, "TOP", 0, 0)
    y1 = y1 - 20

    local privBlockedLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    privBlockedLabel:SetPoint("TOPLEFT", 20, y1)
    privBlockedLabel:SetWidth(privStatLabelWidth)
    privBlockedLabel:SetJustifyH("LEFT")
    privBlockedLabel:SetText("Rate Limited:")
    uiElements.statusPrivilegedBlocked = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    uiElements.statusPrivilegedBlocked:SetPoint("LEFT", privStatValueX, 0)
    uiElements.statusPrivilegedBlocked:SetPoint("TOP", privBlockedLabel, "TOP", 0, 0)
    y1 = y1 - 20

    local privErrorsLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    privErrorsLabel:SetPoint("TOPLEFT", 20, y1)
    privErrorsLabel:SetWidth(privStatLabelWidth)
    privErrorsLabel:SetJustifyH("LEFT")
    privErrorsLabel:SetText("Errors:")
    uiElements.statusPrivilegedErrors = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    uiElements.statusPrivilegedErrors:SetPoint("LEFT", privStatValueX, 0)
    uiElements.statusPrivilegedErrors:SetPoint("TOP", privErrorsLabel, "TOP", 0, 0)
    y1 = y1 - 20

    local privDeferredLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    privDeferredLabel:SetPoint("TOPLEFT", 20, y1)
    privDeferredLabel:SetWidth(privStatLabelWidth)
    privDeferredLabel:SetJustifyH("LEFT")
    privDeferredLabel:SetText("Deferred (LOW):")
    uiElements.statusPrivilegedDeferred = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    uiElements.statusPrivilegedDeferred:SetPoint("LEFT", privStatValueX, 0)
    uiElements.statusPrivilegedDeferred:SetPoint("TOP", privDeferredLabel, "TOP", 0, 0)
    y1 = y1 - 20

    local privRefundedLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    privRefundedLabel:SetPoint("TOPLEFT", 20, y1)
    privRefundedLabel:SetWidth(privStatLabelWidth)
    privRefundedLabel:SetJustifyH("LEFT")
    privRefundedLabel:SetText("Tokens Refunded:")
    uiElements.statusPrivilegedRefunded = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    uiElements.statusPrivilegedRefunded:SetPoint("LEFT", privStatValueX, 0)
    uiElements.statusPrivilegedRefunded:SetPoint("TOP", privRefundedLabel, "TOP", 0, 0)
    y1 = y1 - 20

    local privBucketLabel = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    privBucketLabel:SetPoint("TOPLEFT", 20, y1)
    privBucketLabel:SetWidth(privStatLabelWidth)
    privBucketLabel:SetJustifyH("LEFT")
    privBucketLabel:SetText("Token Bucket:")
    uiElements.statusPrivilegedBucket = tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    uiElements.statusPrivilegedBucket:SetPoint("LEFT", privStatValueX, 0)
    uiElements.statusPrivilegedBucket:SetPoint("TOP", privBucketLabel, "TOP", 0, 0)
    y1 = y1 - 35
    
    CreateSectionHeader(tab1, "Status Tab Settings", y1)
    y1 = y1 - 30

    -- Refresh Rate Slider
    local refreshRateText = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    refreshRateText:SetPoint("TOPLEFT", 20, y1)
    refreshRateText:SetText("Auto-Refresh Rate:")
    y1 = y1 - 30

    local refreshRateSlider = CreateFrame("Slider", "TRP3FW_StatusRefreshSlider", tab1, "OptionsSliderTemplate")
    local sliderWidth = 360
    refreshRateSlider:SetPoint("TOPLEFT", 20, y1)
    refreshRateSlider:SetWidth(sliderWidth)
    refreshRateSlider:SetMinMaxValues(2, 120)
    refreshRateSlider:SetValueStep(1)
    refreshRateSlider:SetObeyStepOnDrag(true)
    refreshRateSlider:SetValue(TRP3FW_Settings.statusRefreshRate or 30)

    -- Slider labels
    local refreshDefault = TRP3FW_Settings.statusRefreshRate or 30
    getglobal(refreshRateSlider:GetName().."Low"):SetText("2s")
    getglobal(refreshRateSlider:GetName().."High"):SetText("120s")
    getglobal(refreshRateSlider:GetName().."Text"):SetText("Refresh every " .. refreshDefault .. " seconds")

    refreshRateSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        TRP3FW_Settings.statusRefreshRate = value
        getglobal(self:GetName().."Text"):SetText("Refresh every " .. value .. " seconds")
    end)

    refreshRateSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Auto-Refresh Rate", 1, 1, 1)
        GameTooltip:AddLine("Controls how often this status page updates.\n\n|cffff0000Warning:|r Lower values (e.g. 2s) increase CPU usage because calculating memory usage forces a garbage collection cycle.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    refreshRateSlider:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Ensure thumb is visible at load
    C_Timer.After(0, function()
        refreshRateSlider:SetValue(TRP3FW_Settings.statusRefreshRate or 30)
    end)

    -- Only restart timer when slider is released (not during drag)
    refreshRateSlider:SetScript("OnMouseUp", function(self)
        -- Restart timer with new interval if on Status tab
        if statusUpdateTimer and currentTab == 1 and settingsFrame:IsVisible() then
            statusUpdateTimer:Cancel()
            statusUpdateTimer = nil
            StartStatusUpdates()
        end
        -- Update background ticker rate
        UpdateBackgroundTracking()
    end)

    -- Manual refresh button
    local refreshNow = CreateFrame("Button", nil, tab1, "UIPanelButtonTemplate")
    refreshNow:SetSize(90, 22)
    refreshNow:SetPoint("LEFT", refreshRateSlider, "RIGHT", 12, 0)
    refreshNow:SetText("Refresh now")
    refreshNow:SetScript("OnClick", function()
        -- Invalidate current phase salt to force API re-check (fixes stale "Secured" status)
        local phaseID = TRP3FW:GetCurrentPhaseID()
        if phaseID and TRP3FW.InvalidatePhaseSaltCache then
            TRP3FW:InvalidatePhaseSaltCache(phaseID)
        end
        UpdateStatusTab()
    end)

    uiElements.statusRefreshRate = refreshRateSlider

    -- ========== TAB 2: NOTIFICATIONS ==========
    local tab2 = tabContents[2].scrollChild
    local y2 = -10

    CreateSectionHeader(tab2, "Notification Settings", y2)
    y2 = y2 - 40

    uiElements.notifyEnabled = CreateCheckbox(tab2, "Enable Notifications", "Master toggle for all notifications", "notifyEnabled")
    uiElements.notifyEnabled:SetPoint("TOPLEFT", 20, y2)
    uiElements.notifyEnabled:SetScript("OnClick", function(self)
        TRP3FW_Settings.notifyEnabled = self:GetChecked()
    end)
    y2 = y2 - 40

    -- Granular notification type controls
    uiElements.notifyOnAllow = CreateCheckbox(tab2, "Notify on Allow", "Show notifications when profiles are sent normally (allowed)", "notifyOnAllow")
    uiElements.notifyOnAllow:SetPoint("TOPLEFT", 20, y2)
    uiElements.notifyOnAllow:SetScript("OnClick", function(self)
        TRP3FW_Settings.notifyOnAllow = self:GetChecked()
    end)
    y2 = y2 - 30

    uiElements.notifyOnStartPhaseBlock = CreateCheckbox(tab2, "Notify on Start Phase Block", "Show notifications when blocking in start phase (169)", "notifyOnStartPhaseBlock")
    uiElements.notifyOnStartPhaseBlock:SetPoint("TOPLEFT", 20, y2)
    uiElements.notifyOnStartPhaseBlock:SetScript("OnClick", function(self)
        TRP3FW_Settings.notifyOnStartPhaseBlock = self:GetChecked()
    end)
    y2 = y2 - 30

    y2 = y2 - 10
    local notifyHelpText = tab2:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    notifyHelpText:SetPoint("TOPLEFT", 20, y2)
    notifyHelpText:SetText("|cffaaaaaa(Broadcast/Whisper toggles only affect 'Allow' notifications)|r")
    y2 = y2 - 25

    uiElements.notifyBroadcast = CreateCheckbox(tab2, "Notify on Broadcast", "Show notifications for map scan broadcasts (only affects Allow notifications)", "notifyOnBroadcast")
    uiElements.notifyBroadcast:SetPoint("TOPLEFT", 20, y2)
    uiElements.notifyBroadcast:SetScript("OnClick", function(self)
        TRP3FW_Settings.notifyOnBroadcast = self:GetChecked()
    end)
    y2 = y2 - 30

    uiElements.notifyWhisper = CreateCheckbox(tab2, "Notify on Whisper", "Show notifications for direct profile requests (only affects Allow notifications)", "notifyOnWhisper")
    uiElements.notifyWhisper:SetPoint("TOPLEFT", 20, y2)
    uiElements.notifyWhisper:SetScript("OnClick", function(self)
        TRP3FW_Settings.notifyOnWhisper = self:GetChecked()
    end)
    y2 = y2 - 30

    -- Scan Reply Group
    local scanGroupHeight = 85
    local scanGroup = CreateFrame("Frame", nil, tab2, BackdropTemplateMixin and "BackdropTemplate")
    scanGroup:SetPoint("TOPLEFT", 20, y2)
    scanGroup:SetSize(540, scanGroupHeight)
    scanGroup:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    scanGroup:SetBackdropColor(0, 0, 0, 0.2)
    scanGroup:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)

    local scanGroupTitle = scanGroup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scanGroupTitle:SetPoint("TOPLEFT", 10, -8)
    scanGroupTitle:SetText("Scan Reply Notifications")
    scanGroupTitle:SetTextColor(0.7, 0.7, 0.7)

    -- Position elements inside the group area
    local groupY = y2 - 25

    uiElements.notifyOnScanResponse = CreateCheckbox(tab2, "Show Scan Reply Notifications", "Controls chat/on-screen notifications for scan replies (TRP3 or RPMapScan). Protections are configured separately.", "notifyOnScanResponse")
    uiElements.notifyOnScanResponse:SetPoint("TOPLEFT", 30, groupY)
    uiElements.notifyOnScanResponse:SetScript("OnClick", function(self)
        TRP3FW_Settings.notifyOnScanResponse = self:GetChecked()
        local enabled = self:GetChecked()
        
        if enabled then
            uiElements.notifyOnScanAllow:Enable()
            uiElements.notifyOnScanAllow:SetAlpha(1.0)
            uiElements.notifyOnScanAllow:SetChecked(TRP3FW_Settings.notifyOnScanAllow)
        else
            uiElements.notifyOnScanAllow:Disable()
            uiElements.notifyOnScanAllow:SetAlpha(0.5)
            uiElements.notifyOnScanAllow:SetChecked(false) -- Visually uncheck when disabled
        end
        
        RequestRefreshUI()
    end)
    groupY = groupY - 30

    uiElements.notifyOnScanAllow = CreateCheckbox(tab2, "Notify on Scan Allow", "Show notifications when scan replies are allowed/sent (alerts/blocks still follow their modes).", "notifyOnScanAllow")
    uiElements.notifyOnScanAllow:SetPoint("TOPLEFT", 50, groupY)
    uiElements.notifyOnScanAllow:SetScript("OnClick", function(self)
        TRP3FW_Settings.notifyOnScanAllow = self:GetChecked()
    end)
    
    y2 = y2 - scanGroupHeight - 10
    -- Current mode summary
    local summaryLabel = tab2:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    summaryLabel:SetPoint("TOPLEFT", 20, y2)
    summaryLabel:SetText("Current Modes:")
    y2 = y2 - 24

    uiElements.notificationModeSummary = tab2:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    uiElements.notificationModeSummary:SetPoint("TOPLEFT", 30, y2)
    uiElements.notificationModeSummary:SetWidth(520)
    uiElements.notificationModeSummary:SetJustifyH("LEFT")
    y2 = y2 - 24
    y2 = y2 - 20
    y2 = y2 - 10  -- Extra spacing before new section
    CreateSectionHeader(tab2, "Display Options", y2)
    y2 = y2 - 40

    uiElements.showInChat = CreateCheckbox(tab2, "Show in Chat", "Display notifications in chat window", "showInChat")
    uiElements.showInChat:SetPoint("TOPLEFT", 20, y2)
    uiElements.showInChat:SetScript("OnClick", function(self)
        TRP3FW_Settings.showInChat = self:GetChecked()
    end)
    y2 = y2 - 30

    uiElements.showGhostNotifications = CreateCheckbox(tab2, "Show Ghost Notifications", "Display chat/on-screen messages when ghost profiles are sent", "showGhostNotifications")
    uiElements.showGhostNotifications:SetPoint("TOPLEFT", 40, y2)
    uiElements.showGhostNotifications:SetScript("OnClick", function(self)
        TRP3FW_Settings.showGhostNotifications = self:GetChecked()
    end)
    y2 = y2 - 30

    uiElements.showOnScreen = CreateCheckbox(tab2, "Show On-Screen", "Display on-screen alert frames", "showOnScreen")
    uiElements.showOnScreen:SetPoint("TOPLEFT", 20, y2)
    uiElements.showOnScreen:SetScript("OnClick", function(self)
        TRP3FW_Settings.showOnScreen = self:GetChecked()
    end)
    y2 = y2 - 30

    uiElements.playSound = CreateCheckbox(tab2, "Play Sound", "Play notification sound", "playSound")
    uiElements.playSound:SetPoint("TOPLEFT", 20, y2)
    uiElements.playSound:SetScript("OnClick", function(self)
        TRP3FW_Settings.playSound = self:GetChecked()
    end)
    y2 = y2 - 30

    uiElements.showAddonSource = CreateCheckbox(tab2, "Show Addon Source", "Display which addon sent the request (TRP3, MRP, XRP)", "showAddonSource")
    uiElements.showAddonSource:SetPoint("TOPLEFT", 20, y2)
    uiElements.showAddonSource:SetScript("OnClick", function(self)
        TRP3FW_Settings.showAddonSource = self:GetChecked()
    end)
    y2 = y2 - 30

    uiElements.showCacheInfo = CreateCheckbox(tab2, "Show Cache Info", "Append cache hit/miss info to allow notifications", "showCacheInfo")
    uiElements.showCacheInfo:SetPoint("TOPLEFT", 20, y2)
    uiElements.showCacheInfo:SetScript("OnClick", function(self)
        TRP3FW_Settings.showCacheInfo = self:GetChecked()
    end)
    y2 = y2 - 30

    uiElements.showCheckResults = CreateCheckbox(tab2, "Show Check Results", "Append phase/map pass/fail and method (WHO, map scan, cache, skipped) to allow notifications", "showCheckResults")
    uiElements.showCheckResults:SetPoint("TOPLEFT", 20, y2)
    uiElements.showCheckResults:SetScript("OnClick", function(self)
        TRP3FW_Settings.showCheckResults = self:GetChecked()
    end)
    y2 = y2 - 50

    y2 = y2 - 10  -- Extra spacing before new section
    CreateSectionHeader(tab2, "Suppression", y2)
    y2 = y2 - 50

    uiElements.suppressionTime = CreateEditBox(tab2, "Suppression Time (seconds)", "Time to suppress repeated notifications from the same player.", 80, "suppressionTime")
    uiElements.suppressionTime:SetPoint("TOPLEFT", 20, y2)

    local function saveSuppressionTime(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 then
            TRP3FW_Settings.suppressionTime = value
            TRP3FW:Info("Profile suppression time set to "..value.." seconds")
        else
            TRP3FW:Warn("Invalid value - must be a positive number")
            self:SetText(TRP3FW_Settings.suppressionTime)
        end
    end

    local suppressionTimeEnterPressed = false
    uiElements.suppressionTime:SetScript("OnEnterPressed", function(self)
        suppressionTimeEnterPressed = true
        saveSuppressionTime(self)
        self:ClearFocus()
        C_Timer.After(0, function() suppressionTimeEnterPressed = false end)
    end)
    uiElements.suppressionTime:SetScript("OnEditFocusLost", function(self)
        if not suppressionTimeEnterPressed then
            saveSuppressionTime(self)
        end
    end)

    uiElements.refreshSuppression = CreateCheckbox(tab2, "Refresh Suppression", "Extend suppression duration when new notifications are received (Sliding Window).\n\n|cff00ff00Checked:|r Spam keeps suppression active indefinitely.\n|cffff0000Unchecked:|r Suppression expires after fixed time from first notification.", "refreshSuppression")
    uiElements.refreshSuppression:SetPoint("LEFT", uiElements.suppressionTime, "RIGHT", 120, 0)
    uiElements.refreshSuppression:SetScript("OnClick", function(self)
        TRP3FW_Settings.refreshSuppression = self:GetChecked()
    end)

    -- ========== TAB 3: ALERTS & BLOCKING ==========
    -- ========== TAB 3: ALERTS & BLOCKING ==========
    CreateAlertsTab(tabContents[3].scrollChild)

    -- ========== TAB 4: FILTERS & ADDONS ==========
    local tab4 = tabContents[4].scrollChild
    local y4 = -10

    -- Complexity Level Dropdown
    local complexityLabel = tab4:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    complexityLabel:SetPoint("TOPLEFT", 20, y4)
    complexityLabel:SetText("Settings Complexity Level")
    
    local complexityDropdown = CreateFrame("Frame", "TRP3FW_ComplexityDropdown", tab4, "UIDropDownMenuTemplate")
    complexityDropdown:SetPoint("TOPLEFT", 20, y4 - 25)
    UIDropDownMenu_SetWidth(complexityDropdown, 200)
    
    UIDropDownMenu_Initialize(complexityDropdown, function(self, level)
        for i = 1, 4 do
            local info = UIDropDownMenu_CreateInfo()
            info.text = COMPLEXITY_NAMES[i]
            info.value = i
            info.func = function()
                TRP3FW_Settings.uiComplexityLevel = i
                UIDropDownMenu_SetText(complexityDropdown, COMPLEXITY_NAMES[i])
                TRP3FW:EnforceComplexityDefaults(i)
                RequestRefreshUI()
            end
            info.checked = (TRP3FW_Settings.uiComplexityLevel == i)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    
    local currentLevel = TRP3FW_Settings.uiComplexityLevel or 2
    UIDropDownMenu_SetText(complexityDropdown, COMPLEXITY_NAMES[currentLevel] or "Intermediate")
    
    y4 = y4 - 70

    CreateSectionHeader(tab4, "Filter Settings", y4)
    y4 = y4 - 40

    uiElements.filterGradients = CreateCheckbox(tab4, "Strip Color Gradients", "Remove color gradients from incoming profiles (requires /reload)", "filterGradients")
    uiElements.filterGradients:SetPoint("TOPLEFT", 20, y4)
    uiElements.filterGradients:SetScript("OnClick", function(self)
        TRP3FW_Settings.filterGradients = self:GetChecked()
        if self:GetChecked() then
            TRP3FW:Info("Gradient filter enabled - please /reload for changes to take effect")
        else
            TRP3FW:Info("Gradient filter disabled - please /reload for changes to take effect")
        end
    end)
    y4 = y4 - 40

    uiElements.filterMinimumFontSize = CreateCheckbox(tab4, "Minimum Font Size", "Inject minimum font size into incoming profiles for better readability", "filterMinimumFontSize")
    uiElements.filterMinimumFontSize:SetPoint("TOPLEFT", 20, y4)
    uiElements.filterMinimumFontSize:SetScript("OnClick", function(self)
        TRP3FW_Settings.filterMinimumFontSize = self:GetChecked()
        -- Enable/disable the dropdown based on checkbox state
        if uiElements.minimumFontSizeDropdown then
            if self:GetChecked() then
                UIDropDownMenu_EnableDropDown(uiElements.minimumFontSizeDropdown)
                uiElements.minimumFontSizeDropdown:SetAlpha(1.0)
            else
                UIDropDownMenu_DisableDropDown(uiElements.minimumFontSizeDropdown)
                uiElements.minimumFontSizeDropdown:SetAlpha(0.5)
            end
        end
        if self:GetChecked() then
            TRP3FW:Info("Minimum font size filter enabled - will apply to newly viewed profiles")
        else
            TRP3FW:Info("Minimum font size filter disabled")
        end
    end)
    y4 = y4 - 40

    -- Font size level dropdown
    uiElements.minimumFontSizeDropdown, uiElements.minimumFontSizeLabel = CreateDropdown(tab4, "Font Size Level", "Select the minimum font size to inject into incoming profiles", 200, "minimumFontSizeLevel")
    uiElements.minimumFontSizeDropdown:SetPoint("TOPLEFT", 40, y4)  -- Indented to show it's related to the checkbox above

    UIDropDownMenu_Initialize(uiElements.minimumFontSizeDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        -- H1 (Largest)
        info.text = "H1 (Largest)"
        info.value = "h1"
        info.tooltipTitle = "H1 (Largest)"
        info.tooltipText = "Inject {h1} tags - Largest heading size"
        info.func = function()
            TRP3FW_Settings.minimumFontSizeLevel = "h1"
            UIDropDownMenu_SetText(uiElements.minimumFontSizeDropdown, "H1 (Largest)")
        end
        UIDropDownMenu_AddButton(info)

        -- H2 (Large)
        info.text = "H2 (Large)"
        info.value = "h2"
        info.tooltipTitle = "H2 (Large)"
        info.tooltipText = "Inject {h2} tags - Large heading size"
        info.func = function()
            TRP3FW_Settings.minimumFontSizeLevel = "h2"
            UIDropDownMenu_SetText(uiElements.minimumFontSizeDropdown, "H2 (Large)")
        end
        UIDropDownMenu_AddButton(info)

        -- H3 (Medium) - DEFAULT
        info.text = "H3 (Medium)"
        info.value = "h3"
        info.tooltipTitle = "H3 (Medium)"
        info.tooltipText = "Inject {h3} tags - Medium heading size (default)"
        info.func = function()
            TRP3FW_Settings.minimumFontSizeLevel = "h3"
            UIDropDownMenu_SetText(uiElements.minimumFontSizeDropdown, "H3 (Medium)")
        end
        UIDropDownMenu_AddButton(info)

        -- P (Normal)
        info.text = "P (Normal)"
        info.value = "p"
        info.tooltipTitle = "P (Normal)"
        info.tooltipText = "Inject {p} tags - Normal paragraph size"
        info.func = function()
            TRP3FW_Settings.minimumFontSizeLevel = "p"
            UIDropDownMenu_SetText(uiElements.minimumFontSizeDropdown, "P (Normal)")
        end
        UIDropDownMenu_AddButton(info)
    end)

    y4 = y4 - 60  -- Dropdown needs more space

    y4 = y4 - 10  -- Extra spacing before new section
    CreateSectionHeader(tab4, "Addon Monitoring", y4)
    y4 = y4 - 40

    uiElements.monitorTRP3 = CreateCheckbox(tab4, "Monitor TotalRP3", "Monitor TRP3 profile requests", "monitorTRP3")
    uiElements.monitorTRP3:SetPoint("TOPLEFT", 20, y4)
    uiElements.monitorTRP3:SetScript("OnClick", function(self)
        TRP3FW_Settings.monitorTRP3 = self:GetChecked()
    end)
    y4 = y4 - 30

    uiElements.monitorMRP = CreateCheckbox(tab4, "Monitor MyRolePlay", "Monitor MRP profile requests", "monitorMRP")
    uiElements.monitorMRP:SetPoint("TOPLEFT", 20, y4)
    uiElements.monitorMRP:SetScript("OnClick", function(self)
        TRP3FW_Settings.monitorMRP = self:GetChecked()
    end)
    y4 = y4 - 30

    uiElements.monitorXRP = CreateCheckbox(tab4, "Monitor XRP", "Monitor XRP profile requests", "monitorXRP")
    uiElements.monitorXRP:SetPoint("TOPLEFT", 20, y4)
    uiElements.monitorXRP:SetScript("OnClick", function(self)
        TRP3FW_Settings.monitorXRP = self:GetChecked()
    end)
    y4 = y4 - 30

    uiElements.monitorMSP = CreateCheckbox(tab4, "Monitor MSP/Other", "Monitor other MSP-compatible addons", "monitorMSP")
    uiElements.monitorMSP:SetPoint("TOPLEFT", 20, y4)
    uiElements.monitorMSP:SetScript("OnClick", function(self)
        TRP3FW_Settings.monitorMSP = self:GetChecked()
    end)

    y4 = y4 - 40
    CreateSectionHeader(tab4, "Hook Safety", y4)
    y4 = y4 - 40

    uiElements.strictHookMode = CreateCheckbox(tab4, "Strict hook mode", "Refuse to install when another addon already hooks core functions (Chomp/TRP3/MSP). May leave TRP3FW partially inactive instead of chaining.", "strictHookMode")
    uiElements.strictHookMode:SetPoint("TOPLEFT", 20, y4)
    uiElements.strictHookMode:SetScript("OnClick", function(self)
        TRP3FW_Settings.strictHookMode = self:GetChecked()
        TRP3FW:Info("Strict hook mode "..(self:GetChecked() and "enabled" or "disabled"))
    end)
    y4 = y4 - 30

    uiElements.logHookConflicts = CreateCheckbox(tab4, "Log hook conflicts", "Warn when hooks are already wrapped by other addons (keeps logs even if chaining)", "logHookConflicts")
    uiElements.logHookConflicts:SetPoint("TOPLEFT", 20, y4)
    uiElements.logHookConflicts:SetScript("OnClick", function(self)
        TRP3FW_Settings.logHookConflicts = self:GetChecked()
    end)
    y4 = y4 - 30

    uiElements.abortOnMultipleRPAddons = CreateCheckbox(tab4, "Abort on multiple RP addons", "Disable TRP3FW when more than one of TRP3/MRP/XRP is detected (incompatible stack)", "abortOnMultipleRPAddons")
    uiElements.abortOnMultipleRPAddons:SetPoint("TOPLEFT", 20, y4)
    uiElements.abortOnMultipleRPAddons:SetScript("OnClick", function(self)
        TRP3FW_Settings.abortOnMultipleRPAddons = self:GetChecked()
    end)
    y4 = y4 - 30

    uiElements.disableMapScanOnTRP3 = CreateCheckbox(tab4, "Disable map scan when TRP3 + RPMapScan", "RPMapScan only supports MRP/XRP. When TRP3 is present with RPMapScan, skip map-scan hooks.", "disableMapScanOnTRP3")
    uiElements.disableMapScanOnTRP3:SetPoint("TOPLEFT", 20, y4)
    uiElements.disableMapScanOnTRP3:SetScript("OnClick", function(self)
        TRP3FW_Settings.disableMapScanOnTRP3 = self:GetChecked()
    end)

    -- ========== TAB 5: CACHE & DEBUG ==========
    local tab5 = tabContents[5].scrollChild
    local y5 = -10

    CreateSectionHeader(tab5, "Cache Settings", y5)
    y5 = y5 - 55

    -- ============================================
    -- PROFILE EXCHANGE CACHING
    -- ============================================
    CreateSectionHeader(tab5, "Profile Exchange Cache", y5)
    y5 = y5 - 45

    uiElements.sendCacheDuration = CreateEditBox(tab5, "Send Cache (s)", "How long to remember allowed senders.", 80, "sendCacheDuration")
    uiElements.sendCacheDuration:SetPoint("TOPLEFT", 20, y5)

    local function saveSendCacheDuration(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 then
            TRP3FW_Settings.sendCacheDuration = value
            TRP3FW:Info("Send cache duration set to "..value.." seconds")
        else
            TRP3FW:Warn("Invalid value")
            self:SetText(TRP3FW_Settings.sendCacheDuration)
        end
    end

    local sendCacheDurationEnterPressed = false
    uiElements.sendCacheDuration:SetScript("OnEnterPressed", function(self)
        sendCacheDurationEnterPressed = true
        saveSendCacheDuration(self)
        self:ClearFocus()
        C_Timer.After(0, function() sendCacheDurationEnterPressed = false end)
    end)
    uiElements.sendCacheDuration:SetScript("OnEditFocusLost", function(self)
        if not sendCacheDurationEnterPressed then
            saveSendCacheDuration(self)
        end
    end)

    y5 = y5 - 45

    uiElements.sendCacheRefreshRate = CreateEditBox(tab5, "Send Refresh (%)", "Percentage of cache duration after which an allowed sender entry is considered stale and refreshed (0-100%). Default: 10%.", 80, "sendCacheRefreshRate")
    uiElements.sendCacheRefreshRate:SetPoint("TOPLEFT", 20, y5)

    local function saveSendCacheRefreshRate(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 and value <= 100 then
            TRP3FW_Settings.sendCacheRefreshRate = value
            TRP3FW:Info("Send cache refresh threshold set to "..value.."%")
        else
            TRP3FW:Warn("Invalid value (must be 0-100)")
            self:SetText(TRP3FW_Settings.sendCacheRefreshRate or 10)
        end
    end

    local sendCacheRefreshRateEnterPressed = false
    uiElements.sendCacheRefreshRate:SetScript("OnEnterPressed", function(self)
        sendCacheRefreshRateEnterPressed = true
        saveSendCacheRefreshRate(self)
        self:ClearFocus()
        C_Timer.After(0, function() sendCacheRefreshRateEnterPressed = false end)
    end)
    uiElements.sendCacheRefreshRate:SetScript("OnEditFocusLost", function(self)
        if not sendCacheRefreshRateEnterPressed then
            saveSendCacheRefreshRate(self)
        end
    end)
    y5 = y5 - 75

    -- ============================================
    -- INTERACTION CACHING
    -- ============================================
    CreateSectionHeader(tab5, "Interaction Cache", y5)
    y5 = y5 - 45

    uiElements.interactionCacheDuration = CreateEditBox(tab5, "Interaction Cache (s)", "How long to keep interaction records (mouseover/target). This bypasses location checks.", 80, "interactionCacheDuration")
    uiElements.interactionCacheDuration:SetPoint("TOPLEFT", 20, y5)

    local function saveInteractionCacheDuration(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 then
            TRP3FW_Settings.interactionCacheDuration = value
            TRP3FW:Info("Interaction cache duration set to "..value.." seconds")
        else
            TRP3FW:Warn("Invalid value")
            self:SetText(TRP3FW_Settings.interactionCacheDuration)
        end
    end

    local interactionCacheDurationEnterPressed = false
    uiElements.interactionCacheDuration:SetScript("OnEnterPressed", function(self)
        interactionCacheDurationEnterPressed = true
        saveInteractionCacheDuration(self)
        self:ClearFocus()
        C_Timer.After(0, function() interactionCacheDurationEnterPressed = false end)
    end)
    uiElements.interactionCacheDuration:SetScript("OnEditFocusLost", function(self)
        if not interactionCacheDurationEnterPressed then
            saveInteractionCacheDuration(self)
        end
    end)

    y5 = y5 - 45

    uiElements.interactionRefreshRate = CreateEditBox(tab5, "Interaction Refresh (%)", "Percentage of cache duration after which an entry is considered stale and refreshed (0-100%). Default: 10%.", 80, "interactionRefreshRate")
    uiElements.interactionRefreshRate:SetPoint("TOPLEFT", 20, y5)

    local function saveInteractionRefreshRate(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 and value <= 100 then
            TRP3FW_Settings.interactionRefreshRate = value
            TRP3FW:Info("Interaction refresh threshold set to "..value.."%")
            TRP3FW:Warn("This will take effect after /reload")
        else
            TRP3FW:Warn("Invalid value (must be 0-100)")
            self:SetText(TRP3FW_Settings.interactionRefreshRate or 10)
        end
    end

    local interactionRefreshRateEnterPressed = false
    uiElements.interactionRefreshRate:SetScript("OnEnterPressed", function(self)
        interactionRefreshRateEnterPressed = true
        saveInteractionRefreshRate(self)
        self:ClearFocus()
        C_Timer.After(0, function() interactionRefreshRateEnterPressed = false end)
    end)
    uiElements.interactionRefreshRate:SetScript("OnEditFocusLost", function(self)
        if not interactionRefreshRateEnterPressed then
            saveInteractionRefreshRate(self)
        end
    end)
    y5 = y5 - 75

    -- ============================================
    -- WHO/ZONE QUERY CACHING
    -- ============================================
    CreateSectionHeader(tab5, "WHO & Zone Cache", y5)
    y5 = y5 - 45

    uiElements.whoZoneCacheDuration = CreateEditBox(tab5, "WHO Zone (s)", "How long to cache WHO zone query results.", 80, "whoZoneCacheDuration")
    uiElements.whoZoneCacheDuration:SetPoint("TOPLEFT", 20, y5)

    local function saveWhoZoneCacheDuration(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 then
            TRP3FW_Settings.whoZoneCacheDuration = value
            TRP3FW:Info("WHO zone cache duration set to "..value.." seconds")
        else
            TRP3FW:Warn("Invalid value")
            self:SetText(TRP3FW_Settings.whoZoneCacheDuration)
        end
    end

    local whoZoneCacheDurationEnterPressed = false
    uiElements.whoZoneCacheDuration:SetScript("OnEnterPressed", function(self)
        whoZoneCacheDurationEnterPressed = true
        saveWhoZoneCacheDuration(self)
        self:ClearFocus()
        C_Timer.After(0, function() whoZoneCacheDurationEnterPressed = false end)
    end)
    uiElements.whoZoneCacheDuration:SetScript("OnEditFocusLost", function(self)
        if not whoZoneCacheDurationEnterPressed then
            saveWhoZoneCacheDuration(self)
        end
    end)

    y5 = y5 - 45

    uiElements.whoNameCacheDuration = CreateEditBox(tab5, "WHO Name (s)", "How long to cache WHO name query results.", 80, "whoNameCacheDuration")
    uiElements.whoNameCacheDuration:SetPoint("TOPLEFT", 20, y5)

    local function saveWhoNameCacheDuration(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 then
            TRP3FW_Settings.whoNameCacheDuration = value
            TRP3FW:Info("WHO name cache duration set to "..value.." seconds")
        else
            TRP3FW:Warn("Invalid value")
            self:SetText(TRP3FW_Settings.whoNameCacheDuration)
        end
    end

    local whoNameCacheDurationEnterPressed = false
    uiElements.whoNameCacheDuration:SetScript("OnEnterPressed", function(self)
        whoNameCacheDurationEnterPressed = true
        saveWhoNameCacheDuration(self)
        self:ClearFocus()
        C_Timer.After(0, function() whoNameCacheDurationEnterPressed = false end)
    end)
    uiElements.whoNameCacheDuration:SetScript("OnEditFocusLost", function(self)
        if not whoNameCacheDurationEnterPressed then
            saveWhoNameCacheDuration(self)
        end
    end)

    y5 = y5 - 45

    uiElements.whoZoneQueryCooldown = CreateEditBox(tab5, "Zone Cooldown (s)", "Minimum seconds between z- WHO zone queries.", 80, "whoZoneQueryCooldown")
    uiElements.whoZoneQueryCooldown:SetPoint("TOPLEFT", 20, y5)

    local function saveWhoZoneQueryCooldown(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 and value <= 120 then
            TRP3FW_Settings.whoZoneQueryCooldown = value
            TRP3FW:Info("WHO zone query cooldown set to "..value.." seconds")
        else
            TRP3FW:Warn("Invalid value (must be 0-120)")
            self:SetText(TRP3FW_Settings.whoZoneQueryCooldown)
        end
    end

    local whoZoneQueryCooldownEnterPressed = false
    uiElements.whoZoneQueryCooldown:SetScript("OnEnterPressed", function(self)
        whoZoneQueryCooldownEnterPressed = true
        saveWhoZoneQueryCooldown(self)
        self:ClearFocus()
        C_Timer.After(0, function() whoZoneQueryCooldownEnterPressed = false end)
    end)
    uiElements.whoZoneQueryCooldown:SetScript("OnEditFocusLost", function(self)
        if not whoZoneQueryCooldownEnterPressed then
            saveWhoZoneQueryCooldown(self)
        end
    end)
    y5 = y5 - 45

    uiElements.whoCacheRefreshThreshold = CreateEditBox(tab5, "WHO Refresh (%)", "Percentage of cache duration after which an entry is considered stale and refreshed (0-100%). Default: 50%.", 80, "whoCacheRefreshThreshold")
    uiElements.whoCacheRefreshThreshold:SetPoint("TOPLEFT", 20, y5)

    local function saveWhoCacheRefreshThreshold(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 and value <= 100 then
            TRP3FW_Settings.whoCacheRefreshThreshold = value
            TRP3FW:Info("WHO cache refresh threshold set to "..value.."%")
        else
            TRP3FW:Warn("Invalid value (must be 0-100)")
            self:SetText(TRP3FW_Settings.whoCacheRefreshThreshold or 50)
        end
    end

    local whoCacheRefreshThresholdEnterPressed = false
    uiElements.whoCacheRefreshThreshold:SetScript("OnEnterPressed", function(self)
        whoCacheRefreshThresholdEnterPressed = true
        saveWhoCacheRefreshThreshold(self)
        self:ClearFocus()
        C_Timer.After(0, function() whoCacheRefreshThresholdEnterPressed = false end)
    end)
    uiElements.whoCacheRefreshThreshold:SetScript("OnEditFocusLost", function(self)
        if not whoCacheRefreshThresholdEnterPressed then
            saveWhoCacheRefreshThreshold(self)
        end
    end)
    y5 = y5 - 45

    -- WHO cache prepopulation (tied to WHO caching above)
    local function setPrepopulateWhoChildrenEnabled(enabled)
        local shouldEnable = not not enabled
        if uiElements.prepopulateWhoOnPhase then
            uiElements.prepopulateWhoOnPhase:SetEnabled(shouldEnable)
        end
        if uiElements.prepopulateWhoOnZone then
            uiElements.prepopulateWhoOnZone:SetEnabled(shouldEnable)
        end
    end

    uiElements.prepopulateWhoCache = CreateCheckbox(tab5, "Prepopulate WHO Cache", "When enabled, TRP3FW will proactively run WHO queries after zone/phase changes to warm up the WHO cache. Disable if you prefer manual WHO caching.", "prepopulateWhoCache")
    uiElements.prepopulateWhoCache:SetPoint("TOPLEFT", 20, y5)
    uiElements.prepopulateWhoCache:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        TRP3FW_Settings.prepopulateWhoCache = checked
        setPrepopulateWhoChildrenEnabled(checked)
    end)
    uiElements.prepopulateWhoCache:SetChecked(TRP3FW_Settings.prepopulateWhoCache ~= false)
    y5 = y5 - 25

    uiElements.prepopulateWhoOnPhase = CreateCheckbox(tab5, "  On Phase Change", "Run WHO cache pre-population after phase changes (SCENARIO_UPDATE event).", "prepopulateWhoOnPhase")
    uiElements.prepopulateWhoOnPhase:SetPoint("TOPLEFT", 40, y5)
    uiElements.prepopulateWhoOnPhase:SetScript("OnClick", function(self)
        TRP3FW_Settings.prepopulateWhoOnPhase = self:GetChecked()
    end)
    uiElements.prepopulateWhoOnPhase:SetChecked(TRP3FW_Settings.prepopulateWhoOnPhase ~= false)
    y5 = y5 - 20

    uiElements.prepopulateWhoOnZone = CreateCheckbox(tab5, "  On Zone Change", "Run WHO cache pre-population after zone changes (ZONE_CHANGED_NEW_AREA event).", "prepopulateWhoOnZone")
    uiElements.prepopulateWhoOnZone:SetPoint("TOPLEFT", 40, y5)
    uiElements.prepopulateWhoOnZone:SetScript("OnClick", function(self)
        TRP3FW_Settings.prepopulateWhoOnZone = self:GetChecked()
    end)
    uiElements.prepopulateWhoOnZone:SetChecked(TRP3FW_Settings.prepopulateWhoOnZone ~= false)
    setPrepopulateWhoChildrenEnabled(uiElements.prepopulateWhoCache:GetChecked())
    y5 = y5 - 25

    y5 = y5 - 30

    -- ============================================
    -- PHASE / SCAN CACHING
    -- ============================================
    CreateSectionHeader(tab5, "Phase & Scan Cache", y5)
    y5 = y5 - 45

    uiElements.phaseCacheDuration = CreateEditBox(tab5, "Phase Cache (s)", "How long to cache SUCCESSFUL phase check results.", 80, "phaseCacheDuration")
    uiElements.phaseCacheDuration:SetPoint("TOPLEFT", 20, y5)

    local function savePhaseCacheDuration(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 then
            TRP3FW_Settings.phaseCacheDuration = value
            TRP3FW:Info("Phase cache duration set to "..value.." seconds")
        else
            TRP3FW:Warn("Invalid value")
            self:SetText(TRP3FW_Settings.phaseCacheDuration)
        end
    end

    local phaseCacheDurationEnterPressed = false
    uiElements.phaseCacheDuration:SetScript("OnEnterPressed", function(self)
        phaseCacheDurationEnterPressed = true
        savePhaseCacheDuration(self)
        self:ClearFocus()
        C_Timer.After(0, function() phaseCacheDurationEnterPressed = false end)
    end)
    uiElements.phaseCacheDuration:SetScript("OnEditFocusLost", function(self)
        if not phaseCacheDurationEnterPressed then
            savePhaseCacheDuration(self)
        end
    end)

    y5 = y5 - 45

    uiElements.phaseCacheFailureDuration = CreateEditBox(tab5, "Phase Fail (s)", "How long to cache FAILED phase check results (short duration recommended).", 80, "phaseCacheFailureDuration")
    uiElements.phaseCacheFailureDuration:SetPoint("TOPLEFT", 20, y5)

    local function savePhaseCacheFailureDuration(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 then
            TRP3FW_Settings.phaseCacheFailureDuration = value
            TRP3FW:Info("Phase cache failure duration set to "..value.." seconds")
        else
            TRP3FW:Warn("Invalid value")
            self:SetText(TRP3FW_Settings.phaseCacheFailureDuration or 10)
        end
    end

    local phaseCacheFailureDurationEnterPressed = false
    uiElements.phaseCacheFailureDuration:SetScript("OnEnterPressed", function(self)
        phaseCacheFailureDurationEnterPressed = true
        savePhaseCacheFailureDuration(self)
        self:ClearFocus()
        C_Timer.After(0, function() phaseCacheFailureDurationEnterPressed = false end)
    end)
    uiElements.phaseCacheFailureDuration:SetScript("OnEditFocusLost", function(self)
        if not phaseCacheFailureDurationEnterPressed then
            savePhaseCacheFailureDuration(self)
        end
    end)

    y5 = y5 - 45

    uiElements.scanCacheDuration = CreateEditBox(tab5, "Scan Cache (s)", "How long to cache map scan results.", 80, "scanCacheDuration")
    uiElements.scanCacheDuration:SetPoint("TOPLEFT", 20, y5)

    local function saveScanCacheDuration(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 then
            TRP3FW_Settings.scanCacheDuration = value
            TRP3FW:Info("Scan cache duration set to "..value.." seconds")
        else
            TRP3FW:Warn("Invalid value")
            self:SetText(TRP3FW_Settings.scanCacheDuration)
        end
    end

    local scanCacheDurationEnterPressed = false
    uiElements.scanCacheDuration:SetScript("OnEnterPressed", function(self)
        scanCacheDurationEnterPressed = true
        saveScanCacheDuration(self)
        self:ClearFocus()
        C_Timer.After(0, function() scanCacheDurationEnterPressed = false end)
    end)
    uiElements.scanCacheDuration:SetScript("OnEditFocusLost", function(self)
        if not scanCacheDurationEnterPressed then
            saveScanCacheDuration(self)
        end
    end)

    y5 = y5 - 45

    uiElements.scanCacheFailureDuration = CreateEditBox(tab5, "Scan Fail (s)", "How long to cache FAILED scan/broadcast results (short duration recommended).", 80, "scanCacheFailureDuration")
    uiElements.scanCacheFailureDuration:SetPoint("TOPLEFT", 20, y5)

    local function saveScanCacheFailureDuration(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 then
            TRP3FW_Settings.scanCacheFailureDuration = value
            TRP3FW:Info("Scan failure cache duration set to "..value.." seconds")
        else
            TRP3FW:Warn("Invalid value")
            self:SetText(TRP3FW_Settings.scanCacheFailureDuration or 10)
        end
    end

    local scanCacheFailureDurationEnterPressed = false
    uiElements.scanCacheFailureDuration:SetScript("OnEnterPressed", function(self)
        scanCacheFailureDurationEnterPressed = true
        saveScanCacheFailureDuration(self)
        self:ClearFocus()
        C_Timer.After(0, function() scanCacheFailureDurationEnterPressed = false end)
    end)
    uiElements.scanCacheFailureDuration:SetScript("OnEditFocusLost", function(self)
        if not scanCacheFailureDurationEnterPressed then
            saveScanCacheFailureDuration(self)
        end
    end)

    y5 = y5 - 45

    uiElements.mapScanMinInterval = CreateEditBox(tab5, "Min Scan Interval (s)", "Minimum seconds between map scans (manual or automatic).", 100, "mapScanMinInterval")
    uiElements.mapScanMinInterval:SetPoint("TOPLEFT", 20, y5)

    local function saveMapScanMinInterval(self)
        local value = tonumber(self:GetText())
        if value and value >= 10 and value <= 600 then
            TRP3FW_Settings.mapScanMinInterval = value
            TRP3FW:Info("Map scan minimum interval set to "..value.." seconds")
        else
            TRP3FW:Warn("Invalid value (must be 10-600)")
            self:SetText(TRP3FW_Settings.mapScanMinInterval or 60)
        end
    end

    local mapScanMinIntervalEnterPressed = false
    uiElements.mapScanMinInterval:SetScript("OnEnterPressed", function(self)
        mapScanMinIntervalEnterPressed = true
        saveMapScanMinInterval(self)
        self:ClearFocus()
        C_Timer.After(0, function() mapScanMinIntervalEnterPressed = false end)
    end)
    uiElements.mapScanMinInterval:SetScript("OnEditFocusLost", function(self)
        if not mapScanMinIntervalEnterPressed then
            saveMapScanMinInterval(self)
        end
    end)

    y5 = y5 - 45

    uiElements.phaseCacheRefreshThreshold = CreateEditBox(tab5, "Phase Refresh (%)", "Enter a whole number from 0 to 100. This is the percentage of cache duration after which a phase result is considered stale and a background refresh is triggered. (e.g., 10 for 10%, 50 for 50%). Default: 20%.", 80, "phaseCacheRefreshThreshold")
    uiElements.phaseCacheRefreshThreshold:SetPoint("TOPLEFT", 20, y5)

    local function savePhaseCacheRefreshThreshold(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 and value <= 100 then
            TRP3FW_Settings.phaseCacheRefreshThreshold = value / 100
            TRP3FW:Info("Phase cache refresh threshold set to "..value.."%")
        else
            TRP3FW:Warn("Invalid value (must be 0-100)")
            self:SetText((TRP3FW_Settings.phaseCacheRefreshThreshold or 0.2) * 100)
        end
    end

    local phaseCacheRefreshThresholdEnterPressed = false
    uiElements.phaseCacheRefreshThreshold:SetScript("OnEnterPressed", function(self)
        phaseCacheRefreshThresholdEnterPressed = true
        savePhaseCacheRefreshThreshold(self)
        self:ClearFocus()
        C_Timer.After(0, function() phaseCacheRefreshThresholdEnterPressed = false end)
    end)
    uiElements.phaseCacheRefreshThreshold:SetScript("OnEditFocusLost", function(self)
        if not phaseCacheRefreshThresholdEnterPressed then
            savePhaseCacheRefreshThreshold(self)
        end
    end)

    y5 = y5 - 150

    -- ============================================
    -- SPVP CACHE SETTINGS
    -- ============================================
    CreateSectionHeader(tab5, "SPVP Cache Settings", y5)
    y5 = y5 - 45

    -- SPVP Verified Cache Duration (in seconds)
    uiElements.spvpVerifiedCacheDuration = CreateEditBox(tab5, "Verification Duration (s)", "How long a cryptographic verification remains valid (seconds). Longer durations reduce network overhead.", 80, "spvpVerifiedCacheDuration")
    uiElements.spvpVerifiedCacheDuration:SetPoint("TOPLEFT", 20, y5)

    local function saveSpvpVerifiedCacheDuration(self)
        local value = tonumber(self:GetText())
        if value and value >= 10 and value <= 3600 then
            TRP3FW_Settings.spvpVerifiedCacheDuration = value
            TRP3FW:Info("SPVP verification duration set to "..value.." seconds")
            -- Update cache if registered
            local CI = TRP3FW.CacheInterface
            if CI and CI.caches["spvpVerified"] then
                CI.caches["spvpVerified"].options.ttl = value
            end
        else
            TRP3FW:Warn("Invalid value (must be 10-3600 seconds)")
            local currentSeconds = TRP3FW_Settings.spvpVerifiedCacheDuration or 300
            self:SetText(currentSeconds)
        end
    end

    local spvpVerifiedDurationEnterPressed = false
    uiElements.spvpVerifiedCacheDuration:SetScript("OnEnterPressed", function(self)
        spvpVerifiedDurationEnterPressed = true
        saveSpvpVerifiedCacheDuration(self)
        self:ClearFocus()
        C_Timer.After(0, function() spvpVerifiedDurationEnterPressed = false end)
    end)
    uiElements.spvpVerifiedCacheDuration:SetScript("OnEditFocusLost", function(self)
        if not spvpVerifiedDurationEnterPressed then
            saveSpvpVerifiedCacheDuration(self)
        end
    end)

    y5 = y5 - 45

    -- SPVP Verified Refresh (%)
    uiElements.spvpVerifiedRefreshRate = CreateEditBox(tab5, "Verification Refresh (%)", "Percentage of duration after which a background re-verification is triggered (10-90%).", 80, "spvpVerifiedRefreshRate")
    uiElements.spvpVerifiedRefreshRate:SetPoint("TOPLEFT", 20, y5)

    local function saveSpvpVerifiedRefreshRate(self)
        local value = tonumber(self:GetText())
        if value and value >= 10 and value <= 90 then
            TRP3FW_Settings.spvpVerifiedRefreshRate = value
            TRP3FW:Info("SPVP verification refresh threshold set to "..value.."%")
        else
            TRP3FW:Warn("Invalid value (must be 10-90%)")
            self:SetText(TRP3FW_Settings.spvpVerifiedRefreshRate or 50)
        end
    end

    local spvpVerifiedRefreshEnterPressed = false
    uiElements.spvpVerifiedRefreshRate:SetScript("OnEnterPressed", function(self)
        spvpVerifiedRefreshEnterPressed = true
        saveSpvpVerifiedRefreshRate(self)
        self:ClearFocus()
        C_Timer.After(0, function() spvpVerifiedRefreshEnterPressed = false end)
    end)
    uiElements.spvpVerifiedRefreshRate:SetScript("OnEditFocusLost", function(self)
        if not spvpVerifiedRefreshEnterPressed then
            saveSpvpVerifiedRefreshRate(self)
        end
    end)

    y5 = y5 - 45

    -- SPVP Salt Refresh (%)
    uiElements.spvpPhaseSaltRefreshRate = CreateEditBox(tab5, "Phase Salt Refresh (%)", "Percentage of salt cache duration (3h) after which a background fetch is triggered (10-90%).", 80, "spvpPhaseSaltRefreshRate")
    uiElements.spvpPhaseSaltRefreshRate:SetPoint("TOPLEFT", 20, y5)

    local function saveSpvpSaltRefreshRate(self)
        local value = tonumber(self:GetText())
        if value and value >= 10 and value <= 90 then
            TRP3FW_Settings.spvpPhaseSaltRefreshRate = value
            TRP3FW:Info("Phase salt refresh threshold set to "..value.."%")
        else
            TRP3FW:Warn("Invalid value (must be 10-90%)")
            self:SetText(TRP3FW_Settings.spvpPhaseSaltRefreshRate or 50)
        end
    end

    local spvpSaltRefreshEnterPressed = false
    uiElements.spvpPhaseSaltRefreshRate:SetScript("OnEnterPressed", function(self)
        spvpSaltRefreshEnterPressed = true
        saveSpvpSaltRefreshRate(self)
        self:ClearFocus()
        C_Timer.After(0, function() spvpSaltRefreshEnterPressed = false end)
    end)
    uiElements.spvpPhaseSaltRefreshRate:SetScript("OnEditFocusLost", function(self)
        if not spvpSaltRefreshEnterPressed then
            saveSpvpSaltRefreshRate(self)
        end
    end)

    y5 = y5 - 60

    -- ============================================
    -- CACHE LIMITS & TIMING
    -- ============================================
    CreateSectionHeader(tab5, "Cache Limits & Timing", y5)
    y5 = y5 - 45

    uiElements.cacheSizeLimit = CreateEditBox(tab5, "Cache Size Limit", "Maximum number of entries per cache type.", 80, "cacheSizeLimit")
    uiElements.cacheSizeLimit:SetPoint("TOPLEFT", 20, y5)

    local function saveCacheSizeLimit(self)
        local value = tonumber(self:GetText())
        if value and value >= 100 and value <= 10000 then
            TRP3FW_Settings.cacheSizeLimit = value
            TRP3FW:Info("Cache size limit set to "..value.." entries")
        else
            TRP3FW:Warn("Invalid value (must be 100-10000)")
            self:SetText(TRP3FW_Settings.cacheSizeLimit or 1000)
        end
    end

    local cacheSizeLimitEnterPressed = false
    uiElements.cacheSizeLimit:SetScript("OnEnterPressed", function(self)
        cacheSizeLimitEnterPressed = true
        saveCacheSizeLimit(self)
        self:ClearFocus()
        C_Timer.After(0, function() cacheSizeLimitEnterPressed = false end)
    end)
    uiElements.cacheSizeLimit:SetScript("OnEditFocusLost", function(self)
        if not cacheSizeLimitEnterPressed then
            saveCacheSizeLimit(self)
        end
    end)

    y5 = y5 - 45

    uiElements.phaseInDelay = CreateEditBox(tab5, "Phase-In Delay", "Seconds to delay profile processing after phasing (0-10, prevents false alerts during load-in).", 80, "phaseInDelay")
    uiElements.phaseInDelay:SetPoint("TOPLEFT", 20, y5)

    local function savePhaseInDelay(self)
        local rawValue = tonumber(self:GetText())
        if rawValue and rawValue >= 0 and rawValue <= 10 then
            local value = rawValue
            if value < 3 and value ~= 0 then
                TRP3FW:Warn("Phase-in delay values below 3 seconds are treated as 0 (no delay).")
                value = 0
            end
            TRP3FW_Settings.phaseInDelay = value
            self:SetText(value)
            TRP3FW:Info("Phase-in delay set to "..value.." seconds")
        else
            TRP3FW:Warn("Invalid value (must be 0-10)")
            self:SetText(TRP3FW_Settings.phaseInDelay or 4)
        end
    end

    local phaseInDelayEnterPressed = false
    uiElements.phaseInDelay:SetScript("OnEnterPressed", function(self)
        phaseInDelayEnterPressed = true
        savePhaseInDelay(self)
        self:ClearFocus()
        C_Timer.After(0, function() phaseInDelayEnterPressed = false end)
    end)
    uiElements.phaseInDelay:SetScript("OnEditFocusLost", function(self)
        if not phaseInDelayEnterPressed then
            savePhaseInDelay(self)
        end
    end)

    y5 = y5 - 45

    uiElements.transitionGracePeriod = CreateEditBox(tab5, "Transition Grace Period", "Seconds after map/phase change to warn about potential false alerts (helps identify race conditions).", 80, "transitionGracePeriod")
    uiElements.transitionGracePeriod:SetPoint("TOPLEFT", 20, y5)

    local function saveTransitionGracePeriod(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 and value <= 30 then
            TRP3FW_Settings.transitionGracePeriod = value
            TRP3FW:Info("Transition grace period set to "..value.." seconds")
        else
            TRP3FW:Warn("Invalid value (must be 0-30)")
            self:SetText(TRP3FW_Settings.transitionGracePeriod or 10)
        end
    end

    local transitionGracePeriodEnterPressed = false
    uiElements.transitionGracePeriod:SetScript("OnEnterPressed", function(self)
        transitionGracePeriodEnterPressed = true
        saveTransitionGracePeriod(self)
        self:ClearFocus()
        C_Timer.After(0, function() transitionGracePeriodEnterPressed = false end)
    end)
    uiElements.transitionGracePeriod:SetScript("OnEditFocusLost", function(self)
        if not transitionGracePeriodEnterPressed then
            saveTransitionGracePeriod(self)
        end
    end)
    y5 = y5 - 75

    -- Validated Names Cache Duration (in days, converted to/from seconds)
    uiElements.validatedNamesCacheDuration = CreateEditBox(tab5, "Name Cache Duration (days)", "How long to keep validated player names cached (1-30 days). Lower = fresher validation, Higher = better performance.", 80, "validatedNamesCacheDuration")
    uiElements.validatedNamesCacheDuration:SetPoint("TOPLEFT", 20, y5)

    local function saveValidatedNamesCacheDuration(self)
        local days = tonumber(self:GetText())
        if days and days >= 1 and days <= 30 then
            local seconds = days * 86400
            TRP3FW_Settings.validatedNamesCacheDuration = seconds
            TRP3FW:Info("Validated names cache duration set to "..days.." days ("..seconds.." seconds)")
        else
            TRP3FW:Warn("Invalid value (must be 1-30 days)")
            local currentSeconds = TRP3FW_Settings.validatedNamesCacheDuration or 604800
            local currentDays = math.floor(currentSeconds / 86400)
            self:SetText(currentDays)
        end
    end

    local validatedNamesCacheDurationEnterPressed = false
    uiElements.validatedNamesCacheDuration:SetScript("OnEnterPressed", function(self)
        validatedNamesCacheDurationEnterPressed = true
        saveValidatedNamesCacheDuration(self)
        self:ClearFocus()
        C_Timer.After(0, function() validatedNamesCacheDurationEnterPressed = false end)
    end)
    uiElements.validatedNamesCacheDuration:SetScript("OnEditFocusLost", function(self)
        if not validatedNamesCacheDurationEnterPressed then
            saveValidatedNamesCacheDuration(self)
        end
    end)

    y5 = y5 - 45

    -- Validated Names Cache Size Limit
    uiElements.validatedNamesCacheLimit = CreateEditBox(tab5, "Name Cache Size Limit", "Maximum number of validated names to keep in cache (500-10000). Higher = better performance, Lower = less SavedVariables bloat.", 80, "validatedNamesCacheLimit")
    uiElements.validatedNamesCacheLimit:SetPoint("TOPLEFT", 20, y5)

    local function saveValidatedNamesCacheLimit(self)
        local limit = tonumber(self:GetText())
        if limit and limit >= 500 and limit <= 10000 then
            TRP3FW_Settings.validatedNamesCacheLimit = limit
            TRP3FW:Info("Validated names cache size limit set to "..limit.." entries")
        else
            TRP3FW:Warn("Invalid value (must be 500-10000)")
            self:SetText(TRP3FW_Settings.validatedNamesCacheLimit or 5000)
        end
    end

    local validatedNamesCacheLimitEnterPressed = false
    uiElements.validatedNamesCacheLimit:SetScript("OnEnterPressed", function(self)
        validatedNamesCacheLimitEnterPressed = true
        saveValidatedNamesCacheLimit(self)
        self:ClearFocus()
        C_Timer.After(0, function() validatedNamesCacheLimitEnterPressed = false end)
    end)
    uiElements.validatedNamesCacheLimit:SetScript("OnEditFocusLost", function(self)
        if not validatedNamesCacheLimitEnterPressed then
            saveValidatedNamesCacheLimit(self)
        end
    end)
    y5 = y5 - 75

    -- ============================================
    -- CACHE CLEARING
    -- ============================================
    CreateSectionHeader(tab5, "Cache Clearing", y5)
    y5 = y5 - 45

    -- Phase Change Cache Clearing
    uiElements.clearCacheOnPhaseChange = CreateCheckbox(tab5, "Clear Cache on Phase Change", "Master toggle - clear selected caches when changing phases (SCENARIO_UPDATE event)", "clearCacheOnPhaseChange")
    uiElements.clearCacheOnPhaseChange:SetPoint("TOPLEFT", 20, y5)
    uiElements.clearCacheOnPhaseChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearCacheOnPhaseChange = self:GetChecked()
        local enabled = self:GetChecked()
        -- Enable/disable granular options
        if enabled then
            uiElements.clearPhaseCheckOnPhaseChange:Enable()
            uiElements.clearAllowedSendersOnPhaseChange:Enable()
            uiElements.clearInteractionOnPhaseChange:Enable()
            uiElements.clearSuppressionOnPhaseChange:Enable()
            uiElements.clearRecentBroadcastsOnPhaseChange:Enable()
            uiElements.clearRecentScansOnPhaseChange:Enable()
            uiElements.clearWhoZoneOnPhaseChange:Enable()
            uiElements.clearWhoNameOnPhaseChange:Enable()
        else
            uiElements.clearPhaseCheckOnPhaseChange:Disable()
            uiElements.clearAllowedSendersOnPhaseChange:Disable()
            uiElements.clearInteractionOnPhaseChange:Disable()
            uiElements.clearSuppressionOnPhaseChange:Disable()
            uiElements.clearRecentBroadcastsOnPhaseChange:Disable()
            uiElements.clearRecentScansOnPhaseChange:Disable()
            uiElements.clearWhoZoneOnPhaseChange:Disable()
            uiElements.clearWhoNameOnPhaseChange:Disable()
        end
    end)
    y5 = y5 - 30

    -- Granular phase change options (indented)
    uiElements.clearPhaseCheckOnPhaseChange = CreateCheckbox(tab5, "  Phase Check Cache", "Clear phase check cache on phase change. Recommended if phase cache pre-population is enabled; otherwise previously cached entries may allow sends for players no longer nearby.", "clearPhaseCheckOnPhaseChange")
    uiElements.clearPhaseCheckOnPhaseChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearPhaseCheckOnPhaseChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearPhaseCheckOnPhaseChange = self:GetChecked()
    end)
    y5 = y5 - 25

    uiElements.clearAllowedSendersOnPhaseChange = CreateCheckbox(tab5, "  Allowed Senders Cache", "Clear allowed senders cache on phase change", "clearAllowedSendersOnPhaseChange")
    uiElements.clearAllowedSendersOnPhaseChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearAllowedSendersOnPhaseChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearAllowedSendersOnPhaseChange = self:GetChecked()
    end)
    y5 = y5 - 25

    uiElements.clearInteractionOnPhaseChange = CreateCheckbox(tab5, "  Interaction Cache", "Clear interaction cache on phase change", "clearInteractionOnPhaseChange")
    uiElements.clearInteractionOnPhaseChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearInteractionOnPhaseChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearInteractionOnPhaseChange = self:GetChecked()
    end)
    y5 = y5 - 25

    uiElements.clearSuppressionOnPhaseChange = CreateCheckbox(tab5, "  Suppression Timers", "Clear notification suppression timers on phase change (resets per-player notification cooldowns)", "clearSuppressionOnPhaseChange")
    uiElements.clearSuppressionOnPhaseChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearSuppressionOnPhaseChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearSuppressionOnPhaseChange = self:GetChecked()
    end)
    y5 = y5 - 25

    uiElements.clearRecentBroadcastsOnPhaseChange = CreateCheckbox(tab5, "  Recent Broadcasts Cache", "Clear recent broadcasts cache on phase change", "clearRecentBroadcastsOnPhaseChange")
    uiElements.clearRecentBroadcastsOnPhaseChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearRecentBroadcastsOnPhaseChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearRecentBroadcastsOnPhaseChange = self:GetChecked()
    end)
    y5 = y5 - 25

    uiElements.clearRecentScansOnPhaseChange = CreateCheckbox(tab5, "  Recent Scans Cache", "Clear recent scans cache on phase change", "clearRecentScansOnPhaseChange")
    uiElements.clearRecentScansOnPhaseChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearRecentScansOnPhaseChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearRecentScansOnPhaseChange = self:GetChecked()
    end)
    y5 = y5 - 25

    uiElements.clearWhoZoneOnPhaseChange = CreateCheckbox(tab5, "  WHO Zone Cache", "Clear WHO zone cache on phase change", "clearWhoZoneOnPhaseChange")
    uiElements.clearWhoZoneOnPhaseChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearWhoZoneOnPhaseChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearWhoZoneOnPhaseChange = self:GetChecked()
    end)
    y5 = y5 - 25

    uiElements.clearWhoNameOnPhaseChange = CreateCheckbox(tab5, "  WHO Name Cache", "Clear WHO name cache on phase change", "clearWhoNameOnPhaseChange")
    uiElements.clearWhoNameOnPhaseChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearWhoNameOnPhaseChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearWhoNameOnPhaseChange = self:GetChecked()
    end)
    y5 = y5 - 25

    uiElements.clearSpvpOnPhaseChange = CreateCheckbox(tab5, "  SPVP Verification Cache", "Clear SPVP verification cache on phase change (Required for security)", "clearSpvpOnPhaseChange")
    uiElements.clearSpvpOnPhaseChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearSpvpOnPhaseChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearSpvpOnPhaseChange = self:GetChecked()
    end)
    y5 = y5 - 35

    -- Zone Change Cache Clearing
    uiElements.clearCacheOnZoneChange = CreateCheckbox(tab5, "Clear Cache on Zone Change", "Master toggle - clear selected caches when changing zones (ZONE_CHANGED_NEW_AREA event)", "clearCacheOnZoneChange")
    uiElements.clearCacheOnZoneChange:SetPoint("TOPLEFT", 20, y5)
    uiElements.clearCacheOnZoneChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearCacheOnZoneChange = self:GetChecked()
        local enabled = self:GetChecked()
        -- Enable/disable granular options
        if enabled then
            uiElements.clearPhaseCheckOnZoneChange:Enable()
            uiElements.clearAllowedSendersOnZoneChange:Enable()
            uiElements.clearInteractionOnZoneChange:Enable()
            uiElements.clearSuppressionOnZoneChange:Enable()
            uiElements.clearRecentBroadcastsOnZoneChange:Enable()
            uiElements.clearRecentScansOnZoneChange:Enable()
            uiElements.clearWhoZoneOnZoneChange:Enable()
            uiElements.clearWhoNameOnZoneChange:Enable()
            uiElements.clearSpvpOnZoneChange:Enable()
        else
            uiElements.clearPhaseCheckOnZoneChange:Disable()
            uiElements.clearAllowedSendersOnZoneChange:Disable()
            uiElements.clearInteractionOnZoneChange:Disable()
            uiElements.clearSuppressionOnZoneChange:Disable()
            uiElements.clearRecentBroadcastsOnZoneChange:Disable()
            uiElements.clearRecentScansOnZoneChange:Disable()
            uiElements.clearWhoZoneOnZoneChange:Disable()
            uiElements.clearWhoNameOnZoneChange:Disable()
            uiElements.clearSpvpOnZoneChange:Disable()
        end
    end)
    y5 = y5 - 30

    -- Granular zone change options (indented)
    uiElements.clearPhaseCheckOnZoneChange = CreateCheckbox(tab5, "  Phase Check Cache", "Clear phase check cache on zone change. Recommended if phase cache pre-population is enabled; otherwise cached entries from the previous zone may allow sends for players no longer nearby.", "clearPhaseCheckOnZoneChange")
    uiElements.clearPhaseCheckOnZoneChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearPhaseCheckOnZoneChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearPhaseCheckOnZoneChange = self:GetChecked()
    end)
    y5 = y5 - 25

    uiElements.clearAllowedSendersOnZoneChange = CreateCheckbox(tab5, "  Allowed Senders Cache", "Clear allowed senders cache on zone change", "clearAllowedSendersOnZoneChange")
    uiElements.clearAllowedSendersOnZoneChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearAllowedSendersOnZoneChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearAllowedSendersOnZoneChange = self:GetChecked()
    end)
    y5 = y5 - 25

    uiElements.clearInteractionOnZoneChange = CreateCheckbox(tab5, "  Interaction Cache", "Clear interaction cache on zone change", "clearInteractionOnZoneChange")
    uiElements.clearInteractionOnZoneChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearInteractionOnZoneChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearInteractionOnZoneChange = self:GetChecked()
    end)
    y5 = y5 - 25

    uiElements.clearSuppressionOnZoneChange = CreateCheckbox(tab5, "  Suppression Timers", "Clear notification suppression timers on zone change (resets per-player notification cooldowns)", "clearSuppressionOnZoneChange")
    uiElements.clearSuppressionOnZoneChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearSuppressionOnZoneChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearSuppressionOnZoneChange = self:GetChecked()
    end)
    y5 = y5 - 25

    uiElements.clearRecentBroadcastsOnZoneChange = CreateCheckbox(tab5, "  Recent Broadcasts Cache", "Clear recent broadcasts cache on zone change", "clearRecentBroadcastsOnZoneChange")
    uiElements.clearRecentBroadcastsOnZoneChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearRecentBroadcastsOnZoneChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearRecentBroadcastsOnZoneChange = self:GetChecked()
    end)
    y5 = y5 - 25

    uiElements.clearRecentScansOnZoneChange = CreateCheckbox(tab5, "  Recent Scans Cache", "Clear recent scans cache on zone change", "clearRecentScansOnZoneChange")
    uiElements.clearRecentScansOnZoneChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearRecentScansOnZoneChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearRecentScansOnZoneChange = self:GetChecked()
    end)
    y5 = y5 - 25

    uiElements.clearWhoZoneOnZoneChange = CreateCheckbox(tab5, "  WHO Zone Cache", "Clear WHO zone cache on zone change", "clearWhoZoneOnZoneChange")
    uiElements.clearWhoZoneOnZoneChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearWhoZoneOnZoneChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearWhoZoneOnZoneChange = self:GetChecked()
    end)
    y5 = y5 - 25

    uiElements.clearWhoNameOnZoneChange = CreateCheckbox(tab5, "  WHO Name Cache", "Clear WHO name cache on zone change", "clearWhoNameOnZoneChange")
    uiElements.clearWhoNameOnZoneChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearWhoNameOnZoneChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearWhoNameOnZoneChange = self:GetChecked()
    end)
    y5 = y5 - 25

    uiElements.clearSpvpOnZoneChange = CreateCheckbox(tab5, "  SPVP Verification Cache", "Clear SPVP verification cache on zone change", "clearSpvpOnZoneChange")
    uiElements.clearSpvpOnZoneChange:SetPoint("TOPLEFT", 40, y5)
    uiElements.clearSpvpOnZoneChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.clearSpvpOnZoneChange = self:GetChecked()
    end)
    y5 = y5 - 30

    CreateSectionHeader(tab5, "History Settings", y5)
    y5 = y5 - 40

    uiElements.trackHistory = CreateCheckbox(tab5, "Track History", "Enable tracking of session history (alerts, blocks, etc.)", "trackHistory")
    uiElements.trackHistory:SetPoint("TOPLEFT", 20, y5)
    uiElements.trackHistory:SetScript("OnClick", function(self)
        TRP3FW_Settings.trackHistory = self:GetChecked()
    end)
    y5 = y5 - 45

    uiElements.maxHistorySize = CreateEditBox(tab5, "History Size", "Maximum number of history entries to keep.", 80, "maxHistorySize")
    uiElements.maxHistorySize:SetPoint("TOPLEFT", 40, y5)

    local function saveMapScanMinInterval(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 then
            TRP3FW_Settings.mapScanMinInterval = value
            TRP3FW:Info("Map Scan Minimum Interval set to: " .. value .. " seconds")
        else
            self:SetText(tostring(TRP3FW_Settings.mapScanMinInterval or 60)) -- Revert to current setting
            TRP3FW:Warn("Invalid value for Map Scan Minimum Interval. Please enter a positive number.")
        end
        mapScanMinIntervalEnterPressed = false
    end
    uiElements.mapScanMinInterval:SetScript("OnEnterPressed", function(self)
        saveMapScanMinInterval(self)
        mapScanMinIntervalEnterPressed = true
    end)
    uiElements.mapScanMinInterval:SetScript("OnEditFocusLost", function(self)
        if not mapScanMinIntervalEnterPressed then
            saveMapScanMinInterval(self)
        end
    end)

    local function saveMaxHistorySize(self)
        local value = tonumber(self:GetText())
        if value and value >= 10 and value <= 1000 then
            TRP3FW_Settings.maxHistorySize = value
            TRP3FW:Info("History size limit set to "..value.." entries")
        else
            TRP3FW:Warn("Invalid value (must be 10-1000)")
            self:SetText(TRP3FW_Settings.maxHistorySize or 100)
        end
    end

    local maxHistorySizeEnterPressed = false
    uiElements.maxHistorySize:SetScript("OnEnterPressed", function(self)
        maxHistorySizeEnterPressed = true
        saveMaxHistorySize(self)
        self:ClearFocus()
        C_Timer.After(0, function() maxHistorySizeEnterPressed = false end)
    end)
    uiElements.maxHistorySize:SetScript("OnEditFocusLost", function(self)
        if not maxHistorySizeEnterPressed then
            saveMaxHistorySize(self)
        end
    end)
    y5 = y5 - 70

    CreateSectionHeader(tab5, "Rate Limiting & Performance", y5)
    y5 = y5 - 40

    -- Batch Phase Check
    uiElements.phaseCheckBatchMode = CreateCheckbox(tab5, "Batch Phase Checks", "Process multiple phase checks in a single batch to save tokens (40% reduction)", "phaseCheckBatchMode")
    uiElements.phaseCheckBatchMode:SetPoint("TOPLEFT", 20, y5)
    uiElements.phaseCheckBatchMode:SetScript("OnClick", function(self)
        TRP3FW_Settings.phaseCheckBatchMode = self:GetChecked()
    end)
    y5 = y5 - 40

    -- Batch Size Slider
    local batchSizeSlider = CreateFrame("Slider", "TRP3FW_BatchSizeSlider", tab5, "OptionsSliderTemplate")
    batchSizeSlider:SetPoint("TOPLEFT", 40, y5)
    batchSizeSlider:SetWidth(200)
    batchSizeSlider:SetMinMaxValues(2, 10)
    batchSizeSlider:SetValueStep(1)
    batchSizeSlider:SetObeyStepOnDrag(true)
    batchSizeSlider:SetValue(TRP3FW_Settings.phaseCheckBatchSize or 5)
    batchSizeSlider.settingKey = "phaseCheckBatchSize"
    batchSizeSlider.complexityLevel = 3
    table.insert(complexityWidgets, batchSizeSlider)
    batchSizeSlider.label = getglobal(batchSizeSlider:GetName() .. 'Text') -- Set label reference for dimming
    
    getglobal(batchSizeSlider:GetName() .. 'Low'):SetText('2')
    getglobal(batchSizeSlider:GetName() .. 'High'):SetText('10')
    getglobal(batchSizeSlider:GetName() .. 'Text'):SetText('Batch Size: ' .. (TRP3FW_Settings.phaseCheckBatchSize or 5))
    batchSizeSlider:SetScript("OnValueChanged", function(self, value)
        TRP3FW_Settings.phaseCheckBatchSize = math.floor(value)
        getglobal(self:GetName() .. 'Text'):SetText('Batch Size: ' .. math.floor(value))
    end)
    batchSizeSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Batch Size", 1, 1, 1)
        local tooltipText = AppendDefaultToTooltip("Maximum number of phase checks to process in a single batch.", batchSizeSlider.settingKey, batchSizeSlider.complexityLevel)
        GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    batchSizeSlider:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Batch Delay Slider
    local batchDelaySlider = CreateFrame("Slider", "TRP3FW_BatchDelaySlider", tab5, "OptionsSliderTemplate")
    batchDelaySlider:SetPoint("TOPLEFT", 280, y5)
    batchDelaySlider:SetWidth(200)
    batchDelaySlider:SetMinMaxValues(0.1, 2.0)
    batchDelaySlider:SetValueStep(0.1)
    batchDelaySlider:SetObeyStepOnDrag(true)
    batchDelaySlider:SetValue(TRP3FW_Settings.phaseCheckBatchDelay or 1.0)
    batchDelaySlider.settingKey = "phaseCheckBatchDelay" -- ADDED
    batchDelaySlider.complexityLevel = 3 -- ADDED
    table.insert(complexityWidgets, batchDelaySlider) -- ADDED
    batchDelaySlider.label = getglobal(batchDelaySlider:GetName() .. 'Text') -- ADDED
    
    getglobal(batchDelaySlider:GetName() .. 'Low'):SetText('0.1s')
    getglobal(batchDelaySlider:GetName() .. 'High'):SetText('2.0s')
    getglobal(batchDelaySlider:GetName() .. 'Text'):SetText(string.format('Batch Delay: %.1fs', TRP3FW_Settings.phaseCheckBatchDelay or 1.0))
    batchDelaySlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 10 + 0.5) / 10
        TRP3FW_Settings.phaseCheckBatchDelay = value
        getglobal(self:GetName() .. 'Text'):SetText(string.format('Batch Delay: %.1fs', value))
    end)
    batchDelaySlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Batch Delay", 1, 1, 1)
        local tooltipText = AppendDefaultToTooltip("Time to wait for additional phase checks before processing a batch (seconds).", batchDelaySlider.settingKey, batchDelaySlider.complexityLevel)
        GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    batchDelaySlider:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    y5 = y5 - 50

    -- Min Batch Slider
    local minBatchSlider = CreateFrame("Slider", "TRP3FW_MinBatchSlider", tab5, "OptionsSliderTemplate")
    minBatchSlider:SetPoint("TOPLEFT", 40, y5)
    minBatchSlider:SetWidth(200)
    minBatchSlider:SetMinMaxValues(2, 10)
    minBatchSlider:SetValueStep(1)
    minBatchSlider:SetObeyStepOnDrag(true)
    minBatchSlider:SetValue(TRP3FW_Settings.phaseCheckBatchMinSize or 3)
    minBatchSlider.settingKey = "phaseCheckBatchMinSize" -- ADDED
    minBatchSlider.complexityLevel = 3 -- ADDED
    table.insert(complexityWidgets, minBatchSlider) -- ADDED
    minBatchSlider.label = getglobal(minBatchSlider:GetName() .. 'Text') -- ADDED
    
    getglobal(minBatchSlider:GetName() .. 'Low'):SetText('2')
    getglobal(minBatchSlider:GetName() .. 'High'):SetText('10')
    getglobal(minBatchSlider:GetName() .. 'Text'):SetText('Min Batch Size: ' .. (TRP3FW_Settings.phaseCheckBatchMinSize or 3))
    minBatchSlider:SetScript("OnValueChanged", function(self, value)
        TRP3FW_Settings.phaseCheckBatchMinSize = math.floor(value)
        getglobal(self:GetName() .. 'Text'):SetText('Min Batch Size: ' .. math.floor(value))
    end)
    minBatchSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Min Batch Size", 1, 1, 1)
        local tooltipText = AppendDefaultToTooltip("Minimum number of queued checks required to trigger batch processing.", minBatchSlider.settingKey, minBatchSlider.complexityLevel)
        GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    minBatchSlider:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Inter-Target Delay Slider
    local interDelaySlider = CreateFrame("Slider", "TRP3FW_InterDelaySlider", tab5, "OptionsSliderTemplate")
    interDelaySlider:SetPoint("TOPLEFT", 280, y5)
    interDelaySlider:SetWidth(200)
    interDelaySlider:SetMinMaxValues(0.01, 0.2) -- Lower limit changed to 0.01 (10ms)
    interDelaySlider:SetValueStep(0.01)
    interDelaySlider:SetObeyStepOnDrag(true)
    local currentInter = TRP3FW_Settings.phaseCheckInterTargetDelay or 0.1
    interDelaySlider:SetValue(currentInter)
    interDelaySlider.settingKey = "phaseCheckInterTargetDelay" -- ADDED
    interDelaySlider.complexityLevel = 3 -- ADDED
    table.insert(complexityWidgets, interDelaySlider) -- ADDED
    interDelaySlider.label = getglobal(interDelaySlider:GetName() .. 'Text') -- ADDED
    
    getglobal(interDelaySlider:GetName() .. 'Low'):SetText('10ms') -- Updated label
    getglobal(interDelaySlider:GetName() .. 'High'):SetText('200ms')
    getglobal(interDelaySlider:GetName() .. 'Text'):SetText(string.format('Target Delay: %dms', currentInter * 1000))
    interDelaySlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 100 + 0.5) / 100
        TRP3FW_Settings.phaseCheckInterTargetDelay = value
        getglobal(self:GetName() .. 'Text'):SetText(string.format('Target Delay: %dms', value * 1000))
    end)
    interDelaySlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Inter-Target Delay", 1, 1, 1)
        local tooltipText = AppendDefaultToTooltip("Delay between targeting attempts in a batch to ensure client registers the change (seconds).", interDelaySlider.settingKey, interDelaySlider.complexityLevel)
        GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    interDelaySlider:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    y5 = y5 - 50

    -- Priority System
    local priorityLabel = tab5:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    priorityLabel:SetPoint("TOPLEFT", 20, y5)
    priorityLabel:SetText("Priority System & Reservations")
    y5 = y5 - 30

    -- Reserved Tokens
    local reservedSlider = CreateFrame("Slider", "TRP3FW_ReservedTokensSlider", tab5, "OptionsSliderTemplate")
    reservedSlider:SetPoint("TOPLEFT", 40, y5)
    reservedSlider:SetWidth(200)
    reservedSlider:SetMinMaxValues(0, 5)
    reservedSlider:SetValueStep(1)
    reservedSlider:SetObeyStepOnDrag(true)
    reservedSlider:SetValue(TRP3FW_Settings.privilegedReservedTokens or 2)
    reservedSlider.settingKey = "privilegedReservedTokens" -- ADDED
    reservedSlider.complexityLevel = 4 -- ADDED
    table.insert(complexityWidgets, reservedSlider) -- ADDED
    reservedSlider.label = getglobal(reservedSlider:GetName() .. 'Text') -- ADDED
    
    getglobal(reservedSlider:GetName() .. 'Low'):SetText('0')
    getglobal(reservedSlider:GetName() .. 'High'):SetText('5')
    getglobal(reservedSlider:GetName() .. 'Text'):SetText('Reserved Tokens: ' .. (TRP3FW_Settings.privilegedReservedTokens or 2))
    reservedSlider:SetScript("OnValueChanged", function(self, value)
        TRP3FW_Settings.privilegedReservedTokens = math.floor(value)
        getglobal(self:GetName() .. 'Text'):SetText('Reserved Tokens: ' .. math.floor(value))
        if TRP3FW.UpdateValidatedPrioritySettings then TRP3FW:UpdateValidatedPrioritySettings() end
    end)
    reservedSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Reserved Tokens", 1, 1, 1)
        local tooltipText = AppendDefaultToTooltip("Number of RunPrivileged tokens reserved for HIGH priority calls (e.g., phase restore, WHO name queries).", reservedSlider.settingKey, reservedSlider.complexityLevel)
        GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    reservedSlider:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Low Priority Threshold
    local lowThresholdSlider = CreateFrame("Slider", "TRP3FW_LowThresholdSlider", tab5, "OptionsSliderTemplate")
    lowThresholdSlider:SetPoint("TOPLEFT", 280, y5)
    lowThresholdSlider:SetWidth(200)
    lowThresholdSlider:SetMinMaxValues(2, 8)
    lowThresholdSlider:SetValueStep(1)
    lowThresholdSlider:SetObeyStepOnDrag(true)
    lowThresholdSlider:SetValue(TRP3FW_Settings.privilegedLowPriorityThreshold or 4)
    lowThresholdSlider.settingKey = "privilegedLowPriorityThreshold" -- ADDED
    lowThresholdSlider.complexityLevel = 4 -- ADDED
    table.insert(complexityWidgets, lowThresholdSlider) -- ADDED
    lowThresholdSlider.label = getglobal(lowThresholdSlider:GetName() .. 'Text') -- ADDED
    
    getglobal(lowThresholdSlider:GetName() .. 'Low'):SetText('2')
    getglobal(lowThresholdSlider:GetName() .. 'High'):SetText('8')
    getglobal(lowThresholdSlider:GetName() .. 'Text'):SetText('Low Prio Threshold: ' .. (TRP3FW_Settings.privilegedLowPriorityThreshold or 4))
    lowThresholdSlider:SetScript("OnValueChanged", function(self, value)
        TRP3FW_Settings.privilegedLowPriorityThreshold = math.floor(value)
        getglobal(self:GetName() .. 'Text'):SetText('Low Prio Threshold: ' .. math.floor(value))
        if TRP3FW.UpdateValidatedPrioritySettings then TRP3FW:UpdateValidatedPrioritySettings() end
    end)
    lowThresholdSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Low Priority Threshold", 1, 1, 1)
        local tooltipText = AppendDefaultToTooltip("Token count below which LOW priority calls (e.g., cache refreshes) are deferred.", lowThresholdSlider.settingKey, lowThresholdSlider.complexityLevel)
        GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    lowThresholdSlider:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    y5 = y5 - 50

    -- Token Refund
    uiElements.phaseCheckRefundOnNoChange = CreateCheckbox(tab5, "Refund Tokens on Failed Check", "Refund 1 token if phase check target doesn't exist. |cffff0000SECURITY WARNING: Doubles potential abuse rate.|r", "phaseCheckRefundOnNoChange")
    uiElements.phaseCheckRefundOnNoChange:SetPoint("TOPLEFT", 20, y5)
    uiElements.phaseCheckRefundOnNoChange:SetScript("OnClick", function(self)
        TRP3FW_Settings.phaseCheckRefundOnNoChange = self:GetChecked()
    end)
    y5 = y5 - 40

    y5 = y5 - 10
    CreateSectionHeader(tab5, "Redaction", y5)
    y5 = y5 - 35

    uiElements.redactEnabled = CreateCheckbox(tab5, "Enable Redaction", "Redact sensitive data (names, locations, network info) in notifications and debug output", "redactEnabled")
    uiElements.redactEnabled:SetPoint("TOPLEFT", 20, y5)
    uiElements.redactEnabled:SetScript("OnClick", function(self)
        TRP3FW_Settings.redactEnabled = self:GetChecked()
        local enabled = self:GetChecked()
        uiElements.redactNames:SetEnabled(enabled)
        uiElements.redactLocations:SetEnabled(enabled)
        uiElements.redactNetwork:SetEnabled(enabled)
        if uiElements.redactSPVP then uiElements.redactSPVP:SetEnabled(enabled) end
        local alpha = enabled and 1 or 0.5
        uiElements.redactNames:SetAlpha(alpha)
        uiElements.redactLocations:SetAlpha(alpha)
        uiElements.redactNetwork:SetAlpha(alpha)
        if uiElements.redactSPVP then uiElements.redactSPVP:SetAlpha(alpha) end
    end)
    y5 = y5 - 30

    uiElements.redactNames = CreateCheckbox(tab5, "Redact Names/IDs", "Mask character identifiers (Player-XXXX-YYYY, merged realms)", "redactNames")
    uiElements.redactNames:SetPoint("TOPLEFT", 40, y5)
    uiElements.redactNames:SetScript("OnClick", function(self)
        TRP3FW_Settings.redactNames = self:GetChecked()
    end)
    y5 = y5 - 30

    uiElements.redactLocations = CreateCheckbox(tab5, "Redact Locations", "Mask zone/map/phase values in output", "redactLocations")
    uiElements.redactLocations:SetPoint("TOPLEFT", 40, y5)
    uiElements.redactLocations:SetScript("OnClick", function(self)
        TRP3FW_Settings.redactLocations = self:GetChecked()
    end)
    y5 = y5 - 30

    uiElements.redactNetwork = CreateCheckbox(tab5, "Redact Network Info", "Mask IPs, emails, URLs", "redactNetwork")
    uiElements.redactNetwork:SetPoint("TOPLEFT", 40, y5)
    uiElements.redactNetwork:SetScript("OnClick", function(self)
        TRP3FW_Settings.redactNetwork = self:GetChecked()
    end)
    y5 = y5 - 30

    uiElements.redactSPVP = CreateCheckbox(tab5, "Redact SPVP Salt & Keys", "Mask SPVP phase salts and cryptographic keys in debug logs", "redactSPVP")
    uiElements.redactSPVP:SetPoint("TOPLEFT", 40, y5)
    uiElements.redactSPVP:SetScript("OnClick", function(self)
        TRP3FW_Settings.redactSPVP = self:GetChecked()
    end)
    y5 = y5 - 40

    CreateSectionHeader(tab5, "Debug Settings", y5)
    y5 = y5 - 40

    uiElements.debug = CreateCheckbox(tab5, "Enable Debug Mode", "Show debug messages", "debug")
    uiElements.debug:SetPoint("TOPLEFT", 20, y5)
    uiElements.debug:SetScript("OnClick", function(self)
        TRP3FW_Settings.debug = self:GetChecked()
        -- Enable/disable all debug options
        local enabled = self:GetChecked()
        if enabled then
            uiElements.debugTimestamp:Enable()
            uiElements.debugChannel:Enable()
            uiElements.debugWhisper:Enable()
            uiElements.debugWho:Enable()
            uiElements.debugPhase:Enable()
            uiElements.debugCleanName:Enable()
            uiElements.debugLocation:Enable()
            uiElements.debugDecision:Enable()
            uiElements.debugHooks:Enable()
            uiElements.debugCache:Enable()
            uiElements.debugSend:Enable()
            uiElements.debugUI:Enable()
            uiElements.debugUtils:Enable()
            uiElements.debugSecurity:Enable()
            uiElements.debugGhost:Enable()
            uiElements.debugSPVP:Enable()
        else
            uiElements.debugTimestamp:Disable()
            uiElements.debugChannel:Disable()
            uiElements.debugWhisper:Disable()
            uiElements.debugWho:Disable()
            uiElements.debugPhase:Disable()
            uiElements.debugCleanName:Disable()
            uiElements.debugLocation:Disable()
            uiElements.debugDecision:Disable()
            uiElements.debugHooks:Disable()
            uiElements.debugCache:Disable()
            uiElements.debugSend:Disable()
            uiElements.debugUI:Disable()
            uiElements.debugUtils:Disable()
            uiElements.debugSecurity:Disable()
            uiElements.debugGhost:Disable()
            uiElements.debugSPVP:Disable()
        end
    end)
    y5 = y5 - 30

    uiElements.debugTimestamp = CreateCheckbox(tab5, "Show Timestamps", "Show timestamps in debug messages", "debugTimestamp")
    uiElements.debugTimestamp:SetPoint("TOPLEFT", 40, y5)
    uiElements.debugTimestamp:SetScript("OnClick", function(self)
        TRP3FW_Settings.debugTimestamp = self:GetChecked()
    end)
    y5 = y5 - 30

    y5 = y5 - 10  -- Extra spacing before new section
    CreateSectionHeader(tab5, "Debug Output", y5)
    y5 = y5 - 45

    -- Debug output dropdown
    uiElements.debugOutputDropdown, uiElements.debugOutputLabel = CreateDropdown(tab5, "Debug Output", "Where to display debug messages", 200, "debugOutput")
    uiElements.debugOutputDropdown:SetPoint("TOPLEFT", 20, y5)

    UIDropDownMenu_Initialize(uiElements.debugOutputDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        -- Chat
        info.text = "Chat"
        info.value = "chat"
        info.tooltipTitle = "Chat"
        info.tooltipText = "Show debug messages in chat window only"
        info.func = function()
            TRP3FW_Settings.debugOutputChat = true
            TRP3FW_Settings.debugOutputWindow = false
            TRP3FW_Settings.debugOutputBoth = false
            UIDropDownMenu_SetText(uiElements.debugOutputDropdown, "Chat")
        end
        UIDropDownMenu_AddButton(info)

        -- Window
        info.text = "Window"
        info.value = "window"
        info.tooltipTitle = "Window"
        info.tooltipText = "Show debug messages in dedicated window only"
        info.func = function()
            TRP3FW_Settings.debugOutputChat = false
            TRP3FW_Settings.debugOutputWindow = true
            TRP3FW_Settings.debugOutputBoth = false
            UIDropDownMenu_SetText(uiElements.debugOutputDropdown, "Window")
            -- Auto-show window
            if TRP3FW.ShowDebugWindow then
                TRP3FW:ShowDebugWindow()
            end
        end
        UIDropDownMenu_AddButton(info)

        -- Both
        info.text = "Both"
        info.value = "both"
        info.tooltipTitle = "Both"
        info.tooltipText = "Show debug messages in both chat and window"
        info.func = function()
            TRP3FW_Settings.debugOutputChat = false
            TRP3FW_Settings.debugOutputWindow = false
            TRP3FW_Settings.debugOutputBoth = true
            UIDropDownMenu_SetText(uiElements.debugOutputDropdown, "Both")
            -- Auto-show window
            if TRP3FW.ShowDebugWindow then
                TRP3FW:ShowDebugWindow()
            end
        end
        UIDropDownMenu_AddButton(info)
    end)
    y5 = y5 - 50

    -- Debug Window toggle button
    local debugWindowButton = CreateFrame("Button", nil, tab5, "UIPanelButtonTemplate")
    debugWindowButton:SetSize(150, 22)
    debugWindowButton:SetPoint("TOPLEFT", 40, y5)  -- Indent to show it's related to dropdown
    debugWindowButton:SetText("Toggle Debug Window")
    debugWindowButton:SetScript("OnClick", function()
        if TRP3FW.ToggleDebugWindow then
            TRP3FW:ToggleDebugWindow()
        else
            TRP3FW:Warn("Debug window not loaded yet")
        end
    end)
    y5 = y5 - 50

    y5 = y5 - 10  -- Extra spacing before new section
    CreateSectionHeader(tab5, "Debug Filters", y5)
    y5 = y5 - 35

    uiElements.debugChannel = CreateCheckbox(tab5, "Channel Messages", "Show channel debug messages", "debugChannel")
    uiElements.debugChannel:SetPoint("TOPLEFT", 40, y5)  -- Indent to show it's a sub-option
    uiElements.debugChannel:SetScript("OnClick", function(self)
        TRP3FW_Settings.debugChannel = self:GetChecked()
    end)
    y5 = y5 - 30

    uiElements.debugWhisper = CreateCheckbox(tab5, "Whisper Messages", "Show whisper debug messages", "debugWhisper")
    uiElements.debugWhisper:SetPoint("TOPLEFT", 40, y5)  -- Indent to show it's a sub-option
    uiElements.debugWhisper:SetScript("OnClick", function(self)
        TRP3FW_Settings.debugWhisper = self:GetChecked()
    end)
    y5 = y5 - 30

    uiElements.debugWho = CreateCheckbox(tab5, "WHO Query Messages", "Show WHO query debug messages", "debugWho")
    uiElements.debugWho:SetPoint("TOPLEFT", 40, y5)  -- Indent to show it's a sub-option
    uiElements.debugWho:SetScript("OnClick", function(self)
        TRP3FW_Settings.debugWho = self:GetChecked()
    end)
    y5 = y5 - 30

    uiElements.debugPhase = CreateCheckbox(tab5, "Phase Check Messages", "Show phase check debug messages", "debugPhase")
    uiElements.debugPhase:SetPoint("TOPLEFT", 40, y5)  -- Indent to show it's a sub-option
    uiElements.debugPhase:SetScript("OnClick", function(self)
        TRP3FW_Settings.debugPhase = self:GetChecked()
    end)
    y5 = y5 - 30

    uiElements.debugCleanName = CreateCheckbox(tab5, "CleanPlayerName Messages", "Show CleanPlayerName debug messages", "debugCleanName")
    uiElements.debugCleanName:SetPoint("TOPLEFT", 40, y5)  -- Indent to show it's a sub-option
    uiElements.debugCleanName:SetScript("OnClick", function(self)
        TRP3FW_Settings.debugCleanName = self:GetChecked()
    end)
    y5 = y5 - 30

    uiElements.debugLocation = CreateCheckbox(tab5, "Location Check Messages", "Show location checking debug messages", "debugLocation")
    uiElements.debugLocation:SetPoint("TOPLEFT", 40, y5)  -- Indent to show it's a sub-option
    uiElements.debugLocation:SetScript("OnClick", function(self)
        TRP3FW_Settings.debugLocation = self:GetChecked()
    end)
    y5 = y5 - 30

    uiElements.debugDecision = CreateCheckbox(tab5, "Decision Logic Messages", "Show allow/block decision debug messages", "debugDecision")
    uiElements.debugDecision:SetPoint("TOPLEFT", 40, y5)  -- Indent to show it's a sub-option
    uiElements.debugDecision:SetScript("OnClick", function(self)
        TRP3FW_Settings.debugDecision = self:GetChecked()
    end)
    y5 = y5 - 30

    uiElements.debugHooks = CreateCheckbox(tab5, "Hook Messages", "Show addon hook debug messages", "debugHooks")
    uiElements.debugHooks:SetPoint("TOPLEFT", 40, y5)  -- Indent to show it's a sub-option
    uiElements.debugHooks:SetScript("OnClick", function(self)
        TRP3FW_Settings.debugHooks = self:GetChecked()
    end)
    y5 = y5 - 30

    uiElements.debugCache = CreateCheckbox(tab5, "Cache Messages", "Show cache management debug messages", "debugCache")
    uiElements.debugCache:SetPoint("TOPLEFT", 40, y5)  -- Indent to show it's a sub-option
    uiElements.debugCache:SetScript("OnClick", function(self)
        TRP3FW_Settings.debugCache = self:GetChecked()
    end)
    y5 = y5 - 30
    uiElements.debugSend = CreateCheckbox(tab5, "Send Cache Messages", "Show send cache debug messages", "debugSend")
    uiElements.debugSend:SetPoint("TOPLEFT", 40, y5)  -- Indent to show it's a sub-option
    uiElements.debugSend:SetScript("OnClick", function(self)
        TRP3FW_Settings.debugSend = self:GetChecked()
    end)
    y5 = y5 - 30

    uiElements.debugUI = CreateCheckbox(tab5, "UI Messages", "Show UI debug messages", "debugUI")
    uiElements.debugUI:SetPoint("TOPLEFT", 40, y5)  -- Indent to show it's a sub-option
    uiElements.debugUI:SetScript("OnClick", function(self)
        TRP3FW_Settings.debugUI = self:GetChecked()
    end)
    y5 = y5 - 30

    uiElements.debugUtils = CreateCheckbox(tab5, "Utility Messages", "Show utility function debug messages", "debugUtils")
    uiElements.debugUtils:SetPoint("TOPLEFT", 40, y5)  -- Indent to show it's a sub-option
    uiElements.debugUtils:SetScript("OnClick", function(self)
        TRP3FW_Settings.debugUtils = self:GetChecked()
    end)
    y5 = y5 - 30

    uiElements.debugSecurity = CreateCheckbox(tab5, "Security Messages", "Show security enforcement debug messages (sanitization, cache limits, spoofing detection)", "debugSecurity")
    uiElements.debugSecurity:SetPoint("TOPLEFT", 40, y5)  -- Indent to show it's a sub-option
    uiElements.debugSecurity:SetScript("OnClick", function(self)
        TRP3FW_Settings.debugSecurity = self:GetChecked()
    end)
    y5 = y5 - 30

    uiElements.debugGhost = CreateCheckbox(tab5, "Ghost Mode Messages", "Show ghost mode execution flow and exchange hook calls", "debugGhost")
    uiElements.debugGhost:SetPoint("TOPLEFT", 40, y5)  -- Indent to show it's a sub-option
    uiElements.debugGhost:SetScript("OnClick", function(self)
        TRP3FW_Settings.debugGhost = self:GetChecked()
    end)
    y5 = y5 - 30

    uiElements.debugSPVP = CreateCheckbox(tab5, "SPVP Messages", "Show Secure Phase Verification Protocol debug messages", "debugSPVP")
    uiElements.debugSPVP:SetPoint("TOPLEFT", 40, y5)  -- Indent to show it's a sub-option
    uiElements.debugSPVP:SetScript("OnClick", function(self)
        TRP3FW_Settings.debugSPVP = self:GetChecked()
    end)

    -- Add bottom buttons
    local closeButton = CreateFrame("Button", nil, settingsFrame, "GameMenuButtonTemplate")
    closeButton:SetSize(100, 25)
    closeButton:SetPoint("BOTTOMRIGHT", -10, 10)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        settingsFrame:Hide()
    end)

    local resetButton = CreateFrame("Button", nil, settingsFrame, "GameMenuButtonTemplate")
    resetButton:SetSize(100, 25)
    resetButton:SetPoint("RIGHT", closeButton, "LEFT", -10, 0)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", function()
        StaticPopup_Show("TRP3FW_RESET_CONFIRM")
    end)

    -- Show frame when opened
    settingsFrame:SetScript("OnShow", function()
        RequestRefreshUI()
        SelectTab(1)
        StartStatusUpdates() -- Start periodic updates for Status tab
    end)

    -- Stop updates when frame hidden
    settingsFrame:SetScript("OnHide", function()
        if statusUpdateTimer then
            statusUpdateTimer:Cancel()
            statusUpdateTimer = nil
        end
    end)

    -- Register slash command to open UI
    SLASH_TRP3FWUI1 = "/trp3fwui"
    SLASH_TRP3FWUI2 = "/trp3fwconfig"
    SlashCmdList.TRP3FWUI = function()
        if settingsFrame:IsVisible() then
            settingsFrame:Hide()
        else
            settingsFrame:Show()
        end
    end

    -- Create minimap button
    TRP3FW:Debug("Calling CreateMinimapButton...", "ui")
    local success, err = pcall(CreateMinimapButton)
    if not success then
        print("|cffff0000TRP3FW Error:|r Failed to create minimap button: "..tostring(err))
    end

    TRP3FW:Debug("UI initialization complete!", "ui")
    TRP3FW:Info("TRP3 Firewall UI loaded. Use /trp3fwui, /trp3fwconfig, or minimap button to open settings")
end

-- Function to show/hide minimap button
function TRP3FW:ToggleMinimapButton()
    if not minimapButton then return end

    TRP3FW_MinimapSettings.hide = not TRP3FW_MinimapSettings.hide
    if TRP3FW_MinimapSettings.hide then
        minimapButton:Hide()
        self:Info("Minimap button hidden")
    else
        minimapButton:Show()
        self:Info("Minimap button shown")
    end
end

-- ===================== Welcome Wizard =====================

local welcomeFrame

function TRP3FW:ShowWelcomeWizard()
    -- Only show if not configured yet
    if TRP3FW_Settings.complexitySetupDone then return end
    
    if welcomeFrame then 
        welcomeFrame:Show()
        return 
    end

    welcomeFrame = CreateFrame("Frame", "TRP3FW_WelcomeWizard", UIParent, "BasicFrameTemplateWithInset")
    welcomeFrame:SetSize(450, 420)
    welcomeFrame:SetPoint("CENTER")
    welcomeFrame:SetFrameStrata("DIALOG")
    welcomeFrame:EnableMouse(true)
    welcomeFrame:SetMovable(true)
    welcomeFrame:RegisterForDrag("LeftButton")
    welcomeFrame:SetScript("OnDragStart", welcomeFrame.StartMoving)
    welcomeFrame:SetScript("OnDragStop", welcomeFrame.StopMovingOrSizing)

    welcomeFrame.title = welcomeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    welcomeFrame.title:SetPoint("TOP", 0, -10)
    welcomeFrame.title:SetText("Welcome to TRP3 Firewall")

    local text = welcomeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 20, -50)
    text:SetPoint("TOPRIGHT", -20, -50)
    text:SetJustifyH("CENTER")
    text:SetText("TRP3FW 2.0 introduces new complexity levels to declutter settings.\n\nPlease select the level of settings you would like available.\n(You can change this later in the 'Filters and Addons' tab)")
    
    local recText = welcomeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    recText:SetPoint("TOP", text, "BOTTOM", 0, -15)
    recText:SetText("|cff00ff00Recommended for most people: Intermediate|r")

    local function SelectLevel(level)
        TRP3FW_Settings.uiComplexityLevel = level
        TRP3FW_Settings.complexitySetupDone = true
        RequestRefreshUI()
        
        -- Update the dropdown if settings window is open
        if _G["TRP3FW_ComplexityDropdown"] then
             UIDropDownMenu_SetText(_G["TRP3FW_ComplexityDropdown"], COMPLEXITY_NAMES[level])
        end
        
        welcomeFrame:Hide()
        TRP3FW:Info("Settings complexity set to: " .. COMPLEXITY_NAMES[level])
    end

    local btnY = -140
    local btnHeight = 50
    local btnWidth = 380
    local gap = 10

    local function CreateWizardButton(level, label, desc)
        local btn = CreateFrame("Button", nil, welcomeFrame, "UIPanelButtonTemplate")
        btn:SetSize(btnWidth, btnHeight)
        btn:SetPoint("TOP", 0, btnY)
        
        -- Main Label
        local l = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        l:SetPoint("TOPLEFT", 15, -10)
        l:SetText(label)
        
        -- Description
        local d = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        d:SetPoint("TOPLEFT", 15, -28)
        d:SetText(desc)
        d:SetTextColor(0.8, 0.8, 0.8)
        d:SetJustifyH("LEFT")
        
        btn:SetScript("OnClick", function() SelectLevel(level) end)
        
        btnY = btnY - btnHeight - gap
        return btn
    end

    CreateWizardButton(1, "Basic", "Essential settings only. Simple and effective.")
    CreateWizardButton(2, "Intermediate (Recommended)", "Standard customization. Good balance.")
    CreateWizardButton(3, "Advanced", "Full control over caching, specific alerts, and overrides.")
    CreateWizardButton(4, "Everything", "Developer/Debug options exposed. Maximum complexity.")
    
    -- Force show on create
    welcomeFrame:Show()
end
