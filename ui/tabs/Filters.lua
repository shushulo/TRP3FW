-- ui/tabs/Filters.lua
-- Appearance & Filters settings tab for TRP3FW (migrated to the skinned kit)

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

-- Stack a card below the previous one (or at the top), full content width.
local function stackCard(content, card, prev, width)
    card:SetWidth(width)
    if prev then
        card:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -TRP3FW.Theme.metrics.CARD_GAP)
        card:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -TRP3FW.Theme.metrics.CARD_GAP)
    else
        local inset = TRP3FW.Theme.metrics.CONTENT_INSET
        card:SetPoint("TOPLEFT", content, "TOPLEFT", inset, 0)
        card:SetPoint("TOPRIGHT", content, "TOPRIGHT", -inset, 0)
    end
    return card
end

local function CreateFiltersTab(container)
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()

    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 380)
    local uiElements = TabManager:GetUI()
    local M = TRP3FW.Theme.metrics
    local CARD_W = M.CARD_W

    -- (The Settings-complexity card was removed -- the level is now chosen from
    -- the live dropdown pinned to the bottom of the sidebar nav.)

    -- ---- Profile filters ---------------------------------------------------
    local fCard = stackCard(content, TabManager:CreateCard(content, "Profile filters", CARD_W), nil, CARD_W)

    -- Reflowable toggle row helper (hide + restack + resize on complexity change).
    local function toggleRow(key, label, tip, onToggle, step)
        local t = TabManager:CreateToggle(fCard, label, tip, key)
        t:SetOnToggle(onToggle)
        uiElements[key] = t
        fCard:AddRow(function(y)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", fCard, "TOPLEFT", 12, y)
            t:SetPoint("RIGHT", fCard, "RIGHT", -12, 0)
        end, step or M.ROW, t.complexityLevel, { t })
        return t
    end
    toggleRow("filterGradients", "Strip colour gradients", "Remove colour gradients from incoming profiles.",
        function(c) TRP3FW.Prefs.filterGradients = c; TRP3FW:Info("Filter change will take effect after /reload") end)
    toggleRow("filterIcons", "Strip icons from profiles", "Remove embedded icons from profile fields.",
        function(c) TRP3FW.Prefs.filterIcons = c; TRP3FW:Info("Filter change will take effect after /reload") end)
    toggleRow("filterMinimumFontSize", "Minimum font size", "Inject a minimum font size into incoming profiles.",
        function(c) TRP3FW.Prefs.filterMinimumFontSize = c; TRP3FW:RefreshUI() end, M.ROW_TALL)

    local fsd = TabManager:CreateSkinnedDropdown(fCard, "Font size level",
        "Minimum font size to inject.", 200, "minimumFontSizeLevel")
    fCard:AddRow(function(y)
        fsd:ClearAllPoints()
        fsd:SetPoint("TOPLEFT", fCard, "TOPLEFT", -4, y)
    end, 40, fsd.complexityLevel, { fsd })
    -- RefreshUI sets the text via "...LevelDropdown" (dropdownConfig loop) and
    -- enables/disables via "...Dropdown"; point both at this widget so it both
    -- shows the value and greys out when the toggle is off.
    uiElements.minimumFontSizeLevelDropdown = fsd
    uiElements.minimumFontSizeDropdown = fsd
    UIDropDownMenu_Initialize(fsd, function(self, level)
        local l = { {text="H1 (Largest)", val="h1"}, {text="H2 (Large)", val="h2"}, {text="H3 (Medium)", val="h3"}, {text="P (Normal)", val="p"} }
        for _, item in ipairs(l) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.func = function() TRP3FW.Prefs.minimumFontSizeLevel = item.val; UIDropDownMenu_SetText(fsd, item.text) end
            info.checked = (TRP3FW.Prefs.minimumFontSizeLevel == item.val)
            UIDropDownMenu_AddButton(info)
        end
    end)
    fCard:Reflow()

    return scrollFrame
end

TabManager:RegisterTab("filters", "Appearance", "Appearance & Filters", CreateFiltersTab, function() TRP3FW:RefreshUI() end, "Interface\\Icons\\INV_Misc_Ornatebox")
