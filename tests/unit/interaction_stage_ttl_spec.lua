-- tests/unit/interaction_stage_ttl_spec.lua
-- Headless tests for features/stages/InteractionStage.lua's interaction-cache TTL gate
-- (context.settings.interactionCacheDuration, defaulting to 600). A fresh cached
-- interaction (mouseover/target/mutual-exchange recorded earlier) lets a sender skip all
-- location checks entirely; like every other TTL-gated cache in this codebase, a stale
-- entry must fall through to the real checks (handled = false), not be trusted forever.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW()
    local fw = H.newNamespace()
    fw.Prefs = {}

    H.loadModule("core/cache_interface.lua", fw)
    fw.CacheInterface:Register("interaction", {})
    H.loadModule("core/Stage.lua", fw)

    fw.ServiceContainer = { Get = function() return nil end }  -- no HistoryService/NotificationService needed
    function fw:IsUserInitiatedExchange() return false end
    function fw:TrackAddonRequest() end
    function fw:ProcessBurstAllows() end
    function fw:CleanPlayerName(n) return n end

    -- No live mouseover/target interaction by default - tests exercise the CACHED path.
    _G.UnitIsPlayer = function() return false end
    _G.UnitIsUnit = function() return false end
    _G.UnitName = function() return nil end

    H.loadModule("features/stages/InteractionStage.lua", fw)
    return fw
end

local function ctx(fw, playerName, settings)
    return {
        playerName = playerName, addon = "MSP", sendId = 1, isWhisper = true,
        settings = settings or {}, now = mock.clock,
        originalFunc = function() end, originalArgs = {},
    }
end

T.describe("InteractionStage interaction-cache TTL", function()
    T.it("hits (handled=true) on a fresh cached interaction", function()
        mock.setClock(1000)
        local fw = freshFW()
        fw.CacheInterface:Set("interaction", "Bob", { timestamp = 990, zone = "TestZone" })  -- 10s old

        local result = fw.InteractionStage:Process(ctx(fw, "Bob", { interactionCacheDuration = 600 }))

        T.truthy(result.handled)
        T.truthy(result.allowed)
        T.eq(result.reason, "interaction_cache")
    end)

    T.it("BOUNDARY: treats the entry as expired at exactly the TTL (age >= ttl, not just >)", function()
        mock.setClock(1000)
        local fw = freshFW()
        fw.CacheInterface:Set("interaction", "Bob", { timestamp = 400, zone = "TestZone" })  -- exactly 600s old

        local result = fw.InteractionStage:Process(ctx(fw, "Bob", { interactionCacheDuration = 600 }))

        T.falsy(result.handled, "age == ttl must not be treated as a cache hit")
    end)

    T.it("a STALE interaction cache entry falls through (handled=false)", function()
        mock.setClock(1000)
        local fw = freshFW()
        fw.CacheInterface:Set("interaction", "Bob", { timestamp = 300, zone = "TestZone" })  -- 700s old

        local result = fw.InteractionStage:Process(ctx(fw, "Bob", { interactionCacheDuration = 600 }))

        T.falsy(result.handled, "stale entry must fall through so the real checks run")
    end)

    T.it("falls through cleanly when there is no cached entry at all", function()
        mock.setClock(1000)
        local fw = freshFW()

        local result = fw.InteractionStage:Process(ctx(fw, "NeverInteracted", { interactionCacheDuration = 600 }))

        T.falsy(result.handled)
    end)

    T.it("just inside the boundary (age = ttl - 1) still hits", function()
        mock.setClock(1000)
        local fw = freshFW()
        fw.CacheInterface:Set("interaction", "Bob", { timestamp = 401, zone = "TestZone" })  -- 599s old

        local result = fw.InteractionStage:Process(ctx(fw, "Bob", { interactionCacheDuration = 600 }))

        T.truthy(result.handled)
        T.truthy(result.allowed)
    end)

    T.it("uses the default 600s TTL when settings.interactionCacheDuration is not set", function()
        mock.setClock(1000)
        local fw = freshFW()
        fw.CacheInterface:Set("interaction", "Bob", { timestamp = 401, zone = "TestZone" })  -- 599s old

        local result = fw.InteractionStage:Process(ctx(fw, "Bob", {}))

        T.truthy(result.handled, "default TTL (600) should still be honored via the settings fallback")
    end)

    T.it("clears a mismatched-zone cached entry regardless of age (existing invalidation, unaffected by TTL fix)", function()
        mock.setClock(1000)
        local fw = freshFW()
        fw.currentZoneName = "OtherZone"
        fw.CacheInterface:Set("interaction", "Bob", { timestamp = 999, zone = "TestZone" })  -- fresh but wrong zone

        local result = fw.InteractionStage:Process(ctx(fw, "Bob", { interactionCacheDuration = 600 }))

        T.falsy(result.handled, "zone mismatch invalidates the entry before the TTL check even runs")
    end)
end)

return T
