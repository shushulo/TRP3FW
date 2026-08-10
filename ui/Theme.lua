-- ui/Theme.lua
-- Central UI theme for TRP3FW: palette, backdrop tables, and color helpers.
--
-- This is the single source of truth for the redesigned settings UI. It matches
-- Total RP 3's own visual language: dark slate-blue dialog surfaces (Blizzard's
-- UI-DialogBox textures) with gold reserved for the ornate frame border and a
-- few title accents -- not gold fills.
--
-- Loaded before TabManager (see TRP3FW.toc) so every UI file can rely on
-- TRP3FW.Theme being present.
--
-- Note: TRP3FW.COLOR (in core/init.lua) is a separate table of chat-message
-- color CODES (|cff... escapes). This Theme table is for frame/texture colors
-- (0-1 RGBA). Keep them distinct: COLOR = chat text, Theme = UI surfaces.

local addonName, TRP3FW = ...

local Theme = {}
TRP3FW.Theme = Theme

-- ---------------------------------------------------------------------------
-- Palette
--
-- Each entry is {r, g, b} in 0-1 space. Alpha is passed at call sites so the
-- same color can be used opaque (fills) or translucent (overlays). Values are
-- the hex tones validated in the redesign mockups, converted to 0-1.
-- ---------------------------------------------------------------------------

local function rgb(hex)
    -- hex: "RRGGBB" -> r, g, b in 0-1
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return { r, g, b }
end

Theme.palette = {
    -- Surfaces (darkest -> lightest). Lifted out of near-black so cards read as
    -- distinct slate panels rather than voids; hue stays slate-blue.
    PANEL         = rgb("161a26"), -- main content background (slate)
    CARD          = rgb("222839"), -- grouped setting cards / header+footer bars
    INSET         = rgb("11141d"), -- sidebar, slider tracks, sunken wells
    CARD_HOVER    = rgb("2e3650"), -- hovered/active row tint

    -- Trim & accent (gold, used sparingly)
    GOLD          = rgb("d1a24c"), -- frame border tint, active markers, fills that mean "accent"
    GOLD_TEXT     = rgb("ecdcb0"), -- section captions, accented labels
    FRAME_GOLD    = rgb("8a6a2f"), -- outer ornate frame edge tint

    -- Borders
    BORDER        = rgb("3a4258"), -- default hairline between cards/rows
    BORDER_STRONG = rgb("4c566f"), -- hover / emphasized divider

    -- Track (unfilled slider groove, progress-bar background): a visible
    -- blue-slate. INSET is too near-black to read against a CARD surface.
    TRACK         = rgb("39435c"),
    TRACK_HOVER   = rgb("4a5674"),

    -- Text
    TEXT_PRIMARY   = rgb("cdd2df"),
    TEXT_SECONDARY = rgb("9aa0b6"),
    TEXT_MUTED     = rgb("707790"),

    -- Semantic (encode meaning; kept vivid on purpose)
    SUCCESS   = rgb("5d9c3f"), -- allow / good / on
    SUCCESS_T = rgb("7fc07f"), -- success text on dark
    WARN      = rgb("c99a44"), -- caution / mid (shares gold on purpose)
    DANGER    = rgb("c65f45"), -- block / bad
    DANGER_T  = rgb("d76b5e"), -- danger text/number on dark
    GHOST     = rgb("79b0dd"), -- ghost sends (light blue)
}

-- Convenience accessors: Theme:Color("GOLD") -> r, g, b (+ optional alpha passthrough)
function Theme:Color(name, alpha)
    local c = self.palette[name]
    if not c then return 1, 1, 1, alpha or 1 end
    return c[1], c[2], c[3], alpha or 1
end

-- Return a WoW ColorMixin for the given palette entry (for FontString:SetTextColor
-- via :GetRGB(), tooltip lines, etc.). Cached per name.
local colorObjectCache = {}
function Theme:ColorObject(name)
    local cached = colorObjectCache[name]
    if cached then return cached end
    local c = self.palette[name] or { 1, 1, 1 }
    local obj = CreateColor(c[1], c[2], c[3], 1)
    colorObjectCache[name] = obj
    return obj
end

-- Return a |cff...| chat escape hex string for a palette entry, so notifications
-- and tooltips can reuse the exact UI tones. Cached per name.
local hexCache = {}
function Theme:Hex(name)
    local cached = hexCache[name]
    if cached then return cached end
    local c = self.palette[name] or { 1, 1, 1 }
    local hex = string.format("%02x%02x%02x",
        math.floor(c[1] * 255 + 0.5),
        math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
    hexCache[name] = hex
    return hex
end

-- ---------------------------------------------------------------------------
-- Backdrop tables
--
-- Reuse the exact Blizzard textures Total RP 3 uses, so the firewall panel is a
-- genuine family member rather than a hex approximation. See TRP3's
-- core/ui/widgets.lua (TRP3_BACKDROP_MIXED_DIALOG_TOOLTIP_*).
-- ---------------------------------------------------------------------------

-- Outer window: dark dialog background with the ornate gold DialogBox border.
Theme.BACKDROP_FRAME = {
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile     = true,
    tileEdge = true,
    tileSize = 32,
    edgeSize = 24,
    insets   = { left = 6, right = 6, top = 6, bottom = 6 },
}

-- Grouped setting card: same dark background, thinner tooltip border for a
-- lighter interior division.
Theme.BACKDROP_CARD = {
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = true,
    tileEdge = true,
    tileSize = 200,
    edgeSize = 14,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- Circular alpha mask for rounding square WHITE8X8 textures (toggle knobs, pill
-- end caps, slider thumbs). Same hard-edged circle asset Total RP 3 uses.
-- Applied via texture:AddMaskTexture(mask) where mask:SetTexture(this, clamp, clamp).
Theme.ROUND_MASK = "Interface\\Common\\common-iconmask"

-- Sunken well (sidebar, slider track background): border only, no bg fill so we
-- can color the interior with a flat texture for maximum contrast control.
Theme.BACKDROP_WELL = {
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = true,
    tileEdge = true,
    edgeSize = 12,
    insets   = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Chip backdrop: solid tileable fill + thin tooltip border. MUST have a bgFile
-- so SetBackdropColor actually tints the interior (a border-only backdrop shows
-- no fill and the chip appears to only fade). ChatFrameBackground is a flat
-- white tile that takes color cleanly.
Theme.BACKDROP_CHIP = {
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = true,
    tileEdge = true,
    tileSize = 16,
    edgeSize = 12,
    insets   = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- ---------------------------------------------------------------------------
-- Layout metrics (named constants replacing ad-hoc -30 / -40 / -45 offsets)
-- ---------------------------------------------------------------------------

Theme.metrics = {
    ROW        = 30,  -- vertical step between rows in a group
    ROW_TALL   = 40,  -- row with sub-label / larger control
    SECTION    = 45,  -- gap before a new section header
    PAD        = 12,  -- card interior padding (legacy; prefer INNER)
    INNER      = 12,  -- inset of ALL interior elements from the card edge
    CARD_GAP   = 8,   -- gap between stacked cards (== GAP so all gaps match)
    SIDEBAR_W  = 158, -- left nav width

    -- Content layout (single source of truth so all tabs stay in sync).
    -- GAP: the ONE visual gap between boxes (sidebar->cards, cards->scrollbar,
    --   scrollbar->edge, below title bar). EDGE: margin from the raw frame edge;
    --   the frame's border art consumes ~5px, so 14 raw reads as ~8 visible.
    -- Cards fill the scroll viewport edge-to-edge (CONTENT_INSET 0) -- the
    --   structural gaps provide the spacing, never stacked twice.
    -- Derivation: window(864) - EDGE(18) - sidebar(158) - GAP(8) - EDGE(18)
    --   = 662 content panel; - scrollbar zone(24 = GAP + 16px bar) = 638.
    -- EDGE/TOP_GAP are raw-frame offsets; the border art (~5px edge, ~24px
    -- title bar) eats part of them, so the visible outer margins land slightly
    -- LARGER than the inner 8px gaps -- deliberate (outer margins > gutters).
    GAP           = 8,
    EDGE          = 18,
    TOP_GAP       = 36,
    SCROLL_W      = 638,
    CONTENT_INSET = 0,
    CARD_W        = 638, -- == SCROLL_W (cards span the full viewport)
}

-- Fonts: build custom font objects that inherit each Blizzard base's face and
-- flags but bump the point size, so every widget reading Theme.fonts.* gets
-- consistently larger text from one place. Change FONT_BUMP to rescale globally.
Theme.FONT_BUMP = 2  -- points added to each role's Blizzard base size

-- The Blizzard base each role derives from, and a size to fall back on if that
-- base object is somehow missing. Kept as data so RefreshFonts can rebuild every
-- role from the same declaration makeFont used.
local FONT_ROLES = {
    { role = "TITLE",   name = "TRP3FW_Font_Title",   base = "GameFontNormalLarge", fallback = 16 },
    { role = "CAPTION", name = "TRP3FW_Font_Caption", base = "GameFontNormalLarge", fallback = 16 }, -- gold card headers; larger than body LABEL
    { role = "HEADER",  name = "TRP3FW_Font_Header",  base = "GameFontNormal",      fallback = 12 },
    { role = "LABEL",   name = "TRP3FW_Font_Label",   base = "GameFontHighlight",   fallback = 12 },
    { role = "SUB",     name = "TRP3FW_Font_Sub",     base = "GameFontNormalSmall", fallback = 10 },
    { role = "VALUE",   name = "TRP3FW_Font_Value",   base = "GameFontNormalHuge",  fallback = 24 },
}

-- Apply a role's size to its font object, creating the object on first call.
--
-- IMPORTANT -- why this must be re-run on viewport change:
-- Blizzard's font objects are resolution-dependent; the client re-resolves their
-- point sizes when the viewport changes, and any widget that merely REFERENCES
-- GameFontNormal follows along automatically. CopyFontObject + SetFont does not:
-- it snapshots the size resolved at load time and then pins it with an explicit
-- SetFont, severing that link. So after a window resize/snap, Blizzard's text
-- re-resolves and ours stays frozen at the old viewport's size -- the addon's
-- text visibly changes size relative to everything else.
--
-- Re-reading base:GetFont() and re-applying the bump restores the relationship.
-- Because Theme.fonts.* are font object NAMES (returned below) that widgets hold
-- a live reference to, calling SetFont on the shared object updates every
-- existing FontString at once -- no widget traversal, no relayout.
local function applyFont(entry)
    local fontObj = _G[entry.name] or CreateFont(entry.name)
    local base = _G[entry.base]
    if base then
        fontObj:CopyFontObject(base)
        local file, size, flags = base:GetFont()
        if file and size then
            fontObj:SetFont(file, size + Theme.FONT_BUMP, flags)
        end
    else
        -- Extremely defensive fallback if the base object is missing.
        fontObj:SetFont(STANDARD_TEXT_FONT, (entry.fallback or 12) + Theme.FONT_BUMP, "")
    end
    return entry.name
end

Theme.fonts = {}
for _, entry in ipairs(FONT_ROLES) do
    Theme.fonts[entry.role] = applyFont(entry)
end

-- Re-derive every role from its (freshly re-resolved) Blizzard base. Safe to
-- call at any time; idempotent when nothing changed. Returns true if any role's
-- resulting size differs from what it was, so callers can skip needless work.
function Theme:RefreshFonts()
    local changed = false
    for _, entry in ipairs(FONT_ROLES) do
        local existing = _G[entry.name]
        -- NOTE: `existing and existing:GetFont()` would truncate the multiple
        -- return to one value, leaving `before` nil and making every refresh
        -- report "changed". Read the size explicitly instead.
        local before
        if existing then before = select(2, existing:GetFont()) end
        applyFont(entry)
        local after = select(2, _G[entry.name]:GetFont())
        if before ~= after then changed = true end
    end
    return changed
end

-- Rebuild the fonts whenever the viewport changes, so our sizes track Blizzard's
-- re-resolved bases instead of staying pinned to the size captured at load.
--
-- Registered here rather than on the settings frame on purpose: the settings
-- window is created lazily and may not exist (or may be hidden) when the resize
-- happens, but the font objects are global and shared with the debug/history
-- windows too. Refreshing them centrally keeps every window consistent.
--
-- DISPLAY_SIZE_CHANGED covers window resize/snap and resolution changes;
-- UI_SCALE_CHANGED covers the uiScale slider and the "Use UI Scale" checkbox.
-- Both are rare, and the handler is a 6-entry loop, so this is not hot.
local fontWatcher = CreateFrame("Frame")
fontWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
fontWatcher:RegisterEvent("UI_SCALE_CHANGED")
fontWatcher:SetScript("OnEvent", function(_, event)
    -- Blizzard re-resolves its font objects while handling the same event, and
    -- ordering between addon and client handlers is not guaranteed. Defer a
    -- frame so we read the NEW base sizes rather than the ones being replaced.
    C_Timer.After(0, function()
        local changed = Theme:RefreshFonts()
        if not changed then return end

        if TRP3FW.Debug then
            TRP3FW:Debug("Fonts rebuilt after " .. tostring(event), "ui")
        end

        -- Existing FontStrings pick up the new size automatically (they hold a
        -- live reference to the shared font object), but a few widgets size
        -- themselves from MEASURED text -- Dashboard badges, TabManager chips,
        -- history tooltips -- and those widths were computed at the old size.
        -- Reflowing re-runs that measurement. Guarded because Theme.lua loads
        -- before TabManager.lua and well before any card is built.
        local TM = TRP3FW.TabManager
        if TM and TM.ReflowAllCards and TM._cards then
            TM:ReflowAllCards(TRP3FW.Prefs and TRP3FW.Prefs.uiComplexityLevel)
        end
    end)
end)
