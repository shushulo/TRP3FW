-- features/profileswitch.lua
-- Ghost mode profile switching for phase 169, map 1605

local addonName, TRP3FW = ...

local START_PHASE_ID = 169
local START_MAP_ID = 1605

-- Get the profile name from settings (defaults to TRP3FW_BLANK)
local function GetBlankProfileName()
    return TRP3FW.Prefs.ghostProfileName or "TRP3FW_BLANK"
end

-- Track original profile to restore later
-- Note: This is saved to SavedVariables to persist across logout/login
TRP3FW.originalProfile = nil
TRP3FW.isBlankProfileActive = false
TRP3FW.blankProfileSnapshot = nil  -- Snapshot of what a blank profile should look like
TRP3FW.blankProfileSnapshotHash = nil

local profileSwitchTxn = {
    active = false,
    target = nil,
    originals = nil,
}

-- Initialize saved profile tracking
local function InitializeProfileTracking()
    -- Ensure TRP3FW.Prefs has profile tracking table
    if not TRP3FW.Prefs.savedProfiles then
        TRP3FW.Prefs.savedProfiles = {}
    end

    -- Restore from SavedVariables if available
    if TRP3FW.Prefs.savedProfiles.original then
        TRP3FW.originalProfile = TRP3FW.Prefs.savedProfiles.original
        TRP3FW:Debug("[Profile Switch] Restored original profile from SavedVariables", "hooks")
    end

    -- Restore blank profile snapshot
    if TRP3FW.Prefs.savedProfiles.blankSnapshot then
        TRP3FW.blankProfileSnapshot = TRP3FW.Prefs.savedProfiles.blankSnapshot
        TRP3FW.blankProfileSnapshotHash = TRP3FW.Prefs.savedProfiles.blankSnapshotHash
        TRP3FW:Debug("[Profile Switch] Restored blank profile snapshot from SavedVariables", "hooks")
    end

    -- Restore last switched profile name (used to detect on login)
    if TRP3FW.Prefs.savedProfiles.lastSwitchedProfile then
        TRP3FW.lastSwitchedProfile = TRP3FW.Prefs.savedProfiles.lastSwitchedProfile
    end
end

-- Save profile tracking to SavedVariables
local function SaveProfileTracking()
    if not TRP3FW.Prefs.savedProfiles then
        TRP3FW.Prefs.savedProfiles = {}
    end

    TRP3FW.Prefs.savedProfiles.original = TRP3FW.originalProfile
    TRP3FW.Prefs.savedProfiles.blankSnapshot = TRP3FW.blankProfileSnapshot
    TRP3FW.Prefs.savedProfiles.blankSnapshotHash = TRP3FW.blankProfileSnapshotHash
    TRP3FW.Prefs.savedProfiles.lastSwitchedProfile = TRP3FW.lastSwitchedProfile
end

-- Deep copy a table (for taking snapshot)
local function DeepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- Compare two tables deeply
local function DeepCompare(t1, t2, path)
    path = path or ""

    if type(t1) ~= type(t2) then
        return false, path .. ": type mismatch"
    end

    if type(t1) ~= "table" then
        if t1 ~= t2 then
            return false, path .. ": value mismatch (" .. tostring(t1) .. " vs " .. tostring(t2) .. ")"
        end
        return true
    end

    -- Compare table keys
    for k, v1 in pairs(t1) do
        local v2 = t2[k]
        local ok, err = DeepCompare(v1, v2, path .. "." .. tostring(k))
        if not ok then
            return false, err
        end
    end

    -- Check for extra keys in t2
    for k in pairs(t2) do
        if t1[k] == nil then
            return false, path .. "." .. tostring(k) .. ": extra key in comparison"
        end
    end

    return true
end

-- Deterministic stable hash for tables (order-independent keys)
local function StableHash(value, prefix)
    local t = type(value)
    if t == "nil" then return "nil" end
    if t == "boolean" or t == "number" or t == "string" then
        return t .. ":" .. tostring(value)
    end

    if t ~= "table" then
        return t
    end

    local keys = {}
    for k in pairs(value) do
        keys[#keys+1] = tostring(k)
    end
    table.sort(keys)

    local parts = {"table:"}
    for _, sk in ipairs(keys) do
        local v = value[sk] ~= nil and value[sk] or value[tonumber(sk)]
        parts[#parts+1] = sk
        parts[#parts+1] = "="
        parts[#parts+1] = StableHash(v, sk)
        parts[#parts+1] = ";"
    end

    return table.concat(parts)
end

local function ComputeProfileHash(profileTable)
    if not profileTable or type(profileTable) ~= "table" then
        return nil
    end
    return StableHash(profileTable)
end

local function BeginProfileSwitch(targetProfile)
    if profileSwitchTxn.active then
        return nil, "active"
    end
    profileSwitchTxn.active = true
    profileSwitchTxn.target = targetProfile
    profileSwitchTxn.originals = {}
    return profileSwitchTxn
end

local function CommitProfileSwitch()
    profileSwitchTxn.active = false
    profileSwitchTxn.target = nil
    profileSwitchTxn.originals = nil
end

local function RollbackProfileSwitch()
    if not profileSwitchTxn.active or not profileSwitchTxn.originals then
        CommitProfileSwitch()
        return
    end

    -- Best-effort restore for any addons we touched
    local originals = profileSwitchTxn.originals

    if originals.TRP3 and TRP3_API and TRP3_API.profile and TRP3_API.profile.selectProfile then
        local profiles = TRP3_API.profile.getProfiles()
        if profiles and profiles[originals.TRP3] then
            TRP3_API.profile.selectProfile(originals.TRP3)
        end
    end

    if originals.MRP and mrp and mrp.SetCurrentProfile and mrpSaved and mrpSaved.Profiles and mrpSaved.Profiles[originals.MRP] then
        mrp:SetCurrentProfile(originals.MRP)
    end

    if originals.XRP and AddOn_XRP and AddOn_XRP.SetProfile and xrpSaved and xrpSaved.profile and xrpSaved.profile[originals.XRP] then
        AddOn_XRP.SetProfile(originals.XRP, true)
    end

    TRP3FW.isBlankProfileActive = false
    TRP3FW.lastSwitchedProfile = nil

    CommitProfileSwitch()
end

-- Validate that a TRP3 profile is actually blank (unmodified)
-- Only validates if using the default TRP3FW_BLANK name (safety feature)
local function ValidateTRP3ProfileIsBlank(profile, profileName)
    -- Skip validation if using custom profile name
    if profileName ~= "TRP3FW_BLANK" then
        return true
    end

    if not profile or not profile.player then return false end

    -- If we have a snapshot, compare against it
    if TRP3FW.blankProfileSnapshot then
        -- Only compare the player data (not metadata like time, profileName)
        local isBlank, err = DeepCompare(TRP3FW.blankProfileSnapshot, profile.player, "player")
        if not isBlank then
            TRP3FW:Debug("[Profile Switch] Blank profile validation failed: " .. (err or "unknown"), "hooks")
        end
        if not isBlank then
            return false
        end

        -- Hash match is a cheap guard against subtle diffs
        if TRP3FW.blankProfileSnapshotHash then
            local currentHash = ComputeProfileHash(profile.player)
            if currentHash ~= TRP3FW.blankProfileSnapshotHash then
                TRP3FW:Debug("[Profile Switch] Blank profile hash mismatch; snapshot drifted", "hooks")
                return false
            end
        end

        return true
    end

    -- Fallback: basic validation if no snapshot available
    local char = profile.player.characteristics or {}
    local character = profile.player.character or {}

    -- Check critical text fields are empty
    if (char.FN or "") ~= "" then return false end
    if (char.LN or "") ~= "" then return false end
    if (character.CU or "") ~= "" then return false end
    if (character.CO or "") ~= "" then return false end

    return true
end

-- Find profile ID by name
local function FindTRP3ProfileIDByName(profileName)
    if not TRP3_Profiles then return nil end
    for profileID, profile in pairs(TRP3_Profiles) do
        if profile.profileName == profileName then
            return profileID
        end
    end
    return nil
end

-- Create or get blank profile for each addon
function TRP3FW:CreateBlankProfile_TRP3()
    if not TRP3_API then return false end

    local profileName = GetBlankProfileName()

    -- Check if blank profile already exists
    local existingProfileID = FindTRP3ProfileIDByName(profileName)
    if existingProfileID and TRP3_Profiles[existingProfileID] then
        -- Validate it's actually blank (only for default TRP3FW_BLANK name)
        if not ValidateTRP3ProfileIsBlank(TRP3_Profiles[existingProfileID], profileName) then
            self:Debug("[Profile Switch] TRP3 blank profile exists but has been modified - recreating", "hooks")
            -- Profile was modified, recreate it (delete old one first)
            if TRP3_API.profile.deleteProfile then
                TRP3_API.profile.deleteProfile(existingProfileID)
            else
                TRP3_Profiles[existingProfileID] = nil
            end
        else
            self:Debug("[Profile Switch] TRP3 blank profile already exists and is valid (ID: "..existingProfileID..")", "hooks")
            return existingProfileID
        end
    end

    -- Use TRP3's API to create the profile properly
    local profileID

    if TRP3_API and TRP3_API.profile and TRP3_API.profile.createProfile then
        -- Create profile using TRP3's official API (duplicates from default blank template)
        profileID = TRP3_API.profile.createProfile(profileName)
        self:Debug("[Profile Switch] Created TRP3 blank profile using API: " .. profileName .. " (ID: "..profileID..")", "hooks")

        -- Get the newly created profile and take a snapshot
        local profile = TRP3_Profiles[profileID]
        if profile and profile.player then
            -- Take a snapshot of what TRP3 considers a blank profile
            TRP3FW.blankProfileSnapshot = DeepCopy(profile.player)
            TRP3FW.blankProfileSnapshotHash = ComputeProfileHash(TRP3FW.blankProfileSnapshot)
            SaveProfileTracking()  -- Save to SavedVariables immediately
            self:Debug("[Profile Switch] Took snapshot of TRP3 blank profile structure and saved to SavedVariables", "hooks")
        end
    else
        -- Fallback: Create minimal profile directly if TRP3 API not available
        if not TRP3_Profiles then
            TRP3_Profiles = {}
        end

        profileID = "TRP3FW_" .. tostring(time()) .. "_" .. tostring(math.random(1000, 9999))
        TRP3_Profiles[profileID] = {
            player = {},
            time = time(),
            profileName = profileName,
        }

        -- Take snapshot
        TRP3FW.blankProfileSnapshot = DeepCopy(TRP3_Profiles[profileID].player)
        TRP3FW.blankProfileSnapshotHash = ComputeProfileHash(TRP3FW.blankProfileSnapshot)
        SaveProfileTracking()  -- Save to SavedVariables immediately
        self:Debug("[Profile Switch] Created TRP3 blank profile (fallback) and took snapshot: " .. profileName, "hooks")
    end

    return profileID
end

-- Validate that an MRP profile is actually blank (unmodified)
-- Only validates if using the default TRP3FW_BLANK name (safety feature)
local function ValidateMRPProfileIsBlank(profile, profileName)
    -- Skip validation if using custom profile name
    if profileName ~= "TRP3FW_BLANK" then
        return true
    end

    if not profile then return false end  -- Profile must exist

    -- For MRP, missing fields inherit from Default, so ALL fields must be EXPLICITLY present
    -- Check all text fields are PRESENT and empty (except CO which can be "1" for OOC)
    local textFields = {"NA", "NT", "NH", "NI", "RA", "RC", "FC", "CU", "DE", "HI", "AE", "AH", "AW", "AG", "HB", "HH", "MO", "FR", "TT", "RS", "PN"}
    for _, field in ipairs(textFields) do
        -- Field MUST exist (not nil) AND be empty string
        if profile[field] == nil then
            return false  -- Field missing - will inherit from Default!
        end
        if profile[field] ~= "" then
            return false  -- Field has content
        end
    end

    -- Check CO field (character status) - must be "1" (OOC) or "" (empty)
    if profile.CO == nil then
        return false  -- Field missing
    end
    if profile.CO ~= "1" and profile.CO ~= "" then
        return false  -- Not OOC or empty
    end

    -- Check icon is present and is default question mark
    if not profile.IC or (profile.IC ~= "Interface\\Icons\\INV_Misc_QuestionMark" and profile.IC ~= "") then
        return false
    end

    -- Check personality traits are empty string
    if profile.PS == nil then
        return false  -- Field missing
    end
    if profile.PS ~= "" then
        return false  -- Has personality traits
    end

    -- Check glances are empty string
    if profile.PE == nil then
        return false  -- Field missing
    end
    if profile.PE ~= "" then
        return false  -- Has glances
    end

    return true
end

function TRP3FW:CreateBlankProfile_MRP()
    if not mrp then return false end

    local profileName = GetBlankProfileName()

    -- MRP DOES have profiles, stored in mrpSaved.Profiles
    if not mrpSaved then
        self:Debug("[Profile Switch] mrpSaved not available", "hooks")
        return false
    end

    if not mrpSaved.Profiles then
        mrpSaved.Profiles = { ["Default"] = {} }
    end

    -- Check if blank profile already exists
    if mrpSaved.Profiles[profileName] then
        self:Debug("[Profile Switch] MRP blank profile already exists, checking validity...", "hooks")

        -- Debug: Show what's currently in the profile
        local count = 0
        for k, v in pairs(mrpSaved.Profiles[profileName]) do
            count = count + 1
            self:Debug("  Existing field: " .. k .. " = " .. tostring(v), "hooks")
        end
        self:Debug("  Total existing fields: " .. count, "hooks")

        -- Validate it's actually blank (only for default TRP3FW_BLANK name)
        if not ValidateMRPProfileIsBlank(mrpSaved.Profiles[profileName], profileName) then
            self:Debug("[Profile Switch] MRP blank profile exists but has been modified - recreating", "hooks")
            -- Profile was modified, FORCE recreate it by deleting first
            mrpSaved.Profiles[profileName] = nil
        else
            self:Debug("[Profile Switch] MRP blank profile already exists and is valid", "hooks")
            return true
        end
    else
        self:Debug("[Profile Switch] MRP blank profile does not exist, creating new one", "hooks")
    end

    -- Create blank profile with EXPLICIT empty fields (MRP inherits from Default if not set)
    -- All MSP fields that MRP supports need to be explicitly set to empty string
    mrpSaved.Profiles[profileName] = {
        -- Basic info
        ["NA"] = "",  -- Name
        ["NT"] = "",  -- Title
        ["NH"] = "",  -- House/Guild name
        ["NI"] = "",  -- Nickname

        -- Race/Class
        ["RA"] = "",  -- Race
        ["RC"] = "",  -- Class
        ["FC"] = "",  -- Character class (text)

        -- Status/Description
        ["CU"] = "",  -- Currently
        ["DE"] = "",  -- Description
        ["HI"] = "",  -- History
        ["CO"] = "1", -- Character status (1 = OOC, 2 = IC) - default to OOC for safety

        -- Physical
        ["AE"] = "",  -- Eye color
        ["AH"] = "",  -- Height
        ["AW"] = "",  -- Weight

        -- Other
        ["AG"] = "",  -- Age
        ["HB"] = "",  -- Birthplace
        ["HH"] = "",  -- Home
        ["MO"] = "",  -- Motto
        ["FR"] = "",  -- RP style/flag
        ["TT"] = "",  -- Roleplaying style
        ["RS"] = "",  -- Relationship status
        ["PN"] = "",  -- Pronouns

        -- Icon
        ["IC"] = "Interface\\Icons\\INV_Misc_QuestionMark",  -- Use default question mark icon

        -- Personality traits (blank string, not table)
        ["PS"] = "",

        -- Glances (blank string, not table)
        ["PE"] = "",
    }

    self:Debug("[Profile Switch] Created MRP blank profile: " .. profileName, "hooks")

    -- Debug: Verify what we just created
    self:Debug("[Profile Switch] Verifying created profile contents:", "hooks")
    if mrpSaved.Profiles[profileName] then
        local count = 0
        for k, v in pairs(mrpSaved.Profiles[profileName]) do
            count = count + 1
            self:Debug("  " .. k .. " = " .. tostring(v), "hooks")
        end
        self:Debug("[Profile Switch] Total fields in profile: " .. count, "hooks")
    end

    -- Force MRP to switch to it and back to ensure it's properly initialized
    if mrp.SetCurrentProfile then
        local currentProfile = mrpSaved.SelectedProfile
        mrp:SetCurrentProfile(profileName)
        if currentProfile and currentProfile ~= profileName then
            mrp:SetCurrentProfile(currentProfile)
        end
        self:Debug("[Profile Switch] Forced MRP profile initialization", "hooks")
    end

    return true
end

-- Validate that an XRP profile is actually blank (unmodified)
-- Only validates if using the default TRP3FW_BLANK name (safety feature)
local function ValidateXRPProfileIsBlank(profile, profileName)
    -- Skip validation if using custom profile name
    if profileName ~= "TRP3FW_BLANK" then
        return true
    end

    if not profile then return false end

    -- Check fields table is empty
    if profile.fields then
        for k, v in pairs(profile.fields) do
            -- Any field present means it's not blank
            return false
        end
    end

    -- Check inherits table (should be empty or all nil)
    if profile.inherits then
        for k, v in pairs(profile.inherits) do
            -- Any inheritance setting means it's been modified
            return false
        end
    end

    -- No parent profile should be set
    if profile.parent then
        return false
    end

    return true
end

function TRP3FW:CreateBlankProfile_XRP()
    if not AddOn_XRP then return false end

    local profileName = GetBlankProfileName()

    -- XRP DOES have profiles, stored in xrpSaved.profiles
    if not xrpSaved or not xrpSaved.profiles then
        self:Debug("[Profile Switch] xrpSaved not available", "hooks")
        return false
    end

    -- Check if blank profile already exists
    if xrpSaved.profiles[profileName] then
        -- Validate it's actually blank (only for default TRP3FW_BLANK name)
        if not ValidateXRPProfileIsBlank(xrpSaved.profiles[profileName], profileName) then
            self:Debug("[Profile Switch] XRP blank profile exists but has been modified - recreating", "hooks")
            -- Profile was modified, delete and recreate
            xrpSaved.profiles[profileName] = nil
        else
            self:Debug("[Profile Switch] XRP blank profile already exists and is valid", "hooks")
            return true
        end
    end

    -- Create blank profile using XRP's API
    AddOn_XRP.AddProfile(profileName)

    self:Debug("[Profile Switch] Created XRP blank profile: " .. profileName, "hooks")
    return true
end

-- Switch to blank (or selected) profile
function TRP3FW:SwitchToBlankProfile(targetProfile)
    targetProfile = targetProfile or { name = GetBlankProfileName() }
    local targetProfileName = targetProfile.name or GetBlankProfileName()
    local targetProfileID = targetProfile.id

    if self.isBlankProfileActive then
        self:Debug("[Profile Switch] Already using blank profile", "hooks")
        return
    end

    local txn, err = BeginProfileSwitch({ name = targetProfileName, id = targetProfileID })
    if not txn then
        self:Warn("Profile switch already in progress; skipping")
        return
    end

    local originals = {}
    txn.originals = originals

    local function fail(reason)
        self:Error("[Profile Switch] Aborting switch: " .. tostring(reason))
        RollbackProfileSwitch()
        return false
    end

    -- Preflight validation and target resolution per addon
    local trp3SwitchID = nil
    if TRP3_API and TRP3_API.profile then
        originals.TRP3 = TRP3_API.profile.getPlayerCurrentProfileID()

        if targetProfileID then
            trp3SwitchID = targetProfileID
        elseif targetProfileName == GetBlankProfileName() then
            trp3SwitchID = self:CreateBlankProfile_TRP3()
        else
            trp3SwitchID = FindTRP3ProfileIDByName(targetProfileName)
        end

        if not trp3SwitchID then
            return fail("TRP3 target profile missing")
        end

        -- Validate blank profile integrity if switching to default blank
        if targetProfileName == GetBlankProfileName() then
            local profile = TRP3_Profiles and TRP3_Profiles[trp3SwitchID]
            if not profile or not ValidateTRP3ProfileIsBlank(profile, targetProfileName) then
                self:Debug("[Profile Switch] TRP3 blank invalid; recreating", "hooks")
                trp3SwitchID = self:CreateBlankProfile_TRP3()
                profile = TRP3_Profiles and TRP3_Profiles[trp3SwitchID]
                if not profile or not ValidateTRP3ProfileIsBlank(profile, targetProfileName) then
                    return fail("TRP3 blank profile failed validation")
                end
            end
        end
    end

    local mrpTargetName = nil
    if mrp and mrpSaved then
        originals.MRP = mrpSaved.SelectedProfile
        mrpTargetName = targetProfileName

        if mrpTargetName == GetBlankProfileName() then
            if not self:CreateBlankProfile_MRP() then
                return fail("MRP blank create failed")
            end
            if not ValidateMRPProfileIsBlank(mrpSaved.Profiles[mrpTargetName], mrpTargetName) then
                return fail("MRP blank validation failed")
            end
        else
            if not (mrpSaved.Profiles and mrpSaved.Profiles[mrpTargetName]) then
                return fail("MRP target profile missing")
            end
        end
    end

    local xrpTargetName = nil
    if AddOn_XRP and xrpSaved then
        originals.XRP = xrpSaved.selected
        xrpTargetName = targetProfileName

        if xrpTargetName == GetBlankProfileName() then
            if not self:CreateBlankProfile_XRP() then
                return fail("XRP blank create failed")
            end
            if not ValidateXRPProfileIsBlank(xrpSaved.profiles and xrpSaved.profiles[xrpTargetName], xrpTargetName) then
                return fail("XRP blank validation failed")
            end
        else
            if not (xrpSaved.profiles and xrpSaved.profiles[xrpTargetName]) then
                return fail("XRP target profile missing")
            end
        end
    end

    -- TRP3
    if TRP3_API and TRP3_API.profile then
        if trp3SwitchID and TRP3_API.profile.selectProfile then
            TRP3_API.profile.selectProfile(trp3SwitchID)
            self:Debug("[Profile Switch] Switched TRP3 to profile ID: " .. trp3SwitchID, "hooks")
        elseif targetProfileName == GetBlankProfileName() then
            CommitProfileSwitch()
            self:Warn("Could not find or create blank profile for TRP3")
            return
        else
            CommitProfileSwitch()
            self:Warn("Profile override not found for TRP3: " .. tostring(targetProfileName))
            return
        end
    end

    -- MRP
    if mrp and mrpSaved then
        -- Switch to blank profile using MRP's API
        if mrp.SetCurrentProfile then
            mrp:SetCurrentProfile(mrpTargetName)
            self:Debug("[Profile Switch] Switched MRP to profile: " .. mrpTargetName, "hooks")

            -- Debug: Show what MSP is broadcasting after switch
            if msp and msp.my then
                self:Debug("[Profile Switch] MSP broadcast data after switch:", "hooks")
                local importantFields = {"NA", "NT", "CU", "DE", "HI"}
                for _, field in ipairs(importantFields) do
                    self:Debug("  " .. field .. " = " .. tostring(msp.my[field]), "hooks")
                end
            end
        end
    end

    -- XRP
    if AddOn_XRP and xrpSaved then
        -- Switch to blank profile using XRP's API (isAutomated=true preserves overrides)
        if xrpTargetName then
            AddOn_XRP.SetProfile(xrpTargetName, true)
            self:Debug("[Profile Switch] Switched XRP to profile: " .. xrpTargetName, "hooks")
        else
            self:Warn("No target profile specified for XRP switch")
        end
    end

    -- All switches succeeded; commit transactional state
    self.originalProfile = originals
    self.isBlankProfileActive = true
    self.lastSwitchedProfile = targetProfileName

    -- Save to SavedVariables for logout/login persistence
    SaveProfileTracking()
    CommitProfileSwitch()

    self:Info("Switched to profile (" .. tostring(targetProfileName) .. ")")
end

-- Restore original profile
function TRP3FW:RestoreOriginalProfile()
    if not self.isBlankProfileActive then
        self:Debug("[Profile Switch] Not using blank profile, nothing to restore", "hooks")
        return
    end

    if not self.originalProfile then
        self:Debug("[Profile Switch] No original profile stored", "hooks")
        self.isBlankProfileActive = false
        return
    end

    local txn, err = BeginProfileSwitch({ name = "restore" })
    if not txn then
        self:Warn("Profile restore already in progress; skipping")
        return
    end

    local restoreFailed = false

    -- TRP3
    if self.originalProfile.TRP3 and TRP3_API and TRP3_API.profile then
        if TRP3_API.profile.selectProfile then
            local profiles = TRP3_API.profile.getProfiles()
            if profiles and profiles[self.originalProfile.TRP3] then
                TRP3_API.profile.selectProfile(self.originalProfile.TRP3)
                self:Debug("[Profile Switch] Restored TRP3 profile: " .. self.originalProfile.TRP3, "hooks")
            else
                restoreFailed = true
                self:Debug("[Profile Switch] WARNING: Original TRP3 profile no longer exists: " .. self.originalProfile.TRP3, "hooks")
                self:Warn("Original TRP3 profile was deleted. Using default profile instead.")
            end
        end
    end

    -- MRP
    if self.originalProfile.MRP and mrp and mrp.SetCurrentProfile then
        if mrpSaved and mrpSaved.Profiles and mrpSaved.Profiles[self.originalProfile.MRP] then
            mrp:SetCurrentProfile(self.originalProfile.MRP)
            self:Debug("[Profile Switch] Restored MRP profile: " .. self.originalProfile.MRP, "hooks")
        else
            restoreFailed = true
            self:Debug("[Profile Switch] WARNING: Original MRP profile no longer exists: " .. self.originalProfile.MRP, "hooks")
            self:Warn("Original MRP profile was deleted. Using default profile instead.")
        end
    end

    -- XRP
    if self.originalProfile.XRP and AddOn_XRP and AddOn_XRP.SetProfile then
        if xrpSaved and xrpSaved.profile and xrpSaved.profile[self.originalProfile.XRP] then
            AddOn_XRP.SetProfile(self.originalProfile.XRP, true)
            self:Debug("[Profile Switch] Restored XRP profile: " .. self.originalProfile.XRP, "hooks")
        else
            restoreFailed = true
            self:Debug("[Profile Switch] WARNING: Original XRP profile no longer exists: " .. self.originalProfile.XRP, "hooks")
            self:Warn("Original XRP profile was deleted. Using default profile instead.")
        end
    end

    self.isBlankProfileActive = false
    self.lastSwitchedProfile = nil

    if TRP3FW.Prefs.savedProfiles then
        TRP3FW.Prefs.savedProfiles.original = nil
        TRP3FW.Prefs.savedProfiles.lastSwitchedProfile = nil
    end

    CommitProfileSwitch()

    if restoreFailed then
        self:Warn("Profile restore completed with warnings; some originals were missing")
    else
        self:Info("Restored original profile")
    end
end

-- Check if we should use blank profile
function TRP3FW:ShouldUseBlankProfile()
    if not TRP3FW.Prefs.ghostProfileSwitch then
        return false, nil
    end

    -- Check phase
    if not self.hasEpsilonAPI then
        return false, nil
    end

    local phaseID = tonumber(C_Epsilon.GetPhaseId())
    if not phaseID then
        return false, nil
    end

    -- Check map (can be nil in protected areas)
    local mapID = self:GetCurrentMapID()

    -- Helper to check optional exclusion entries (phase OR phase+map)
    local function IsExcludedPhase()
        if not TRP3FW.Prefs.ghostProfileWhitelistEnabled then
            return false
        end

        local list = TRP3FW.Prefs.ghostProfileWhitelist
        if not list or list == "" then
            return false
        end

        for line in string.gmatch(list, "[^\r\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
                local phaseStr, mapStr = trimmed:match("^(%d+)%s*,%s*(%d+)$")
                if phaseStr and mapStr then
                    local entryPhase = tonumber(phaseStr)
                    local entryMap = tonumber(mapStr)
                    if entryPhase and entryMap and entryPhase == phaseID and mapID and entryMap == mapID then
                        return true  -- exact phase+map match
                    end
                else
                    local phaseOnly = trimmed:match("^(%d+)$")
                    if phaseOnly and tonumber(phaseOnly) == phaseID then
                        return true  -- phase match (any map)
                    end
                end
            end
        end

        return false
    end

    -- Determine profile override (most specific match wins: phase+map > phase)
    local function GetOverrideProfile()
        local overrides = TRP3FW.Prefs.ghostProfileOverrides or {}
        local best = nil
        local bestSpecificity = 0  -- 0 = none, 1 = phase, 2 = phase+map

        for _, entry in ipairs(overrides) do
            if entry and entry.match and entry.match ~= "" and (entry.profileName or entry.profileID) then
                local trimmed = entry.match:match("^%s*(.-)%s*$")
                local phaseStr, mapStr = trimmed:match("^(%d+)%s*,%s*(%d+)$")
                local entryPhase, entryMap = tonumber(phaseStr or trimmed), tonumber(mapStr)

                if entryPhase and entryPhase == phaseID then
                    if entryMap and mapID and entryMap == mapID then
                        if bestSpecificity <= 2 then
                            best = { id = entry.profileID, name = entry.profileName or (entry.profileID and tostring(entry.profileID)) }
                            bestSpecificity = 2
                        end
                    elseif not entryMap then
                        if bestSpecificity < 1 then
                            best = { id = entry.profileID, name = entry.profileName or (entry.profileID and tostring(entry.profileID)) }
                            bestSpecificity = 1
                        end
                    end
                end
            end
        end

        return best
    end

    -- If this phase/map is explicitly excluded, keep the real profile
    if IsExcludedPhase() then
        return false, nil
    end

    -- Choose target profile (override if matched, otherwise global selection)
    local targetProfile = GetOverrideProfile() or { name = GetBlankProfileName() }

    -- Exclusion list enabled: switch everywhere else on Epsilon
    if TRP3FW.Prefs.ghostProfileWhitelistEnabled then
        return true, targetProfile
    end

    -- Legacy default: only switch in start phase/map
    if phaseID == START_PHASE_ID and mapID == START_MAP_ID then
        return true, targetProfile
    end

    return false, nil
end

-- 선택한 (또는 선택한) 프로필로 전환
-- Monitor phase/map changes and switch profiles automatically
local function OnProfileSwitchEvent(event)
    local ES = TRP3FW.ServiceContainer:Get("EventService")

    -- Initialize profile tracking on login
    if event == "PLAYER_ENTERING_WORLD" then
        InitializeProfileTracking()

        -- Check if we logged out with blank profile active
        -- and need to restore on login outside phase 169/map 1605
        C_Timer.After(1.0, function()
            local shouldUseBlank, targetProfile = TRP3FW:ShouldUseBlankProfile()

            -- Detect if blank profile is currently active
            local profileName = GetBlankProfileName()
            local lastSwitchedName = TRP3FW.Prefs.savedProfiles and TRP3FW.Prefs.savedProfiles.lastSwitchedProfile
            local targetNames = {}
            targetNames[profileName] = true
            if lastSwitchedName then
                targetNames[lastSwitchedName] = true
            end

            local isOnSwitchedProfile = false
            local blankIntegrityOK = true
            if TRP3_API and TRP3_API.profile then
                local currentProfileID = TRP3_API.profile.getPlayerCurrentProfileID()
                -- Check if current profile ID matches any switched profile by name
                for name in pairs(targetNames) do
                    local targetID = FindTRP3ProfileIDByName(name)
                    if targetID and currentProfileID == targetID then
                        isOnSwitchedProfile = true
                        local profile = TRP3_Profiles and TRP3_Profiles[targetID]
                        if profile and name == GetBlankProfileName() then
                            blankIntegrityOK = ValidateTRP3ProfileIsBlank(profile, name)
                        end
                        break
                    end
                end
            elseif mrpSaved and targetNames[mrpSaved.SelectedProfile] then
                isOnSwitchedProfile = true
                if mrpSaved.Profiles and mrpSaved.Profiles[mrpSaved.SelectedProfile] and mrpSaved.SelectedProfile == GetBlankProfileName() then
                    blankIntegrityOK = ValidateMRPProfileIsBlank(mrpSaved.Profiles[mrpSaved.SelectedProfile], mrpSaved.SelectedProfile)
                end
            elseif xrpSaved and targetNames[xrpSaved.selected] then
                isOnSwitchedProfile = true
                if xrpSaved.profiles and xrpSaved.selected and xrpSaved.selected == GetBlankProfileName() then
                    blankIntegrityOK = ValidateXRPProfileIsBlank(xrpSaved.profiles[xrpSaved.selected], xrpSaved.selected)
                end
            end

            -- If we're on blank profile but shouldn't be, restore
            if isOnSwitchedProfile and (not shouldUseBlank or not blankIntegrityOK) and TRP3FW.originalProfile then
                TRP3FW:Debug("[Profile Switch] Login detected with blank profile active, restoring original", "hooks")
                TRP3FW.isBlankProfileActive = true  -- Set flag so restore works
                TRP3FW:RestoreOriginalProfile()
            end
        end)
    end

    -- Small delay to let map/phase info stabilize
    C_Timer.After(0.5, function()
        -- CRITICAL: Only run profile switching if explicitly enabled
        -- This prevents crashes in other TRP3 addons that expect valid profile data
        if not TRP3FW.Prefs.ghostProfileSwitch then
            return
        end

        -- WARNING: Profile switching is EXPERIMENTAL and may cause crashes in other addons
        -- Show one-time warning
        if not TRP3FW.profileSwitchWarningShown then
            TRP3FW.profileSwitchWarningShown = true
            TRP3FW:Warn("Profile switching is EXPERIMENTAL and may cause errors in other TRP3 addons")
            TRP3FW:Warn("If you experience issues, disable ghostProfileSwitch in TRP3FW settings")
        end

        local shouldUseBlank, targetProfile = TRP3FW:ShouldUseBlankProfile()

        if shouldUseBlank then
            if not TRP3FW.isBlankProfileActive then
                -- Wrap in pcall to prevent crashes in other addons from breaking TRP3FW
                local success, err = pcall(function()
                    TRP3FW:SwitchToBlankProfile(targetProfile)
                end)
                if not success then
                    TRP3FW:Error("[Profile Switch] Failed to switch to blank profile: "..tostring(err))
                    TRP3FW:Error("Consider disabling ghostProfileSwitch to avoid errors")
                end
            end
        else
            if TRP3FW.isBlankProfileActive then
                -- Wrap in pcall to prevent crashes in other addons from breaking TRP3FW
                local success, err = pcall(function()
                    TRP3FW:RestoreOriginalProfile()
                end)
                if not success then
                    TRP3FW:Error("[Profile Switch] Failed to restore original profile: "..tostring(err))
                    TRP3FW:Error("Consider disabling ghostProfileSwitch to avoid errors")
                end
            end
        end
    end)
end

-- Initialize the profile switch monitor when the addon is ready
C_Timer.After(1, function()
    local ES = TRP3FW.ServiceContainer:Get("EventService")
    if ES then
        ES:RegisterCallback(ES.Events.ZONE_CHANGED, OnProfileSwitchEvent)
        ES:RegisterCallback(ES.Events.PHASE_CHANGED, OnProfileSwitchEvent)
    end
end)

TRP3FW:Debug("[Profile Switch] Module loaded", "hooks")
