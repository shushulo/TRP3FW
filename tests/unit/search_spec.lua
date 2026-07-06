-- tests/unit/search_spec.lua
-- Headless tests for the settings-search filtering + complexity-gating logic in
-- ui/TabManager.lua (SearchSettings / EntryLevel / IsAboveLevel). These are pure
-- table/string operations; TabManager only touches CreateFrame inside its widget
-- constructors, so the file loads and these methods run without a frame mock.

local T = require("tests.framework")
local H = require("tests.harness")

local TRP3FW = H.newNamespace()
TRP3FW.SETTING_LEVELS = {}
H.loadModule("ui/TabManager.lua", TRP3FW)
local TM = TRP3FW.TabManager

-- Fake index of {label, widget(with complexityLevel), tabId}.
local function widget(level) return { complexityLevel = level } end
TM.searchIndex = {
    { label = "Enable notifications",   widget = widget(1), tabId = "notifications" },
    { label = "Phase check mode",       widget = widget(1), tabId = "alerts" },
    { label = "SPVP salt cache",        widget = widget(3), tabId = "security" },
    { label = "Send cache duration",    widget = widget(4), tabId = "debug" },
    { label = "Notify on whisper",      widget = widget(2), tabId = "notifications" },
    -- A card heading: no complexityLevel on the widget, so it's never gated.
    { label = "Ghost mode",             widget = { _isHeading = true }, tabId = "alerts" },
}

T.describe("TabManager:SearchSettings", function()
    T.it("returns nothing for an empty query", function()
        T.eq(#TM:SearchSettings("", 8), 0)
        T.eq(#TM:SearchSettings(nil, 8), 0)
    end)

    T.it("matches case-insensitive substrings of the label", function()
        local r = TM:SearchSettings("cache", 8)
        T.eq(#r, 2, "SPVP salt cache + Send cache duration")
        local r2 = TM:SearchSettings("NOTIF", 8)  -- upper query, mixed-case labels
        T.eq(#r2, 2, "Enable notifications + Notify on whisper")
    end)

    T.it("respects the result limit", function()
        T.eq(#TM:SearchSettings("e", 2), 2)  -- many labels contain 'e'; capped at 2
    end)

    T.it("returns entries carrying their widget + tabId", function()
        local r = TM:SearchSettings("Phase check", 8)
        T.eq(#r, 1)
        T.eq(r[1].tabId, "alerts")
        T.not_nil(r[1].widget)
    end)

    T.it("finds card headings (e.g. 'Ghost mode')", function()
        local r = TM:SearchSettings("ghost", 8)
        T.eq(#r, 1)
        T.eq(r[1].tabId, "alerts")
        T.truthy(r[1].widget._isHeading, "heading entry")
    end)

    T.it("headings are never above level (no complexityLevel -> defaults to 1)", function()
        TRP3FW.Prefs.uiComplexityLevel = 1
        T.falsy(TM:IsAboveLevel({ widget = { _isHeading = true } }), "headings always visible")
    end)
end)

T.describe("TabManager complexity gating", function()
    T.it("EntryLevel reads the widget's complexity (default 1)", function()
        T.eq(TM:EntryLevel({ widget = widget(3) }), 3)
        T.eq(TM:EntryLevel({ widget = {} }), 1, "missing level defaults to 1")
        T.eq(TM:EntryLevel(nil), 1)
    end)

    T.it("IsAboveLevel compares against the current uiComplexityLevel", function()
        TRP3FW.Prefs.uiComplexityLevel = 2
        T.falsy(TM:IsAboveLevel({ widget = widget(1) }), "level 1 <= 2 -> visible")
        T.falsy(TM:IsAboveLevel({ widget = widget(2) }), "level 2 <= 2 -> visible")
        T.truthy(TM:IsAboveLevel({ widget = widget(3) }), "level 3 > 2 -> hidden")
    end)

    T.it("tracks the current level (raising it reveals more)", function()
        TRP3FW.Prefs.uiComplexityLevel = 4
        T.falsy(TM:IsAboveLevel({ widget = widget(4) }), "everything visible at 4")
        TRP3FW.Prefs.uiComplexityLevel = 1
        T.truthy(TM:IsAboveLevel({ widget = widget(2) }), "level 2 hidden at Basic")
    end)
end)

return T
