-- tests/unit/allowsender_apostrophe_key_spec.lua
-- Regression test: AllowSender used to key the "allowedSenders" CacheInterface entry
-- with SanitizePlayerName's output, which ESCAPES quotes/backslashes for safe embedding
-- in a RunPrivileged() code string (e.g. "Il'tar" -> "Il\'tar", with a literal backslash
-- byte). Every reader of that cache (CacheStage, trp3_scan_pipeline, NotificationService)
-- looks it up with the unescaped/clean name instead. For any apostrophe-free name the two
-- forms are identical, so the mismatch was invisible - but for an apostrophe-containing
-- name like "Il'tar" the write key ("Il\'tar") and every read key ("Il'tar") never
-- matched, so the allowedSenders fast-path was a guaranteed miss FOREVER for that player:
-- every request re-ran a full location check instead of hitting the cache, which read as
-- "this one person keeps getting blocked" if the full check had any flaky failure mode.
--
-- Fix: AllowSender now keys on CleanPlayerName (unescaped, canonical), matching every
-- reader.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW()
    local fw = H.newNamespace()
    fw.Prefs = { sendCacheDuration = 600, sendCacheRefreshRate = 10 }
    _G.TRP3FW_ValidatedNames = {}
    H.loadModule("core/Service.lua", fw)
    H.loadModule("core/ServiceContainer.lua", fw)
    H.loadModule("core/cache_interface.lua", fw)
    H.loadModule("features/services/SecurityService.lua", fw)
    H.loadModule("core/utils.lua", fw)
    fw.CacheInterface:Register("allowedSenders", {})
    fw.CacheInterface:Register("sanitizedName", {})
    fw.CacheInterface:Register("cleanName", {})

    fw.ServiceContainer = fw.ServiceContainer -- already set by ServiceContainer.lua load
    H.loadModule("features/decision.lua", fw)
    return fw
end

T.describe("AllowSender caches under the same key every reader uses (apostrophe names)", function()
    T.it("writes allowedSenders under CleanPlayerName's unescaped form", function()
        mock.setClock(1000)
        local fw = freshFW()

        fw:AllowSender("Il'tar", "manual")

        -- Every real reader (CacheStage, trp3_scan_pipeline, NotificationService) looks
        -- this cache up keyed on CleanPlayerName's plain, unescaped output - simulate
        -- that read directly.
        local cleanKey = fw:CleanPlayerName("Il'tar")
        T.eq(cleanKey, "Il'tar", "sanity: CleanPlayerName does not escape apostrophes")

        local hit = fw.CacheInterface:Get("allowedSenders", cleanKey)
        T.not_nil(hit, "allowedSenders cache must be readable via the unescaped/clean key")
    end)

    T.it("does not write allowedSenders under SanitizePlayerName's escaped form", function()
        mock.setClock(1000)
        local fw = freshFW()

        fw:AllowSender("Il'tar", "manual")

        local escapedKey = fw:SanitizePlayerName("Il'tar")
        T.eq(escapedKey, "Il\\'tar", "sanity: SanitizePlayerName escapes the apostrophe")

        local hit = fw.CacheInterface:Get("allowedSenders", escapedKey)
        T.is_nil(hit, "allowedSenders must not be keyed by the RunPrivileged-escaped form")
    end)

    T.it("still works normally for apostrophe-free names (both forms identical)", function()
        mock.setClock(1000)
        local fw = freshFW()

        fw:AllowSender("Plainbob", "manual")

        local cleanKey = fw:CleanPlayerName("Plainbob")
        local hit = fw.CacheInterface:Get("allowedSenders", cleanKey)
        T.not_nil(hit, "allowedSenders cache must still work for names without apostrophes")
    end)

    T.it("still works for space-containing names, alone or combined with an apostrophe", function()
        mock.setClock(1000)
        local fw = freshFW()

        -- %s is whitelisted in both SANITIZE_NAME_PATTERN and CleanPlayerName's
        -- reject-class, and SanitizePlayerName's escaping gsub chain only touches
        -- backslash/quote/apostrophe - spaces are never touched by either function, so
        -- they were never part of this bug. Verify that explicitly rather than assume it.
        for _, name in ipairs({ "Mai Lin", "Il'tar Moonwhisper" }) do
            fw:AllowSender(name, "manual")
            local cleanKey = fw:CleanPlayerName(name)
            T.eq(cleanKey, name, "CleanPlayerName must not alter a space (or space+apostrophe) name: "..name)
            local hit = fw.CacheInterface:Get("allowedSenders", cleanKey)
            T.not_nil(hit, "allowedSenders cache must be readable for: "..name)
        end
    end)

    T.it("still works for accented (high-byte) names, alone or combined with an apostrophe", function()
        mock.setClock(1000)
        local fw = freshFW()

        -- \128-\255 is whitelisted in both patterns as an opaque high-byte range - it
        -- doesn't matter whether the client sent UTF-8 (multi-byte, e.g. e-acute as
        -- 0xC3 0xA9) or a legacy single-byte codepage (e.g. CP1252 e-acute as 0xE9): every
        -- byte in \128-\255 passes through CleanPlayerName/SanitizePlayerName unchanged,
        -- and SanitizePlayerName's escaping gsub only touches backslash/quote/apostrophe,
        -- so high bytes are never split or mangled by the escape/unescape round-trip.
        local utf8Name = "R\195\169'gnor Sto\195\169l"  -- "Ré'gnor Stoél" (UTF-8 e-acute)
        fw:AllowSender(utf8Name, "manual")
        local cleanKey = fw:CleanPlayerName(utf8Name)
        T.eq(cleanKey, utf8Name, "CleanPlayerName must not alter high-byte/accented characters")
        local hit = fw.CacheInterface:Get("allowedSenders", cleanKey)
        T.not_nil(hit, "allowedSenders cache must be readable for an accented+apostrophe name")
    end)
end)

return T
