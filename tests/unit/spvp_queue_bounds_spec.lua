-- tests/unit/spvp_queue_bounds_spec.lua
-- Headless tests for the two network-fed SPVP tables (features/encryption/spvp.lua).
--
-- Both are written directly from the CHAT_MSG_ADDON handler -- any player can whisper us an
-- SPVP packet -- and both previously had NO cap and NO expiry:
--
--   pendingSPVPInits      queued while a salt ticket resolves; drained only when a salt
--                         response arrives. If it never arrives, entries live forever.
--   spvpIncomingSessions  Bob's half-open handshake state; removed only by a matching
--                         CONFIRM. A peer that never confirms leaves one entry per INIT,
--                         each pinning a derived shared key.
--
-- Replay detection does not bound either one: it rejects a REPEATED sessionID, and the
-- sender picks their own sessionID, so a fresh one per packet queues without limit.
--
-- pendingSPVPInits had a second, separate bug: entries recorded only {sender, message}, and
-- BOTH drain paths processed the WHOLE queue for whichever ticket resolved. Since
-- HandleSPVPInit re-reads GetCurrentPhaseID() on replay, an INIT queued in phase A that
-- drained after moving to phase B was verified against phase B's salt.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW()
    local fw = H.newNamespace()
    fw.Prefs = { spvpSaltCacheDuration = 10800, spvpPhaseSaltRefreshRate = 50 }
    fw.spvpSessions, fw.spvpIncomingSessions = {}, {}
    fw.spvpFailedAttempts, fw.pendingSaltTickets, fw.pendingSPVPInits = {}, {}, {}
    fw.profiler = { start = function() end, stop = function() end }

    local store = {}
    fw.CacheInterface = {
        Get = function(_, _, key) return store[key] end,
        Set = function(_, _, key, val) store[key] = val end,
        Remove = function(_, _, key) store[key] = nil end,
        GetSize = function() return 0 end,
        Clear = function() store = {} end,
    }

    _G.C_ChatInfo = { SendAddonMessage = function() end, RegisterAddonMessagePrefix = function() end }

    H.loadModule("features/encryption/spvp.lua", fw)
    return fw
end

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

T.describe("pendingSPVPInits bounds", function()
    T.it("BUG (fixed): the queue is capped rather than growing without limit", function()
        mock.setClock(1000)
        local fw = freshFW()

        for i = 1, 500 do
            table.insert(fw.pendingSPVPInits, {
                sender = "Attacker", message = "INIT:2:s"..i..":123",
                phaseID = 1, queuedAt = mock.clock,
            })
        end
        fw:PrunePendingSPVPInits()

        T.truthy(#fw.pendingSPVPInits <= fw.SPVP_PENDING_INIT_LIMIT,
            "queue must stay within its cap, got "..#fw.pendingSPVPInits)
    end)

    T.it("BUG (fixed): entries past the TTL are discarded", function()
        mock.setClock(1000)
        local fw = freshFW()

        table.insert(fw.pendingSPVPInits, {
            sender = "Ghost", message = "INIT:2:abc:123", phaseID = 1, queuedAt = 1000,
        })

        mock.advance(fw.SPVP_PENDING_INIT_TTL + 1)
        fw:PrunePendingSPVPInits()

        T.eq(#fw.pendingSPVPInits, 0,
            "a salt response that never arrives must not pin the entry forever")
    end)

    T.it("keeps entries that are still within the TTL", function()
        mock.setClock(1000)
        local fw = freshFW()

        table.insert(fw.pendingSPVPInits, {
            sender = "Live", message = "INIT:2:abc:123", phaseID = 1, queuedAt = 1000,
        })

        mock.advance(1)
        fw:PrunePendingSPVPInits()

        T.eq(#fw.pendingSPVPInits, 1, "a fresh entry must survive the sweep")
    end)

    T.it("drops the OLDEST first, so the newest waiting sender is kept", function()
        mock.setClock(1000)
        local fw = freshFW()

        for i = 1, fw.SPVP_PENDING_INIT_LIMIT + 10 do
            table.insert(fw.pendingSPVPInits, {
                sender = "P"..i, message = "INIT:2:s"..i..":123",
                phaseID = 1, queuedAt = mock.clock,
            })
        end
        fw:PrunePendingSPVPInits()

        local last = fw.pendingSPVPInits[#fw.pendingSPVPInits]
        T.eq(last.sender, "P"..(fw.SPVP_PENDING_INIT_LIMIT + 10),
            "the most recent INIT must survive - its sender is the one still waiting")
    end)
end)

T.describe("pendingSPVPInits phase correctness", function()
    T.it("BUG (fixed): a salt response only drains INITs queued under THAT phase", function()
        mock.setClock(1000)
        local fw = freshFW()

        -- Two INITs queued under different phases, both awaiting their own salt.
        table.insert(fw.pendingSPVPInits, {
            sender = "PhaseA_Peer", message = "INIT:2:aaa:123", phaseID = 111, queuedAt = 1000,
        })
        table.insert(fw.pendingSPVPInits, {
            sender = "PhaseB_Peer", message = "INIT:2:bbb:456", phaseID = 222, queuedAt = 1000,
        })

        -- Phase 111's salt resolves as "no salt". Only its entry may be consumed.
        fw.pendingSaltTickets["ticket-a"] = 111
        fw:HandleSaltResponse("ticket-a", "not-a-valid-salt")

        T.eq(#fw.pendingSPVPInits, 1,
            "the other phase's INIT must be left queued for its own salt response")
        T.eq(fw.pendingSPVPInits[1].phaseID, 222,
            "and it must be the phase-222 entry that survived")
    end)

    T.it("a successful salt response likewise leaves other phases queued", function()
        mock.setClock(1000)
        local fw = freshFW()
        -- HandleSPVPInit is invoked for the ready entries; stub it so this test stays
        -- focused on which entries are SELECTED rather than on handshake behaviour.
        local handled = {}
        fw.HandleSPVPInit = function(_, message, sender)
            table.insert(handled, sender)
        end

        table.insert(fw.pendingSPVPInits, {
            sender = "PhaseA_Peer", message = "INIT:2:aaa:123", phaseID = 111, queuedAt = 1000,
        })
        table.insert(fw.pendingSPVPInits, {
            sender = "PhaseB_Peer", message = "INIT:2:bbb:456", phaseID = 222, queuedAt = 1000,
        })

        local validSalt = string.rep("a", 64)..":1704844800"
        fw.pendingSaltTickets["ticket-a"] = 111
        fw:HandleSaltResponse("ticket-a", validSalt)

        T.eq(#handled, 1, "exactly one INIT should have been replayed")
        T.eq(handled[1], "PhaseA_Peer", "and it must be the one queued under phase 111")
        T.eq(#fw.pendingSPVPInits, 1, "the phase-222 entry stays queued")
        T.eq(fw.pendingSPVPInits[1].sender, "PhaseB_Peer")
    end)
end)

T.describe("spvpIncomingSessions bounds", function()
    T.it("BUG (fixed): half-open sessions past the timeout are swept", function()
        mock.setClock(1000)
        local fw = freshFW()

        fw.spvpIncomingSessions["dead"] = {
            sharedKey = 12345, sender = "NeverConfirms", timestamp = 1000,
        }

        mock.advance(100)  -- well past SPVP_TIMEOUT_SECONDS * 4
        fw:PruneSPVPIncomingSessions()

        T.eq(countKeys(fw.spvpIncomingSessions), 0,
            "a peer that never CONFIRMs must not pin its session state forever")
    end)

    T.it("keeps a session that is still inside the handshake window", function()
        mock.setClock(1000)
        local fw = freshFW()

        fw.spvpIncomingSessions["live"] = {
            sharedKey = 12345, sender = "MidHandshake", timestamp = 1000,
        }

        mock.advance(1)
        fw:PruneSPVPIncomingSessions()

        T.eq(countKeys(fw.spvpIncomingSessions), 1,
            "an in-flight handshake must not be swept out from under itself")
    end)

    T.it("BUG (fixed): a flood is capped even inside the TTL window", function()
        mock.setClock(1000)
        local fw = freshFW()

        -- All within the TTL, so only the hard cap can bound this.
        for i = 1, 400 do
            fw.spvpIncomingSessions["s"..i] = {
                sharedKey = i, sender = "Flooder", timestamp = mock.clock,
            }
        end
        fw:PruneSPVPIncomingSessions()

        T.truthy(countKeys(fw.spvpIncomingSessions) <= fw.SPVP_INCOMING_SESSION_LIMIT,
            "must stay within the cap, got "..countKeys(fw.spvpIncomingSessions))
    end)
end)

-- ===================== Phase-ID cache unification =====================
-- GetCachedPhaseID (core/utils.lua) and GetCurrentPhaseID (spvp.lua) were two separate
-- caching implementations that SHARED TRP3FW.cachedPhaseID but tracked freshness in different
-- fields (cachedPhaseTimestamp vs cachedPhaseIDTime), with different TTLs (1s vs 5s), on
-- different clocks (time() wall-clock vs GetCurrentTime() monotonic uptime -- not even the
-- same epoch). Whichever wrote last, the other served that value judged against its own
-- unrelated timestamp, so GetCachedPhaseID could return a phase ID up to 5s old under a
-- contract promising 1s -- and its caller is ghost mode's start-phase check.

T.describe("phase ID cache unification", function()
    local function withEpsilon(fw, phaseID)
        _G.C_Epsilon = { GetPhaseId = function() return phaseID end }
        fw.hasEpsilonAPI = true
        fw.PHASE_CACHE_TTL = 1
        fw.cachedPhaseID = nil
        fw.cachedPhaseTimestamp = 0
    end

    T.it("both entry points agree on the current phase", function()
        mock.setClock(1000)
        local fw = freshFW()
        H.loadModule("core/utils.lua", fw)
        withEpsilon(fw, 111)

        T.eq(fw:GetCurrentPhaseID(), 111)
        T.eq(fw:GetCachedPhaseID(), 111, "both names must resolve to the same value")
    end)

    T.it("BUG (fixed): GetCurrentPhaseID honours the 1s TTL, not its own 5s one", function()
        -- This is the defect that actually bit. GetCurrentPhaseID kept a private cache with a
        -- 5s TTL, so SPVPStage, cascading, decision, the salt paths and the UI could all act
        -- on a phase ID up to 5 seconds out of date -- while PHASE_CACHE_TTL says 1s.
        mock.setClock(1000)
        local fw = freshFW()
        H.loadModule("core/utils.lua", fw)
        withEpsilon(fw, 111)

        local realTime = _G.time
        _G.time = function() return 1000 end
        T.eq(fw:GetCurrentPhaseID(), 111, "sanity: primes the cache")

        -- Phase changes; 2s pass. Past the 1s TTL, inside the old 5s one.
        _G.C_Epsilon.GetPhaseId = function() return 222 end
        _G.time = function() return 1002 end
        mock.advance(2)
        local result = fw:GetCurrentPhaseID()
        _G.time = realTime

        T.eq(result, 222,
            "2s after a phase change the new phase must be visible; the old 5s cache served 111")
    end)

    T.it("still caches within the TTL rather than hitting the API every call", function()
        mock.setClock(1000)
        local fw = freshFW()
        H.loadModule("core/utils.lua", fw)
        withEpsilon(fw, 111)

        local apiCalls = 0
        _G.C_Epsilon.GetPhaseId = function() apiCalls = apiCalls + 1; return 111 end

        local realTime = _G.time
        _G.time = function() return 1000 end
        fw:GetCurrentPhaseID()
        fw:GetCurrentPhaseID()
        fw:GetCurrentPhaseID()
        _G.time = realTime

        T.eq(apiCalls, 1, "repeat calls inside the TTL must be served from cache")
    end)

    T.it("returns nil without the Epsilon API", function()
        local fw = freshFW()
        H.loadModule("core/utils.lua", fw)
        _G.C_Epsilon = nil
        T.is_nil(fw:GetCurrentPhaseID())
        T.is_nil(fw:GetCachedPhaseID())
    end)
end)

-- ===================== Auto-init salt-loading race =====================
-- GetPhaseSalt is three-valued: nil = still loading, "" = confirmed no salt, string = salt.
-- Auto-init's guard was `if existingSalt and existingSalt ~= ""`, so nil fell THROUGH to
-- generation. On a cold cache -- the common case right after a phase change, which is exactly
-- when auto-init runs -- it would SetPhaseAddonData over a salt that was merely still being
-- fetched, silently rotating the phase secret out from under every peer.

T.describe("SPVP auto-init salt-loading race", function()
    local function autoInitFW(saltResult)
        local fw = freshFW()
        fw.hasEpsilonAPI = true
        fw.Prefs.spvpEnabled = true
        fw.Prefs.spvpAutoInitialize = true

        fw.setCalls = {}
        _G.C_Epsilon = {
            IsOwner = function() return true end,
            IsOfficer = function() return false end,
            GetPhaseAddonData = function() return "" end,
            SetPhaseAddonData = function(k, v) table.insert(fw.setCalls, { key = k, value = v }) end,
            GetPhaseId = function() return 555 end,
        }

        fw.GetCurrentPhaseID = function() return 555 end
        fw.GetPhaseSalt = function() return saltResult end
        fw.GeneratePhaseSalt = function() return string.rep("f", 64)..":1704844800" end
        fw.Info = function() end
        fw.Error = function() end
        fw.ParsePhaseSalt = function() return nil, 1704844800 end

        H.loadModule("features/encryption/spvp_auto_init.lua", fw)
        return fw
    end

    T.it("BUG (fixed): does NOT generate while the salt is still loading (nil)", function()
        mock.setClock(1000)
        local fw = autoInitFW(nil)  -- nil = loading, NOT "no salt"

        fw:CheckAutoInitializeSalt()

        T.eq(#fw.setCalls, 0,
            "must not overwrite a salt that is merely still being fetched")
    end)

    T.it("generates when the phase is confirmed to have no salt ('')", function()
        mock.setClock(1000)
        local fw = autoInitFW("")

        fw:CheckAutoInitializeSalt()

        T.eq(#fw.setCalls, 1, "an empty string is a confirmed absence - generating is correct")
        T.eq(fw.setCalls[1].key, "TRP3FW_SPVP_KEY")
    end)

    T.it("skips when a salt already exists", function()
        mock.setClock(1000)
        local fw = autoInitFW(string.rep("a", 64)..":1704844800")

        fw:CheckAutoInitializeSalt()

        T.eq(#fw.setCalls, 0, "an existing salt must never be silently rotated")
    end)
end)

T.describe("GetSaltFingerprint", function()
    T.it("never returns salt material", function()
        local fw = freshFW()
        local salt = string.rep("a", 64)..":1704844800"
        local fp = fw:GetSaltFingerprint(salt)

        T.eq(#fp, 8, "fingerprint is a fixed 8 hex chars")
        T.falsy(salt:find(fp, 1, true), "the fingerprint must not be a substring of the salt")
    end)

    T.it("is stable and distinguishes different salts", function()
        local fw = freshFW()
        local a = string.rep("a", 64)..":1704844800"
        local b = string.rep("b", 64)..":1704844800"

        T.eq(fw:GetSaltFingerprint(a), fw:GetSaltFingerprint(a), "stable for the same input")
        T.neq(fw:GetSaltFingerprint(a), fw:GetSaltFingerprint(b), "differs for different salts")
    end)

    T.it("handles nil/empty without leaking a format", function()
        local fw = freshFW()
        T.eq(fw:GetSaltFingerprint(nil), "none")
        T.eq(fw:GetSaltFingerprint(""), "none")
    end)
end)
