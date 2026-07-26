-- ui/debugwindow.lua
-- Dedicated debug output window

local addonName, TRP3FW = ...

-- Create debug window frame
local debugFrame = CreateFrame("Frame", "TRP3FW_DebugWindow", UIParent, "BasicFrameTemplateWithInset")
debugFrame:SetSize(600, 400)
debugFrame:SetPoint("CENTER")
debugFrame:SetMovable(true)
debugFrame:EnableMouse(true)
debugFrame:RegisterForDrag("LeftButton")
debugFrame:SetScript("OnDragStart", debugFrame.StartMoving)
debugFrame:SetScript("OnDragStop", debugFrame.StopMovingOrSizing)
debugFrame:SetFrameStrata("HIGH")
debugFrame:Hide()

-- Title
debugFrame.title = debugFrame:CreateFontString(nil, "OVERLAY")
debugFrame.title:SetFontObject("GameFontHighlight")
debugFrame.title:SetPoint("LEFT", debugFrame.TitleBg, "LEFT", 5, 0)
debugFrame.title:SetText("TRP3 Firewall - Debug Output")

-- Debug message storage and filtering
local debugMessages = {}
local currentFilter = "all"
local CATEGORY_LABELS = {
    { key = "all", label = "All" },
    { key = "channel", label = "Channel" },
    { key = "whisper", label = "Whisper" },
    { key = "who", label = "WHO" },
    { key = "phase", label = "Phase" },
    { key = "location", label = "Location" },
    { key = "decision", label = "Decision" },
    { key = "hooks", label = "Hooks" },
    { key = "cache", label = "Cache" },
    { key = "send", label = "Send" },
    { key = "ui", label = "UI" },
    { key = "utils", label = "Utils" },
    { key = "security", label = "Security" },
    { key = "ghost", label = "Ghost" },
    { key = "spvp", label = "SPVP" },
    { key = "cleanname", label = "Names" },
    { key = "core", label = "Core" },
    { key = "general", label = "General" },
    { key = "refactor", label = "Refactor" },
}

-- Categories that share a filter bucket (see DEBUG_CATEGORIES in core/utils.lua)
local CATEGORY_ALIASES = {
    init = "core",
    pipeline = "core",
    queue = "core",
}

local CATEGORY_LOOKUP = {}
for _, entry in ipairs(CATEGORY_LABELS) do
    CATEGORY_LOOKUP[entry.key] = entry.label
end

-- Create ScrollFrame
local scrollFrame = CreateFrame("ScrollFrame", nil, debugFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", debugFrame, "TOPLEFT", 4, -24)
scrollFrame:SetPoint("BOTTOMRIGHT", debugFrame, "BOTTOMRIGHT", -26, 38)  -- Leave space for buttons at bottom

-- Create EditBox for output
local editBox = CreateFrame("EditBox", nil, scrollFrame)
editBox:SetMultiLine(true)
editBox:SetAutoFocus(false)
editBox:SetFontObject("ChatFontNormal")
editBox:SetWidth(scrollFrame:GetWidth())
editBox:SetMaxLetters(0) -- Unlimited
scrollFrame:SetScrollChild(editBox)

-- Store reference
debugFrame.editBox = editBox

local refreshPending = false

-- Forward declaration: RefreshDebugOutput below reads this to decide whether to
-- pin the view to the bottom, but the CheckButton itself is created further down
-- (it anchors to the frame's bottom edge, after the scroll frame). Without this
-- line the name inside RefreshDebugOutput resolved to a nil GLOBAL, so the
-- auto-scroll branch never ran no matter how the checkbox was set.
local autoScrollCheck

-- Helper to rebuild output based on current filter (Optimized via table.concat)
local function RefreshDebugOutput()
    refreshPending = false
    if not debugFrame:IsShown() then return end

    local lines = {}
    local count = 0

    -- Only process the last 1000 messages to keep UI responsive even if array grows
    -- (Though array is capped at 1000 anyway)
    local startIdx = math.max(1, #debugMessages - 1000)

    for i = startIdx, #debugMessages do
        local entry = debugMessages[i]
        if currentFilter == "all" or entry.category == currentFilter then
            count = count + 1
            lines[count] = entry.text
        end
    end

    local text = table.concat(lines, "\n")
    editBox:SetText(text)

    if autoScrollCheck and autoScrollCheck:GetChecked() then
        -- Scroll to bottom after layout update
        C_Timer.After(0.01, function()
            local scrollRange = scrollFrame:GetVerticalScrollRange()
            scrollFrame:SetVerticalScroll(scrollRange)
        end)
    end
end

-- Request a refresh (Debounced)
local function RequestDebugRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.1, RefreshDebugOutput) -- 10Hz max refresh rate
end

-- Clear button
local clearButton = CreateFrame("Button", nil, debugFrame, "UIPanelButtonTemplate")
clearButton:SetSize(80, 22)
clearButton:SetPoint("BOTTOMRIGHT", debugFrame, "BOTTOMRIGHT", -8, 8)
clearButton:SetText("Clear")
clearButton:SetScript("OnClick", function()
    debugMessages = {}
    editBox:SetText("")
    editBox:SetCursorPosition(0)
end)

-- Copy button
local copyButton = CreateFrame("Button", nil, debugFrame, "UIPanelButtonTemplate")
copyButton:SetSize(80, 22)
copyButton:SetPoint("RIGHT", clearButton, "LEFT", -6, 0)
copyButton:SetText("Copy")
copyButton:SetScript("OnClick", function()
    editBox:HighlightText(0, editBox:GetNumLetters())
    editBox:SetFocus()
end)

-- Auto-scroll checkbox
-- Assignment, not `local` -- the forward declaration above is the one
-- RefreshDebugOutput closes over. A second `local` here would shadow it.
autoScrollCheck = CreateFrame("CheckButton", nil, debugFrame, "UICheckButtonTemplate")
autoScrollCheck:SetPoint("BOTTOMLEFT", debugFrame, "BOTTOMLEFT", 8, 8)
autoScrollCheck.text = autoScrollCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
autoScrollCheck.text:SetPoint("LEFT", autoScrollCheck, "RIGHT", 0, 0)
autoScrollCheck.text:SetText("Auto-scroll")
autoScrollCheck:SetChecked(true)
debugFrame.autoScrollCheck = autoScrollCheck

-- Category filter dropdown
local filterDropdown = CreateFrame("Frame", "TRP3FW_DebugFilter", debugFrame, "UIDropDownMenuTemplate")
filterDropdown:SetPoint("BOTTOMLEFT", autoScrollCheck, "BOTTOMRIGHT", 160, 0)
UIDropDownMenu_SetWidth(filterDropdown, 140)

UIDropDownMenu_Initialize(filterDropdown, function(self, level)
    for _, entry in ipairs(CATEGORY_LABELS) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = entry.label
        info.value = entry.key
        info.func = function()
            currentFilter = entry.key
            UIDropDownMenu_SetText(filterDropdown, entry.label)
            RefreshDebugOutput()
        end
        UIDropDownMenu_AddButton(info, level)
    end
end)
UIDropDownMenu_SetText(filterDropdown, CATEGORY_LOOKUP.all)

-- Function to add debug message
function TRP3FW:AddDebugMessage(msg, category, timestamp)
    -- Messages accumulate whenever debug mode is on, even with the window closed, so the
    -- window can be opened after an event to read the backlog.

    local rawCategory = category or ""
    local categoryKey = CATEGORY_ALIASES[rawCategory]
        or (CATEGORY_LOOKUP[rawCategory] and rawCategory)
        or "general"
    local timeStr = timestamp or date("%H:%M:%S")
    local entryText = string.format("[%s] %s", timeStr, TRP3FW:Redact(msg))

    table.insert(debugMessages, { text = entryText, category = categoryKey })

    -- Limit total lines to prevent memory bloat (keep last 1000 lines)
    if #debugMessages > 1000 then
        -- Batch remove 100 at a time to avoid O(N) shift overhead on every insert
        for _ = 1, 100 do
            table.remove(debugMessages, 1)
        end
    end

    -- OPTIMIZATION: Only refresh when window is visible, and debounce updates
    if debugFrame:IsShown() then
        RequestDebugRefresh()
    end
end

-- Render the buffered backlog whenever the window becomes visible. RefreshDebugOutput()
-- bails while the frame is hidden, so the refresh has to happen after Show().
debugFrame:SetScript("OnShow", function()
    RefreshDebugOutput()
end)

-- Function to toggle debug window
function TRP3FW:ToggleDebugWindow()
    if debugFrame:IsShown() then
        debugFrame:Hide()
    else
        debugFrame:Show()  -- OnShow renders the backlog
    end
end

-- Function to show debug window
function TRP3FW:ShowDebugWindow()
    if debugFrame:IsShown() then
        RefreshDebugOutput()
    else
        debugFrame:Show()  -- OnShow renders the backlog
    end
end

-- Function to hide debug window
function TRP3FW:HideDebugWindow()
    debugFrame:Hide()
end

-- Store frame reference
TRP3FW.debugWindow = debugFrame
