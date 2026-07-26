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

-- The method set above, as DATA rather than prose. Previously this file documented 11 required
-- methods and then defined none of them: there was no base table to inherit from and nothing
-- verified an adapter implemented the set (contrast core/Service.lua and core/Stage.lua, which
-- are real base classes). A missing method therefore surfaced as "attempt to call a nil value"
-- at ghost-send time -- i.e. mid-send, on the path that decides what leaves your client.
TRP3FW.ADAPTER_REQUIRED_METHODS = {
	"IsAvailable",
	"GetAddonName",
	"GetProfiles",
	"GetCurrentProfile",
	"GetProfileByID",
	"GetCharacteristics",
	"GetAbout",
	"GetMisc",
	"GetCharacter",
	"ValidateProfileID",
	"IsCurrentProfile",
}

-- Verify an adapter implements the full interface.
-- @return boolean ok, table missing - list of absent method names
function TRP3FW:ValidateAdapter(adapter)
	local missing = {}
	if type(adapter) ~= "table" then
		return false, self.ADAPTER_REQUIRED_METHODS
	end
	for _, method in ipairs(self.ADAPTER_REQUIRED_METHODS) do
		if type(adapter[method]) ~= "function" then
			table.insert(missing, method)
		end
	end
	return #missing == 0, missing
end

-- Check every registered adapter and report gaps at STARTUP rather than at ghost-send time.
-- Deliberately reports instead of erroring: a partially-implemented third adapter should not
-- prevent the addon from loading with the two that are fine.
function TRP3FW:ValidateRegisteredAdapters()
	local allOk = true
	for name, adapter in pairs(self.Adapters or {}) do
		local ok, missing = self:ValidateAdapter(adapter)
		if not ok then
			allOk = false
			self:Debug("[Adapter] "..tostring(name).." is missing required method(s): "
				..table.concat(missing, ", "), "hooks")
		end
	end
	return allOk
end

-- Initialize adapter registry
TRP3FW.Adapters = TRP3FW.Adapters or {}

-- Per-adapter throttle to avoid profile count log spam.
--
-- This was a single shared `last` timestamp, so whichever adapter called GetProfiles() first
-- suppressed the others' count logs for the next 3s -- i.e. with more than one RP addon
-- installed, the logs you most needed to compare were the ones being swallowed. Keyed per
-- adapter now, so each throttles independently.
TRP3FW.profileLogThrottle = TRP3FW.profileLogThrottle or {}

-- @param adapterKey string|nil - adapter identity ("TRP3"/"MRP"/"XRP"); falls back to a
--        shared bucket if a caller omits it, preserving the old behaviour for that caller.
function TRP3FW:ShouldLogProfileCount(adapterKey)
	-- Use the addon's standard clock rather than raw GetTime(), so this matches every other
	-- timing path (and keeps the os.time() 1s-resolution fallback out of the hot path).
	local now = self:GetCurrentTime()
	local key = adapterKey or "_shared"
	local last = self.profileLogThrottle[key] or 0
	if (now - last) >= 3 then
		self.profileLogThrottle[key] = now
		return true
	end
	return false
end

TRP3FW:Debug("Profile adapter interface loaded", "hooks")
