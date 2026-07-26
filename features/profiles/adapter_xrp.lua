-- features/profiles/adapter_xrp.lua
-- XRP profile adapter implementation

local addonName, TRP3FW = ...

local XRPAdapter = {}

-- Check if XRP is available
function XRPAdapter:IsAvailable()
    return AddOn_XRP and xrpSaved and xrpSaved.profiles and xrpSaved.selected and true or false
end

-- Get addon name
function XRPAdapter:GetAddonName()
    return "XRP"
end

-- Get all available profiles
function XRPAdapter:GetProfiles()
    if not self:IsAvailable() then
        TRP3FW:Debug("XRP adapter: XRP not available", "hooks")
        return {}
    end

    local profiles = {}
    local currentName = xrpSaved.selected

    -- Use XRP's API to get profile list if available
    local profileList
    if AddOn_XRP.GetProfileList then
        profileList = AddOn_XRP.GetProfileList()
    else
        -- Fallback: enumerate manually
        profileList = {}
        for profileName in pairs(xrpSaved.profiles) do
            table.insert(profileList, profileName)
        end
        table.sort(profileList)
    end

    for _, profileName in ipairs(profileList) do
        local profileData = xrpSaved.profiles[profileName]
        if profileData then
            table.insert(profiles, {
                id = profileName,
                name = profileName,
                addon = "XRP",
                isCurrent = (profileName == currentName),
                data = profileData
            })
        end
    end

    if TRP3FW:ShouldLogProfileCount("XRP") then
        TRP3FW:Debug("XRP adapter: Found "..#profiles.." profiles", "hooks")
    end
    return profiles
end

-- Get current active profile
function XRPAdapter:GetCurrentProfile()
    if not self:IsAvailable() then
        TRP3FW:Debug("XRP adapter: XRP not available for GetCurrentProfile", "hooks")
        return nil
    end

    local currentName = xrpSaved.selected
    if not currentName then
        TRP3FW:Debug("XRP adapter: No profile selected", "hooks")
        return nil
    end

    local profileData = xrpSaved.profiles[currentName]
    if not profileData then
        TRP3FW:Debug("XRP adapter: Current profile '"..currentName.."' not found", "hooks")
        return nil
    end

    return {
        id = currentName,
        name = currentName,
        addon = "XRP",
        isCurrent = true,
        data = profileData
    }
end

-- Get specific profile by ID (name)
function XRPAdapter:GetProfileByID(id)
    if not self:IsAvailable() or not id then
        TRP3FW:Debug("XRP adapter: Cannot get profile by ID (available: "..tostring(self:IsAvailable())..", id: "..tostring(id)..")", "hooks")
        return nil
    end

    local profileData = xrpSaved.profiles[id]
    if not profileData then
        TRP3FW:Debug("XRP adapter: Profile '"..tostring(id).."' not found", "hooks")
        return nil
    end

    local currentName = xrpSaved.selected

    return {
        id = id,
        name = id,
        addon = "XRP",
        isCurrent = (id == currentName),
        data = profileData
    }
end

-- Get characteristics data from profile
-- XRP uses fields table with MSP structure
function XRPAdapter:GetCharacteristics(id)
    local profile = self:GetProfileByID(id)
    if not profile or not profile.data or not profile.data.fields then
        TRP3FW:Debug("XRP adapter: No profile data or fields for GetCharacteristics", "hooks")
        return nil
    end

    local fields = profile.data.fields

    -- Map XRP fields to TRP3-like characteristics structure
    return {
        v = 1,
        FN = fields.NA or "",    -- Name
        RA = fields.RA or "",    -- Race
        CL = fields.RC or "",    -- Class
        IC = fields.IC or "",    -- Icon
        TI = fields.NT or "",    -- Title
        NH = fields.NH or "",    -- House
        NI = fields.NI or "",    -- Nickname
        AG = fields.AG or "",    -- Age
        AE = fields.AE or "",    -- Eye color
        AH = fields.AH or "",    -- Height
        AW = fields.AW or "",    -- Weight
        HB = fields.HB or "",    -- Birthplace
        HH = fields.HH or "",    -- Home
        MI = {},                 -- Misc traits (XRP doesn't have this structure)
        PS = {},                 -- Personality traits (XRP doesn't have this structure)
    }
end

-- Get about data from profile
function XRPAdapter:GetAbout(id)
    local profile = self:GetProfileByID(id)
    if not profile or not profile.data or not profile.data.fields then
        TRP3FW:Debug("XRP adapter: No profile data or fields for GetAbout", "hooks")
        return nil
    end

    local fields = profile.data.fields

    -- Map XRP fields to TRP3-like about structure
    return {
        v = 1,
        TE = 1,                  -- Template type (1 = simple text)
        BK = 1,                  -- Background
        MU = fields.MU or "",    -- Music
        T1 = {
            TX = fields.DE or "",  -- Description
        },
        -- Note: XRP also has HI (history), but we're using simple template for compatibility
    }
end

-- Get misc data from profile
function XRPAdapter:GetMisc(id)
    local profile = self:GetProfileByID(id)
    if not profile or not profile.data or not profile.data.fields then
        TRP3FW:Debug("XRP adapter: No profile data or fields for GetMisc", "hooks")
        return nil
    end

    local fields = profile.data.fields

    -- Map XRP fields to TRP3-like misc structure
    return {
        v = 1,
        PE = {},                 -- Peek/glance slots (XRP doesn't have this)
        ST = {},                 -- RP styles (XRP doesn't have this)
        CU = fields.CU or "",    -- Currently
        CO = fields.CO or "",    -- Currently OOC
    }
end

-- Get character data from profile
function XRPAdapter:GetCharacter(id)
    local profile = self:GetProfileByID(id)
    if not profile or not profile.data or not profile.data.fields then
        TRP3FW:Debug("XRP adapter: No profile data or fields for GetCharacter", "hooks")
        return nil
    end

    local fields = profile.data.fields

    -- Map XRP fields to TRP3-like character structure.
    --
    -- Same correction as adapter_mrp: RP/XP were hardcoded to 1 on the claim that XRP "uses FC
    -- differently". FC/FR are standard MSP fields with a defined mapping, which TRP3 itself
    -- implements (totalRP3/modules/register/msp/register_msp.lua:437-443 and :450).
    --
    -- The RP case is the one that mattered: a ghosted XRP profile always reported
    -- IN-CHARACTER even when the source profile was explicitly flagged OOC.
    return {
        v = 1,
        CU = fields.CU or "",    -- Currently IC
        CO = fields.CO or "",    -- Currently OOC
        -- FC == "1" is OOC -> RP = 2; anything else (including absent) -> RP = 1 (IC).
        RP = (fields.FC == "1") and 2 or 1,
        -- FR == "4" is the "not looking for RP" end -> XP = 1; otherwise XP = 2.
        -- Note this reads INVERSE to intuition; it matches TRP3's own conversion.
        XP = (fields.FR == "4") and 1 or 2,
    }
end

-- Validate that a profile ID exists
function XRPAdapter:ValidateProfileID(id)
    return self:GetProfileByID(id) ~= nil
end

-- Check if profile ID is the current profile
function XRPAdapter:IsCurrentProfile(id)
    if not self:IsAvailable() then
        return false
    end

    return xrpSaved.selected == id
end

-- Register adapter
TRP3FW.Adapters.XRP = XRPAdapter
TRP3FW:Debug("XRP profile adapter registered", "hooks")
