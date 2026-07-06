-- tests/unit/theme_spec.lua
-- Headless tests for ui/Theme.lua's pure color helpers: rgb hex parsing and the
-- Color/Hex accessors. Guards the multi-return contract (Color must yield 4
-- values r,g,b,a -- truncating it to one caused the red-sidebar bug).

local T = require("tests.framework")
local H = require("tests.harness")

local TRP3FW = H.newNamespace()

-- Theme.lua builds custom font objects from GameFont* bases at load time.
-- Provide just enough of the font/color API for it to load headlessly.
local function fakeFont(name)
    local f = { _size = 12, _file = "Fonts\\FRIZQT__.TTF", _flags = "" }
    function f:CopyFontObject(o) self._size = o._size; self._file = o._file; self._flags = o._flags end
    function f:GetFont() return self._file, self._size, self._flags end
    function f:SetFont(file, size, flags) self._file, self._size, self._flags = file, size, flags end
    _G[name] = f
    return f
end
for _, n in ipairs({ "GameFontNormalLarge", "GameFontNormal", "GameFontHighlight", "GameFontNormalSmall", "GameFontNormalHuge" }) do
    fakeFont(n)
end
_G.CreateFont = function(name) return fakeFont(name) end
_G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

H.loadModule("ui/Theme.lua", TRP3FW)
local Theme = TRP3FW.Theme

local function approx(a, b) return math.abs(a - b) < 0.004 end

T.describe("Theme.rgb / Color", function()
    T.it("parses hex into 0-1 channels (via a known palette entry)", function()
        -- GOLD = d1a24c -> 0.82, 0.635, 0.298
        local r, g, b = Theme:Color("GOLD")
        T.truthy(approx(r, 0xd1 / 255), "R ~= d1")
        T.truthy(approx(g, 0xa2 / 255), "G ~= a2")
        T.truthy(approx(b, 0x4c / 255), "B ~= 4c")
    end)

    T.it("returns FOUR values (r,g,b,a) -- guards the truncation bug", function()
        -- `a and Theme:Color(x) or Theme:Color(y)` truncated this to 1 value,
        -- leaving g/b/a nil -> pure red. Color must always return 4.
        local r, g, b, a = Theme:Color("TEXT_SECONDARY")
        T.not_nil(r, "r"); T.not_nil(g, "g"); T.not_nil(b, "b"); T.not_nil(a, "a")
        T.eq(a, 1, "default alpha is 1")
    end)

    T.it("passes alpha through", function()
        local _, _, _, a = Theme:Color("GOLD", 0.5)
        T.eq(a, 0.5)
    end)

    T.it("falls back to white for unknown names without crashing", function()
        local r, g, b = Theme:Color("NOPE")
        T.eq(r, 1); T.eq(g, 1); T.eq(b, 1)
    end)

    T.it("Hex returns a 6-char lowercase string matching the channels", function()
        T.eq(Theme:Hex("GOLD"), "d1a24c")
    end)

    T.it("ColorObject returns a cached CreateColor result", function()
        local a = Theme:ColorObject("GOLD")
        local b = Theme:ColorObject("GOLD")
        T.not_nil(a)
        T.truthy(a == b, "same object cached across calls")
    end)
end)

return T
