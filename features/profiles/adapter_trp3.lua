-- features/profiles/adapter_trp3.lua
-- TotalRP3 profile adapter implementation

local addonName, TRP3FW = ...

local TRP3Adapter = {}

-- Check if TRP3 is available
function TRP3Adapter:IsAvailable()
    return TRP3_API and TRP3_API.profile and true or false
end

-- Get addon name
function TRP3Adapter:GetAddonName()
    return "TRP3"
end

-- Get all available profiles
function TRP3Adapter:GetProfiles()
    if not self:IsAvailable() then
        TRP3FW:Debug("TRP3 adapter: TRP3 not available", "hooks")
        return {}
    end

    local profiles = {}
    local currentID = TRP3_API.profile.getPlayerCurrentProfileID()
    local allProfiles = TRP3_API.profile.getProfiles()

    if not allProfiles then
        TRP3FW:Debug("TRP3 adapter: No profiles found", "hooks")
        return {}
    end

    for profileID, profileData in pairs(allProfiles) do
        table.insert(profiles, {
            id = profileID,
            name = profileData.profileName or profileID,
            addon = "TRP3",
            isCurrent = (profileID == currentID),
            data = profileData
        })
    end

    -- Sort by name
    table.sort(profiles, function(a, b) return a.name < b.name end)

    if TRP3FW:ShouldLogProfileCount() then
        TRP3FW:Debug("TRP3 adapter: Found "..#profiles.." profiles", "hooks")
    end
    return profiles
end

-- Get current active profile
function TRP3Adapter:GetCurrentProfile()
    if not self:IsAvailable() then
        TRP3FW:Debug("TRP3 adapter: TRP3 not available for GetCurrentProfile", "hooks")
        return nil
    end

    local currentID = TRP3_API.profile.getPlayerCurrentProfileID()
    local profileData = TRP3_API.profile.getPlayerCurrentProfile()

    if not profileData then
        TRP3FW:Debug("TRP3 adapter: No current profile data", "hooks")
        return nil
    end

    return {
        id = currentID,
        name = profileData.profileName or currentID,
        addon = "TRP3",
        isCurrent = true,
        data = profileData
    }
end

-- Get specific profile by ID
function TRP3Adapter:GetProfileByID(id)
    if not self:IsAvailable() or not id then
        TRP3FW:Debug("TRP3 adapter: Cannot get profile by ID (available: "..tostring(self:IsAvailable())..", id: "..tostring(id)..")", "hooks")
        return nil
    end

    -- IMPORTANT: Check YOUR profiles first (for ghost mode alternate profiles)
    -- Then fallback to register (for viewing other players' profiles)
    local profileData = TRP3_API.profile.getProfiles()[id]

    -- If not found in your profiles, try register (other players)
    if not profileData and TRP3_API.register.getProfileOrNil then
        profileData = TRP3_API.register.getProfileOrNil(id)
    end

    if not profileData then
        TRP3FW:Debug("TRP3 adapter: Profile '"..tostring(id).."' not found", "hooks")
        return nil
    end

    local currentID = TRP3_API.profile.getPlayerCurrentProfileID()

    return {
        id = id,
        name = profileData.profileName or id,
        addon = "TRP3",
        isCurrent = (id == currentID),
        data = profileData
    }
end

-- Get characteristics data from profile
function TRP3Adapter:GetCharacteristics(id)
    local profile = self:GetProfileByID(id)
    if not profile or not profile.data then
        TRP3FW:Debug("TRP3 adapter: No profile data for GetCharacteristics", "hooks")
        return nil
    end

    if not profile.data.player or not profile.data.player.characteristics then
        TRP3FW:Debug("TRP3 adapter: No characteristics in profile", "hooks")
        return nil
    end

    return profile.data.player.characteristics
end

-- Get about data from profile
function TRP3Adapter:GetAbout(id)
    local profile = self:GetProfileByID(id)
    if not profile or not profile.data then
        TRP3FW:Debug("TRP3 adapter: No profile data for GetAbout", "hooks")
        return nil
    end

    if not profile.data.player or not profile.data.player.about then
        TRP3FW:Debug("TRP3 adapter: No about data in profile", "hooks")
        return nil
    end

    return profile.data.player.about
end

-- Get misc data from profile
function TRP3Adapter:GetMisc(id)
    local profile = self:GetProfileByID(id)
    if not profile or not profile.data then
        TRP3FW:Debug("TRP3 adapter: No profile data for GetMisc", "hooks")
        return nil
    end

    if not profile.data.player or not profile.data.player.misc then
        TRP3FW:Debug("TRP3 adapter: No misc data in profile", "hooks")
        return nil
    end

    return profile.data.player.misc
end

-- Get character data from profile
function TRP3Adapter:GetCharacter(id)
    local profile = self:GetProfileByID(id)
    if not profile or not profile.data then
        TRP3FW:Debug("TRP3 adapter: No profile data for GetCharacter", "hooks")
        return nil
    end

    if not profile.data.player or not profile.data.player.character then
        TRP3FW:Debug("TRP3 adapter: No character data in profile", "hooks")
        return nil
    end

    return profile.data.player.character
end

-- Validate that a profile ID exists
function TRP3Adapter:ValidateProfileID(id)
    return self:GetProfileByID(id) ~= nil
end

-- Check if profile ID is the current profile
function TRP3Adapter:IsCurrentProfile(id)
    if not self:IsAvailable() then
        return false
    end

    local currentID = TRP3_API.profile.getPlayerCurrentProfileID()
    return currentID == id
end

-- Register adapter
TRP3FW.Adapters.TRP3 = TRP3Adapter
TRP3FW:Debug("TRP3 profile adapter registered", "hooks")
