-- features/profiles/adapter_factory.lua
-- Profile adapter factory - Auto-detect which RP addon is available

local addonName, TRP3FW = ...

-- Cache for detected adapter (avoid repeated detection)
TRP3FW.cachedProfileAdapter = nil
TRP3FW.detectedProfileAddon = nil

--- Get the appropriate profile adapter based on which RP addon is installed
-- Tries adapters in priority order: TRP3 > MRP > XRP
-- @return adapter object or nil if no RP addon detected
function TRP3FW:GetProfileAdapter()
	-- Return cached adapter if already detected
	if self.cachedProfileAdapter then
		TRP3FW:Debug("Using cached profile adapter: "..tostring(self.detectedProfileAddon), "hooks")
		return self.cachedProfileAdapter
	end

	TRP3FW:Debug("Detecting available RP addon...", "hooks")

	-- Try TRP3 first (highest priority)
	if self.Adapters.TRP3 and self.Adapters.TRP3:IsAvailable() then
		self.cachedProfileAdapter = self.Adapters.TRP3
		self.detectedProfileAddon = "TRP3"
		TRP3FW:Debug("Detected profile adapter: TRP3", "hooks")
		return self.Adapters.TRP3
	end

	-- Try MRP second
	if self.Adapters.MRP and self.Adapters.MRP:IsAvailable() then
		self.cachedProfileAdapter = self.Adapters.MRP
		self.detectedProfileAddon = "MRP"
		TRP3FW:Debug("Detected profile adapter: MRP", "hooks")
		return self.Adapters.MRP
	end

	-- Try XRP third (lowest priority)
	if self.Adapters.XRP and self.Adapters.XRP:IsAvailable() then
		self.cachedProfileAdapter = self.Adapters.XRP
		self.detectedProfileAddon = "XRP"
		TRP3FW:Debug("Detected profile adapter: XRP", "hooks")
		return self.Adapters.XRP
	end

	-- No RP addon detected
	TRP3FW:Debug("No RP addon detected (TRP3, MRP, XRP not available)", "hooks")
	return nil
end

--- Get the name of the detected RP addon
-- @return "TRP3", "MRP", "XRP", or nil if no addon detected
function TRP3FW:GetDetectedAddonName()
	if not self.detectedProfileAddon then
		-- Trigger detection if not done yet
		self:GetProfileAdapter()
	end
	return self.detectedProfileAddon
end

--- Clear the cached adapter (force re-detection on next call)
-- Useful if user loads/unloads an RP addon at runtime
function TRP3FW:ClearAdapterCache()
	TRP3FW:Debug("Clearing profile adapter cache", "hooks")
	self.cachedProfileAdapter = nil
	self.detectedProfileAddon = nil
end

--- Get all available profiles from the detected RP addon
-- @return array of Profile objects, or empty table if no addon detected
-- Profile object: { id, name, addon, isCurrent, data }
function TRP3FW:GetAllProfiles()
	local adapter = self:GetProfileAdapter()
	if not adapter then
		TRP3FW:Debug("Cannot get profiles: No RP addon detected", "hooks")
		return {}
	end

	local profiles = adapter:GetProfiles()
	TRP3FW:Debug("Retrieved "..#profiles.." profiles from "..self.detectedProfileAddon, "hooks")
	return profiles
end

--- Get the current active profile from the detected RP addon
-- @return Profile object or nil
function TRP3FW:GetCurrentProfile()
	local adapter = self:GetProfileAdapter()
	if not adapter then
		TRP3FW:Debug("Cannot get current profile: No RP addon detected", "hooks")
		return nil
	end

	local profile = adapter:GetCurrentProfile()
	if profile then
		TRP3FW:Debug("Current profile: "..tostring(profile.name).." (ID: "..tostring(profile.id)..")", "hooks")
	else
		TRP3FW:Debug("No current profile found", "hooks")
	end
	return profile
end

--- Get a specific profile by ID
-- @param id Profile ID (UUID for TRP3, name for MRP/XRP)
-- @return Profile object or nil
function TRP3FW:GetProfileByID(id)
	local adapter = self:GetProfileAdapter()
	if not adapter then
		TRP3FW:Debug("Cannot get profile by ID: No RP addon detected", "hooks")
		return nil
	end

	if not id then
		TRP3FW:Debug("Cannot get profile: ID is nil", "hooks")
		return nil
	end

	local profile = adapter:GetProfileByID(id)
	if profile then
		TRP3FW:Debug("Retrieved profile: "..tostring(profile.name).." (ID: "..tostring(id)..")", "hooks")
	else
		TRP3FW:Debug("Profile not found: "..tostring(id), "hooks")
	end
	return profile
end

--- Validate that a profile ID exists
-- @param id Profile ID
-- @return boolean
function TRP3FW:ValidateProfileID(id)
	local adapter = self:GetProfileAdapter()
	if not adapter then
		return false
	end

	return adapter:ValidateProfileID(id)
end

--- Check if a profile ID is the current profile
-- @param id Profile ID
-- @return boolean
function TRP3FW:IsCurrentProfile(id)
	local adapter = self:GetProfileAdapter()
	if not adapter then
		return false
	end

	return adapter:IsCurrentProfile(id)
end

--- Get profile characteristics data
-- @param id Profile ID (nil = current profile)
-- @return table or nil
function TRP3FW:GetProfileCharacteristics(id)
	local adapter = self:GetProfileAdapter()
	if not adapter then
		return nil
	end

	-- Use current profile if no ID specified
	if not id then
		local current = adapter:GetCurrentProfile()
		if not current then return nil end
		id = current.id
	end

	return adapter:GetCharacteristics(id)
end

--- Get profile about data
-- @param id Profile ID (nil = current profile)
-- @return table or nil
function TRP3FW:GetProfileAbout(id)
	local adapter = self:GetProfileAdapter()
	if not adapter then
		return nil
	end

	-- Use current profile if no ID specified
	if not id then
		local current = adapter:GetCurrentProfile()
		if not current then return nil end
		id = current.id
	end

	return adapter:GetAbout(id)
end

--- Get profile misc data
-- @param id Profile ID (nil = current profile)
-- @return table or nil
function TRP3FW:GetProfileMisc(id)
	local adapter = self:GetProfileAdapter()
	if not adapter then
		return nil
	end

	-- Use current profile if no ID specified
	if not id then
		local current = adapter:GetCurrentProfile()
		if not current then return nil end
		id = current.id
	end

	return adapter:GetMisc(id)
end

--- Get profile character data
-- @param id Profile ID (nil = current profile)
-- @return table or nil
function TRP3FW:GetProfileCharacter(id)
	local adapter = self:GetProfileAdapter()
	if not adapter then
		return nil
	end

	-- Use current profile if no ID specified
	if not id then
		local current = adapter:GetCurrentProfile()
		if not current then return nil end
		id = current.id
	end

	return adapter:GetCharacter(id)
end

TRP3FW:Debug("Profile adapter factory loaded", "hooks")
