-- tests/unit/msp_conversion_cache_spec.lua
-- Headless tests for the TRP3->MSP ghost-profile conversion cache
-- (hooks/msp_exchange.lua's GetProfileTRP3ToMSP).
--
-- Bug fixed: the cache wrote a `timestamp` on every entry and NEVER READ IT. Nothing
-- pruned the table, and there is no profile-edited event anywhere in the addon to
-- invalidate on, so a conversion cached once lived until /reload -- meaning an edit to
-- the ghost profile mid-session kept transmitting the PRE-EDIT version for the rest of
-- the session. It was also the one cache in the addon with no size cap, against
-- CLAUDE.md's stated rule. These tests pin the TTL now honouring the stored timestamp,
-- and the cap.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW(prefs)
    local fw = H.newNamespace()
    fw.Prefs = prefs or {}
    fw.VERSION = "test"

    function fw:CountTableEntries(tbl)
        local n = 0
        for _ in pairs(tbl or {}) do n = n + 1 end
        return n
    end

    -- The conversion body reads through the adapter layer; stub it so each call is
    -- observable and its output distinguishable between calls.
    fw.conversionCalls = 0
    fw.currentDescription = "original description"
    function fw:GetProfileCharacteristics()
        self.conversionCalls = self.conversionCalls + 1
        return { FN = "Kael", CH = "" }
    end
    -- TE == 1 is TRP3's single-block "about" template; the conversion reads T1.TX for DE.
    function fw:GetProfileAbout() return { TE = 1, T1 = { TX = self.currentDescription } } end
    function fw:RemoveTextTags(s) return s end
    function fw:GetProfileCharacter() return { RP = 1 } end

    fw.mspConversionCache = {}

    H.loadModule("hooks/msp_exchange.lua", fw)
    return fw
end

T.describe("mspConversionCache TTL", function()
    T.it("serves a cached conversion while it is within the TTL", function()
        mock.setClock(1000)
        local fw = freshFW({ mspConversionCacheDuration = 300 })

        fw:GetProfileTRP3ToMSP("prof1")
        T.eq(fw.conversionCalls, 1, "first call converts")

        mock.advance(100)  -- well within the 300s TTL
        fw:GetProfileTRP3ToMSP("prof1")
        T.eq(fw.conversionCalls, 1, "a fresh entry must be served from cache, not reconverted")
    end)

    T.it("BUG (fixed): a stale entry is reconverted rather than served forever", function()
        mock.setClock(1000)
        local fw = freshFW({ mspConversionCacheDuration = 300 })

        fw:GetProfileTRP3ToMSP("prof1")
        T.eq(fw.conversionCalls, 1, "first call converts")

        mock.advance(301)  -- past the TTL
        fw:GetProfileTRP3ToMSP("prof1")
        T.eq(fw.conversionCalls, 2, "a stale entry must be reconverted")
    end)

    T.it("BUG (fixed): a ghost-profile edit is picked up once the TTL lapses", function()
        -- This is the user-visible consequence: before the fix, editing the ghost profile
        -- kept sending the pre-edit version until /reload.
        mock.setClock(1000)
        local fw = freshFW({ mspConversionCacheDuration = 300 })

        local before = fw:GetProfileTRP3ToMSP("prof1")
        T.eq(before.DE, "original description", "sanity: first conversion carries the original text")

        fw.currentDescription = "edited description"

        mock.advance(10)
        local stillCached = fw:GetProfileTRP3ToMSP("prof1")
        T.eq(stillCached.DE, "original description", "within the TTL the cached version is still served")

        mock.advance(300)
        local after = fw:GetProfileTRP3ToMSP("prof1")
        T.eq(after.DE, "edited description", "past the TTL the edit must reach the wire")
    end)

    T.it("falls back to a 300s default when the pref is absent", function()
        mock.setClock(1000)
        local fw = freshFW({})  -- no mspConversionCacheDuration

        fw:GetProfileTRP3ToMSP("prof1")
        mock.advance(100)
        fw:GetProfileTRP3ToMSP("prof1")
        T.eq(fw.conversionCalls, 1, "within the default TTL, served from cache")

        mock.advance(250)  -- 350s total, past the 300s default
        fw:GetProfileTRP3ToMSP("prof1")
        T.eq(fw.conversionCalls, 2, "past the default TTL, reconverted")
    end)

    T.it("treats an entry with no timestamp as stale rather than trusting it forever", function()
        mock.setClock(1000)
        local fw = freshFW({ mspConversionCacheDuration = 300 })

        -- A hand-planted entry with no timestamp, as an older cache write would have left.
        fw.mspConversionCache["prof1"] = { mspFields = { DE = "ancient" } }

        local result = fw:GetProfileTRP3ToMSP("prof1")
        T.eq(fw.conversionCalls, 1, "a timestamp-less entry must not be served")
        T.eq(result.DE, "original description", "it is replaced by a real conversion")
    end)
end)

T.describe("mspConversionCache size cap", function()
    T.it("stays bounded rather than growing without limit", function()
        mock.setClock(1000)
        local fw = freshFW({ mspConversionCacheDuration = 300 })

        for i = 1, 120 do
            fw:GetProfileTRP3ToMSP("prof"..i)
        end

        local size = fw:CountTableEntries(fw.mspConversionCache)
        T.truthy(size <= 50, "cache must stay within its cap, got "..size)
        T.truthy(size > 0, "cache must still be caching something, got "..size)
    end)

    T.it("re-caching an existing profile does not trip the cap", function()
        mock.setClock(1000)
        local fw = freshFW({ mspConversionCacheDuration = 300 })

        for i = 1, 50 do
            fw:GetProfileTRP3ToMSP("prof"..i)
        end
        local sizeBefore = fw:CountTableEntries(fw.mspConversionCache)

        -- Refreshing a key already present is an update, not growth, so it must not
        -- trigger the wipe and discard 49 healthy entries.
        mock.advance(301)
        fw:GetProfileTRP3ToMSP("prof1")

        T.eq(fw:CountTableEntries(fw.mspConversionCache), sizeBefore,
            "refreshing an existing key must not clear the cache")
    end)
end)
