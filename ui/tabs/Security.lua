-- ui/tabs/Security.lua
-- Security tab: whitelist bypass, scan reply controls, SPVP (migrated to kit).
--
-- Preserves every uiElements key and epsilon registration RefreshUI depends on:
-- whitelistEnabled/whitelistEdit/whitelistScroll, notifyOnScanResponse/Allow,
-- scanResponse{Phase,Map}ModeDropdown (+ WhoModeDropdown alias for RefreshUI's
-- enable/disable), the five scanResponse* gating toggles, scanResponseWhitelist*,
-- spvpModeDropdown, spvpAutoInitialize, spvpBlockDurationSlider,
-- spvpSaltCacheDurationSlider, spvpSaltStatus, spvpSecureButton.

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

-- A multiline name box in a slate well inside a card. Returns scroll, edit.
local function multilineNames(card, wY, height, initialText, onChanged, onFocusLost)
    local Theme = TRP3FW.Theme
    local W = Theme.metrics.CARD_W
    -- The visual box is the backdrop, which extends -6 left / +26 right of the
    -- scroll frame; offset the scroll so the BOX sits exactly GAP(8) from each
    -- card edge: left 14-6=8, right 14+(W-48)+26 = W-8.
    local scroll = CreateFrame("ScrollFrame", nil, card, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, wY); scroll:SetSize(W - 48, height)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true); edit:SetFontObject(Theme.fonts.SUB); edit:SetWidth(W - 68); edit:SetHeight(height)
    edit:SetAutoFocus(false); edit:SetMaxLetters(3000); edit:SetText(initialText or "")
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    if onChanged then edit:SetScript("OnTextChanged", onChanged) end
    if onFocusLost then edit:SetScript("OnEditFocusLost", onFocusLost) end
    scroll:SetScrollChild(edit)
    local bg = CreateFrame("Frame", nil, card, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", scroll, -6, 6); bg:SetPoint("BOTTOMRIGHT", scroll, 26, -6)
    bg:SetBackdrop(Theme.BACKDROP_CHIP)
    bg:SetBackdropColor(Theme:Color("INSET"))
    bg:SetBackdropBorderColor(Theme:Color("BORDER_STRONG"))
    return scroll, edit, bg
end

local function sanitizeNames(text)
    local seen, out = {}, {}
    for line in string.gmatch(text or "", "[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            local clean = TRP3FW:SanitizePlayerName(trimmed) or TRP3FW:CleanPlayerName(trimmed)
            if clean and not seen[clean:lower()] then seen[clean:lower()] = true; table.insert(out, clean) end
        end
    end
    return table.concat(out, "\n")
end

local function CreateSecurityTab(container)
    local Theme = TRP3FW.Theme
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()

    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 1120)
    local uiElements = TabManager:GetUI()
    local epsilonControls = TabManager:GetEpsilonControls()
    local W = Theme.metrics.CARD_W

    -- ===== Card 1: Whitelist bypass (danger-tinted border) =================
    local wlCard = stackCard(content, TabManager:CreateCard(content, "Whitelist bypass", W), nil)
    wlCard:SetBackdropBorderColor(Theme:Color("DANGER"))

    local warn = wlCard:CreateFontString(nil, "OVERLAY", Theme.fonts.SUB)
    warn:SetPoint("TOPLEFT", 12, wlCard:NextY(30)); warn:SetPoint("RIGHT", wlCard, "RIGHT", -12, 0); warn:SetJustifyH("LEFT")
    warn:SetText("|cffff6600Warning:|r listed players will |cffffff00always|r receive your current profile. All phase/map checks, blocking, ghost mode, and start-phase protections are skipped for them.")

    uiElements.whitelistEnabled = TabManager:CreateToggle(wlCard, "Enable whitelist bypass",
        "Allow listed names to bypass all security checks and always receive your active profile.", "whitelistEnabled")
    uiElements.whitelistEnabled:SetPoint("TOPLEFT", 12, wlCard:NextY())
    uiElements.whitelistEnabled:SetPoint("RIGHT", wlCard, "RIGHT", -14, 0)
    -- Confirm-on-enable (unchanged behavior); toggle exposes GetChecked/SetChecked.
    uiElements.whitelistEnabled:SetScript("OnClick", function(self)
        if self:GetChecked() then
            self:SetChecked(false)
            StaticPopup_Show("TRP3FW_WHITELIST_CONFIRM")
        else
            TRP3FW.Prefs.whitelistEnabled = false
            if TRP3FW.RefreshWhitelistCache then TRP3FW:RefreshWhitelistCache() end
            TRP3FW:RefreshUI()
        end
        self:_applyVisual()
    end)

    local wlLabel = wlCard:CreateFontString(nil, "OVERLAY", Theme.fonts.SUB)
    wlLabel:SetPoint("TOPLEFT", 12, wlCard:NextY(18)); wlLabel:SetTextColor(Theme:Color("TEXT_SECONDARY"))
    uiElements.whitelistNameLabel = wlLabel

    local function countNames(text)
        local n = 0
        for line in string.gmatch(text or "", "[^\r\n]+") do if line:match("%S") then n = n + 1 end end
        return n
    end
    local function updateCount(text)
        local n = countNames(text)
        wlLabel:SetText(string.format("Names (one per line):  |cffaaaaaa(%s)|r", n == 0 and "empty" or (n == 1 and "1 name" or n.." names")))
    end

    local wlScroll, wlEdit = multilineNames(wlCard, wlCard:NextY(94), 88, TRP3FW.Prefs.whitelistEntries,
        function(self) TRP3FW.Prefs.whitelistEntries = self:GetText(); updateCount(self:GetText()) end,
        function(self)
            local cleaned = sanitizeNames(self:GetText())
            if cleaned ~= self:GetText() then self:SetText(cleaned) end
            TRP3FW.Prefs.whitelistEntries = cleaned; updateCount(cleaned)
        end)
    uiElements.whitelistScroll = wlScroll
    uiElements.whitelistEdit = wlEdit
    updateCount(TRP3FW.Prefs.whitelistEntries)
    -- Box bottom sits 6 below the scroll (94-88); +8 pad = 8px gap to card edge.
    wlCard:FitHeight(8)

    -- ===== Card 2: Map scan reply controls =================================
    local scanCard = stackCard(content, TabManager:CreateCard(content, "Map scan reply controls", W), wlCard)

    uiElements.notifyOnScanResponse = TabManager:CreateToggle(scanCard, "Show scan reply notifications",
        "Controls notifications for scan replies.", "notifyOnScanResponse")
    uiElements.notifyOnScanResponse:SetPoint("TOPLEFT", 12, scanCard:NextY())
    uiElements.notifyOnScanResponse:SetPoint("RIGHT", scanCard, "RIGHT", -14, 0)
    uiElements.notifyOnScanResponse:SetOnToggle(function(c) TRP3FW.Prefs.notifyOnScanResponse = c; TRP3FW:RefreshUI() end)

    uiElements.notifyOnScanAllow = TabManager:CreateToggle(scanCard, "Notify on scan allow",
        "Show notifications when scan replies are allowed.", "notifyOnScanAllow")
    uiElements.notifyOnScanAllow:SetPoint("TOPLEFT", 12, scanCard:NextY())
    uiElements.notifyOnScanAllow:SetPoint("RIGHT", scanCard, "RIGHT", -14, 0)
    uiElements.notifyOnScanAllow:SetOnToggle(function(c) TRP3FW.Prefs.notifyOnScanAllow = c end)

    local function scanModeDropdown(label, key, extraKey)
        local d = TabManager:CreateSkinnedDropdown(scanCard, label, "Behavior for scan replies.", 220, key)
        d:SetPoint("TOPLEFT", 6, scanCard:NextY(52) - 16)
        UIDropDownMenu_Initialize(d, function()
            local m = { {text="Off", val="off"}, {text="Statistics only", val="statistics"}, {text="Alert (send anyway)", val="alert"}, {text="Block (silent)", val="block"}, {text="Alert + block", val="alert_block"} }
            for _, item in ipairs(m) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.text; info.func = function() TRP3FW.Prefs[key] = item.val; UIDropDownMenu_SetText(d, item.text); TRP3FW:RefreshUI() end
                info.checked = (TRP3FW.Prefs[key] == item.val); UIDropDownMenu_AddButton(info)
            end
        end)
        uiElements[key.."Dropdown"] = d
        if extraKey then uiElements[extraKey] = d end
        return d
    end
    scanModeDropdown("Different-phase behavior", "scanResponsePhaseMode")
    -- RefreshUI enables/disables via the legacy "scanResponseWhoModeDropdown"
    -- key; alias the map dropdown to it so the gating actually applies.
    scanModeDropdown("Different-map behavior", "scanResponseMapMode", "scanResponseWhoModeDropdown")

    local gating = {
        { "scanResponseRequireNonce", "Require nonce on scan replies", "Ignore map scan replies without the issued nonce token (older scanners may be ignored)." },
        { "scanResponseCacheEnabled", "Cache scan requesters", "When replying to map scans, cache WHO results (if a WHO query ran). Does not add to interaction/send caches." },
        { "scanResponseAllowCacheBypass", "Bypass with existing caches", "If the requester is already in the allowed or interaction cache, skip the WHO gate and reply immediately." },
        { "scanResponseAllowGroupBypass", "Always allow party/raid", "If the scan requester is in your party or raid, always reply (skips phase/map/WHO gates)." },
        { "scanResponseWhitelistEnabled", "Enable scan reply whitelist", "If disabled, names in the whitelist below are ignored (no bypass)." },
    }
    for _, g in ipairs(gating) do
        local key, label, tip = g[1], g[2], g[3]
        local t = TabManager:CreateToggle(scanCard, label, tip, key)
        t:SetPoint("TOPLEFT", 12, scanCard:NextY())
        t:SetPoint("RIGHT", scanCard, "RIGHT", -14, 0)
        t:SetOnToggle(function(c) TRP3FW.Prefs[key] = c; if key == "scanResponseWhitelistEnabled" then TRP3FW:RefreshUI() end end)
        uiElements[key] = t
    end

    local swLabel = scanCard:CreateFontString(nil, "OVERLAY", Theme.fonts.SUB)
    swLabel:SetPoint("TOPLEFT", 12, scanCard:NextY(18)); swLabel:SetTextColor(Theme:Color("TEXT_SECONDARY"))
    swLabel:SetText("Scan reply whitelist (one name per line):")

    local swScroll, swEdit = multilineNames(scanCard, scanCard:NextY(86), 80, TRP3FW.Prefs.scanResponseWhitelist,
        function(self) TRP3FW.Prefs.scanResponseWhitelist = self:GetText() end,
        function(self)
            local cleaned = sanitizeNames(self:GetText())
            if cleaned ~= self:GetText() then self:SetText(cleaned) end
            TRP3FW.Prefs.scanResponseWhitelist = cleaned
        end)
    uiElements.scanResponseWhitelistScroll = swScroll
    uiElements.scanResponseWhitelistEdit = swEdit
    scanCard:FitHeight(8)

    -- ===== Card 3: SPVP ====================================================
    local spvpCard = stackCard(content, TabManager:CreateCard(content, "SPVP (cryptographic phase verification)", W), scanCard)

    local info = spvpCard:CreateFontString(nil, "OVERLAY", Theme.fonts.SUB)
    info:SetPoint("TOPLEFT", 12, spvpCard:NextY(46)); info:SetPoint("RIGHT", spvpCard, "RIGHT", -12, 0); info:SetJustifyH("LEFT")
    info:SetText("|cff00ccffSPVP|r verifies phase membership cryptographically as a fallback when normal location checks fail. Phase owners set a security key (salt); players in the same phase can then prove it without proximity checks.")

    local smd = TabManager:CreateSkinnedDropdown(spvpCard, "SPVP mode", "Control SPVP usage.", 220, "spvpMode")
    smd:SetPoint("TOPLEFT", 6, spvpCard:NextY(52) - 16); uiElements.spvpModeDropdown = smd
    UIDropDownMenu_Initialize(smd, function()
        local l = { {t="Off", v="off"}, {t="Optional (post-check)", v="optional"}, {t="Preferred (pre-check)", v="preferred"}, {t="Required (strict)", v="required"} }
        for _, it in ipairs(l) do
            local info2 = UIDropDownMenu_CreateInfo(); info2.text = it.t
            info2.func = function() TRP3FW.Prefs.spvpMode = it.v; TRP3FW.Prefs.spvpEnabled = (it.v ~= "off"); UIDropDownMenu_SetText(smd, it.t); TRP3FW:RefreshUI() end
            UIDropDownMenu_AddButton(info2)
        end
    end)
    if epsilonControls then table.insert(epsilonControls, smd) end

    uiElements.spvpAutoInitialize = TabManager:CreateToggle(spvpCard, "Auto-initialize salts",
        "Auto-generate keys for owned phases.", "spvpAutoInitialize")
    uiElements.spvpAutoInitialize:SetPoint("TOPLEFT", 12, spvpCard:NextY())
    uiElements.spvpAutoInitialize:SetPoint("RIGHT", spvpCard, "RIGHT", -14, 0)
    uiElements.spvpAutoInitialize:SetOnToggle(function(c) TRP3FW.Prefs.spvpAutoInitialize = c end)
    if epsilonControls then table.insert(epsilonControls, uiElements.spvpAutoInitialize) end

    local blockSlider = TabManager:CreateSlider(spvpCard, "Block duration",
        "How long a failed SPVP check blocks a sender.", "spvpBlockDuration", 10, 600, 10, "%d s")
    blockSlider:SetPoint("TOPLEFT", 12, spvpCard:NextY(40))
    blockSlider:SetPoint("RIGHT", spvpCard, "RIGHT", -14, 0)
    blockSlider:SetOnChange(function(v) TRP3FW.Prefs.spvpBlockDuration = v end)
    uiElements.spvpBlockDurationSlider = blockSlider
    if epsilonControls then table.insert(epsilonControls, blockSlider) end

    local saltSlider = TabManager:CreateSlider(spvpCard, "Salt cache",
        "How long to cache phase salts.", "spvpSaltCacheDuration", 300, 43200, 300, "%d s")
    saltSlider:SetPoint("TOPLEFT", 12, spvpCard:NextY(40))
    saltSlider:SetPoint("RIGHT", spvpCard, "RIGHT", -14, 0)
    saltSlider:SetOnChange(function(v) TRP3FW.Prefs.spvpSaltCacheDuration = v end)
    uiElements.spvpSaltCacheDurationSlider = saltSlider
    if epsilonControls then table.insert(epsilonControls, saltSlider) end

    uiElements.spvpSaltStatus = spvpCard:CreateFontString(nil, "OVERLAY", Theme.fonts.SUB)
    uiElements.spvpSaltStatus:SetPoint("TOPLEFT", 12, spvpCard:NextY(24)); uiElements.spvpSaltStatus:SetPoint("RIGHT", spvpCard, "RIGHT", -12, 0); uiElements.spvpSaltStatus:SetJustifyH("LEFT")
    uiElements.spvpSaltStatus:SetText("Loading phase status...")
    if epsilonControls then table.insert(epsilonControls, uiElements.spvpSaltStatus) end

    uiElements.spvpSecureButton = TabManager:CreateButton(spvpCard, "Secure this phase", 180, false)
    uiElements.spvpSecureButton:SetPoint("TOPLEFT", 12, spvpCard:NextY(24))
    uiElements.spvpSecureButton:SetOnClick(function()
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
    -- Button is 24 tall in a 24 step; +8 pad = 8px gap below it.
    spvpCard:FitHeight(8)

    return scrollFrame
end

TabManager:RegisterTab("security", "Security", "Security & Access Control", CreateSecurityTab, function() TRP3FW:RefreshUI() end, "Interface\\Icons\\INV_Misc_Key_03")
