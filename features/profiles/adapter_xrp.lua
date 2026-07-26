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

-- Characteristics / About / Misc / Character.
--
-- Shared with the MRP adapter: both store flat MSP fields and converted them with
-- near-identical bodies, differing only by the .fields indirection and comment wording.
-- See adapter_msp_shared.lua.
TRP3FW.MSPAdapterShared.Apply(XRPAdapter, "XRP", function(profile)
    -- XRP nests MSP fields under .fields.
    --
    -- NOTE these are the profile's OWN fields, NOT the parent-inheritance-resolved set: XRP
    -- resolves fields through a parent chain and a child stores only its overrides
    -- (XRP/Backend/Profiles.lua:86-125). GetProfileByID returns xrpSaved.profiles[id] raw, so
    -- a child profile read through this adapter reports only what it overrides.
    --
    -- That is pre-existing behaviour, unchanged by this refactor. The ghost-send path does
    -- walk the chain (hooks/msp_exchange.lua), which is where it actually matters -- these
    -- getters feed the settings UI's profile preview. Flagged here rather than fixed because
    -- changing it alters what the UI displays and deserves its own decision.
    return profile.data and profile.data.fields
end)

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
