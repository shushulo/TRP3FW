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

    if TRP3FW:ShouldLogProfileCount("MRP") then
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

-- Characteristics / About / Misc / Character.
--
-- These four getters were near-identical copies of XRP's, differing only by where the MSP
-- fields live (MRP: profile.data, XRP: profile.data.fields), the adapter name in the debug
-- string, and comment wording -- the field mappings themselves were the same. That is the
-- shape that let the FC/FR hardcode exist twice and need fixing twice. They now come from
-- one implementation in adapter_msp_shared.lua.
TRP3FW.MSPAdapterShared.Apply(MRPAdapter, "MRP", function(profile)
    -- MRP stores MSP fields flat on the profile itself.
    return profile.data
end)

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
