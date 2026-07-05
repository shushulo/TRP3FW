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

local function makeFont(name, baseObjectName, fallbackSize)
    local base = _G[baseObjectName]
    local fontObj = CreateFont(name)
    if base then
        fontObj:CopyFontObject(base)
        local file, size, flags = base:GetFont()
        if file and size then
            fontObj:SetFont(file, size + Theme.FONT_BUMP, flags)
        end
    else
        -- Extremely defensive fallback if the base object is missing.
        fontObj:SetFont(STANDARD_TEXT_FONT, (fallbackSize or 12) + Theme.FONT_BUMP, "")
    end
    return name
end

Theme.fonts = {
    TITLE   = makeFont("TRP3FW_Font_Title",   "GameFontNormalLarge", 16),
    CAPTION = makeFont("TRP3FW_Font_Caption", "GameFontNormalLarge", 16), -- gold card headers; larger than body LABEL
    HEADER  = makeFont("TRP3FW_Font_Header",  "GameFontNormal",      12),
    LABEL   = makeFont("TRP3FW_Font_Label",   "GameFontHighlight",   12),
    SUB     = makeFont("TRP3FW_Font_Sub",     "GameFontNormalSmall", 10),
    VALUE   = makeFont("TRP3FW_Font_Value",   "GameFontNormalHuge",  24),
}
