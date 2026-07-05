-- ui/tabs/Profiles.lua
-- Settings Profiles management tab for TRP3FW (migrated to the skinned kit)

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

local currentRefreshFunc

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

local function CreateProfilesTab(container)
    local Theme = TRP3FW.Theme
    local INNER = Theme.metrics.INNER
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()

    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 560)
    local W = Theme.metrics.CARD_W

    -- ===== Card 1: Active profile ==========================================
    local activeCard = stackCard(content, TabManager:CreateCard(content, "Active profile", nil), nil)
    local activeLabel = activeCard:CreateFontString(nil, "OVERLAY", Theme.fonts.LABEL)
    activeLabel:SetPoint("TOPLEFT", INNER, activeCard:NextY(28))
    activeLabel:SetText("Current:")
    activeLabel:SetTextColor(Theme:Color("TEXT_SECONDARY"))
    local activeValue = activeCard:CreateFontString(nil, "OVERLAY", Theme.fonts.LABEL)
    activeValue:SetPoint("LEFT", activeLabel, "RIGHT", 8, 0)
    activeValue:SetTextColor(Theme:Color("GOLD_TEXT"))
    activeCard:FitHeight(12)

    local function UpdateProfileUI()
        local charKey = TRP3FW:GetCharacterKey()
        local activeProfile = TRP3FW.GlobalDB.profileKeys[charKey] or "Default"
        activeValue:SetText(activeProfile)
    end
    UpdateProfileUI()

    -- ===== Card 2: Available profiles (dynamic list) =======================
    local listCard = stackCard(content, TabManager:CreateCard(content, "Available profiles", nil), activeCard)
    local listTopCursor = listCard._cursorY  -- capture the post-caption start Y
    local rowButtons = {}

    local function RefreshProfileList()
        if not content:IsVisible() then return end
        for _, btn in ipairs(rowButtons) do btn:Hide() end
        wipe(rowButtons)

        local charKey = TRP3FW:GetCharacterKey()
        local activeProfile = TRP3FW.GlobalDB.profileKeys[charKey] or "Default"

        local names = {}
        if TRP3FW.GlobalDB and TRP3FW.GlobalDB.profiles then
            for name in pairs(TRP3FW.GlobalDB.profiles) do table.insert(names, name) end
        end
        table.sort(names, function(a, b)
            if a == "Default" then return true end
            if b == "Default" then return false end
            return a < b
        end)

        -- Reset the card cursor to just under its caption/divider each refresh.
        listCard._cursorY = listTopCursor
        for _, name in ipairs(names) do
            local rowY = listCard:NextY(30)
            local isActive = (name == activeProfile)

            local switchBtn = TabManager:CreateButton(listCard, isActive and (name.." (active)") or name, 240, isActive)
            switchBtn:SetPoint("TOPLEFT", INNER, rowY)
            if isActive then
                switchBtn:SetScript("OnClick", nil)
            else
                switchBtn:SetOnClick(function() StaticPopup_Show("TRP3FW_CONFIRM_PROFILE_SWITCH", name, nil, name) end)
            end

            local del = TabManager:CreateButton(listCard, "Delete", 70, false)
            del:SetPoint("LEFT", switchBtn, "RIGHT", 8, 0)
            if name == "Default" or isActive then
                del:SetScript("OnClick", nil); del.text:SetTextColor(Theme:Color("TEXT_MUTED"))
            else
                del:SetOnClick(function() StaticPopup_Show("TRP3FW_CONFIRM_PROFILE_DELETE", name, nil, name) end)
            end

            local ren = TabManager:CreateButton(listCard, "Rename", 80, false)
            ren:SetPoint("LEFT", del, "RIGHT", 8, 0)
            if name == "Default" then
                ren:SetScript("OnClick", nil); ren.text:SetTextColor(Theme:Color("TEXT_MUTED"))
            else
                ren:SetOnClick(function() StaticPopup_Show("TRP3FW_RENAME_PROFILE", name, nil, name) end)
            end

            table.insert(rowButtons, switchBtn)
            table.insert(rowButtons, del)
            table.insert(rowButtons, ren)
        end

        local newBtn = TabManager:CreateButton(listCard, "+ Create new profile", 180, false)
        newBtn:SetPoint("TOPLEFT", INNER, listCard:NextY(38))
        newBtn:SetOnClick(function() StaticPopup_Show("TRP3FW_CREATE_PROFILE") end)
        table.insert(rowButtons, newBtn)

        listCard:FitHeight(12)
        UpdateProfileUI()
    end

    currentRefreshFunc = RefreshProfileList
    TRP3FW.RefreshProfilesTab = RefreshProfileList
    RefreshProfileList()
    return scrollFrame
end

TabManager:RegisterTab("profiles", "Profiles", "Settings Profiles", CreateProfilesTab, function()
    if currentRefreshFunc then currentRefreshFunc() end
end, "Interface\\Icons\\Achievement_Character_Human_Male")
