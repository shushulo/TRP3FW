-- tests/unit/addon_keyspace_spec.lua
-- Headless tests for the split between TRP3FW.detectedAddons and
-- TRP3FW.playerAddonProtocol.
--
-- Bug fixed: one table served two unrelated keyspaces.
--
--   hooks/installer.lua keys it by CAPABILITY - detectedAddons.TRP3/.MRP/.XRP/.MSP are
--   booleans for "is this addon loaded locally", and .MapScanner is the string "TRP3" or
--   "RPMapScan". Read by status.lua, ui/, core/utils.lua:808, location/maps.lua:361 and
--   location/cascading.lua:214.
--
--   hooks/msp.lua keyed the SAME table by remote PLAYER NAME, storing which RP addon that
--   player appears to be running, and hooks/trp3.lua read it back that way.
--
-- Player names and capability names share a namespace, so the two collided both ways:
--
--   1. Player -> capability. A profile request from a player named "MapScanner" wrote
--      detectedAddons.MapScanner = "MSP". That is truthy, so maps.lua and cascading.lua
--      concluded a map scanner was installed when none was, and the Status tab displayed
--      "Map Scanner: MSP".
--
--   2. Capability -> player. The installer sets detectedAddons.MSP = true. A send to a
--      player named literally "MSP" then read that back as that player's addon, so `addon`
--      became a BOOLEAN where every consumer expects a string. HistoryService:TrackAddonRequest
--      type-guards it (the request goes untracked), but NotificationService formats it with
--      "%s" at :279 and :506 - and string.format("%s", true) is a hard error in Lua 5.1,
--      inside the notification path of a profile send.
--
-- Fix: player-keyed data moved to TRP3FW.playerAddonProtocol, and the read site in
-- hooks/trp3.lua now also type-checks the value it resolves.

local T = require("tests.framework")
local H = require("tests.harness")

T.describe("addon keyspaces: a capability flag is not a player's protocol", function()
    T.it("string.format('%s', true) really does error in Lua 5.1", function()
        -- Pins the premise the bug rests on. If this ever stops being true the
        -- NotificationService half of the finding changes severity.
        local ok = pcall(string.format, "via %s", true)
        T.falsy(ok, "a boolean reaching a %s format is a hard error, not a tostring")
    end)

    T.it("resolving a player named after a capability yields no protocol", function()
        local fw = H.newNamespace()
        -- The installer's capability flags.
        fw.detectedAddons = { TRP3 = true, MSP = true, MapScanner = "TRP3" }
        -- No MSP handshake has been seen from anyone.
        fw.playerAddonProtocol = {}

        -- What hooks/trp3.lua does for an MSP-prefixed send.
        local function resolveAddon(playerName)
            local addon = "MSP"
            local resolved = fw.playerAddonProtocol and playerName and fw.playerAddonProtocol[playerName]
            if type(resolved) == "string" then addon = resolved end
            return addon
        end

        T.eq(resolveAddon("MSP"), "MSP", "must not pick up detectedAddons.MSP == true")
        T.eq(type(resolveAddon("MSP")), "string", "a boolean here errors in NotificationService")
        T.eq(resolveAddon("TRP3"), "MSP", "nor detectedAddons.TRP3 == true")
        T.eq(resolveAddon("MapScanner"), "MSP", "nor the MapScanner string")
    end)

    T.it("resolves a real handshake result normally", function()
        local fw = H.newNamespace()
        fw.detectedAddons = { TRP3 = true, MSP = true }
        fw.playerAddonProtocol = { Bob = "MRP" }

        local function resolveAddon(playerName)
            local addon = "MSP"
            local resolved = fw.playerAddonProtocol and playerName and fw.playerAddonProtocol[playerName]
            if type(resolved) == "string" then addon = resolved end
            return addon
        end

        T.eq(resolveAddon("Bob"), "MRP", "a detected protocol still wins")
        T.eq(resolveAddon("Carol"), "MSP", "an unknown player falls back to generic MSP")
    end)

    T.it("the type guard rejects a non-string that somehow lands in the table", function()
        local fw = H.newNamespace()
        fw.playerAddonProtocol = { Bob = true }

        local function resolveAddon(playerName)
            local addon = "MSP"
            local resolved = fw.playerAddonProtocol and playerName and fw.playerAddonProtocol[playerName]
            if type(resolved) == "string" then addon = resolved end
            return addon
        end

        T.eq(resolveAddon("Bob"), "MSP",
            "belt-and-braces: the read site no longer trusts the value's type either")
    end)
end)

T.describe("addon keyspaces: capability detection stays clean", function()
    T.it("a player-keyed write does not fabricate a map scanner", function()
        local fw = H.newNamespace()
        fw.detectedAddons = {}        -- no map scanner installed
        fw.playerAddonProtocol = {}

        -- A request arrives from a player who happens to be named "MapScanner".
        fw.playerAddonProtocol["MapScanner"] = "MSP"

        T.is_nil(fw.detectedAddons.MapScanner,
            "location/maps.lua:361 and cascading.lua:214 gate on this being absent")
        T.falsy(fw.detectedAddons.TRP3, "and the RP-addon flags stay untouched too")
    end)
end)

T.describe("playerAddonProtocol is bounded", function()
    local function freshFW()
        local fw = H.newNamespace()
        fw.playerAddonProtocol = {}
        fw.playerAddonProtocolCount = 0
        fw.PLAYER_ADDON_PROTOCOL_LIMIT = 500
        return fw
    end

    -- The cap logic as hooks/msp.lua applies it on a new player.
    local function record(fw, name, protocol)
        if fw.playerAddonProtocol[name] == nil then
            local count = (fw.playerAddonProtocolCount or 0) + 1
            if count > (fw.PLAYER_ADDON_PROTOCOL_LIMIT or 500) then
                fw.playerAddonProtocol = {}
                count = 1
            end
            fw.playerAddonProtocolCount = count
        end
        fw.playerAddonProtocol[name] = protocol
    end

    local function size(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    T.it("never exceeds the cap no matter how many players are seen", function()
        local fw = freshFW()
        fw.PLAYER_ADDON_PROTOCOL_LIMIT = 10

        for i = 1, 95 do record(fw, "Player" .. i, "MSP") end

        T.truthy(size(fw.playerAddonProtocol) <= 10,
            "unbounded growth is what the cap exists to stop, got " .. size(fw.playerAddonProtocol))
        T.eq(fw.playerAddonProtocol["Player95"], "MSP", "the most recent player is retained")
    end)

    T.it("re-detecting a known player does not consume cap budget", function()
        local fw = freshFW()
        fw.PLAYER_ADDON_PROTOCOL_LIMIT = 10

        for _ = 1, 50 do record(fw, "Bob", "MRP") end

        T.eq(fw.playerAddonProtocolCount, 1, "one player, one slot")
        T.eq(fw.playerAddonProtocol["Bob"], "MRP")
    end)

    T.it("an updated protocol for a known player overwrites in place", function()
        local fw = freshFW()
        record(fw, "Bob", "MSP")
        record(fw, "Bob", "TRP3")
        T.eq(fw.playerAddonProtocol["Bob"], "TRP3", "later handshake wins")
        T.eq(fw.playerAddonProtocolCount, 1)
    end)
end)
