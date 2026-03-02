-- ui/tabs/Alerts.lua
-- Alerts & Blocking settings tab for TRP3FW

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

local function CreateAlertsTab(container)
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()
    
    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 1500)
    local uiElements = TabManager:GetUI()
    local epsilonControls = TabManager:GetEpsilonControls()
    local y = -10

    -- Quick presets
    local function ApplyPreset(preset)
        local prevPhaseMode = TRP3FW.Prefs.phaseCheckMode
        local prevMapMode = TRP3FW.Prefs.mapCheckMode

        if preset == "relaxed" then
            TRP3FW.Prefs.phaseCheckMode = "off"
            TRP3FW.Prefs.mapCheckMode = "alert"
            TRP3FW.Prefs.useWhoQuery = false
            TRP3FW.Prefs.blockStartPhase = false
            TRP3FW.Prefs.ghostOnStartPhase = false
            TRP3FW.Prefs.phaseCheckBatchMode = true
            TRP3FW.Prefs.phaseCheckRefundOnNoChange = false

        elseif preset == "balanced" then
            TRP3FW.Prefs.phaseCheckMode = "alert"
            TRP3FW.Prefs.mapCheckMode = "alert"
            TRP3FW.Prefs.useWhoQuery = true
            TRP3FW.Prefs.blockStartPhase = false
            TRP3FW.Prefs.ghostOnStartPhase = false

        elseif preset == "recommended" then
            TRP3FW.Prefs.phaseCheckMode = "alert_block"
            TRP3FW.Prefs.mapCheckMode = "alert_block"
            TRP3FW.Prefs.useWhoQuery = true
            TRP3FW.Prefs.blockStartPhase = true
            TRP3FW.Prefs.ghostOnStartPhase = false
            TRP3FW.Prefs.spvpEnabled = true

        elseif preset == "strict" then
            TRP3FW.Prefs.phaseCheckMode = "alert_block"
            TRP3FW.Prefs.mapCheckMode = "alert_block"
            TRP3FW.Prefs.useWhoQuery = true
            TRP3FW.Prefs.blockStartPhase = true
            TRP3FW.Prefs.ghostOnStartPhase = false
            TRP3FW.Prefs.spvpEnabled = true
            TRP3FW.Prefs.scanResponsePhaseMode = "block"
            TRP3FW.Prefs.scanResponseMapMode = "block"
            TRP3FW.Prefs.scanResponseRequireNonce = false

        elseif preset == "ghost" then
            TRP3FW.Prefs.phaseCheckMode = "alert_ghost"
            TRP3FW.Prefs.mapCheckMode = "alert_ghost"
            TRP3FW.Prefs.useWhoQuery = true
            TRP3FW.Prefs.blockStartPhase = false
            TRP3FW.Prefs.ghostOnStartPhase = true
            TRP3FW.Prefs.ghostProfileSwitch = true
            TRP3FW.Prefs.spvpEnabled = true
            TRP3FW.Prefs.scanResponsePhaseMode = "block"
            TRP3FW.Prefs.scanResponseMapMode = "block"
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

    TabManager:CreateSectionHeader(content, "Quick Presets", y)
    y = y - 35

    local presets = {
        { key = "relaxed", label = "Relaxed", tooltip = "Phase Off, Map Alert, WHO Off, Batching On, Token Refund Off" },
        { key = "balanced", label = "Balanced", tooltip = "Phase Alert, Map Alert, WHO On, Batching On" },
        { key = "recommended", label = "Recommended", tooltip = "Phase/Map Alert+Block, WHO On, Start-phase block, Batching On, Token Refund Off" },
        { key = "strict", label = "Strict", tooltip = "Phase/Map Alert+Block, WHO On, Start-phase block, Scan replies block, Batching On, Token Refund Off" },
        { key = "ghost", label = "Ghosty", tooltip = "Phase/Map Alert+Ghost, WHO On, Start-phase ghost+switch, Scan replies block, Batching On" },
    }

    local presetX = 20
    for _, preset in ipairs(presets) do
        local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        btn:SetSize(100, 24)
        btn:SetPoint("TOPLEFT", presetX, y)
        btn:SetText(preset.label)
        if preset.tooltip then
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(preset.label, 1, 1, 1)
                GameTooltip:AddLine(preset.tooltip, nil, nil, nil, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        btn:SetScript("OnClick", function() ApplyPreset(preset.key) end)
        presetX = presetX + 110
    end

    y = y - 40
    TabManager:CreateSectionHeader(content, "Location Checking", y)
    y = y - 45

    local pcm, pcl = TabManager:CreateDropdown(content, "Phase Check Mode", "How should TRP3FW respond when someone from a different phase requests your profile? Default: Alert.", 200, "phaseCheckMode")
    pcm:SetPoint("TOPLEFT", 20, y); uiElements.phaseCheckModeDropdown = pcm
    UIDropDownMenu_Initialize(pcm, function(self, level)
        local l = { {t="Off", v="off"}, {t="Statistics Only", v="statistics"}, {t="Alert", v="alert"}, {t="Block", v="block"}, {t="Ghost (Blank Profile)", v="ghost"}, {t="Alert + Block", v="alert_block"}, {t="Alert + Ghost", v="alert_ghost"} }
        for _, it in ipairs(l) do
            local info = UIDropDownMenu_CreateInfo(); info.text=it.t; info.func=function() 
                local prev = TRP3FW.Prefs.phaseCheckMode; TRP3FW.Prefs.phaseCheckMode=it.v; UIDropDownMenu_SetText(pcm, it.t)
                if it.v=="ghost" or it.v=="alert_ghost" then if TRP3FW.EnsureBlankProfilesExist then TRP3FW:EnsureBlankProfilesExist() end end
                if TRP3FW.ShouldClearAllowedSenders and TRP3FW:ShouldClearAllowedSenders(it.v, prev) then local CI = TRP3FW.CacheInterface; if CI then CI:Clear("allowedSenders") end end
                TRP3FW:RefreshUI()
            end; UIDropDownMenu_AddButton(info)
        end
    end)
    
    local mcm, mcl = TabManager:CreateDropdown(content, "Map Check Mode", "How should TRP3FW respond when someone from a different map requests your profile? Default: Alert.", 200, "mapCheckMode")
    mcm:SetPoint("TOPLEFT", 300, y); uiElements.mapCheckModeDropdown = mcm
    UIDropDownMenu_Initialize(mcm, function(self, level)
        local l = { {t="Off", v="off"}, {t="Statistics Only", v="statistics"}, {t="Alert", v="alert"}, {t="Block", v="block"}, {t="Ghost (Blank Profile)", v="ghost"}, {t="Alert + Block", v="alert_block"}, {t="Alert + Ghost", v="alert_ghost"} }
        for _, it in ipairs(l) do
            local info = UIDropDownMenu_CreateInfo(); info.text=it.t; info.func=function() 
                local prev = TRP3FW.Prefs.mapCheckMode; TRP3FW.Prefs.mapCheckMode=it.v; UIDropDownMenu_SetText(mcm, it.t)
                if it.v=="ghost" or it.v=="alert_ghost" then if TRP3FW.EnsureBlankProfilesExist then TRP3FW:EnsureBlankProfilesExist() end end
                if TRP3FW.ShouldClearAllowedSenders and TRP3FW:ShouldClearAllowedSenders(it.v, prev) then local CI = TRP3FW.CacheInterface; if CI then CI:Clear("allowedSenders") end end
                TRP3FW:RefreshUI()
            end; UIDropDownMenu_AddButton(info)
        end
    end)
    y = y - 65

    uiElements.allowGroupPhaseBypass = TabManager:CreateCheckbox(content, "Allow Party/Raid Auto-Allow", "Party/raid members skip checks.", "allowGroupPhaseBypass")
    uiElements.allowGroupPhaseBypass:SetPoint("TOPLEFT", 20, y)
    uiElements.allowGroupPhaseBypass:SetScript("OnClick", function(self) TRP3FW.Prefs.allowGroupPhaseBypass = self:GetChecked() end)
    y = y - 45

    TabManager:CreateSectionHeader(content, "Other Options", y)
    y = y - 50

    local gpd, gpl = TabManager:CreateDropdown(content, "Ghost Profile", "Choose which profile to send in ghost mode.", 300, "ghostProfileName")
    gpd:SetPoint("TOPLEFT", 20, y); uiElements.ghostProfileDropdown = gpd
    UIDropDownMenu_Initialize(gpd, function(self, level)
        local profiles = TRP3FW:GetAllProfiles()
        if #profiles > 0 then
            for _, p in ipairs(profiles) do
                local info = UIDropDownMenu_CreateInfo(); info.text=p.name; if p.isCurrent then info.text=info.text.." (current)" end
                info.func=function() 
                    TRP3FW.Prefs.ghostProfileID=p.id; 
                    TRP3FW.Prefs.ghostProfileName=p.name;
                    UIDropDownMenu_SetText(gpd, p.name); 
                    if p.name=="TRP3FW_BLANK" and TRP3FW.EnsureBlankProfilesExist then TRP3FW:EnsureBlankProfilesExist() end 
                end
                info.checked=(TRP3FW.Prefs.ghostProfileID==p.id); UIDropDownMenu_AddButton(info)
            end
        else
            local info = UIDropDownMenu_CreateInfo(); info.text="(No profiles found)"; info.disabled=true; info.notCheckable=true; UIDropDownMenu_AddButton(info)
        end
    end)
    y = y - 60

    uiElements.epsilonWarning = content:CreateFontString(nil, "OVERLAY", "GameFontNormal"); uiElements.epsilonWarning:SetPoint("TOPLEFT", 20, y); uiElements.epsilonWarning:SetText("|cffff6600Epsilon-only options hidden (API unavailable)|r"); uiElements.epsilonWarning:Hide()
    y = y - 25

    uiElements.suppressAllWhoOutput = TabManager:CreateCheckbox(content, "Suppress WHO Output", "Hide all WHO results in chat.", "suppressAllWhoOutput")
    uiElements.suppressAllWhoOutput:SetPoint("TOPLEFT", 20, y)
    uiElements.suppressAllWhoOutput:SetScript("OnClick", function(self) TRP3FW.Prefs.suppressAllWhoOutput = self:GetChecked() end)
    if epsilonControls then table.insert(epsilonControls, uiElements.suppressAllWhoOutput) end
    y = y - 30

    uiElements.blockStartPhase = TabManager:CreateCheckbox(content, "Block in Start Phase", "Block transmissions in phase 169.", "blockStartPhase")
    uiElements.blockStartPhase:SetPoint("TOPLEFT", 20, y)
    uiElements.blockStartPhase:SetScript("OnClick", function(self) TRP3FW.Prefs.blockStartPhase = self:GetChecked(); if TRP3FW.Prefs.ghostOnStartPhase and TRP3FW.EnsureBlankProfilesExist then TRP3FW:EnsureBlankProfilesExist() end end)
    if epsilonControls then table.insert(epsilonControls, uiElements.blockStartPhase) end
    y = y - 30

    uiElements.ghostOnStartPhase = TabManager:CreateCheckbox(content, "Ghost Mode in Start Phase", "Send blank profile in phase 169.", "ghostOnStartPhase")
    uiElements.ghostOnStartPhase:SetPoint("TOPLEFT", 40, y)
    uiElements.ghostOnStartPhase:SetScript("OnClick", function(self) TRP3FW.Prefs.ghostOnStartPhase = self:GetChecked(); if TRP3FW.EnsureBlankProfilesExist then TRP3FW:EnsureBlankProfilesExist() end end)
    if epsilonControls then table.insert(epsilonControls, uiElements.ghostOnStartPhase) end
    y = y - 30

    uiElements.ghostProfileSwitch = TabManager:CreateCheckbox(content, "Auto-Switch to Blank Profile", "Switch to blank profile in 169/1605.", "ghostProfileSwitch")
    uiElements.ghostProfileSwitch:SetPoint("TOPLEFT", 20, y)
    uiElements.ghostProfileSwitch:SetScript("OnClick", function(self) TRP3FW.Prefs.ghostProfileSwitch = self:GetChecked(); if TRP3FW.EnsureBlankProfilesExist then TRP3FW:EnsureBlankProfilesExist() end end)
    if epsilonControls then table.insert(epsilonControls, uiElements.ghostProfileSwitch) end
    y = y - 45

    uiElements.ghostProfileWhitelistEnabled = TabManager:CreateCheckbox(content, "Exclude Phases/Maps", "Keep real profile in specific areas.", "ghostProfileWhitelistEnabled")
    uiElements.ghostProfileWhitelistEnabled:SetPoint("TOPLEFT", 20, y)
    uiElements.ghostProfileWhitelistEnabled:SetScript("OnClick", function(self) 
        TRP3FW.Prefs.ghostProfileWhitelistEnabled = self:GetChecked()
        if uiElements.ghostProfileWhitelistEdit then local e = self:GetChecked(); if e then uiElements.ghostProfileWhitelistEdit:Enable() else uiElements.ghostProfileWhitelistEdit:Disable() end; uiElements.ghostProfileWhitelistEdit:SetAlpha(e and 1 or 0.5) end
    end)
    if epsilonControls then table.insert(epsilonControls, uiElements.ghostProfileWhitelistEnabled) end
    y = y - 35

    local wlScroll, wlEdit = TabManager:CreateEditBox(content, "Exclusion entries:", nil, 500, "ghostProfileWhitelist") -- Using EditBox helper but we need multiline, so customizing
    wlEdit:Hide(); wlScroll:Hide() -- Hide the single line one created by helper
    
    local wls = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate"); wls:SetPoint("TOPLEFT", 40, y); wls:SetSize(460, 100); uiElements.ghostProfileWhitelistScroll = wls
    local wle = CreateFrame("EditBox", nil, wls); wle:SetMultiLine(true); wle:SetFontObject(ChatFontNormal); wle:SetWidth(440); wle:SetHeight(100); wle:SetAutoFocus(false); wle:SetMaxLetters(3000)
    wle:SetText(TRP3FW.Prefs.ghostProfileWhitelist or ""); wle:SetScript("OnTextChanged", function(self) TRP3FW.Prefs.ghostProfileWhitelist = self:GetText() end)
    wls:SetScrollChild(wle); uiElements.ghostProfileWhitelistEdit = wle

    local wlbg = CreateFrame("Frame", nil, content, "BackdropTemplate")
    wlbg:SetPoint("TOPLEFT", wls, -6, 6)
    wlbg:SetPoint("BOTTOMRIGHT", wls, 26, -6)
    wlbg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    wlbg:SetBackdropColor(0, 0, 0, 0.25)
    wlbg:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    TabManager:AddComplexityWidget(wle, "ghostProfileWhitelist"); TabManager:AddComplexityWidget(wls, "ghostProfileWhitelist"); TabManager:AddComplexityWidget(wlbg, "ghostProfileWhitelist")
    if epsilonControls then table.insert(epsilonControls, wle); table.insert(epsilonControls, wls); table.insert(epsilonControls, wlbg) end
    y = y - 120

    TabManager:CreateSectionHeader(content, "SPVP (Cryptographic Phase Verification)", y)
    y = y - 35
    
    local spvpInfoBox = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spvpInfoBox:SetPoint("TOPLEFT", 20, y)
    spvpInfoBox:SetWidth(560)
    spvpInfoBox:SetJustifyH("LEFT")
    spvpInfoBox:SetText("|cff00ccffℹ SPVP Info:|r SPVP uses cryptographic phase verification as a fallback when normal location checks fail. Requires phase owners to set a security key (salt). Players in the same phase can prove it cryptographically without physical proximity checks.")
    y = y - 60
    
    local smd, sml = TabManager:CreateDropdown(content, "SPVP Mode", "Control SPVP usage.", 220, "spvpMode")
    smd:SetPoint("TOPLEFT", 20, y); uiElements.spvpModeDropdown = smd
    UIDropDownMenu_Initialize(smd, function(self, level)
        local l = { {t="Off", v="off"}, {t="Optional (Post-Check)", v="optional"}, {t="Preferred (Pre-Check)", v="preferred"}, {t="Required (Strict)", v="required"} }
        for _, it in ipairs(l) do local info = UIDropDownMenu_CreateInfo(); info.text=it.t; info.func=function() TRP3FW.Prefs.spvpMode=it.v; TRP3FW.Prefs.spvpEnabled=(it.v~="off"); UIDropDownMenu_SetText(smd, it.t); TRP3FW:RefreshUI() end; UIDropDownMenu_AddButton(info) end
    end)
    if epsilonControls then table.insert(epsilonControls, smd) end
    y = y - 50

    uiElements.spvpAutoInitialize = TabManager:CreateCheckbox(content, "Auto-Initialize Salts", "Auto-generate keys for owned phases.", "spvpAutoInitialize")
    uiElements.spvpAutoInitialize:SetPoint("TOPLEFT", 40, y)
    uiElements.spvpAutoInitialize:SetScript("OnClick", function(self) TRP3FW.Prefs.spvpAutoInitialize = self:GetChecked() end)
    if epsilonControls then table.insert(epsilonControls, uiElements.spvpAutoInitialize) end
    y = y - 35

    local sbd = CreateFrame("Slider", "TRP3FW_SPVPBlockSlider", content, "OptionsSliderTemplate"); sbd:SetPoint("TOPLEFT", 40, y); sbd:SetWidth(300); sbd:SetMinMaxValues(10, 600); sbd:SetValueStep(10); sbd:SetObeyStepOnDrag(true)
    uiElements.spvpBlockDurationSlider = sbd
    local low, high, text = sbd.Low or getglobal(sbd:GetName().."Low"), sbd.High or getglobal(sbd:GetName().."High"), sbd.Text or getglobal(sbd:GetName().."Text")
    if low then low:SetText("10s") end; if high then high:SetText("10m") end
    sbd:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value/10)*10; TRP3FW.Prefs.spvpBlockDuration = value
        local t = self.Text or getglobal(self:GetName().."Text")
        if t then t:SetText("Block Duration: "..value.."s") end
    end)
    if epsilonControls then table.insert(epsilonControls, sbd) end
    y = y - 60

    local scd = CreateFrame("Slider", "TRP3FW_SPVPSaltCacheSlider", content, "OptionsSliderTemplate"); scd:SetPoint("TOPLEFT", 40, y); scd:SetWidth(300); scd:SetMinMaxValues(300, 43200); scd:SetValueStep(300); scd:SetObeyStepOnDrag(true)
    uiElements.spvpSaltCacheDurationSlider = scd
    local clow, chigh, ctext = scd.Low or getglobal(scd:GetName().."Low"), scd.High or getglobal(scd:GetName().."High"), scd.Text or getglobal(scd:GetName().."Text")
    if clow then clow:SetText("5m") end; if chigh then chigh:SetText("12h") end
    scd:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value/300)*300; TRP3FW.Prefs.spvpSaltCacheDuration = value
        local t = self.Text or getglobal(self:GetName().."Text")
        if t then t:SetText("Salt Cache: "..math.floor(value/60).."m") end
    end)
    if epsilonControls then table.insert(epsilonControls, scd) end
    y = y - 60

    uiElements.spvpSaltStatus = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); uiElements.spvpSaltStatus:SetPoint("TOPLEFT", 40, y); uiElements.spvpSaltStatus:SetText("Loading phase status...")
    if epsilonControls then table.insert(epsilonControls, uiElements.spvpSaltStatus) end
    y = y - 30

    uiElements.spvpSecureButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate"); uiElements.spvpSecureButton:SetSize(200, 24); uiElements.spvpSecureButton:SetPoint("TOPLEFT", 40, y); uiElements.spvpSecureButton:SetText("Secure This Phase")
    uiElements.spvpSecureButton:SetScript("OnClick", function()
        if not C_Epsilon or not (C_Epsilon.IsOwner() or C_Epsilon.IsOfficer()) then
            TRP3FW:Error("You must be a phase owner or officer to secure phases.")
            return
        end

        local phaseID = TRP3FW:GetCurrentPhaseID()
        local existingSalt = TRP3FW:GetPhaseSalt(phaseID, false)
        if existingSalt and existingSalt ~= "" then
            StaticPopup_Show("TRP3FW_SPVP_ROTATE_CONFIRM")
        else
            if TRP3FW.SecureCurrentPhase then TRP3FW:SecureCurrentPhase(); TRP3FW:RefreshUI() end
        end
    end)
    if epsilonControls then table.insert(epsilonControls, uiElements.spvpSecureButton) end
    y = y - 40

    TabManager:CreateSectionHeader(content, "Overrides", y)
    y = y - 35
    
    uiElements.profileOverrides = {}
    TRP3FW.Prefs.ghostProfileOverrides = TRP3FW.Prefs.ghostProfileOverrides or {}
    for i = 1, 20 do
        TRP3FW.Prefs.ghostProfileOverrides[i] = TRP3FW.Prefs.ghostProfileOverrides[i] or {}
        local entry = TRP3FW.Prefs.ghostProfileOverrides[i]
        local l = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); l:SetPoint("TOPLEFT", 40, y); l:SetText(string.format("#%02d", i))
        local cb = CreateFrame("EditBox", nil, content, "InputBoxTemplate"); cb:SetSize(140, 20); cb:SetAutoFocus(false); cb:SetPoint("TOPLEFT", 80, y-2); cb:SetText(entry.match or "")
        cb:SetScript("OnTextChanged", function(self) entry.match = self:GetText() end)
        
        local od = CreateFrame("Frame", nil, content, "UIDropDownMenuTemplate"); od:SetPoint("TOPLEFT", 232, y-2); UIDropDownMenu_SetWidth(od, 170)
        UIDropDownMenu_Initialize(od, function(self, level)
            local info = UIDropDownMenu_CreateInfo(); info.text="(Use global)"; info.func=function() entry.profileID=nil; UIDropDownMenu_SetText(od, "(Use global)") end; UIDropDownMenu_AddButton(info)
            for _, p in ipairs(TRP3FW:GetAllProfiles()) do
                info = UIDropDownMenu_CreateInfo(); info.text=p.name; info.func=function() entry.profileID=p.id; entry.profileName=p.name; UIDropDownMenu_SetText(od, p.name) end; UIDropDownMenu_AddButton(info)
            end
        end)
        UIDropDownMenu_SetText(od, entry.profileName or "(Use global)")
        table.insert(uiElements.profileOverrides, { edit = cb, dropdown = od })
        if epsilonControls then table.insert(epsilonControls, cb); table.insert(epsilonControls, od) end
        y = y - 34
    end

    return scrollFrame
end

TabManager:RegisterTab("alerts", "Alerts", "Alerts & Blocking", CreateAlertsTab, function() TRP3FW:RefreshUI() end)
