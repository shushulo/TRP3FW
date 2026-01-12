-- features/ghost_provider.lua
-- Ghost profile data provider with validation

local addonName, TRP3FW = ...

TRP3FW.GhostProvider = {}
local GP = TRP3FW.GhostProvider

-- Get a valid ghost profile (or blank fallback)
function GP:GetProfile(profileID, profileType)
    -- Validate ID
    if profileID and profileID ~= "" then
        if not self:IsValidProfileID(profileID) then
            TRP3FW:Error("[GhostProvider] Invalid profile ID: "..profileID..". Using blank profile.")
            profileID = nil -- Fallback to blank
        end
    end

    -- Retrieve profile
    if not profileID or profileID == "" then
        return self:GetBlankProfile(profileType)
    else
        -- Double-check profile still exists (TOCTOU protection)
        -- Assuming GetAlternateProfile is the existing function in ghostmode.lua
        local profile = TRP3FW:GetAlternateProfile(profileID, profileType)
        if not profile or not next(profile) then
            TRP3FW:Warn("[GhostProvider] Profile "..profileID.." is empty or missing. Using blank.")
            return self:GetBlankProfile(profileType)
        end
        return profile
    end
end

-- Validate a profile ID exists in TRP3
function GP:IsValidProfileID(profileID)
    if not profileID or profileID == "" then
        return true -- Blank is always valid
    end

    if not TRP3_API or not TRP3_API.profile or not TRP3_API.profile.getProfiles then
        TRP3FW:Error("[GhostProvider] TRP3 API not available")
        return false
    end

    local profiles = TRP3_API.profile.getProfiles()
    if not profiles or not profiles[profileID] then
        return false
    end

    local profile = profiles[profileID]
    if not profile.characteristics then
        TRP3FW:Warn("[GhostProvider] Profile missing characteristics: "..profileID)
        return false
    end

    return true
end

-- Get blank profile data (wrapper for existing functions)
function GP:GetBlankProfile(profileType)
    if profileType == "characteristics" then
        return TRP3FW:GetBlankCharacteristicsData()
    elseif profileType == "about" then
        return TRP3FW:GetBlankAboutData()
    elseif profileType == "misc" then
        return TRP3FW:GetBlankMiscData()
    elseif profileType == "character" then
        return TRP3FW:GetBlankCharacterData()
    end
    return nil
end
