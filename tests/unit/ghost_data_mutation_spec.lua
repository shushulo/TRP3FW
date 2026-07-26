-- tests/unit/ghost_data_mutation_spec.lua
-- Headless tests for hooks/trp3.lua's GetGhostDataForInformationType.
--
-- Bug fixed: the CHARACTERISTICS branch filled in two required defaults by assigning
-- straight onto the table it had just fetched:
--
--     if not ghostData.FN or ghostData.FN == "" then ghostData.FN = UnitName("player") end
--     if not ghostData.CH or ghostData.CH == "" then ghostData.CH = "ffffff" end
--
-- GetProfileCharacteristics does not copy. The TRP3 adapter returns
-- `profile.data.player.characteristics` itself (features/profiles/adapter_trp3.lua:125), a
-- live reference into TRP3_Profiles - so those assignments wrote into the user's real saved
-- ghost profile. The first ghost send using a profile with an empty first name or no name
-- colour permanently stamped the player's own character name and #ffffff onto it, visible in
-- TRP3's own profile editor and persisted to SavedVariables.
--
-- ValidateGhostTRP3Payload, called a few lines later, does copy before it sanitizes
-- (hooks/trp3.lua:174) - which is exactly why only these two assignments leaked, and why the
-- leak was easy to miss.
--
-- Fix: apply the defaults to a copy.

local T = require("tests.framework")
local H = require("tests.harness")

local CHARACTERISTICS, ABOUT, MISC, CHARACTER = 1, 2, 3, 4

local function freshFW(liveCharacteristics)
    local fw = H.newNamespace()
    fw.Prefs = {}

    _G.TRP3_API = {
        register = {
            registerInfoTypes = {
                CHARACTERISTICS = CHARACTERISTICS,
                ABOUT = ABOUT,
                MISC = MISC,
                CHARACTER = CHARACTER,
            }
        }
    }

    -- Stand in for the adapter handing back a LIVE reference, as the real one does.
    fw.liveCharacteristics = liveCharacteristics
    function fw:GetProfileCharacteristics() return fw.liveCharacteristics end
    function fw:GetProfileAbout() return { v = 1, TE = 1, T1 = { TX = "x" } } end
    function fw:GetProfileMisc() return { v = 1, PE = {}, ST = {} } end
    function fw:GetProfileCharacter() return { v = 1, RP = 2, XP = 1, CU = "" } end

    function fw:IsDefaultBlankProfileID() return false end
    function fw:GetBlankCharacteristicsData() return { FN = "Blank", CH = "ffffff", IC = "TEMP" } end
    function fw:GetBlankAboutData() return { v = 1, TE = 1, BK = 1, T1 = { TX = "" } } end
    function fw:GetBlankMiscData() return { v = 1, PE = {}, ST = {} } end
    function fw:GetBlankCharacterData() return { v = 1, RP = 2, XP = 1, CU = "" } end

    H.loadModule("hooks/trp3.lua", fw)
    return fw
end

T.describe("ghost characteristics: defaults must not touch the saved profile", function()
    T.it("BUG (fixed): an empty FN is not written back into the live profile", function()
        local live = { FN = "", CH = "ff0000", IC = "TEMP" }
        local fw = freshFW(live)

        local result = fw:GetGhostDataForInformationType(CHARACTERISTICS, "ghost-profile-1")

        T.eq(live.FN, "", "the user's saved ghost profile must be left exactly as it was")
        T.neq(result.FN, "", "but the outgoing payload still gets a usable name")
    end)

    T.it("BUG (fixed): a missing CH is not written back into the live profile", function()
        local live = { FN = "Ghosty", IC = "TEMP" }  -- no CH at all
        local fw = freshFW(live)

        local result = fw:GetGhostDataForInformationType(CHARACTERISTICS, "ghost-profile-1")

        T.is_nil(live.CH, "the saved profile must not gain a colour it never had")
        T.eq(result.CH, "ffffff", "the payload gets the white default")
    end)

    T.it("returns a table distinct from the live profile when defaults are applied", function()
        local live = { FN = "", CH = "", IC = "TEMP" }
        local fw = freshFW(live)

        local result = fw:GetGhostDataForInformationType(CHARACTERISTICS, "ghost-profile-1")

        T.neq(result, live, "must not hand back the live profile table itself")
        T.eq(live.FN, "", "and the original stays untouched")
        T.eq(live.CH, "", "in both fields")
    end)

    T.it("preserves the profile's own values when they are already present", function()
        local live = { FN = "Ghosty", CH = "ff0000", IC = "Spell_Fire" }
        local fw = freshFW(live)

        local result = fw:GetGhostDataForInformationType(CHARACTERISTICS, "ghost-profile-1")

        T.eq(result.FN, "Ghosty", "a real name is not overwritten")
        T.eq(result.CH, "ff0000", "a real colour is not overwritten")
        T.eq(live.FN, "Ghosty", "and the live profile is unchanged either way")
    end)

    T.it("carries the profile's other fields through to the payload", function()
        local live = { FN = "", CH = "ff0000", IC = "Spell_Fire", RA = "Human" }
        local fw = freshFW(live)

        local result = fw:GetGhostDataForInformationType(CHARACTERISTICS, "ghost-profile-1")

        T.eq(result.IC, "Spell_Fire", "the copy must not drop unrelated fields")
        T.eq(result.RA, "Human")
    end)

    T.it("falls back to blank data when the profile is missing", function()
        local fw = freshFW(nil)  -- adapter finds no profile

        local result = fw:GetGhostDataForInformationType(CHARACTERISTICS, "no-such-profile")

        T.not_nil(result, "a missing profile must still produce a sendable payload")
        T.eq(result.FN, "Blank")
    end)

    T.it("rejects an unknown informationType", function()
        local fw = freshFW({ FN = "Ghosty", CH = "ff0000" })
        T.is_nil(fw:GetGhostDataForInformationType(999, "ghost-profile-1"))
    end)
end)
