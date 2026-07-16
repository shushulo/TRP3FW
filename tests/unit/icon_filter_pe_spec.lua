-- tests/unit/icon_filter_pe_spec.lua
-- Headless tests for a regression in the MSP icon filter (hooks/icon.lua).
--
-- Bug: the field list stripped by StripAllIcons was widened to include PE (glance/peek
-- slots), but at the point this hook runs, PE is still TRP3's raw serialized wire format:
--   "|TInterface\Icons\<name>:32:32|t\n#Title\n\nText"
-- The |T..|t tag here IS the icon selection, not decoration - it's the only thing TRP3's
-- own parsePeekString() (register_msp.lua) matches against to read a slot's icon. Once
-- StripAllIcons removes the tag (and the trailing newline that separates it from the
-- title/text), TRP3 can no longer parse the icon or title/text out of the string, so every
-- glance received from another player showed up blank/default - only the local player's
-- own profile (built directly by TRP3, never passing through this filter) looked right.
--
-- Fix: PE was removed from the MSP-level fieldsToStrip list in hooks/icon.lua. This spec
-- locks that in place and verifies the round trip survives the filter.

local T = require("tests.framework")
local H = require("tests.harness")

-- Mirrors register_msp.lua's parsePeekString close enough to prove the round trip:
-- extracts icon/title/text from a serialized PE slot string.
local function parsePeekString(str)
    local icon = str:match("%f[^\n%z]|TInterface\\Icons\\([^:|]+)[^|]*|t%f[\n%z]")
    local title = str:match("%f[^\n%z]#+%s*(.-)%s*%f[\n%z]")
    local text = str:match("%f[^\n%z]%s*([^|#].-)%s*$")
    return { IC = icon, TI = title, TX = text }
end

local function freshIconFilter()
    local TRP3FW = H.newNamespace()
    TRP3FW.Prefs.filterIcons = true
    TRP3FW.ServiceContainer = { Get = function() return nil end }
    TRP3FW.COLOR = { info = "ffffff", warn = "ffff00", error = "ff0000", white = "ffffff" }

    H.loadModule("core/utils.lua", TRP3FW)
    H.loadModule("hooks/icon.lua", TRP3FW)

    return TRP3FW
end

T.describe("Icon filter MSP hook does not corrupt the PE (glance) field", function()
    T.it("leaves PE's |T..|t icon tag and structure intact", function()
        local TRP3FW = freshIconFilter()

        local senderID = "Testchar-Realm"
        local rawPE = "|TInterface\\Icons\\inv_misc_book_09:32:32|t\n#My Title\n\nSome flavor text"

        _G.msp = {
            callback = { received = {} },
            char = {
                [senderID] = {
                    field = {
                        NA = "Testchar",
                        PE = rawPE,
                    }
                }
            }
        }

        TRP3FW:InstallIconHooks()
        T.eq(#msp.callback.received, 1)

        msp.callback.received[1](senderID)

        local resultPE = msp.char[senderID].field.PE
        T.eq(resultPE, rawPE, "PE must pass through the MSP icon filter untouched")

        local parsed = parsePeekString(resultPE)
        T.eq(parsed.IC, "inv_misc_book_09", "icon must still be extractable after the filter runs")
        T.eq(parsed.TI, "My Title", "title must still be extractable after the filter runs")
        T.eq(parsed.TX, "Some flavor text", "text must still be extractable after the filter runs")
    end)

    T.it("still strips icon tags from ordinary free-text fields like NA/CU", function()
        local TRP3FW = freshIconFilter()

        local senderID = "Testchar2-Realm"
        _G.msp = {
            callback = { received = {} },
            char = {
                [senderID] = {
                    field = {
                        NA = "|TInterface\\Icons\\inv_misc_book_09:16:16|t Evil Name",
                        CU = "|TInterface\\Icons\\inv_misc_book_09:16:16|t Doing something",
                    }
                }
            }
        }

        TRP3FW:InstallIconHooks()
        msp.callback.received[1](senderID)

        T.eq(msp.char[senderID].field.NA, "Evil Name")
        T.eq(msp.char[senderID].field.CU, "Doing something")
    end)
end)

return T
