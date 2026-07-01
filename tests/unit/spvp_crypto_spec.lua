-- tests/unit/spvp_crypto_spec.lua
-- Headless tests for the SPVP SPEKE crypto primitives (pure math).

local T = require("tests.framework")
local H = require("tests.harness")

-- Load spvp.lua into a fresh namespace; it exports primitives via TRP3FW.SPVP
local TRP3FW = H.newNamespace()
TRP3FW.CacheInterface = nil
TRP3FW.spvpSessions = {}
TRP3FW.spvpIncomingSessions = {}
TRP3FW.spvpFailedAttempts = {}
TRP3FW.pendingSaltTickets = {}
TRP3FW.pendingSPVPInits = {}
H.loadModule("features/encryption/spvp.lua", TRP3FW)

local SPVP = TRP3FW.SPVP
local DH_PRIME = 90000049  -- must match the constant in spvp.lua

T.describe("SPVP.ModPow", function()
    T.it("handles base cases", function()
        T.eq(SPVP.ModPow(5, 0, 7), 1, "x^0 = 1")
        T.eq(SPVP.ModPow(0, 5, 7), 0, "0^x = 0")
        T.eq(SPVP.ModPow(5, 1, 7), 5, "x^1 = x")
        T.eq(SPVP.ModPow(123, 456, 1), 0, "mod 1 = 0")
    end)

    T.it("computes known modular exponentiations", function()
        T.eq(SPVP.ModPow(2, 10, 1000), 24, "2^10 mod 1000 = 1024 mod 1000")
        T.eq(SPVP.ModPow(3, 5, 7), 5, "3^5=243, 243 mod 7 = 5")
        T.eq(SPVP.ModPow(7, 4, 13), 9, "7^4=2401, mod 13 = 9")
    end)

    T.it("rejects negative exponents", function()
        T.raises(function() SPVP.ModPow(2, -1, 7) end)
    end)

    T.it("stays within range for large DH_PRIME operands", function()
        local r = SPVP.ModPow(123456, 654321, DH_PRIME)
        T.truthy(r >= 0 and r < DH_PRIME, "result must be in [0, p)")
    end)
end)

T.describe("SPVP.FNV1aHash", function()
    T.it("is deterministic", function()
        T.eq(SPVP.FNV1aHash("hello"), SPVP.FNV1aHash("hello"))
    end)

    T.it("differs for different inputs", function()
        T.neq(SPVP.FNV1aHash("hello"), SPVP.FNV1aHash("hellp"))
    end)

    T.it("produces a 32-bit unsigned value", function()
        local h = SPVP.FNV1aHash("some arbitrary string of bytes")
        T.truthy(h >= 0 and h <= 0xFFFFFFFF, "must fit in 32 bits")
        T.eq(h, math.floor(h), "must be an integer")
    end)

    T.it("matches the known FNV-1a empty-string basis behavior", function()
        -- FNV-1a of "" is the offset basis (no bytes processed)
        T.eq(SPVP.FNV1aHash(""), 2166136261)
    end)
end)

T.describe("SPVP.HashKey", function()
    T.it("returns an 8-char hex string", function()
        local v = SPVP.HashKey(123456789)
        T.eq(#v, 8, "verifier is 8 hex chars")
        T.truthy(v:match("^[0-9a-f]+$"), "lowercase hex only")
    end)

    T.it("is deterministic for the same key", function()
        T.eq(SPVP.HashKey(42), SPVP.HashKey(42))
    end)
end)

T.describe("SPEKE handshake (DH key agreement)", function()
    -- The core security property: Alice and Bob, starting from the SAME generator
    -- (derived from shared phase salt), independently derive the SAME shared key.
    T.it("both parties derive the same shared key from a shared generator", function()
        local generator = SPVP.GetGenerator(123, "DEADBEEFCAFE0123456789ABCDEF00112233445566778899AABBCCDDEEFF0011")

        -- Alice
        local a = SPVP.GeneratePrivateKey()
        local A = SPVP.GeneratePublicKey(generator, a)
        -- Bob
        local b = SPVP.GeneratePrivateKey()
        local B = SPVP.GeneratePublicKey(generator, b)

        -- Shared keys: K = B^a = A^b
        local kAlice = SPVP.DeriveSharedKey(B, a)
        local kBob = SPVP.DeriveSharedKey(A, b)

        T.eq(kAlice, kBob, "DH shared secret must agree")
        -- And the verifier hashes match (what actually goes on the wire)
        T.eq(SPVP.HashKey(kAlice), SPVP.HashKey(kBob))
    end)

    T.it("different generators (different salt) yield different shared keys", function()
        local g1 = SPVP.GetGenerator(123, "AAAA1111BBBB2222CCCC3333DDDD4444EEEE5555FFFF66667777888899990000")
        local g2 = SPVP.GetGenerator(123, "0000999988887777666655554444333322221111FFFFEEEEDDDDCCCCBBBBAAAA")

        local a, b = SPVP.GeneratePrivateKey(), SPVP.GeneratePrivateKey()
        local kImposter = SPVP.DeriveSharedKey(SPVP.GeneratePublicKey(g2, b), a)
        local kReal = SPVP.DeriveSharedKey(SPVP.GeneratePublicKey(g1, b), a)
        -- An attacker without the right salt computes a different generator, so the
        -- verifier won't match. (Keys are overwhelmingly likely to differ.)
        T.neq(SPVP.HashKey(kImposter), SPVP.HashKey(kReal),
            "wrong-salt generator should not produce the same verifier")
    end)

    T.it("generator is always >= 2 (never degenerate)", function()
        -- Even if the hash squared mod p is < 2, GetGenerator clamps to 2.
        local g = SPVP.GetGenerator(0, "")
        T.truthy(g >= 2, "generator must be >= 2")
    end)
end)

T.describe("SPVP.GenerateSessionID", function()
    T.it("returns 8 hex chars", function()
        local s = SPVP.GenerateSessionID()
        T.eq(#s, 8)
        T.truthy(s:match("^[0-9A-F]+$"), "uppercase hex")
    end)
end)

T.describe("IsWellFormedSalt (ticket vs salt discriminator)", function()
    local isSalt = TRP3FW.SPVP_IsWellFormedSalt

    T.it("accepts a real salt (64 hex + : + timestamp)", function()
        local salt = string.rep("A1B2", 16)..":1704844800"  -- 64 hex + timestamp
        T.truthy(isSalt(salt))
    end)

    T.it("accepts a legacy salt (bare hex, no timestamp)", function()
        T.truthy(isSalt(string.rep("deadbeef", 8)))  -- 64 hex, no ":"
    end)

    T.it("rejects the async tickets observed on Epsilon", function()
        -- Real 15-char tickets captured in-game; they contain non-hex letters.
        T.falsy(isSalt("ITOSj3iH7JTRsbY"))
        T.falsy(isSalt("H133TyWLIB4G3sv"))
        T.falsy(isSalt("KjxRrJBdT3hVOfo"))
    end)

    T.it("still accepts bare all-hex strings (legacy salts, no timestamp)", function()
        -- The discriminator's guarantee is that async TICKETS are rejected. It relies on
        -- Epsilon tickets containing non-hex chars (verified above). A bare 32+ hex string
        -- is accepted as a legacy salt by design; if Epsilon ever emits an all-hex ticket
        -- of >=32 chars this branch would misclassify it, but no such ticket has been seen.
        T.truthy(isSalt(string.rep("ab", 20)))  -- 40 hex -> treated as legacy salt
    end)

    T.it("rejects nil, empty, and too-short input", function()
        T.falsy(isSalt(nil))
        T.falsy(isSalt(""))
        T.falsy(isSalt("short"))
        T.falsy(isSalt(12345))
    end)
end)

T.describe("GetPhaseSalt negative-cache signal", function()
    -- GetPhaseSalt must return "" (confirmed no salt), not nil (still loading), on a
    -- negative-cache hit. Downstream SPVP callers treat "" as "no salt, skip" and nil as
    -- "wait" — conflating them kept SPVP engaged for up to an hour on no-salt phases.
    local function withStubCache()
        local fw = H.newNamespace()
        fw.Prefs = { spvpSaltCacheDuration = 10800, spvpPhaseSaltRefreshRate = 50 }
        fw.spvpSessions, fw.spvpIncomingSessions = {}, {}
        fw.spvpFailedAttempts, fw.pendingSaltTickets, fw.pendingSPVPInits = {}, {}, {}
        local store = {}
        fw.CacheInterface = {
            Get = function(_, _, key) return store[key] end,
            Set = function(_, _, key, val) store[key] = val end,
            Remove = function(_, _, key) store[key] = nil end,
            GetSize = function() return 0 end,
        }
        H.loadModule("features/encryption/spvp.lua", fw)
        return fw, store
    end

    T.it("returns \"\" for a fresh negative-cache entry", function()
        local fw, store = withStubCache()
        store[42] = { noSalt = true, timestamp = fw:GetCurrentTime() }
        T.eq(fw:GetPhaseSalt(42, false), "", "negative cache within TTL -> confirmed no salt")
    end)

    T.it("returns a real salt when one is cached", function()
        local fw, store = withStubCache()
        local salt = string.rep("ab", 32)..":1704844800"
        store[42] = { salt = salt, timestamp = fw:GetCurrentTime() }
        T.eq(fw:GetPhaseSalt(42, false), salt)
    end)
end)

return T
