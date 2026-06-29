-- ui/tabs/Notifications.lua
-- Notifications settings tab for TRP3FW

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

local function CreateNotificationsTab(container)
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()

    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 600)
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

    -- (Scan Reply Controls moved to Security tab — Phase 3 UX restructure)
    -- (Mode summary moved to Protection tab — Phase 1 UX restructure)

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
    y = y - 30

    -- Suppress WHO Output (moved from Alerts tab — Phase 2 UX restructure)
    uiElements.suppressAllWhoOutput = TabManager:CreateCheckbox(content, "Suppress WHO Output", "Hide all WHO results in chat.", "suppressAllWhoOutput")
    uiElements.suppressAllWhoOutput:SetPoint("TOPLEFT", 20, y)
    uiElements.suppressAllWhoOutput:SetScript("OnClick", function(self) TRP3FW.Prefs.suppressAllWhoOutput = self:GetChecked() end)
    do
        local ec = TabManager:GetEpsilonControls()
        if ec then table.insert(ec, uiElements.suppressAllWhoOutput) end
    end

    -- (Whitelist Bypass moved to Security tab — Phase 3 UX restructure)

    return scrollFrame
end

TabManager:RegisterTab("notifications", "Notifications", "Notification Settings", CreateNotificationsTab, function() TRP3FW:RefreshUI() end)
