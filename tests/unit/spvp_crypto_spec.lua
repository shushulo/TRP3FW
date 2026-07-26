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
-- Must match the constant in spvp.lua. This is a SAFE prime (p = 2q+1, q = 46999871 prime):
-- the previous 90000049 had p-1 = 2^4 * 3 * 971 * 1931, all small factors, so Pohlig-Hellman
-- reduced the discrete log to ~sqrt(1931) = 44 operations.
local DH_PRIME = 93999743
local DH_SUBGROUP_ORDER = 46999871

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

T.describe("DH group parameters", function()
    local function isPrime(n)
        if n < 2 then return false end
        if n % 2 == 0 then return n == 2 end
        local i = 3
        while i * i <= n do
            if n % i == 0 then return false end
            i = i + 2
        end
        return true
    end

    T.it("DH_PRIME is prime", function()
        T.truthy(isPrime(DH_PRIME), DH_PRIME.." must be prime")
    end)

    T.it("is a SAFE prime: p = 2q+1 with q also prime", function()
        -- This is the property that defeats Pohlig-Hellman. Without it, p-1 factors into
        -- small primes and the discrete log decomposes into tiny subgroups.
        T.eq((DH_PRIME - 1) / 2, DH_SUBGROUP_ORDER, "q must be (p-1)/2")
        T.truthy(isPrime(DH_SUBGROUP_ORDER), DH_SUBGROUP_ORDER.." must be prime")
    end)

    T.it("ModPow's intermediate stays exactly representable in a double", function()
        -- ModPow computes base*base BEFORE reducing, so (p-1)^2 must be < 2^53 or the
        -- arithmetic silently produces WRONG answers rather than merely weak ones.
        local maxIntermediate = (DH_PRIME - 1) * (DH_PRIME - 1)
        T.truthy(maxIntermediate < 2 ^ 53,
            "(p-1)^2 must fit in a double's exact-integer range")
        T.eq(maxIntermediate, math.floor(maxIntermediate), "must be an exact integer")
    end)

    T.it("a handshake round-trips under the new prime", function()
        local g = 4
        local a, b = 12345678, 87654321
        local A = SPVP.ModPow(g, a, DH_PRIME)
        local B = SPVP.ModPow(g, b, DH_PRIME)
        T.eq(SPVP.ModPow(B, a, DH_PRIME), SPVP.ModPow(A, b, DH_PRIME),
            "both sides must derive the same shared key")
    end)
end)

T.describe("GetGenerator subgroup validation", function()
    T.it("produces a generator in the large prime subgroup", function()
        local g = SPVP.GetGenerator(184739, string.rep("a", 64) .. ":1704844800")
        T.eq(SPVP.ModPow(g, DH_SUBGROUP_ORDER, DH_PRIME), 1,
            "g^q mod p must be 1, i.e. g lies in the order-q subgroup")
    end)

    T.it("never returns a degenerate generator across many salts", function()
        -- g == 1 or g == p-1 would collapse the shared key to a single value, making the
        -- handshake succeed for anyone regardless of phase.
        for i = 1, 300 do
            local salt = string.format("%064x:%d", i * 7919, 1704844800 + i)
            local g = SPVP.GetGenerator(1000 + i, salt)
            T.truthy(g ~= 1 and g ~= DH_PRIME - 1,
                "degenerate generator produced for salt #" .. i .. " (g=" .. g .. ")")
            T.eq(SPVP.ModPow(g, DH_SUBGROUP_ORDER, DH_PRIME), 1,
                "generator outside the large subgroup for salt #" .. i)
        end
    end)

    T.it("is deterministic: same phase+salt gives the same generator", function()
        -- Both peers must derive the same g from the same salt or nothing verifies.
        local salt = string.rep("f", 64) .. ":1704844800"
        T.eq(SPVP.GetGenerator(555, salt), SPVP.GetGenerator(555, salt))
    end)

    T.it("differs across phases and across salts", function()
        local saltA = string.rep("a", 64) .. ":1704844800"
        local saltB = string.rep("b", 64) .. ":1704844800"
        T.neq(SPVP.GetGenerator(111, saltA), SPVP.GetGenerator(222, saltA),
            "different phase must give a different generator")
        T.neq(SPVP.GetGenerator(111, saltA), SPVP.GetGenerator(111, saltB),
            "different salt must give a different generator")
    end)
end)

T.describe("SPVP.HashKey", function()
    -- WIDENED 32 -> 64 bits. The old 8-char verifier was a single FNV-1a, and FNV-1a has no
    -- collision resistance -- by the birthday bound an attacker needed only ~2^16 tries to
    -- find a colliding verifier without solving any discrete log. That made the verifier the
    -- cheapest attack on the whole protocol, below even the group weakness it sits on.
    T.it("returns a 16-char hex string (64-bit verifier)", function()
        local v = SPVP.HashKey(123456789)
        T.eq(#v, 16, "verifier is 16 hex chars")
        T.truthy(v:match("^[0-9a-f]+$"), "lowercase hex only")
    end)

    T.it("is deterministic for the same key", function()
        T.eq(SPVP.HashKey(42), SPVP.HashKey(42))
    end)

    T.it("distinguishes different keys", function()
        T.neq(SPVP.HashKey(42), SPVP.HashKey(43))
    end)

    T.it("both 32-bit halves participate", function()
        -- Guards against a refactor that accidentally makes one half constant, which would
        -- silently put the birthday bound back at 2^16.
        local hiSeen, loSeen = {}, {}
        for k = 1, 200 do
            local v = SPVP.HashKey(k * 7919)
            hiSeen[v:sub(1, 8)] = true
            loSeen[v:sub(9, 16)] = true
        end
        local hiCount, loCount = 0, 0
        for _ in pairs(hiSeen) do hiCount = hiCount + 1 end
        for _ in pairs(loSeen) do loCount = loCount + 1 end
        T.truthy(hiCount > 150, "high half must vary, got "..hiCount.." distinct")
        T.truthy(loCount > 150, "low half must vary, got "..loCount.." distinct")
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
