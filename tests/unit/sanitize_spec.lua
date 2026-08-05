-- tests/unit/sanitize_spec.lua
-- Headless tests for SecurityService name sanitization.
-- Guards the SANITIZE_NAME_PATTERN fix (accented names accepted, digits rejected).

local T = require("tests.framework")
local H = require("tests.harness")

local TRP3FW = H.newNamespace()
_G.TRP3FW_ValidatedNames = {}
TRP3FW.hasEpsilonAPI = false

-- SecurityService is a service: load its base class + container + cache first.
H.loadModule("core/Service.lua", TRP3FW)
H.loadModule("core/ServiceContainer.lua", TRP3FW)
H.loadModule("core/cache_interface.lua", TRP3FW)
H.loadModule("features/services/SecurityService.lua", TRP3FW)

local svc = TRP3FW.ServiceContainer:Get("SecurityService")

-- UTF-8 helpers for accented names (high bytes)
local Bjorn = "Bj\195\182rn"      -- Björn
local Zephyr = "Z\195\169phyr"    -- Zéphyr

T.describe("SecurityService:SanitizePlayerName", function()
    T.it("accepts plain ASCII names", function()
        T.eq(svc:SanitizePlayerName("Bob"), "Bob")
    end)

    T.it("accepts accented (high-byte) names", function()
        -- The bug: \128-%255 range was malformed and rejected these outright
        -- (the CleanPlayerName fallback could rescue, but the primary path failed).
        T.not_nil(svc:SanitizePlayerName(Bjorn), "Björn should sanitize")
        T.not_nil(svc:SanitizePlayerName(Zephyr), "Zéphyr should sanitize")
    end)

    T.it("accepts names containing digits", function()
        -- Regression: this spec used to assert digits were REJECTED, which pinned the side
        -- effect of the old malformed "\128-%255" range rather than a real naming rule.
        -- Epsilon allows digits, and rejecting them fails closed at the Chomp hook - the
        -- live report was "Fallywix 420-Apertus" being blocked outright.
        T.not_nil(svc:SanitizePlayerName("Bob2"), "digit names must be accepted")
        T.not_nil(svc:SanitizePlayerName("Player5"), "digit names must be accepted")
        -- The exact reported name: digits behind a space, plus a realm suffix.
        T.not_nil(svc:SanitizePlayerName("Fallywix 420-Apertus"), "reported name must sanitize")
    end)

    T.it("still rejects injection metacharacters despite the digit widening", function()
        -- %w widened the class to alphanumerics only; punctuation that could escape the
        -- TargetUnit("<name>") string context must remain outside the whitelist.
        T.is_nil(svc:SanitizePlayerName("Bob;evil"), "semicolons must stay rejected")
        T.is_nil(svc:SanitizePlayerName("Bob)evil"), "parens must stay rejected")
    end)

    T.it("accepts apostrophes and single hyphen", function()
        T.not_nil(svc:SanitizePlayerName("Bob'Lightbringer"))
        -- single hyphen ok; Epsilon strips realm so result is the base name
        T.not_nil(svc:SanitizePlayerName("Bob-Stormwind"))
    end)

    T.it("rejects names with control characters", function()
        T.is_nil(svc:SanitizePlayerName("Bob\0evil"))
        T.is_nil(svc:SanitizePlayerName("Bob\nNewline"))
    end)

    T.it("rejects oversized and too-short names", function()
        T.is_nil(svc:SanitizePlayerName(string.rep("A", 60)))
        T.is_nil(svc:SanitizePlayerName("A"))
    end)

    T.it("rejects non-string input without crashing", function()
        T.no_raise(function() svc:SanitizePlayerName(nil) end)
        T.no_raise(function() svc:SanitizePlayerName(12345) end)
        T.is_nil(svc:SanitizePlayerName(nil))
    end)

    T.it("escapes injection metacharacters in output", function()
        -- Quotes/backslashes that survive the whitelist are escaped (not present in
        -- a normal name, but the escaping path must not crash).
        T.no_raise(function() svc:SanitizePlayerName("Bob") end)
    end)
end)

T.describe("SecurityService:CleanPlayerName", function()
    T.it("strips the realm suffix", function()
        T.eq(svc:CleanPlayerName("Bob-Stormwind"), "Bob")
    end)

    T.it("accepts accented names via the clean path too", function()
        T.not_nil(svc:CleanPlayerName(Bjorn))
    end)

    T.it("accepts digit-containing names and strips the realm", function()
        -- This is the exact path that emitted "[Chomp Hook] Unparseable target name
        -- (Fallywix 420-Apertus); blocking send rather than transmitting ungated".
        T.eq(svc:CleanPlayerName("Fallywix 420-Apertus"), "Fallywix 420")
        T.eq(svc:CleanPlayerName("Bob2-Stormwind"), "Bob2")
    end)

    T.it("rejects control chars and bad lengths", function()
        T.is_nil(svc:CleanPlayerName("A"))
        T.is_nil(svc:CleanPlayerName("Bob\0"))
        T.no_raise(function() svc:CleanPlayerName(nil) end)
    end)
end)

return T
