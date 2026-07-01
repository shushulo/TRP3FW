-- tests/unit/utils_security_spec.lua
-- Headless tests for the security-critical helpers in core/utils.lua:
--   * SanitizeZoneName        - whitelist guard for WHO/RunPrivileged zone args
--   * CreateVerifiedSendId /   - HMAC-like sendId signing + spoof rejection
--     VerifySendId
--   * RunPrivilegedSafe        - token-bucket rate limiting for privileged calls
--   * ValidateSettings         - numeric bounds clamping back to defaults
--   * FormatTime               - duration formatting
--
-- These all live directly in utils.lua (no SecurityService delegation), so the
-- spec just needs the minimal namespace plus a few fields the functions read.

local T = require("tests.framework")
local H = require("tests.harness")

local TRP3FW = H.newNamespace()
TRP3FW.Prefs = {}
TRP3FW.sendIdSalt = 424242        -- fixed salt so signatures are deterministic
TRP3FW.hasEpsilonAPI = false      -- default off; opted into per-test below

H.loadModule("core/utils.lua", TRP3FW)
local mock = H.mock

-- ===================== SanitizeZoneName =====================

T.describe("SanitizeZoneName whitelist", function()
    T.it("accepts normal zone names", function()
        T.eq(TRP3FW:SanitizeZoneName("Stormwind City"), "Stormwind City")
        T.eq(TRP3FW:SanitizeZoneName("Ahn'Qiraj"), "Ahn'Qiraj")
        T.eq(TRP3FW:SanitizeZoneName("Dire Maul"), "Dire Maul")
    end)

    T.it("trims leading/trailing whitespace", function()
        T.eq(TRP3FW:SanitizeZoneName("  The Barrens  "), "The Barrens")
    end)

    T.it("rejects injection metacharacters", function()
        -- Semicolons/parens/quotes-as-code are the RunPrivileged injection vectors.
        T.is_nil(TRP3FW:SanitizeZoneName('Stormwind"); evil()'))
        T.is_nil(TRP3FW:SanitizeZoneName("Zone)"))
        T.is_nil(TRP3FW:SanitizeZoneName("a=b"))
    end)

    T.it("rejects the ]]-breakout payload used against the WHO zone query", function()
        -- WhoService builds z-"<zone>" inside a RunPrivileged [[...]] long-string. A zone
        -- name containing ]] would terminate the literal and inject code. The zone branch
        -- of WhoService:CheckPlayer now routes through SanitizeZoneName, which must reject
        -- brackets (they're outside the [%w%s'-] whitelist) so the fallback name query runs.
        T.is_nil(TRP3FW:SanitizeZoneName(']] print("pwned") --'))
        T.is_nil(TRP3FW:SanitizeZoneName('Zone]])'))
    end)

    T.it("rejects control characters", function()
        T.is_nil(TRP3FW:SanitizeZoneName("Zone\nName"))
        T.is_nil(TRP3FW:SanitizeZoneName("Zone\0"))
    end)

    T.it("rejects empty and oversized names", function()
        T.is_nil(TRP3FW:SanitizeZoneName(""))
        T.is_nil(TRP3FW:SanitizeZoneName(string.rep("A", 101)))
    end)

    T.it("rejects excessive special chars (abuse guard)", function()
        T.is_nil(TRP3FW:SanitizeZoneName("a'b'c'd'e"))   -- >3 apostrophes
        T.is_nil(TRP3FW:SanitizeZoneName("a-b-c-d-e"))    -- >3 hyphens
    end)

    T.it("is nil-safe / non-string-safe", function()
        T.no_raise(function() TRP3FW:SanitizeZoneName(nil) end)
        T.is_nil(TRP3FW:SanitizeZoneName(nil))
        T.is_nil(TRP3FW:SanitizeZoneName(12345))
    end)
end)

-- ===================== sendId signing =====================

T.describe("CreateVerifiedSendId / VerifySendId", function()
    T.it("a freshly created sendId verifies", function()
        local s = TRP3FW:CreateVerifiedSendId()
        T.truthy(TRP3FW:VerifySendId(s))
    end)

    T.it("ids increment monotonically", function()
        local a = TRP3FW:CreateVerifiedSendId()
        local b = TRP3FW:CreateVerifiedSendId()
        T.eq(b.id, a.id + 1)
    end)

    T.it("rejects a tampered signature", function()
        local s = TRP3FW:CreateVerifiedSendId()
        s.signature = s.signature + 1
        T.falsy(TRP3FW:VerifySendId(s))
    end)

    T.it("rejects a tampered id (signature no longer matches)", function()
        local s = TRP3FW:CreateVerifiedSendId()
        s.id = s.id + 1000
        T.falsy(TRP3FW:VerifySendId(s))
    end)

    T.it("rejects non-table and missing-field inputs", function()
        T.falsy(TRP3FW:VerifySendId(nil))
        T.falsy(TRP3FW:VerifySendId("nope"))
        T.falsy(TRP3FW:VerifySendId({ id = 1 }))  -- missing timestamp/signature
    end)

    T.it("a sendId from a different salt does not verify here", function()
        -- Simulate a forger who guessed the structure but not the salt.
        local forged = { id = 5, timestamp = TRP3FW:GetCurrentTime(), signature = 12345 }
        T.falsy(TRP3FW:VerifySendId(forged))
    end)
end)

-- ===================== RunPrivilegedSafe token bucket =====================

T.describe("RunPrivilegedSafe rate limiting", function()
    -- Build an isolated namespace per describe so token state doesn't leak.
    local function freshEpsilon()
        local fw = H.newNamespace()
        fw.Prefs = {}
        fw.hasEpsilonAPI = true
        H.loadModule("core/utils.lua", fw)
        return fw
    end

    T.it("fails closed when the Epsilon API is unavailable", function()
        local fw = H.newNamespace(); fw.Prefs = {}; fw.hasEpsilonAPI = false
        H.loadModule("core/utils.lua", fw)
        local ok, reason = fw:RunPrivilegedSafe("print(1)", "who_name_query")
        T.falsy(ok)
        T.eq(reason, "api_unavailable")
    end)

    T.it("rejects non-string and oversized code", function()
        local fw = freshEpsilon()
        local _, r1 = fw:RunPrivilegedSafe(nil, "who_name_query")
        T.eq(r1, "invalid_code")
        local _, r2 = fw:RunPrivilegedSafe(string.rep("x", 1001), "who_name_query")
        T.eq(r2, "code_too_long")
    end)

    T.it("executes and consumes a token on success", function()
        mock.setClock(1000)
        local ran = false
        _G.C_Epsilon = { RunPrivileged = function() ran = true end }
        local fw = freshEpsilon()
        local ok = fw:RunPrivilegedSafe("noop()", "who_name_query")  -- HIGH priority
        T.truthy(ok)
        T.truthy(ran)
        T.eq(fw.privilegedCallStats.total, 1)
        _G.C_Epsilon = nil
    end)

    T.it("blocks once the bucket is drained (rate_limit)", function()
        mock.setClock(2000)  -- freeze clock so no refill happens between calls
        _G.C_Epsilon = { RunPrivileged = function() end }
        local fw = freshEpsilon()
        -- HIGH priority can use the full bucket of 10 tokens.
        local lastReason
        for _ = 1, 10 do
            local _, reason = fw:RunPrivilegedSafe("noop()", "who_name_query")
            lastReason = reason
        end
        -- 11th call: bucket empty -> blocked.
        local ok, reason = fw:RunPrivilegedSafe("noop()", "who_name_query")
        T.falsy(ok)
        T.eq(reason, "rate_limit")
        T.truthy(fw.privilegedCallStats.blocked >= 1)
        _G.C_Epsilon = nil
    end)

    T.it("NORMAL priority cannot spend the reserved tokens", function()
        mock.setClock(3000)
        _G.C_Epsilon = { RunPrivileged = function() end }
        local fw = freshEpsilon()
        -- NORMAL can't use reserved (2). Effective budget = 10 - 2 = 8 calls.
        for _ = 1, 8 do
            T.truthy(fw:RunPrivilegedSafe("noop()", "who_zone_query"))
        end
        local ok, reason = fw:RunPrivilegedSafe("noop()", "who_zone_query")
        T.falsy(ok, "9th NORMAL call should be blocked by reserved-token floor")
        T.eq(reason, "rate_limit")
        -- ...but a HIGH-priority call can still dip into the reserved pool.
        T.truthy(fw:RunPrivilegedSafe("noop()", "who_name_query"))
        _G.C_Epsilon = nil
    end)

    T.it("refills tokens as time passes", function()
        mock.setClock(4000)
        _G.C_Epsilon = { RunPrivileged = function() end }
        local fw = freshEpsilon()
        for _ = 1, 10 do fw:RunPrivilegedSafe("noop()", "who_name_query") end
        T.falsy(fw:RunPrivilegedSafe("noop()", "who_name_query"))  -- drained
        mock.setClock(4001)  -- 1s later -> +10 tokens
        T.truthy(fw:RunPrivilegedSafe("noop()", "who_name_query"))
        _G.C_Epsilon = nil
    end)
end)

-- ===================== GetCategoryPriority =====================

T.describe("GetCategoryPriority", function()
    T.it("maps known categories to their tier", function()
        T.eq((TRP3FW:GetCategoryPriority("who_name_query")), "HIGH")
        T.eq((TRP3FW:GetCategoryPriority("who_zone_query")), "NORMAL")
        T.eq((TRP3FW:GetCategoryPriority("phase_check_target_low")), "LOW")
    end)

    T.it("defaults unknown categories to NORMAL", function()
        T.eq((TRP3FW:GetCategoryPriority("totally_made_up")), "NORMAL")
    end)
end)

-- ===================== ValidateSettings =====================

T.describe("ValidateSettings bounds clamping", function()
    T.it("resets out-of-range numeric settings to the documented default", function()
        local fw = H.newNamespace()
        fw.defaultSettings = { suppressionTime = 30, cacheSizeLimit = 1000 }
        fw.Prefs = { suppressionTime = 999999, cacheSizeLimit = 1000 }
        H.loadModule("core/utils.lua", fw)
        fw:ValidateSettings()
        T.eq(fw.Prefs.suppressionTime, 30, "over-max reset to default")
        T.eq(fw.Prefs.cacheSizeLimit, 1000, "in-range value untouched")
    end)

    T.it("resets non-numeric values too", function()
        local fw = H.newNamespace()
        fw.defaultSettings = { phaseCacheDuration = 300 }
        fw.Prefs = { phaseCacheDuration = "not a number" }
        H.loadModule("core/utils.lua", fw)
        fw:ValidateSettings()
        T.eq(fw.Prefs.phaseCacheDuration, 300)
    end)

    T.it("is a no-op when Prefs is absent", function()
        local fw = H.newNamespace()
        fw.Prefs = nil
        H.loadModule("core/utils.lua", fw)
        T.no_raise(function() fw:ValidateSettings() end)
    end)
end)

-- ===================== FormatTime =====================

T.describe("FormatTime", function()
    T.it("formats sub-minute durations as seconds", function()
        T.eq(TRP3FW:FormatTime(5), "5s")
        T.eq(TRP3FW:FormatTime(59), "59s")
    end)

    T.it("formats minutes with remaining seconds", function()
        T.eq(TRP3FW:FormatTime(90), "1m 30s")
    end)

    T.it("formats hours with remaining minutes", function()
        T.eq(TRP3FW:FormatTime(3661), "1h 1m")
    end)
end)

return T
