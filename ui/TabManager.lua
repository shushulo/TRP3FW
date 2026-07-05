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

function TabManager:RegisterTab(id, name, title, createFunc, refreshFunc, iconTexture)
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
        iconTexture = iconTexture,  -- optional sidebar nav icon
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
    local M = TRP3FW.Theme.metrics
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    -- Fill the content panel exactly (no internal top inset -- the first card's
    -- top must line up with the sidebar's top). Reserve GAP + 16px on the right
    -- for the scrollbar so the card->scrollbar gap equals the structural GAP.
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -(M.GAP + 16), 0)

    -- Re-anchor the template's scrollbar to sit exactly GAP right of the
    -- viewport (its default is +6, which made the right gap look different).
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", M.GAP, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", M.GAP, 16)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    -- Viewport width from the shared metric (content panel - scrollbar reserve).
    scrollChild:SetSize(M.SCROLL_W, contentHeight or 1000)
    scrollFrame:SetScrollChild(scrollChild)
    -- Safety net: keep the scroll child's width in lockstep with the real
    -- viewport so full-width cards can never overhang or fall short.
    scrollFrame:HookScript("OnSizeChanged", function(self, w)
        if w and w > 0 then scrollChild:SetWidth(w) end
    end)

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

    local INNER = Theme.metrics.INNER
    local topPad = 10
    if captionText then
        local cap = card:CreateFontString(nil, "OVERLAY", Theme.fonts.SUB)
        cap:SetPoint("TOPLEFT", INNER, -9)
        cap:SetText(captionText:upper())
        cap:SetTextColor(Theme:Color("GOLD"))
        card.caption = cap
        -- Hairline divider under the caption (mockup parity; adds structure).
        local rule = card:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", cap, "BOTTOMLEFT", 0, -4)
        rule:SetPoint("RIGHT", card, "RIGHT", -INNER, 0)
        rule:SetColorTexture(Theme:Color("BORDER"))
        card.rule = rule
        topPad = 30
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

-- A pill toggle switch built from a CheckButton + custom textures. The widget
-- is a full-width ROW: a label on the left and a sliding pill on the right.
-- Behaves like a checkbox (click, keyboard, :SetChecked/:GetChecked). The knob
-- is a circle (round mask) and the track uses rounded end-cap textures so it
-- reads as a switch, not a raw square. subLabel is optional muted hint text.
--
-- The whole row is clickable; :SetChecked drives the visual via a secure hook.
function TabManager:CreateToggle(parent, labelText, tooltipText, settingKey, subLabel)
    local Theme = TRP3FW.Theme
    local ROUND_MASK = Theme.ROUND_MASK
    local PILL_W, PILL_H, KNOB = 36, 18, 14

    -- Full-width row acts as the CheckButton so the whole line is clickable.
    local toggle = CreateFrame("CheckButton", nil, parent)
    toggle:SetHeight(22)
    toggle:SetWidth(560)

    -- Label (left)
    local label = toggle:CreateFontString(nil, "ARTWORK", Theme.fonts.LABEL)
    label:SetPoint("LEFT", toggle, "LEFT", 0, 0)
    label:SetText(labelText)
    label:SetTextColor(Theme:Color("TEXT_PRIMARY"))
    toggle.label = label

    if subLabel then
        local sub = toggle:CreateFontString(nil, "ARTWORK", Theme.fonts.SUB)
        sub:SetPoint("LEFT", label, "RIGHT", 5, 0)
        sub:SetText(subLabel)
        sub:SetTextColor(Theme:Color("TEXT_MUTED"))
        toggle.sub = sub
    end

    -- Pill container (right) is a BackdropTemplate frame: the track fill + border
    -- come from the backdrop, which colors reliably via SetBackdropColor (no mask
    -- involved, so no SetColorTexture-vs-mask conflict). Flat rounded-rect look.
    local pill = CreateFrame("Frame", nil, toggle, "BackdropTemplate")
    pill:SetSize(PILL_W, PILL_H)
    pill:SetPoint("RIGHT", toggle, "RIGHT", 0, 0)
    pill:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    toggle.pill = pill

    -- Knob: round-masked circle that slides. The knob mask alone works fine
    -- (a circle mask on a square texture is a true circle). OVERLAY so it sits
    -- above the pill backdrop.
    local knob = pill:CreateTexture(nil, "OVERLAY")
    knob:SetTexture(WHITE8X8)
    knob:SetSize(KNOB, KNOB)
    local knobMask = pill:CreateMaskTexture()
    knobMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    knobMask:SetAllPoints(knob)
    knob:AddMaskTexture(knobMask)
    toggle.knob = knob

    local function setTrackColor(r, g, b, a)
        pill:SetBackdropColor(r, g, b, a)
    end

    local function applyVisual(self)
        local on = self:GetChecked()
        if not self:IsEnabled() then
            setTrackColor(Theme:Color("BORDER"))
            pill:SetBackdropBorderColor(Theme:Color("BORDER"))
            knob:SetColorTexture(Theme:Color("TEXT_MUTED"))
        elseif on then
            setTrackColor(Theme:Color("SUCCESS"))
            pill:SetBackdropBorderColor(Theme:Color("GOLD"))
            knob:SetColorTexture(Theme:Color("GOLD_TEXT"))
        else
            setTrackColor(Theme:Color("INSET"))
            pill:SetBackdropBorderColor(Theme:Color("BORDER_STRONG"))
            knob:SetColorTexture(Theme:Color("TEXT_SECONDARY"))
        end
        knob:ClearAllPoints()
        if on then
            knob:SetPoint("RIGHT", pill, "RIGHT", -2, 0)
        else
            knob:SetPoint("LEFT", pill, "LEFT", 2, 0)
        end
    end
    toggle._applyVisual = applyVisual

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

-- A compact on/off chip for boolean appearance flags. Shows a checkmark
-- texture when on (no icon when off) and recolors its background/border.
-- Same checkbox behavior underneath.
function TabManager:CreateChip(parent, labelText, tooltipText, settingKey)
    local Theme = TRP3FW.Theme

    local chip = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    chip:SetBackdrop(Theme.BACKDROP_CHIP)
    chip:SetHeight(24)

    -- Check icon: Blizzard's checkmark texture (font-safe, no tofu glyphs).
    local icon = chip:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 6, 0)
    chip.icon = icon

    local text = chip:CreateFontString(nil, "OVERLAY", Theme.fonts.SUB)
    text:SetPoint("LEFT", icon, "RIGHT", 3, 0)
    text:SetText(labelText)
    chip.label = text

    -- Size chip to its text (icon + gaps + text + right padding).
    chip:SetWidth(text:GetStringWidth() + 34)

    local function applyVisual(self)
        local on = self:GetChecked()
        if on then
            -- Clear "on" tint: lifted slate fill + gold border so the active
            -- state reads at a glance, not just from the checkmark.
            self:SetBackdropColor(Theme:Color("CARD_HOVER"))
            self:SetBackdropBorderColor(Theme:Color("GOLD"))
            icon:Show()
            text:SetTextColor(Theme:Color("GOLD_TEXT"))
        else
            self:SetBackdropColor(Theme:Color("INSET"))
            self:SetBackdropBorderColor(Theme:Color("BORDER"))
            icon:Hide()
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
-- readout (e.g. "%d s"). displayMul scales the value for DISPLAY only (e.g.
-- 1000 to show seconds as ms) without changing the stored value. Exposes
-- :SetValue/:GetValue like a Slider.
function TabManager:CreateSlider(parent, labelText, tooltipText, settingKey, minV, maxV, step, valueFormat, displayMul)
    local Theme = TRP3FW.Theme
    valueFormat = valueFormat or "%d"
    displayMul = displayMul or 1

    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(560, 22)

    local label = row:CreateFontString(nil, "ARTWORK", Theme.fonts.LABEL)
    label:SetPoint("LEFT", 0, 0)
    label:SetText(labelText)
    label:SetTextColor(Theme:Color("TEXT_PRIMARY"))
    row.label = label

    -- Fixed-width readout so the value never gets clipped, with clearance from
    -- the slider so the thumb at max value can't overlap the text.
    local readout = row:CreateFontString(nil, "ARTWORK", Theme.fonts.LABEL)
    readout:SetPoint("RIGHT", 0, 0)
    readout:SetWidth(52)
    readout:SetJustifyH("RIGHT")
    readout:SetTextColor(Theme:Color("GOLD_TEXT"))
    row.readout = readout

    local slider = CreateFrame("Slider", nil, row)
    slider:SetPoint("LEFT", label, "RIGHT", 12, 0)
    slider:SetPoint("RIGHT", readout, "LEFT", -14, 0)
    slider:SetHeight(14)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT"); track:SetPoint("RIGHT")
    track:SetHeight(4)
    track:SetTexture(WHITE8X8)
    track:SetColorTexture(Theme:Color("TRACK"))

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE8X8)
    thumb:SetSize(14, 14)
    thumb:SetColorTexture(Theme:Color("GOLD_TEXT"))
    slider:SetThumbTexture(thumb)
    -- Round the thumb with a circular mask (WHITE8X8 is otherwise a square).
    local thumbMask = slider:CreateMaskTexture()
    thumbMask:SetTexture(Theme.ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    thumbMask:SetAllPoints(thumb)
    thumb:AddMaskTexture(thumbMask)

    -- Fill: anchor its RIGHT edge to the THUMB rather than computing a width from
    -- the slider's size. WoW positions the thumb correctly for the current value
    -- regardless of layout timing, so the fill tracks it automatically -- this
    -- avoids the "bar overshoots until you drag it" bug caused by GetWidth()
    -- returning a stale/zero value during the first RefreshUI pass.
    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetPoint("RIGHT", thumb, "CENTER")
    fill:SetHeight(4)
    fill:SetTexture(WHITE8X8)
    fill:SetColorTexture(Theme:Color("GOLD"))
    row.fill = fill

    slider:SetScript("OnValueChanged", function(self, value)
        readout:SetText(string.format(valueFormat, value * displayMul))
        if row._onChange then row._onChange(value) end
    end)

    -- Proxy the row so RefreshUI can treat it like a slider via row:SetValue().
    function row:SetValue(v) slider:SetValue(v) end
    function row:GetValue() return slider:GetValue() end
    function row:SetOnChange(fn) self._onChange = fn end
    -- Compatibility shim: RefreshUI's numeric-edit loop calls :SetText(tostring(v))
    -- on uiElements[key]. Accept that here so a slider can transparently replace an
    -- edit box without changing the shared refresh path.
    function row:SetText(v) local n = tonumber(v); if n then slider:SetValue(n) end end
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

-- A skinned dropdown. Returns a real UIDropDownMenuTemplate frame (so all the
-- existing UIDropDownMenu_Initialize / _SetText / Enable/DisableDropDown calls
-- and RefreshUI's dropdown handling keep working unchanged) but hides the
-- default Blizzard textures and overlays a slate backdrop + gold chevron so it
-- matches the kit. Signature mirrors CreateDropdown: returns dropdown, label.
function TabManager:CreateSkinnedDropdown(parent, labelText, tooltipText, width, settingKey)
    local Theme = TRP3FW.Theme
    width = width or 200

    local label = parent:CreateFontString(nil, "ARTWORK", Theme.fonts.LABEL)
    label:SetText(labelText or "")
    label:SetTextColor(Theme:Color("TEXT_SECONDARY"))

    -- UIDropDownMenuTemplate relies on NAMED child frames ($parentText,
    -- $parentButton, ...); a nil name makes GetName() nil and those lookups
    -- fail. Give each dropdown a unique global name.
    self._dropdownCount = (self._dropdownCount or 0) + 1
    local dropdownName = "TRP3FW_SkinnedDropdown" .. self._dropdownCount
    local dropdown = CreateFrame("Frame", dropdownName, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dropdown, width)
    dropdown.label = label
    label:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 16, 3)

    -- Hide the default Blizzard dropdown art.
    local dl = _G[dropdownName .. "Left"]
    local dm = _G[dropdownName .. "Middle"]
    local dr = _G[dropdownName .. "Right"]
    if dl then dl:SetAlpha(0) end
    if dm then dm:SetAlpha(0) end
    if dr then dr:SetAlpha(0) end

    -- Slate backdrop over the dropdown's clickable area.
    local skin = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
    skin:SetPoint("TOPLEFT", 16, -2)
    skin:SetPoint("BOTTOMRIGHT", -18, 6)
    skin:SetBackdrop(Theme.BACKDROP_CHIP)
    skin:SetBackdropColor(Theme:Color("CARD"))
    skin:SetBackdropBorderColor(Theme:Color("BORDER_STRONG"))
    skin:SetFrameLevel(dropdown:GetFrameLevel())  -- sit below the invisible button
    dropdown.skin = skin

    -- Recolor the visible text and chevron to match.
    local text = _G[dropdownName .. "Text"]
    if text then text:SetTextColor(Theme:Color("TEXT_PRIMARY")) end
    local btn = _G[dropdownName .. "Button"]
    if btn then
        local nt = btn:GetNormalTexture(); if nt then nt:SetVertexColor(Theme:Color("GOLD")) end
        local pt = btn:GetPushedTexture(); if pt then pt:SetVertexColor(Theme:Color("GOLD")) end
    end

    local level = TRP3FW.SETTING_LEVELS and TRP3FW.SETTING_LEVELS[settingKey] or 4
    dropdown.complexityLevel = level
    dropdown.settingKey = settingKey
    dropdown.EnableDropDown = function(self) UIDropDownMenu_EnableDropDown(self); skin:SetBackdropBorderColor(Theme:Color("BORDER_STRONG")) end
    dropdown.DisableDropDown = function(self) UIDropDownMenu_DisableDropDown(self); skin:SetBackdropBorderColor(Theme:Color("BORDER")) end
    table.insert(self.complexityWidgets, dropdown)

    -- Only attach a tooltip when there's a label to title it (nil-label
    -- dropdowns like the per-row override selectors get none).
    if labelText and (tooltipText or level > 1) then
        local tip = self:AppendDefaultToTooltip(tooltipText, settingKey, level)
        dropdown:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        dropdown:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return dropdown, label
end

-- A skinned push button: slate fill + border, gold label, hover lift. Pass
-- isPrimary=true for the gold-accented primary action (e.g. Close/Save). Exposes
-- SetText/SetScript like a normal Button and a SetOnClick convenience.
function TabManager:CreateButton(parent, text, width, isPrimary)
    local Theme = TRP3FW.Theme

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 100, 24)
    btn:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })

    local fs = btn:CreateFontString(nil, "OVERLAY", Theme.fonts.LABEL)
    fs:SetPoint("CENTER")
    fs:SetText(text)
    btn:SetFontString(fs)
    btn.text = fs

    local function base(self)
        if isPrimary then
            self:SetBackdropColor(Theme:Color("CARD_HOVER"))
            self:SetBackdropBorderColor(Theme:Color("GOLD"))
            fs:SetTextColor(Theme:Color("GOLD_TEXT"))
        else
            self:SetBackdropColor(Theme:Color("CARD"))
            self:SetBackdropBorderColor(Theme:Color("BORDER_STRONG"))
            fs:SetTextColor(Theme:Color("TEXT_PRIMARY"))
        end
    end
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(Theme:Color("BORDER_STRONG"))
        self:SetBackdropBorderColor(Theme:Color("GOLD"))
    end)
    btn:SetScript("OnLeave", base)
    btn:SetScript("OnMouseDown", function(self) fs:SetPoint("CENTER", 0, -1) end)
    btn:SetScript("OnMouseUp", function(self) fs:SetPoint("CENTER", 0, 0) end)
    base(btn)

    function btn:SetOnClick(fn) self:SetScript("OnClick", fn) end
    return btn
end

-- A skinned single-line edit box in a slate well, with a label above it. Named
-- CreateSkinnedEditBox (not CreateEditBox) so the classic numeric InputBoxTemplate
-- helper used by not-yet-migrated tabs keeps working. numeric defaults to false
-- (whitelist/name fields are text). Registers with complexity/tooltip.
function TabManager:CreateSkinnedEditBox(parent, labelText, tooltipText, width, settingKey, numeric)
    local Theme = TRP3FW.Theme
    width = width or 120

    local label = parent:CreateFontString(nil, "ARTWORK", Theme.fonts.LABEL)
    label:SetText(labelText)
    label:SetTextColor(Theme:Color("TEXT_SECONDARY"))

    local well = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    well:SetSize(width, 22)
    well:SetBackdrop(Theme.BACKDROP_CHIP)
    well:SetBackdropColor(Theme:Color("INSET"))
    well:SetBackdropBorderColor(Theme:Color("BORDER_STRONG"))

    local editBox = CreateFrame("EditBox", nil, well)
    editBox:SetPoint("TOPLEFT", 6, -2)
    editBox:SetPoint("BOTTOMRIGHT", -6, 2)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(Theme.fonts.LABEL)
    editBox:SetTextColor(Theme:Color("TEXT_PRIMARY"))
    if numeric then editBox:SetNumeric(true); editBox:SetMaxLetters(6) end
    editBox.label = label
    editBox.well = well

    label:SetPoint("BOTTOMLEFT", well, "TOPLEFT", 0, 4)

    -- Focus highlight on the well border.
    editBox:SetScript("OnEditFocusGained", function() well:SetBackdropBorderColor(Theme:Color("GOLD")) end)
    editBox:SetScript("OnEditFocusLost", function() well:SetBackdropBorderColor(Theme:Color("BORDER_STRONG")) end)
    editBox:SetScript("OnEscapePressed", editBox.ClearFocus)

    local level = TRP3FW.SETTING_LEVELS and TRP3FW.SETTING_LEVELS[settingKey] or 4
    editBox.complexityLevel = level
    editBox.settingKey = settingKey
    table.insert(self.complexityWidgets, editBox)

    if tooltipText or level > 1 then
        local tip = self:AppendDefaultToTooltip(tooltipText, settingKey, level)
        editBox:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        editBox:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return editBox, label
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

    -- If switching to a live-updating tab (status or dashboard), ensure the
    -- background timer is running. The ticker itself checks the active tab.
    if (id == "status" or id == "dashboard") and TRP3FW.StartStatusUpdates then
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
