-- tests/unit/direct_msp_xrp_spec.lua
-- Headless tests for GetProfileDirectMSP (hooks/msp_exchange.lua), the path that turns an
-- MRP or XRP alternate profile into an outgoing MSP field table for ghost mode.
--
-- The XRP branch previously tested `xrp.profiles[profileID]` - a legacy global that does not
-- exist in current XRP (the modern namespace is AddOn_XRP / xrpSaved, and MSP data lives in
-- xrpSaved.profiles[name].fields). The condition was therefore never true and every XRP ghost
-- send fell through to the "profile not found" nil return. These tests pin the corrected
-- reads, including XRP's parent-inheritance chain: a child profile stores only its overrides,
-- so copying raw .fields alone would ghost a mostly-empty profile.

local T = require("tests.framework")
local H = require("tests.harness")

local TRP3FW = H.newNamespace()
TRP3FW.Prefs = {}

-- CountTableEntries lives in utils and is used by the debug logging in this path.
function TRP3FW:CountTableEntries(tbl)
    local n = 0
    for _ in pairs(tbl or {}) do n = n + 1 end
    return n
end

H.loadModule("hooks/msp_exchange.lua", TRP3FW)

local function clearAddonGlobals()
    _G.mrp = nil; _G.mrpSaved = nil
    _G.AddOn_XRP = nil; _G.xrpSaved = nil
    _G.xrp = nil
end

-- ===================== XRP =====================

T.describe("GetProfileDirectMSP (XRP)", function()
    local function installXRP()
        _G.AddOn_XRP = {}
        _G.xrpSaved = {
            selected = "Main",
            profiles = {
                Main = {
                    fields = { NA = "Kael", RA = "Elf", DE = "Wary ranger." },
                    inherits = {},
                },
            },
        }
    end

    T.it("reads MSP data out of xrpSaved.profiles[id].fields", function()
        clearAddonGlobals(); installXRP()
        local f = TRP3FW:GetProfileDirectMSP("Main")
        T.not_nil(f, "XRP profile should resolve (regression: legacy xrp.profiles global)")
        T.eq(f.NA, "Kael")
        T.eq(f.RA, "Elf")
        T.eq(f.DE, "Wary ranger.")
    end)

    T.it("does not copy XRP's container keys into the MSP payload", function()
        clearAddonGlobals(); installXRP()
        local f = TRP3FW:GetProfileDirectMSP("Main")
        -- Only `fields` contents are MSP; `inherits`/`parent` are XRP bookkeeping.
        T.is_nil(f.fields, "the fields table itself must not be copied as an MSP field")
        T.is_nil(f.inherits)
        T.is_nil(f.parent)
    end)

    T.it("stamps the required protocol and game fields", function()
        clearAddonGlobals(); installXRP()
        local f = TRP3FW:GetProfileDirectMSP("Main")
        T.eq(f.VP, "3")
        T.eq(f.VA, "TRP3FW/test")
        T.eq(f.GC, "WARRIOR")
        T.eq(f.GF, "Alliance")
    end)

    T.it("inherits parent fields the child does not override", function()
        clearAddonGlobals(); installXRP()
        _G.xrpSaved.profiles.Base = {
            fields = { NA = "BaseName", RA = "Human", AG = "40" },
            inherits = {},
        }
        _G.xrpSaved.profiles.Child = {
            fields = { NA = "ChildName" },  -- overrides NA only
            inherits = {},
            parent = "Base",
        }
        local f = TRP3FW:GetProfileDirectMSP("Child")
        T.eq(f.NA, "ChildName", "child's own field wins")
        T.eq(f.RA, "Human", "unset field comes from the parent")
        T.eq(f.AG, "40")
    end)

    T.it("honors an explicit inherits=false opt-out", function()
        clearAddonGlobals(); installXRP()
        _G.xrpSaved.profiles.Base = { fields = { RA = "Human" }, inherits = {} }
        _G.xrpSaved.profiles.Child = {
            fields = { NA = "ChildName" },
            inherits = { RA = false },  -- deliberately blank, do not inherit
            parent = "Base",
        }
        local f = TRP3FW:GetProfileDirectMSP("Child")
        T.eq(f.NA, "ChildName")
        T.is_nil(f.RA, "a field marked inherits=false must stay unset")
    end)

    T.it("terminates on a cyclic parent chain", function()
        clearAddonGlobals(); installXRP()
        _G.xrpSaved.profiles.A = { fields = { NA = "A" }, inherits = {}, parent = "B" }
        _G.xrpSaved.profiles.B = { fields = { RA = "Elf" }, inherits = {}, parent = "A" }
        local f = TRP3FW:GetProfileDirectMSP("A")
        T.not_nil(f, "a parent cycle must not hang or error")
        T.eq(f.NA, "A")
        T.eq(f.RA, "Elf")
    end)

    T.it("tolerates a profile with no fields table", function()
        clearAddonGlobals(); installXRP()
        _G.xrpSaved.profiles.Empty = {}
        local f = TRP3FW:GetProfileDirectMSP("Empty")
        T.not_nil(f, "an empty profile still yields the required protocol fields")
        T.eq(f.VP, "3")
    end)

    T.it("returns nil for an unknown profile id", function()
        clearAddonGlobals(); installXRP()
        T.is_nil(TRP3FW:GetProfileDirectMSP("does-not-exist"))
    end)
end)

-- ===================== MRP (unchanged path, pinned alongside) =====================

T.describe("GetProfileDirectMSP (MRP)", function()
    local function installMRP()
        _G.mrp = {}
        _G.mrpSaved = {
            SelectedProfile = "Default",
            Profiles = { Default = { NA = "Aldric", RA = "Human", CU = "Reading" } },
        }
    end

    T.it("copies MRP's flat MSP fields directly", function()
        clearAddonGlobals(); installMRP()
        local f = TRP3FW:GetProfileDirectMSP("Default")
        T.not_nil(f)
        T.eq(f.NA, "Aldric")
        T.eq(f.CU, "Reading")
        T.eq(f.VP, "3")
    end)

    T.it("returns nil for an unknown MRP profile", function()
        clearAddonGlobals(); installMRP()
        T.is_nil(TRP3FW:GetProfileDirectMSP("Nope"))
    end)
end)

clearAddonGlobals()

return T
