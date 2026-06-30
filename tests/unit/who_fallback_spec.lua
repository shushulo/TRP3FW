-- tests/unit/who_fallback_spec.lua
-- Behavioral test for CheckPlayerViaWho's map-fallback classification (#7):
-- technical WHO failures should trigger a map-scan rescue; legitimate
-- negatives and bad-input failures should not.

local T = require("tests.framework")
local H = require("tests.harness")

local TRP3FW = H.newNamespace()
TRP3FW.Prefs = {}
TRP3FW.hasEpsilonAPI = true

-- Stubs for the deps TryMapFallbackForWho / CheckPlayerViaWho touch.
TRP3FW.CacheInterface = nil  -- forces map-scan path (no cache entries)
function TRP3FW:GetCurrentMapID() return 1519 end
function TRP3FW:IsMapCheckEnabled() return true end

-- A controllable WhoService whose CheckPlayer invokes the callback with a chosen source.
TRP3FW.ServiceContainer = {
    _svc = {},
    Get = function(self, name) return self._svc[name] end,
    Register = function(self, s) self._svc[s.name or "?"] = s end,
}
local fakeWho = { name = "WhoService" }
function fakeWho:CheckPlayer(playerName, sendId, cb, trackStats, forceName, priority)
    cb(self._nextFound, self._nextSource)
end
TRP3FW.ServiceContainer._svc.WhoService = fakeWho

-- Track whether the map-scan fallback was invoked.
local mapScanCalled
function TRP3FW:MapScan(name, sendId, cb, priority)
    mapScanCalled = true
    if cb then cb(false, "timeout", 0) end
end

H.loadModule("location/who.lua", TRP3FW)

-- Helper: drive one CheckPlayerViaWho with a given (found, source) and report
-- whether MapScan got called.
local function fallbackFiredFor(found, source)
    mapScanCalled = false
    fakeWho._nextFound = found
    fakeWho._nextSource = source
    TRP3FW:CheckPlayerViaWho("Target", 1, function() end, true, false, "NORMAL")
    return mapScanCalled
end

T.describe("WHO map-fallback triggers on technical failures", function()
    -- These are the actual source strings WhoService / RunPrivilegedSafe emit.
    -- The pre-#7 code checked for "error"/"full" which never matched these.
    T.it("fires for timeout", function() T.truthy(fallbackFiredFor(false, "timeout")) end)
    T.it("fires for rate_limit", function() T.truthy(fallbackFiredFor(false, "rate_limit")) end)
    T.it("fires for execution_error", function() T.truthy(fallbackFiredFor(false, "execution_error")) end)
    T.it("fires for queue_full", function() T.truthy(fallbackFiredFor(false, "queue_full")) end)
    T.it("fires for api_error", function() T.truthy(fallbackFiredFor(false, "api_error")) end)
    T.it("fires for api_unavailable", function() T.truthy(fallbackFiredFor(false, "api_unavailable")) end)
end)

T.describe("WHO map-fallback does NOT fire for non-technical results", function()
    T.it("skips a successful lookup", function() T.falsy(fallbackFiredFor(true, "who_query")) end)
    T.it("skips a legitimate not-found", function() T.falsy(fallbackFiredFor(false, "who_query")) end)
    T.it("skips a zone-complete negative", function() T.falsy(fallbackFiredFor(false, "cached_zone_complete")) end)
    T.it("skips bad-input failures", function() T.falsy(fallbackFiredFor(false, "invalid_name")) end)
    T.it("does not crash on a nil source", function()
        T.no_raise(function() fallbackFiredFor(false, nil) end)
    end)
end)

return T
