-- ui/historywindow.lua
-- Performance History Graphs

local addonName, TRP3FW = ...

-- Create history window frame
local historyFrame = CreateFrame("Frame", "TRP3FW_HistoryWindow", UIParent, "BasicFrameTemplateWithInset")
historyFrame:SetSize(800, 650)  -- Increased from 600 to 650
historyFrame:SetPoint("CENTER")
historyFrame:SetMovable(true)
historyFrame:EnableMouse(true)
historyFrame:RegisterForDrag("LeftButton")
historyFrame:SetScript("OnDragStart", historyFrame.StartMoving)
historyFrame:SetScript("OnDragStop", historyFrame.StopMovingOrSizing)
historyFrame:SetFrameStrata("HIGH")
historyFrame:Hide()

-- Title
historyFrame.title = historyFrame:CreateFontString(nil, "OVERLAY")
historyFrame.title:SetFontObject("GameFontHighlight")
historyFrame.title:SetPoint("LEFT", historyFrame.TitleBg, "LEFT", 5, 0)
historyFrame.title:SetText("TRP3 Firewall - Performance History")

-- TODO: #7 - Context Filter (defined here, created after graphs below)
local currentFilter = "All Contexts"
local filterDropdown -- Will be created after graphs

-- Forward declarations for functions used in button callbacks
local UpdateHistoryGraphs
local lastRenderedTimestamp

-- Helper to draw a line between two points
local function DrawLine(parent, startX, startY, endX, endY, thickness, r, g, b, alpha)
    local line = parent:CreateLine()
    line:SetThickness(thickness)
    line:SetColorTexture(r, g, b, alpha)
    line:SetStartPoint("BOTTOMLEFT", startX, startY)
    line:SetEndPoint("BOTTOMLEFT", endX, endY)
    return line
end

-- TODO: #12 - Performance Budget Definitions
-- Get current refresh rate and calculate frame budget dynamically
local function GetLatencyBudget()
    -- Get current refresh rate (returnsHz, e.g., 60, 144, 165)
    local currentRate = GetCVar("refreshRate")
    if currentRate then
        local hz = tonumber(currentRate)
        if hz and hz > 0 then
            return 1000 / hz -- Convert Hz to milliseconds per frame
        end
    end
    -- Fallback to 60 FPS if we can't determine refresh rate
    return 16.67
end

local BUDGETS = {
    latency = nil,       -- Calculated dynamically based on refresh rate
    load = 5.0,          -- 5% CPU per frame
    throughput = 100,    -- 100 req/sec max
    memory = 20480       -- 20 MB (20480 KB)
}

-- Graph Widget Constructor
local function CreateGraphWidget(parent, title, width, height)
    local graph = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    graph:SetSize(width, height)
    graph:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    graph:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    graph:SetBackdropBorderColor(0.4, 0.4, 0.4)

    -- Title
    graph.title = graph:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    graph.title:SetPoint("TOPLEFT", 10, -10)
    graph.title:SetText(title)

    -- Axis Labels
    graph.maxLabel = graph:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    graph.maxLabel:SetPoint("TOPRIGHT", -10, -10)
    graph.maxLabel:SetTextColor(0.7, 0.7, 0.7)

    graph.minLabel = graph:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    graph.minLabel:SetPoint("BOTTOMRIGHT", -10, 10)
    graph.minLabel:SetTextColor(0.7, 0.7, 0.7)

    -- TODO: #12 - Budget Line and Status Indicator
    -- Budget reference line (horizontal yellow line)
    graph.budgetLine = graph:CreateTexture(nil, "OVERLAY")
    graph.budgetLine:SetTexture("Interface\\Buttons\\WHITE8X8")
    graph.budgetLine:SetVertexColor(1, 1, 0, 0.6) -- Yellow warning line
    graph.budgetLine:SetHeight(2)
    graph.budgetLine:Hide()

    -- Status indicator dot (next to title)
    graph.statusDot = graph:CreateTexture(nil, "OVERLAY")
    graph.statusDot:SetTexture("Interface\\Buttons\\WHITE8X8")
    graph.statusDot:SetSize(8, 8)
    graph.statusDot:SetPoint("LEFT", graph.title, "RIGHT", 5, 0)
    graph.statusDot:Hide()

    -- TODO: #1 - Visual Legend
    -- Create legend showing what colors mean (positioned below graph)
    graph.legendText = graph:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    graph.legendText:SetPoint("BOTTOM", graph, "BOTTOM", 0, 5)

    -- Check if this graph has dual series (avg + peak) based on title
    local hasPeak = title:find("Green:Avg Red:Peak")

    if hasPeak then
        -- Dual series: show both avg and peak indicators
        -- Green box for Avg (left)
        graph.legendAvgBox = graph:CreateTexture(nil, "OVERLAY")
        graph.legendAvgBox:SetTexture("Interface\\Buttons\\WHITE8X8")
        graph.legendAvgBox:SetVertexColor(0, 1, 0, 0.8)
        graph.legendAvgBox:SetSize(10, 10)
        graph.legendAvgBox:SetPoint("RIGHT", graph.legendText, "LEFT", -5, 0)

        -- Red box for Peak (right)
        graph.legendPeakBox = graph:CreateTexture(nil, "OVERLAY")
        graph.legendPeakBox:SetTexture("Interface\\Buttons\\WHITE8X8")
        graph.legendPeakBox:SetVertexColor(1, 0, 0, 0.8)
        graph.legendPeakBox:SetSize(10, 10)
        graph.legendPeakBox:SetPoint("LEFT", graph.legendText, "RIGHT", 5, 0)

        graph.legendText:SetText("|cff00ff00Avg|r  |cffff0000Peak|r")
    else
        -- Single series: show only avg indicator
        graph.legendAvgBox = graph:CreateTexture(nil, "OVERLAY")
        graph.legendAvgBox:SetTexture("Interface\\Buttons\\WHITE8X8")
        graph.legendAvgBox:SetVertexColor(0, 1, 0, 0.8)
        graph.legendAvgBox:SetSize(10, 10)
        graph.legendAvgBox:SetPoint("RIGHT", graph.legendText, "LEFT", -5, 0)

        graph.legendText:SetText("|cff00ff00Value|r")
    end

    -- Data storage - pool of bar textures (50 max)
    graph.bars = {} -- Each entry: { avgBar, peakBar }

    -- TODO: #2 - Bar Tooltips
    -- Create shared tooltip frame for this graph
    graph.tooltip = CreateFrame("Frame", nil, graph, "BackdropTemplate")
    graph.tooltip:SetFrameStrata("TOOLTIP")
    graph.tooltip:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    graph.tooltip:SetBackdropColor(0, 0, 0, 0.9)
    graph.tooltip:SetBackdropBorderColor(0.4, 0.4, 0.4)
    graph.tooltip.text = graph.tooltip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    graph.tooltip.text:SetPoint("CENTER", 2, 0)
    graph.tooltip.text:SetJustifyH("LEFT")
    graph.tooltip:Hide()

    -- Status Text
    graph.statusText = graph:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    graph.statusText:SetPoint("CENTER")
    graph.statusText:SetTextColor(0.5, 0.5, 0.5)
    graph.statusText:Hide()

    -- Update function - Bar Graph Implementation
    function graph:SetData(dataPoints, valueFunc1, valueFunc2)
        -- Hide all existing bars
        for _, barPair in ipairs(self.bars) do
            if barPair.avgBar then barPair.avgBar:Hide() end
            if barPair.peakBar then barPair.peakBar:Hide() end
        end

        if not dataPoints or #dataPoints == 0 then
            if TRP3FW_Settings and not TRP3FW_Settings.performanceHistoryEnabled then
                self.statusText:SetText("|cffff0000History Tracking Disabled|r")
            else
                self.statusText:SetText("Waiting for data...")
            end
            self.statusText:Show()
            self.maxLabel:SetText("")
            self.minLabel:SetText("")
            return
        end

        self.statusText:Hide()

        -- Calculate value range for scaling
        local minVal, maxVal = math.huge, -math.huge
        for _, entry in ipairs(dataPoints) do
            local v1 = valueFunc1(entry) or 0
            minVal = math.min(minVal, v1)
            maxVal = math.max(maxVal, v1)
            if valueFunc2 then
                local v2 = valueFunc2(entry) or 0
                minVal = math.min(minVal, v2)
                maxVal = math.max(maxVal, v2)
            end
        end

        -- Add padding to range
        local range = maxVal - minVal
        if range == 0 then range = 1 end -- Avoid div by zero
        maxVal = maxVal + (range * 0.1)
        minVal = math.max(0, minVal - (range * 0.1))
        range = maxVal - minVal

        -- Update labels
        self.maxLabel:SetText(string.format("%.2f", maxVal))
        self.minLabel:SetText(string.format("%.2f", minVal))

        -- Bar graph dimensions
        local width = self:GetWidth() - 20
        local height = self:GetHeight() - 40
        local bottom = 20
        local left = 10
        local maxBars = 50
        local barWidth = width / maxBars
        local barSpacing = 1 -- 1 pixel gap between bars

        -- Draw bars (newest on the right)
        for i = 1, #dataPoints do
            local entry = dataPoints[i]
            local val1 = valueFunc1(entry) or 0
            local val2 = valueFunc2 and (valueFunc2(entry) or 0) or nil

            -- Calculate bar position (right-to-left from newest)
            local barIndex = maxBars - (#dataPoints - i)
            if barIndex < 1 then break end -- Skip if too many data points

            local x = left + (barIndex - 1) * barWidth

            -- Get or create bar pair
            if not self.bars[i] then
                self.bars[i] = {}
                self.bars[i].avgBar = self:CreateTexture(nil, "ARTWORK")
                self.bars[i].avgBar:SetTexture("Interface\\Buttons\\WHITE8X8")

                -- Create invisible mouse-over frame for tooltip
                local hoverFrame = CreateFrame("Frame", nil, self)
                hoverFrame:EnableMouse(true)
                self.bars[i].hoverFrame = hoverFrame

                -- Set scripts ONCE - data will be stored on frame, not in closure
                hoverFrame:SetScript("OnEnter", function(frame)
                    if not frame.tooltipData then return end

                    local tooltipText = string.format(
                        "|cffaaaaaa%s|r\n|cff00ff00Avg: %.2f|r%s",
                        date("%Y-%m-%d %H:%M:%S", frame.tooltipData.timestamp),
                        frame.tooltipData.avg,
                        frame.tooltipData.peak and string.format("\n|cffff0000Peak: %.2f|r", frame.tooltipData.peak) or ""
                    )

                    self.tooltip.text:SetText(tooltipText)
                    self.tooltip:SetSize(
                        self.tooltip.text:GetStringWidth() + 16,
                        self.tooltip.text:GetStringHeight() + 12
                    )
                    self.tooltip:ClearAllPoints()
                    self.tooltip:SetPoint("BOTTOM", frame, "TOP", 0, 5)
                    self.tooltip:Show()
                end)

                hoverFrame:SetScript("OnLeave", function()
                    self.tooltip:Hide()
                end)
            end

            -- Ensure peakBar exists if needed (lazy creation)
            if valueFunc2 and not self.bars[i].peakBar then
                self.bars[i].peakBar = self:CreateTexture(nil, "ARTWORK")
                self.bars[i].peakBar:SetTexture("Interface\\Buttons\\WHITE8X8")
            end

            local avgBar = self.bars[i].avgBar
            local peakBar = self.bars[i].peakBar
            local hoverFrame = self.bars[i].hoverFrame

            -- Calculate heights (normalized to range)
            local avgHeight = ((val1 - minVal) / range) * height
            local peakHeight = val2 and ((val2 - minVal) / range) * height or 0

            -- Average bar (green) - always draw from bottom
            avgBar:SetVertexColor(0, 1, 0, 0.8)
            avgBar:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, bottom)
            avgBar:SetSize(barWidth - barSpacing, avgHeight)
            avgBar:Show()

            -- Peak bar (red) - draw from top of average bar if both exist
            local totalHeight = avgHeight
            if valueFunc2 and peakBar then
                if peakHeight > avgHeight then
                    -- Peak is higher - draw red from top of green
                    peakBar:SetVertexColor(1, 0, 0, 0.8)
                    peakBar:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, bottom + avgHeight)
                    peakBar:SetSize(barWidth - barSpacing, peakHeight - avgHeight)
                    peakBar:Show()
                    totalHeight = peakHeight
                else
                    -- Peak is same or lower - hide it (shouldn't happen but handle gracefully)
                    peakBar:Hide()
                end
            end

            -- TODO: #2 - Position hover frame and store tooltip data (no closure!)
            hoverFrame:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, bottom)
            hoverFrame:SetSize(barWidth - barSpacing, totalHeight)
            hoverFrame:Show()

            -- Store data on frame instead of closure to prevent memory leak
            if not hoverFrame.tooltipData then
                hoverFrame.tooltipData = {}
            end
            hoverFrame.tooltipData.timestamp = entry.timestamp
            hoverFrame.tooltipData.avg = val1
            hoverFrame.tooltipData.peak = val2
        end

        -- Hide unused bars (important for preventing memory growth!)
        for i = #dataPoints + 1, #self.bars do
            if self.bars[i] then
                if self.bars[i].avgBar then self.bars[i].avgBar:Hide() end
                if self.bars[i].peakBar then self.bars[i].peakBar:Hide() end
                if self.bars[i].hoverFrame then
                    self.bars[i].hoverFrame:Hide()
                    self.bars[i].hoverFrame.tooltipData = nil -- Clear data reference
                end
            end
        end

        -- TODO: #12 - Update budget indicators
        -- Determine metric type from title and get appropriate budget
        local metricType = nil
        local budget = nil
        if self.title:GetText():find("Latency") then
            metricType = "latency"
            budget = GetLatencyBudget() -- Dynamic based on refresh rate
        elseif self.title:GetText():find("CPU Load") then
            metricType = "load"
            budget = BUDGETS.load
        elseif self.title:GetText():find("Throughput") then
            metricType = "throughput"
            budget = BUDGETS.throughput
        elseif self.title:GetText():find("Memory") then
            metricType = "memory"
            budget = BUDGETS.memory
        end

        if budget and #dataPoints > 0 then
            local latestEntry = dataPoints[#dataPoints]
            local currentAvg = valueFunc1(latestEntry) or 0
            local currentPeak = valueFunc2 and (valueFunc2(latestEntry) or 0) or currentAvg

            -- Draw budget line if within visible range
            local budgetY = bottom + ((budget - minVal) / range) * height
            if budgetY >= bottom and budgetY <= (bottom + height) then
                self.budgetLine:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", left, budgetY)
                self.budgetLine:SetWidth(width)
                self.budgetLine:Show()
            else
                self.budgetLine:Hide()
            end

            -- Update status indicator dot
            local overBudget = currentPeak > budget
            local nearBudget = currentPeak > (budget * 0.8)

            if overBudget then
                self.statusDot:SetVertexColor(1, 0, 0, 1) -- Red: Over budget
            elseif nearBudget then
                self.statusDot:SetVertexColor(1, 1, 0, 1) -- Yellow: Warning (>80%)
            else
                self.statusDot:SetVertexColor(0, 1, 0, 1) -- Green: Good
            end
            self.statusDot:Show()
        else
            self.budgetLine:Hide()
            self.statusDot:Hide()
        end
    end

    return graph
end

-- Create Graphs
local graphHeight = 170  -- Reduced from 180 to avoid budget line overlap
local graphWidth = 380
local topY = -40

local graphMemory = CreateGraphWidget(historyFrame, "Memory Usage (KB)", graphWidth, graphHeight)
graphMemory:SetPoint("TOPLEFT", 10, topY)

local graphLatency = CreateGraphWidget(historyFrame, "Latency (ms) - Green:Avg Red:Peak", graphWidth, graphHeight)
graphLatency:SetPoint("TOPRIGHT", -10, topY)

local graphLoad = CreateGraphWidget(historyFrame, "CPU Load (%) - Green:Avg Red:Peak", graphWidth, graphHeight)
graphLoad:SetPoint("TOPLEFT", graphMemory, "BOTTOMLEFT", 0, -20) -- 20px gap below top row

local graphThroughput = CreateGraphWidget(historyFrame, "Throughput (req/sec) - Green:Avg Red:Peak", graphWidth, graphHeight)
graphThroughput:SetPoint("TOPLEFT", graphLatency, "BOTTOMLEFT", 0, -20) -- 20px gap below top row

-- TODO: #7 - Context Filter Dropdown (positioned between graphs and Top 5)
filterDropdown = CreateFrame("Frame", "TRP3FW_HistoryFilterDropdown", historyFrame, "UIDropDownMenuTemplate")
filterDropdown:SetPoint("TOPLEFT", graphLoad, "BOTTOMLEFT", 0, -5)

-- Show Peak Checkbox
local peakCheckbox = CreateFrame("CheckButton", nil, historyFrame, "ChatConfigCheckButtonTemplate")
peakCheckbox:SetPoint("LEFT", filterDropdown, "RIGHT", 180, 0)
peakCheckbox.Text:SetText("Show Peak")
peakCheckbox:SetChecked(true)
peakCheckbox:SetScript("OnClick", function()
    lastRenderedTimestamp = 0
    UpdateHistoryGraphs()
end)

-- Clear History Button (same level as dropdown)
local clearButton = CreateFrame("Button", nil, historyFrame, "UIPanelButtonTemplate")
clearButton:SetSize(120, 22)
clearButton:SetPoint("LEFT", filterDropdown, "RIGHT", 440, 2)
clearButton:SetText("Clear History")
clearButton:SetScript("OnClick", function()
    if TRP3FW.sessionStats and TRP3FW.sessionStats.performanceHistory then
        -- Clear the history array
        TRP3FW.sessionStats.performanceHistory = {}

        -- Force an immediate refresh to show empty state
        lastRenderedTimestamp = 0
        UpdateHistoryGraphs()

        print("|cff00ff00TRP3 Firewall:|r Performance history cleared.")
    end
end)

-- TODO: #12 - Budget Indicators Panel (positioned below dropdown)
-- 2 rows x 4 columns layout
local budgetPanel = CreateFrame("Frame", nil, historyFrame, "BackdropTemplate")
budgetPanel:SetSize(760, 50)  -- Full width, compact height
budgetPanel:SetPoint("TOPLEFT", filterDropdown, "BOTTOMLEFT", 15, -10)
budgetPanel:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
budgetPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
budgetPanel:SetBackdropBorderColor(0.4, 0.4, 0.4)

-- Budget Panel Title
local budgetTitle = budgetPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
budgetTitle:SetPoint("TOPLEFT", 10, -8)
budgetTitle:SetText("Performance Budgets")

-- Budget Status Cells (4 columns in a single row)
budgetPanel.rows = {}
local budgetLabels = {
    {key = "latency", label = "Latency", format = "%.1f ms"},
    {key = "load", label = "CPU Load", format = "%.1f%%"},
    {key = "throughput", label = "Throughput", format = "%.0f r/s"},
    {key = "memory", label = "Memory", format = "%.0f KB"}
}

local colWidth = 180
local rowHeight = 16
local startY = -25

for i, info in ipairs(budgetLabels) do
    local col = (i - 1) % 4  -- 0, 1, 2, 3

    local cell = CreateFrame("Frame", nil, budgetPanel)
    cell:SetSize(colWidth, rowHeight)
    cell:SetPoint("TOPLEFT", 10 + (col * colWidth), startY)

    -- Status dot
    local dot = cell:CreateTexture(nil, "OVERLAY")
    dot:SetTexture("Interface\\Buttons\\WHITE8X8")
    dot:SetSize(8, 8)
    dot:SetPoint("LEFT", 0, 0)

    -- Label text
    local label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 12, 0)
    label:SetWidth(65)
    label:SetJustifyH("LEFT")
    label:SetText(info.label .. ":")

    -- Current/Budget value text (combined)
    local valueText = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", 80, 0)
    valueText:SetWidth(95)
    valueText:SetJustifyH("RIGHT")

    budgetPanel.rows[info.key] = {
        dot = dot,
        label = label,
        valueText = valueText,
        format = info.format
    }
end

local function FilterDropdown_OnClick(self)
    currentFilter = self.value
    UIDropDownMenu_SetText(filterDropdown, "Filter: " .. currentFilter)
    CloseDropDownMenus()
    UpdateHistoryGraphs() -- Refresh with new filter
end

local function FilterDropdown_Initialize(self, level)
    local info = UIDropDownMenu_CreateInfo()

    -- "All Contexts" option
    info.text = "All Contexts"
    info.value = "All Contexts"
    info.func = FilterDropdown_OnClick
    info.checked = (currentFilter == "All Contexts")
    UIDropDownMenu_AddButton(info, level)

    -- Collect unique contexts from current topStats
    local contexts = {}
    if TRP3FW.sessionStats and TRP3FW.sessionStats.performance.topStats then
        for _, list in pairs(TRP3FW.sessionStats.performance.topStats) do
            if list then
                for _, entry in ipairs(list) do
                    if entry.context then
                        contexts[entry.context] = true
                    end
                end
            end
        end
    end

    -- Sort contexts alphabetically
    local contextList = {}
    for context in pairs(contexts) do
        table.insert(contextList, context)
    end
    table.sort(contextList)

    -- Add context options
    for _, context in ipairs(contextList) do
        info.text = context
        info.value = context
        info.func = FilterDropdown_OnClick
        info.checked = (currentFilter == context)
        UIDropDownMenu_AddButton(info, level)
    end
end

UIDropDownMenu_Initialize(filterDropdown, FilterDropdown_Initialize)
UIDropDownMenu_SetWidth(filterDropdown, 150)
UIDropDownMenu_SetText(filterDropdown, "Filter: All Contexts")

-- Top Stats Container
local statsContainer = CreateFrame("Frame", nil, historyFrame, "BackdropTemplate")
statsContainer:SetSize(760, 130)
statsContainer:SetPoint("TOPLEFT", budgetPanel, "BOTTOMLEFT", 0, -5)
statsContainer:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
statsContainer:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
statsContainer:SetBackdropBorderColor(0.4, 0.4, 0.4)

-- TODO: #9 - Improved Top 5 Display with bars and better formatting
local function CreateStatColumn(parent, title, index)
    local col = CreateFrame("Frame", nil, parent)
    col:SetSize(240, 120)
    local x = 10 + (index - 1) * 250
    col:SetPoint("TOPLEFT", x, 0)

    local lbl = col:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", 0, -10)
    lbl:SetText(title)

    col.rows = {}
    for i = 1, 5 do
        -- Container for each row
        local rowContainer = CreateFrame("Frame", nil, col)
        rowContainer:SetSize(235, 16)
        rowContainer:SetPoint("TOPLEFT", 5, -28 - (i * 17))

        -- Background bar showing relative magnitude
        local bar = rowContainer:CreateTexture(nil, "BACKGROUND")
        bar:SetTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetPoint("LEFT")
        bar:SetHeight(14)
        bar:SetWidth(0) -- Will be set dynamically

        -- Rank number (e.g., "#1")
        local rank = rowContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rank:SetPoint("LEFT", 2, 0)
        rank:SetWidth(20)
        rank:SetJustifyH("LEFT")
        rank:SetText(string.format("|cffcccccc#%d|r", i))

        -- Value and context text
        local text = rowContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", 24, 0)
        text:SetWidth(210)
        text:SetJustifyH("LEFT")

        col.rows[i] = {
            container = rowContainer,
            bar = bar,
            rank = rank,
            text = text
        }
    end
    return col
end

local colLat = CreateStatColumn(statsContainer, "Top 5 Latency (Peak ms)", 1)
local colCpu = CreateStatColumn(statsContainer, "Top 5 CPU (Total ms)", 2)
local colTput = CreateStatColumn(statsContainer, "Top 5 Throughput (Req/s)", 3)

-- Reusable table for budget updates to prevent allocation
local reusableBudgets = {
    latency = {budget = 0, current = 0},
    load = {budget = 0, current = 0},
    throughput = {budget = 0, current = 0},
    memory = {budget = 0, current = 0}
}

-- Update Budget Panel
local function UpdateBudgetPanel()
    if not TRP3FW.sessionStats then return end

    local history = TRP3FW.sessionStats.performanceHistory
    if not history or #history == 0 then return end

    local latest = history[#history]

    -- Update reusable table values
    reusableBudgets.latency.budget = GetLatencyBudget()
    reusableBudgets.latency.current = latest.peakLatency or 0
    
    reusableBudgets.load.budget = BUDGETS.load
    reusableBudgets.load.current = latest.maxLoad or 0
    
    reusableBudgets.throughput.budget = BUDGETS.throughput
    reusableBudgets.throughput.current = latest.peakThroughput or 0
    
    reusableBudgets.memory.budget = BUDGETS.memory
    reusableBudgets.memory.current = latest.memory or 0

    for key, data in pairs(reusableBudgets) do
        local cell = budgetPanel.rows[key]
        if cell then
            -- Calculate status
            local overBudget = data.current > data.budget
            local nearBudget = data.current > (data.budget * 0.8)

            -- Update status dot color
            if overBudget then
                cell.dot:SetVertexColor(1, 0, 0, 1) -- Red
            elseif nearBudget then
                cell.dot:SetVertexColor(1, 1, 0, 1) -- Yellow
            else
                cell.dot:SetVertexColor(0, 1, 0, 1) -- Green
            end

            -- Update combined value text (current/budget)
            local currentStr = string.format(cell.format, data.current)
            local budgetStr = string.format(cell.format, data.budget)
            cell.valueText:SetText(string.format("%s/%s", currentStr, budgetStr))
        end
    end
end

-- Value extractors (defined at file scope to avoid closure allocation)
local function ValMemory(e) return e.memory end
local function ValAvgLatency(e) return e.avgLatency end
local function ValPeakLatency(e) return e.peakLatency end
local function ValAvgLoad(e) return e.avgLoad end
local function ValMaxLoad(e) return e.maxLoad end
local function ValThroughput(e) return e.throughput end
local function ValPeakThroughput(e) return e.peakThroughput end

-- Update Function
lastRenderedTimestamp = 0
function UpdateHistoryGraphs()
    -- DEBUG: Log function entry
    if TRP3FW and TRP3FW.Debug then
        TRP3FW:Debug("[Graph] UpdateHistoryGraphs called", "ui")
    end

    local sessionStats = TRP3FW.sessionStats
    if not sessionStats then
        if TRP3FW and TRP3FW.Debug then
            TRP3FW:Debug("[Graph] sessionStats is nil", "ui")
        end
        return
    end

    local stats = sessionStats.performance
    if not stats then
        if TRP3FW and TRP3FW.Debug then
            TRP3FW:Debug("[Graph] stats.performance is nil", "ui")
        end
        return
    end

    -- TODO: #7 & #9 - Update Top Stats Columns with filtering and improved visuals
    local function FillCol(col, data, fmt)
        -- Apply context filter if not "All Contexts"
        local filteredData = data
        if currentFilter ~= "All Contexts" and data then
            filteredData = {}
            for _, entry in ipairs(data) do
                if entry.context == currentFilter then
                    table.insert(filteredData, entry)
                end
            end
        end

        -- Find max value for bar scaling
        local maxValue = 0
        if filteredData and filteredData[1] then
            maxValue = filteredData[1].value
        end

        for i = 1, 5 do
            local row = col.rows[i]
            local entry = filteredData and filteredData[i]

            if entry then
                local valStr = string.format(fmt, entry.value)
                local percentage = maxValue > 0 and (entry.value / maxValue) or 0

                -- Rank-based gradient colors
                local barColor, textColor
                if i == 1 then
                    barColor = {1, 0.2, 0.2}     -- Red for #1
                    textColor = "|cffff3333"
                elseif i == 2 then
                    barColor = {1, 0.5, 0}       -- Orange for #2
                    textColor = "|cffff8800"
                elseif i == 3 then
                    barColor = {1, 0.8, 0}       -- Yellow for #3
                    textColor = "|cffffcc00"
                else
                    barColor = {0.4, 0.8, 0.4}   -- Green for #4-5
                    textColor = "|cff66cc66"
                end

                -- Set background bar
                row.bar:SetVertexColor(barColor[1], barColor[2], barColor[3], 0.3)
                row.bar:SetWidth(220 * percentage)

                -- Set text with color-coded value
                row.text:SetText(string.format("%s%s|r - %s", textColor, valStr, entry.context or "?"))
            else
                -- Empty row
                row.bar:SetWidth(0)
                row.text:SetText("|cff666666--|r")
            end
        end
    end

    if stats.topStats then
        FillCol(colLat, stats.topStats.latency, "%.1f")
        FillCol(colCpu, stats.topStats.cpu, "%.1f")
        FillCol(colTput, stats.topStats.throughput, "%.2f")
    end

    -- FIX: performanceHistory is at sessionStats.performanceHistory, not stats.performanceHistory
    local history = sessionStats.performanceHistory

    -- DEBUG: Log history status
    if TRP3FW and TRP3FW.Debug then
        if not history then
            TRP3FW:Debug("[Graph] performanceHistory is nil", "ui")
        else
            TRP3FW:Debug(function() return string.format("[Graph] performanceHistory has %d entries", #history) end, "ui")
        end
    end

    if not history or #history == 0 then return end

    -- Optimization: Only redraw if new data is available
    local lastEntry = history[#history]
    if lastEntry.timestamp == lastRenderedTimestamp then
        if TRP3FW and TRP3FW.Debug then
            TRP3FW:Debug("[Graph] Data unchanged, skipping redraw", "ui")
        end
        return
    end
    lastRenderedTimestamp = lastEntry.timestamp

    -- DEBUG: Log graph update
    if TRP3FW and TRP3FW.Debug then
        TRP3FW:Debug("[Graph] Updating all graphs with new data", "ui")
    end

    local showPeak = peakCheckbox:GetChecked()

    graphMemory:SetData(history, ValMemory)
    graphLatency:SetData(history, ValAvgLatency, showPeak and ValPeakLatency or nil)
    graphLoad:SetData(history, ValAvgLoad, showPeak and ValMaxLoad or nil)
    graphThroughput:SetData(history, ValThroughput, showPeak and ValPeakThroughput or nil)

    -- Update budget panel
    UpdateBudgetPanel()
end

-- TODO: #10 - Smart Refresh Management
-- Track window state to avoid unnecessary updates when closed
local windowOpen = false

-- Hook into refresh cycle via OnUpdate (only when window is shown)
local updateTimer = 0
historyFrame:SetScript("OnUpdate", function(self, elapsed)
    if not windowOpen then return end -- Don't update when closed

    updateTimer = updateTimer + elapsed

    -- Check for updates at the same rate as data collection (statusRefreshRate)
    -- Use a minimum of 5 seconds to avoid excessive polling
    local checkInterval = math.max(5, TRP3FW_Settings and TRP3FW_Settings.statusRefreshRate or 30)

    if updateTimer >= checkInterval then
        updateTimer = 0
        UpdateHistoryGraphs()
    end
end)

historyFrame:SetScript("OnShow", function()
    windowOpen = true
    updateTimer = 0 -- Reset timer to trigger immediate update
    lastRenderedTimestamp = 0 -- Force redraw to show all accumulated data
    UpdateHistoryGraphs() -- Immediately show all data collected while closed
end)

historyFrame:SetScript("OnHide", function()
    windowOpen = false
end)

-- Public Toggle Function
function TRP3FW:ToggleHistoryWindow()
    if historyFrame:IsShown() then
        historyFrame:Hide()
    else
        historyFrame:Show()
    end
end