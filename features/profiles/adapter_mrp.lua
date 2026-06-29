-- features/profiles/adapter_mrp.lua
-- MyRolePlay profile adapter implementation

local addonName, TRP3FW = ...

local MRPAdapter = {}

-- Check if MRP is available
function MRPAdapter:IsAvailable()
    return mrp and mrpSaved and mrpSaved.Profiles and true or false
end

-- Get addon name
function MRPAdapter:GetAddonName()
    return "MRP"
end

-- Get all available profiles
function MRPAdapter:GetProfiles()
    if not self:IsAvailable() then
        TRP3FW:Debug("MRP adapter: MRP not available", "hooks")
        return {}
    end

    local profiles = {}
    local currentName = mrpSaved.SelectedProfile or "Default"

    for profileName, profileData in pairs(mrpSaved.Profiles) do
        table.insert(profiles, {
            id = profileName,
            name = profileName,
            addon = "MRP",
            isCurrent = (profileName == currentName),
            data = profileData
        })
    end

    -- Sort, Default first
    table.sort(profiles, function(a, b)
        if a.name == "Default" then return true end
        if b.name == "Default" then return false end
        return a.name < b.name
    end)

    if TRP3FW:ShouldLogProfileCount() then
        TRP3FW:Debug("MRP adapter: Found "..#profiles.." profiles", "hooks")
    end
    return profiles
end

-- Get current active profile
function MRPAdapter:GetCurrentProfile()
    if not self:IsAvailable() then
        TRP3FW:Debug("MRP adapter: MRP not available for GetCurrentProfile", "hooks")
        return nil
    end

    local currentName = mrpSaved.SelectedProfile or "Default"
    local profileData = mrpSaved.Profiles[currentName]

    if not profileData then
        TRP3FW:Debug("MRP adapter: Current profile '"..currentName.."' not found", "hooks")
        return nil
    end

    return {
        id = currentName,
        name = currentName,
        addon = "MRP",
        isCurrent = true,
        data = profileData
    }
end

-- Get specific profile by ID (name)
function MRPAdapter:GetProfileByID(id)
    if not self:IsAvailable() or not id then
        TRP3FW:Debug("MRP adapter: Cannot get profile by ID (available: "..tostring(self:IsAvailable())..", id: "..tostring(id)..")", "hooks")
        return nil
    end

    local profileData = mrpSaved.Profiles[id]
    if not profileData then
        TRP3FW:Debug("MRP adapter: Profile '"..tostring(id).."' not found", "hooks")
        return nil
    end

    local currentName = mrpSaved.SelectedProfile or "Default"

    return {
        id = id,
        name = id,
        addon = "MRP",
        isCurrent = (id == currentName),
        data = profileData
    }
end

-- Get characteristics data from profile
-- MRP uses flat MSP structure, so we map to TRP3-like format
function MRPAdapter:GetCharacteristics(id)
    local profile = self:GetProfileByID(id)
    if not profile or not profile.data then
        TRP3FW:Debug("MRP adapter: No profile data for GetCharacteristics", "hooks")
        return nil
    end

    local data = profile.data

    -- Map MRP MSP fields to TRP3-like characteristics structure
    return {
        v = 1,
        FN = data.NA or "",      -- Name
        RA = data.RA or "",      -- Race
        CL = data.RC or "",      -- Class (RC in MSP)
        IC = data.IC or "",      -- Icon
        TI = data.NT or "",      -- Title
        NH = data.NH or "",      -- House/nickname house
        NI = data.NI or "",      -- Nickname
        AG = data.AG or "",      -- Age
        AE = data.AE or "",      -- Eye color
        AH = data.AH or "",      -- Height
        AW = data.AW or "",      -- Weight
        HB = data.HB or "",      -- Birthplace
        HH = data.HH or "",      -- Home/residence
        MI = {},                 -- Misc traits (MRP doesn't have this structure)
        PS = {},                 -- Personality traits (MRP doesn't have this structure)
    }
end

-- Get about data from profile
function MRPAdapter:GetAbout(id)
    local profile = self:GetProfileByID(id)
    if not profile or not profile.data then
        TRP3FW:Debug("MRP adapter: No profile data for GetAbout", "hooks")
        return nil
    end

    local data = profile.data

    -- Map MRP MSP fields to TRP3-like about structure
    return {
        v = 1,
        TE = 1,                  -- Template type (1 = simple text, closest to MRP)
        BK = 1,                  -- Background
        MU = data.MU or "",      -- Music
        T1 = {
            TX = data.DE or "",  -- Description (short) - map to template 1 text
        },
        -- Note: MRP has HI (history/long description) separate, but TRP3 template 1 only has one text field
        -- We'll use DE for simplicity, or could create T3 structure with separate HI
    }
end

-- Get misc data from profile
function MRPAdapter:GetMisc(id)
    local profile = self:GetProfileByID(id)
    if not profile or not profile.data then
        TRP3FW:Debug("MRP adapter: No profile data for GetMisc", "hooks")
        return nil
    end

    local data = profile.data

    -- Map MRP MSP fields to TRP3-like misc structure
    return {
        v = 1,
        PE = {},                 -- Peek/glance slots (MRP has custom glances field, not included here)
        ST = {},                 -- RP styles (MRP doesn't have this)
        CU = data.CU or "",      -- Currently (included here for convenience)
        CO = data.CO or "",      -- Currently OOC
    }
end

-- Get character data from profile
function MRPAdapter:GetCharacter(id)
    local profile = self:GetProfileByID(id)
    if not profile or not profile.data then
        TRP3FW:Debug("MRP adapter: No profile data for GetCharacter", "hooks")
        return nil
    end

    local data = profile.data

    -- Map MRP MSP fields to TRP3-like character structure
    return {
        v = 1,
        CU = data.CU or "",      -- Currently IC
        CO = data.CO or "",      -- Currently OOC
        RP = 1,                  -- RP status (1=IC) - MRP uses FC field differently
        XP = 1,                  -- Experience level (MRP doesn't have this)
    }
end

-- Validate that a profile ID exists
function MRPAdapter:ValidateProfileID(id)
    return self:GetProfileByID(id) ~= nil
end

-- Check if profile ID is the current profile
function MRPAdapter:IsCurrentProfile(id)
    if not self:IsAvailable() then
        return false
    end

    local currentName = mrpSaved.SelectedProfile or "Default"
    return currentName == id
end

-- Register adapter
TRP3FW.Adapters.MRP = MRPAdapter
TRP3FW:Debug("MRP profile adapter registered", "hooks")
