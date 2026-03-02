-- ui/tabs/Status.lua
-- Status & Performance Tab for TRP3FW Settings

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

local function CreateStatusTab(container)
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()
    
    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 1100)
    local uiElements = TabManager:GetUI()
    local y = -10

    TabManager:CreateSectionHeader(content, "Environment", y)
    y = y - 35

    local function createInlineStat(parent, labelText, yOffset, xOffset)
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", xOffset or 20, yOffset)
        label:SetText(labelText)
        label:SetTextColor(0.8, 0.8, 0.8)

        local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        value:SetPoint("LEFT", label, "RIGHT", 10, 0)
        return value, label
    end

    uiElements.statusAddonsList = createInlineStat(content, "RP Addons:", y)
    y = y - 22
    uiElements.statusMapScanner = createInlineStat(content, "Map Scanner:", y)
    y = y - 22
    uiElements.statusEpsilonAPI = createInlineStat(content, "Epsilon API:", y)
    y = y - 22
    uiElements.statusMemory = createInlineStat(content, "Memory Usage:", y)
    
    -- Column 2: Performance Metrics
    local col2X = 220
    local perfY = y + 66
    uiElements.statusLatency = createInlineStat(content, "Latency (Inst/Avg/Peak):", perfY, col2X)
    perfY = perfY - 22
    uiElements.statusCPULoad = createInlineStat(content, "CPU Load (Inst/Avg/Peak):", perfY, col2X)
    perfY = perfY - 22
    uiElements.statusThroughput = createInlineStat(content, "Throughput (Inst/Avg/Peak):", perfY, col2X)
    perfY = perfY - 22
    uiElements.statusPhaseSecurity = createInlineStat(content, "Phase Security:", perfY, col2X)
    
    y = y - 45

    -- History Controls
    local histCheck = TabManager:CreateCheckbox(content, "Track Performance History", "Enable background performance tracking.", "performanceHistoryEnabled")
    histCheck:SetPoint("TOPLEFT", 20, y)
    uiElements.performanceHistoryEnabled = histCheck
    histCheck:SetScript("OnClick", function(self)
        TRP3FW.Prefs.performanceHistoryEnabled = self:GetChecked()
        if TRP3FW.UpdateBackgroundTracking then TRP3FW:UpdateBackgroundTracking() end
    end)

    local showHistoryBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    showHistoryBtn:SetSize(120, 22)
    showHistoryBtn:SetPoint("LEFT", histCheck.label, "RIGHT", 20, 0)
    showHistoryBtn:SetText("Show Graphs")
    showHistoryBtn:SetScript("OnClick", function()
        if TRP3FW.ToggleHistoryWindow then TRP3FW:ToggleHistoryWindow() end
    end)

    y = y - 40

    TabManager:CreateSectionHeader(content, "Session Statistics", y)
    y = y - 45
    local cardWidth = (560 - 20) / 3
    uiElements.statusAlertsCard = TabManager:CreateStatCard(content, cardWidth, 75)
    uiElements.statusAlertsCard:SetPoint("TOPLEFT", 20, y)
    uiElements.statusAlertsCard.title:SetText("ALERTS SHOWN")

    uiElements.statusBlocksCard = TabManager:CreateStatCard(content, cardWidth, 75)
    uiElements.statusBlocksCard:SetPoint("LEFT", uiElements.statusAlertsCard, "RIGHT", 10, 0)
    uiElements.statusBlocksCard.title:SetText("BLOCKS")

    uiElements.statusGhostCard = TabManager:CreateStatCard(content, cardWidth, 75)
    uiElements.statusGhostCard:SetPoint("LEFT", uiElements.statusBlocksCard, "RIGHT", 10, 0)
    uiElements.statusGhostCard.title:SetText("GHOST PROFILES")
    y = y - 85

    TabManager:CreateSectionHeader(content, "Detection Breakdown", y)
    y = y - 30
    uiElements.statusPhaseAlerts = createInlineStat(content, "Phase Verification Failures:", y)
    y = y - 25
    uiElements.statusMapAlerts = createInlineStat(content, "Map/WHO Verification Failures:", y)
    y = y - 50

    TabManager:CreateSectionHeader(content, "Recent Activity", y)
    y = y - 30
    local function createHeader(parent, text, width, xOffset)
        local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", xOffset, 0)
        h:SetWidth(width)
        h:SetJustifyH("LEFT")
        h:SetText(text)
        h:SetTextColor(0.6, 0.6, 0.6)
        return h
    end
    local headerRow = CreateFrame("Frame", nil, content)
    headerRow:SetSize(540, 20)
    headerRow:SetPoint("TOPLEFT", 20, y)
    createHeader(headerRow, "Time", 60, 0)
    createHeader(headerRow, "Player", 150, 65)
    createHeader(headerRow, "Addon", 60, 220)
    createHeader(headerRow, "Result", 100, 285)
    y = y - 20
    uiElements.statusRecentEvents = {}
    for i = 1, 8 do
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(540, 18)
        row:SetPoint("TOPLEFT", 20, y)
        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.05)
        end
        local function createCell(width, xOffset)
            local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cell:SetPoint("LEFT", xOffset, 0); cell:SetWidth(width); cell:SetJustifyH("LEFT")
            return cell
        end
        row.Time = createCell(60, 0)
        row.Player = createCell(150, 65)
        row.Addon = createCell(60, 220)
        row.Result = createCell(200, 285)
        table.insert(uiElements.statusRecentEvents, row)
        y = y - 18
    end
    y = y - 20

    TabManager:CreateSectionHeader(content, "Requests by Addon", y)
    y = y - 30
    uiElements.statusRequestsBar = TabManager:CreateHorizontalStackedBar(content, 540, 30)
    uiElements.statusRequestsBar:SetPoint("TOPLEFT", 20, y)
    y = y - 35
    local legend = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legend:SetPoint("TOPLEFT", 20, y)
    legend:SetText("|cff4D99FFTRP3|r  |cffCC4DCCMRP|r  |cffFF9933XRP|r  |cff33CC66MSP|r")
    legend:SetTextColor(0.7, 0.7, 0.7)
    y = y - 35

    TabManager:CreateSectionHeader(content, "Cache Performance", y)
    y = y - 30
    local function createCachePerf(parent, label, yOffset)
        local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetPoint("TOPLEFT", 20, yOffset); l:SetWidth(130); l:SetJustifyH("LEFT")
        l:SetText(label); l:SetTextColor(0.8, 0.8, 0.8)
        local bar = TabManager:CreateProgressBar(parent, 400, 18)
        bar:SetPoint("TOPLEFT", 155, yOffset)
        return bar
    end
    uiElements.statusPhaseCachePerfBar = createCachePerf(content, "Phase Cache:", y)
    y = y - 25
    uiElements.statusMapCachePerfBar = createCachePerf(content, "Map Scan:", y)
    y = y - 25
    uiElements.statusWhoCachePerfBar = createCachePerf(content, "WHO Query:", y)
    y = y - 25
    uiElements.statusAllowedSendersCachePerfBar = createCachePerf(content, "Allowed Senders:", y)
    y = y - 25
    uiElements.statusInteractionCachePerfBar = createCachePerf(content, "Interaction:", y)
    y = y - 25
    uiElements.statusBroadcastCachePerfBar = createCachePerf(content, "Broadcasts:", y)
    y = y - 25
    uiElements.statusSpvpCachePerfBar = createCachePerf(content, "SPVP Salt:", y)
    y = y - 25
    uiElements.statusSpvpVerifiedCachePerfBar = createCachePerf(content, "SPVP Verified:", y)
    y = y - 40

    TabManager:CreateSectionHeader(content, "Cache Status", y)
    y = y - 30
    local function createCacheStatus(parent, label, yOffset, xOffset)
        local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetPoint("TOPLEFT", xOffset, yOffset); l:SetWidth(140); l:SetJustifyH("LEFT")
        l:SetText(label); l:SetTextColor(0.8, 0.8, 0.8)
        local v = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        v:SetPoint("TOPLEFT", xOffset + 140, yOffset); v:SetJustifyH("LEFT")
        return v
    end
    uiElements.statusPhaseCache = createCacheStatus(content, "Phase Cache:", y, 20)
    uiElements.statusBroadcastCache = createCacheStatus(content, "Broadcast Cache:", y, 310)
    y = y - 22
    uiElements.statusScanCache = createCacheStatus(content, "Map Scan Cache:", y, 20)
    uiElements.statusSendCache = createCacheStatus(content, "Send Cache:", y, 310)
    y = y - 22
    uiElements.statusWhoNameCache = createCacheStatus(content, "WHO Name Cache:", y, 20)
    uiElements.statusWhoZoneCache = createCacheStatus(content, "WHO Zone Cache:", y, 310)
    y = y - 22
    uiElements.statusInteractionCache = createCacheStatus(content, "Interaction Cache:", y, 20)
    uiElements.statusSuppressionCache = createCacheStatus(content, "Suppression Timers:", y, 310)
    y = y - 22
    uiElements.statusSpvpCache = createCacheStatus(content, "SPVP Salt Cache:", y, 20)
    uiElements.statusSpvpVerifiedCache = createCacheStatus(content, "SPVP Verified Cache:", y, 310)
    y = y - 40

    TabManager:CreateSectionHeader(content, "RunPrivileged API Statistics", y)
    y = y - 30
    uiElements.statusPrivilegedTotal = createInlineStat(content, "Total Calls:", y, 20)
    y = y - 20
    uiElements.statusPrivilegedSuccess = createInlineStat(content, "Successful:", y, 20)
    y = y - 20
    uiElements.statusPrivilegedBlocked = createInlineStat(content, "Rate Limited:", y, 20)
    y = y - 20
    uiElements.statusPrivilegedErrors = createInlineStat(content, "Errors:", y, 20)
    y = y - 20
    uiElements.statusPrivilegedDeferred = createInlineStat(content, "Deferred (LOW):", y, 20)
    y = y - 20
    uiElements.statusPrivilegedRefunded = createInlineStat(content, "Tokens Refunded:", y, 20)
    y = y - 40

    TabManager:CreateSectionHeader(content, "Status Tab Settings", y)
    y = y - 30
    local refreshText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    refreshText:SetPoint("TOPLEFT", 20, y); refreshText:SetText("Auto-Refresh Rate:")
    y = y - 30
    local slider = CreateFrame("Slider", "TRP3FW_StatusRefreshSlider", content, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 20, y); slider:SetWidth(360); slider:SetMinMaxValues(2, 120); slider:SetValueStep(1); slider:SetObeyStepOnDrag(true)
    slider:SetValue(TRP3FW.Prefs.statusRefreshRate or 30)  -- Initialize with current value
    uiElements.statusRefreshRate = slider
    getglobal(slider:GetName().."Low"):SetText("2s"); getglobal(slider:GetName().."High"):SetText("120s")
    getglobal(slider:GetName().."Text"):SetText("Refresh every " .. (TRP3FW.Prefs.statusRefreshRate or 30) .. " seconds")
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value); TRP3FW.Prefs.statusRefreshRate = value
        getglobal(self:GetName().."Text"):SetText("Refresh every " .. value .. " seconds")
        if TRP3FW.StartStatusUpdates then TRP3FW:StartStatusUpdates() end
    end)
    
    local refreshBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    refreshBtn:SetSize(90, 22); refreshBtn:SetPoint("LEFT", slider, "RIGHT", 12, 0); refreshBtn:SetText("Refresh now")
    refreshBtn:SetScript("OnClick", function() if TRP3FW.UpdateStatusTab then TRP3FW:UpdateStatusTab() end end)

    return scrollFrame
end

TabManager:RegisterTab("status", "Status", "Status & Performance", CreateStatusTab, function() if TRP3FW.UpdateStatusTab then TRP3FW:UpdateStatusTab() end end)
