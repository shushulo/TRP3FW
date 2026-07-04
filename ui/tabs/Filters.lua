-- ui/tabs/Filters.lua
-- Filters & Addons settings tab for TRP3FW

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

local function CreateFiltersTab(container)
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()

    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 350)
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

    -- Addon Monitoring & Hook Safety moved to the Advanced tab (Phase 2 UX restructure)

    return scrollFrame
end

TabManager:RegisterTab("filters", "Appearance", "Appearance & Filters", CreateFiltersTab, function() TRP3FW:RefreshUI() end, "Interface\\Icons\\INV_Misc_Ornatebox")
