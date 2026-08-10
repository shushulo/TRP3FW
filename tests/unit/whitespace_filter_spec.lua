-- tests/unit/whitespace_filter_spec.lua
-- Headless tests for the profile whitespace filter (hooks/whitespace.lua + CollapseWhitespace).
--
-- Origin: a profile in the wild set MSP NA to
--   "Gravecaller\n" .. (" "):rep(16) .. "Sombria"
-- (verified by byte dump: 35 bytes, a single \n at offset 12 followed by 16 spaces). The
-- newline forces the name onto a second row and the space run pushes the surname right,
-- inflating the tooltip. Both collapse in one pass because Lua's %s matches \n and space.
--
-- The carve-outs matter as much as the collapse: PE at the MSP layer is TRP3's raw
-- serialized wire format whose newlines are structural, and DE/HI are rich-text fields
-- whose paragraph breaks are content. Collapsing either would repeat the icon filter's
-- PE regression (see icon_filter_pe_spec.lua).

local T = require("tests.framework")
local H = require("tests.harness")

-- The exact field value observed in the wild, byte-for-byte.
local SOMBRIA_NA = "Gravecaller\n" .. string.rep(" ", 16) .. "Sombria"

local function freshWhitespaceFilter()
    local TRP3FW = H.newNamespace()
    TRP3FW.Prefs.filterNameWhitespace = true
    TRP3FW.ServiceContainer = { Get = function() return nil end }
    TRP3FW.COLOR = { info = "ffffff", warn = "ffff00", error = "ff0000", white = "ffffff" }

    H.loadModule("core/utils.lua", TRP3FW)
    H.loadModule("hooks/whitespace.lua", TRP3FW)

    return TRP3FW
end

T.describe("CollapseWhitespace transform", function()
    T.it("collapses the observed Sombria padding to a single space", function()
        local TRP3FW = freshWhitespaceFilter()
        T.eq(#SOMBRIA_NA, 35, "fixture must match the observed byte count")
        T.eq(TRP3FW:CollapseWhitespace(SOMBRIA_NA), "Gravecaller Sombria")
    end)

    T.it("collapses a bare newline with no adjacent spaces", function()
        local TRP3FW = freshWhitespaceFilter()
        T.eq(TRP3FW:CollapseWhitespace("First\nLast"), "First Last")
    end)

    T.it("collapses tabs and mixed whitespace runs", function()
        local TRP3FW = freshWhitespaceFilter()
        T.eq(TRP3FW:CollapseWhitespace("A\t \n\t B"), "A B")
    end)

    T.it("trims leading and trailing padding", function()
        local TRP3FW = freshWhitespaceFilter()
        T.eq(TRP3FW:CollapseWhitespace("   Padded   "), "Padded")
        T.eq(TRP3FW:CollapseWhitespace("\n\nName\n\n"), "Name")
    end)

    T.it("turns a bare control character into a separator rather than fusing words", function()
        -- %s does not match \1, so it is stripped explicitly first. Without that step this
        -- would come back as "ab".
        local TRP3FW = freshWhitespaceFilter()
        T.eq(TRP3FW:CollapseWhitespace("a\1b"), "a b")
    end)

    T.it("leaves legitimate single-spaced names untouched", function()
        -- Epsilon allows spaces in names (see SecurityService CleanPlayerName); a real
        -- two-word name must survive the filter unchanged.
        local TRP3FW = freshWhitespaceFilter()
        T.eq(TRP3FW:CollapseWhitespace("Madam Sweet"), "Madam Sweet")
        T.eq(TRP3FW:CollapseWhitespace("Amellia Sutton"), "Amellia Sutton")
    end)

    T.it("passes through non-string and empty input", function()
        local TRP3FW = freshWhitespaceFilter()
        T.eq(TRP3FW:CollapseWhitespace(nil), nil)
        T.eq(TRP3FW:CollapseWhitespace(42), 42)
        T.eq(TRP3FW:CollapseWhitespace(""), "")
    end)
end)

T.describe("Whitespace filter MSP hook", function()
    local function runMSPHook(fields)
        local TRP3FW = freshWhitespaceFilter()
        local senderID = "Sombria-Apertus"

        _G.msp = {
            callback = { received = {} },
            char = { [senderID] = { field = fields } }
        }

        TRP3FW:InstallWhitespaceHooks()
        T.eq(#msp.callback.received, 1)
        msp.callback.received[1](senderID)

        return msp.char[senderID].field
    end

    T.it("collapses the padded name in NA", function()
        local field = runMSPHook({ NA = SOMBRIA_NA })
        T.eq(field.NA, "Gravecaller Sombria")
    end)

    T.it("collapses titles, race, class, nickname, house and pronouns", function()
        local field = runMSPHook({
            NT = "The\n   Dreaded",
            RA = "Sin'dorei\n\n\n",
            RC = "Blood\t\tKnight",
            NI = "Grave\n   caller",
            NH = "House\n  Nightfall",
            PN = "she\n\n\n\n\nher",
        })

        T.eq(field.NT, "The Dreaded")
        T.eq(field.RA, "Sin'dorei")
        T.eq(field.RC, "Blood Knight")
        T.eq(field.NI, "Grave caller")
        T.eq(field.NH, "House Nightfall")
        T.eq(field.PN, "she her")
    end)

    T.it("leaves PE untouched - its newlines are structural at this layer", function()
        -- Same carve-out and same reasoning as icon_filter_pe_spec.lua: collapsing here
        -- would fuse the icon tag, title and text into one line and break parsePeekString.
        local rawPE = "|TInterface\\Icons\\inv_misc_book_09:32:32|t\n#My Title\n\nSome flavor text"
        local field = runMSPHook({ NA = "Testchar", PE = rawPE })
        T.eq(field.PE, rawPE, "PE must pass through the MSP whitespace filter untouched")
    end)

    T.it("leaves DE and HI untouched - paragraph breaks are content", function()
        local prose = "First paragraph.\n\nSecond paragraph."
        local field = runMSPHook({ NA = "Testchar", DE = prose, HI = prose })
        T.eq(field.DE, prose)
        T.eq(field.HI, prose)
    end)

    T.it("leaves CU and CO untouched - multi-line status is normal", function()
        local status = "Standing by.\nWaiting for the signal."
        local field = runMSPHook({ NA = "Testchar", CU = status, CO = status })
        T.eq(field.CU, status)
        T.eq(field.CO, status)
    end)

    T.it("does not install a second callback on re-run", function()
        -- Guards against /trp3fw reloadhooks nesting wrappers, as icon.lua does.
        local TRP3FW = freshWhitespaceFilter()
        _G.msp = {
            callback = { received = {} },
            char = { ["X-Realm"] = { field = { NA = "X" } } }
        }

        TRP3FW:InstallWhitespaceHooks()
        TRP3FW:InstallWhitespaceHooks()

        T.eq(#msp.callback.received, 1, "re-running the installer must not add a second hook")
    end)

    T.it("installs nothing when the pref is off", function()
        local TRP3FW = H.newNamespace()
        TRP3FW.Prefs.filterNameWhitespace = false
        TRP3FW.ServiceContainer = { Get = function() return nil end }
        TRP3FW.COLOR = { info = "ffffff", warn = "ffff00", error = "ff0000", white = "ffffff" }
        H.loadModule("core/utils.lua", TRP3FW)
        H.loadModule("hooks/whitespace.lua", TRP3FW)

        _G.msp = { callback = { received = {} }, char = {} }
        TRP3FW:InstallWhitespaceHooks()

        T.eq(#msp.callback.received, 0)
    end)
end)

T.describe("Whitespace filter TRP3 sanitizer hooks", function()
    local function freshWithTRP3(sanitizers)
        local TRP3FW = freshWhitespaceFilter()
        _G.msp = nil
        _G.TRP3_API = {
            register = { ui = sanitizers },
        }
        TRP3FW:InstallWhitespaceHooks()
        return TRP3FW
    end

    T.it("collapses names, titles, class and race in characteristics", function()
        freshWithTRP3({ sanitizeCharacteristics = function() return false end })

        local structure = {
            FN = "Grave\ncaller",
            LN = "Som\n    bria",
            FT = "The\n\nDreaded One",
            TI = "Lady\t\tof Ash",
            CL = "Blood\nKnight",
            RA = "Sin'dorei   ",
        }

        local modified = TRP3_API.register.ui.sanitizeCharacteristics(structure)

        T.eq(structure.FN, "Grave caller")
        T.eq(structure.LN, "Som bria")
        T.eq(structure.FT, "The Dreaded One")
        T.eq(structure.TI, "Lady of Ash")
        T.eq(structure.CL, "Blood Knight")
        T.eq(structure.RA, "Sin'dorei")
        T.eq(modified, true, "sanitizer must report that it changed the structure")
    end)

    T.it("collapses nickname and pronoun misc traits (MI)", function()
        -- TRP3 carries Nickname/Pronouns as MI entries, not flat fields - they only become
        -- NI/PN on the way out to MSP (hooks/msp_exchange.lua).
        freshWithTRP3({ sanitizeCharacteristics = function() return false end })

        local structure = {
            MI = {
                { NA = "Pronouns", VA = "she\n\n\nher" },
                { NA = "Nick\nname", VA = "Grave\n   caller" },
            },
        }

        TRP3_API.register.ui.sanitizeCharacteristics(structure)

        T.eq(structure.MI[1].VA, "she her")
        T.eq(structure.MI[2].NA, "Nick name")
        T.eq(structure.MI[2].VA, "Grave caller")
    end)

    T.it("reports false when nothing needed collapsing", function()
        freshWithTRP3({ sanitizeCharacteristics = function() return false end })
        local structure = { FN = "Gravecaller", LN = "Sombria" }
        T.eq(TRP3_API.register.ui.sanitizeCharacteristics(structure), false)
    end)

    T.it("preserves the original sanitizer's return value", function()
        freshWithTRP3({ sanitizeCharacteristics = function() return true end })
        local structure = { FN = "Gravecaller" }
        T.eq(TRP3_API.register.ui.sanitizeCharacteristics(structure), true)
    end)

    T.it("collapses glance titles but not glance text in sanitizeMisc", function()
        -- By this hook PE is parsed into per-slot fields, so TI is safe to collapse. TX is
        -- free text where deliberate line breaks are legitimate.
        freshWithTRP3({ sanitizeMisc = function() return false end })

        local structure = {
            PE = {
                ["1"] = { TI = "My\n    Glance", TX = "Line one.\nLine two." },
            },
        }

        local modified = TRP3_API.register.ui.sanitizeMisc(structure)

        T.eq(structure.PE["1"].TI, "My Glance")
        T.eq(structure.PE["1"].TX, "Line one.\nLine two.", "glance body must keep its breaks")
        T.eq(modified, true)
    end)
end)
