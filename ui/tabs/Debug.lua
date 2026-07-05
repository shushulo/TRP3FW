-- ui/tabs/Debug.lua
-- Advanced (Cache & Debug) settings tab for TRP3FW (migrated to the skinned kit)
--
-- The densest tab: ~24 numeric tunables, ~40 toggles, 4 batching sliders, 2
-- dropdowns. Preserves every uiElements key and behavior RefreshUI depends on
-- (the edits table drives all edit boxes via :SetText, the checks list drives
-- toggles via :SetChecked, and the granular clear/redact/debug groups + slider
-- and dropdown keys are all retained).

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

    -- A labelled numeric edit box with the value paired to the RIGHT of the
    -- label (not far-right), so the two read as one unit. IMPORTANT:
    -- CreateSkinnedEditBox's outer frame is `eb.well` (the editBox sits inside
    -- it) -- position the WELL, not the editBox.
    --
    -- If x/y are given, the row is placed at that offset from the card's
    -- TOPLEFT (used for the 2-column cache grid). Otherwise it uses the card
    -- cursor (single column, full width). Label is capped so the value clears it.
    local function numRow(card, key, label, tip, min, max, pct, x, y, labelW)
        local eb, lbl = TabManager:CreateSkinnedEditBox(card, label, tip, 64, key, true)
        local well = eb.well
        x = x or INNER
        y = y or card:NextY(26)
        lbl:ClearAllPoints()
        lbl:SetPoint("TOPLEFT", card, "TOPLEFT", x, y - 4)
        lbl:SetWidth(labelW or 0)  -- 0 = natural width (single column)
        lbl:SetJustifyH("LEFT")
        well:ClearAllPoints()
        -- Value sits just right of the label's box (paired), not far-right.
        if labelW then
            well:SetPoint("TOPLEFT", card, "TOPLEFT", x + labelW + 6, y)
        else
            well:SetPoint("TOPLEFT", lbl, "RIGHT", 8, 4)
        end
        setupEditBox(eb, key, min, max, pct)
        uiElements[key] = eb
        return eb
    end

    -- Lay out a list of {key,label,tip,min,max,pct} numeric specs in two columns
    -- inside a card, pairing each value tightly to its label. Advances the card
    -- cursor past the grid.
    local function numGrid(card, specs)
        local W = TRP3FW.Theme.metrics.CARD_W
        local colW = (W - INNER * 2) / 2
        local labelW = colW - 76  -- leave room for the 64px value box + gaps
        local baseY = card:NextY(0)
        for i, s in ipairs(specs) do
            local col = (i - 1) % 2
            local rowIdx = math.floor((i - 1) / 2)
            numRow(card, s[1], s[2], s[3], s[4], s[5], s[6], INNER + col * colW, baseY - rowIdx * 28, labelW)
        end
        card._cursorY = baseY - math.ceil(#specs / 2) * 28
    end

    -- A full-width toggle row. indent adds left padding for sub-options.
    local function toggleRow(card, key, label, tip, onClick, indent)
        local t = TabManager:CreateToggle(card, label, tip, key)
        t:SetPoint("TOPLEFT", INNER + (indent or 0), card:NextY())
        t:SetPoint("RIGHT", card, "RIGHT", -INNER, 0)
        t:SetOnToggle(onClick or function(c) TRP3FW.Prefs[key] = c end)
        uiElements[key] = t
        return t
    end

    -- ===== Card: Cache durations (all numeric tunables, 2-column grid) =====
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
    local W = TRP3FW.Theme.metrics.CARD_W
    local nameTTL = numRow(cacheCard, "validatedNamesCacheDuration", "Name cache TTL (days)", "TTL for persistent names.",
        nil, nil, false, INNER, cacheCard:NextY(28), (W - INNER * 2) / 2 - 76)
    uiElements.validatedNamesCacheDuration = nameTTL
    local function saveNameTTL(self)
        local d = tonumber(self:GetText())
        if d and d >= 1 and d <= 30 then TRP3FW.Prefs.validatedNamesCacheDuration = d * 86400
        else self:SetText(tostring(math.floor((TRP3FW.Prefs.validatedNamesCacheDuration or 604800) / 86400))) end
    end
    nameTTL:SetScript("OnEnterPressed", function(self) saveNameTTL(self); self:ClearFocus() end)
    nameTTL:SetScript("OnEditFocusLost", saveNameTTL)
    cacheCard:FitHeight(12)

    -- ===== Card: WHO prepopulation =========================================
    local prepopCard = stackCard(content, TabManager:CreateCard(content, "WHO prepopulation", nil), cacheCard)
    toggleRow(prepopCard, "prepopulateWhoCache", "Prepopulate WHO cache", "Run WHO queries automatically after area changes.", function(c) TRP3FW.Prefs.prepopulateWhoCache = c; TRP3FW:RefreshUI() end)
    toggleRow(prepopCard, "prepopulateWhoOnPhase", "On phase change", "Warm up cache after scenario updates.", nil, 16)
    toggleRow(prepopCard, "prepopulateWhoOnZone", "On zone change", "Warm up cache after zone changes.", nil, 16)
    prepopCard:FitHeight(4)

    -- ===== Card: Batching & rate limiting ==================================
    local batchCard = stackCard(content, TabManager:CreateCard(content, "Batching & rate limiting", nil), prepopCard)
    toggleRow(batchCard, "phaseCheckBatchMode", "Enable phase batching", "Bundle checks into single actions.")
    uiElements.phaseCheckBatchSizeSlider = TabManager:CreateSlider(batchCard, "Batch size", "Targets per batch.", "phaseCheckBatchSize", 2, 10, 1, "%d")
    uiElements.phaseCheckBatchSizeSlider:SetPoint("TOPLEFT", INNER, batchCard:NextY(40)); uiElements.phaseCheckBatchSizeSlider:SetPoint("RIGHT", batchCard, "RIGHT", -INNER, 0)
    uiElements.phaseCheckBatchSizeSlider:SetOnChange(function(v) TRP3FW.Prefs.phaseCheckBatchSize = v end)
    uiElements.phaseCheckBatchDelaySlider = TabManager:CreateSlider(batchCard, "Batch delay (s)", "Delay between batches.", "phaseCheckBatchDelay", 0.1, 2.0, 0.1, "%.1f")
    uiElements.phaseCheckBatchDelaySlider:SetPoint("TOPLEFT", INNER, batchCard:NextY(40)); uiElements.phaseCheckBatchDelaySlider:SetPoint("RIGHT", batchCard, "RIGHT", -INNER, 0)
    uiElements.phaseCheckBatchDelaySlider:SetOnChange(function(v) TRP3FW.Prefs.phaseCheckBatchDelay = v end)
    uiElements.phaseCheckBatchMinSizeSlider = TabManager:CreateSlider(batchCard, "Min batch size", "Minimum targets to batch.", "phaseCheckBatchMinSize", 2, 10, 1, "%d")
    uiElements.phaseCheckBatchMinSizeSlider:SetPoint("TOPLEFT", INNER, batchCard:NextY(40)); uiElements.phaseCheckBatchMinSizeSlider:SetPoint("RIGHT", batchCard, "RIGHT", -INNER, 0)
    uiElements.phaseCheckBatchMinSizeSlider:SetOnChange(function(v) TRP3FW.Prefs.phaseCheckBatchMinSize = v end)
    -- Inter-target delay is stored in seconds (0.01-0.2) but shown in ms.
    uiElements.phaseCheckInterTargetDelaySlider = TabManager:CreateSlider(batchCard, "Target delay (ms)", "Delay between individual targets.", "phaseCheckInterTargetDelay", 0.01, 0.2, 0.01, "%.0f", 1000)
    uiElements.phaseCheckInterTargetDelaySlider:SetPoint("TOPLEFT", INNER, batchCard:NextY(40)); uiElements.phaseCheckInterTargetDelaySlider:SetPoint("RIGHT", batchCard, "RIGHT", -INNER, 0)
    uiElements.phaseCheckInterTargetDelaySlider:SetOnChange(function(v) TRP3FW.Prefs.phaseCheckInterTargetDelay = v end)
    numRow(batchCard, "privilegedReservedTokens", "API reserved tokens", "Reserved for HIGH priority.", 0, 5)
    numRow(batchCard, "privilegedLowPriorityThreshold", "API low threshold", "Tokens needed for LOW priority.", 2, 8)
    toggleRow(batchCard, "phaseCheckRefundOnNoChange", "Refund tokens on fail", "Refund if target is missing.")
    batchCard:FitHeight(4)

    -- ===== Card: Area-change cache clearing ================================
    local clearCard = stackCard(content, TabManager:CreateCard(content, "Area-change cache clearing", nil), batchCard)
    local subLabels = { "Phase check cache", "Allowed senders cache", "Interaction cache", "Suppression timers", "Recent broadcasts", "Recent scans", "WHO zone results", "WHO name results", "SPVP handshakes" }
    toggleRow(clearCard, "clearCacheOnPhaseChange", "Clear all on phase change", "Master toggle for phase changes.", function(c) TRP3FW.Prefs.clearCacheOnPhaseChange = c; TRP3FW:RefreshUI() end)
    local pClear = { "clearPhaseCheckOnPhaseChange", "clearAllowedSendersOnPhaseChange", "clearInteractionOnPhaseChange", "clearSuppressionOnPhaseChange", "clearRecentBroadcastsOnPhaseChange", "clearRecentScansOnPhaseChange", "clearWhoZoneOnPhaseChange", "clearWhoNameOnPhaseChange", "clearSpvpOnPhaseChange" }
    for i, k in ipairs(pClear) do toggleRow(clearCard, k, subLabels[i], "Clear on phase change.", nil, 16) end
    toggleRow(clearCard, "clearCacheOnZoneChange", "Clear all on zone change", "Master toggle for zone changes.", function(c) TRP3FW.Prefs.clearCacheOnZoneChange = c; TRP3FW:RefreshUI() end)
    local zClear = { "clearPhaseCheckOnZoneChange", "clearAllowedSendersOnZoneChange", "clearInteractionOnZoneChange", "clearSuppressionOnZoneChange", "clearRecentBroadcastsOnZoneChange", "clearRecentScansOnZoneChange", "clearWhoZoneOnZoneChange", "clearWhoNameOnZoneChange", "clearSpvpOnZoneChange" }
    for i, k in ipairs(zClear) do toggleRow(clearCard, k, subLabels[i], "Clear on zone change.", nil, 16) end
    clearCard:FitHeight(4)

    -- ===== Card: History & redaction =======================================
    local histCard = stackCard(content, TabManager:CreateCard(content, "History & redaction", nil), clearCard)
    toggleRow(histCard, "trackHistory", "Enable event tracking", "Save alerts/blocks to history.")
    numRow(histCard, "maxHistorySize", "Max event log size", "Max history entries.", 10, 1000)
    toggleRow(histCard, "redactEnabled", "Enable global redaction", "Mask sensitive data in output.", function(c) TRP3FW.Prefs.redactEnabled = c; TRP3FW:RefreshUI() end)
    local rKeys = { "redactNames", "redactLocations", "redactNetwork", "redactSPVP" }
    local rLabels = { "Redact names/IDs", "Redact locations", "Redact IPs/network", "Redact SPVP keys" }
    for i, k in ipairs(rKeys) do toggleRow(histCard, k, rLabels[i], "Mask this category.", nil, 16) end
    histCard:FitHeight(4)

    -- ===== Card: Debug controls ============================================
    local dbgCard = stackCard(content, TabManager:CreateCard(content, "Debug controls", nil), histCard)
    toggleRow(dbgCard, "debug", "Master debug mode", "Display verbose technical logs.", function(c) TRP3FW.Prefs.debug = c; TRP3FW:RefreshUI() end)
    toggleRow(dbgCard, "debugTimestamp", "Prefix timestamps", "Include server time in debug.", nil, 16)

    local dOut = TabManager:CreateSkinnedDropdown(dbgCard, "Debug output destination", "Target frame for logs.", 200, "debugOutputBoth")
    dOut:SetPoint("TOPLEFT", INNER - 16, dbgCard:NextY(52) - 16); uiElements.debugOutputDropdown = dOut
    UIDropDownMenu_Initialize(dOut, function()
        local l = {
            {t="Chat",   f=function() TRP3FW.Prefs.debugOutputChat=true;  TRP3FW.Prefs.debugOutputWindow=false; TRP3FW.Prefs.debugOutputBoth=false end},
            {t="Window", f=function() TRP3FW.Prefs.debugOutputChat=false; TRP3FW.Prefs.debugOutputWindow=true;  TRP3FW.Prefs.debugOutputBoth=false end},
            {t="Both",   f=function() TRP3FW.Prefs.debugOutputChat=true;  TRP3FW.Prefs.debugOutputWindow=true;  TRP3FW.Prefs.debugOutputBoth=true  end},
        }
        for _, it in ipairs(l) do local info = UIDropDownMenu_CreateInfo(); info.text = it.t; info.func = function() it.f(); UIDropDownMenu_SetText(dOut, it.t) end; UIDropDownMenu_AddButton(info) end
    end)

    local dbgWinBtn = TabManager:CreateButton(dbgCard, "Toggle debug window", 170, false)
    dbgWinBtn:SetPoint("TOPLEFT", INNER, dbgCard:NextY(30))
    dbgWinBtn:SetOnClick(function()
        if TRP3FW.ToggleDebugWindow then TRP3FW:ToggleDebugWindow() else TRP3FW:Warn("Debug window not loaded yet") end
    end)

    -- Debug category verbosity toggles (2 columns to keep the card compact).
    local catHdr = dbgCard:CreateFontString(nil, "OVERLAY", Theme.fonts.SUB)
    catHdr:SetPoint("TOPLEFT", INNER, dbgCard:NextY(20)); catHdr:SetText("Category verbosity"); catHdr:SetTextColor(Theme:Color("TEXT_MUTED"))
    local dCats = { "debugChannel", "debugWhisper", "debugWho", "debugPhase", "debugCleanName", "debugLocation", "debugDecision", "debugHooks", "debugCache", "debugSend", "debugUI", "debugUtils", "debugSecurity", "debugGhost", "debugSPVP" }
    local dLabels = { "Channel", "Whisper", "WHO", "Phase", "Names", "Location", "Decision", "Hooks", "Cache", "Send", "UI", "Utils", "Security", "Ghost", "SPVP" }
    local W = Theme.metrics.CARD_W
    local colW = (W - INNER * 2) / 2
    local baseCatY = dbgCard:NextY(0)
    for i, k in ipairs(dCats) do
        local col = (i - 1) % 2
        local rowIdx = math.floor((i - 1) / 2)
        local t = TabManager:CreateToggle(dbgCard, dLabels[i], "Toggle logs.", k)
        t:SetPoint("TOPLEFT", INNER + col * colW, baseCatY - rowIdx * 28)
        t.pill:ClearAllPoints()
        t.pill:SetPoint("LEFT", t, "LEFT", colW - 44, 0)  -- pill after the label, within the column
        t:SetOnToggle(function(c) TRP3FW.Prefs[k] = c end)
        uiElements[k] = t
    end
    dbgCard._cursorY = baseCatY - math.ceil(#dCats / 2) * 28 - 4
    dbgCard:FitHeight(12)

    -- ===== Card: Addon monitoring ==========================================
    local monCard = stackCard(content, TabManager:CreateCard(content, "Addon monitoring", nil), dbgCard)
    toggleRow(monCard, "monitorTRP3", "Monitor Total RP 3", "Enable protections for TRP3.")
    toggleRow(monCard, "monitorMRP", "Monitor MyRolePlay", "Enable protections for MRP.")
    toggleRow(monCard, "monitorXRP", "Monitor XRP", "Enable protections for XRP.")
    toggleRow(monCard, "monitorMSP", "Monitor MSP/other", "Monitor other compatible addons.")
    monCard:FitHeight(4)

    -- ===== Card: Hook safety ===============================================
    local hookCard = stackCard(content, TabManager:CreateCard(content, "Hook safety", nil), monCard)
    toggleRow(hookCard, "strictHookMode", "Strict hook mode", "Refuse to install when another addon hooks core functions.")
    toggleRow(hookCard, "logHookConflicts", "Log hook conflicts", "Warn when hooks are already wrapped.")
    toggleRow(hookCard, "abortOnMultipleRPAddons", "Abort on multiple RP addons", "Disable TRP3FW if multiple RP addons detected.")
    toggleRow(hookCard, "disableMapScanOnTRP3", "Disable map scan with TRP3 + RPMapScan", "Skip map-scan hooks in this specific combo.")
    hookCard:FitHeight(4)

    return scrollFrame
end

TabManager:RegisterTab("debug", "Advanced", "Advanced Settings", CreateDebugTab, function() TRP3FW:RefreshUI() end, "Interface\\Icons\\Trade_Engineering")
