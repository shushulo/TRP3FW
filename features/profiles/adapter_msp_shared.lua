-- features/profiles/adapter_msp_shared.lua
-- Shared MSP -> TRP3-shape conversion for the flat-MSP adapters (MRP, XRP).
--
-- MRP and XRP both store profiles as flat MSP field tables and both convert them into the same
-- TRP3-like structure. Their four Get* bodies were near-identical copies differing only by:
--
--   * where the fields live -- MRP: profile.data       XRP: profile.data.fields
--   * the adapter name in the debug string
--   * comment wording and whitespace
--
-- Verified by diff that the actual field mappings were byte-identical in substance. That is
-- exactly the shape the section-6 bug had: two branches that should have been one, which
-- diverged because nothing forced them to agree. The FC/FR hardcode was fixed twice, once per
-- adapter, for the same reason.
--
-- The TRP3 adapter is deliberately NOT routed through here: it returns its native structures
-- straight from profile.data.player.* with no field mapping at all, so sharing this would mean
-- inventing a conversion it does not need.

local addonName, TRP3FW = ...

TRP3FW.MSPAdapterShared = {}
local Shared = TRP3FW.MSPAdapterShared

--- Build the four MSP getters for an adapter.
--- @param adapterName string  - "MRP" / "XRP", used only in debug output
--- @param getFields function  - (profile) -> flat MSP field table, or nil
--- @return table - { GetCharacteristics, GetAbout, GetMisc, GetCharacter }
---
--- Each returned function is a method: call as adapter:GetX(id).
function Shared.BuildGetters(adapterName, getFields)
    local getters = {}

    -- The preamble every getter shared: resolve the profile, reach its fields, and bail with a
    -- debug line naming the getter. Written once here rather than eight times.
    local function resolve(self, id, what)
        local profile = self:GetProfileByID(id)
        local fields = profile and getFields(profile)
        if not fields then
            TRP3FW:Debug(adapterName.." adapter: No profile data or fields for "..what, "hooks")
            return nil
        end
        return fields
    end

    function getters:GetCharacteristics(id)
        local f = resolve(self, id, "GetCharacteristics")
        if not f then return nil end

        return {
            v = 1,
            FN = f.NA or "",    -- Name
            RA = f.RA or "",    -- Race
            CL = f.RC or "",    -- Class (RC in MSP)
            IC = f.IC or "",    -- Icon
            TI = f.NT or "",    -- Title
            NH = f.NH or "",    -- House
            NI = f.NI or "",    -- Nickname
            AG = f.AG or "",    -- Age
            AE = f.AE or "",    -- Eye color
            AH = f.AH or "",    -- Height
            AW = f.AW or "",    -- Weight
            HB = f.HB or "",    -- Birthplace
            HH = f.HH or "",    -- Home/residence
            MI = {},            -- Misc traits (flat MSP has no equivalent structure)
            PS = {},            -- Personality traits (flat MSP has no equivalent structure)
        }
    end

    function getters:GetAbout(id)
        local f = resolve(self, id, "GetAbout")
        if not f then return nil end

        return {
            v = 1,
            TE = 1,             -- Template type (1 = simple text, closest to flat MSP)
            BK = 1,             -- Background
            MU = f.MU or "",    -- Music
            T1 = {
                TX = f.DE or "",  -- Description -> template 1 text
            },
            -- MSP also carries HI (history/long description), but TRP3 template 1 has only one
            -- text field, so DE is used alone.
        }
    end

    function getters:GetMisc(id)
        local f = resolve(self, id, "GetMisc")
        if not f then return nil end

        return {
            v = 1,
            PE = {},            -- Peek/glance slots (not represented in flat MSP)
            ST = {},            -- RP styles (not represented in flat MSP)
            CU = f.CU or "",    -- Currently
            CO = f.CO or "",    -- Currently OOC
        }
    end

    function getters:GetCharacter(id)
        local f = resolve(self, id, "GetCharacter")
        if not f then return nil end

        -- RP and XP were previously hardcoded to 1 in BOTH adapters, with the comment
        -- "MRP/XRP uses FC differently". They don't -- FC/FR are standard MSP fields with a
        -- defined mapping that TRP3 implements in both directions
        -- (totalRP3/modules/register/msp/register_msp.lua:437-443 and :450).
        return {
            v = 1,
            CU = f.CU or "",    -- Currently IC
            CO = f.CO or "",    -- Currently OOC
            -- FC == "1" is OOC -> RP = 2; anything else (including absent) -> RP = 1 (IC).
            RP = (f.FC == "1") and 2 or 1,
            -- FR == "4" is the "not looking for RP" end -> XP = 1; otherwise XP = 2.
            -- Note this reads INVERSE to intuition; it matches TRP3's own conversion.
            XP = (f.FR == "4") and 1 or 2,
        }
    end

    return getters
end

--- Copy the shared getters onto an adapter table.
--- @param adapter table
--- @param adapterName string
--- @param getFields function - (profile) -> flat MSP field table, or nil
function Shared.Apply(adapter, adapterName, getFields)
    for name, fn in pairs(Shared.BuildGetters(adapterName, getFields)) do
        adapter[name] = fn
    end
end

TRP3FW:Debug("MSP shared adapter helpers loaded", "hooks")
