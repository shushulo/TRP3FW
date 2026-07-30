-- ui/tabs/Status.lua
-- Status & Performance Tab for TRP3FW Settings
-- Phase 3 UX restructure: reordered sections by user relevance, made most
-- sections collapsible with reflow, and moved performance-history controls
-- inline with the section that uses them.

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

-- Header block: caption top(10) + caption height(20) + gap(8) + rule(1) +
-- gap(8) = 47, matching CreateCard's captioned topPad so the divider has equal
-- spacing above/below and the body clears it. Collapsed frames use this height.
local SECTION_HEADER_HEIGHT = 47
local SECTION_GAP = 8

-- Build a section container that supports collapse with reflow.
-- The previousAnchor (frame or nil) is what we anchor below; if nil, anchor to top of content.
-- expandedHeight = total content height when expanded (excluding the header).
local function CreateSection(parent, previousAnchor, title, expandedHeight, defaultOpen, onToggle)
    local Theme = TRP3FW.Theme
    local INNER = Theme.metrics.INNER
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetWidth(1) -- width inherited from anchors
    if previousAnchor then
        frame:SetPoint("TOPLEFT", previousAnchor, "BOTTOMLEFT", 0, -Theme.metrics.CARD_GAP)
        frame:SetPoint("TOPRIGHT", previousAnchor, "BOTTOMRIGHT", 0, -Theme.metrics.CARD_GAP)
    else
        frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    end
    -- Card-style backdrop so each collapsible section reads like the other tabs.
    frame:SetBackdrop(Theme.BACKDROP_CARD)
    frame:SetBackdropColor(Theme:Color("CARD"))
    frame:SetBackdropBorderColor(Theme:Color("BORDER"))

    local section = {
        frame = frame,
        open = defaultOpen ~= false,
        expandedHeight = expandedHeight,
        children = {},
        title = title,
    }

    local header = frame:CreateFontString(nil, "ARTWORK", Theme.fonts.CAPTION)
    header:SetPoint("TOPLEFT", INNER + 16, -10)  -- room for the arrow to its left
    header:SetHeight(20)  -- fixed so the divider anchor is deterministic
    header:SetJustifyV("MIDDLE")
    header:SetTextColor(Theme:Color("GOLD"))
    section.header = header

    local toggle = CreateFrame("Button", nil, frame)
    toggle:SetSize(16, 16)
    toggle:SetPoint("RIGHT", header, "LEFT", -6, 0)
    local arrow = toggle:CreateFontString(nil, "OVERLAY", Theme.fonts.CAPTION)
    arrow:SetAllPoints()
    arrow:SetJustifyH("CENTER")
    arrow:SetTextColor(Theme:Color("GOLD"))

    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -16, -8)
    line:SetPoint("RIGHT", frame, -INNER, 0)
    line:SetColorTexture(Theme:Color("BORDER"))

    -- Hitbox spanning the whole header strip so users don't have to click the tiny arrow
    local hitbox = CreateFrame("Button", nil, frame)
    hitbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    hitbox:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    hitbox:SetHeight(SECTION_HEADER_HEIGHT)

    -- Body region — children anchor here.
    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -SECTION_HEADER_HEIGHT)
    body:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    body:SetHeight(expandedHeight)
    section.body = body

    function section:Refresh()
        -- ASCII glyphs: the caption font doesn't include the Unicode triangle
        -- codepoints (U+25BC / U+25B6), so they render as tofu -- use +/-.
        arrow:SetText(self.open and "-" or "+")
        header:SetText(self.title)
        if self.open then
            body:Show()
            frame:SetHeight(SECTION_HEADER_HEIGHT + self.expandedHeight)
        else
            body:Hide()
            frame:SetHeight(SECTION_HEADER_HEIGHT)
        end
    end

    local function onClick()
        section.open = not section.open
        section:Refresh()
        if onToggle then onToggle(section) end
        if section.onToggleExtra then section.onToggleExtra(section) end
    end
    toggle:SetScript("OnClick", onClick)
    hitbox:SetScript("OnClick", onClick)

    section:Refresh()
    return section
end

local function CreateStatusTab(container)
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()

    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 1400)
    local uiElements = TabManager:GetUI()

    local function inlineStat(parent, labelText, yOffset, xOffset)
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", xOffset or 20, yOffset)
        label:SetText(labelText)
        label:SetTextColor(0.85, 0.85, 0.85)
        local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        value:SetPoint("LEFT", label, "RIGHT", 10, 0)
        return value, label
    end

    -- Collect the flow frames (section frames + trailing settings frame) so the
    -- scroll child can be resized to only the expanded content -- otherwise the
    -- scrollbar stays sized for the fully-expanded 1400px height.
    local flowFrames = {}
    local function recomputeHeight()
        local total = 10  -- top offset
        for i, f in ipairs(flowFrames) do
            total = total + f:GetHeight() + (i > 1 and SECTION_GAP or 0)
        end
        total = total + 12  -- bottom padding
        local minH = scrollFrame:GetHeight() or 0
        content:SetHeight(math.max(total, minH))
    end
    -- Passed as each section's onToggle so collapsing/expanding resizes the scroll.
    local function onSectionToggle() recomputeHeight() end

    -- ============================================================
    -- 1. Session Statistics (cards)
    -- ============================================================
    local sessionSec = CreateSection(content, nil, "Session Statistics", 90, true)
    do
        local body = sessionSec.body
        local cardWidth = (560 - 20) / 3
        uiElements.statusAlertsCard = TabManager:CreateStatCard(body, cardWidth, 75)
        uiElements.statusAlertsCard:SetPoint("TOPLEFT", 20, -5)
        uiElements.statusAlertsCard.title:SetText("ALERTS SHOWN")

        uiElements.statusBlocksCard = TabManager:CreateStatCard(body, cardWidth, 75)
        uiElements.statusBlocksCard:SetPoint("LEFT", uiElements.statusAlertsCard, "RIGHT", 10, 0)
        uiElements.statusBlocksCard.title:SetText("BLOCKS")

        uiElements.statusGhostCard = TabManager:CreateStatCard(body, cardWidth, 75)
        uiElements.statusGhostCard:SetPoint("LEFT", uiElements.statusBlocksCard, "RIGHT", 10, 0)
        uiElements.statusGhostCard.title:SetText("GHOST PROFILES")
    end

    -- ============================================================
    -- 2. Recent Activity (8-row table)
    -- ============================================================
    local recentSec = CreateSection(content, sessionSec.frame, "Recent Activity", 175, true)
    do
        local body = recentSec.body
        local function createHeader(parent, text, width, xOffset, yOffset)
            local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            h:SetPoint("TOPLEFT", xOffset, yOffset)
            h:SetWidth(width); h:SetJustifyH("LEFT")
            h:SetText(text); h:SetTextColor(0.6, 0.6, 0.6)
            return h
        end
        createHeader(body, "Time",   60,   20, -5)
        createHeader(body, "Player", 150,  85, -5)
        createHeader(body, "Addon",  60,  240, -5)
        createHeader(body, "Result", 100, 305, -5)

        uiElements.statusRecentEvents = {}
        local rowY = -25
        for i = 1, 8 do
            local row = CreateFrame("Frame", nil, body)
            row:SetSize(540, 18)
            row:SetPoint("TOPLEFT", 20, rowY)
            if i % 2 == 0 then
                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.05)
            end
            local function createCell(width, xOffset)
                local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                cell:SetPoint("LEFT", xOffset, 0); cell:SetWidth(width); cell:SetJustifyH("LEFT")
                return cell
            end
            row.Time   = createCell(60,   0)
            row.Player = createCell(150, 65)
            row.Addon  = createCell(60, 220)
            row.Result = createCell(200, 285)
            table.insert(uiElements.statusRecentEvents, row)
            rowY = rowY - 18
        end
    end

    -- ============================================================
    -- 3. Requests by Addon
    -- ============================================================
    local requestsSec = CreateSection(content, recentSec.frame, "Requests by Addon", 75, true)
    do
        local body = requestsSec.body
        uiElements.statusRequestsBar = TabManager:CreateHorizontalStackedBar(body, 540, 30)
        uiElements.statusRequestsBar:SetPoint("TOPLEFT", 20, -5)
        local legend = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        legend:SetPoint("TOPLEFT", 20, -40)
        legend:SetText("|cff4D99FFTRP3|r  |cffCC4DCCMRP|r  |cffFF9933XRP|r  |cff33CC66MSP|r")
        legend:SetTextColor(0.7, 0.7, 0.7)
    end

    -- ============================================================
    -- 4. Detection Breakdown
    -- ============================================================
    local detectionSec = CreateSection(content, requestsSec.frame, "Detection Breakdown", 60, true)
    do
        local body = detectionSec.body
        uiElements.statusPhaseAlerts = inlineStat(body, "Phase Verification Failures:", -5)
        uiElements.statusMapAlerts   = inlineStat(body, "Map/WHO Verification Failures:", -28)
    end

    -- ============================================================
    -- 5. Environment (collapsed by default at lower complexity)
    -- ============================================================
    local envSec = CreateSection(content, detectionSec.frame, "Environment", 100, false)
    do
        local body = envSec.body
        uiElements.statusAddonsList   = inlineStat(body, "RP Addons:",     -5)
        uiElements.statusMapScanner   = inlineStat(body, "Map Scanner:",  -27)
        uiElements.statusEpsilonAPI   = inlineStat(body, "Epsilon API:",  -49)
        uiElements.statusMemory       = inlineStat(body, "Memory Usage:", -71)
    end

    -- ============================================================
    -- 6. Performance Metrics + History toggle
    -- ============================================================
    -- expandedHeight fits the four stats (down to -71) plus the checkbox/button
    -- row at -100 (~24 tall) with a gap below matching the other sections.
    local perfSec = CreateSection(content, envSec.frame, "Performance Metrics", 140, false)
    do
        local body = perfSec.body
        uiElements.statusLatency       = inlineStat(body, "Latency (Inst/Avg/Peak):",   -5)
        uiElements.statusCPULoad       = inlineStat(body, "CPU Load (Inst/Avg/Peak):", -27)
        uiElements.statusThroughput    = inlineStat(body, "Throughput (Inst/Avg/Peak):", -49)
        uiElements.statusPhaseSecurity = inlineStat(body, "Phase Security:",            -71)

        local histCheck = TabManager:CreateCheckbox(body, "Track Performance History", "Enable background performance tracking.", "performanceHistoryEnabled")
        histCheck:SetPoint("TOPLEFT", 20, -100)
        uiElements.performanceHistoryEnabled = histCheck
        histCheck:SetScript("OnClick", function(self)
            TRP3FW.Prefs.performanceHistoryEnabled = self:GetChecked()
            if TRP3FW.UpdateBackgroundTracking then TRP3FW:UpdateBackgroundTracking() end
        end)

        local showHistoryBtn = TabManager:CreateButton(body, "Show graphs", 120, false)
        showHistoryBtn:SetPoint("LEFT", histCheck.label, "RIGHT", 20, 0)
        showHistoryBtn:SetOnClick(function()
            if TRP3FW.ToggleHistoryWindow then TRP3FW:ToggleHistoryWindow() end
        end)
    end

    -- ============================================================
    -- 7. Cache Performance (8 progress bars)
    -- ============================================================
    local cachePerfSec = CreateSection(content, perfSec.frame, "Cache Performance", 220, false)
    do
        local body = cachePerfSec.body
        local function createCachePerf(parent, label, yOffset)
            local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            l:SetPoint("TOPLEFT", 20, yOffset); l:SetWidth(130); l:SetJustifyH("LEFT")
            l:SetText(label); l:SetTextColor(0.85, 0.85, 0.85)
            local bar = TabManager:CreateProgressBar(parent, 400, 18)
            bar:SetPoint("TOPLEFT", 155, yOffset)
            return bar
        end
        local cy = -5
        uiElements.statusPhaseCachePerfBar          = createCachePerf(body, "Phase Cache:",      cy); cy = cy - 25
        uiElements.statusMapCachePerfBar            = createCachePerf(body, "Map Scan:",         cy); cy = cy - 25
        uiElements.statusWhoCachePerfBar            = createCachePerf(body, "WHO Query:",        cy); cy = cy - 25
        uiElements.statusAllowedSendersCachePerfBar = createCachePerf(body, "Allowed Senders:",  cy); cy = cy - 25
        uiElements.statusInteractionCachePerfBar    = createCachePerf(body, "Interaction:",      cy); cy = cy - 25
        uiElements.statusBroadcastCachePerfBar      = createCachePerf(body, "Broadcasts:",       cy); cy = cy - 25
        uiElements.statusSpvpCachePerfBar           = createCachePerf(body, "SPVP Salt:",        cy); cy = cy - 25
        uiElements.statusSpvpVerifiedCachePerfBar   = createCachePerf(body, "SPVP Verified:",    cy)
    end

    -- ============================================================
    -- 8. Cache Status (entry counts)
    -- ============================================================
    local cacheStatusSec = CreateSection(content, cachePerfSec.frame, "Cache Status", 130, false)
    do
        local body = cacheStatusSec.body
        local function createCacheStatus(parent, label, yOffset, xOffset)
            local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            l:SetPoint("TOPLEFT", xOffset, yOffset); l:SetWidth(140); l:SetJustifyH("LEFT")
            l:SetText(label); l:SetTextColor(0.85, 0.85, 0.85)
            local v = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            v:SetPoint("TOPLEFT", xOffset + 140, yOffset); v:SetJustifyH("LEFT")
            return v
        end
        local sy = -5
        uiElements.statusPhaseCache         = createCacheStatus(body, "Phase Cache:",        sy,  20)
        uiElements.statusBroadcastCache     = createCacheStatus(body, "Broadcast Cache:",    sy, 310); sy = sy - 22
        uiElements.statusScanCache          = createCacheStatus(body, "Map Scan Cache:",     sy,  20)
        uiElements.statusSendCache          = createCacheStatus(body, "Send Cache:",         sy, 310); sy = sy - 22
        uiElements.statusWhoNameCache       = createCacheStatus(body, "WHO Name Cache:",     sy,  20)
        uiElements.statusWhoZoneCache       = createCacheStatus(body, "WHO Zone Cache:",     sy, 310); sy = sy - 22
        uiElements.statusInteractionCache   = createCacheStatus(body, "Interaction Cache:",  sy,  20)
        uiElements.statusSuppressionCache   = createCacheStatus(body, "Suppression Timers:", sy, 310); sy = sy - 22
        uiElements.statusSpvpCache          = createCacheStatus(body, "SPVP Salt Cache:",    sy,  20)
        uiElements.statusSpvpVerifiedCache  = createCacheStatus(body, "SPVP Verified Cache:",sy, 310)
    end

    -- ============================================================
    -- 9. RunPrivileged API Statistics (Level 4)
    -- ============================================================
    local privSec = CreateSection(content, cacheStatusSec.frame, "RunPrivileged API Statistics", 140, false)
    do
        local body = privSec.body
        local py = -5
        uiElements.statusPrivilegedTotal    = inlineStat(body, "Total Calls:",      py); py = py - 22
        uiElements.statusPrivilegedSuccess  = inlineStat(body, "Successful:",       py); py = py - 22
        uiElements.statusPrivilegedBlocked  = inlineStat(body, "Rate Limited:",     py); py = py - 22
        uiElements.statusPrivilegedErrors   = inlineStat(body, "Errors:",           py); py = py - 22
        uiElements.statusPrivilegedDeferred = inlineStat(body, "Deferred (LOW):",   py); py = py - 22
        uiElements.statusPrivilegedRefunded = inlineStat(body, "Tokens Refunded:",  py)
    end

    -- ============================================================
    -- 10. Status Tab Settings (slider — not collapsible, always visible)
    -- ============================================================
    local settingsFrame = CreateFrame("Frame", nil, content)
    settingsFrame:SetPoint("TOPLEFT", privSec.frame, "BOTTOMLEFT", 0, -SECTION_GAP)
    settingsFrame:SetPoint("TOPRIGHT", privSec.frame, "BOTTOMRIGHT", 0, -SECTION_GAP)
    settingsFrame:SetHeight(110)
    do
        TabManager:CreateSkinnedHeader(settingsFrame, "Status tab settings", 0)
        local refreshText = settingsFrame:CreateFontString(nil, "OVERLAY", TRP3FW.Theme.fonts.LABEL)
        refreshText:SetPoint("TOPLEFT", 20, -35); refreshText:SetText("Auto-refresh rate:")
        refreshText:SetTextColor(TRP3FW.Theme:Color("TEXT_SECONDARY"))

        local slider = CreateFrame("Slider", "TRP3FW_StatusRefreshSlider", settingsFrame, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", 20, -65); slider:SetWidth(360)
        slider:SetMinMaxValues(2, 120); slider:SetValueStep(1); slider:SetObeyStepOnDrag(true)
        slider:SetValue(TRP3FW.Prefs.statusRefreshRate or 30)
        uiElements.statusRefreshRate = slider
        getglobal(slider:GetName().."Low"):SetText("2s")
        getglobal(slider:GetName().."High"):SetText("120s")
        getglobal(slider:GetName().."Text"):SetText("Refresh every " .. (TRP3FW.Prefs.statusRefreshRate or 30) .. " seconds")
        slider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value); TRP3FW.Prefs.statusRefreshRate = value
            getglobal(self:GetName().."Text"):SetText("Refresh every " .. value .. " seconds")
            if TRP3FW.StartStatusUpdates then TRP3FW:StartStatusUpdates() end
        end)

        local refreshBtn = TabManager:CreateButton(settingsFrame, "Refresh now", 90, false)
        refreshBtn:SetPoint("LEFT", slider, "RIGHT", 12, 0)
        refreshBtn:SetOnClick(function() if TRP3FW.UpdateStatusTab then TRP3FW:UpdateStatusTab() end end)
    end

    -- Default expansion by complexity (per spec 6.5)
    --   L1: sections 1-4 expanded
    --   L2: sections 1-6 expanded
    --   L3: sections 1-8 expanded
    --   L4: all expanded
    local complexity = (TRP3FW.Prefs and TRP3FW.Prefs.uiComplexityLevel) or 2
    if complexity < 4 then privSec.open = false; privSec:Refresh() end
    if complexity < 3 then
        cachePerfSec.open = false; cachePerfSec:Refresh()
        cacheStatusSec.open = false; cacheStatusSec:Refresh()
    end
    if complexity < 2 then
        envSec.open = false; envSec:Refresh()
        perfSec.open = false; perfSec:Refresh()
    end

    -- Register the flow frames (in visual order) and wire each section's toggle
    -- to resize the scroll child, so the scrollbar matches what's expanded.
    local sections = { sessionSec, recentSec, requestsSec, detectionSec, envSec, perfSec, cachePerfSec, cacheStatusSec, privSec }
    for _, sec in ipairs(sections) do
        sec.onToggleExtra = onSectionToggle
        flowFrames[#flowFrames + 1] = sec.frame
    end
    flowFrames[#flowFrames + 1] = settingsFrame
    recomputeHeight()

    return scrollFrame
end

TabManager:RegisterTab("status", "Status", "Status & Performance", CreateStatusTab, function() if TRP3FW.UpdateStatusTab then TRP3FW:UpdateStatusTab() end end, "Interface\\Icons\\INV_Misc_Note_01")
