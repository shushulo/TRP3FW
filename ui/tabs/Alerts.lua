-- ui/tabs/Alerts.lua
-- Protection & Blocking settings tab for TRP3FW (migrated to the skinned kit)
--
-- Preserves every uiElements key, epsilon registration, and behavior the old
-- tab and RefreshUI depend on (phaseCheckModeDropdown, mapCheckModeDropdown,
-- ghostProfileDropdown, notificationModeSummaryNotify, the check toggles, the
-- ghostProfileWhitelist* widgets, epsilonWarning, and profileOverrides), just
-- reorganized into slate cards with skinned controls.

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

local MODE_OPTIONS = {
    {t="Off", v="off"}, {t="Statistics only", v="statistics"}, {t="Notify only", v="alert"},
    {t="Block (silent)", v="block"}, {t="Send blank profile", v="ghost"},
    {t="Block (with notification)", v="alert_block"}, {t="Send blank profile (with notification)", v="alert_ghost"},
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

    -- Current mode summary
    local sumHdr = presetCard:CreateFontString(nil, "ARTWORK", TRP3FW.Theme.fonts.SUB)
    sumHdr:SetPoint("TOPLEFT", 8, presetCard:NextY(18))
    sumHdr:SetText("Current modes")
    sumHdr:SetTextColor(TRP3FW.Theme:Color("TEXT_MUTED"))
    uiElements.notificationModeSummaryNotify = presetCard:CreateFontString(nil, "ARTWORK", TRP3FW.Theme.fonts.SUB)
    uiElements.notificationModeSummaryNotify:SetPoint("TOPLEFT", 8, presetCard:NextY(44))
    uiElements.notificationModeSummaryNotify:SetWidth(CARD_W - 24)
    uiElements.notificationModeSummaryNotify:SetJustifyH("LEFT")
    uiElements.notificationModeSummaryNotify:SetTextColor(TRP3FW.Theme:Color("TEXT_PRIMARY"))
    presetCard:FitHeight(10)

    -- ===== Card 2: Location checking =======================================
    local locCard = stackCard(content, TabManager:CreateCard(content, "Location checking", CARD_W), presetCard, CARD_W)

    local pcm = TabManager:CreateSkinnedDropdown(locCard, "Phase check mode",
        "How should TRP3FW respond when someone from a different phase requests your profile? Default: Alert.", 220, "phaseCheckMode")
    pcm:SetPoint("TOPLEFT", -8, locCard:NextY(56) - 16); uiElements.phaseCheckModeDropdown = pcm
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
    mcm:SetPoint("TOPLEFT", -8, locCard:NextY(56)); uiElements.mapCheckModeDropdown = mcm
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
    uiElements.allowGroupPhaseBypass:SetPoint("TOPLEFT", 8, locCard:NextY())
    uiElements.allowGroupPhaseBypass:SetPoint("RIGHT", locCard, "RIGHT", -8, 0)
    uiElements.allowGroupPhaseBypass:SetOnToggle(function(c) TRP3FW.Prefs.allowGroupPhaseBypass = c end)

    uiElements.useWhoQuery = TabManager:CreateToggle(locCard,
        "Use WHO query", "Use WHO queries as a secondary location check (Epsilon only).", "useWhoQuery")
    uiElements.useWhoQuery:SetPoint("TOPLEFT", 8, locCard:NextY())
    uiElements.useWhoQuery:SetPoint("RIGHT", locCard, "RIGHT", -8, 0)
    uiElements.useWhoQuery:SetOnToggle(function(c) TRP3FW.Prefs.useWhoQuery = c end)
    if epsilonControls then table.insert(epsilonControls, uiElements.useWhoQuery) end
    -- Toggle rows advance 30 for 22-tall pills, leaving 8 residual; pad 0 keeps
    -- the bottom gap at exactly 8 like every other gap.
    locCard:FitHeight(0)

    -- ===== Card 3: Ghost mode ==============================================
    local ghostCard = stackCard(content, TabManager:CreateCard(content, "Ghost mode", CARD_W), locCard, CARD_W)

    local gpd = TabManager:CreateSkinnedDropdown(ghostCard, "Ghost profile",
        "Choose which profile to send in ghost mode.", 300, "ghostProfileName")
    gpd:SetPoint("TOPLEFT", -8, ghostCard:NextY(56) - 16); uiElements.ghostProfileDropdown = gpd
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

    uiElements.epsilonWarning = ghostCard:CreateFontString(nil, "OVERLAY", TRP3FW.Theme.fonts.SUB)
    uiElements.epsilonWarning:SetPoint("TOPLEFT", 8, ghostCard:NextY(20))
    uiElements.epsilonWarning:SetText("|cffff6600Epsilon-only options hidden (API unavailable)|r")
    uiElements.epsilonWarning:Hide()

    uiElements.blockStartPhase = TabManager:CreateToggle(ghostCard,
        "Block in start phase", "Block transmissions in phase 169.", "blockStartPhase")
    uiElements.blockStartPhase:SetPoint("TOPLEFT", 8, ghostCard:NextY())
    uiElements.blockStartPhase:SetPoint("RIGHT", ghostCard, "RIGHT", -8, 0)
    uiElements.blockStartPhase:SetOnToggle(function(c) TRP3FW.Prefs.blockStartPhase = c; if TRP3FW.Prefs.ghostOnStartPhase and TRP3FW.EnsureBlankProfilesExist then TRP3FW:EnsureBlankProfilesExist() end end)
    if epsilonControls then table.insert(epsilonControls, uiElements.blockStartPhase) end

    uiElements.ghostOnStartPhase = TabManager:CreateToggle(ghostCard,
        "Ghost in start phase", "Send blank profile in phase 169.", "ghostOnStartPhase")
    uiElements.ghostOnStartPhase:SetPoint("TOPLEFT", 8, ghostCard:NextY())
    uiElements.ghostOnStartPhase:SetPoint("RIGHT", ghostCard, "RIGHT", -8, 0)
    uiElements.ghostOnStartPhase:SetOnToggle(function(c) TRP3FW.Prefs.ghostOnStartPhase = c; if TRP3FW.EnsureBlankProfilesExist then TRP3FW:EnsureBlankProfilesExist() end end)
    if epsilonControls then table.insert(epsilonControls, uiElements.ghostOnStartPhase) end

    uiElements.ghostProfileSwitch = TabManager:CreateToggle(ghostCard,
        "Auto-switch to blank profile", "Switch to blank profile in 169/1605.", "ghostProfileSwitch")
    uiElements.ghostProfileSwitch:SetPoint("TOPLEFT", 8, ghostCard:NextY())
    uiElements.ghostProfileSwitch:SetPoint("RIGHT", ghostCard, "RIGHT", -8, 0)
    uiElements.ghostProfileSwitch:SetOnToggle(function(c) TRP3FW.Prefs.ghostProfileSwitch = c; if TRP3FW.EnsureBlankProfilesExist then TRP3FW:EnsureBlankProfilesExist() end end)
    if epsilonControls then table.insert(epsilonControls, uiElements.ghostProfileSwitch) end

    uiElements.ghostProfileWhitelistEnabled = TabManager:CreateToggle(ghostCard,
        "Exclude phases/maps", "Keep real profile in specific areas.", "ghostProfileWhitelistEnabled")
    uiElements.ghostProfileWhitelistEnabled:SetPoint("TOPLEFT", 8, ghostCard:NextY())
    uiElements.ghostProfileWhitelistEnabled:SetPoint("RIGHT", ghostCard, "RIGHT", -8, 0)
    uiElements.ghostProfileWhitelistEnabled:SetOnToggle(function(c)
        TRP3FW.Prefs.ghostProfileWhitelistEnabled = c
        if uiElements.ghostProfileWhitelistEdit then if c then uiElements.ghostProfileWhitelistEdit:Enable() else uiElements.ghostProfileWhitelistEdit:Disable() end; uiElements.ghostProfileWhitelistEdit:SetAlpha(c and 1 or 0.5) end
    end)
    if epsilonControls then table.insert(epsilonControls, uiElements.ghostProfileWhitelistEnabled) end

    -- Multiline exclusion whitelist, in a slate well. The visual box is the
    -- backdrop (-6 left / +26 right of the scroll). Match the 8px interior inset
    -- (== all card gaps): box left = 14-6 = 8, box right = 14+(W-48)+26 = W-8.
    local wlY = ghostCard:NextY(96)
    local wls = CreateFrame("ScrollFrame", nil, ghostCard, "UIPanelScrollFrameTemplate")
    wls:SetPoint("TOPLEFT", 14, wlY); wls:SetSize(CARD_W - 48, 90); uiElements.ghostProfileWhitelistScroll = wls
    local wle = CreateFrame("EditBox", nil, wls); wle:SetMultiLine(true); wle:SetFontObject(TRP3FW.Theme.fonts.SUB); wle:SetWidth(CARD_W - 68); wle:SetHeight(90); wle:SetAutoFocus(false); wle:SetMaxLetters(3000)
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
    -- Box bottom is 6 below the scroll (96-90); +8 pad = 8px gap to card edge.
    ghostCard:FitHeight(8)

    -- ===== Card 4: Overrides ===============================================
    local ovCard = stackCard(content, TabManager:CreateCard(content, "Profile overrides", CARD_W), ghostCard, CARD_W)
    uiElements.profileOverrides = {}
    TRP3FW.Prefs.ghostProfileOverrides = TRP3FW.Prefs.ghostProfileOverrides or {}

    local MAX_ROWS = 20
    local INITIAL_ROWS = 5
    local renderedRows = 0
    local addRowBtn

    local function RenderOverrideRow(i)
        TRP3FW.Prefs.ghostProfileOverrides[i] = TRP3FW.Prefs.ghostProfileOverrides[i] or {}
        local entry = TRP3FW.Prefs.ghostProfileOverrides[i]
        local rowY = ovCard:NextY(34)
        local l = ovCard:CreateFontString(nil, "OVERLAY", TRP3FW.Theme.fonts.SUB); l:SetPoint("TOPLEFT", 8, rowY - 4); l:SetText(string.format("#%02d", i)); l:SetTextColor(TRP3FW.Theme:Color("TEXT_MUTED"))
        local cb = CreateFrame("EditBox", nil, ovCard, "InputBoxTemplate"); cb:SetSize(130, 20); cb:SetAutoFocus(false); cb:SetPoint("TOPLEFT", 48, rowY - 2); cb:SetText(entry.match or "")
        cb:SetScript("OnTextChanged", function(self) entry.match = self:GetText() end)
        cb:SetScript("OnEscapePressed", cb.ClearFocus)

        local od = TabManager:CreateSkinnedDropdown(ovCard, nil, nil, 150, "ghostProfileOverrides")
        od:SetPoint("TOPLEFT", 182, rowY + 2)
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
    end

    local lastPopulated = 0
    for i = 1, MAX_ROWS do
        local e = TRP3FW.Prefs.ghostProfileOverrides[i]
        if e and ((e.match and e.match ~= "") or e.profileID) then lastPopulated = i end
    end
    local startCount = math.min(MAX_ROWS, math.max(INITIAL_ROWS, lastPopulated))
    for i = 1, startCount do RenderOverrideRow(i); renderedRows = i end

    -- Place the Add button at the current cursor; on click, render the next row
    -- at the button's slot and re-place the button just below it.
    local function placeAddButton()
        addRowBtn:ClearAllPoints()
        addRowBtn:SetPoint("TOPLEFT", 8, ovCard._cursorY)
    end
    addRowBtn = TabManager:CreateButton(ovCard, "+ Add row", 100, false)
    placeAddButton()
    addRowBtn:SetOnClick(function()
        if renderedRows < MAX_ROWS then
            renderedRows = renderedRows + 1
            RenderOverrideRow(renderedRows)  -- consumes the slot the button was in
            placeAddButton()                 -- move button below the new row
            ovCard:FitHeight(32)  -- 24px button + 8 gap below
            if renderedRows >= MAX_ROWS then addRowBtn:Disable() end
        end
    end)
    if renderedRows >= MAX_ROWS then addRowBtn:Disable() end
    ovCard._cursorY = ovCard._cursorY - 24  -- reserve the button's own height
    ovCard:FitHeight(8)

    return scrollFrame
end

TabManager:RegisterTab("alerts", "Protection", "Protection & Blocking", CreateAlertsTab, function() TRP3FW:RefreshUI() end, "Interface\\Icons\\Ability_Warrior_ShieldWall")
