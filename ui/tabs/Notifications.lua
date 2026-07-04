-- ui/tabs/Notifications.lua
-- Notifications settings tab for TRP3FW (redesigned with the skinned widget kit)
--
-- First tab migrated to the TRP3-style card layout. The flat checkbox wall is
-- reorganized into grouped cards: a master toggle, a "what to notify on" group
-- of pill toggles, an appearance chip row, and a suppression group with a
-- slider. Uses TabManager:CreateCard/CreateToggle/CreateChip/CreateSlider
-- (added alongside the classic helpers) so RefreshUI drives every widget
-- unchanged via its existing settingKey loops.

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

-- Small helper: place a card at the top of the content, or below the previous
-- card, with the standard gap. Returns the card so callers can chain.
local function stackCard(content, card, prev, width)
    card:SetWidth(width)
    if prev then
        card:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -TRP3FW.Theme.metrics.CARD_GAP)
        card:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -TRP3FW.Theme.metrics.CARD_GAP)
    else
        local inset = TRP3FW.Theme.metrics.CONTENT_INSET
        card:SetPoint("TOPLEFT", content, "TOPLEFT", inset, -10)
        card:SetPoint("TOPRIGHT", content, "TOPRIGHT", -inset, -10)
    end
    return card
end

-- Wire a toggle to write its pref on change (mirrors the classic OnClick pattern)
-- and stretch its row to the card's right edge so the pill hugs the right side.
local function bindToggle(toggle, key)
    toggle:SetOnToggle(function(checked) TRP3FW.Prefs[key] = checked end)
    toggle:SetPoint("RIGHT", toggle:GetParent(), "RIGHT", -14, 0)
    return toggle
end

local function CreateNotificationsTab(container)
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()

    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 640)
    local uiElements = TabManager:GetUI()
    local M = TRP3FW.Theme.metrics
    local CARD_W = M.CARD_W

    -- ---- Card 1: master toggle --------------------------------------------
    local masterCard = stackCard(content, TabManager:CreateCard(content, nil, CARD_W), nil, CARD_W)
    uiElements.notifyEnabled = TabManager:CreateToggle(masterCard,
        "Enable notifications", "Master toggle for all firewall alerts", "notifyEnabled")
    uiElements.notifyEnabled:SetPoint("TOPLEFT", 12, masterCard:NextY(M.ROW_TALL))
    bindToggle(uiElements.notifyEnabled, "notifyEnabled")
    masterCard:FitHeight()

    -- ---- Card 2: what to notify on ----------------------------------------
    local notifyCard = stackCard(content, TabManager:CreateCard(content, "What to notify on", CARD_W), masterCard, CARD_W)

    uiElements.notifyOnAllow = TabManager:CreateToggle(notifyCard,
        "On allow (profile sent normally)", "Show notifications when profiles are sent normally (allowed)", "notifyOnAllow")
    uiElements.notifyOnAllow:SetPoint("TOPLEFT", 12, notifyCard:NextY())
    bindToggle(uiElements.notifyOnAllow, "notifyOnAllow")

    uiElements.notifyOnStartPhaseBlock = TabManager:CreateToggle(notifyCard,
        "On start-phase block", "Show notifications when blocking in start phase (169)", "notifyOnStartPhaseBlock", "(phase 169)")
    uiElements.notifyOnStartPhaseBlock:SetPoint("TOPLEFT", 12, notifyCard:NextY())
    bindToggle(uiElements.notifyOnStartPhaseBlock, "notifyOnStartPhaseBlock")

    uiElements.notifyOnBroadcast = TabManager:CreateToggle(notifyCard,
        "On broadcast", "Show notifications for map scan broadcasts (only affects Allow notifications)", "notifyOnBroadcast", "(affects allow only)")
    uiElements.notifyOnBroadcast:SetPoint("TOPLEFT", 12, notifyCard:NextY())
    bindToggle(uiElements.notifyOnBroadcast, "notifyOnBroadcast")

    uiElements.notifyOnWhisper = TabManager:CreateToggle(notifyCard,
        "On whisper", "Show notifications for whisper exchanges (only affects Allow notifications)", "notifyOnWhisper", "(affects allow only)")
    uiElements.notifyOnWhisper:SetPoint("TOPLEFT", 12, notifyCard:NextY())
    bindToggle(uiElements.notifyOnWhisper, "notifyOnWhisper")
    notifyCard:FitHeight()

    -- ---- Card 3: appearance (chip row) ------------------------------------
    local apprCard = stackCard(content, TabManager:CreateCard(content, "Appearance", CARD_W), notifyCard, CARD_W)

    local chipSpecs = {
        { key = "showInChat",            label = "Show in chat",   tip = "Display firewall alerts in the main chat window" },
        { key = "showOnScreen",          label = "On-screen",      tip = "Display firewall alerts as floating text on the screen" },
        { key = "playSound",             label = "Play sound",     tip = "Play a subtle sound when a firewall alert occurs" },
        { key = "showGhostNotifications",label = "Ghosting alerts",tip = "Display chat messages when a blank profile is sent via Ghost mode" },
        { key = "showAddonSource",       label = "Addon source",   tip = "Include the name of the requesting addon (TRP3, MRP, XRP) in notifications" },
        { key = "showCacheInfo",         label = "Cache hit/miss", tip = "Append cache status (HIT/MISS) to Allow notifications" },
        { key = "showCheckResults",      label = "Check detail",   tip = "Append phase and map check results/methods to notifications" },
    }
    local chipY = apprCard:NextY(0)  -- take current cursor without advancing
    local chipX = 12
    local rowStartX = 12
    local maxRight = CARD_W - 14
    for _, spec in ipairs(chipSpecs) do
        local chip = TabManager:CreateChip(apprCard, spec.label, spec.tip, spec.key)
        -- Wrap to a new line when the chip would overflow the card width.
        if chipX > rowStartX and (chipX + chip:GetWidth()) > maxRight then
            chipX = rowStartX
            chipY = chipY - 30
        end
        chip:SetPoint("TOPLEFT", chipX, chipY)
        chip:SetOnToggle(function(checked) TRP3FW.Prefs[spec.key] = checked end)
        uiElements[spec.key] = chip
        chipX = chipX + chip:GetWidth() + 8
    end
    -- Advance the card cursor past the chip rows and size the card.
    apprCard._cursorY = chipY - 30
    apprCard:FitHeight()

    -- ---- Card 4: suppression ----------------------------------------------
    local supprCard = stackCard(content, TabManager:CreateCard(content, "Suppression", CARD_W), apprCard, CARD_W)

    local suppr = TabManager:CreateSlider(supprCard,
        "Duration", "How many seconds to suppress repeated notifications from the same player.",
        "suppressionTime", 0, 600, 5, "%d s")
    suppr:SetPoint("TOPLEFT", 12, supprCard:NextY(M.ROW_TALL))
    suppr:SetPoint("RIGHT", supprCard, "RIGHT", -14, 0)
    suppr:SetOnChange(function(v) TRP3FW.Prefs.suppressionTime = v end)
    uiElements.suppressionTime = suppr

    uiElements.refreshSuppression = TabManager:CreateToggle(supprCard,
        "Extend on activity", "Refresh the suppression window when new profile sends are detected from the same player (sliding window).", "refreshSuppression", "(sliding window)")
    uiElements.refreshSuppression:SetPoint("TOPLEFT", 12, supprCard:NextY())
    bindToggle(uiElements.refreshSuppression, "refreshSuppression")

    uiElements.suppressAllWhoOutput = TabManager:CreateToggle(supprCard,
        "Suppress WHO output", "Hide all WHO results in chat.", "suppressAllWhoOutput")
    uiElements.suppressAllWhoOutput:SetPoint("TOPLEFT", 12, supprCard:NextY())
    bindToggle(uiElements.suppressAllWhoOutput, "suppressAllWhoOutput")
    do
        local ec = TabManager:GetEpsilonControls()
        if ec then table.insert(ec, uiElements.suppressAllWhoOutput) end
    end
    supprCard:FitHeight()

    return scrollFrame
end

TabManager:RegisterTab("notifications", "Notifications", "Notification Settings", CreateNotificationsTab, function() TRP3FW:RefreshUI() end, "Interface\\Icons\\INV_Letter_15")
