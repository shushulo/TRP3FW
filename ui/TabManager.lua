-- ui/TabManager.lua
-- Manages modular tabs for the settings UI

local addonName, TRP3FW = ...

local TabManager = {}
TRP3FW.TabManager = TabManager

TabManager.tabs = {}
TabManager.orderedTabs = {}
TabManager.activeTab = nil

-- UI context shared across tabs
TabManager.uiElements = {}
TabManager.complexityWidgets = {}

function TabManager:LinkUI(uiElements, complexityWidgets, epsilonControls)
    self.uiElements = uiElements
    self.complexityWidgets = complexityWidgets
    self.epsilonControls = epsilonControls
end

function TabManager:GetEpsilonControls()
    return self.epsilonControls
end

function TabManager:RegisterTab(id, name, title, createFunc, refreshFunc)
    if self.tabs[id] then
        TRP3FW:Warn("Tab already registered: "..tostring(id))
        return
    end

    local tab = {
        id = id,
        name = name,
        title = title,
        create = createFunc,
        refresh = refreshFunc,
        frame = nil
    }

    self.tabs[id] = tab
    table.insert(self.orderedTabs, tab)
    TRP3FW:Debug("Registered settings tab: "..tostring(id), "ui")
end

function TabManager:GetUI()
    return self.uiElements
end

function TabManager:AddComplexityWidget(widget, key)
    widget.settingKey = key
    widget.complexityLevel = TRP3FW.SETTING_LEVELS[key] or 4
    table.insert(self.complexityWidgets, widget)
end

-- Shared UI Helpers
function TabManager:CreateSectionHeader(parent, text, yOffset)
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

function TabManager:AppendDefaultToTooltip(tooltipText, settingKey, level)
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
        local color = "00ff00"
        if level == 2 then color = "ffff00"
        elseif level == 3 then color = "ff8800"
        elseif level == 4 then color = "ff0000"
        end

        local COMPLEXITY_NAMES = { [1] = "Basic", [2] = "Intermediate", [3] = "Advanced", [4] = "Everything" }
        local levelName = COMPLEXITY_NAMES[level] or "Unknown"
        text = text .. string.format("\n|cff%s[%s Setting]|r", color, levelName)
    end

    return text
end

function TabManager:CreateCheckbox(parent, labelText, tooltipText, settingKey)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)

    local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 5, 0)
    label:SetText(labelText)
    check.label = label

    local level = TRP3FW.SETTING_LEVELS and TRP3FW.SETTING_LEVELS[settingKey] or 4
    check.complexityLevel = level
    check.settingKey = settingKey
    table.insert(self.complexityWidgets, check)

    local tooltip = self:AppendDefaultToTooltip(tooltipText, settingKey, level)
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

function TabManager:CreateEditBox(parent, labelText, tooltipText, width, settingKey)
    width = width or 100

    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetText(labelText)

    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetSize(width, 20)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)
    editBox:SetMaxLetters(6)
    editBox.label = label

    label:SetPoint("BOTTOMLEFT", editBox, "TOPLEFT", 0, 5)

    local level = TRP3FW.SETTING_LEVELS and TRP3FW.SETTING_LEVELS[settingKey] or 4
    editBox.complexityLevel = level
    editBox.settingKey = settingKey
    table.insert(self.complexityWidgets, editBox)

    local tooltip = self:AppendDefaultToTooltip(tooltipText, settingKey, level)
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

function TabManager:CreateDropdown(parent, labelText, tooltipText, width, settingKey)
    width = width or 200

    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetText(labelText)

    local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dropdown, width)
    dropdown.label = label

    label:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 20, 5)

    local level = TRP3FW.SETTING_LEVELS and TRP3FW.SETTING_LEVELS[settingKey] or 4
    dropdown.complexityLevel = level
    dropdown.settingKey = settingKey

    dropdown.EnableDropDown = function(self) UIDropDownMenu_EnableDropDown(self) end
    dropdown.DisableDropDown = function(self) UIDropDownMenu_DisableDropDown(self) end

    table.insert(self.complexityWidgets, dropdown)

    local tooltip = self:AppendDefaultToTooltip(tooltipText, settingKey, level)
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

function TabManager:CreateProgressBar(parent, width, height)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, height or 20)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    bar.bg = bg

    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT")
    fill:SetHeight(height or 20)
    fill:SetColorTexture(0, 1, 0, 0.8)
    bar.fill = fill

    local border = bar:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetColorTexture(0.5, 0.5, 0.5, 0.3)
    border:SetDrawLayer("OVERLAY", 7)

    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    bar.text = text

    function bar:SetValue(percent, displayText)
        percent = math.max(0, math.min(100, percent))
        local fillWidth = (width * percent) / 100
        self.fill:SetWidth(math.max(1, fillWidth))
        if percent >= 80 then self.fill:SetColorTexture(0, 0.8, 0, 0.8)
        elseif percent >= 50 then self.fill:SetColorTexture(1, 0.8, 0, 0.8)
        else self.fill:SetColorTexture(0.9, 0.2, 0, 0.8) end
        self.text:SetText(displayText or string.format("%.1f%%", percent))
    end

    return bar
end

function TabManager:CreateStatCard(parent, width, height)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(width, height)
    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.15, 0.18, 0.9)
    local border = CreateFrame("Frame", nil, card, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    border:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -8)
    title:SetTextColor(0.7, 0.7, 0.7)
    card.title = title
    local value = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    value:SetPoint("CENTER", 0, -5)
    card.value = value
    local subtext = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtext:SetPoint("BOTTOM", 0, 8)
    subtext:SetTextColor(0.6, 0.6, 0.6)
    card.subtext = subtext
    return card
end

function TabManager:CreateHorizontalStackedBar(parent, width, height)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, height or 25)
    local bg = container:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    container.segments = {}
    function container:SetValues(values)
        local total = 0
        for _, v in pairs(values) do total = total + v end
        if total == 0 then
            if not self.noDataText then self.noDataText = self:CreateFontString(nil, "OVERLAY", "GameFontNormal"); self.noDataText:SetPoint("CENTER"); self.noDataText:SetTextColor(0.5, 0.5, 0.5) end
            self.noDataText:SetText("No requests yet"); self.noDataText:Show()
            for _, seg in ipairs(self.segments) do seg.texture:Hide(); if seg.text then seg.text:Hide() end end
            return
        end
        if self.noDataText then self.noDataText:Hide() end
        local colors = { TRP3 = {0.3, 0.6, 1.0}, MRP = {0.8, 0.3, 0.8}, XRP = {1.0, 0.6, 0.2}, MSP = {0.2, 0.8, 0.4} }
        local dataList = {}
        for name, value in pairs(values) do if value > 0 then table.insert(dataList, {name = name, value = value}) end end
        table.sort(dataList, function(a,b) return a.name < b.name end)
        local currentX = 0
        for i, data in ipairs(dataList) do
            if not self.segments[i] then
                local segTexture = self:CreateTexture(nil, "ARTWORK")
                local text = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                self.segments[i] = {texture = segTexture, text = text}
            end
            local seg = self.segments[i]; local segWidth = (width * data.value) / total
            seg.texture:ClearAllPoints(); seg.texture:SetPoint("LEFT", currentX, 0); seg.texture:SetSize(segWidth, height or 25)
            local color = colors[data.name] or {0.5, 0.5, 0.5}; seg.texture:SetColorTexture(color[1], color[2], color[3], 0.9); seg.texture:Show()
            if segWidth > 40 then seg.text:ClearAllPoints(); seg.text:SetPoint("CENTER", self, "LEFT", currentX + (segWidth / 2), 0); seg.text:SetText(data.value); seg.text:SetTextColor(1, 1, 1); seg.text:Show() else seg.text:Hide() end
            currentX = currentX + segWidth
        end
        for i = #dataList + 1, #self.segments do self.segments[i].texture:Hide(); self.segments[i].text:Hide() end
    end
    return container
end

function TabManager:CreateScrollFrame(parent, contentHeight)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -70)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    -- Use fixed width for child to avoid 0-width issues, will be updated by scrollFrame
    scrollChild:SetSize(640, contentHeight or 1000)
    scrollFrame:SetScrollChild(scrollChild)

    return scrollFrame, scrollChild
end

function TabManager:SwitchToTab(id)
    if not self.tabs[id] then return end

    -- Hide current
    if self.activeTab and self.activeTab.frame then
        self.activeTab.frame:Hide()
    end

    local tab = self.tabs[id]

    -- Create if needed (Lazy Loading)
    if not tab.frame then
        -- Important: Ensure the created frame is what we show/hide
        -- If create() returns a scrollFrame, that's what we store and hide.
        tab.frame = tab.create(self.container)
    end

    if tab.frame then
        tab.frame:Show()
    end
    self.activeTab = tab

    if tab.refresh then
        tab.refresh()
    end

    -- If switching to status tab, ensure the background timer is running
    if id == "status" and TRP3FW.StartStatusUpdates then
        TRP3FW:StartStatusUpdates()
    end

    -- Global refresh to populate elements
    if TRP3FW.RefreshUI then
        TRP3FW:RefreshUI()
    end
end

-- Initialize the TabManager with the settings container
function TabManager:Initialize(container)
    self.container = container
end
