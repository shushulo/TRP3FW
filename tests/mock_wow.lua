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

-- No Epsilon API by default (tests opt in by setting _G.C_Epsilon)
_G.C_Epsilon = nil

return M
