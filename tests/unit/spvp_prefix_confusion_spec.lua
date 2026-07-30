-- tests/unit/spvp_prefix_confusion_spec.lua
-- Headless tests for the CHAT_MSG_ADDON dispatch in features/encryption/spvp_handlers.lua.
--
-- The handler receives (prefix, message, channel, sender) straight from the client, for EVERY
-- addon message the client surfaces -- not just ours. Two things about that are load-bearing:
--
--   1. `prefix` is attacker-chosen. Any player can SendAddonMessage with any prefix they like.
--   2. The async-salt branch keys `pendingSaltTickets` on `prefix`, and it ran BEFORE the
--      `prefix ~= "TRP3FW_SPVP"` guard -- so a remote packet whose prefix happened to equal a
--      live Epsilon salt ticket was fed to HandleSaltResponse as though the SERVER had answered.
--
-- Epsilon tickets are short (~15 mixed-case chars, e.g. "ITOSj3iH7JTRsbY") and are not secret
-- in any deliberate sense; nothing in the protocol was treating them as an authenticator. The
-- fix is to only ever consult pendingSaltTickets for messages that did NOT come from a player,
-- which is what the server-origin check below asserts.
--
-- Consequences of a spoofed salt response, both covered here:
--   * a bogus salt is cached for the phase, so every subsequent SPVP verification in that phase
--     runs against a salt the attacker chose;
--   * a malformed one negative-caches the phase for an hour AND flushes pendingSPVPInits for it,
--     NOSALT-ing legitimate peers who were waiting on the real response.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW()
    local fw = H.newNamespace()
    fw.Prefs = { spvpSaltCacheDuration = 10800, spvpPhaseSaltRefreshRate = 50 }
    fw.spvpSessions, fw.spvpIncomingSessions = {}, {}
    fw.spvpFailedAttempts, fw.pendingSaltTickets, fw.pendingSPVPInits = {}, {}, {}
    fw.profiler = { start = function() end, stop = function() end }

    -- Keyed by cache NAME as well as key: SecurityService keeps its own cleanName /
    -- sanitizedName caches here, and a single flat keyspace would let a player name collide
    -- with a phase ID. `cacheStore` below is the spvpPhaseSalt bucket, which is what the
    -- assertions inspect.
    local buckets = {}
    local function bucket(name)
        buckets[name] = buckets[name] or {}
        return buckets[name]
    end
    fw.CacheInterface = {
        Get = function(_, cacheName, key) return bucket(cacheName)[key] end,
        Set = function(_, cacheName, key, val) bucket(cacheName)[key] = val end,
        Remove = function(_, cacheName, key) bucket(cacheName)[key] = nil end,
        GetSize = function() return 0 end,
        Clear = function(_, cacheName) buckets[cacheName] = {} end,
    }
    fw.cacheStore = bucket("spvpPhaseSalt")

    fw.sentMessages = {}
    _G.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() end,
        SendAddonMessage = function(prefix, msg, channel, target)
            table.insert(fw.sentMessages, {prefix = prefix, msg = msg, channel = channel, target = target})
        end,
    }

    -- The handler compares the packet's sender against our own name, so this spec needs the
    -- REAL CleanPlayerName rather than a stub. It delegates to SecurityService, so that (and
    -- the container + name caches it uses) has to be wired up or it returns nil for every
    -- name -- including our own, which would make the accept-cases pass vacuously.
    _G.TRP3FW_ValidatedNames = {}
    H.loadModule("core/Service.lua", fw)
    H.loadModule("core/ServiceContainer.lua", fw)
    H.loadModule("features/services/SecurityService.lua", fw)
    H.loadModule("core/utils.lua", fw)

    H.loadModule("features/encryption/spvp.lua", fw)
    H.loadModule("features/encryption/spvp_handlers.lua", fw)
    -- The handlers module registers its OnEvent on a module-scoped frame we get no
    -- reference to; the most recently created frame is it.
    fw.eventFrame = mock.lastFrame()
    return fw
end

local VALID_SALT = string.rep("a", 64)..":1704844800"
local TICKET = "ITOSj3iH7JTRsbY"  -- shape Epsilon actually returns: short, mixed-case, non-hex

T.describe("SPVP salt-ticket prefix confusion", function()
    T.it("BUG: a player-sent packet whose prefix matches a live ticket spoofs the salt", function()
        mock.setClock(1000)
        local fw = freshFW()

        -- We are waiting on Epsilon for phase 184739's salt.
        fw.pendingSaltTickets[TICKET] = 184739

        -- A remote player sends an addon message using the ticket as the prefix. The 4th
        -- CHAT_MSG_ADDON arg is the sender; a real server-side salt response has no player
        -- sender, a player-originated packet always does.
        fw.eventFrame:Fire("CHAT_MSG_ADDON", TICKET, VALID_SALT, "WHISPER", "Attacker-Apertus")

        T.eq(fw.cacheStore[184739], nil,
            "a packet with a player sender must never be accepted as a salt response")
        T.eq(fw.pendingSaltTickets[TICKET], 184739,
            "and the real ticket must still be pending, so the genuine response can land")
    end)

    T.it("BUG: a malformed spoofed response negative-caches the phase and NOSALTs waiters", function()
        mock.setClock(1000)
        local fw = freshFW()

        fw.pendingSaltTickets[TICKET] = 184739
        table.insert(fw.pendingSPVPInits, {
            sender = "LegitPeer", message = "INIT:3:abc:184739", phaseID = 184739, queuedAt = 1000,
        })

        fw.eventFrame:Fire("CHAT_MSG_ADDON", TICKET, "not-a-salt", "WHISPER", "Attacker-Apertus")

        T.eq(fw.cacheStore[184739], nil,
            "a spoofed malformed response must not negative-cache the phase for an hour")
        T.eq(#fw.pendingSPVPInits, 1,
            "the legitimate peer must still be queued, not flushed")
        T.eq(#fw.sentMessages, 0,
            "and no NOSALT should have been sent on an attacker's say-so")
    end)

    -- Which of the two server-side sender forms Epsilon actually uses is not observable from
    -- the client, so BOTH must keep working -- that is the whole reason the guard rejects only
    -- third-party senders rather than requiring an absent one.
    T.it("a genuine server salt response with no sender is accepted", function()
        mock.setClock(1000)
        local fw = freshFW()

        fw.pendingSaltTickets[TICKET] = 184739
        fw.eventFrame:Fire("CHAT_MSG_ADDON", TICKET, VALID_SALT, nil, nil)

        T.not_nil(fw.cacheStore[184739], "the real response must still be cached")
        T.eq(fw.cacheStore[184739].salt, VALID_SALT, "and it must cache the salt verbatim")
        T.eq(fw.pendingSaltTickets[TICKET], nil, "the ticket is consumed")
    end)

    T.it("a genuine server salt response attributed to ourselves is accepted", function()
        mock.setClock(1000)
        local fw = freshFW()

        fw.pendingSaltTickets[TICKET] = 184739
        -- mock UnitName("player") is the local character; Epsilon may stamp its own delivery
        -- with our name rather than leaving it blank.
        fw.eventFrame:Fire("CHAT_MSG_ADDON", TICKET, VALID_SALT, "WHISPER", UnitName("player"))

        T.not_nil(fw.cacheStore[184739], "a self-attributed server response must be accepted")
        T.eq(fw.cacheStore[184739].salt, VALID_SALT, "and it must cache the salt verbatim")
        T.eq(fw.pendingSaltTickets[TICKET], nil, "the ticket is consumed")
    end)

    T.it("an unrelated addon's prefix is ignored regardless of body", function()
        mock.setClock(1000)
        local fw = freshFW()

        fw.pendingSaltTickets[TICKET] = 184739

        -- Another addon's traffic must not be mistaken for anything of ours.
        fw.eventFrame:Fire("CHAT_MSG_ADDON", "SomeOtherAddon", VALID_SALT, "WHISPER", "Bystander-Apertus")

        T.eq(fw.cacheStore[184739], nil, "unrelated prefix must not touch the salt cache")
        T.eq(fw.pendingSaltTickets[TICKET], 184739, "and must not consume our ticket")
    end)
end)
