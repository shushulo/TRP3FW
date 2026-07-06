-- tests/unit/complexity_preserve_spec.lua
-- Regression: changing the UI complexity level must NOT alter stored setting
-- values. EnforceComplexityDefaults used to reset every above-level setting to
-- its default when complexity was lowered, silently discarding the user's
-- configured values. It is now a no-op; this locks that behavior.

local T = require("tests.framework")
local H = require("tests.harness")

local TRP3FW = H.newNamespace()

-- settings.lua defines StaticPopupDialogs entries at load; stub the table. It
-- has no CreateFrame at file scope (those live inside InitializeUI), so the
-- file loads with just this global plus the namespace.
_G.StaticPopupDialogs = _G.StaticPopupDialogs or {}
_G.CopyTable = _G.CopyTable or function(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end

H.loadModule("ui/settings.lua", TRP3FW)

T.describe("EnforceComplexityDefaults", function()
    T.it("does not reset above-level settings when complexity is lowered", function()
        -- Give a couple of settings non-default, user-configured values.
        TRP3FW.defaultSettings = { spvpBlockDuration = 60, cacheSizeLimit = 1000 }
        TRP3FW.Prefs.spvpBlockDuration = 300   -- user changed it (Advanced setting)
        TRP3FW.Prefs.cacheSizeLimit = 5000     -- user changed it (Advanced setting)

        -- Lowering to Basic (1) previously reset both to defaults.
        TRP3FW:EnforceComplexityDefaults(1)

        T.eq(TRP3FW.Prefs.spvpBlockDuration, 300, "block duration preserved")
        T.eq(TRP3FW.Prefs.cacheSizeLimit, 5000, "cache size preserved")
    end)

    T.it("is safe to call with no defaults / prefs set", function()
        T.no_raise(function() TRP3FW:EnforceComplexityDefaults(2) end)
    end)
end)

return T
