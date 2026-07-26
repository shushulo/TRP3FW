-- tests/unit/ui_refresh_spec.lua
-- Section 8 (UI) regressions.
--
-- Three defects, all of the same family the earlier sections kept finding:
-- state that something is assumed to own, owned by nobody.
--
--  1. The four phase-batching sliders were registered into uiElements under
--     "<key>Slider" keys that RefreshUI never reads, so they never received the
--     stored pref and displayed their minimum instead.
--  2. SETTING_LEVELS carried "phaseCheckBatchInterDelay", a key no setting uses;
--     the real key is "phaseCheckInterTargetDelay", which therefore fell through
--     to the level-4 default and vanished below the Everything complexity level.
--  3. debugwindow.lua's RefreshDebugOutput referenced `autoScrollCheck` as an
--     upvalue, but the local is declared BELOW the function -- so the name
--     resolved to a nil global and auto-scroll never ran.
--
-- The frames themselves need a real client; these tests pin the data contracts
-- (which keys RefreshUI drives, which keys SETTING_LEVELS covers, and the
-- declaration order in debugwindow.lua) that the fixes restore.

local T = require("tests.framework")
local H = require("tests.harness")

local TRP3FW = H.newNamespace()

_G.StaticPopupDialogs = _G.StaticPopupDialogs or {}
_G.CopyTable = _G.CopyTable or function(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end

H.loadModule("ui/settings.lua", TRP3FW)

-- Read a file as one string (specs run from the addon root).
local function readFile(path)
    local f = assert(io.open(path, "r"), "could not open " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

local settingsSrc = readFile("ui/settings.lua")

T.describe("SETTING_LEVELS covers the real setting keys", function()
    T.it("classifies phaseCheckInterTargetDelay (the key the code actually reads)", function()
        T.truthy(TRP3FW.SETTING_LEVELS.phaseCheckInterTargetDelay,
            "inter-target delay must have a complexity level, or it hides at level 4")
    end)

    T.it("does not classify the phantom phaseCheckBatchInterDelay key", function()
        T.is_nil(TRP3FW.SETTING_LEVELS.phaseCheckBatchInterDelay,
            "no setting by this name exists; it shadowed the real one")
    end)

    T.it("keeps the inter-target delay at the same level as its sibling batch settings", function()
        T.eq(TRP3FW.SETTING_LEVELS.phaseCheckInterTargetDelay,
             TRP3FW.SETTING_LEVELS.phaseCheckBatchDelay,
             "all four batching tunables belong to one group")
    end)
end)

T.describe("RefreshUI drives every slider it owns", function()
    -- Each of these is created in ui/tabs/Debug.lua as uiElements[<name>] and
    -- must be handed its stored pref by RefreshUI, the way
    -- spvpBlockDurationSlider / spvpSaltCacheDurationSlider already are.
    --
    -- `uiElements` is a file-local in ui/settings.lua with no accessor, so a
    -- behavioural test would mean adding a test-only hook to production code.
    -- Assert on the source instead: each slider key must appear somewhere in
    -- RefreshUI paired with the pref key it displays. That catches the actual
    -- defect (the key being absent entirely) without pinning an indexing style.
    local sliderKeys = {
        { "phaseCheckBatchSizeSlider",        "phaseCheckBatchSize"        },
        { "phaseCheckBatchDelaySlider",       "phaseCheckBatchDelay"       },
        { "phaseCheckBatchMinSizeSlider",     "phaseCheckBatchMinSize"     },
        { "phaseCheckInterTargetDelaySlider", "phaseCheckInterTargetDelay" },
        { "spvpBlockDurationSlider",          "spvpBlockDuration"          }, -- control
        { "spvpSaltCacheDurationSlider",      "spvpSaltCacheDuration"      }, -- control
    }

    for _, pair in ipairs(sliderKeys) do
        local widgetKey, prefKey = pair[1], pair[2]
        T.it(widgetKey .. " is populated from " .. prefKey, function()
            T.truthy(settingsSrc:find(widgetKey, 1, true),
                widgetKey .. " is never mentioned in ui/settings.lua, so RefreshUI "
                .. "leaves it at the slider minimum regardless of the stored value")
            T.truthy(settingsSrc:find(prefKey, 1, true),
                prefKey .. " must be read so the widget shows the stored value")
        end)
    end
end)

T.describe("debugwindow auto-scroll is not a nil global", function()
    local src = readFile("ui/debugwindow.lua")

    T.it("declares autoScrollCheck before the function that reads it", function()
        local declPos = src:find("local autoScrollCheck")
        local usePos  = src:find("if autoScrollCheck and autoScrollCheck:GetChecked")
        T.truthy(declPos, "autoScrollCheck local must exist")
        T.truthy(usePos, "the auto-scroll branch must exist")
        T.truthy(declPos < usePos,
            "reading it above its `local` resolves to a nil global -- auto-scroll silently never fires")
    end)

    T.it("keeps exactly one declaration of autoScrollCheck", function()
        local n = 0
        for _ in src:gmatch("local autoScrollCheck") do n = n + 1 end
        T.eq(n, 1, "a second `local` would shadow the first and reintroduce the bug")
    end)
end)

return T
