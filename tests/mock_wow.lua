-- tests/mock_wow.lua
-- Minimal WoW API shim so pure-logic TRP3FW modules can load and run under
-- standalone Lua 5.1 (which lacks the `bit` library and all WoW globals).
--
-- This is NOT a full WoW emulation. It provides just enough for the unit
-- specs to exercise algorithmic code (crypto, sanitization, cache LRU, etc.).
-- Anything frame/event/hook-related belongs in the in-game integration tests.

local M = {}

-- ===================== bit library (32-bit) =====================
-- Standalone Lua 5.1 has no `bit`. WoW's client provides LuaJIT's bit lib.
-- Implement the operations SPVP crypto uses: bxor, band. Pure-Lua, 32-bit.
if not _G.bit then
    -- LuaJIT's bit ops truncate operands to int32 first. We must replicate that,
    -- including for products like (hash * FNV_prime) that exceed 2^53 where the
    -- naive bit-by-bit loop would lose precision. Reduce mod 2^32 up front, and
    -- decompose into 16-bit halves so intermediate products stay exact.
    local TWO32 = 4294967296  -- 2^32

    local function tobits(n)
        n = n % TWO32
        if n < 0 then n = n + TWO32 end
        return math.floor(n)
    end

    -- Apply a 16-bit boolean op across both halves of two 32-bit numbers.
    local function bitop(a, b, op)
        a, b = tobits(a), tobits(b)
        local ah, al = math.floor(a / 65536), a % 65536
        local bh, bl = math.floor(b / 65536), b % 65536

        local function half(x, y)
            local res, p = 0, 1
            for _ = 1, 16 do
                local xb, yb = x % 2, y % 2
                if op(xb, yb) == 1 then res = res + p end
                x = (x - xb) / 2
                y = (y - yb) / 2
                p = p * 2
            end
            return res
        end

        return half(ah, bh) * 65536 + half(al, bl)
    end

    local bit = {}
    bit.band = function(a, b) return bitop(a, b, function(x, y) return (x == 1 and y == 1) and 1 or 0 end) end
    bit.bor  = function(a, b) return bitop(a, b, function(x, y) return (x == 1 or y == 1) and 1 or 0 end) end
    bit.bxor = function(a, b) return bitop(a, b, function(x, y) return (x ~= y) and 1 or 0 end) end

    _G.bit = bit
end

-- ===================== Time =====================
-- Controllable clock so tests can advance time deterministically.
M.clock = 0
local function now() return M.clock end
M.advance = function(seconds) M.clock = M.clock + seconds end
M.setClock = function(t) M.clock = t end

_G.GetTime = now
_G.GetTimePreciseSec = now
_G.time = function() return math.floor(now()) + 1700000000 end  -- plausible epoch
_G.debugprofilestop = function() return now() * 1000 end

-- ===================== Misc WoW globals =====================
_G.UnitGUID = function() return "Player-1234-ABCDEF01" end
_G.UnitName = function() return "TestPlayer" end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.UnitRace = function() return "Human", "Human" end
_G.UnitSex = function() return 2 end
_G.UnitFactionGroup = function() return "Alliance" end
_G.GetCursorPosition = function() return 100, 200 end
_G.GetFramerate = function() return 60 end

-- WoW exposes Lua's os.date as a bare `date` global. spvp_auto_init formats a salt's
-- generation timestamp with it; absent here only because no spec had reached that line.
_G.date = os.date

-- WoW's table-clearing global. Production uses it in CacheService, HistoryService and
-- msp_exchange; it was absent here only because no spec had reached one of those lines yet.
_G.wipe = function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end
_G.table.wipe = _G.wipe

-- Addon memory profiling. HistoryService:RecordPerformance calls these whenever
-- performanceHistoryEnabled is set, so they must exist for that path to be testable.
M.addonMemoryKB = 512
_G.UpdateAddOnMemoryUsage = function() end
_G.GetAddOnMemoryUsage = function() return M.addonMemoryKB end

-- ===================== Frames =====================
-- Minimal frame stub. Some modules build an event frame at file scope (e.g.
-- location/maps.lua's CHAT_MSG_ADDON listener), so CreateFrame has to exist merely to
-- load them; specs then need to drive the captured handler, hence Fire(). Unknown frame
-- methods degrade to no-ops rather than erroring - frames collect a lot of incidental
-- layout calls that specs don't care about.
M.frames = {}

local FRAME_METHODS = {}
function FRAME_METHODS:RegisterEvent(event) self.events[event] = true end
function FRAME_METHODS:UnregisterEvent(event) self.events[event] = nil end
function FRAME_METHODS:UnregisterAllEvents() self.events = {} end
function FRAME_METHODS:IsEventRegistered(event) return self.events[event] == true end
function FRAME_METHODS:SetScript(name, fn) self.scripts[name] = fn end
function FRAME_METHODS:GetScript(name) return self.scripts[name] end
function FRAME_METHODS:Show() self.shown = true end
function FRAME_METHODS:Hide() self.shown = false end
function FRAME_METHODS:IsShown() return self.shown end
-- Real IsVisible also walks the parent chain; shown-state is enough for specs, and returning
-- a real boolean matters: production guards like `if not content:IsVisible() then return end`
-- would otherwise always bail, making a render-loop spec pass vacuously.
function FRAME_METHODS:IsVisible() return self.shown end

-- Replay an event through this frame's OnEvent handler the way the client would.
function FRAME_METHODS:Fire(event, ...)
    if self.scripts.OnEvent then self.scripts.OnEvent(self, event, ...) end
end

-- Names that are CHILD FRAME REFERENCES on real widgets, not methods. The catch-all below
-- cannot tell a method call from a field read, so without this an `if frame.ScrollBar then`
-- guard sees the no-op function, passes, and then indexes it -- production code that correctly
-- guards for an absent child would fail only under the mock. Real WoW returns a frame or nil;
-- nil is the honest stand-in here.
local FRAME_FIELDS = {
    ScrollBar = true, ScrollChild = true, Text = true, Icon = true,
    NormalTexture = true, Left = true, Right = true, Middle = true,
}

-- Regions (FontStrings / Textures). Real widgets return an OBJECT from CreateFontString and
-- CreateTexture; the catch-all below returns a no-op function, so `local cap =
-- card:CreateFontString(...)` used to yield nil and the next `cap:SetPoint(...)` blew up.
-- That is why no spec could drive a real UI render loop.
--
-- These carry just enough state for assertions: text, shown, and the width/height a caller
-- explicitly set. Everything else degrades to a no-op like frames do.
local REGION_METHODS = {}
function REGION_METHODS:SetText(t) self.text = t end
function REGION_METHODS:GetText() return self.text end
function REGION_METHODS:Show() self.shown = true end
function REGION_METHODS:Hide() self.shown = false end
function REGION_METHODS:IsShown() return self.shown end
function REGION_METHODS:SetWidth(w) self.width = w end
function REGION_METHODS:GetWidth() return self.width or 0 end
function REGION_METHODS:SetHeight(h) self.height = h end
function REGION_METHODS:GetHeight() return self.height or 0 end
function REGION_METHODS:GetStringWidth() return #(self.text or "") * 6 end

local regionMeta = {
    __index = function(_, key)
        return REGION_METHODS[key] or function() end
    end
}

M.regions = {}
local function newRegion(kind)
    local r = setmetatable({ regionKind = kind, shown = true }, regionMeta)
    table.insert(M.regions, r)
    return r
end

function FRAME_METHODS:CreateFontString() return newRegion("FontString") end
function FRAME_METHODS:CreateTexture() return newRegion("Texture") end
function FRAME_METHODS:CreateMaskTexture() return newRegion("MaskTexture") end

local frameMeta = {
    __index = function(_, key)
        if FRAME_FIELDS[key] then return nil end
        return FRAME_METHODS[key] or function() end
    end
}

_G.CreateFrame = function(frameType, name)
    local f = setmetatable({
        frameType = frameType, frameName = name,
        events = {}, scripts = {}, shown = false,
    }, frameMeta)
    table.insert(M.frames, f)
    return f
end

-- The most recently created frame - how a spec gets hold of a module-scoped event frame
-- it never receives a reference to.
M.lastFrame = function() return M.frames[#M.frames] end

-- C_Timer: run the callback synchronously-deferred queue (tests can flush).
M.timers = {}
_G.C_Timer = {
    After = function(delay, fn) table.insert(M.timers, {at = now() + delay, fn = fn}) end,
    NewTimer = function(delay, fn)
        local t = {at = now() + delay, fn = fn, cancelled = false}
        table.insert(M.timers, t)
        return { Cancel = function() t.cancelled = true end }
    end,
    NewTicker = function(_, _) return { Cancel = function() end } end,
}
M.flushTimers = function()
    for _, t in ipairs(M.timers) do
        if not t.cancelled and now() >= t.at then t.fn() end
    end
    M.timers = {}
end

-- Addon message capture (SPVP sends via C_ChatInfo.SendAddonMessage)
M.sentMessages = {}
_G.C_ChatInfo = {
    SendAddonMessage = function(prefix, msg, channel, target)
        table.insert(M.sentMessages, {prefix = prefix, msg = msg, channel = channel, target = target})
    end,
    RegisterAddonMessagePrefix = function() return true end,
}

-- Slash command registry. commands.lua assigns SLASH_TRP3FW1 and
-- SlashCmdList.TRP3FW at file scope, so the table must exist merely to load it;
-- specs then invoke SlashCmdList.TRP3FW(msg) to drive a real command.
_G.SlashCmdList = _G.SlashCmdList or {}

-- Zone/location globals read by the `location` and `phasecheck` commands.
M.zone = "Elwynn Forest"
M.subZone = ""
M.minimapZone = ""
_G.GetRealZoneText = function() return M.zone end
_G.GetZoneText = function() return M.zone end
_G.GetSubZoneText = function() return M.subZone end
_G.GetMinimapZoneText = function() return M.minimapZone end

-- No Epsilon API by default (tests opt in by setting _G.C_Epsilon)
_G.C_Epsilon = nil

return M
