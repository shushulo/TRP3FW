-- tests/unit/fontsize_wrapper_spec.lua
-- Headless tests for hooks/fontsize.lua's TRP3 structure-tag handling.
--
-- Bug fixed: FONT_WRAPPER_PATTERN was written with regex syntax that Lua patterns do not
-- have - alternation ("|") and an optional group ("?"):
--
--     "^%s*{%s*([Hh][123]|[Pp])([:cCrR])?%s*}"
--
-- In a Lua pattern "|" is a literal pipe and a "?" following ")" is a literal question
-- mark, so the expression matched exactly one input in the universe: the string
-- "{h1|Pc?}". Every real profile fell through the `if not startBlock then return text end`
-- guard untouched, so NormalizeFontWrappers was a no-op for the whole life of the setting.
-- A second copy of the same broken alternation sat on the next line
-- (startBlock:match("([Hh][123]|[Pp])")), so even a fixed opening pattern would have
-- bailed there.
--
-- Consequence: with "Minimum Font Size" enabled, a profile whose entire body was wrapped
-- in an explicit {h1}...{/h1} kept that wrapper. toHTML then emitted <h1>, which already
-- outranks the configured floor, so EnsureMinimumHtmlFont left it alone - the profile
-- rendered at h1 no matter what the user selected. CleanupLegacyFontWrappers (which calls
-- this with force=true over saved CU/CO fields) cleaned nothing either, and reported
-- "Removed legacy font wrappers from 0 character fields" every login.
--
-- Case note: TRP3's own structureTags table (totalRP3 core/impl/utils.lua:856) is
-- lowercase-only - {h1}/{h2:c}/{p}/{p:r}. "{H1}" is not a tag TRP3 renders, so it is not a
-- wrapper and must pass through untouched. The broken pattern's [Hh] classes implied
-- otherwise.

local T = require("tests.framework")
local H = require("tests.harness")

local function freshFW(prefs)
    local fw = H.newNamespace()
    fw.Prefs = prefs or { filterMinimumFontSize = true, minimumFontSizeLevel = "h3" }
    fw.ServiceContainer = { Get = function() return nil end }
    H.loadModule("hooks/fontsize.lua", fw)
    return fw
end

T.describe("NormalizeFontWrappers: strips a whole-text TRP3 structure wrapper", function()
    local fw = freshFW()

    local cases = {
        { "{h1}Hello there{/h1}",  "Hello there",  "plain h1 wrapper" },
        { "{h2}Body{/h2}",         "Body",         "h2 wrapper" },
        { "{h3}Body{/h3}",         "Body",         "h3 wrapper" },
        { "{p}body text{/p}",      "body text",    "paragraph wrapper" },
        { "{h2:c}Centered{/h2}",   "Centered",     "centered alignment suffix" },
        { "{h2:r}Right{/h2}",      "Right",        "right alignment suffix" },
        { "{p:c}Centered{/p}",     "Centered",     "centered paragraph" },
        { "{ h1 }spaced{ /h1 }",   "spaced",       "inner whitespace" },
        { "{h1}trailing{/h1}   ",  "trailing",     "trailing whitespace after close" },
    }

    for _, case in ipairs(cases) do
        local input, expected, label = case[1], case[2], case[3]
        T.it("strips " .. label, function()
            T.eq(fw:NormalizeFontWrappers(input), expected, label)
        end)
    end
end)

T.describe("NormalizeFontWrappers: leaves non-wrappers alone", function()
    local fw = freshFW()

    local cases = {
        { "plain text",                "no tags at all" },
        { "{h1}unclosed",              "opening tag with no matching close" },
        { "{h1}mismatched{/h2}",       "close tag is a different level" },
        { "{h4}bad level{/h4}",        "h4 is not a TRP3 heading level" },
        { "mid {h1}text{/h1}",         "opening tag is not at the start" },
        { "{h1}a{/h1} then more",      "close tag is not at the end" },
        { "{H1}Upper{/H1}",            "uppercase is not a TRP3 tag" },
        { "{P}Upper{/P}",              "uppercase paragraph is not a TRP3 tag" },
    }

    for _, case in ipairs(cases) do
        local input, label = case[1], case[2]
        T.it("passes through: " .. label, function()
            T.eq(fw:NormalizeFontWrappers(input), input, label)
        end)
    end

    T.it("handles nil, empty and non-string input without erroring", function()
        T.is_nil(fw:NormalizeFontWrappers(nil))
        T.eq(fw:NormalizeFontWrappers(""), "")
        T.eq(fw:NormalizeFontWrappers(42), 42)
    end)
end)

T.describe("NormalizeFontWrappers: honours the setting and the force override", function()
    T.it("is a no-op when filterMinimumFontSize is off", function()
        local fw = freshFW({ filterMinimumFontSize = false, minimumFontSizeLevel = "h3" })
        T.eq(fw:NormalizeFontWrappers("{h1}Body{/h1}"), "{h1}Body{/h1}",
            "the setting gates the live render path")
    end)

    T.it("still strips when force=true even with the setting off", function()
        local fw = freshFW({ filterMinimumFontSize = false, minimumFontSizeLevel = "h3" })
        T.eq(fw:NormalizeFontWrappers("{h1}Body{/h1}", true), "Body",
            "CleanupLegacyFontWrappers passes force=true to scrub already-saved fields")
    end)
end)

T.describe("EnsureMinimumHtmlFont: raises tags below the configured floor", function()
    local fw = freshFW()

    T.it("upgrades a paragraph to the h3 floor", function()
        T.eq(fw:EnsureMinimumHtmlFont("<P>text</P>"), "<H3>text</H3>")
    end)

    T.it("preserves alignment attributes while upgrading", function()
        T.eq(fw:EnsureMinimumHtmlFont('<P align="center">x</P>'),
            '<H3 align="center">x</H3>')
    end)

    T.it("leaves tags already at or above the floor untouched", function()
        T.eq(fw:EnsureMinimumHtmlFont("<h1>Title</h1>"), "<h1>Title</h1>")
        T.eq(fw:EnsureMinimumHtmlFont("<h3>Small</h3>"), "<h3>Small</h3>")
    end)

    T.it("ignores non-heading tags that toHTML emits", function()
        -- <img>, <br/> and <a> all come out of TRP3's toHTML; none may be rewritten.
        T.eq(fw:EnsureMinimumHtmlFont('<img src="x" width="8" height="8" align="center"/>'),
            '<img src="x" width="8" height="8" align="center"/>')
        T.eq(fw:EnsureMinimumHtmlFont("<h3>a<br/>b</h3>"), "<h3>a<br/>b</h3>")
        T.eq(fw:EnsureMinimumHtmlFont('<h3><a href="u">l</a></h3>'), '<h3><a href="u">l</a></h3>')
    end)

    T.it("is a no-op when the setting is off", function()
        local off = freshFW({ filterMinimumFontSize = false, minimumFontSizeLevel = "h3" })
        T.eq(off:EnsureMinimumHtmlFont("<P>text</P>"), "<P>text</P>")
    end)
end)

T.describe("fontsize: the wrapper strip and the floor compose", function()
    T.it("an {h1}-wrapped profile ends up at the configured floor, not h1", function()
        local fw = freshFW({ filterMinimumFontSize = true, minimumFontSizeLevel = "h3" })

        -- What the hook does: normalize the source text, hand it to toHTML, then apply the
        -- floor. Stand in for toHTML with the two substitutions it makes here.
        local source = "{h1}Body text{/h1}"
        local normalized = fw:NormalizeFontWrappers(source)
        T.eq(normalized, "Body text", "the explicit h1 wrapper is gone before toHTML sees it")

        local html = "<P>" .. normalized .. "</P>"  -- toHTML's untagged-line behaviour
        T.eq(fw:EnsureMinimumHtmlFont(html), "<H3>Body text</H3>",
            "so the floor decides the size - previously this stayed <h1>")
    end)
end)
