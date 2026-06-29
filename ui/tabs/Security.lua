-- ui/tabs/Security.lua
-- Security tab: whitelist bypass, scan reply controls, SPVP.
-- Created in Phase 3 of the UI UX restructure (consolidates trust/access-control
-- features previously scattered across Alerts and Notifications tabs).

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

local function CreateSecurityTab(container)
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()

    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 1250)
    local uiElements = TabManager:GetUI()
    local epsilonControls = TabManager:GetEpsilonControls()
    local y = -10

    -- ============================================================
    -- Whitelist Bypass (universal — not Epsilon-specific)
    -- ============================================================
    local whitelistSectionTop = y
    TabManager:CreateSectionHeader(content, "Whitelist Bypass", whitelistSectionTop)
    y = whitelistSectionTop - 35

    local whitelistInfo = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    whitelistInfo:SetPoint("TOPLEFT", 20, y)
    whitelistInfo:SetWidth(520)
    whitelistInfo:SetJustifyH("LEFT")
    whitelistInfo:SetText("|cffff6600Warning:|r Players listed below will |cffffff00always|r receive your current profile. Phase/map checks, alerts, blocking, ghost mode, and start-phase protections are skipped for them.")
    y = y - 45

    uiElements.whitelistEnabled = TabManager:CreateCheckbox(content, "Enable Whitelist Bypass", "Allow listed names to bypass all security checks and always receive your active profile.", "whitelistEnabled")
    uiElements.whitelistEnabled:SetPoint("TOPLEFT", 20, y)
    uiElements.whitelistEnabled:SetScript("OnClick", function(self)
        if self:GetChecked() then
            self:SetChecked(false)
            StaticPopup_Show("TRP3FW_WHITELIST_CONFIRM")
        else
            TRP3FW.Prefs.whitelistEnabled = false
            if TRP3FW.RefreshWhitelistCache then TRP3FW:RefreshWhitelistCache() end
            TRP3FW:RefreshUI()
        end
    end)
    y = y - 35

    local whitelistNameLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    whitelistNameLabel:SetPoint("TOPLEFT", 20, y)
    whitelistNameLabel:SetText("Names (one per line):")
    uiElements.whitelistNameLabel = whitelistNameLabel
    y = y - 20

    local whitelistScroll = CreateFrame("ScrollFrame", "TRP3FW_WhitelistScroll", content, "UIPanelScrollFrameTemplate")
    whitelistScroll:SetPoint("TOPLEFT", 20, y)
    whitelistScroll:SetSize(480, 100)
    uiElements.whitelistScroll = whitelistScroll

    local whitelistEdit = CreateFrame("EditBox", "TRP3FW_WhitelistEdit", whitelistScroll)
    whitelistEdit:SetMultiLine(true)
    whitelistEdit:SetFontObject(ChatFontNormal)
    whitelistEdit:SetWidth(460)
    whitelistEdit:SetHeight(90)
    whitelistEdit:SetAutoFocus(false)
    whitelistEdit:SetMaxLetters(3000)
    whitelistEdit:SetText(TRP3FW.Prefs.whitelistEntries or "")

    local function countWhitelistNames(text)
        local n = 0
        for line in string.gmatch(text or "", "[^\r\n]+") do
            if line:match("%S") then n = n + 1 end
        end
        return n
    end

    local function updateWhitelistCount(text)
        if not whitelistNameLabel then return end
        local n = countWhitelistNames(text)
        if n == 0 then
            whitelistNameLabel:SetText("Names (one per line):  |cffaaaaaa(empty)|r")
        elseif n == 1 then
            whitelistNameLabel:SetText("Names (one per line):  |cffaaaaaa(1 name)|r")
        else
            whitelistNameLabel:SetText(string.format("Names (one per line):  |cffaaaaaa(%d names)|r", n))
        end
    end
    updateWhitelistCount(TRP3FW.Prefs.whitelistEntries)

    local function sanitizeWhitelist(text)
        local seen = {}
        local out = {}
        for line in string.gmatch(text or "", "[^\r\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
                local clean = TRP3FW:SanitizePlayerName(trimmed) or TRP3FW:CleanPlayerName(trimmed)
                if clean and not seen[clean:lower()] then
                    seen[clean:lower()] = true
                    table.insert(out, clean)
                end
            end
        end
        return table.concat(out, "\n")
    end

    whitelistEdit:SetScript("OnTextChanged", function(self)
        TRP3FW.Prefs.whitelistEntries = self:GetText()
        updateWhitelistCount(self:GetText())
    end)
    whitelistEdit:SetScript("OnEditFocusLost", function(self)
        local cleaned = sanitizeWhitelist(self:GetText())
        if cleaned ~= self:GetText() then
            self:SetText(cleaned)
        end
        TRP3FW.Prefs.whitelistEntries = cleaned
        updateWhitelistCount(cleaned)
    end)
    whitelistScroll:SetScrollChild(whitelistEdit)

    local whitelistBG = CreateFrame("Frame", nil, content, "BackdropTemplate")
    whitelistBG:SetPoint("TOPLEFT", whitelistScroll, -6, 6)
    whitelistBG:SetPoint("BOTTOMRIGHT", whitelistScroll, 26, -6)
    whitelistBG:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    whitelistBG:SetBackdropColor(0, 0, 0, 0.25)
    whitelistBG:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    uiElements.whitelistEdit = whitelistEdit

    y = y - 120

    local whitelistSectionBottom = y
    local whitelistHeight = (whitelistSectionTop - whitelistSectionBottom) + 30
    local whitelistDanger = CreateFrame("Frame", nil, content, "BackdropTemplate")
    whitelistDanger:SetPoint("TOPLEFT", content, "TOPLEFT", 10, whitelistSectionTop + 20)
    whitelistDanger:SetPoint("RIGHT", content, "RIGHT", -2, 0)
    whitelistDanger:SetHeight(whitelistHeight)
    whitelistDanger:SetFrameStrata("BACKGROUND")
    whitelistDanger:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    whitelistDanger:SetBackdropColor(0.2, 0, 0, 0.2)
    whitelistDanger:SetBackdropBorderColor(0.8, 0.2, 0.2, 0.8)

    y = y - 20

    -- ============================================================
    -- Map Scan Reply Controls (Epsilon)
    -- ============================================================
    local scanGroup = CreateFrame("Frame", "TRP3FW_SecurityScanGroup", content, "BackdropTemplate")
    scanGroup:SetPoint("TOPLEFT", 10, y)
    scanGroup:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    scanGroup:SetBackdropColor(0, 0, 0, 0.2)
    scanGroup:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)

    local sgTitle = scanGroup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sgTitle:SetPoint("TOPLEFT", 15, -10); sgTitle:SetText("Map Scan Reply Controls"); sgTitle:SetTextColor(0.7, 0.7, 0.7)

    local scanY = y - 35
    uiElements.notifyOnScanResponse = TabManager:CreateCheckbox(content, "Show Scan Reply Notifications", "Controls notifications for scan replies.", "notifyOnScanResponse")
    uiElements.notifyOnScanResponse:SetPoint("TOPLEFT", 30, scanY)
    uiElements.notifyOnScanResponse:SetScript("OnClick", function(self) TRP3FW.Prefs.notifyOnScanResponse = self:GetChecked(); TRP3FW:RefreshUI() end)
    scanY = scanY - 30

    uiElements.notifyOnScanAllow = TabManager:CreateCheckbox(content, "Notify on Scan Allow", "Show notifications when scan replies are allowed.", "notifyOnScanAllow")
    uiElements.notifyOnScanAllow:SetPoint("TOPLEFT", 50, scanY)
    uiElements.notifyOnScanAllow:SetScript("OnClick", function(self) TRP3FW.Prefs.notifyOnScanAllow = self:GetChecked() end)
    scanY = scanY - 45

    local function createScanMode(label, key, yOff)
        local d, l = TabManager:CreateDropdown(content, label, "Behavior for scan replies.", 200, key)
        d:SetPoint("TOPLEFT", 30, yOff)
        UIDropDownMenu_Initialize(d, function(self, level)
            local m = { {text="Off", val="off"}, {text="Statistics Only", val="statistics"}, {text="Alert (send anyway)", val="alert"}, {text="Block (silent)", val="block"}, {text="Alert + Block", val="alert_block"} }
            for _, item in ipairs(m) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.text; info.func = function() TRP3FW.Prefs[key] = item.val; UIDropDownMenu_SetText(d, item.text); TRP3FW:RefreshUI() end
                info.checked = (TRP3FW.Prefs[key] == item.val); UIDropDownMenu_AddButton(info)
            end
        end)
        return d
    end

    uiElements.scanResponsePhaseModeDropdown = createScanMode("Different-Phase Behavior", "scanResponsePhaseMode", scanY)
    scanY = scanY - 50
    uiElements.scanResponseMapModeDropdown = createScanMode("Different-Map Behavior", "scanResponseMapMode", scanY)
    scanY = scanY - 50

    uiElements.scanResponseRequireNonce = TabManager:CreateCheckbox(content, "Require Nonce on Scan Replies", "When enabled, ignore map scan replies that do not include the issued nonce token (older scanners may be ignored).", "scanResponseRequireNonce")
    uiElements.scanResponseRequireNonce:SetPoint("TOPLEFT", 30, scanY)
    uiElements.scanResponseRequireNonce:SetScript("OnClick", function(self)
        TRP3FW.Prefs.scanResponseRequireNonce = self:GetChecked()
    end)
    scanY = scanY - 30

    uiElements.scanResponseCacheEnabled = TabManager:CreateCheckbox(content, "Cache Scan Requesters", "When replying to map scans, cache WHO results (if a WHO query ran). Does not add to interaction/send caches.", "scanResponseCacheEnabled")
    uiElements.scanResponseCacheEnabled:SetPoint("TOPLEFT", 30, scanY)
    uiElements.scanResponseCacheEnabled:SetScript("OnClick", function(self)
        TRP3FW.Prefs.scanResponseCacheEnabled = self:GetChecked()
    end)
    scanY = scanY - 30

    uiElements.scanResponseAllowCacheBypass = TabManager:CreateCheckbox(content, "Bypass with Existing Caches", "If scan requester is already in allowed or interaction cache (unrefreshed), skip the WHO gate and reply immediately.", "scanResponseAllowCacheBypass")
    uiElements.scanResponseAllowCacheBypass:SetPoint("TOPLEFT", 30, scanY)
    uiElements.scanResponseAllowCacheBypass:SetScript("OnClick", function(self)
        TRP3FW.Prefs.scanResponseAllowCacheBypass = self:GetChecked()
    end)
    scanY = scanY - 30

    uiElements.scanResponseAllowGroupBypass = TabManager:CreateCheckbox(content, "Always Allow Party/Raid", "If the scan requester is in your party or raid, always reply (skips phase/map/WHO gates).", "scanResponseAllowGroupBypass")
    uiElements.scanResponseAllowGroupBypass:SetPoint("TOPLEFT", 30, scanY)
    uiElements.scanResponseAllowGroupBypass:SetScript("OnClick", function(self)
        TRP3FW.Prefs.scanResponseAllowGroupBypass = self:GetChecked()
    end)
    scanY = scanY - 30

    uiElements.scanResponseWhitelistEnabled = TabManager:CreateCheckbox(content, "Enable Scan Reply Whitelist", "If disabled, names in the whitelist are ignored (no bypass).", "scanResponseWhitelistEnabled")
    uiElements.scanResponseWhitelistEnabled:SetPoint("TOPLEFT", 30, scanY)
    uiElements.scanResponseWhitelistEnabled:SetScript("OnClick", function(self)
        TRP3FW.Prefs.scanResponseWhitelistEnabled = self:GetChecked()
        TRP3FW:RefreshUI()
    end)
    scanY = scanY - 30

    local scanWhitelistLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scanWhitelistLabel:SetPoint("TOPLEFT", 30, scanY)
    scanWhitelistLabel:SetText("Scan Reply Whitelist (one name per line):")
    scanY = scanY - 20

    local scanWhitelistScroll = CreateFrame("ScrollFrame", "TRP3FW_SecurityScanWhitelistScroll", content, "UIPanelScrollFrameTemplate")
    scanWhitelistScroll:SetPoint("TOPLEFT", 30, scanY)
    scanWhitelistScroll:SetSize(480, 80)
    uiElements.scanResponseWhitelistScroll = scanWhitelistScroll

    local scanWhitelistEdit = CreateFrame("EditBox", "TRP3FW_SecurityScanWhitelistEdit", scanWhitelistScroll)
    scanWhitelistEdit:SetMultiLine(true)
    scanWhitelistEdit:SetFontObject(ChatFontNormal)
    scanWhitelistEdit:SetWidth(460)
    scanWhitelistEdit:SetHeight(80)
    scanWhitelistEdit:SetAutoFocus(false)
    scanWhitelistEdit:SetMaxLetters(3000)

    local function sanitizeScanWhitelist(text)
        local seen = {}
        local out = {}
        for line in string.gmatch(text or "", "[^\r\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
                local clean = TRP3FW:SanitizePlayerName(trimmed) or TRP3FW:CleanPlayerName(trimmed)
                if clean and not seen[clean:lower()] then
                    seen[clean:lower()] = true
                    table.insert(out, clean)
                end
            end
        end
        return table.concat(out, "\n")
    end

    scanWhitelistEdit:SetText(TRP3FW.Prefs.scanResponseWhitelist or "")
    scanWhitelistEdit:SetScript("OnTextChanged", function(self)
        TRP3FW.Prefs.scanResponseWhitelist = self:GetText()
    end)
    scanWhitelistEdit:SetScript("OnEditFocusLost", function(self)
        local cleaned = sanitizeScanWhitelist(self:GetText())
        if cleaned ~= self:GetText() then
            self:SetText(cleaned)
        end
        TRP3FW.Prefs.scanResponseWhitelist = cleaned
    end)
    scanWhitelistScroll:SetScrollChild(scanWhitelistEdit)

    local scanWhitelistBG = CreateFrame("Frame", nil, content, "BackdropTemplate")
    scanWhitelistBG:SetPoint("TOPLEFT", scanWhitelistScroll, -6, 6)
    scanWhitelistBG:SetPoint("BOTTOMRIGHT", scanWhitelistScroll, 26, -6)
    scanWhitelistBG:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    scanWhitelistBG:SetBackdropColor(0, 0, 0, 0.25)
    scanWhitelistBG:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    uiElements.scanResponseWhitelistEdit = scanWhitelistEdit
    scanY = scanY - 100

    scanGroup:SetPoint("BOTTOMRIGHT", content, "TOPLEFT", 570, scanY + 10)

    y = scanY - 20

    -- ============================================================
    -- SPVP (Cryptographic Phase Verification)
    -- ============================================================
    TabManager:CreateSectionHeader(content, "SPVP (Cryptographic Phase Verification)", y)
    y = y - 30

    local spvpInfoBox = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spvpInfoBox:SetPoint("TOPLEFT", 20, y)
    spvpInfoBox:SetWidth(560)
    spvpInfoBox:SetJustifyH("LEFT")
    spvpInfoBox:SetText("|cff00ccffℹ SPVP Info:|r SPVP uses cryptographic phase verification as a fallback when normal location checks fail. Requires phase owners to set a security key (salt). Players in the same phase can prove it cryptographically without physical proximity checks.")
    y = y - 65

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

    return scrollFrame
end

TabManager:RegisterTab("security", "Security", "Security & Access Control", CreateSecurityTab, function() TRP3FW:RefreshUI() end)
