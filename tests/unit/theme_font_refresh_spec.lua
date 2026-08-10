-- tests/unit/theme_font_refresh_spec.lua
-- Font rebuild on viewport change (ui/Theme.lua).
--
-- THE BUG: Theme's font objects are built once at load with CopyFontObject +
-- an explicit SetFont that bumps the size. Blizzard's font objects are
-- resolution-dependent -- the client re-resolves their point sizes when the
-- viewport changes, and widgets that merely REFERENCE GameFontNormal follow
-- along. The explicit SetFont severs that link, pinning our sizes to whatever
-- was resolved at load.
--
-- Symptom as reported: snapping a 3840-wide window to 1920 left every frame and
-- box correctly sized (all layout metrics are hardcoded logical units) while the
-- addon's TEXT got smaller relative to Blizzard's, which stayed put.
--
-- THE FIX: Theme:RefreshFonts() re-reads each Blizzard base and re-applies the
-- bump, wired to DISPLAY_SIZE_CHANGED / UI_SCALE_CHANGED. Because Theme.fonts.*
-- are font object NAMES that widgets hold a live reference to, mutating the
-- shared object updates every existing FontString with no widget traversal.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

-- Blizzard base sizes as the client would resolve them on a large viewport.
local WIDE = {
    GameFontNormalLarge = 16,
    GameFontNormal      = 12,
    GameFontHighlight    = 12,
    GameFontNormalSmall = 10,
    GameFontNormalHuge  = 24,
}

-- The same bases after the client re-resolves them for a narrower viewport.
local NARROW = {
    GameFontNormalLarge = 13,
    GameFontNormal      = 10,
    GameFontHighlight    = 10,
    GameFontNormalSmall = 8,
    GameFontNormalHuge  = 19,
}

local function newEnv(baseSizes)
    -- Drop any font objects a previous spec installed: these specs share one Lua
    -- state, and CreateFont returns the EXISTING object for a known name, so a
    -- stale TRP3FW_Font_* would make a rebuild look like a no-op.
    for name in pairs(mock.fonts) do _G[name] = nil end
    for _, n in ipairs({ "GameFontNormalLarge", "GameFontNormal", "GameFontHighlight",
                         "GameFontNormalSmall", "GameFontNormalHuge" }) do
        _G[n] = nil
    end
    mock.fonts = {}

    -- Re-assert the mock's CreateFont. theme_spec.lua installs its own version
    -- that returns a BRAND NEW object on every call; these specs share one Lua
    -- state, so whichever ran last wins. With that version a rebuild would never
    -- mutate the object a widget holds -- the exact property under test here.
    _G.CreateFont = function(name) return mock.newFont(name, nil, 12, "") end

    mock.setBlizzardFontSizes(baseSizes or WIDE)
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

    local TRP3FW = H.newNamespace()
    H.loadModule("ui/Theme.lua", TRP3FW)
    return TRP3FW
end

-- Drop any timers queued by earlier specs, so flushTimers only ever runs the one
-- our event handler schedules. Without this, unrelated deferred callbacks (e.g.
-- spvp_auto_init's) fire against a namespace that has no ServiceContainer.
local function clearTimers()
    mock.timers = {}
end

-- Flush the deferred C_Timer.After(0) the event handler schedules.
local function flushTimers()
    local pending = mock.timers
    mock.timers = {}
    for _, t in ipairs(pending) do
        if not t.cancelled then t.fn() end
    end
end

T.describe("Theme font objects", function()
    T.it("builds each role at its Blizzard base size plus the bump", function()
        local TRP3FW = newEnv(WIDE)
        local Theme = TRP3FW.Theme
        local bump = Theme.FONT_BUMP
        T.eq(select(2, _G[Theme.fonts.LABEL]:GetFont()), WIDE.GameFontHighlight + bump)
        T.eq(select(2, _G[Theme.fonts.SUB]:GetFont()), WIDE.GameFontNormalSmall + bump)
        T.eq(select(2, _G[Theme.fonts.VALUE]:GetFont()), WIDE.GameFontNormalHuge + bump)
    end)

    T.it("exposes font object NAMES, not objects", function()
        local TRP3FW = newEnv()
        -- This is load-bearing: widgets pass these to CreateFontString/
        -- SetFontObject, which is what makes a later SetFont propagate to them.
        T.eq(type(TRP3FW.Theme.fonts.LABEL), "string",
            "widgets need a registered name so they share the live font object")
        T.eq(TRP3FW.Theme.fonts.LABEL, "TRP3FW_Font_Label")
    end)
end)

T.describe("Theme:RefreshFonts", function()
    T.it("re-derives sizes after the Blizzard bases change", function()
        local TRP3FW = newEnv(WIDE)
        local Theme = TRP3FW.Theme
        local bump = Theme.FONT_BUMP

        -- The client re-resolves its fonts for the narrower viewport.
        mock.setBlizzardFontSizes(NARROW)

        -- Before the refresh our sizes are stale -- this IS the reported bug.
        T.eq(select(2, _G[Theme.fonts.LABEL]:GetFont()), WIDE.GameFontHighlight + bump,
            "stale until refreshed; the frozen snapshot is the defect")

        Theme:RefreshFonts()

        T.eq(select(2, _G[Theme.fonts.LABEL]:GetFont()), NARROW.GameFontHighlight + bump,
            "must track the re-resolved base")
        T.eq(select(2, _G[Theme.fonts.SUB]:GetFont()), NARROW.GameFontNormalSmall + bump)
        T.eq(select(2, _G[Theme.fonts.TITLE]:GetFont()), NARROW.GameFontNormalLarge + bump)
    end)

    T.it("mutates the SHARED object so existing widgets follow", function()
        local TRP3FW = newEnv(WIDE)
        local Theme = TRP3FW.Theme

        -- A widget created before the resize holds this exact reference.
        local widgetFont = _G[Theme.fonts.LABEL]

        mock.setBlizzardFontSizes(NARROW)
        Theme:RefreshFonts()

        T.eq(widgetFont, _G[Theme.fonts.LABEL],
            "refresh must not swap in a new object; widgets would keep the old one")
        T.eq(select(2, widgetFont:GetFont()), NARROW.GameFontHighlight + Theme.FONT_BUMP,
            "the reference a live FontString holds must show the new size")
    end)

    T.it("reports whether anything actually changed", function()
        local TRP3FW = newEnv(WIDE)
        local Theme = TRP3FW.Theme
        T.eq(Theme:RefreshFonts(), false, "no base changed -> no work for callers")

        mock.setBlizzardFontSizes(NARROW)
        T.eq(Theme:RefreshFonts(), true, "bases changed -> callers should relayout")
    end)

    T.it("is idempotent", function()
        local TRP3FW = newEnv(WIDE)
        local Theme = TRP3FW.Theme
        mock.setBlizzardFontSizes(NARROW)
        Theme:RefreshFonts()
        local afterFirst = select(2, _G[Theme.fonts.LABEL]:GetFont())
        Theme:RefreshFonts()
        Theme:RefreshFonts()
        T.eq(select(2, _G[Theme.fonts.LABEL]:GetFont()), afterFirst,
            "repeated refreshes must not compound the bump")
    end)

    T.it("recovers when fonts grow back", function()
        local TRP3FW = newEnv(WIDE)
        local Theme = TRP3FW.Theme
        mock.setBlizzardFontSizes(NARROW)
        Theme:RefreshFonts()
        -- Un-snap back to the wide viewport.
        mock.setBlizzardFontSizes(WIDE)
        Theme:RefreshFonts()
        T.eq(select(2, _G[Theme.fonts.LABEL]:GetFont()), WIDE.GameFontHighlight + Theme.FONT_BUMP,
            "restoring the window must restore the original size, not stay small")
    end)

    T.it("survives a missing Blizzard base", function()
        local TRP3FW = newEnv(WIDE)
        local Theme = TRP3FW.Theme
        _G.GameFontHighlight = nil
        T.no_raise(function() Theme:RefreshFonts() end,
            "a missing base must fall back, not error during a resize")
        local _, size = _G[Theme.fonts.LABEL]:GetFont()
        T.eq(type(size), "number", "the fallback must still yield a usable size")
    end)
end)

T.describe("Theme font refresh wiring", function()
    T.it("registers for viewport-change events", function()
        newEnv()
        local watcher
        for _, f in ipairs(mock.frames) do
            if f.events and f.events["DISPLAY_SIZE_CHANGED"] then watcher = f end
        end
        T.eq(watcher ~= nil, true, "something must listen for the resize")
        T.eq(watcher.events["UI_SCALE_CHANGED"] ~= nil, true,
            "the uiScale slider changes font sizes the same way a resize does")
    end)

    T.it("rebuilds fonts when the event fires", function()
        local TRP3FW = newEnv(WIDE)
        local Theme = TRP3FW.Theme

        local watcher
        for _, f in ipairs(mock.frames) do
            if f.events and f.events["DISPLAY_SIZE_CHANGED"] then watcher = f end
        end

        clearTimers()
        mock.setBlizzardFontSizes(NARROW)
        watcher.scripts.OnEvent(watcher, "DISPLAY_SIZE_CHANGED")

        -- The handler defers a frame so Blizzard finishes re-resolving first.
        T.eq(select(2, _G[Theme.fonts.LABEL]:GetFont()), WIDE.GameFontHighlight + Theme.FONT_BUMP,
            "must NOT rebuild synchronously; base sizes may still be mid-update")

        flushTimers()

        T.eq(select(2, _G[Theme.fonts.LABEL]:GetFont()), NARROW.GameFontHighlight + Theme.FONT_BUMP,
            "after the deferred frame the sizes must be current")
    end)

    T.it("does not error when TabManager has no cards yet", function()
        local TRP3FW = newEnv(WIDE)
        local watcher
        for _, f in ipairs(mock.frames) do
            if f.events and f.events["DISPLAY_SIZE_CHANGED"] then watcher = f end
        end
        clearTimers()
        mock.setBlizzardFontSizes(NARROW)
        -- Theme.lua loads before TabManager.lua and long before any card exists;
        -- an early resize must not take the reflow path.
        watcher.scripts.OnEvent(watcher, "DISPLAY_SIZE_CHANGED")
        T.no_raise(flushTimers, "an early resize must not blow up on a nil TabManager")
    end)

    T.it("reflows cards so text-measured widths are recomputed", function()
        local TRP3FW = newEnv(WIDE)
        local reflowed = false
        TRP3FW.TabManager = {
            _cards = { {} },
            ReflowAllCards = function() reflowed = true end,
        }

        local watcher
        for _, f in ipairs(mock.frames) do
            if f.events and f.events["DISPLAY_SIZE_CHANGED"] then watcher = f end
        end

        clearTimers()
        mock.setBlizzardFontSizes(NARROW)
        watcher.scripts.OnEvent(watcher, "DISPLAY_SIZE_CHANGED")
        flushTimers()

        -- Dashboard badges, TabManager chips and history tooltips size themselves
        -- from GetStringWidth/GetStringHeight at creation time.
        T.eq(reflowed, true, "measured-text widths are stale until a reflow")
    end)

    T.it("skips the reflow when no size actually changed", function()
        local TRP3FW = newEnv(WIDE)
        local reflowed = false
        TRP3FW.TabManager = {
            _cards = { {} },
            ReflowAllCards = function() reflowed = true end,
        }

        local watcher
        for _, f in ipairs(mock.frames) do
            if f.events and f.events["DISPLAY_SIZE_CHANGED"] then watcher = f end
        end

        clearTimers()
        -- Fire with the bases unchanged (e.g. a resize that kept font sizes).
        watcher.scripts.OnEvent(watcher, "DISPLAY_SIZE_CHANGED")
        flushTimers()

        T.eq(reflowed, false, "a no-op resize must not trigger a full relayout")
    end)
end)
