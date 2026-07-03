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

-- ===========================================================================
-- Skinned widget kit (TRP3-style slate/gold theme)
--
-- These constructors are ADDED ALONGSIDE the classic Create* helpers above;
-- the old ones keep working so tabs can migrate one at a time. New widgets
-- expose the same :SetChecked()/:GetChecked() surface as UICheckButtonTemplate
-- so RefreshUI's existing loops drive them unchanged.
--
-- Requires TRP3FW.Theme (ui/Theme.lua, loaded before this file).
-- ===========================================================================

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"

-- Register a widget with the complexity system + attach standard tooltip.
-- Mirrors the bookkeeping the classic CreateCheckbox does.
function TabManager:_registerSkinned(widget, labelText, tooltipText, settingKey)
    local level = TRP3FW.SETTING_LEVELS and TRP3FW.SETTING_LEVELS[settingKey] or 4
    widget.complexityLevel = level
    widget.settingKey = settingKey
    table.insert(self.complexityWidgets, widget)

    if labelText and (tooltipText or level > 1) then
        local tip = self:AppendDefaultToTooltip(tooltipText, settingKey, level)
        widget:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return widget
end

-- A grouped setting card: dark slate panel with a gold-caps section caption.
-- Returns the card frame. Card exposes :NextY() as a simple vertical layout
-- cursor so callers can stack rows without hand-tracking offsets.
function TabManager:CreateCard(parent, captionText, width)
    local Theme = TRP3FW.Theme
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetSize(width or 600, 60)
    card:SetBackdrop(Theme.BACKDROP_CARD)
    card:SetBackdropColor(Theme:Color("CARD"))
    card:SetBackdropBorderColor(Theme:Color("BORDER"))

    local topPad = 10
    if captionText then
        local cap = card:CreateFontString(nil, "OVERLAY", Theme.fonts.SUB)
        cap:SetPoint("TOPLEFT", 12, -9)
        cap:SetText(captionText:upper())
        cap:SetTextColor(Theme:Color("GOLD"))
        card.caption = cap
        topPad = 26
    end

    card._cursorY = -topPad
    function card:NextY(step)
        local y = self._cursorY
        self._cursorY = self._cursorY - (step or TRP3FW.Theme.metrics.ROW)
        return y
    end
    -- Resize the card to fit its content after rows are added.
    function card:FitHeight(bottomPad)
        self:SetHeight(math.abs(self._cursorY) + (bottomPad or 10))
    end

    return card
end

-- A pill toggle switch built from a CheckButton + custom textures. Behaves like
-- a checkbox (click, keyboard, :SetChecked/:GetChecked) but renders as a
-- sliding pill. subLabel is optional muted hint text shown after the label.
function TabManager:CreateToggle(parent, labelText, tooltipText, settingKey, subLabel)
    local Theme = TRP3FW.Theme
    local W, H = 34, 18

    local toggle = CreateFrame("CheckButton", nil, parent)
    toggle:SetSize(W, H)
    toggle:SetHitRectInsets(-4, -4, -4, -4)

    -- Track (pill background)
    local track = toggle:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetTexture(WHITE8X8)
    toggle.track = track

    -- Knob
    local knob = toggle:CreateTexture(nil, "ARTWORK")
    knob:SetTexture(WHITE8X8)
    knob:SetSize(H - 4, H - 4)
    toggle.knob = knob

    -- Label (to the LEFT of the pill so the pill sits on the right edge of a row)
    local label = toggle:CreateFontString(nil, "ARTWORK", Theme.fonts.LABEL)
    label:SetText(labelText)
    label:SetTextColor(Theme:Color("TEXT_PRIMARY"))
    toggle.label = label

    if subLabel then
        local sub = toggle:CreateFontString(nil, "ARTWORK", Theme.fonts.LABEL)
        sub:SetPoint("LEFT", label, "RIGHT", 4, 0)
        sub:SetText(subLabel)
        sub:SetTextColor(Theme:Color("TEXT_MUTED"))
        toggle.sub = sub
    end

    local function applyVisual(self)
        local on = self:GetChecked()
        if not self:IsEnabled() then
            track:SetColorTexture(Theme:Color("BORDER"))
            knob:SetColorTexture(Theme:Color("TEXT_MUTED"))
        elseif on then
            track:SetColorTexture(Theme:Color("SUCCESS", 0.55))
            knob:SetColorTexture(Theme:Color("GOLD_TEXT"))
        else
            track:SetColorTexture(Theme:Color("BORDER"))
            knob:SetColorTexture(Theme:Color("TEXT_SECONDARY"))
        end
        knob:ClearAllPoints()
        if on then
            knob:SetPoint("RIGHT", track, "RIGHT", -2, 0)
        else
            knob:SetPoint("LEFT", track, "LEFT", 2, 0)
        end
    end
    toggle._applyVisual = applyVisual

    -- Keep visuals in sync with programmatic and user state changes.
    hooksecurefunc(toggle, "SetChecked", function(self) applyVisual(self) end)
    toggle:SetScript("OnClick", function(self)
        applyVisual(self)
        if self._onToggle then self._onToggle(self:GetChecked()) end
    end)
    toggle:HookScript("OnEnable", applyVisual)
    toggle:HookScript("OnDisable", applyVisual)
    applyVisual(toggle)

    -- Convenience: register a change handler that also writes the pref.
    function toggle:SetOnToggle(fn) self._onToggle = fn end

    self:_registerSkinned(toggle, labelText, tooltipText, settingKey)
    return toggle
end

-- A compact on/off chip for boolean appearance flags. Shows a check when on and
-- a plus when off, recoloring accordingly. Same checkbox behavior underneath.
function TabManager:CreateChip(parent, labelText, tooltipText, settingKey)
    local Theme = TRP3FW.Theme

    local chip = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    chip:SetBackdrop(Theme.BACKDROP_WELL)
    chip:SetHeight(24)

    local icon = chip:CreateFontString(nil, "OVERLAY", Theme.fonts.SUB)
    icon:SetPoint("LEFT", 8, 0)
    chip.iconFS = icon

    local text = chip:CreateFontString(nil, "OVERLAY", Theme.fonts.SUB)
    text:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    text:SetText(labelText)
    chip.label = text

    -- Size chip to its text.
    chip:SetWidth(text:GetStringWidth() + 40)

    local function applyVisual(self)
        local on = self:GetChecked()
        if on then
            self:SetBackdropColor(Theme:Color("CARD_HOVER"))
            self:SetBackdropBorderColor(Theme:Color("BORDER_STRONG"))
            icon:SetText("|cff7fc07f\226\156\147|r") -- check, success green
            text:SetTextColor(Theme:Color("TEXT_PRIMARY"))
        else
            self:SetBackdropColor(Theme:Color("INSET"))
            self:SetBackdropBorderColor(Theme:Color("BORDER"))
            icon:SetText("|cff707790+|r")
            text:SetTextColor(Theme:Color("TEXT_MUTED"))
        end
    end
    chip._applyVisual = applyVisual

    hooksecurefunc(chip, "SetChecked", function(self) applyVisual(self) end)
    chip:SetScript("OnClick", function(self)
        applyVisual(self)
        if self._onToggle then self._onToggle(self:GetChecked()) end
    end)
    applyVisual(chip)

    function chip:SetOnToggle(fn) self._onToggle = fn end

    self:_registerSkinned(chip, labelText, tooltipText, settingKey)
    return chip
end

-- A gold-fill slider with an inline value readout. Replaces raw numeric edit
-- boxes for ranged tunables. valueFormat is a string.format pattern for the
-- readout (e.g. "%d s"). Exposes :SetValue/:GetValue like a Slider.
function TabManager:CreateSlider(parent, labelText, tooltipText, settingKey, minV, maxV, step, valueFormat)
    local Theme = TRP3FW.Theme
    valueFormat = valueFormat or "%d"

    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(560, 22)

    local label = row:CreateFontString(nil, "ARTWORK", Theme.fonts.LABEL)
    label:SetPoint("LEFT", 0, 0)
    label:SetText(labelText)
    label:SetTextColor(Theme:Color("TEXT_PRIMARY"))
    row.label = label

    local readout = row:CreateFontString(nil, "ARTWORK", Theme.fonts.LABEL)
    readout:SetPoint("RIGHT", 0, 0)
    readout:SetJustifyH("RIGHT")
    readout:SetTextColor(Theme:Color("GOLD_TEXT"))
    row.readout = readout

    local slider = CreateFrame("Slider", nil, row)
    slider:SetPoint("LEFT", label, "RIGHT", 12, 0)
    slider:SetPoint("RIGHT", readout, "LEFT", -12, 0)
    slider:SetHeight(14)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT"); track:SetPoint("RIGHT")
    track:SetHeight(4)
    track:SetTexture(WHITE8X8)
    track:SetColorTexture(Theme:Color("INSET"))

    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetHeight(4)
    fill:SetTexture(WHITE8X8)
    fill:SetColorTexture(Theme:Color("GOLD"))
    row.fill = fill

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE8X8)
    thumb:SetSize(14, 14)
    thumb:SetColorTexture(Theme:Color("GOLD_TEXT"))
    slider:SetThumbTexture(thumb)

    local function updateFill(self, value)
        local lo, hi = self:GetMinMaxValues()
        local pct = (hi > lo) and ((value - lo) / (hi - lo)) or 0
        local w = self:GetWidth() * pct
        fill:SetWidth(math.max(1, w))
        readout:SetText(string.format(valueFormat, value))
    end

    slider:SetScript("OnValueChanged", function(self, value)
        updateFill(self, value)
        if row._onChange then row._onChange(value) end
    end)

    -- Proxy the row so RefreshUI can treat it like a slider via row:SetValue().
    function row:SetValue(v) slider:SetValue(v) end
    function row:GetValue() return slider:GetValue() end
    function row:SetOnChange(fn) self._onChange = fn end
    row.slider = slider

    self:_registerSkinned(slider, labelText, tooltipText, settingKey)
    return row
end

-- Reskinned section header: gold caps + slate hairline (replaces the cyan
-- header used by the classic CreateSectionHeader). Kept as a separate name so
-- existing tabs are unaffected until they migrate.
function TabManager:CreateSkinnedHeader(parent, text, yOffset)
    local Theme = TRP3FW.Theme
    local header = parent:CreateFontString(nil, "ARTWORK", Theme.fonts.SUB)
    header:SetPoint("TOPLEFT", 12, yOffset)
    header:SetText(text:upper())
    header:SetTextColor(Theme:Color("GOLD_TEXT"))

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -5)
    line:SetPoint("RIGHT", parent, -12, 0)
    line:SetColorTexture(Theme:Color("BORDER"))

    return header
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
