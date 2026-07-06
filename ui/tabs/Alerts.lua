-- ui/tabs/Alerts.lua
-- Protection & Blocking settings tab for TRP3FW (migrated to the skinned kit)
--
-- Preserves every uiElements key, epsilon registration, and behavior the old
-- tab and RefreshUI depend on (phaseCheckModeDropdown, mapCheckModeDropdown,
-- ghostProfileDropdown, modeSummary (current-modes grid), the check toggles, the
-- ghostProfileWhitelist* widgets, epsilonWarning, and profileOverrides), just
-- reorganized into slate cards with skinned controls.

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

local MODE_OPTIONS = {
    {t="Off", v="off"}, {t="Statistics only", v="statistics"}, {t="Notify only", v="alert"},
    {t="Block (silent)", v="block"}, {t="Send blank profile", v="ghost"},
    {t="Block (with notification)", v="alert_block"}, {t="Send blank profile (with notification)", v="alert_ghost"},
}

-- Inspect-timeout fallback: how to resolve the phase check if the inspect window is
-- still open after the 10s retry window. Resolves to a phase result (not an action),
-- so the normal phase/map modes and SPVP fallback still decide what happens.
local INSPECT_TIMEOUT_OPTIONS = {
    {t="Assume in phase", v="in_phase"},
    {t="Assume out of phase", v="out_of_phase"},
}

-- Stack a card below the previous one (or at the top). Cards inset 8px on each
-- side of the scroll viewport, matching the shell's structural gap. The CARD_W
-- callers use for internal layout must equal this anchored width.
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

local function CreateAlertsTab(container)
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()

    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 1180)
    local uiElements = TabManager:GetUI()
    local epsilonControls = TabManager:GetEpsilonControls()
    local M = TRP3FW.Theme.metrics
    local CARD_W = M.CARD_W

    -- ===== Preset logic (unchanged behavior) ===============================
    local function ApplyPreset(preset)
        local prevPhaseMode = TRP3FW.Prefs.phaseCheckMode
        local prevMapMode = TRP3FW.Prefs.mapCheckMode

        if preset == "relaxed" then
            TRP3FW.Prefs.phaseCheckMode = "off"; TRP3FW.Prefs.mapCheckMode = "alert"
            TRP3FW.Prefs.useWhoQuery = false; TRP3FW.Prefs.blockStartPhase = false
            TRP3FW.Prefs.ghostOnStartPhase = false; TRP3FW.Prefs.phaseCheckBatchMode = true
            TRP3FW.Prefs.phaseCheckRefundOnNoChange = false
        elseif preset == "balanced" then
            TRP3FW.Prefs.phaseCheckMode = "alert"; TRP3FW.Prefs.mapCheckMode = "alert"
            TRP3FW.Prefs.useWhoQuery = true; TRP3FW.Prefs.blockStartPhase = false
            TRP3FW.Prefs.ghostOnStartPhase = false
        elseif preset == "recommended" then
            TRP3FW.Prefs.phaseCheckMode = "alert_block"; TRP3FW.Prefs.mapCheckMode = "alert_block"
            TRP3FW.Prefs.useWhoQuery = true; TRP3FW.Prefs.blockStartPhase = true
            TRP3FW.Prefs.ghostOnStartPhase = false; TRP3FW.Prefs.spvpEnabled = true
        elseif preset == "strict" then
            TRP3FW.Prefs.phaseCheckMode = "alert_block"; TRP3FW.Prefs.mapCheckMode = "alert_block"
            TRP3FW.Prefs.useWhoQuery = true; TRP3FW.Prefs.blockStartPhase = true
            TRP3FW.Prefs.ghostOnStartPhase = false; TRP3FW.Prefs.spvpEnabled = true
            TRP3FW.Prefs.scanResponsePhaseMode = "block"; TRP3FW.Prefs.scanResponseMapMode = "block"
            TRP3FW.Prefs.scanResponseRequireNonce = false
        elseif preset == "ghost" then
            TRP3FW.Prefs.phaseCheckMode = "alert_ghost"; TRP3FW.Prefs.mapCheckMode = "alert_ghost"
            TRP3FW.Prefs.useWhoQuery = true; TRP3FW.Prefs.blockStartPhase = false
            TRP3FW.Prefs.ghostOnStartPhase = true; TRP3FW.Prefs.ghostProfileSwitch = true
            TRP3FW.Prefs.spvpEnabled = true
            TRP3FW.Prefs.scanResponsePhaseMode = "block"; TRP3FW.Prefs.scanResponseMapMode = "block"
            TRP3FW.Prefs.scanResponseRequireNonce = false
            if TRP3FW.EnsureBlankProfilesExist then TRP3FW:EnsureBlankProfilesExist() end
        end

        if preset == "strict" or preset == "recommended" or preset == "ghost" or preset == "balanced" or preset == "relaxed" then
            TRP3FW.Prefs.phaseCheckBatchMode = true
        end
        if preset == "strict" or preset == "recommended" or preset == "relaxed" then
            TRP3FW.Prefs.phaseCheckRefundOnNoChange = false
        end
        if TRP3FW.ShouldClearAllowedSenders and (TRP3FW:ShouldClearAllowedSenders(TRP3FW.Prefs.phaseCheckMode, prevPhaseMode) or
           TRP3FW:ShouldClearAllowedSenders(TRP3FW.Prefs.mapCheckMode, prevMapMode)) then
            local CI = TRP3FW.CacheInterface
            if CI then CI:Clear("allowedSenders") end
        end
        TRP3FW:RefreshUI()
        TRP3FW:Info("Applied preset: "..preset)
    end

    -- ===== Card 1: Quick presets + mode summary ============================
    local presetCard = stackCard(content, TabManager:CreateCard(content, "Quick presets", CARD_W), nil, CARD_W)
    local presets = {
        { key = "relaxed", label = "Relaxed", tooltip = "Phase Off, Map Alert, WHO Off, Batching On, Token Refund Off" },
        { key = "balanced", label = "Balanced", tooltip = "Phase Alert, Map Alert, WHO On, Batching On" },
        { key = "recommended", label = "Recommended", tooltip = "Phase/Map Alert+Block, WHO On, Start-phase block, Batching On, Token Refund Off" },
        { key = "strict", label = "Strict", tooltip = "Phase/Map Alert+Block, WHO On, Start-phase block, Scan replies block, Batching On, Token Refund Off" },
        { key = "ghost", label = "Ghosty", tooltip = "Phase/Map Alert+Ghost, WHO On, Start-phase ghost+switch, Scan replies block, Batching On" },
    }
    local presetY = presetCard:NextY(30)
    -- Compute the button width from the card so five buttons + four gaps exactly
    -- fill the row (12px pad each side) without overflowing.
    local PBTN_GAP = 8
    local PBTN_W = math.floor((CARD_W - 24 - 4 * PBTN_GAP) / 5)
    local px = 12
    for _, preset in ipairs(presets) do
        local btn = TabManager:CreateButton(presetCard, preset.label, PBTN_W, false)
        btn:SetPoint("TOPLEFT", px, presetY)
        btn:SetOnClick(function() ApplyPreset(preset.key) end)
        if preset.tooltip then
            btn:HookScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(preset.label, 1, 1, 1)
                GameTooltip:AddLine(preset.tooltip, nil, nil, nil, true)
                GameTooltip:Show()
            end)
            btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
        end
        px = px + PBTN_W + PBTN_GAP
        if px + PBTN_W > CARD_W - 12 then px = 12; presetY = presetY - 28 end
    end
    presetCard._cursorY = presetY - 34

    -- Current mode summary: a small key/value grid (label left, value gold)
    -- rather than a space-padded text blob. RefreshUI fills the .value fields.
    local Theme = TRP3FW.Theme
    local sumHdr = presetCard:CreateFontString(nil, "ARTWORK", Theme.fonts.SUB)
    sumHdr:SetPoint("TOPLEFT", 12, presetCard:NextY(20))
    sumHdr:SetText("Current modes")
    sumHdr:SetTextColor(Theme:Color("TEXT_MUTED"))

    uiElements.modeSummary = {}
    local function summaryRow(labelText)
        local rowY = presetCard:NextY(22)
        local lbl = presetCard:CreateFontString(nil, "ARTWORK", Theme.fonts.LABEL)
        lbl:SetPoint("TOPLEFT", 12, rowY); lbl:SetWidth(120); lbl:SetJustifyH("LEFT")
        lbl:SetText(labelText); lbl:SetTextColor(Theme:Color("TEXT_SECONDARY"))
        local val = presetCard:CreateFontString(nil, "ARTWORK", Theme.fonts.LABEL)
        val:SetPoint("TOPLEFT", 140, rowY); val:SetPoint("RIGHT", presetCard, "RIGHT", -12, 0)
        val:SetJustifyH("LEFT"); val:SetTextColor(Theme:Color("GOLD_TEXT"))
        return val
    end
    uiElements.modeSummary.phase = summaryRow("Different phase")
    uiElements.modeSummary.map = summaryRow("Different map")
    uiElements.modeSummary.who = summaryRow("WHO query")
    uiElements.modeSummary.scan = summaryRow("Scan replies")
    presetCard:FitHeight(12)

    -- ===== Card 2: Location checking =======================================
    local locCard = stackCard(content, TabManager:CreateCard(content, "Location checking", CARD_W), presetCard, CARD_W)

    local pcm = TabManager:CreateSkinnedDropdown(locCard, "Phase check mode",
        "How should TRP3FW respond when someone from a different phase requests your profile? Default: Alert.", 220, "phaseCheckMode")
    pcm:SetPoint("TOPLEFT", -4, locCard:NextY(56) - 16); uiElements.phaseCheckModeDropdown = pcm
    UIDropDownMenu_Initialize(pcm, function()
        for _, it in ipairs(MODE_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo(); info.text = it.t
            info.func = function()
                local prev = TRP3FW.Prefs.phaseCheckMode; TRP3FW.Prefs.phaseCheckMode = it.v; UIDropDownMenu_SetText(pcm, it.t)
                if it.v == "ghost" or it.v == "alert_ghost" then if TRP3FW.EnsureBlankProfilesExist then TRP3FW:EnsureBlankProfilesExist() end end
                if TRP3FW.ShouldClearAllowedSenders and TRP3FW:ShouldClearAllowedSenders(it.v, prev) then local CI = TRP3FW.CacheInterface; if CI then CI:Clear("allowedSenders") end end
                TRP3FW:RefreshUI()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local mcm = TabManager:CreateSkinnedDropdown(locCard, "Map check mode",
        "How should TRP3FW respond when someone from a different map requests your profile? Default: Alert.", 220, "mapCheckMode")
    mcm:SetPoint("TOPLEFT", -4, locCard:NextY(56)); uiElements.mapCheckModeDropdown = mcm
    UIDropDownMenu_Initialize(mcm, function()
        for _, it in ipairs(MODE_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo(); info.text = it.t
            info.func = function()
                local prev = TRP3FW.Prefs.mapCheckMode; TRP3FW.Prefs.mapCheckMode = it.v; UIDropDownMenu_SetText(mcm, it.t)
                if it.v == "ghost" or it.v == "alert_ghost" then if TRP3FW.EnsureBlankProfilesExist then TRP3FW:EnsureBlankProfilesExist() end end
                if TRP3FW.ShouldClearAllowedSenders and TRP3FW:ShouldClearAllowedSenders(it.v, prev) then local CI = TRP3FW.CacheInterface; if CI then CI:Clear("allowedSenders") end end
                TRP3FW:RefreshUI()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    uiElements.allowGroupPhaseBypass = TabManager:CreateToggle(locCard,
        "Auto-allow party/raid", "Party/raid members skip checks.", "allowGroupPhaseBypass")
    uiElements.allowGroupPhaseBypass:SetPoint("TOPLEFT", 12, locCard:NextY())
    uiElements.allowGroupPhaseBypass:SetPoint("RIGHT", locCard, "RIGHT", -12, 0)
    uiElements.allowGroupPhaseBypass:SetOnToggle(function(c) TRP3FW.Prefs.allowGroupPhaseBypass = c end)

    uiElements.useWhoQuery = TabManager:CreateToggle(locCard,
        "Use WHO query", "Use WHO queries as a secondary location check (Epsilon only).", "useWhoQuery")
    uiElements.useWhoQuery:SetPoint("TOPLEFT", 12, locCard:NextY())
    uiElements.useWhoQuery:SetPoint("RIGHT", locCard, "RIGHT", -12, 0)
    uiElements.useWhoQuery:SetOnToggle(function(c) TRP3FW.Prefs.useWhoQuery = c end)
    if epsilonControls then table.insert(epsilonControls, uiElements.useWhoQuery) end

    uiElements.muteTargetSound = TabManager:CreateToggle(locCard,
        "Mute target sound", "Silence only the target-select sound caused by automated phase checks. Your manual targeting sound and all other audio are unaffected (Epsilon only).", "muteTargetSound")
    uiElements.muteTargetSound:SetPoint("TOPLEFT", 12, locCard:NextY())
    uiElements.muteTargetSound:SetPoint("RIGHT", locCard, "RIGHT", -12, 0)
    uiElements.muteTargetSound:SetOnToggle(function(c) TRP3FW.Prefs.muteTargetSound = c end)
    if epsilonControls then table.insert(epsilonControls, uiElements.muteTargetSound) end

    uiElements.pausePhaseCheckOnInspect = TabManager:CreateToggle(locCard,
        "Pause during inspect", "Skip automated phase-check targeting while the armory/inspect window is open, so it doesn't disrupt the view (Epsilon only).", "pausePhaseCheckOnInspect")
    uiElements.pausePhaseCheckOnInspect:SetPoint("TOPLEFT", 12, locCard:NextY())
    uiElements.pausePhaseCheckOnInspect:SetPoint("RIGHT", locCard, "RIGHT", -12, 0)
    uiElements.pausePhaseCheckOnInspect:SetOnToggle(function(c) TRP3FW.Prefs.pausePhaseCheckOnInspect = c end)
    if epsilonControls then table.insert(epsilonControls, uiElements.pausePhaseCheckOnInspect) end

    -- If inspect stays open past the 10s retry window, resolve the check as this phase
    -- result and let the normal phase/map modes + SPVP fallback decide the action.
    local itr = TabManager:CreateSkinnedDropdown(locCard, "If inspect stays open",
        "When 'Pause during inspect' is on and the inspect window is still open after 10 seconds of retries, treat the player as this phase result. Your Phase/Map check modes (and SPVP) then decide the action.", 220, "inspectTimeoutResolution")
    itr:SetPoint("TOPLEFT", -4, locCard:NextY(56) - 16); uiElements.inspectTimeoutResolutionDropdown = itr
    UIDropDownMenu_Initialize(itr, function()
        for _, opt in ipairs(INSPECT_TIMEOUT_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo(); info.text = opt.t
            info.func = function()
                TRP3FW.Prefs.inspectTimeoutResolution = opt.v; UIDropDownMenu_SetText(itr, opt.t)
            end
            info.checked = (TRP3FW.Prefs.inspectTimeoutResolution == opt.v)
            UIDropDownMenu_AddButton(info)
        end
    end)
    if epsilonControls then table.insert(epsilonControls, itr) end
    -- Last row advanced ROW(30) for a 22-tall pill = 8 residual below it;
    -- +4 makes the bottom gap 12, matching the 12px side insets.
    locCard:FitHeight(4)

    -- ===== Card 3: Ghost mode ==============================================
    local ghostCard = stackCard(content, TabManager:CreateCard(content, "Ghost mode", CARD_W), locCard, CARD_W)

    local gpd = TabManager:CreateSkinnedDropdown(ghostCard, "Ghost profile",
        "Choose which profile to send in ghost mode.", 300, "ghostProfileName")
    uiElements.ghostProfileDropdown = gpd
    ghostCard:AddRow(function(y)
        gpd:ClearAllPoints()
        gpd:SetPoint("TOPLEFT", ghostCard, "TOPLEFT", -4, y - 16)
    end, 48, gpd.complexityLevel, { gpd })
    UIDropDownMenu_Initialize(gpd, function()
        local profiles = TRP3FW:GetAllProfiles()
        if #profiles > 0 then
            for _, p in ipairs(profiles) do
                local info = UIDropDownMenu_CreateInfo(); info.text = p.name; if p.isCurrent then info.text = info.text.." (current)" end
                info.func = function()
                    TRP3FW.Prefs.ghostProfileID = p.id; TRP3FW.Prefs.ghostProfileName = p.name; UIDropDownMenu_SetText(gpd, p.name)
                    if p.name == "TRP3FW_BLANK" and TRP3FW.EnsureBlankProfilesExist then TRP3FW:EnsureBlankProfilesExist() end
                end
                info.checked = (TRP3FW.Prefs.ghostProfileID == p.id); UIDropDownMenu_AddButton(info)
            end
        else
            local info = UIDropDownMenu_CreateInfo(); info.text = "(No profiles found)"; info.disabled = true; info.notCheckable = true; UIDropDownMenu_AddButton(info)
        end
    end)

    -- Epsilon warning: RefreshUI owns its visibility (shown when the API is
    -- MISSING), so the row reserves space but never touches shown state.
    uiElements.epsilonWarning = ghostCard:CreateFontString(nil, "OVERLAY", TRP3FW.Theme.fonts.SUB)
    uiElements.epsilonWarning:SetText("|cffff6600Epsilon-only options hidden (API unavailable)|r")
    uiElements.epsilonWarning:Hide()
    ghostCard:AddRow(function(y)
        uiElements.epsilonWarning:ClearAllPoints()
        uiElements.epsilonWarning:SetPoint("TOPLEFT", ghostCard, "TOPLEFT", 12, y)
    end, 20, 1)

    local function ghostToggleRow(key, label, tip, onToggle)
        local t = TabManager:CreateToggle(ghostCard, label, tip, key)
        t:SetOnToggle(onToggle)
        uiElements[key] = t
        if epsilonControls then table.insert(epsilonControls, t) end
        ghostCard:AddRow(function(y)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", ghostCard, "TOPLEFT", 12, y)
            t:SetPoint("RIGHT", ghostCard, "RIGHT", -12, 0)
        end, TRP3FW.Theme.metrics.ROW, t.complexityLevel, { t })
        return t
    end
    ghostToggleRow("blockStartPhase", "Block in start phase", "Block transmissions in phase 169.",
        function(c) TRP3FW.Prefs.blockStartPhase = c; if TRP3FW.Prefs.ghostOnStartPhase and TRP3FW.EnsureBlankProfilesExist then TRP3FW:EnsureBlankProfilesExist() end end)
    ghostToggleRow("ghostOnStartPhase", "Ghost in start phase", "Send blank profile in phase 169.",
        function(c) TRP3FW.Prefs.ghostOnStartPhase = c; if TRP3FW.EnsureBlankProfilesExist then TRP3FW:EnsureBlankProfilesExist() end end)
    ghostToggleRow("ghostProfileSwitch", "Auto-switch to blank profile", "Switch to blank profile in 169/1605.",
        function(c) TRP3FW.Prefs.ghostProfileSwitch = c; if TRP3FW.EnsureBlankProfilesExist then TRP3FW:EnsureBlankProfilesExist() end end)
    ghostToggleRow("ghostProfileWhitelistEnabled", "Exclude phases/maps", "Keep real profile in specific areas.",
        function(c)
            TRP3FW.Prefs.ghostProfileWhitelistEnabled = c
            if uiElements.ghostProfileWhitelistEdit then if c then uiElements.ghostProfileWhitelistEdit:Enable() else uiElements.ghostProfileWhitelistEdit:Disable() end; uiElements.ghostProfileWhitelistEdit:SetAlpha(c and 1 or 0.5) end
        end)

    -- Multiline exclusion whitelist, in a slate well. The visual box is the
    -- backdrop (-6 left / +26 right of the scroll). Match the 12px interior inset
    -- box left = 18-6 = 12, box right = 18+(W-56)+26 = W-12.
    local wls = CreateFrame("ScrollFrame", nil, ghostCard, "UIPanelScrollFrameTemplate")
    wls:SetSize(CARD_W - 56, 90); uiElements.ghostProfileWhitelistScroll = wls
    local wle = CreateFrame("EditBox", nil, wls); wle:SetMultiLine(true); wle:SetFontObject(TRP3FW.Theme.fonts.SUB); wle:SetWidth(CARD_W - 76); wle:SetHeight(90); wle:SetAutoFocus(false); wle:SetMaxLetters(3000)
    wle:SetText(TRP3FW.Prefs.ghostProfileWhitelist or ""); wle:SetScript("OnTextChanged", function(self) TRP3FW.Prefs.ghostProfileWhitelist = self:GetText() end)
    wle:SetScript("OnEscapePressed", wle.ClearFocus)
    wls:SetScrollChild(wle); uiElements.ghostProfileWhitelistEdit = wle

    local wlbg = CreateFrame("Frame", nil, ghostCard, "BackdropTemplate")
    wlbg:SetPoint("TOPLEFT", wls, -6, 6); wlbg:SetPoint("BOTTOMRIGHT", wls, 26, -6)
    wlbg:SetBackdrop(TRP3FW.Theme.BACKDROP_CHIP)
    wlbg:SetBackdropColor(TRP3FW.Theme:Color("INSET"))
    wlbg:SetBackdropBorderColor(TRP3FW.Theme:Color("BORDER_STRONG"))
    TabManager:AddComplexityWidget(wle, "ghostProfileWhitelist"); TabManager:AddComplexityWidget(wls, "ghostProfileWhitelist"); TabManager:AddComplexityWidget(wlbg, "ghostProfileWhitelist")
    if epsilonControls then table.insert(epsilonControls, wle); table.insert(epsilonControls, wls); table.insert(epsilonControls, wlbg) end
    ghostCard:AddRow(function(y)
        wls:ClearAllPoints()
        wls:SetPoint("TOPLEFT", ghostCard, "TOPLEFT", 18, y)
    end, 96, wle.complexityLevel, { wls, wle, wlbg })
    ghostCard:Reflow()

    -- ===== Card 4: Overrides ===============================================
    local ovCard = stackCard(content, TabManager:CreateCard(content, "Profile overrides", CARD_W), ghostCard, CARD_W)
    uiElements.profileOverrides = {}
    TRP3FW.Prefs.ghostProfileOverrides = TRP3FW.Prefs.ghostProfileOverrides or {}

    local MAX_ROWS = 20
    local INITIAL_ROWS = 5
    local renderedRows = 0
    local addRowBtn

    -- Each override row is a reflowable row (level 3 = the overrides feature's
    -- complexity), so the whole card collapses to its header below Advanced.
    local function RenderOverrideRow(i)
        TRP3FW.Prefs.ghostProfileOverrides[i] = TRP3FW.Prefs.ghostProfileOverrides[i] or {}
        local entry = TRP3FW.Prefs.ghostProfileOverrides[i]
        local l = ovCard:CreateFontString(nil, "OVERLAY", TRP3FW.Theme.fonts.SUB); l:SetText(string.format("#%02d", i)); l:SetTextColor(TRP3FW.Theme:Color("TEXT_MUTED"))
        local cb = CreateFrame("EditBox", nil, ovCard, "InputBoxTemplate"); cb:SetSize(130, 20); cb:SetAutoFocus(false); cb:SetText(entry.match or "")
        cb:SetScript("OnTextChanged", function(self) entry.match = self:GetText() end)
        cb:SetScript("OnEscapePressed", cb.ClearFocus)

        local od = TabManager:CreateSkinnedDropdown(ovCard, nil, nil, 150, "ghostProfileOverrides")
        if od.label then od.label:Hide() end
        UIDropDownMenu_Initialize(od, function()
            local info = UIDropDownMenu_CreateInfo(); info.text = "(Use global)"; info.func = function() entry.profileID = nil; entry.profileName = nil; UIDropDownMenu_SetText(od, "(Use global)") end; UIDropDownMenu_AddButton(info)
            for _, p in ipairs(TRP3FW:GetAllProfiles()) do
                info = UIDropDownMenu_CreateInfo(); info.text = p.name; info.func = function() entry.profileID = p.id; entry.profileName = p.name; UIDropDownMenu_SetText(od, p.name) end; UIDropDownMenu_AddButton(info)
            end
        end)
        UIDropDownMenu_SetText(od, entry.profileName or "(Use global)")
        table.insert(uiElements.profileOverrides, { edit = cb, dropdown = od })
        if epsilonControls then table.insert(epsilonControls, cb); table.insert(epsilonControls, od) end
        return ovCard:AddRow(function(y)
            l:ClearAllPoints();  l:SetPoint("TOPLEFT", ovCard, "TOPLEFT", 12, y - 4)
            cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", ovCard, "TOPLEFT", 48, y - 2)
            od:ClearAllPoints(); od:SetPoint("TOPLEFT", ovCard, "TOPLEFT", 182, y + 2)
        end, 34, 3, { l, cb, od })
    end

    local lastPopulated = 0
    for i = 1, MAX_ROWS do
        local e = TRP3FW.Prefs.ghostProfileOverrides[i]
        if e and ((e.match and e.match ~= "") or e.profileID) then lastPopulated = i end
    end
    local startCount = math.min(MAX_ROWS, math.max(INITIAL_ROWS, lastPopulated))
    for i = 1, startCount do RenderOverrideRow(i); renderedRows = i end

    addRowBtn = TabManager:CreateButton(ovCard, "+ Add row", 100, false)
    ovCard:AddRow(function(y)
        addRowBtn:ClearAllPoints()
        addRowBtn:SetPoint("TOPLEFT", ovCard, "TOPLEFT", 12, y)
    end, 28, 3, { addRowBtn })
    addRowBtn:SetOnClick(function()
        if renderedRows < MAX_ROWS then
            renderedRows = renderedRows + 1
            local newRow = RenderOverrideRow(renderedRows)  -- appended after the button row
            table.remove(ovCard._rows)                       -- pop it back off
            table.insert(ovCard._rows, #ovCard._rows, newRow) -- insert before the button row
            ovCard:Reflow()
            if renderedRows >= MAX_ROWS then addRowBtn:Disable() end
        end
    end)
    if renderedRows >= MAX_ROWS then addRowBtn:Disable() end
    ovCard:Reflow()

    return scrollFrame
end

TabManager:RegisterTab("alerts", "Protection", "Protection & Blocking", CreateAlertsTab, function() TRP3FW:RefreshUI() end, "Interface\\Icons\\Ability_Warrior_ShieldWall")
