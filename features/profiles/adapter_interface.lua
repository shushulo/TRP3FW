-- features/profiles/adapter_interface.lua
-- Profile adapter interface definition
-- All profile adapters (TRP3, MRP, XRP) must implement these methods

local addonName, TRP3FW = ...

-- Base adapter interface documentation
-- All adapters must implement the following methods:
--
-- IsAvailable() -> boolean
--   Returns true if the addon is loaded and functional
--
-- GetAddonName() -> string
--   Returns "TRP3", "MRP", or "XRP"
--
-- GetProfiles() -> array of Profile objects
--   Returns all available profiles (excluding current if applicable)
--   Profile object: { id, name, addon, isCurrent, data }
--
-- GetCurrentProfile() -> Profile object or nil
--   Returns the currently active profile
--
-- GetProfileByID(id) -> Profile object or nil
--   Returns a specific profile by ID/name
--
-- GetCharacteristics(id) -> table or nil
--   Returns characteristics data for the profile
--
-- GetAbout(id) -> table or nil
--   Returns about/description data for the profile
--
-- GetMisc(id) -> table or nil
--   Returns misc/preferences data for the profile
--
-- GetCharacter(id) -> table or nil
--   Returns character/status data for the profile
--
-- ValidateProfileID(id) -> boolean
--   Returns true if the profile ID exists
--
-- IsCurrentProfile(id) -> boolean
--   Returns true if the ID matches the currently active profile

-- Initialize adapter registry
TRP3FW.Adapters = TRP3FW.Adapters or {}

-- Shared throttle to avoid profile count log spam across adapters
TRP3FW.profileLogThrottle = TRP3FW.profileLogThrottle or { last = 0 }

function TRP3FW:ShouldLogProfileCount()
	local now = (GetTime and GetTime()) or os.time()
	local last = self.profileLogThrottle.last or 0
	if (now - last) >= 3 then
		self.profileLogThrottle.last = now
		return true
	end
	return false
end

TRP3FW:Debug("Profile adapter interface loaded", "hooks")
