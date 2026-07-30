-- ui/tabs/Debug.lua
-- Advanced (Cache & Debug) settings tab for TRP3FW (skinned kit + reflow rows)
--
-- Every row is registered with its card via card:AddRow so complexity changes
-- hide filtered rows, restack the visible ones, and resize the card. All
-- uiElements keys RefreshUI drives (edits table :SetText, checks :SetChecked,
-- slider :SetValue, debugOutputDropdown) are preserved.

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

local function stackCard(content, card, prev)
    local W = TRP3FW.Theme.metrics.CARD_W
    local inset = TRP3FW.Theme.metrics.CONTENT_INSET
    card:SetWidth(W)
    if prev then
        card:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -TRP3FW.Theme.metrics.CARD_GAP)
        card:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -TRP3FW.Theme.metrics.CARD_GAP)
    else
        card:SetPoint("TOPLEFT", content, "TOPLEFT", inset, 0)
        card:SetPoint("TOPRIGHT", content, "TOPRIGHT", -inset, 0)
    end
    return card
end

local function CreateDebugTab(container)
    local Theme = TRP3FW.Theme
    local INNER = Theme.metrics.INNER
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()

    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 3200)
    local uiElements = TabManager:GetUI()

    -- Shared column geometry so single rows, 2-up rows, and the grid all align.
    local CW = Theme.metrics.CARD_W
    local COL_W = (CW - INNER * 2) / 2   -- one grid column
    local GRID_LABEL_W = COL_W - 76      -- label width; leaves room for the 64px box

    -- Numeric edit-box save validation (unchanged semantics).
    local function setupEditBox(eb, key, min, max, isPercentage)
        local function save()
            local val = tonumber(eb:GetText())
            if val and (not min or val >= min) and (not max or val <= max) then
                TRP3FW.Prefs[key] = isPercentage and (val / 100) or val
            else eb:SetText(tostring(TRP3FW.Prefs[key] or 0)) end
        end
        eb:SetScript("OnEnterPressed", function(self) save(); self:ClearFocus() end)
        eb:SetScript("OnEditFocusLost", save)
    end

    -- Build a numeric item (label + skinned edit box) with a place(x, y, labelW)
    -- function so both single-column rows and the 2-column grid can position it.
    -- IMPORTANT: position eb.well (the outer frame), never the inner editBox.
    local function makeNum(card, key, label, tip, min, max, pct)
        local eb, lbl = TabManager:CreateSkinnedEditBox(card, label, tip, 64, key, true)
        setupEditBox(eb, key, min, max, pct)
        uiElements[key] = eb
        local item = { eb = eb, lbl = lbl }
        function item.place(x, y, labelW)
            lbl:ClearAllPoints()
            lbl:SetPoint("TOPLEFT", card, "TOPLEFT", x, y - 4)
            lbl:SetWidth(labelW or 0)
            lbl:SetJustifyH("LEFT")
            eb.well:ClearAllPoints()
            if labelW then
                eb.well:SetPoint("TOPLEFT", card, "TOPLEFT", x + labelW + 6, y)
            else
                eb.well:SetPoint("TOPLEFT", lbl, "RIGHT", 8, 4)
            end
        end
        return item
    end

    -- Single numeric row: left column of the grid layout, so it lines up with the
    -- rows above it (rather than a different flat width).
    local function numRow(card, key, label, tip, min, max, pct)
        local item = makeNum(card, key, label, tip, min, max, pct)
        card:AddRow(function(y) item.place(INNER, y, GRID_LABEL_W) end, 26, item.eb.complexityLevel, { item.eb })
        return item.eb
    end

    -- Full-width numeric row with the value box pinned to the card's RIGHT edge
    -- and the label filling the space to its left.
    local function numRowWide(card, key, label, tip, min, max, pct)
        local item = makeNum(card, key, label, tip, min, max, pct)
        card:AddRow(function(y)
            item.lbl:ClearAllPoints()
            item.lbl:SetPoint("TOPLEFT", card, "TOPLEFT", INNER, y - 4)
            item.lbl:SetPoint("RIGHT", item.eb.well, "LEFT", -8, 0)
            item.lbl:SetJustifyH("LEFT")
            item.eb.well:ClearAllPoints()
            item.eb.well:SetPoint("TOPRIGHT", card, "TOPRIGHT", -INNER, y)
        end, 26, item.eb.complexityLevel, { item.eb })
        return item.eb
    end

    -- Two numeric items side by side in one row (left + right grid columns).
    local function numRow2(card, aKey, aLabel, aTip, aMin, aMax, aPct, bKey, bLabel, bTip, bMin, bMax, bPct)
        local a = makeNum(card, aKey, aLabel, aTip, aMin, aMax, aPct)
        local b = makeNum(card, bKey, bLabel, bTip, bMin, bMax, bPct)
        -- Shown together at the higher of the two complexity levels.
        local lvl = math.max(a.eb.complexityLevel, b.eb.complexityLevel)
        card:AddRow(function(y)
            a.place(INNER, y, GRID_LABEL_W)
            b.place(INNER + COL_W, y, GRID_LABEL_W)
        end, 26, lvl, { a.eb, b.eb })
        return a.eb, b.eb
    end

    -- 2-column numeric grid as ONE dynamic row: re-grids only the visible items
    -- and returns the height used, so the card shrinks with the filter level.
    local function numGrid(card, specs)
        local items = {}
        for _, s in ipairs(specs) do
            items[#items + 1] = makeNum(card, s[1], s[2], s[3], s[4], s[5], s[6])
        end
        card:AddRow(function(y, level)
            local shown = {}
            for _, it in ipairs(items) do
                local s = it.eb.complexityLevel <= level
                it.eb:SetShown(s); it.eb.well:SetShown(s); it.lbl:SetShown(s)
                if s then shown[#shown + 1] = it end
            end
            for i, it in ipairs(shown) do
                local col = (i - 1) % 2
                local rowIdx = math.floor((i - 1) / 2)
                it.place(INNER + col * COL_W, y - rowIdx * 28, GRID_LABEL_W)
            end
            return math.ceil(#shown / 2) * 28
        end, 28, 1)
        return items
    end

    -- Full-width reflowable toggle row. indent adds left padding for sub-options.
    local function toggleRow(card, key, label, tip, onClick, indent)
        local t = TabManager:CreateToggle(card, label, tip, key)
        t:SetOnToggle(onClick or function(c) TRP3FW.Prefs[key] = c end)
        uiElements[key] = t
        card:AddRow(function(y)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", card, "TOPLEFT", INNER + (indent or 0), y)
            t:SetPoint("RIGHT", card, "RIGHT", -INNER, 0)
        end, Theme.metrics.ROW, t.complexityLevel, { t })
        return t
    end

    -- Reflowable slider row (positions the row frame; level from inner slider).
    local function sliderRow(card, rowWidget)
        card:AddRow(function(y)
            rowWidget:ClearAllPoints()
            rowWidget:SetPoint("TOPLEFT", card, "TOPLEFT", INNER, y)
            rowWidget:SetPoint("RIGHT", card, "RIGHT", -INNER, 0)
        end, 40, rowWidget.slider.complexityLevel, { rowWidget })
    end

    -- ===== Card: Cache durations (2-column grid) ===========================
    local cacheCard = stackCard(content, TabManager:CreateCard(content, "Cache durations", nil), nil)
    numGrid(cacheCard, {
        { "sendCacheDuration",         "Send cache (s)",       "How long to remember allowed senders.", 0 },
        { "sendCacheRefreshRate",      "Send refresh (%)",     "TTL percentage to trigger refresh.", 0, 100, true },
        { "interactionCacheDuration",  "Interaction (s)",      "How long to keep interaction records.", 0 },
        { "interactionRefreshRate",    "Interaction refresh (%)","TTL percentage to trigger refresh.", 0, 100, true },
        { "whoZoneCacheDuration",      "WHO zone (s)",         "How long to cache WHO zone results.", 0 },
        { "whoNameCacheDuration",      "WHO name (s)",         "How long to cache WHO name results.", 0 },
        { "whoZoneQueryCooldown",      "Zone cooldown (s)",    "Min seconds between WHO queries.", 0, 120 },
        { "whoCacheRefreshThreshold",  "WHO refresh (%)",      "TTL percentage to trigger refresh.", 0, 100, true },
        { "phaseCacheDuration",        "Phase success (s)",    "Success cache duration.", 0 },
        { "phaseCacheFailureDuration", "Phase failure (s)",    "Failure cache duration.", 0 },
        { "scanCacheDuration",         "Scan success (s)",     "Scan result duration.", 0 },
        { "scanCacheFailureDuration",  "Scan failure (s)",     "Failure cache duration.", 0 },
        { "mapScanMinInterval",        "Min scan interval (s)","Wait time between scans.", 10, 600 },
        { "phaseCacheRefreshThreshold","Phase refresh (%)",    "TTL percentage to refresh.", 0, 100, true },
        { "spvpVerifiedCacheDuration", "SPVP verify TTL (s)",  "How long verification lasts.", 10, 3600 },
        { "spvpVerifiedRefreshRate",   "SPVP verify refresh (%)","TTL percentage to trigger re-check.", 10, 90, true },
        { "spvpPhaseSaltRefreshRate",  "SPVP salt refresh (%)","TTL percentage to refetch salt.", 10, 90, true },
        { "cacheSizeLimit",            "Cache entry limit",    "Max entries per cache.", 100, 10000 },
        { "phaseInDelay",              "Phase-in delay (s)",   "Wait time after phasing.", 0, 10 },
        { "transitionGracePeriod",     "Transition grace (s)", "Race condition protection window.", 0, 30 },
        { "validatedNamesCacheLimit",  "Name entry limit",     "Max persistent entries.", 500, 10000 },
    })
    -- Name TTL: stored in seconds, edited in days; own row + custom save.
    local nameTTL = numRow(cacheCard, "validatedNamesCacheDuration", "Name cache TTL (days)", "TTL for persistent names.")
    uiElements.validatedNamesCacheDuration = nameTTL
    local function saveNameTTL(self)
        local d = tonumber(self:GetText())
        if d and d >= 1 and d <= 30 then TRP3FW.Prefs.validatedNamesCacheDuration = d * 86400
        else self:SetText(tostring(math.floor((TRP3FW.Prefs.validatedNamesCacheDuration or 604800) / 86400))) end
    end
    nameTTL:SetScript("OnEnterPressed", function(self) saveNameTTL(self); self:ClearFocus() end)
    nameTTL:SetScript("OnEditFocusLost", saveNameTTL)
    cacheCard:Reflow()

    -- ===== Card: WHO prepopulation =========================================
    local prepopCard = stackCard(content, TabManager:CreateCard(content, "WHO prepopulation", nil), cacheCard)
    toggleRow(prepopCard, "prepopulateWhoCache", "Prepopulate WHO cache", "Run WHO queries automatically after area changes.", function(c) TRP3FW.Prefs.prepopulateWhoCache = c; TRP3FW:RefreshUI() end)
    toggleRow(prepopCard, "prepopulateWhoOnPhase", "On phase change", "Warm up cache after scenario updates.", nil, 16)
    toggleRow(prepopCard, "prepopulateWhoOnZone", "On zone change", "Warm up cache after zone changes.", nil, 16)
    prepopCard:Reflow()

    -- ===== Card: Batching & rate limiting ==================================
    local batchCard = stackCard(content, TabManager:CreateCard(content, "Batching & rate limiting", nil), prepopCard)
    toggleRow(batchCard, "phaseCheckBatchMode", "Enable phase batching", "Bundle checks into single actions.")

    uiElements.phaseCheckBatchSizeSlider = TabManager:CreateSlider(batchCard, "Batch size", "Targets per batch.", "phaseCheckBatchSize", 2, 10, 1, "%d")
    uiElements.phaseCheckBatchSizeSlider:SetOnChange(function(v) TRP3FW.Prefs.phaseCheckBatchSize = v end)
    sliderRow(batchCard, uiElements.phaseCheckBatchSizeSlider)
    uiElements.phaseCheckBatchDelaySlider = TabManager:CreateSlider(batchCard, "Batch delay (s)", "Delay between batches.", "phaseCheckBatchDelay", 0.1, 2.0, 0.1, "%.1f")
    uiElements.phaseCheckBatchDelaySlider:SetOnChange(function(v) TRP3FW.Prefs.phaseCheckBatchDelay = v end)
    sliderRow(batchCard, uiElements.phaseCheckBatchDelaySlider)
    uiElements.phaseCheckBatchMinSizeSlider = TabManager:CreateSlider(batchCard, "Min batch size", "Minimum targets to batch.", "phaseCheckBatchMinSize", 2, 10, 1, "%d")
    uiElements.phaseCheckBatchMinSizeSlider:SetOnChange(function(v) TRP3FW.Prefs.phaseCheckBatchMinSize = v end)
    sliderRow(batchCard, uiElements.phaseCheckBatchMinSizeSlider)
    -- Inter-target delay is stored in seconds (0.01-0.2) but shown in ms.
    uiElements.phaseCheckInterTargetDelaySlider = TabManager:CreateSlider(batchCard, "Target delay (ms)", "Delay between individual targets.", "phaseCheckInterTargetDelay", 0.01, 0.2, 0.01, "%.0f", 1000)
    uiElements.phaseCheckInterTargetDelaySlider:SetOnChange(function(v) TRP3FW.Prefs.phaseCheckInterTargetDelay = v end)
    sliderRow(batchCard, uiElements.phaseCheckInterTargetDelaySlider)

    numRow2(batchCard,
        "privilegedReservedTokens", "API reserved tokens", "Reserved for HIGH priority.", 0, 5, nil,
        "privilegedLowPriorityThreshold", "API low threshold", "Tokens needed for LOW priority.", 2, 8, nil)
    toggleRow(batchCard, "phaseCheckRefundOnNoChange", "Refund tokens on fail", "Refund if target is missing.")
    batchCard:Reflow()

    -- ===== Card: Area-change cache clearing ================================
    local clearCard = stackCard(content, TabManager:CreateCard(content, "Area-change cache clearing", nil), batchCard)
    local subLabels = { "Phase check cache", "Allowed senders cache", "Interaction cache", "Suppression timers", "Recent broadcasts", "Recent scans", "WHO zone results", "WHO name results", "SPVP handshakes" }
    toggleRow(clearCard, "clearCacheOnPhaseChange", "Clear caches on phase change", "Enable cache clearing on phase change, then choose which caches below.", function(c) TRP3FW.Prefs.clearCacheOnPhaseChange = c; TRP3FW:RefreshUI() end)
    local pClear = { "clearPhaseCheckOnPhaseChange", "clearAllowedSendersOnPhaseChange", "clearInteractionOnPhaseChange", "clearSuppressionOnPhaseChange", "clearRecentBroadcastsOnPhaseChange", "clearRecentScansOnPhaseChange", "clearWhoZoneOnPhaseChange", "clearWhoNameOnPhaseChange", "clearSpvpOnPhaseChange" }
    for i, k in ipairs(pClear) do toggleRow(clearCard, k, subLabels[i], "Clear on phase change.", nil, 16) end
    toggleRow(clearCard, "clearCacheOnZoneChange", "Clear caches on zone change", "Enable cache clearing on zone change, then choose which caches below.", function(c) TRP3FW.Prefs.clearCacheOnZoneChange = c; TRP3FW:RefreshUI() end)
    local zClear = { "clearPhaseCheckOnZoneChange", "clearAllowedSendersOnZoneChange", "clearInteractionOnZoneChange", "clearSuppressionOnZoneChange", "clearRecentBroadcastsOnZoneChange", "clearRecentScansOnZoneChange", "clearWhoZoneOnZoneChange", "clearWhoNameOnZoneChange", "clearSpvpOnZoneChange" }
    for i, k in ipairs(zClear) do toggleRow(clearCard, k, subLabels[i], "Clear on zone change.", nil, 16) end
    clearCard:Reflow()

    -- ===== Card: History & redaction =======================================
    local histCard = stackCard(content, TabManager:CreateCard(content, "History & redaction", nil), clearCard)
    toggleRow(histCard, "trackHistory", "Enable event tracking", "Save alerts/blocks to history.")
    numRowWide(histCard, "maxHistorySize", "Max event log size", "Max history entries.", 10, 1000)
    toggleRow(histCard, "redactEnabled", "Enable global redaction", "Mask sensitive data in output.", function(c) TRP3FW.Prefs.redactEnabled = c; TRP3FW:RefreshUI() end)
    local rKeys = { "redactNames", "redactLocations", "redactNetwork", "redactSPVP" }
    local rLabels = { "Redact names/IDs", "Redact locations", "Redact IPs/network", "Redact SPVP keys" }
    for i, k in ipairs(rKeys) do toggleRow(histCard, k, rLabels[i], "Mask this category.", nil, 16) end
    histCard:Reflow()

    -- ===== Card: Debug controls ============================================
    local dbgCard = stackCard(content, TabManager:CreateCard(content, "Debug controls", nil), histCard)
    toggleRow(dbgCard, "debug", "Master debug mode", "Display verbose technical logs.", function(c) TRP3FW.Prefs.debug = c; TRP3FW:RefreshUI() end)
    toggleRow(dbgCard, "debugTimestamp", "Prefix timestamps", "Include server time in debug.", nil, 16)

    local dOut = TabManager:CreateSkinnedDropdown(dbgCard, "Debug output destination", "Logs are always captured for the debug window while debug mode is on; this picks whether they also print to chat.", 200, "debugOutputBoth")
    uiElements.debugOutputDropdown = dOut
    UIDropDownMenu_Initialize(dOut, function()
        local l = {
            {t="Chat",   f=function() TRP3FW.Prefs.debugOutputChat=true;  TRP3FW.Prefs.debugOutputWindow=false; TRP3FW.Prefs.debugOutputBoth=false end},
            {t="Window", f=function() TRP3FW.Prefs.debugOutputChat=false; TRP3FW.Prefs.debugOutputWindow=true;  TRP3FW.Prefs.debugOutputBoth=false end},
            {t="Both",   f=function() TRP3FW.Prefs.debugOutputChat=true;  TRP3FW.Prefs.debugOutputWindow=true;  TRP3FW.Prefs.debugOutputBoth=true  end},
        }
        for _, it in ipairs(l) do local info = UIDropDownMenu_CreateInfo(); info.text = it.t; info.func = function() it.f(); UIDropDownMenu_SetText(dOut, it.t) end; UIDropDownMenu_AddButton(info) end
    end)
    dbgCard:AddRow(function(y)
        dOut:ClearAllPoints()
        dOut:SetPoint("TOPLEFT", dbgCard, "TOPLEFT", INNER - 16, y - 16)
    end, 52, dOut.complexityLevel, { dOut })

    local dbgWinBtn = TabManager:CreateButton(dbgCard, "Toggle debug window", 170, false)
    dbgWinBtn:SetOnClick(function()
        if TRP3FW.ToggleDebugWindow then TRP3FW:ToggleDebugWindow() else TRP3FW:Warn("Debug window not loaded yet") end
    end)
    dbgCard:AddRow(function(y)
        dbgWinBtn:ClearAllPoints()
        dbgWinBtn:SetPoint("TOPLEFT", dbgCard, "TOPLEFT", INNER, y)
    end, 30, 1, { dbgWinBtn })

    -- Debug category verbosity toggles: one dynamic 2-column group row.
    local catHdr = dbgCard:CreateFontString(nil, "OVERLAY", Theme.fonts.SUB)
    catHdr:SetText("Category verbosity"); catHdr:SetTextColor(Theme:Color("TEXT_MUTED"))
    local dCats = { "debugChannel", "debugWhisper", "debugWho", "debugPhase", "debugCleanName", "debugLocation", "debugDecision", "debugHooks", "debugCache", "debugSend", "debugUI", "debugUtils", "debugSecurity", "debugGhost", "debugSPVP" }
    local dLabels = { "Channel", "Whisper", "WHO", "Phase", "Names", "Location", "Decision", "Hooks", "Cache", "Send", "UI", "Utils", "Security", "Ghost", "SPVP" }
    local cats = {}
    local W = Theme.metrics.CARD_W
    local colW = (W - INNER * 2) / 2
    for i, k in ipairs(dCats) do
        local t = TabManager:CreateToggle(dbgCard, dLabels[i], "Toggle logs.", k)
        t:SetOnToggle(function(c) TRP3FW.Prefs[k] = c end)
        uiElements[k] = t
        cats[#cats + 1] = t
    end
    dbgCard:AddRow(function(y, level)
        catHdr:ClearAllPoints()
        catHdr:SetPoint("TOPLEFT", dbgCard, "TOPLEFT", INNER, y)
        local shown = {}
        for _, t in ipairs(cats) do
            local s = t.complexityLevel <= level
            t:SetShown(s)
            if s then shown[#shown + 1] = t end
        end
        catHdr:SetShown(#shown > 0)
        for i, t in ipairs(shown) do
            local col = (i - 1) % 2
            local rowIdx = math.floor((i - 1) / 2)
            -- Give the toggle an explicit column width so its label (anchored to
            -- LEFT) and pill (anchored to RIGHT) lay out with room between them.
            -- Without a width the frame is 0-wide and the label overlaps the pill.
            t:ClearAllPoints()
            t:SetWidth(colW - 12)
            t:SetPoint("TOPLEFT", dbgCard, "TOPLEFT", INNER + col * colW, y - 22 - rowIdx * 28)
        end
        if #shown == 0 then return 0 end
        return 22 + math.ceil(#shown / 2) * 28
    end, 28, 1)
    dbgCard:Reflow()

    -- ===== Card: Addon monitoring ==========================================
    local monCard = stackCard(content, TabManager:CreateCard(content, "Addon monitoring", nil), dbgCard)
    toggleRow(monCard, "monitorTRP3", "Monitor Total RP 3", "Enable protections for TRP3.")
    toggleRow(monCard, "monitorMRP", "Monitor MyRolePlay", "Enable protections for MRP.")
    toggleRow(monCard, "monitorXRP", "Monitor XRP", "Enable protections for XRP.")
    toggleRow(monCard, "monitorMSP", "Monitor MSP/other", "Monitor other compatible addons.")
    monCard:Reflow()

    -- ===== Card: Hook safety ===============================================
    local hookCard = stackCard(content, TabManager:CreateCard(content, "Hook safety", nil), monCard)
    toggleRow(hookCard, "strictHookMode", "Strict hook mode", "Refuse to install when another addon hooks core functions.")
    toggleRow(hookCard, "logHookConflicts", "Log hook conflicts", "Warn when hooks are already wrapped.")
    toggleRow(hookCard, "abortOnMultipleRPAddons", "Abort on multiple RP addons", "Disable TRP3FW if multiple RP addons detected.")
    toggleRow(hookCard, "disableMapScanOnTRP3", "Disable map scan with TRP3 + RPMapScan", "Skip map-scan hooks in this specific combo.")
    hookCard:Reflow()

    return scrollFrame
end

TabManager:RegisterTab("debug", "Advanced", "Advanced Settings", CreateDebugTab, function() TRP3FW:RefreshUI() end, "Interface\\Icons\\Trade_Engineering")
