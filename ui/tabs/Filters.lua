-- ui/tabs/Filters.lua
-- Filters & Addons settings tab for TRP3FW

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

local function CreateFiltersTab(container)
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()
    
    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 650)
    local uiElements = TabManager:GetUI()
    local y = -10

    -- Complexity Level Header
    local complexityLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    complexityLabel:SetPoint("TOPLEFT", 20, y); complexityLabel:SetText("Settings Complexity Level")
    y = y - 30
    
    local complexityDropdown = CreateFrame("Frame", "TRP3FW_ComplexityDropdown", content, "UIDropDownMenuTemplate")
    complexityDropdown:SetPoint("TOPLEFT", 20, y); UIDropDownMenu_SetWidth(complexityDropdown, 200)
    uiElements.complexityDropdown = complexityDropdown
    
    local COMPLEXITY_NAMES = { [1] = "Basic", [2] = "Intermediate", [3] = "Advanced", [4] = "Everything" }
    UIDropDownMenu_Initialize(complexityDropdown, function(self, level)
        for i = 1, 4 do
            local info = UIDropDownMenu_CreateInfo()
            info.text = COMPLEXITY_NAMES[i]; info.value = i; info.func = function()
                TRP3FW.Prefs.uiComplexityLevel = i; UIDropDownMenu_SetText(complexityDropdown, COMPLEXITY_NAMES[i])
                if TRP3FW.EnforceComplexityDefaults then TRP3FW:EnforceComplexityDefaults(i) end
                TRP3FW:RefreshUI()
            end
            info.checked = (TRP3FW.Prefs.uiComplexityLevel == i); UIDropDownMenu_AddButton(info, level)
        end
    end)
    y = y - 50

    TabManager:CreateSectionHeader(content, "Filter Settings", y)
    y = y - 40
    uiElements.filterGradients = TabManager:CreateCheckbox(content, "Strip Color Gradients", "Remove color gradients from incoming profiles.", "filterGradients")
    uiElements.filterGradients:SetPoint("TOPLEFT", 20, y)
    uiElements.filterGradients:SetScript("OnClick", function(self) TRP3FW.Prefs.filterGradients = self:GetChecked(); TRP3FW:Info("Filter change will take effect after /reload") end)
    y = y - 35
    
    uiElements.filterIcons = TabManager:CreateCheckbox(content, "Strip Icons from Profiles", "Remove embedded icons from profile fields.", "filterIcons")
    uiElements.filterIcons:SetPoint("TOPLEFT", 20, y)
    uiElements.filterIcons:SetScript("OnClick", function(self) TRP3FW.Prefs.filterIcons = self:GetChecked(); TRP3FW:Info("Filter change will take effect after /reload") end)
    y = y - 35
    
    uiElements.filterMinimumFontSize = TabManager:CreateCheckbox(content, "Minimum Font Size", "Inject minimum font size into incoming profiles.", "filterMinimumFontSize")
    uiElements.filterMinimumFontSize:SetPoint("TOPLEFT", 20, y)
    uiElements.filterMinimumFontSize:SetScript("OnClick", function(self) TRP3FW.Prefs.filterMinimumFontSize = self:GetChecked(); TRP3FW:RefreshUI() end)
    y = y - 40
    
    local fsd, fsl = TabManager:CreateDropdown(content, "Font Size Level", "Minimum font size to inject.", 200, "minimumFontSizeLevel")
    fsd:SetPoint("TOPLEFT", 40, y); uiElements.minimumFontSizeLevelDropdown = fsd
    UIDropDownMenu_Initialize(fsd, function(self, level)
        local l = { {text="H1 (Largest)", val="h1"}, {text="H2 (Large)", val="h2"}, {text="H3 (Medium)", val="h3"}, {text="P (Normal)", val="p"} }
        for _, item in ipairs(l) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text; info.func = function() TRP3FW.Prefs.minimumFontSizeLevel = item.val; UIDropDownMenu_SetText(fsd, item.text) end
            info.checked = (TRP3FW.Prefs.minimumFontSizeLevel == item.val); UIDropDownMenu_AddButton(info)
        end
    end)
    y = y - 60

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

TabManager:RegisterTab("filters", "Filters", "Filters & Addons", CreateFiltersTab, function() TRP3FW:RefreshUI() end)
