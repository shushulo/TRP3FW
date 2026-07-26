-- tests/unit/spvp_entropy_spec.lua
-- Entropy sourcing for SPVP secrets (features/encryption/spvp.lua).
--
-- THE BUG THIS COVERS. Every SPVP secret -- private key, session ID, phase salt -- was produced
-- by building a seed from (GUID + microsecond time + cursor position), calling math.randomseed,
-- and drawing. That makes the output a pure function of the seed, so the effective keyspace is
-- the SEED space, not the nominal range. Decomposed against what the peer actually knows:
--
--   GUID    -- they know it; the attacker IS the peer
--   cursor  -- bounded by screen resolution, and the arithmetic combination collapses it
--   time    -- the dominant term, and they know roughly WHEN we sent, having received it
--
-- Measured on the old code: 1000 adjacent microsecond seeds produced 1000 distinct keys, so no
-- outright collapse -- but no amplification either. Bound the send time to ~1ms and the search
-- space is ~2^10; to ~100ms, ~2^17. Both at or below the group's own ~2^12.7, which made this
-- plausibly the cheapest attack on SPVP.
--
-- These tests pin the OBSERVABLE consequences of the fix. They deliberately do not assert
-- anything about entropy quantity -- you cannot measure that from inside, and a test claiming
-- to would be lying. What they can prove: secrets do not repeat when the observable inputs
-- repeat, and every declared source actually reaches the pool.
--
-- NOT COVERED (needs in-game verification): whether the ambient sources carry real entropy on
-- a live client. Under the mock, GetCursorPosition/GetFramerate are CONSTANTS -- which is
-- exactly why these tests are a meaningful floor: they pass with every ambient source frozen,
-- so they demonstrate the pool's own evolution rather than the mock's variability.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW()
    local fw = H.newNamespace()
    fw.CacheInterface = nil
    fw.spvpSessions, fw.spvpIncomingSessions = {}, {}
    fw.spvpFailedAttempts, fw.pendingSaltTickets, fw.pendingSPVPInits = {}, {}, {}
    H.loadModule("features/encryption/spvp.lua", fw)
    return fw
end

local DH_PRIME = 93999743

T.describe("SPVP private key entropy", function()
    T.it("BUG (fixed): successive keys differ even with the clock frozen", function()
        -- The core regression. Under the old code the seed was rebuilt from time + GUID +
        -- cursor; freeze all three and every key in that tick was IDENTICAL. Two handshakes in
        -- one frame would share a private key -- and a peer who solved one would hold both.
        mock.setClock(1000)
        local fw = freshFW()

        local seen, N = {}, 50
        for _ = 1, N do
            seen[fw.SPVP.GeneratePrivateKey()] = true
        end

        local count = 0
        for _ in pairs(seen) do count = count + 1 end
        T.eq(count, N, "all "..N.." keys must be distinct with time/cursor/GUID held constant")
    end)

    T.it("keys stay inside the valid exponent range", function()
        mock.setClock(1000)
        local fw = freshFW()

        for _ = 1, 200 do
            local k = fw.SPVP.GeneratePrivateKey()
            T.truthy(k >= 2 and k <= DH_PRIME - 2,
                "private key out of range [2, p-2]: "..tostring(k))
            T.eq(k, math.floor(k), "private key must be an integer")
        end
    end)

    T.it("two clients sharing observable inputs do not derive the same key", function()
        -- Same frozen clock, same mocked GUID and cursor: the ONLY difference between these two
        -- namespaces is their independently-evolving pools. Under the old scheme both derived
        -- their seed from the shared observables and collided.
        mock.setClock(5000)
        local alice = freshFW()
        local bob = freshFW()

        -- Diverge the pools the way real clients would -- different packets seen.
        alice.SPVP_StirEntropy("alice-saw-this")
        bob.SPVP_StirEntropy("bob-saw-something-else")

        T.neq(alice.SPVP.GeneratePrivateKey(), bob.SPVP.GeneratePrivateKey(),
            "independent clients must not share a private key")
    end)
end)

T.describe("SPVP session ID entropy", function()
    T.it("BUG (fixed): session IDs differ with the clock frozen", function()
        -- The old loop reseeded per CHARACTER, which looked like hardening but reseeded from
        -- the same three observables each time, differing only by loop index. Frozen inputs
        -- made the whole ID deterministic.
        mock.setClock(1000)
        local fw = freshFW()

        local seen, N = {}, 50
        for _ = 1, N do
            seen[fw.SPVP.GenerateSessionID()] = true
        end

        local count = 0
        for _ in pairs(seen) do count = count + 1 end
        T.eq(count, N, "session IDs must not repeat within a tick")
    end)

    T.it("keeps its wire format: 8 uppercase hex chars", function()
        mock.setClock(1000)
        local fw = freshFW()
        -- HandleSPVPInit parses sessionID as (%w+), so the shape must not drift.
        for _ = 1, 20 do
            local s = fw.SPVP.GenerateSessionID()
            T.eq(#s, 8)
            T.truthy(s:match("^[0-9A-F]+$"), "uppercase hex only, got "..s)
        end
    end)

    T.it("all 16 hex digits are reachable", function()
        -- Guards an off-by-one in the draw bounds silently shrinking the alphabet.
        mock.setClock(1000)
        local fw = freshFW()
        local seen = {}
        for _ = 1, 400 do
            for c in fw.SPVP.GenerateSessionID():gmatch(".") do seen[c] = true end
        end
        local count = 0
        for _ in pairs(seen) do count = count + 1 end
        T.eq(count, 16, "every hex digit must be producible, got "..count)
    end)
end)

T.describe("SPVP phase salt entropy", function()
    -- The salt matters more than the private key: a key compromise costs one handshake, but
    -- the salt is what the entire protocol proves possession of, and it persists in phase
    -- addon data until someone re-secures the phase.
    T.it("BUG (fixed): salts differ with the clock frozen", function()
        mock.setClock(1000)
        local fw = freshFW()

        local seen, N = {}, 30
        for _ = 1, N do
            local salt = fw:GeneratePhaseSalt()
            local hexPart = salt:match("^(%x+):")
            seen[hexPart] = true
        end

        local count = 0
        for _ in pairs(seen) do count = count + 1 end
        T.eq(count, N, "phase salts must not repeat within a tick")
    end)

    T.it("keeps the format IsWellFormedSalt expects", function()
        -- If the shape drifts, GetPhaseSalt misclassifies real salts as async tickets and SPVP
        -- silently stops working rather than failing loudly.
        mock.setClock(1000)
        local fw = freshFW()

        local salt = fw:GeneratePhaseSalt()
        T.truthy(fw.SPVP_IsWellFormedSalt(salt), "generated salt must pass its own validator")

        local hexPart, ts = salt:match("^(%x+):(%d+)$")
        T.truthy(hexPart ~= nil, "salt must be hex:timestamp")
        T.eq(#hexPart, 64, "hex portion must stay 64 chars")
        T.truthy(tonumber(ts) > 0, "timestamp must be present and positive")
    end)

    T.it("uses the full hex alphabet across the salt body", function()
        mock.setClock(1000)
        local fw = freshFW()
        local seen = {}
        for _ = 1, 20 do
            for c in fw:GeneratePhaseSalt():match("^(%x+):"):gmatch(".") do seen[c] = true end
        end
        local count = 0
        for _ in pairs(seen) do count = count + 1 end
        T.eq(count, 16, "salt must draw on all 16 hex digits, got "..count)
    end)
end)

T.describe("entropy pool mechanics", function()
    T.it("stirring is order-dependent, so the pool encodes history", function()
        -- If folding were commutative the pool would depend only on the SET of samples seen,
        -- and an attacker reproducing those in any order would reconstruct it.
        mock.setClock(1000)
        local a = freshFW()
        local b = freshFW()

        a.SPVP_StirEntropy("first"); a.SPVP_StirEntropy("second")
        b.SPVP_StirEntropy("second"); b.SPVP_StirEntropy("first")

        T.neq(a.SPVP.GeneratePrivateKey(), b.SPVP.GeneratePrivateKey(),
            "same samples in a different order must not converge")
    end)

    T.it("drawing a secret advances the pool", function()
        mock.setClock(1000)
        local fw = freshFW()

        local before = fw.SPVP_GetEntropyStirCount()
        fw.SPVP.GeneratePrivateKey()
        local after = fw.SPVP_GetEntropyStirCount()

        T.truthy(after > before,
            "a draw must stir the pool, else successive draws share a seed")
    end)

    T.it("never exposes the pool value itself", function()
        -- Only the COUNT is observable. Exporting the pool would hand an attacker the state
        -- that every subsequent secret derives from.
        local fw = freshFW()
        T.eq(type(fw.SPVP_GetEntropyStirCount()), "number")
        T.is_nil(rawget(fw, "entropyPool"), "pool must stay a module local")
        T.is_nil(fw.SPVP and fw.SPVP.entropyPool, "pool must not leak via the SPVP export")
    end)

    T.it("packet arrivals feed the pool", function()
        -- spvp_handlers stirs message+sender on every SPVP packet. Arrival timing is a source
        -- the SENDER cannot fully observe: they know when they sent, not the network delay.
        mock.setClock(1000)
        local fw = freshFW()

        local before = fw.SPVP_GetEntropyStirCount()
        fw.SPVP_StirEntropy("REPLY:ABCD1234:5551212:deadbeefcafe0123")
        fw.SPVP_StirEntropy("SomePlayer-Realm")

        T.eq(fw.SPVP_GetEntropyStirCount(), before + 2, "each stir must register")
    end)
end)

T.describe("handshake still works after the entropy change", function()
    -- Regression guard: entropy is upstream of the DH agreement, so a mistake in the draw
    -- bounds (a key of 0, or out of range) would break agreement rather than merely weaken it.
    T.it("Alice and Bob still derive the same shared key", function()
        mock.setClock(1000)
        local fw = freshFW()
        local SPVP = fw.SPVP

        local g = SPVP.GetGenerator(184739, string.rep("a", 64)..":1704844800")

        for _ = 1, 25 do
            local a, b = SPVP.GeneratePrivateKey(), SPVP.GeneratePrivateKey()
            local A, B = SPVP.GeneratePublicKey(g, a), SPVP.GeneratePublicKey(g, b)

            T.eq(SPVP.DeriveSharedKey(B, a), SPVP.DeriveSharedKey(A, b),
                "DH agreement must hold for pool-drawn keys")
            -- And the public keys must survive our own validation, or honest peers get
            -- rejected as small-subgroup attackers.
            T.truthy(SPVP.IsValidPublicKey(A), "our own public key must validate")
            T.truthy(SPVP.IsValidPublicKey(B), "our own public key must validate")
        end
    end)
end)

return T
