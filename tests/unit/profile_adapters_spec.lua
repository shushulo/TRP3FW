-- tests/unit/profile_adapters_spec.lua
-- Headless tests for the cross-addon profile adapters (TRP3 / MRP / XRP) and the
-- detection factory. These adapters normalize each RP addon's native profile
-- store into TRP3FW's common shape: { id, name, addon, isCurrent, data }, and the
-- MRP/XRP adapters additionally remap flat MSP fields into a TRP3-like structure.
--
-- Everything here is pure data-shaping over global tables (TRP3_API, mrpSaved,
-- xrpSaved, ...), which the spec sets up directly. Realistic field names/shapes
-- mirror the real addons in ../other_addons.

local T = require("tests.framework")
local H = require("tests.harness")

local TRP3FW = H.newNamespace()
TRP3FW.Prefs = {}

-- adapter_interface defines TRP3FW.Adapters + ShouldLogProfileCount (uses GetTime).
H.loadModule("features/profiles/adapter_interface.lua", TRP3FW)
H.loadModule("features/profiles/adapter_trp3.lua", TRP3FW)
H.loadModule("features/profiles/adapter_mrp.lua", TRP3FW)
H.loadModule("features/profiles/adapter_xrp.lua", TRP3FW)
H.loadModule("features/profiles/adapter_factory.lua", TRP3FW)

-- Helper to wipe all the addon globals between tests so availability is explicit.
local function clearAddonGlobals()
    _G.TRP3_API = nil
    _G.mrp = nil; _G.mrpSaved = nil
    _G.AddOn_XRP = nil; _G.xrpSaved = nil
    TRP3FW:ClearAdapterCache()
end

-- ===================== TRP3 adapter =====================

T.describe("TRP3Adapter", function()
    local A = TRP3FW.Adapters.TRP3

    local function installTRP3()
        _G.TRP3_API = {
            profile = {
                getPlayerCurrentProfileID = function() return "id-current" end,
                getPlayerCurrentProfile = function() return { profileName = "Active" } end,
                getProfiles = function()
                    return {
                        ["id-current"] = { profileName = "Active",
                            player = {
                                characteristics = { FN = "Hero" },
                                about = { TE = 1 },
                                misc = { CU = "busy" },
                                character = { RP = 1 },
                            } },
                        ["id-other"] = { profileName = "Alt" },
                        ["id-noname"] = {},  -- exercises the profileName-or-id fallback
                    }
                end,
            },
            register = {
                getProfileOrNil = function(id)
                    if id == "register-only" then return { profileName = "FromRegister" } end
                    return nil
                end,
            },
        }
    end

    T.it("reports unavailable without TRP3_API.profile", function()
        clearAddonGlobals()
        T.falsy(A:IsAvailable())
        T.eq(#A:GetProfiles(), 0, "GetProfiles returns empty when unavailable")
    end)

    T.it("normalizes every profile into the common shape", function()
        clearAddonGlobals(); installTRP3()
        local profiles = A:GetProfiles()
        T.eq(#profiles, 3)
        for _, p in ipairs(profiles) do
            T.eq(p.addon, "TRP3")
            T.not_nil(p.id); T.not_nil(p.name); T.not_nil(p.data)
        end
    end)

    T.it("falls back to the id when profileName is missing", function()
        clearAddonGlobals(); installTRP3()
        local p = A:GetProfileByID("id-noname")
        T.eq(p.name, "id-noname")
    end)

    T.it("marks the current profile with isCurrent", function()
        clearAddonGlobals(); installTRP3()
        T.truthy(A:GetProfileByID("id-current").isCurrent)
        T.falsy(A:GetProfileByID("id-other").isCurrent)
        T.truthy(A:IsCurrentProfile("id-current"))
    end)

    T.it("falls back to the register for other players' profiles", function()
        clearAddonGlobals(); installTRP3()
        local p = A:GetProfileByID("register-only")
        T.not_nil(p, "register fallback should resolve")
        T.eq(p.name, "FromRegister")
    end)

    T.it("digs nested player data for characteristics/about/misc/character", function()
        clearAddonGlobals(); installTRP3()
        T.eq(A:GetCharacteristics("id-current").FN, "Hero")
        T.eq(A:GetAbout("id-current").TE, 1)
        T.eq(A:GetMisc("id-current").CU, "busy")
        T.eq(A:GetCharacter("id-current").RP, 1)
        -- A profile lacking nested player data returns nil, not a crash.
        T.is_nil(A:GetCharacteristics("id-other"))
    end)

    T.it("returns nil for unknown ids and validates existence", function()
        clearAddonGlobals(); installTRP3()
        T.is_nil(A:GetProfileByID("does-not-exist"))
        T.falsy(A:ValidateProfileID("does-not-exist"))
        T.truthy(A:ValidateProfileID("id-current"))
    end)
end)

-- ===================== MRP adapter (MSP -> TRP3 mapping) =====================

T.describe("MRPAdapter", function()
    local A = TRP3FW.Adapters.MRP

    local function installMRP()
        _G.mrp = {}
        _G.mrpSaved = {
            SelectedProfile = "Default",
            Profiles = {
                Default = {
                    NA = "Aldric", RA = "Human", RC = "Mage", NT = "the Wise",
                    DE = "A tall mage.", CU = "Reading", CO = "afk", MU = "song",
                },
                Alt = { NA = "Shade" },
            },
        }
    end

    T.it("reports unavailable without mrpSaved.Profiles", function()
        clearAddonGlobals()
        T.falsy(A:IsAvailable())
    end)

    T.it("lists profiles with Default sorted first", function()
        clearAddonGlobals(); installMRP()
        local profiles = A:GetProfiles()
        T.eq(#profiles, 2)
        T.eq(profiles[1].name, "Default", "Default sorts ahead of others")
    end)

    T.it("maps MSP fields into TRP3-like characteristics", function()
        clearAddonGlobals(); installMRP()
        local c = A:GetCharacteristics("Default")
        T.eq(c.FN, "Aldric")   -- NA -> FN
        T.eq(c.RA, "Human")    -- RA -> RA
        T.eq(c.CL, "Mage")     -- RC -> CL
        T.eq(c.TI, "the Wise") -- NT -> TI
    end)

    T.it("defaults missing MSP fields to empty strings", function()
        clearAddonGlobals(); installMRP()
        local c = A:GetCharacteristics("Alt")  -- only NA set
        T.eq(c.FN, "Shade")
        T.eq(c.RA, "")  -- absent field -> "" not nil
    end)

    T.it("maps about/misc/character fields", function()
        clearAddonGlobals(); installMRP()
        T.eq(A:GetAbout("Default").T1.TX, "A tall mage.")  -- DE -> T1.TX
        T.eq(A:GetMisc("Default").CU, "Reading")           -- CU -> CU
        T.eq(A:GetCharacter("Default").CO, "afk")          -- CO -> CO
    end)

    T.it("tracks the selected profile as current", function()
        clearAddonGlobals(); installMRP()
        T.truthy(A:IsCurrentProfile("Default"))
        T.falsy(A:IsCurrentProfile("Alt"))
    end)
end)

-- ===================== XRP adapter (fields.* MSP mapping) =====================

T.describe("XRPAdapter", function()
    local A = TRP3FW.Adapters.XRP

    local function installXRP()
        _G.AddOn_XRP = {}  -- no GetProfileList -> exercises manual enumeration fallback
        _G.xrpSaved = {
            selected = "Main",
            profiles = {
                Main = { fields = { NA = "Kael", RA = "Elf", RC = "Hunter",
                    DE = "Wary ranger.", CU = "Hunting" } },
                Spare = { fields = { NA = "Other" } },
            },
        }
    end

    T.it("reports unavailable without the full xrpSaved triple", function()
        clearAddonGlobals()
        T.falsy(A:IsAvailable())
        _G.AddOn_XRP = {}; _G.xrpSaved = { profiles = {} }  -- missing `selected`
        T.falsy(A:IsAvailable())
    end)

    T.it("enumerates profiles when GetProfileList is absent", function()
        clearAddonGlobals(); installXRP()
        T.eq(#A:GetProfiles(), 2)
    end)

    T.it("reads MSP fields out of data.fields", function()
        clearAddonGlobals(); installXRP()
        local c = A:GetCharacteristics("Main")
        T.eq(c.FN, "Kael")    -- fields.NA -> FN
        T.eq(c.CL, "Hunter")  -- fields.RC -> CL
        T.eq(A:GetMisc("Main").CU, "Hunting")
    end)

    T.it("returns nil characteristics when fields are missing", function()
        clearAddonGlobals(); installXRP()
        _G.xrpSaved.profiles.NoFields = {}  -- profile present but no .fields
        T.is_nil(A:GetCharacteristics("NoFields"))
    end)

    T.it("honors current selection", function()
        clearAddonGlobals(); installXRP()
        T.truthy(A:GetProfileByID("Main").isCurrent)
        T.falsy(A:GetProfileByID("Spare").isCurrent)
    end)
end)

-- ===================== Factory detection & priority =====================

T.describe("Profile adapter factory", function()
    local function installTRP3()
        _G.TRP3_API = { profile = {
            getPlayerCurrentProfileID = function() return "x" end,
            getPlayerCurrentProfile = function() return {} end,
            getProfiles = function() return {} end,
        }, register = {} }
    end
    local function installMRP()
        _G.mrp = {}; _G.mrpSaved = { SelectedProfile = "Default", Profiles = { Default = {} } }
    end

    T.it("returns nil when no RP addon is present", function()
        clearAddonGlobals()
        T.is_nil(TRP3FW:GetProfileAdapter())
        T.is_nil(TRP3FW:GetDetectedAddonName())
    end)

    T.it("prefers TRP3 over MRP when both are present", function()
        clearAddonGlobals(); installTRP3(); installMRP()
        T.eq(TRP3FW:GetProfileAdapter():GetAddonName(), "TRP3")
        T.eq(TRP3FW:GetDetectedAddonName(), "TRP3")
    end)

    T.it("falls through to MRP when TRP3 is absent", function()
        clearAddonGlobals(); installMRP()
        T.eq(TRP3FW:GetProfileAdapter():GetAddonName(), "MRP")
    end)

    T.it("caches the detected adapter until cleared", function()
        clearAddonGlobals(); installMRP()
        T.eq(TRP3FW:GetProfileAdapter():GetAddonName(), "MRP")
        -- Add TRP3 *after* detection: cache should still report MRP.
        installTRP3()
        T.eq(TRP3FW:GetProfileAdapter():GetAddonName(), "MRP", "cached result wins")
        -- After clearing, re-detection picks up the higher-priority TRP3.
        TRP3FW:ClearAdapterCache()
        T.eq(TRP3FW:GetProfileAdapter():GetAddonName(), "TRP3")
    end)

    T.it("GetAllProfiles returns empty (not nil) with no addon", function()
        clearAddonGlobals()
        local r = TRP3FW:GetAllProfiles()
        T.not_nil(r)
        T.eq(#r, 0)
    end)
end)

-- Leave globals clean for any later spec.
clearAddonGlobals()

return T
