-- ui/tabs/Notifications.lua
-- Notifications settings tab for TRP3FW

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

local function CreateNotificationsTab(container)
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()
    
    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 1200) -- Increased height to accommodate missing section
    local uiElements = TabManager:GetUI()
    local y = -10

    TabManager:CreateSectionHeader(content, "Notification Settings", y)
    y = y - 40

    uiElements.notifyEnabled = TabManager:CreateCheckbox(content, "Enable Notifications", "Master toggle for all notifications", "notifyEnabled")
    uiElements.notifyEnabled:SetPoint("TOPLEFT", 20, y)
    uiElements.notifyEnabled:SetScript("OnClick", function(self)
        TRP3FW.Prefs.notifyEnabled = self:GetChecked()
    end)
    y = y - 40

    -- Granular notification type controls
    uiElements.notifyOnAllow = TabManager:CreateCheckbox(content, "Notify on Allow", "Show notifications when profiles are sent normally (allowed)", "notifyOnAllow")
    uiElements.notifyOnAllow:SetPoint("TOPLEFT", 20, y)
    uiElements.notifyOnAllow:SetScript("OnClick", function(self)
        TRP3FW.Prefs.notifyOnAllow = self:GetChecked()
    end)
    y = y - 30

    uiElements.notifyOnStartPhaseBlock = TabManager:CreateCheckbox(content, "Notify on Start Phase Block", "Show notifications when blocking in start phase (169)", "notifyOnStartPhaseBlock")
    uiElements.notifyOnStartPhaseBlock:SetPoint("TOPLEFT", 20, y)
    uiElements.notifyOnStartPhaseBlock:SetScript("OnClick", function(self)
        TRP3FW.Prefs.notifyOnStartPhaseBlock = self:GetChecked()
    end)
    y = y - 30

    y = y - 10
    local notifyHelpText = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    notifyHelpText:SetPoint("TOPLEFT", 20, y)
    notifyHelpText:SetText("|cffaaaaaa(Broadcast/Whisper toggles only affect 'Allow' notifications)|r")
    y = y - 25

    uiElements.notifyOnBroadcast = TabManager:CreateCheckbox(content, "Notify on Broadcast", "Show notifications for map scan broadcasts (only affects Allow notifications)", "notifyOnBroadcast")
    uiElements.notifyOnBroadcast:SetPoint("TOPLEFT", 20, y)
    uiElements.notifyOnBroadcast:SetScript("OnClick", function(self)
        TRP3FW.Prefs.notifyOnBroadcast = self:GetChecked()
    end)
    y = y - 30

    uiElements.notifyOnWhisper = TabManager:CreateCheckbox(content, "Notify on Whisper", "Show notifications for whisper exchanges (only affects Allow notifications)", "notifyOnWhisper")
    uiElements.notifyOnWhisper:SetPoint("TOPLEFT", 20, y)
    uiElements.notifyOnWhisper:SetScript("OnClick", function(self)
        TRP3FW.Prefs.notifyOnWhisper = self:GetChecked()
    end)
    y = y - 40

    -- Scan Reply Group
    local scanGroup = CreateFrame("Frame", "TRP3FW_NotificationsScanGroup", content, "BackdropTemplate")
    scanGroup:SetPoint("TOPLEFT", 10, y)
    scanGroup:SetSize(560, 480) -- Increased height for whitelist
    scanGroup:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    scanGroup:SetBackdropColor(0, 0, 0, 0.2)
    scanGroup:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)

    local sgTitle = scanGroup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sgTitle:SetPoint("TOPLEFT", 15, -10); sgTitle:SetText("Map Scan Reply Controls"); sgTitle:SetTextColor(0.7, 0.7, 0.7)

    local scanY = y - 35
    uiElements.notifyOnScanResponse = TabManager:CreateCheckbox(content, "Show Scan Reply Notifications", "Controls notifications for scan replies.", "notifyOnScanResponse")
    uiElements.notifyOnScanResponse:SetPoint("TOPLEFT", 30, scanY)
    uiElements.notifyOnScanResponse:SetScript("OnClick", function(self) TRP3FW.Prefs.notifyOnScanResponse = self:GetChecked(); TRP3FW:RefreshUI() end)
    scanY = scanY - 30

    uiElements.notifyOnScanAllow = TabManager:CreateCheckbox(content, "Notify on Scan Allow", "Show notifications when scan replies are allowed.", "notifyOnScanAllow")
    uiElements.notifyOnScanAllow:SetPoint("TOPLEFT", 50, scanY)
    uiElements.notifyOnScanAllow:SetScript("OnClick", function(self) TRP3FW.Prefs.notifyOnScanAllow = self:GetChecked() end)
    scanY = scanY - 45

    local function createScanMode(label, key, yOff)
        local d, l = TabManager:CreateDropdown(content, label, "Behavior for scan replies.", 200, key)
        d:SetPoint("TOPLEFT", 30, yOff)
        UIDropDownMenu_Initialize(d, function(self, level)
            local m = { {text="Off", val="off"}, {text="Statistics Only", val="statistics"}, {text="Alert (send anyway)", val="alert"}, {text="Block (silent)", val="block"}, {text="Alert + Block", val="alert_block"} }
            for _, item in ipairs(m) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.text; info.func = function() TRP3FW.Prefs[key] = item.val; UIDropDownMenu_SetText(d, item.text); TRP3FW:RefreshUI() end
                info.checked = (TRP3FW.Prefs[key] == item.val); UIDropDownMenu_AddButton(info)
            end
        end)
        return d
    end
    
    uiElements.scanResponsePhaseModeDropdown = createScanMode("Different-Phase Behavior", "scanResponsePhaseMode", scanY)
    scanY = scanY - 50
    uiElements.scanResponseMapModeDropdown = createScanMode("Different-Map Behavior", "scanResponseMapMode", scanY)
    scanY = scanY - 50

    uiElements.scanResponseRequireNonce = TabManager:CreateCheckbox(content, "Require Nonce on Scan Replies", "When enabled, ignore map scan replies that do not include the issued nonce token (older scanners may be ignored).", "scanResponseRequireNonce")
    uiElements.scanResponseRequireNonce:SetPoint("TOPLEFT", 30, scanY)
    uiElements.scanResponseRequireNonce:SetScript("OnClick", function(self)
        TRP3FW.Prefs.scanResponseRequireNonce = self:GetChecked()
    end)
    scanY = scanY - 30
    
    uiElements.scanResponseCacheEnabled = TabManager:CreateCheckbox(content, "Cache Scan Requesters", "When replying to map scans, cache WHO results (if a WHO query ran). Does not add to interaction/send caches.", "scanResponseCacheEnabled")
    uiElements.scanResponseCacheEnabled:SetPoint("TOPLEFT", 30, scanY)
    uiElements.scanResponseCacheEnabled:SetScript("OnClick", function(self)
        TRP3FW.Prefs.scanResponseCacheEnabled = self:GetChecked()
    end)
    scanY = scanY - 30

    uiElements.scanResponseAllowCacheBypass = TabManager:CreateCheckbox(content, "Bypass with Existing Caches", "If scan requester is already in allowed or interaction cache (unrefreshed), skip the WHO gate and reply immediately.", "scanResponseAllowCacheBypass")
    uiElements.scanResponseAllowCacheBypass:SetPoint("TOPLEFT", 30, scanY)
    uiElements.scanResponseAllowCacheBypass:SetScript("OnClick", function(self)
        TRP3FW.Prefs.scanResponseAllowCacheBypass = self:GetChecked()
    end)
    scanY = scanY - 30

    uiElements.scanResponseAllowGroupBypass = TabManager:CreateCheckbox(content, "Always Allow Party/Raid", "If the scan requester is in your party or raid, always reply (skips phase/map/WHO gates).", "scanResponseAllowGroupBypass")
    uiElements.scanResponseAllowGroupBypass:SetPoint("TOPLEFT", 30, scanY)
    uiElements.scanResponseAllowGroupBypass:SetScript("OnClick", function(self)
        TRP3FW.Prefs.scanResponseAllowGroupBypass = self:GetChecked()
    end)
    scanY = scanY - 30

    -- Missing Whitelist Section Logic Restored
    uiElements.scanResponseWhitelistEnabled = TabManager:CreateCheckbox(content, "Enable Scan Reply Whitelist", "If disabled, names in the whitelist are ignored (no bypass).", "scanResponseWhitelistEnabled")
    uiElements.scanResponseWhitelistEnabled:SetPoint("TOPLEFT", 30, scanY)
    uiElements.scanResponseWhitelistEnabled:SetScript("OnClick", function(self)
        TRP3FW.Prefs.scanResponseWhitelistEnabled = self:GetChecked()
        TRP3FW:RefreshUI()
    end)
    scanY = scanY - 30

    local scanWhitelistLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scanWhitelistLabel:SetPoint("TOPLEFT", 30, scanY)
    scanWhitelistLabel:SetText("Scan Reply Whitelist (one name per line):")
    scanY = scanY - 20

    local scanWhitelistScroll = CreateFrame("ScrollFrame", "TRP3FW_NotificationsScanWhitelistScroll", content, "UIPanelScrollFrameTemplate")
    scanWhitelistScroll:SetPoint("TOPLEFT", 30, scanY)
    scanWhitelistScroll:SetSize(480, 80)
    uiElements.scanResponseWhitelistScroll = scanWhitelistScroll

    local scanWhitelistEdit = CreateFrame("EditBox", "TRP3FW_NotificationsScanWhitelistEdit", scanWhitelistScroll)
    scanWhitelistEdit:SetMultiLine(true)
    scanWhitelistEdit:SetFontObject(ChatFontNormal)
    scanWhitelistEdit:SetWidth(460)
    scanWhitelistEdit:SetHeight(80)
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

    scanWhitelistEdit:SetText(TRP3FW.Prefs.scanResponseWhitelist or "")
    scanWhitelistEdit:SetScript("OnTextChanged", function(self)
        TRP3FW.Prefs.scanResponseWhitelist = self:GetText()
    end)
    scanWhitelistEdit:SetScript("OnEditFocusLost", function(self)
        local cleaned = sanitizeScanWhitelist(self:GetText())
        if cleaned ~= self:GetText() then
            self:SetText(cleaned)
        end
        TRP3FW.Prefs.scanResponseWhitelist = cleaned
    end)
    scanWhitelistScroll:SetScrollChild(scanWhitelistEdit)

    local scanWhitelistBG = CreateFrame("Frame", nil, content, "BackdropTemplate")
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
    scanY = scanY - 100

    -- Adjust the scan group background height dynamically
    scanGroup:SetPoint("BOTTOMRIGHT", content, "TOPLEFT", 570, scanY + 10)

    -- Advance Y past group
    y = scanY - 20

    -- Current mode summary
    local summaryLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    summaryLabel:SetPoint("TOPLEFT", 20, y); summaryLabel:SetText("Current Modes Summary:")
    y = y - 30
    uiElements.notificationModeSummaryNotify = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    uiElements.notificationModeSummaryNotify:SetPoint("TOPLEFT", 30, y); uiElements.notificationModeSummaryNotify:SetWidth(520); uiElements.notificationModeSummaryNotify:SetJustifyH("LEFT")
    y = y - 50

    TabManager:CreateSectionHeader(content, "Notification Appearance", y)
    y = y - 40

    uiElements.showInChat = TabManager:CreateCheckbox(content, "Show in Chat", "Display firewall alerts in the main chat window", "showInChat")
    uiElements.showInChat:SetPoint("TOPLEFT", 20, y)
    uiElements.showInChat:SetScript("OnClick", function(self)
        TRP3FW.Prefs.showInChat = self:GetChecked()
    end)
    y = y - 30

    uiElements.showGhostNotifications = TabManager:CreateCheckbox(content, "Show Ghosting Alerts", "Display chat messages when a blank profile is sent via Ghost mode", "showGhostNotifications")
    uiElements.showGhostNotifications:SetPoint("TOPLEFT", 20, y)
    uiElements.showGhostNotifications:SetScript("OnClick", function(self)
        TRP3FW.Prefs.showGhostNotifications = self:GetChecked()
    end)
    y = y - 30

    uiElements.showOnScreen = TabManager:CreateCheckbox(content, "Show On Screen", "Display firewall alerts as floating text on the screen", "showOnScreen")
    uiElements.showOnScreen:SetPoint("TOPLEFT", 20, y)
    uiElements.showOnScreen:SetScript("OnClick", function(self)
        TRP3FW.Prefs.showOnScreen = self:GetChecked()
    end)
    y = y - 30

    uiElements.playSound = TabManager:CreateCheckbox(content, "Play Sound", "Play a subtle sound when a firewall alert occurs", "playSound")
    uiElements.playSound:SetPoint("TOPLEFT", 20, y)
    uiElements.playSound:SetScript("OnClick", function(self)
        TRP3FW.Prefs.playSound = self:GetChecked()
    end)
    y = y - 30

    uiElements.showAddonSource = TabManager:CreateCheckbox(content, "Show Addon Source", "Include the name of the requesting addon (TRP3, MRP, XRP) in notifications", "showAddonSource")
    uiElements.showAddonSource:SetPoint("TOPLEFT", 20, y)
    uiElements.showAddonSource:SetScript("OnClick", function(self)
        TRP3FW.Prefs.showAddonSource = self:GetChecked()
    end)
    y = y - 30

    uiElements.showCacheInfo = TabManager:CreateCheckbox(content, "Show Cache Hit/Miss Info", "Append cache status (HIT/MISS) to Allow notifications", "showCacheInfo")
    uiElements.showCacheInfo:SetPoint("TOPLEFT", 20, y)
    uiElements.showCacheInfo:SetScript("OnClick", function(self)
        TRP3FW.Prefs.showCacheInfo = self:GetChecked()
    end)
    y = y - 30

    uiElements.showCheckResults = TabManager:CreateCheckbox(content, "Show Check Detail (Pass/Fail)", "Append phase and map check results/methods to notifications", "showCheckResults")
    uiElements.showCheckResults:SetPoint("TOPLEFT", 20, y)
    uiElements.showCheckResults:SetScript("OnClick", function(self)
        TRP3FW.Prefs.showCheckResults = self:GetChecked()
    end)
    y = y - 45

    TabManager:CreateSectionHeader(content, "Suppression", y)
    y = y - 45

    uiElements.suppressionTime = TabManager:CreateEditBox(content, "Duration (s)", "How many seconds to suppress repeated notifications from the same player.", 80, "suppressionTime")
    uiElements.suppressionTime:SetPoint("TOPLEFT", 20, y)
    
    local function saveSuppressionTime(self)
        local val = tonumber(self:GetText())
        if val and val >= 0 then TRP3FW.Prefs.suppressionTime = val else self:SetText(TRP3FW.Prefs.suppressionTime or 30) end
    end
    
    uiElements.suppressionTime:SetScript("OnEnterPressed", function(self) saveSuppressionTime(self); self:ClearFocus() end)
    uiElements.suppressionTime:SetScript("OnEditFocusLost", saveSuppressionTime)
    
    y = y - 40
    uiElements.refreshSuppression = TabManager:CreateCheckbox(content, "Extend on Activity", "Refresh the suppression window when new profile sends are detected from the same player (sliding window).", "refreshSuppression")
    uiElements.refreshSuppression:SetPoint("TOPLEFT", 20, y)
    uiElements.refreshSuppression:SetScript("OnClick", function(self)
        TRP3FW.Prefs.refreshSuppression = self:GetChecked()
    end)

    local whitelistSectionTop = y - 40
    TabManager:CreateSectionHeader(content, "Whitelist Bypass (Advanced)", whitelistSectionTop)
    y = whitelistSectionTop - 35

    local whitelistInfo = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    whitelistInfo:SetPoint("TOPLEFT", 20, y)
    whitelistInfo:SetWidth(520)
    whitelistInfo:SetJustifyH("LEFT")
    whitelistInfo:SetText("|cffff6600Warning:|r Players listed below will |cffffff00always|r receive your current profile. Phase/map checks, alerts, blocking, ghost mode, and start-phase protections are skipped for them.")
    y = y - 45

    uiElements.whitelistEnabled = TabManager:CreateCheckbox(content, "Enable Whitelist Bypass", "Allow listed names to bypass all security checks and always receive your active profile.", "whitelistEnabled")
    uiElements.whitelistEnabled:SetPoint("TOPLEFT", 20, y)
    uiElements.whitelistEnabled:SetScript("OnClick", function(self)
        if self:GetChecked() then
            self:SetChecked(false)
            StaticPopup_Show("TRP3FW_WHITELIST_CONFIRM")
        else
            TRP3FW.Prefs.whitelistEnabled = false
            if TRP3FW.RefreshWhitelistCache then TRP3FW:RefreshWhitelistCache() end
            TRP3FW:RefreshUI()
        end
    end)
    y = y - 35

    local whitelistNameLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    whitelistNameLabel:SetPoint("TOPLEFT", 20, y)
    whitelistNameLabel:SetText("Names (one per line):")
    y = y - 20

    local whitelistScroll = CreateFrame("ScrollFrame", "TRP3FW_WhitelistScroll", content, "UIPanelScrollFrameTemplate")
    whitelistScroll:SetPoint("TOPLEFT", 20, y)
    whitelistScroll:SetSize(480, 100)
    uiElements.whitelistScroll = whitelistScroll

    local whitelistEdit = CreateFrame("EditBox", "TRP3FW_WhitelistEdit", whitelistScroll)
    whitelistEdit:SetMultiLine(true)
    whitelistEdit:SetFontObject(ChatFontNormal)
    whitelistEdit:SetWidth(460)
    whitelistEdit:SetHeight(90)
    whitelistEdit:SetAutoFocus(false)
    whitelistEdit:SetMaxLetters(3000)
    whitelistEdit:SetText(TRP3FW.Prefs.whitelistEntries or "")
    
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
        TRP3FW.Prefs.whitelistEntries = self:GetText()
    end)
    whitelistEdit:SetScript("OnEditFocusLost", function(self)
        local cleaned = sanitizeWhitelist(self:GetText())
        if cleaned ~= self:GetText() then
            self:SetText(cleaned)
        end
        TRP3FW.Prefs.whitelistEntries = cleaned
    end)
    whitelistScroll:SetScrollChild(whitelistEdit)

    local whitelistBG = CreateFrame("Frame", nil, content, "BackdropTemplate")
    whitelistBG:SetPoint("TOPLEFT", whitelistScroll, -6, 6)
    whitelistBG:SetPoint("BOTTOMRIGHT", whitelistScroll, 26, -6)
    whitelistBG:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    whitelistBG:SetBackdropColor(0, 0, 0, 0.25)
    whitelistBG:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    uiElements.whitelistEdit = whitelistEdit

    y = y - 120

    local whitelistSectionBottom = y
    local whitelistHeight = (whitelistSectionTop - whitelistSectionBottom) + 30
    local whitelistDanger = CreateFrame("Frame", nil, content, "BackdropTemplate")
    whitelistDanger:SetPoint("TOPLEFT", content, "TOPLEFT", 10, whitelistSectionTop + 20)
    whitelistDanger:SetPoint("RIGHT", content, "RIGHT", -2, 0)
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

    return scrollFrame
end

TabManager:RegisterTab("notifications", "Notifications", "Notification Settings", CreateNotificationsTab, function() TRP3FW:RefreshUI() end)
