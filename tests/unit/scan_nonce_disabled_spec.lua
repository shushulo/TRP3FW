-- tests/unit/scan_nonce_disabled_spec.lua
-- Pins that scanResponseRequireNonce cannot break map checking, even when the pref is on.
--
-- The nonce verification is half-built. MapScan generates a per-scan nonce and stores it on
-- the activeScanCallbacks entry, but NOTHING EVER TRANSMITS IT:
--   * the scan request is TRP3's own MapScannersManager.launch("playerScan") broadcast, which
--     knows nothing about a TRP3FW nonce; and
--   * TRP3FW's own scan REPLY hook (hooks/trp3.lua) wraps TRP3's sendP2PMessage and forwards
--     unpack(args) verbatim, appending nothing.
-- So no responder -- not even another TRP3FW user -- can echo a nonce back. Every reply lands
-- in the "missing nonce" branch and every cached entry has verified = false.
--
-- With the pref ON that meant every scan reply was ignored, every mapScan/broadcast cache
-- entry read as invalid, and map checking failed SHUT. The pref, its checkbox and
-- `/trp3fw scanreply nonce` were all still reachable, so this was a live footgun.
--
-- Fix: every consumer now gates on TRP3FW:IsScanNonceVerificationAvailable(), which returns
-- false. These tests set the pref to TRUE deliberately -- that is the whole point. The
-- verification code is left intact (merely inert) for whenever the protocol work happens.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function fireDueTimers()
    for _, t in ipairs(mock.timers) do
        if not t.cancelled and not t.fired and t.at <= mock.clock then
            t.fired = true
            t.callback()
        end
    end
end

local function freshMaps()
    local fw = H.newNamespace()
    fw.Prefs = {
        scanCacheDuration = 120,
        scanCacheFailureDuration = 10,
        mapScanMinInterval = 60,
        -- The setting under test, deliberately ON.
        scanResponseRequireNonce = true,
    }
    fw.detectedAddons = { MapScanner = true }
    fw.sessionStats = { cacheStats = {
        mapCacheHits = 0, mapCacheMisses = 0,
        broadcastCacheHits = 0, broadcastCacheMisses = 0,
    } }
    fw.ServiceContainer = { Get = function() return nil end }

    H.loadModule("core/cache_interface.lua", fw)
    fw.CacheInterface:Register("mapScan", {})
    fw.CacheInterface:Register("broadcast", {})
    fw.CacheInterface:Register("mapName", {})

    function fw:IsMapCheckEnabled() return true end
    function fw:CleanPlayerName(n) return n end
    -- The real accessor lives in core/init.lua, which the maps spec does not load; mirror
    -- its hard-disabled contract here.
    function fw:IsScanNonceVerificationAvailable() return false end

    _G.C_Map = { GetBestMapForUnit = function() return 1 end, GetMapInfo = function() return { name = "TestZone" } end }
    _G.GetRealZoneText = function() return "TestZone" end
    _G.WorldMapFrame = nil
    _G.TRP3_API = nil
    _G.RPMapScan = nil
    _G.AddOn_TotalRP3 = nil

    mock.frames = {}
    mock.timers = {}
    H.loadModule("location/maps.lua", fw)
    return fw, mock.lastFrame()
end

T.describe("scanResponseRequireNonce cannot fail map checking shut", function()
    T.it("BUG (fixed): a nonce-less scan reply is still accepted with the pref ON", function()
        mock.setClock(1000)
        local fw, frame = freshMaps()

        local result
        fw:MapScan("Kara", 1, function(found, source) result = { found, source } end)

        -- A real reply: no nonce token, because nothing can produce one.
        frame:Fire("CHAT_MSG_ADDON", "RPB1", "RPB1~C_SCAN~0.5~0.5", "WHISPER", "Kara")

        T.not_nil(result, "the reply must not be ignored - it is the only kind that exists")
        T.eq(result[1], true, "the player was found and must be reported as found")
    end)

    T.it("BUG (fixed): the mapScan cache is still usable with the pref ON", function()
        mock.setClock(1000)
        local fw, frame = freshMaps()

        -- Populate the cache via a real reply.
        fw:MapScan("Kara", 1, function() end)
        frame:Fire("CHAT_MSG_ADDON", "RPB1", "RPB1~C_SCAN~0.5~0.5", "WHISPER", "Kara")

        local cached = fw.CacheInterface:Get("mapScan", "Kara")
        T.not_nil(cached, "sanity: the reply populated the cache")
        T.eq(cached.verified, false,
            "sanity: entries are ALWAYS unverified - nothing transmits a nonce to verify against")

        -- A second scan must be served from that cache rather than rejecting it as invalid.
        local result
        fw:MapScan("Kara", 2, function(found, source) result = { found, source } end)

        T.not_nil(result, "an unverified cache entry must still be usable")
        T.eq(result[1], true, "and must report the cached find")
    end)

    T.it("a genuine nonce MISMATCH is still rejected (verification code left intact)", function()
        mock.setClock(1000)
        local fw, frame = freshMaps()

        local result
        fw:MapScan("Kara", 1, function(found, source) result = { found, source } end)

        -- Fabricate a wrong nonce. The mismatch branch is independent of the strict-presence
        -- flag, so it must still reject - the feature is inert, not deleted.
        frame:Fire("CHAT_MSG_ADDON", "RPB1", "RPB1~C_SCAN~0.5~0.5~000000", "WHISPER", "Kara")

        T.is_nil(result, "a mismatched nonce must still be ignored")
    end)
end)

T.describe("IsScanNonceVerificationAvailable contract", function()
    T.it("reports unavailable, so no consumer can be gated on the raw pref", function()
        local fw = H.newNamespace()
        H.loadModule("core/init.lua", fw)
        T.falsy(fw:IsScanNonceVerificationAvailable(),
            "must stay false until something actually transmits the nonce")
    end)
end)
