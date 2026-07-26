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

    -- WIDGET POOL, keyed by row index.
    --
    -- RefreshProfileList used to Hide() the previous buttons, wipe() the list, and then create
    -- three brand-new CreateButton frames per profile plus the "+ Create new profile" button.
    -- WoW frames are never garbage collected, so every profile switch, create, delete and
    -- rename permanently added `3 * #profiles + 1` orphaned frames -- and the refresh is also
    -- wired to the tab's refresh callback, so it fired on every SwitchToTab("profiles") too.
    -- Growth was bounded only by how often the user opened the tab.
    --
    -- Same shape as historywindow.lua's graph.bars pool: hide everything, then reuse by index
    -- and only create when the pool is short.
    local rowPool = {}   -- [i] = { switch, del, ren }
    local newBtn         -- the single "+ Create new profile" button, created once

    -- CreateButton captures `isPrimary` in its OnLeave closure, so a pooled button cannot
    -- change primary styling by itself. Restyle explicitly on reuse instead, and re-arm
    -- OnLeave so hover-out returns to the CORRECT state rather than the creation-time one.
    --
    -- The state lives ON the button (_isPrimary / _isMuted) and the handler is a single shared
    -- function, rather than a fresh closure per call -- this runs 3x per row per refresh, and
    -- allocating there would trade a frame leak for garbage churn on the same path.
    local function applyBaseStyle(btn)
        if btn._isPrimary then
            btn:SetBackdropColor(Theme:Color("CARD_HOVER"))
            btn:SetBackdropBorderColor(Theme:Color("GOLD"))
            btn.text:SetTextColor(Theme:Color("GOLD_TEXT"))
        else
            btn:SetBackdropColor(Theme:Color("CARD"))
            btn:SetBackdropBorderColor(Theme:Color("BORDER_STRONG"))
            btn.text:SetTextColor(btn._isMuted and Theme:Color("TEXT_MUTED") or Theme:Color("TEXT_PRIMARY"))
        end
    end

    local function styleButton(btn, isPrimary, isMuted)
        btn._isPrimary, btn._isMuted = isPrimary, isMuted
        btn:SetScript("OnLeave", applyBaseStyle)
        applyBaseStyle(btn)
    end

    -- Click handlers are shared and read the profile name off the button (_profileName),
    -- rather than being rebuilt as per-name closures on every refresh. Same reasoning as
    -- applyBaseStyle: a pool that reallocates per refresh has not fixed much.
    local function onSwitchClick(btn)
        StaticPopup_Show("TRP3FW_CONFIRM_PROFILE_SWITCH", btn._profileName, nil, btn._profileName)
    end
    local function onDeleteClick(btn)
        StaticPopup_Show("TRP3FW_CONFIRM_PROFILE_DELETE", btn._profileName, nil, btn._profileName)
    end
    local function onRenameClick(btn)
        StaticPopup_Show("TRP3FW_RENAME_PROFILE", btn._profileName, nil, btn._profileName)
    end

    -- Fetch row i from the pool, creating it on first use.
    local function acquireRow(i)
        local row = rowPool[i]
        if row then return row end

        row = {
            switch = TabManager:CreateButton(listCard, "", 240, false),
            del    = TabManager:CreateButton(listCard, "Delete", 70, false),
            ren    = TabManager:CreateButton(listCard, "Rename", 80, false),
        }
        row.del:SetPoint("LEFT", row.switch, "RIGHT", 8, 0)
        row.ren:SetPoint("LEFT", row.del, "RIGHT", 8, 0)
        rowPool[i] = row
        return row
    end

    local function RefreshProfileList()
        if not content:IsVisible() then return end

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
        for i, name in ipairs(names) do
            local rowY = listCard:NextY(30)
            local isActive = (name == activeProfile)
            local row = acquireRow(i)

            -- Re-anchor every refresh: the row's Y depends on its position in the list, which
            -- changes as profiles are created, deleted and renamed.
            row.switch:ClearAllPoints()
            row.switch:SetPoint("TOPLEFT", INNER, rowY)

            -- Every button in the row carries the name it currently represents; the shared
            -- handlers above read it back on click.
            row.switch._profileName = name
            row.del._profileName    = name
            row.ren._profileName    = name

            row.switch.text:SetText(isActive and (name.." (active)") or name)
            styleButton(row.switch, isActive, false)
            row.switch:SetScript("OnClick", (not isActive) and onSwitchClick or nil)

            local delDisabled = (name == "Default" or isActive)
            styleButton(row.del, false, delDisabled)
            row.del:SetScript("OnClick", (not delDisabled) and onDeleteClick or nil)

            local renDisabled = (name == "Default")
            styleButton(row.ren, false, renDisabled)
            row.ren:SetScript("OnClick", (not renDisabled) and onRenameClick or nil)

            row.switch:Show(); row.del:Show(); row.ren:Show()
        end

        -- Hide the tail of the pool beyond the current profile count. Without this, deleting a
        -- profile would leave its row visible with a stale name and a live click handler.
        for i = #names + 1, #rowPool do
            local row = rowPool[i]
            row.switch:Hide(); row.del:Hide(); row.ren:Hide()
            -- Clear handlers and the stored name: a hidden button cannot be clicked, but
            -- leaving either attached keeps a row pointing at a profile that may no longer
            -- exist. Same reasoning as historywindow's pool clearing tooltipData on its tail.
            row.switch:SetScript("OnClick", nil)
            row.del:SetScript("OnClick", nil)
            row.ren:SetScript("OnClick", nil)
            row.switch._profileName, row.del._profileName, row.ren._profileName = nil, nil, nil
        end

        -- Created once, then just re-anchored: its Y moves as the list length changes.
        if not newBtn then
            newBtn = TabManager:CreateButton(listCard, "+ Create new profile", 180, false)
            newBtn:SetOnClick(function() StaticPopup_Show("TRP3FW_CREATE_PROFILE") end)
        end
        newBtn:ClearAllPoints()
        newBtn:SetPoint("TOPLEFT", INNER, listCard:NextY(38))
        newBtn:Show()

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
