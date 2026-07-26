-- tests/unit/profile_isolation_spec.lua
-- Headless tests for core/init.lua's settings-profile handling (MigrateSettings /
-- LoadProfile).
--
-- The case that motivated these: LoadProfile backfills any default key the active
-- profile is missing. Assigning table-valued defaults directly shared ONE table
-- between defaultSettings and every profile that backfilled it, so per-phase SPVP
-- overrides and ghost profile overrides bled across profiles -- and into every
-- profile later created from defaultSettings. Profiles saved before those settings
-- existed all lack the keys, so upgrading users hit it on the first profile switch.

local T = require("tests.framework")
local H = require("tests.harness")

-- init.lua touches a few globals at load / in these code paths that mock_wow
-- does not provide.
_G.CreateFrame = _G.CreateFrame or function()
    return setmetatable({}, { __index = function() return function() end end })
end
_G.GetRealmName = _G.GetRealmName or function() return "TestRealm" end
_G.CopyTable = _G.CopyTable or function(t)
    local function deep(v)
        if type(v) ~= "table" then return v end
        local c = {}
        for k, sub in pairs(v) do c[k] = deep(sub) end
        return c
    end
    return deep(t)
end

local TRP3FW = H.newNamespace()
H.loadModule("core/init.lua", TRP3FW)

-- Build a fresh DB with the given profile tables.
-- Specs share _G and several of them restub UnitName for targeting tests, so
-- re-assert the identity globals GetCharacterKey needs on every setup rather than
-- relying on load-order.
local function withProfiles(profiles)
    _G.UnitName = function() return "TestPlayer" end
    _G.GetRealmName = function() return "TestRealm" end

    _G.TRP3FW_DB = {
        profiles = profiles,
        profileKeys = {},
        global = { version = "test" },
    }
    return _G.TRP3FW_DB
end

T.describe("LoadProfile default backfill", function()
    T.it("fills in missing scalar defaults", function()
        withProfiles({ Default = {} })
        TRP3FW:LoadProfile("Default")
        T.eq(TRP3FW.Prefs.suppressionTime, TRP3FW.defaultSettings.suppressionTime)
        T.eq(TRP3FW.Prefs.phaseCheckMode, TRP3FW.defaultSettings.phaseCheckMode)
    end)

    T.it("does not overwrite values the profile already sets", function()
        withProfiles({ Default = { phaseCheckMode = "block", suppressionTime = 42 } })
        TRP3FW:LoadProfile("Default")
        T.eq(TRP3FW.Prefs.phaseCheckMode, "block")
        T.eq(TRP3FW.Prefs.suppressionTime, 42)
    end)

    T.it("falls back to Default for an unknown profile name", function()
        withProfiles({ Default = { suppressionTime = 7 } })
        TRP3FW:LoadProfile("NoSuchProfile")
        T.eq(TRP3FW.Prefs.suppressionTime, 7)
    end)

    T.it("records the active profile against the character key", function()
        local db = withProfiles({ Default = {}, Alt = {} })
        TRP3FW:LoadProfile("Alt")
        local charKey = TRP3FW:GetCharacterKey()
        T.eq(db.profileKeys[charKey], "Alt")
    end)
end)

T.describe("LoadProfile table-default isolation", function()
    -- The core regression. Before the fix all three tables below were the same object.
    T.it("does not alias a table default into the profile", function()
        withProfiles({ Default = {} })
        TRP3FW:LoadProfile("Default")

        T.neq(TRP3FW.Prefs.spvpPerPhaseOverrides, TRP3FW.defaultSettings.spvpPerPhaseOverrides,
            "profile gets its own spvpPerPhaseOverrides table")
        T.neq(TRP3FW.Prefs.ghostProfileOverrides, TRP3FW.defaultSettings.ghostProfileOverrides,
            "profile gets its own ghostProfileOverrides table")
    end)

    T.it("keeps two profiles' table settings independent", function()
        withProfiles({ Default = {}, Alt = {} })

        TRP3FW:LoadProfile("Default")
        TRP3FW.Prefs.spvpPerPhaseOverrides[169] = false
        TRP3FW.Prefs.ghostProfileOverrides[1] = { match = "169", profileName = "Blank" }

        TRP3FW:LoadProfile("Alt")
        T.is_nil(TRP3FW.Prefs.spvpPerPhaseOverrides[169],
            "an override set on Default must not appear on Alt")
        T.is_nil(TRP3FW.Prefs.ghostProfileOverrides[1],
            "a ghost override set on Default must not appear on Alt")

        -- ...and going back, Default still has its own.
        TRP3FW:LoadProfile("Default")
        T.eq(TRP3FW.Prefs.spvpPerPhaseOverrides[169], false)
        T.eq(TRP3FW.Prefs.ghostProfileOverrides[1].match, "169")
    end)

    T.it("does not let a profile mutate defaultSettings", function()
        withProfiles({ Default = {} })
        TRP3FW:LoadProfile("Default")
        TRP3FW.Prefs.spvpPerPhaseOverrides[42] = false

        T.is_nil(TRP3FW.defaultSettings.spvpPerPhaseOverrides[42],
            "defaultSettings stays pristine so new profiles are not born polluted")
    end)
end)

T.describe("MigrateSettings", function()
    T.it("creates a Default profile when none exist", function()
        withProfiles({})
        _G.TRP3FW_DB = nil
        _G.TRP3FW_Settings = nil
        TRP3FW:MigrateSettings()
        T.not_nil(TRP3FW_DB.profiles["Default"])
        T.eq(TRP3FW_DB.profiles["Default"].suppressionTime, TRP3FW.defaultSettings.suppressionTime)
    end)

    T.it("migrates legacy flat settings into Default and clears the legacy table", function()
        withProfiles({})
        _G.TRP3FW_DB = nil
        _G.TRP3FW_Settings = { suppressionTime = 123, phaseCheckMode = "ghost" }

        TRP3FW:MigrateSettings()
        T.eq(TRP3FW_DB.profiles["Default"].suppressionTime, 123)
        T.eq(TRP3FW_DB.profiles["Default"].phaseCheckMode, "ghost")
        T.is_nil(next(TRP3FW_Settings), "legacy container is wiped after migration")
    end)

    T.it("leaves an already-migrated DB alone", function()
        withProfiles({ Default = { suppressionTime = 999 } })
        _G.TRP3FW_Settings = nil
        TRP3FW:MigrateSettings()
        T.eq(TRP3FW_DB.profiles["Default"].suppressionTime, 999)
    end)
end)

return T
