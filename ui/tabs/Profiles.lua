-- ui/tabs/Profiles.lua
-- Settings Profiles management tab for TRP3FW

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

local currentRefreshFunc

local function CreateProfilesTab(container)
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()
    
    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 500)
    local uiElements = TabManager:GetUI()
    local y = -10

    TabManager:CreateSectionHeader(content, "Profile Management", y)
    y = y - 40
    
    -- Active profile info
    local activeLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    activeLabel:SetPoint("TOPLEFT", 20, y)
    activeLabel:SetText("Active Profile:")
    
    local activeValue = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    activeValue:SetPoint("LEFT", activeLabel, "RIGHT", 10, 0)
    
    local function UpdateProfileUI()
        local charKey = TRP3FW:GetCharacterKey()
        local activeProfile = TRP3FW.GlobalDB.profileKeys[charKey] or "Default"
        activeValue:SetText("|cff00ff00" .. activeProfile .. "|r")
    end
    
    UpdateProfileUI()
    y = y - 40
    
    -- List of profiles
    local listHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listHeader:SetPoint("TOPLEFT", 20, y)
    listHeader:SetText("Available Profiles:")
    y = y - 25
    
    -- Simple profile list
    local profileButtons = {}
    
    local function RefreshProfileList()
        if not content:IsVisible() then return end
        
        -- Clear old buttons
        for _, btn in ipairs(profileButtons) do btn:Hide() end
        profileButtons = {}
        
        local currentY = y
        local charKey = TRP3FW:GetCharacterKey()
        local activeProfile = TRP3FW.GlobalDB.profileKeys[charKey] or "Default"
        
        -- Get sorted profile names
        local names = {}
        if TRP3FW.GlobalDB and TRP3FW.GlobalDB.profiles then
            for name in pairs(TRP3FW.GlobalDB.profiles) do
                table.insert(names, name)
            end
        end
        table.sort(names, function(a, b)
            if a == "Default" then return true end
            if b == "Default" then return false end
            return a < b
        end)
        
        for i, name in ipairs(names) do
            local row = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            row:SetSize(200, 25)
            row:SetPoint("TOPLEFT", 30, currentY)
            row:SetText(name)
            
            if name == activeProfile then
                row:Disable()
                row:SetText(name .. " (Active)")
            end
            
            row:SetScript("OnClick", function()
                StaticPopup_Show("TRP3FW_CONFIRM_PROFILE_SWITCH", name, nil, name)
            end)
            
            -- Delete button
            local del = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            del:SetSize(60, 25)
            del:SetPoint("LEFT", row, "RIGHT", 5, 0)
            del:SetText("Delete")
            if name == "Default" or name == activeProfile then
                del:Disable()
            end
            del:SetScript("OnClick", function()
                StaticPopup_Show("TRP3FW_CONFIRM_PROFILE_DELETE", name, nil, name)
            end)

            -- Rename button
            local ren = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            ren:SetSize(70, 25)
            ren:SetPoint("LEFT", del, "RIGHT", 5, 0)
            ren:SetText("Rename")
            if name == "Default" then ren:Disable() end
            ren:SetScript("OnClick", function()
                StaticPopup_Show("TRP3FW_RENAME_PROFILE", name, nil, name)
            end)
            
            table.insert(profileButtons, row)
            table.insert(profileButtons, del)
            table.insert(profileButtons, ren)
            currentY = currentY - 30
        end
        
        -- New Profile button
        local newBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        newBtn:SetSize(150, 30)
        newBtn:SetPoint("TOPLEFT", 20, currentY - 20)
        newBtn:SetText("Create New Profile")
        newBtn:SetScript("OnClick", function()
            StaticPopup_Show("TRP3FW_CREATE_PROFILE")
        end)
        table.insert(profileButtons, newBtn)
        
        UpdateProfileUI()
    end
    
    currentRefreshFunc = RefreshProfileList
    TRP3FW.RefreshProfilesTab = RefreshProfileList
    return scrollFrame
end

TabManager:RegisterTab("profiles", "Profiles", "Settings Profiles", CreateProfilesTab, function()
    if currentRefreshFunc then currentRefreshFunc() end
end)
