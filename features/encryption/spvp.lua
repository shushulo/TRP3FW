-- ===================================================================
-- TRP3 Firewall - SPVP (Secure Phase Verification Protocol) v2.5
-- ===================================================================
-- SPEKE-based phase verification.
-- Uses a server-side phase salt + SPEKE handshake to prevent spoofing.
--
-- THREAT MODEL -- READ BEFORE RELYING ON THIS.
--
-- WHO THE ATTACKER IS. Not a passive eavesdropper: every SPVP packet is sent by WHISPER,
-- point-to-point, so there is no broadcast traffic to sniff. The realistic attacker is the
-- PEER ITSELF -- someone who requests your profile, receives your public value as a normal
-- part of the handshake, and computes against it offline with no rate limit. The party the
-- firewall exists to screen is the party the protocol hands its inputs to. That is inherent
-- to any Diffie-Hellman exchange and is fine when the group is large; the group here is not.
--
-- CURRENT SECURITY (measured, not estimated):
--
--   * Discrete log in the group: best generic attack is Pollard's rho at ~1.03*sqrt(q) = 7061
--     steps, i.e. ~2^12.7. Verified that 100% of 3000 simulated salts produce a generator of
--     order exactly q, so Pohlig-Hellman gains nothing.
--   * Private key: GeneratePrivateKey draws ONE value from math.random after seeding from
--     GUID + microsecond time + cursor. The key is therefore a pure function of that seed,
--     and the attacker knows our GUID and roughly WHEN we sent the packet. Measured search
--     space is ~2^10 if send time is known to ~1ms, ~2^17 at ~100ms -- at or below the group
--     strength. See GeneratePrivateKey for the fix status.
--   * Verifier collision: HashKey is 64 bits, so the birthday bound is ~2^32.
--   * Peer public keys are validated on receipt (IsValidPublicKey), closing a
--     small-subgroup confinement forgery that cost ZERO work and needed no salt knowledge.
--   * Binding constraint: ~2^12.7.
--
-- WHAT ~2^12.7 ACTUALLY COSTS -- do not read the exponent and stop there.
--
-- 2^12.7 is ~21,000 modular multiplications (7061 rho steps at ~3 modmuls each). Measured
-- throughput in interpreted Lua 5.1 is 4.6e7 modmul/sec, so a full Pollard's rho run finishes
-- in ~0.46 MILLISECONDS -- in Lua, on one core. That is under a single frame at 60fps.
--
-- The practical consequence: an attacker needs no external tooling. An ordinary WoW addon can
-- complete one honest handshake, recover our private exponent before the next frame draws, and
-- forge verifiers from then on. Not a rented server, not C -- a .lua file.
--
-- CORRECTION: this header previously read "Hours of compute, not centuries." That was a
-- careless translation from 2^12.7 to wall-clock and overstated the attacker's cost by roughly
-- seven orders of magnitude. The security exponent was right; the time estimate was not.
-- thoughts/SPVP_CRYPTO_UPGRADE_SPEC.md has the measurement method.
--
-- Note also that RATE LIMITING DOES NOT APPLY to any of this. spvpBlockDuration, replay
-- detection and the queue caps all bound how often a peer can SEND us packets. Rho is offline:
-- the attacker completes one legitimate handshake, walks away, and computes against the public
-- value we already handed them. There is no packet left to throttle.
--
-- HISTORY -- what these numbers were before, and why:
--
--   * DH_PRIME was 90000049. It was prime and correctly sized, but p-1 factored as
--     2^4 * 3 * 971 * 1931. Pohlig-Hellman decomposes a discrete log into the prime-power
--     subgroups of the generator's order, so the work factor collapsed to ~sqrt(1931) = 44
--     operations -- about 2^5.5, i.e. microseconds. The SIZE of the prime was never the
--     problem; its FACTORISATION was.
--   * HashKey produced 32 bits, so a colliding verifier cost ~2^16 tries and could be found
--     WITHOUT touching the group at all. That was the cheapest attack on the protocol.
--   * Peer public keys were used unvalidated. Sending B = 0, 1 or p (all matched by the
--     wire pattern (%d+)) forced K = B^a mod p to a CONSTANT independent of the honest
--     party's secret, so the attacker computed HashKey(K) offline and sent a verifier that
--     matched every time -- no discrete log, no salt, no phase membership. It defeated the
--     one thing SPVP proves. Cost: zero, versus ~2^12.7 for the group and ~2^32 for the
--     verifier, making it by far the cheapest attack until it was closed. Both receive
--     paths now gate on IsValidPublicKey; measured over 26,000 honest keys the guard
--     rejects none, so it needed no protocol version bump.
--
-- TWO DIFFERENT ADVERSARIES. Conflating them leads to opposite conclusions about whether the
-- group size matters at all, so keep them separate:
--
--   (A) ADMITTED MEMBER. Anyone the phase lets in can read the salt directly --
--       C_Epsilon.GetPhaseAddonData("TRP3FW_SPVP_KEY") is a one-line macro, and this is NOT
--       limited to owners and officers as this header once claimed. Phase MEMBERSHIP is the
--       boundary, not rank. A member standing in a different ZONE therefore passes SPVP from
--       anywhere, without attacking anything -- that is the protocol working as designed.
--       Group strength is irrelevant to this adversary: they hold the real secret.
--
--   (B) EXCLUDED OUTSIDER. Someone blacklisted or never whitelisted is not admitted, so
--       GetPhaseAddonData gives them nothing. They have NO salt. To pass SPVP they must break
--       the math -- rho on our public key (~2^12.7) or guessing the private key (~2^10-2^17).
--       Group strength IS the binding constraint for this adversary, and at present it does
--       not stop them. This is the case SPVP exists to defeat.
--
-- So what SPVP actually proves is: "this peer has, at some point, been admitted to a phase
-- sharing this salt." NOT "is in my phase" and NOT "is near me." Membership at SOME time --
-- a salt does not expire when someone leaves or is blacklisted, so a removed member keeps a
-- working salt until the phase is re-secured. Nothing here rotates it on removal.
--
-- WHAT IS STILL WEAK:
--
--   * ~2^12.7 is not cryptographic strength, and per the timing note above it is ~0.46ms of
--     in-game Lua. It does not deter adversary (B) at all.
--   * The private key may be a cheaper target than the group; see the entropy note above.
--   * FNV-1a is a hash-TABLE function with no collision resistance. Two rounds give 64 bits
--     of output but are not equivalent to one round of a real hash.
--   * Against adversary (A) none of the above matters, and no amount of group strength fixes
--     a shared secret with that distribution. Proximity is measured by the phase/WHO/map
--     checks, not by SPVP.
--
-- WHY IT CANNOT BE STRONGER. Lua 5.1 has no integer type; numbers are doubles, exact only to
-- 2^53. ModPow computes base*base BEFORE reducing, so the modulus must satisfy p^2 < 2^53,
-- capping p at ~94906265 (~2^26.5). Above that the arithmetic silently produces WRONG results
-- rather than merely weak ones. Bignum arithmetic in interpreted Lua, per profile send, on
-- the game client, is not viable. This is a platform ceiling, not an implementation choice.
--
-- Appropriate use: making phase spoofing inconvenient for the casual case.
-- Inappropriate use: anything where being wrong has real consequences for the user.
-- ===================================================================

local addonName, TRP3FW = ...

-- ===================================================================
-- CONSTANTS
-- ===================================================================

-- Diffie-Hellman SAFE prime: p = 2q + 1 where q = 46999871 is also prime.
--
-- The previous value (90000049) was prime and correctly sized, but p-1 factored as
-- 2^4 * 3 * 971 * 1931 -- all small factors. Pohlig-Hellman decomposes a discrete log into
-- the prime-power subgroups of the generator's order and recombines by CRT, so the work
-- factor collapses to roughly sqrt(largest prime factor). Measured across 5000 simulated
-- salts, EVERY generator order shared the same largest factor, 1931, giving an effective
-- security of ~sqrt(1931) = 44 operations. Microseconds -- and available to the legitimate
-- handshake peer, who already holds our public value.
--
-- With a safe prime, p-1 = 2q has no small factors, so Pohlig-Hellman buys nothing and the
-- best generic attack is Pollard's rho at ~sqrt(q) = 6856 operations (~2^12.7). That is a
-- ~157x improvement for a one-constant change.
--
-- SIZE CEILING: ModPow computes base*base BEFORE reducing, so the intermediate reaches
-- (p-1)^2 and must stay exactly representable in a double (< 2^53). That caps p at
-- ~94906265. This value sits at 1.9% headroom below the limit; the largest safe prime under
-- the cap (94905947) leaves only 0.0007%, which is too thin a margin for a value that must
-- be exact.
--
-- See the threat-model note above: even after this change SPVP is well below cryptographic
-- strength. The improvement is real but the ceiling is set by Lua 5.1's doubles.
local DH_PRIME = 93999743

-- Order of the large prime subgroup: q = (DH_PRIME - 1) / 2.
-- Used to reject degenerate generators (see GetGenerator).
local DH_SUBGROUP_ORDER = 46999871

-- SPVP protocol version.
-- BUMPED 2 -> 3: DH_PRIME changed, so a v2 client derives a different generator from the same
-- salt and every cross-version handshake would fail with a verifier mismatch -- which
-- HandleSPVPReply treats as a hostile peer and BLOCKS. HandleSPVPInit rejects mismatched
-- versions outright, so the bump turns a silent mutual-block into a clean no-op.
local SPVP_VERSION = 3

-- Timeout and retry settings
local SPVP_TIMEOUT_SECONDS = 5
local SPVP_MAX_RETRIES = 2

-- ===================================================================
-- UTILITIES
-- ===================================================================

--- Distinguish an inline phase salt from an async request ticket.
--- GetPhaseAddonData returns EITHER the salt data (our generator emits exactly
--- 64 hex chars + ":" + a UTC timestamp) OR a short async ticket handle. On Epsilon
--- these tickets are ~15 mixed-case alphanumeric chars (e.g. "ITOSj3iH7JTRsbY") that
--- contain non-hex letters, so an anchored hex-shape match separates them cleanly.
--- Previously the check was `#result >= 32 and match("^[0-9a-fA-F:]+$")`, which is
--- fine for today's 15-char tickets but would misclassify any future longer ticket
--- that happened to be hex-only. Anchoring to the exact salt shape is stricter.
--- Accepts both the current form (hex:timestamp) and legacy salts with no timestamp.
--- @param s string|nil
--- @return boolean - true if s looks like a real salt (not a ticket / not empty)
local function IsWellFormedSalt(s)
    if type(s) ~= "string" or #s < 32 then return false end
    -- Current form: 64 hex + ":" + digits. Legacy form: bare hex (>=32), no timestamp.
    return s:match("^%x+:%d+$") ~= nil or s:match("^%x+$") ~= nil
end
TRP3FW.SPVP_IsWellFormedSalt = IsWellFormedSalt  -- exported for tests

--- FNV-1a hash function (32-bit)
--- @param data string - Input data to hash
--- @return number - 32-bit hash value
local function FNV1aHash(data)
    local hash = 2166136261 -- FNV offset basis

    for i = 1, #data do
        hash = bit.bxor(hash, string.byte(data, i))
        hash = hash * 16777619 -- FNV prime
        hash = bit.band(hash, 0xFFFFFFFF) -- Keep 32-bit
    end

    return hash
end

--- Modular exponentiation: (base^exp) mod m
--- Uses binary exponentiation to prevent overflow in Lua doubles
--- @param base number - Base value
--- @param exp number - Exponent (non-negative integer)
--- @param m number - Modulus
--- @return number - Result of (base^exp) mod m
local function ModPow(base, exp, m)
    -- Edge cases
    if m == 1 then return 0 end
    if exp == 0 then return 1 end
    if exp < 0 then
        error("ModPow: negative exponents not supported")
    end

    local result = 1
    base = base % m

    -- Binary exponentiation (keeps intermediate values < m^2)
    while exp > 0 do
        if exp % 2 == 1 then
            result = (result * base) % m
        end
        exp = math.floor(exp / 2)
        base = (base * base) % m
    end

    return result
end

--- Hash a key to create verifier (16-char hex, 64-bit)
---
--- WIDENED from 32 to 64 bits. The old form was a single FNV-1a over tostring(K), truncated to
--- 8 hex chars. FNV-1a is a hash-TABLE function with no collision resistance, so by the
--- birthday bound an attacker needed only ~2^16 (65,536) tries to find SOME value whose
--- verifier matched -- without solving any discrete log at all. That made the verifier the
--- CHEAPEST attack on the protocol, cheaper than the group weakness it sits on top of, and
--- fixing the prime alone would have left it as the binding constraint.
---
--- Two independent FNV-1a rounds over differently-domain-separated inputs give 64 bits, moving
--- the birthday bound to ~2^32. Not cryptographic -- FNV-1a is still FNV-1a, and two rounds of
--- a weak hash is not equivalent to one round of a strong one -- but it removes a shortcut
--- that was orders of magnitude below every other attack.
---
--- Wire cost: 8 extra characters per REPLY/CONFIRM packet.
--- @param sharedKey number - Shared key from handshake
--- @return string - 16-character hex hash
local function HashKey(sharedKey)
    local keyStr = tostring(sharedKey)
    -- Distinct prefixes so the two halves cannot collapse to the same value.
    local hi = FNV1aHash("SPVP-A:" .. keyStr)
    local lo = FNV1aHash("SPVP-B:" .. keyStr .. ":" .. keyStr)
    return string.format("%08x%08x", hi, lo)
end

--- Safe wrapper for math.randomseed (handles environments where it's missing)
--- @param seed number - Seed value
local function SafeRandomSeed(seed)
    if math.randomseed then
        math.randomseed(seed)
    end
end

-- ===================================================================
-- ENTROPY POOL
-- ===================================================================
--
-- WHY THIS EXISTS. Every secret here used to be produced the same way: build a seed from
-- (GUID + microsecond time + cursor position), call math.randomseed, draw ONE value. That
-- makes the output a pure function of the seed, so the real keyspace is the SEED space, not
-- the nominal [2, p-2].
--
-- Decomposed by what the attacker -- who IS the peer -- actually knows:
--   * GUID: they know it. Constant, not secret.
--   * Cursor: bounded by screen resolution, and mouse_x*1337 + mouse_y*7331 collapses hard.
--   * floor(now * 1e6) % 2^31: the dominant term, and they know roughly WHEN we sent the
--     packet, because they received it.
--
-- Measured: 1000 adjacent microsecond seeds give 1000 distinct keys -- no collapse, but no
-- amplification either. Bound the send time to ~1ms and the search is ~2^10; to ~100ms and it
-- is ~2^17. Both are at or BELOW the group's own ~2^12.7, so this was plausibly the cheapest
-- attack on SPVP -- and unlike the group weakness it needs no bignum work to fix.
--
-- WHAT THIS DOES. Accumulate entropy across the whole session instead of rebuilding a seed at
-- each call, and never let a single observable quantity dominate. Each Stir folds a new sample
-- into a retained 32-bit state via FNV-1a, so the pool's value depends on the ENTIRE history of
-- samples -- timings, cursor positions, framerates, event arrivals -- not just the latest one.
-- To predict a draw an attacker must reproduce that whole history, not one timestamp.
--
-- WHAT THIS IS NOT. Lua 5.1's math.random is still the underlying generator and its internal
-- state is still far smaller than the group. This raises a floor that sat well below the
-- group; it does not lift the ceiling that Pollard's rho sets (~2^12.7), and it cannot -- rho
-- attacks the GROUP and works regardless of how well the exponent was chosen. Only a larger
-- prime moves that. See thoughts/SPVP_CRYPTO_UPGRADE_SPEC.md section 4.4.

local entropyPool = 2166136261  -- FNV offset basis; folded, never reset
local entropyStirCount = 0
local entropyDrawCounter = 0    -- strictly increasing; guarantees per-draw seed divergence

--- Normalise a 32-bit value to unsigned.
---
--- REQUIRED, not cosmetic. bit.band returns a SIGNED 32-bit int on LuaJIT (and on the test
--- shim), so FNV1aHash yields a negative number whenever the top bit is set -- about half the
--- time. Feeding a negative value to math.randomseed collapses many distinct pool states onto
--- the same RNG stream: observed directly, the pool kept landing on -2^31 and successive
--- private keys repeated the SAME value (33842432) across unrelated draws. That is strictly
--- worse than the entropy weakness this pool was written to fix, so keep the pool unsigned.
--- @param n number - Possibly-negative 32-bit value
--- @return number - Value in [0, 2^32)
local function ToUnsigned32(n)
    n = n % 4294967296  -- 2^32
    if n < 0 then n = n + 4294967296 end
    return n
end

--- Fold an arbitrary value into the pool. Cheap enough to call from hot paths.
--- Order matters: stirring A then B differs from B then A, so the pool encodes history.
--- @param value any - Any value; stringified before folding
local function StirEntropy(value)
    entropyPool = ToUnsigned32(FNV1aHash(tostring(entropyPool) .. ":" .. tostring(value)))
    entropyStirCount = entropyStirCount + 1
    return entropyPool
end

--- Sample every ambient source we can reach and fold them all in.
--- Called before drawing any secret, and from event hooks so the pool keeps moving between
--- handshakes rather than only at the moment an attacker can predict.
local function StirAmbientEntropy()
    local now = GetTimePreciseSec and GetTimePreciseSec() or GetTime()
    StirEntropy(now)
    StirEntropy(GetTime and GetTime() or 0)

    if GetCursorPosition then
        local mx, my = GetCursorPosition()
        -- Fold separately: combining them arithmetically (as the old seed did) discards
        -- information that keeping them distinct preserves.
        StirEntropy(mx or 0)
        StirEntropy(my or 0)
    end

    if GetFramerate then StirEntropy(GetFramerate()) end
    -- Millisecond-resolution timer on a different epoch from GetTimePreciseSec.
    if debugprofilestop then StirEntropy(debugprofilestop()) end
    if UnitGUID then StirEntropy(UnitGUID("player") or "NOGUID") end
    if math.random then StirEntropy(math.random()) end  -- carries forward existing PRNG state

    return entropyPool
end

--- Draw an integer in [lo, hi] from the pool.
---
--- Reseeds math.random from the POOL rather than from a freshly-built observable seed, then
--- discards a few outputs. The reseed value depends on every sample ever stirred, so an
--- attacker who knows the send time to the microsecond still cannot reconstruct it.
--- @param lo number - Lower bound (inclusive)
--- @param hi number - Upper bound (inclusive)
--- @return number - Value in [lo, hi]
local function DrawFromPool(lo, hi)
    -- Strictly-increasing counter, stirred FIRST. The ambient sources can all be frozen --
    -- same frame, motionless cursor, stable framerate -- and on a live client several draws
    -- routinely happen inside one frame (a salt makes 64 back to back). Without a term that
    -- cannot repeat, the pool could re-enter a previous state and replay the same value; that
    -- was observed before this counter existed. This does not ADD entropy (a counter is fully
    -- predictable) -- it guarantees SEPARATION, so the pool's accumulated entropy is never
    -- re-used across draws rather than being spread across them.
    entropyDrawCounter = entropyDrawCounter + 1
    StirEntropy(entropyDrawCounter)

    StirAmbientEntropy()

    -- Map the pool into a seed that survives math.randomseed's truncation.
    --
    -- math.randomseed coerces to a SIGNED 32-bit int, so 0, 2^31, -2^31 and 2^32 all alias to
    -- seed 0 -- which on this interpreter deterministically produces 33842432 from the private
    -- key range. Measured before this fold: that single value came up 23 times in 50 draws
    -- (~46%), because roughly half of all pool states landed on one of those aliases. Two
    -- handshakes sharing a private key means solving one solves both, so this mattered far
    -- more than the entropy weakness the pool was written to fix.
    --
    -- Reducing modulo 2^31-1 (a prime, and the largest safe positive seed) and shifting off
    -- zero keeps every distinct pool state mapped to a distinct, non-degenerate seed.
    local seed = (entropyPool % 2147483647) + 1
    SafeRandomSeed(seed)
    for _ = 1, 5 do math.random() end

    local value = math.random(lo, hi)
    -- Fold the result back in so successive draws in the same tick do not share a seed.
    StirEntropy(value)
    return value
end

-- Exported for tests and diagnostics. GetEntropyStirCount lets a spec assert the pool is
-- actually being fed; it exposes the COUNT, never the pool value itself.
TRP3FW.SPVP_StirEntropy = StirEntropy
TRP3FW.SPVP_GetEntropyStirCount = function() return entropyStirCount end

-- ===================================================================
-- GENERATOR CALCULATION
-- ===================================================================

--- Get SPEKE generator from Phase ID and Phase Salt
--- Generator is the secret: G = (Hash(PhaseID + PhaseSalt)^2) mod p
--- @param phaseID number - Current phase ID
--- @param phaseSalt string - Optional cached phase salt (if nil, will fetch from cache)
--- @return number - Generator value
local function GetGenerator(phaseID, phaseSalt)
    TRP3FW.profiler.start("SPVP:GetGenerator")
    -- 1. Base: Phase ID
    local entropy = tostring(phaseID or 0)

    -- 2. Phase Salt (Server-Side Secret)
    -- IMPORTANT: Use FULL salt including timestamp for crypto
    -- Both Alice and Bob read the same phase data, so they get identical salt strings
    if not phaseSalt then
        -- Fetch from cache if not provided
        phaseSalt = TRP3FW:GetPhaseSalt(phaseID, false)
    end

    if phaseSalt and phaseSalt ~= "" then
        entropy = entropy .. ":" .. phaseSalt  -- Full salt with timestamp!
    end

    -- Example entropy string:
    -- "5:A3F2E9D1C4B7A6F5E4D3C2B1A0F9E8D7C6B5A4F3E2D1C0B9A8F7E6D5C4B3A2F1:1704844800"
    --  ^  ^--- 64-char hex ---^                                                 ^--- timestamp

    -- Hash into a 32-bit integer (FNV-1a)
    local hash = FNV1aHash(entropy)

    -- Square to ensure quadratic residue group (USE ModPow!)
    local g = ModPow(hash, 2, DH_PRIME)
    if g < 2 then g = 2 end

    -- Reject degenerate generators.
    --
    -- With a SAFE prime (p = 2q+1) the multiplicative group has exactly four subgroup orders:
    -- 1, 2, q and 2q. Squaring lands g in the quadratic residues, so g should have order q --
    -- but g == 1 (order 1) and g == p-1 (order 2) are still reachable when the hash happens to
    -- land there, and either collapses the shared key to a single value: the handshake would
    -- then "succeed" for anyone, in phase or not.
    --
    -- One ModPow settles it: if g^q mod p ~= 1, g is not in the large subgroup. Cheap
    -- insurance -- this runs once per handshake, not per operation.
    if g == 1 or g == DH_PRIME - 1 or ModPow(g, DH_SUBGROUP_ORDER, DH_PRIME) ~= 1 then
        -- Deterministic fallback: 4 is a quadratic residue (2^2) and generates the large
        -- subgroup for this prime. Both peers derive the same salt, so both land here
        -- together and still agree -- degrading to a fixed generator rather than a broken one.
        TRP3FW:Debug("[SPVP] Degenerate generator rejected, using subgroup fallback", "spvp")
        g = 4
    end

    TRP3FW.profiler.stop("SPVP:GetGenerator")
    return g
end

-- ===================================================================
-- KEY GENERATION
-- ===================================================================

--- Generate a random private key from the session entropy pool.
---
--- Previously this built a seed from (GUID + microsecond time + cursor) and drew a single
--- value, which made the key a pure function of quantities the peer largely knows -- measured
--- at ~2^10 to ~2^17 of real search space, at or below the group's own ~2^12.7. See the
--- ENTROPY POOL section above for the measurement and the limits of this fix.
--- @return number - Private key in range [2, DH_PRIME-2]
local function GeneratePrivateKey()
    return DrawFromPool(2, DH_PRIME - 2)
end

--- Generate public key: A = G^a mod p
--- @param generator number - SPEKE generator
--- @param privateKey number - Private key
--- @return number - Public key
local function GeneratePublicKey(generator, privateKey)
    return ModPow(generator, privateKey, DH_PRIME)
end

--- Validate a peer's public key before using it in a key exchange.
---
--- Without this check the protocol is trivially forgeable, and the forgery needs NO knowledge
--- of the phase salt -- which is the one secret SPVP exists to prove possession of.
---
--- The attack is small-subgroup confinement. K = B^a mod p, so an attacker who sends a B whose
--- order is 1 or 2 makes K independent of the honest party's secret exponent `a`:
---   B = 0    -> K = 0 always      (and B = p is the same element)
---   B = 1    -> K = 1 always
---   B = p-1  -> K in {1, p-1}, decided only by the parity of `a` -- one guess, 50%, retryable
--- The attacker then computes HashKey(K) offline and sends a verifier that matches. Both
--- HandleSPVPInit (Bob) and HandleSPVPReply (Alice) accept `(%d+)` off the wire and fed it
--- straight to ModPow, so either side could be spoofed by any player who can whisper an addon
--- message -- no phase membership, no salt, no discrete log.
---
--- The check is the standard one: require 2 <= B <= p-2 (excludes 0, 1, p-1 and anything >= p),
--- then confirm B is in the order-q subgroup via B^q mod p == 1. The subgroup test is what
--- GetGenerator already does for its own generator; this applies the same standard to values
--- that arrive from the network, which is where it matters more.
---
--- @param theirPublicKey number|nil - Candidate public key from the wire
--- @return boolean - true if safe to use in DeriveSharedKey
local function IsValidPublicKey(theirPublicKey)
    if type(theirPublicKey) ~= "number" then return false end
    -- Reject non-integers and NaN (NaN fails every comparison, including == itself).
    if theirPublicKey ~= math.floor(theirPublicKey) then return false end
    -- Excludes 0, 1, p-1 and p (and any out-of-range value) in one range test.
    if theirPublicKey < 2 or theirPublicKey > DH_PRIME - 2 then return false end
    -- Must live in the large (order-q) subgroup, not a small one.
    return ModPow(theirPublicKey, DH_SUBGROUP_ORDER, DH_PRIME) == 1
end

--- Derive shared key: K = B^a mod p
--- Callers MUST gate on IsValidPublicKey first; see the attack described there.
--- @param theirPublicKey number - Their public key
--- @param myPrivateKey number - My private key
--- @return number - Shared key
local function DeriveSharedKey(theirPublicKey, myPrivateKey)
    TRP3FW.profiler.start("SPVP:DeriveKey")
    local key = ModPow(theirPublicKey, myPrivateKey, DH_PRIME)
    TRP3FW.profiler.stop("SPVP:DeriveKey")
    return key
end

-- ===================================================================
-- SESSION ID GENERATION
-- ===================================================================

--- Generate a random session ID (8-char hex) from the session entropy pool.
---
--- The per-character re-seed this used to do looked like hardening but was the opposite: every
--- character was reseeded from the SAME three observable quantities, differing only by the
--- loop index, so the whole ID collapsed to roughly the entropy of one draw. Drawing from the
--- pool keeps the characters independent of each other and of the send time.
---
--- Session IDs are lower-stakes than private keys -- they are replay/correlation handles, not
--- secrets -- but they are attacker-visible, so a predictable ID would let a peer anticipate
--- our next session and pre-place state against it.
--- @return string - 8-character hex session ID
local function GenerateSessionID()
    local chars = "0123456789ABCDEF"
    local sessionID = ""

    for _ = 1, 8 do
        local r = DrawFromPool(1, 16)
        sessionID = sessionID .. chars:sub(r, r)
    end

    return sessionID
end

-- ===================================================================
-- PHASE SALT MANAGEMENT
-- ===================================================================

--- Generate phase salt with timestamp for tracking
--- Format: 64-char-hex:UTC-timestamp
--- Example: "A3F2E9...D1C4:1704844800"
---
--- ENTROPY. The old implementation reseeded every 2 characters from (GUID + microsecond time +
--- cursor + framerate) and claimed "~100-120 bits" in this comment. That claim did not hold:
--- the 64 characters were not independent, because each reseed drew on the same few observable
--- quantities separated by microseconds, so the salt's real entropy was closer to a single
--- seed's than to 256 bits of hex. This now draws every character from the session pool, whose
--- state depends on the entire history of stirred samples. See the ENTROPY POOL section.
---
--- This matters more than the private key does. A private key compromise costs one handshake;
--- the salt is the shared secret the ENTIRE protocol rests on, it is what SPVP proves
--- possession of, and it persists in phase addon data until someone re-secures the phase.
--- @return string - Phase salt (64 hex chars + colon + UTC timestamp)
function TRP3FW:GeneratePhaseSalt()
    TRP3FW.profiler.start("SPVP:GenerateSalt")

    local chars = "0123456789ABCDEF"
    local salt = ""

    for _ = 1, 64 do
        local r = DrawFromPool(1, 16)
        salt = salt .. chars:sub(r, r)
    end

    -- Append UTC timestamp for tracking (self-documenting)
    local utcTimestamp = time()  -- UTC seconds since epoch
    salt = salt .. ":" .. tostring(utcTimestamp)

    TRP3FW.profiler.stop("SPVP:GenerateSalt")
    return salt
end

--- Parse phase salt to extract timestamp (for UI display ONLY)
--- @param salt string - Full salt string (with or without timestamp)
--- @return string, number|nil - (salt_part, timestamp)
function TRP3FW:ParsePhaseSalt(salt)
    if not salt then return "", nil end

    -- Try to extract timestamp (format: salt:timestamp)
    local saltPart, timestampStr = salt:match("^(.+):(%d+)$")

    if saltPart and timestampStr then
        return saltPart, tonumber(timestampStr)
    else
        -- Legacy format (no timestamp)
        return salt, nil
    end
end

--- Check if phase salt is old and should be rotated
--- @return boolean, number|nil - (needs_rotation, days_old)
function TRP3FW:CheckSaltRotation()
    if not C_Epsilon or not C_Epsilon.GetPhaseAddonData then
        return false, nil
    end

    local existingSalt = C_Epsilon.GetPhaseAddonData("TRP3FW_SPVP_KEY")
    if not existingSalt or existingSalt == "" then
        return false, nil
    end

    local _, timestamp = self:ParsePhaseSalt(existingSalt)
    if not timestamp then
        -- Legacy salt (unknown age) - recommend rotation
        return true, nil
    end

    local daysOld = math.floor((time() - timestamp) / 86400)

    -- Recommend rotation after 30 days
    return daysOld > 30, daysOld
end

--- Secure current phase with SPVP salt
function TRP3FW:SecureCurrentPhase()
    -- Check permissions (must call the functions, not just check existence)
    local isOwner = C_Epsilon.IsOwner and C_Epsilon.IsOwner()
    local isOfficer = C_Epsilon.IsOfficer and C_Epsilon.IsOfficer()

    if not C_Epsilon or not (isOwner or isOfficer) then
        self:Error("You must be a phase owner or officer to secure phases.")
        return
    end

    local salt = self:GeneratePhaseSalt()

    if not salt or #salt < 32 then
        self:Error("Generated salt is invalid/weak. Aborting secure.")
        return
    end

    C_Epsilon.SetPhaseAddonData("TRP3FW_SPVP_KEY", salt)

    -- Invalidate cache and update with new salt
    local phaseID = self:GetCurrentPhaseID()
    if phaseID then
        local CI = self.CacheInterface
        if CI then
            CI:Set("spvpPhaseSalt", phaseID, {
                salt = salt,
                timestamp = self:GetCurrentTime()
            })
            if self.sessionStats and self.sessionStats.spvpCache then
                self.sessionStats.spvpCache.activeEntries = CI:GetSize("spvpPhaseSalt") or 0
            end
        end
    end

    -- Parse timestamp for user feedback
    local _, timestamp = self:ParsePhaseSalt(salt)
    local dateStr = timestamp and date("%Y-%m-%d %H:%M UTC", timestamp) or "unknown"

    self:Info("Phase secured successfully! (Generated: " .. dateStr .. ")")
end

-- ===================================================================
-- PHASE SALT CACHING
-- ===================================================================

--- Get phase salt from cache or API (with 3-hour cache)
--- @param phaseID number - Phase ID to get salt for
--- @param forceRefresh boolean - Force cache refresh (on handshake failure)
--- @return string|nil - Phase salt or nil if not available
function TRP3FW:GetPhaseSalt(phaseID, forceRefresh)
    if not phaseID then
        phaseID = self:GetCurrentPhaseID()
    end
    if not phaseID then return nil end

    local CI = self.CacheInterface
    if not CI then return nil end

    -- Check cache (unless forced refresh)
    if not forceRefresh then
        local cached = CI:Get("spvpPhaseSalt", phaseID)
        if cached then
            -- Check for negative cache (No Salt)
            if cached.noSalt then
                local age = self:GetCurrentTime() - cached.timestamp
                -- 1 hour retry for missing salts
                if age < 3600 then
                    self:Debug(string.format("Phase salt NEGATIVE cache hit for phase %d (age: %.0fs)",
                        phaseID, age), "spvp")
                    -- Return "" (confirmed no salt), NOT nil (which means "still loading").
                    -- Callers already treat "" as "no salt configured" (salt ~= "" guards
                    -- everywhere; SPVPStage/PrepopulatePhaseSaltCache/HandleSPVPInit each
                    -- have an explicit "" branch). Returning nil here made SPVPStage log
                    -- "SPVP pending: Phase salt loading..." on every send in a phase we
                    -- already KNOW has no salt, keeping SPVP engaged for up to an hour.
                    return ""
                end
                -- Expired negative cache - retry
            elseif cached.salt then
                local age = self:GetCurrentTime() - cached.timestamp
                self:Debug(string.format("Phase salt cache hit for phase %d (age: %.0fs)",
                    phaseID, age), "spvp")

                -- Background refresh logic
                local ttl = TRP3FW.Prefs.spvpSaltCacheDuration or 10800
                local refreshThreshold = ttl * ((TRP3FW.Prefs.spvpPhaseSaltRefreshRate or 50) / 100)

                if age > refreshThreshold then
                    self:Debug(string.format("Phase salt cache aging (%.0fs) - triggering background refresh", age), "spvp")
                    -- Trigger API fetch (HandleSaltResponse will update cache)
                    if C_Epsilon and C_Epsilon.GetPhaseAddonData then
                        local result = C_Epsilon.GetPhaseAddonData("TRP3FW_SPVP_KEY")
                        if result and result ~= "" and not IsWellFormedSalt(result) then -- Result is a ticket
                            self.pendingSaltTickets[result] = phaseID
                        end
                    end
                end

                -- Track hits
                if self.sessionStats and self.sessionStats.spvpCache then
                    self.sessionStats.spvpCache.hits = self.sessionStats.spvpCache.hits + 1
                    self.sessionStats.spvpCache.apiCallsSaved = self.sessionStats.spvpCache.apiCallsSaved + 1
                end

                return cached.salt
            end
        end
    end

    -- Cache miss or forced refresh - fetch from API
    if self.sessionStats and self.sessionStats.spvpCache then
        self.sessionStats.spvpCache.misses = self.sessionStats.spvpCache.misses + 1
    end

    if not C_Epsilon or not C_Epsilon.GetPhaseAddonData then
        return nil
    end

    -- Asynchronous/Synchronous Request
    local result = C_Epsilon.GetPhaseAddonData("TRP3FW_SPVP_KEY")

    if not result or result == "" then
        -- Immediate "No Salt" result
        self:Debug("Phase salt not found (Synchronous) for phase "..phaseID..", caching negative result (1h)", "spvp")
        if CI then
            CI:Set("spvpPhaseSalt", phaseID, {
                noSalt = true,
                timestamp = self:GetCurrentTime()
            })
        end
        return nil
    end

    if result then
        -- Check if result is the data itself (Synchronous hit)
        -- If the client already has the data, it might return it directly
        if IsWellFormedSalt(result) then
            self:Debug("Synchronous phase salt fetch successful for phase "..phaseID, "spvp")

            -- Cache it immediately
            if CI then
                CI:Set("spvpPhaseSalt", phaseID, {
                    salt = result,
                    timestamp = self:GetCurrentTime()
                })

                -- Update stats
                if self.sessionStats and self.sessionStats.spvpCache then
                    self.sessionStats.spvpCache.lastRefresh = self:GetCurrentTime()
                    self.sessionStats.spvpCache.activeEntries = CI:GetSize("spvpPhaseSalt") or 0
                end
            end

            return result
        else
            -- Result is a ticket (Async)
            self.pendingSaltTickets[result] = phaseID
            self:Debug("Requested salt for phase "..phaseID.." (Ticket: "..result..")", "spvp")
        end
    end

    return nil -- Loading...
end

--- Invalidate phase salt cache for a specific phase
--- @param phaseID number - Phase ID to invalidate (nil = current phase)
function TRP3FW:InvalidatePhaseSaltCache(phaseID)
    if not phaseID then
        phaseID = self:GetCurrentPhaseID()
    end
    if not phaseID then return end

    local CI = self.CacheInterface
    if CI then
        CI:Remove("spvpPhaseSalt", phaseID)
        if self.sessionStats and self.sessionStats.spvpCache then
            self.sessionStats.spvpCache.activeEntries = CI:GetSize("spvpPhaseSalt") or 0
        end
        self:Debug(string.format("Phase salt cache invalidated for phase %d", phaseID), "spvp")
    end
end

--- Prepopulate phase salt cache on login or phase change
function TRP3FW:PrepopulatePhaseSaltCache()
    if not TRP3FW.Prefs.spvpEnabled then return end
    if not self.hasEpsilonAPI then return end

    local phaseID = self:GetCurrentPhaseID()
    if not phaseID then return end

    -- Phase 169 (Start Phase) never participates in SPVP — the stage, the cascading
    -- check, and the decision rescue all hard-exclude it. Requesting a salt here just
    -- burns an async ticket that always resolves to "no salt". Skip to match those paths.
    if phaseID == 169 then
        self:Debug("Phase salt prepopulation skipped: Start Phase (169) exclusion", "spvp")
        return
    end

    -- Fetch and cache the salt
    local salt = self:GetPhaseSalt(phaseID, false)

    if salt == nil then
        self:Debug(string.format("Phase salt prepopulation PENDING for phase %d (Ticket requested)", phaseID), "spvp")
    elseif salt ~= "" then
        self:Debug(string.format("Phase salt prepopulated for phase %d", phaseID), "spvp")
    else
        self:Debug(string.format("Phase %d has no salt (not secured)", phaseID), "spvp")
    end
end

-- ===================================================================
-- REPLAY ATTACK PROTECTION
-- ===================================================================

--- Check if session ID was recently used (replay detection)
--- Uses CacheInterface for automatic cleanup
--- @param sessionID string - 8-char hex session ID
--- @param sender string - Player name sending the packet
--- @return boolean - True if replayed (reject), false if new (accept)
local function IsReplayedSession(sessionID, sender)
    local CI = TRP3FW.CacheInterface

    -- Check cache
    local cached = CI:Get("spvpSessions", sessionID)
    if cached then
        TRP3FW:Debug(string.format("Replay detected: session %s from %s (age: %.1fs)",
            sessionID, sender, TRP3FW:GetCurrentTime() - cached.timestamp), "spvp")
        return true
    end

    -- New session - cache it
    CI:Set("spvpSessions", sessionID, {
        timestamp = TRP3FW:GetCurrentTime(),
        sender = sender
    })
    -- TTL: 60s (automatic eviction via CacheInterface)

    return false
end

-- ===================================================================
-- SPVP HANDSHAKE LOGIC
-- ===================================================================

-- Initialize session tracking
TRP3FW.spvpSessions = {}
TRP3FW.spvpIncomingSessions = {} -- [sessionID] = {sharedKey, sender, timestamp} (Bob's state)
TRP3FW.spvpFailedAttempts = {}
TRP3FW.pendingSaltTickets = {} -- [ticket] = phaseID
TRP3FW.pendingSPVPInits = {}   -- [{sender, message, phaseID, queuedAt}] - Queued while salt loads

-- Bound on pendingSPVPInits. This queue is fed DIRECTLY from the CHAT_MSG_ADDON handler --
-- any player can whisper us an INIT -- and it previously had no cap and no expiry. Replay
-- detection does not bound it either: it only rejects a REPEATED sessionID, and a sender
-- picks their own sessionID, so a fresh one per packet queues without limit. If the salt
-- ticket response never arrives, nothing ever drains the queue.
TRP3FW.SPVP_PENDING_INIT_LIMIT = 50
TRP3FW.SPVP_PENDING_INIT_TTL = 30  -- seconds; salt tickets resolve in well under this

--- Drop queued INITs that are too old to be worth answering, and enforce the cap.
--- @return number - how many entries were discarded
function TRP3FW:PrunePendingSPVPInits()
    local queue = self.pendingSPVPInits
    if not queue or #queue == 0 then return 0 end

    local now = self:GetCurrentTime()
    local ttl = self.SPVP_PENDING_INIT_TTL or 30
    local dropped = 0

    for i = #queue, 1, -1 do
        local age = now - (queue[i].queuedAt or 0)
        if age >= ttl then
            table.remove(queue, i)
            dropped = dropped + 1
        end
    end

    -- Cap: drop OLDEST first. The newest INIT is the one whose sender is still waiting.
    local limit = self.SPVP_PENDING_INIT_LIMIT or 50
    while #queue > limit do
        table.remove(queue, 1)
        dropped = dropped + 1
    end

    if dropped > 0 then
        self:Debug("[SPVP] Pruned "..dropped.." stale/overflow pending INIT(s)", "spvp")
    end
    return dropped
end

-- Bound on spvpIncomingSessions (Bob's half-open handshake state).
--
-- Same exposure as pendingSPVPInits and it had the same gap: an entry is written for EVERY
-- valid INIT we answer, but removed only when a matching CONFIRM arrives. An attacker who
-- sends INITs with fresh session IDs and never confirms leaves one entry per packet, forever
-- -- and replay detection does not help, because a NEW sessionID is not a replay. Each entry
-- also pins a derived shared key. The table already carried a `timestamp` that nothing read.
--
-- A handshake that has not completed within the protocol's own timeout is dead: Alice gives
-- up at SPVP_TIMEOUT_SECONDS, so her CONFIRM can never arrive after that.
TRP3FW.SPVP_INCOMING_SESSION_LIMIT = 100

--- Drop half-open incoming sessions past the handshake timeout, and enforce the cap.
--- @return number - how many entries were discarded
function TRP3FW:PruneSPVPIncomingSessions()
    local sessions = self.spvpIncomingSessions
    if not sessions then return 0 end

    local now = self:GetCurrentTime()
    -- Generous multiple of the handshake timeout: this is a backstop against unbounded
    -- growth, not a second deadline competing with the protocol's own.
    local ttl = SPVP_TIMEOUT_SECONDS * 4
    local dropped = 0

    for sessionID, entry in pairs(sessions) do
        if now - (entry.timestamp or 0) >= ttl then
            sessions[sessionID] = nil
            dropped = dropped + 1
        end
    end

    -- Hard cap for a flood tight enough to outrun the TTL sweep: evict oldest first.
    local limit = self.SPVP_INCOMING_SESSION_LIMIT or 100
    local count = 0
    for _ in pairs(sessions) do count = count + 1 end
    while count > limit do
        local oldestID, oldestTime = nil, math.huge
        for sessionID, entry in pairs(sessions) do
            local ts = entry.timestamp or 0
            if ts < oldestTime then oldestID, oldestTime = sessionID, ts end
        end
        if not oldestID then break end
        sessions[oldestID] = nil
        count = count - 1
        dropped = dropped + 1
    end

    if dropped > 0 then
        self:Debug("[SPVP] Pruned "..dropped.." stale/overflow incoming session(s)", "spvp")
    end
    return dropped
end

--- Handle asynchronous salt response from Epsilon
--- @param ticket string - The request ticket (prefix)
--- @param salt string - The received salt data
function TRP3FW:HandleSaltResponse(ticket, salt)
    local phaseID = self.pendingSaltTickets[ticket]
    if not phaseID then return end

    self.pendingSaltTickets[ticket] = nil

    -- Validate salt
    if not IsWellFormedSalt(salt) then
        self:Debug("Async salt missing/invalid for phase "..phaseID..", caching negative result (1h)", "spvp")
        local CI = self.CacheInterface
        if CI then
            CI:Set("spvpPhaseSalt", phaseID, {
                noSalt = true,
                timestamp = self:GetCurrentTime()
            })
        end

        -- Fail pending INITs FOR THIS PHASE ONLY (we can't verify them).
        -- This used to walk the whole queue and then wipe it, so a salt response for one
        -- phase NOSALT'd and discarded entries queued under a different one -- and the
        -- comment already said "for this phase", which is what it should have been doing.
        self:PrunePendingSPVPInits()
        local remaining = {}
        for _, pending in ipairs(self.pendingSPVPInits) do
            if pending.phaseID == phaseID then
                -- Inform sender we have no salt
                local reply = string.format("NOSALT:%s", pending.message:match("^INIT:.-:(%w+):") or "0")
                C_ChatInfo.SendAddonMessage("TRP3FW_SPVP", reply, "WHISPER", pending.sender)
            else
                table.insert(remaining, pending)
            end
        end
        self.pendingSPVPInits = remaining

        return
    end

    -- Cache valid salt
    local CI = self.CacheInterface
    if CI then
        CI:Set("spvpPhaseSalt", phaseID, {
            salt = salt,
            timestamp = self:GetCurrentTime()
        })
        self:Debug("Async salt cached for phase "..phaseID, "spvp")

        -- Update stats
        if self.sessionStats and self.sessionStats.spvpCache then
            self.sessionStats.spvpCache.lastRefresh = self:GetCurrentTime()
            self.sessionStats.spvpCache.activeEntries = CI:GetSize("spvpPhaseSalt") or 0
        end
    end

    -- Process pending INITs that were waiting for THIS phase's salt.
    -- Entries queued under a different phase are left in place for their own salt response:
    -- replaying them here would verify them against this phase's salt, since HandleSPVPInit
    -- re-reads GetCurrentPhaseID() rather than trusting the queued entry.
    self:PrunePendingSPVPInits()
    if #self.pendingSPVPInits > 0 then
        local ready, remaining = {}, {}
        for _, pending in ipairs(self.pendingSPVPInits) do
            if pending.phaseID == phaseID then
                table.insert(ready, pending)
            else
                table.insert(remaining, pending)
            end
        end

        -- Reassign BEFORE replaying: HandleSPVPInit can re-enter this queue (it re-queues
        -- when the salt reads as still-loading), and replaying against a list we are about
        -- to overwrite would discard those new entries.
        self.pendingSPVPInits = remaining

        if #ready > 0 then
            self:Debug(string.format("Processing %d pending SPVP INITs for phase %d", #ready, phaseID), "spvp")
            for _, pending in ipairs(ready) do
                -- Re-handle the INIT now that we have the salt
                self:HandleSPVPInit(pending.message, pending.sender)
            end
        end
    end
end

--- Start SPVP handshake with retry logic
--- @param playerName string - Target player
--- @param sendId number - Unique send ID
--- @param callback function - Callback(verified, reason)
--- @param attempt number - Current attempt (0-indexed)
local function StartSPVPHandshakeWithRetry(playerName, sendId, callback, attempt)
    if attempt >= SPVP_MAX_RETRIES then
        TRP3FW:Debug(string.format("SPVP timeout: %s (retries exhausted)", playerName), "spvp")
        -- callback may be nil for background refreshes (aging-cache path) — guard it.
        if callback then callback(nil, "timeout") end  -- nil = unknown (fallback to normal checks)
        return
    end

    -- Generate session
    local sessionID = GenerateSessionID()
    local phaseID = TRP3FW:GetCurrentPhaseID()
    local generator = GetGenerator(phaseID)
    local privateKey = GeneratePrivateKey()
    local publicKey = GeneratePublicKey(generator, privateKey)

    -- Store session state
    TRP3FW.spvpSessions[sessionID] = {
        playerName = playerName,
        sendId = sendId,
        privateKey = privateKey,
        publicKey = publicKey,
        generator = generator,
        timestamp = TRP3FW:GetCurrentTime(),
        attempt = attempt,
        callback = callback
    }

    -- Send INIT packet
    local message = string.format("INIT:%d:%s:%d", SPVP_VERSION, sessionID, publicKey)
    C_ChatInfo.SendAddonMessage("TRP3FW_SPVP", message, "WHISPER", playerName)

    TRP3FW:Debug(string.format("SPVP INIT sent to %s (session: %s, attempt: %d)",
        playerName, sessionID, attempt), "spvp")

    -- Start timeout timer
    C_Timer.After(SPVP_TIMEOUT_SECONDS, function()
        -- Check if session still pending (not completed)
        if TRP3FW.spvpSessions[sessionID] then
            TRP3FW:Debug(string.format("SPVP timeout: session %s (attempt %d/%d)",
                sessionID, attempt, SPVP_MAX_RETRIES), "spvp")

            -- Cleanup session
            local session = TRP3FW.spvpSessions[sessionID]
            TRP3FW.spvpSessions[sessionID] = nil

            -- Retry
            StartSPVPHandshakeWithRetry(playerName, sendId, callback, attempt + 1)
        end
    end)
end

--- Check player via SPVP with timeout and retry
--- @param playerName string - Target player
--- @param sendId number - Unique send ID
--- @param callback function - Callback(verified, reason)
function TRP3FW:CheckPlayerViaSPVP(playerName, sendId, callback)
    local CI = TRP3FW.CacheInterface
    local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")

    -- Check cache first
    local cached = CI:Get("spvpVerified", playerName)
    if cached then
        local now = TRP3FW:GetCurrentTime()
        local age = now - cached.timestamp
        local ttl = TRP3FW.Prefs.spvpVerifiedCacheDuration or 300
        local refreshThreshold = ttl * ((TRP3FW.Prefs.spvpVerifiedRefreshRate or 50) / 100)

        if age < refreshThreshold then
            -- Fresh cache
            TRP3FW:Debug(string.format("SPVP cache hit: %s", playerName), "spvp")
            if hs then hs:IncrementStat("cacheStats", "spvpVerifiedCacheHits") end
            callback(true, "cached")
            return
        else
            -- Aging cache - return success but refresh in background
            TRP3FW:Debug(string.format("SPVP cache hit (aging): %s - triggering background refresh", playerName), "spvp")
            if hs then hs:IncrementStat("cacheStats", "spvpVerifiedCacheHits") end
            callback(true, "cached")

            -- Background refresh (no callback)
            StartSPVPHandshakeWithRetry(playerName, sendId, nil, 0)
            return
        end
    end

    if hs then hs:IncrementStat("cacheStats", "spvpVerifiedCacheMisses") end

    -- Check if player is blocked (failed verification)
    if TRP3FW.spvpFailedAttempts[playerName] then
        local block = TRP3FW.spvpFailedAttempts[playerName]
        local now = TRP3FW:GetCurrentTime()

        if now < block.blockedUntil then
            TRP3FW:Debug(string.format("SPVP blocked: %s (%.0fs remaining)",
                playerName, block.blockedUntil - now), "spvp")
            callback(false, "blocked")
            return
        else
            -- Block expired
            TRP3FW.spvpFailedAttempts[playerName] = nil
        end
    end

    -- Start handshake with retry
    StartSPVPHandshakeWithRetry(playerName, sendId, callback, 0)  -- attempt = 0
end

--- Handle SPVP INIT packet (we are Bob, the prover)
--- @param message string - INIT packet data
--- @param sender string - Sender player name
function TRP3FW:HandleSPVPInit(message, sender)
    TRP3FW.profiler.start("SPVP:HandleInit")
    local version, sessionID, publicKey = message:match("^INIT:(%d+):(%w+):(%d+)$")

    if not version or not sessionID or not publicKey then
        TRP3FW:Debug("Malformed INIT packet from " .. sender, "spvp")
        TRP3FW.profiler.stop("SPVP:HandleInit")
        return
    end

    -- Check version
    if tonumber(version) ~= SPVP_VERSION then
        TRP3FW:Debug(string.format("Unsupported SPVP version %s from %s", version, sender), "spvp")
        TRP3FW.profiler.stop("SPVP:HandleInit")
        return
    end

    -- Replay detection (CRITICAL)
    if IsReplayedSession(sessionID, sender) then
        TRP3FW:Debug(string.format("Rejecting replayed INIT from %s (session: %s)",
            sender, sessionID), "spvp")
        TRP3FW.profiler.stop("SPVP:HandleInit")
        return  -- Drop silently
    end

    -- Check Local Salt
    local phaseID = TRP3FW:GetCurrentPhaseID()
    local salt = TRP3FW:GetPhaseSalt(phaseID)

    if salt == nil then
        -- Salt is loading asynchronously (Ticket)
        -- Queue this INIT and wait for HandleSaltResponse to process it
        -- Record the phase this INIT was queued UNDER. HandleSPVPInit re-reads
        -- GetCurrentPhaseID() when the entry is replayed, so without this a queued INIT that
        -- drains after a phase change is verified against the NEW phase's salt.
        table.insert(self.pendingSPVPInits, {
            sender = sender,
            message = message,
            phaseID = phaseID,
            queuedAt = TRP3FW:GetCurrentTime(),
        })
        TRP3FW:PrunePendingSPVPInits()
        TRP3FW:Debug("Queued SPVP INIT from " .. sender .. " (waiting for salt ticket, phase "
            .. tostring(phaseID) .. ")", "spvp")
        TRP3FW.profiler.stop("SPVP:HandleInit")
        return
    elseif salt == "" then
        -- We are in an unsecured phase. Cannot participate in SPVP.
        -- Inform sender to stop waiting.
        local reply = string.format("NOSALT:%s", sessionID)
        C_ChatInfo.SendAddonMessage("TRP3FW_SPVP", reply, "WHISPER", sender)
        TRP3FW:Debug("Sent NOSALT to " .. sender, "spvp")
        TRP3FW.profiler.stop("SPVP:HandleInit")
        return
    end

    -- Validate their public key BEFORE doing any crypto work.
    -- An unvalidated small-subgroup element (0, 1, p-1) collapses the shared key to a constant
    -- the sender can predict without knowing the phase salt, letting them forge a verifier --
    -- see IsValidPublicKey. Checked here rather than at the point of use so a hostile INIT
    -- costs us one ModPow instead of a generator derivation plus a keypair. Drop silently: a
    -- peer sending one of these is attacking, not misconfigured, and a reply would only
    -- confirm we are listening.
    local theirPublicKey = tonumber(publicKey)
    if not IsValidPublicKey(theirPublicKey) then
        TRP3FW:Debug(string.format(
            "[SPVP] Rejecting INIT from %s: invalid public key %s (small-subgroup or out of range)",
            sender, tostring(publicKey)), "spvp")
        TRP3FW.profiler.stop("SPVP:HandleInit")
        return
    end

    -- Get our generator
    local generator = GetGenerator(phaseID, salt)

    -- Generate our keys
    local privateKey = GeneratePrivateKey()
    local myPublicKey = GeneratePublicKey(generator, privateKey)

    -- Derive shared key from their (now validated) public key
    local sharedKey = DeriveSharedKey(theirPublicKey, privateKey)

    -- Store incoming session state for Bob (to verify Alice's upcoming CONFIRM).
    -- Prune first: this table is written from a network handler and is only cleared by a
    -- matching CONFIRM, so without a sweep here a peer that never confirms grows it forever.
    TRP3FW:PruneSPVPIncomingSessions()
    TRP3FW.spvpIncomingSessions[sessionID] = {
        sharedKey = sharedKey,
        sender = sender,
        timestamp = TRP3FW:GetCurrentTime()
    }

    -- Create verifier
    local verifier = HashKey(sharedKey)

    -- Send REPLY packet
    local reply = string.format("REPLY:%s:%d:%s", sessionID, myPublicKey, verifier)
    C_ChatInfo.SendAddonMessage("TRP3FW_SPVP", reply, "WHISPER", sender)

    TRP3FW:Debug(string.format("SPVP REPLY sent to %s (session: %s)", sender, sessionID), "spvp")
    TRP3FW.profiler.stop("SPVP:HandleInit")
end

--- Handle SPVP CONFIRM packet (Bob Side)
--- Alice has verified Bob and is now proving herself to him
--- @param message string - CONFIRM packet data
--- @param sender string - Sender player name
function TRP3FW:HandleSPVPConfirm(message, sender)
    local sessionID, verifier = message:match("^CONFIRM:(%w+):(%w+)$")
    if not sessionID or not verifier then return end

    local incoming = TRP3FW.spvpIncomingSessions[sessionID]
    if not incoming or incoming.sender ~= sender then
        TRP3FW:Debug(string.format("Unknown incoming SPVP session %s from %s", sessionID, sender), "spvp")
        return
    end

    -- Cleanup incoming state
    TRP3FW.spvpIncomingSessions[sessionID] = nil

    -- Verify Alice's proof (Uses same shared key)
    local expectedVerifier = HashKey(incoming.sharedKey)
    if verifier == expectedVerifier then
        TRP3FW:Debug(string.format("SPVP SUCCESS (Mutual): %s verified via CONFIRM", sender), "spvp")

        -- Cache result for Bob
        local CI = TRP3FW.CacheInterface
        if CI then
            CI:Set("spvpVerified", sender, {
                timestamp = TRP3FW:GetCurrentTime(),
                verified = true,
                sessionID = sessionID
            })
        end
    else
        TRP3FW:Debug(string.format("SPVP FAILED (Mutual): %s verifier mismatch in CONFIRM", sender), "spvp")
    end
end

--- Handle SPVP NOSALT packet (Sender Side)
--- @param message string - NOSALT packet data
--- @param sender string - Sender player name
function TRP3FW:HandleSPVPNosalt(message, sender)
    local sessionID = message:match("^NOSALT:(%w+)$")
    if not sessionID then return end

    local session = TRP3FW.spvpSessions[sessionID]
    if session and session.playerName == sender then
        TRP3FW:Debug("Received NOSALT from " .. sender .. ". Verification failed.", "spvp")

        -- Fail verification immediately
        if session.callback then
            session.callback(false, "peer_no_salt")
        end

        -- Cleanup
        TRP3FW.spvpSessions[sessionID] = nil
    end
end

--- Handle SPVP REPLY packet (we are Alice, the verifier)
--- @param message string - REPLY packet data
--- @param sender string - Sender player name
function TRP3FW:HandleSPVPReply(message, sender)
    TRP3FW.profiler.start("SPVP:HandleReply")
    local sessionID, publicKey, verifier = message:match("^REPLY:(%w+):(%d+):(%w+)$")

    if not sessionID or not publicKey or not verifier then
        TRP3FW:Debug("Malformed REPLY packet from " .. sender, "spvp")
        TRP3FW.profiler.stop("SPVP:HandleReply")
        return
    end

    -- Find session
    local session = TRP3FW.spvpSessions[sessionID]
    if not session then
        TRP3FW:Debug(string.format("Unknown session %s from %s (expired or invalid)", sessionID, sender), "spvp")
        TRP3FW.profiler.stop("SPVP:HandleReply")
        return
    end

    -- Cleanup session (completed)
    TRP3FW.spvpSessions[sessionID] = nil

    -- Derive shared key.
    -- Validate their public key first (see IsValidPublicKey): a small-subgroup element makes
    -- the shared key predictable without any knowledge of the phase salt, letting an attacker
    -- forge a matching verifier and be cached as spvpVerified.
    --
    -- The session was consumed just above, so this path must still settle the callback or the
    -- caller waits for its timeout. Treated as a failed verification -- it IS a failed proof --
    -- but deliberately WITHOUT the salt-cache invalidation and force-refresh the mismatch
    -- branch does: a malformed public key tells us nothing about our own salt being stale, and
    -- letting an attacker trigger a forced salt refetch per packet would hand them a cheap way
    -- to hammer the Epsilon salt API.
    local theirPublicKey = tonumber(publicKey)
    if not IsValidPublicKey(theirPublicKey) then
        TRP3FW:Debug(string.format(
            "[SPVP] Rejecting REPLY from %s: invalid public key %s (small-subgroup or out of range)",
            sender, tostring(publicKey)), "spvp")

        local now = TRP3FW:GetCurrentTime()
        local blockDuration = TRP3FW.Prefs.spvpBlockDuration or 60
        TRP3FW.spvpFailedAttempts[sender] = {
            count = (TRP3FW.spvpFailedAttempts[sender] and TRP3FW.spvpFailedAttempts[sender].count or 0) + 1,
            firstFailTime = TRP3FW.spvpFailedAttempts[sender] and TRP3FW.spvpFailedAttempts[sender].firstFailTime or now,
            blockedUntil = now + blockDuration
        }

        if session.callback then
            session.callback(false, "invalid_public_key")
        end
        TRP3FW.profiler.stop("SPVP:HandleReply")
        return
    end
    local sharedKey = DeriveSharedKey(theirPublicKey, session.privateKey)

    -- Verify
    local expectedVerifier = HashKey(sharedKey)

    if verifier == expectedVerifier then
        -- Verification passed!
        TRP3FW:Debug(string.format("SPVP SUCCESS: %s verified (session: %s)", sender, sessionID), "spvp")

        -- Cache result
        local CI = TRP3FW.CacheInterface
        CI:Set("spvpVerified", sender, {
            timestamp = TRP3FW:GetCurrentTime(),
            verified = true,
            sessionID = sessionID
        })
        -- TTL: 300s (5 min)

        -- 3-WAY HANDSHAKE: Send confirmation back to prover (Bob)
        -- Bob uses this to verify Alice without starting his own handshake
        local confirm = string.format("CONFIRM:%s:%s", sessionID, expectedVerifier)
        C_ChatInfo.SendAddonMessage("TRP3FW_SPVP", confirm, "WHISPER", sender)
        TRP3FW:Debug(string.format("SPVP CONFIRM sent to %s (session: %s)", sender, sessionID), "spvp")

        -- Invoke callback
        if session.callback then
            session.callback(true, "verified")
        end
    else
        -- Verification failed!
        TRP3FW:Debug(string.format("SPVP failed: %s (session: %s, verifier mismatch)", sender, sessionID), "spvp")

        -- Invalidate salt cache in case it was rotated
        local phaseID = TRP3FW:GetCurrentPhaseID()
        if phaseID then
            TRP3FW:InvalidatePhaseSaltCache(phaseID)
            TRP3FW:Debug(string.format("Invalidated phase salt cache (handshake failed, possible rotation)"), "spvp")

            -- Try to refresh the salt from API
            TRP3FW:GetPhaseSalt(phaseID, true)  -- Force refresh
        end

        -- Block sender
        local now = TRP3FW:GetCurrentTime()
        local blockDuration = TRP3FW.Prefs.spvpBlockDuration or 60

        TRP3FW.spvpFailedAttempts[sender] = {
            count = (TRP3FW.spvpFailedAttempts[sender] and TRP3FW.spvpFailedAttempts[sender].count or 0) + 1,
            firstFailTime = TRP3FW.spvpFailedAttempts[sender] and TRP3FW.spvpFailedAttempts[sender].firstFailTime or now,
            blockedUntil = now + blockDuration
        }

        -- Invoke callback
        if session.callback then
            session.callback(false, "verification_failed")
        end
    end
    TRP3FW.profiler.stop("SPVP:HandleReply")
end

-- ===================================================================
-- HELPER FUNCTIONS
-- ===================================================================

--- Get current phase ID (with caching)
---
--- Delegates to GetCachedPhaseID (core/utils.lua) rather than keeping its own cache.
---
--- BUG FIXED: these were two separate caching implementations that SHARED the
--- `TRP3FW.cachedPhaseID` value but tracked its freshness independently and incompatibly:
---
---   GetCachedPhaseID   TTL 1s, timestamp in `cachedPhaseTimestamp`, clock = time()
---                      (wall-clock seconds)
---   GetCurrentPhaseID  TTL 5s, timestamp in `cachedPhaseIDTime`,    clock = GetCurrentTime()
---                      (monotonic uptime)
---
--- Two different epochs, so the timestamps were not comparable quantities at all.
---
--- The concrete defect was the 5s TTL: nearly every phase-sensitive caller in the addon uses
--- GetCurrentPhaseID (SPVPStage, cascading, decision, the salt paths, the UI), and all of them
--- could act on a phase ID up to 5 seconds out of date, while the addon's stated phase-cache
--- contract is 1s (PHASE_CACHE_TTL).
---
--- Verified by direct execution that the reverse direction was NOT corrupting: because the old
--- GetCurrentPhaseID never wrote `cachedPhaseTimestamp`, GetCachedPhaseID always saw a huge
--- apparent age and refetched -- it failed safe. So ghost mode's start-phase check was not
--- reading stale values; the exposure was confined to GetCurrentPhaseID's own callers.
---
--- One cache, one clock, one owner. GetCachedPhaseID is the owner because it holds the tighter
--- TTL; this stays as the name most callers use.
--- @return number|nil - Phase ID or nil if unavailable
function TRP3FW:GetCurrentPhaseID()
    if not C_Epsilon or not C_Epsilon.GetPhaseId then
        return nil
    end
    -- GetCachedPhaseID additionally requires the hasEpsilonAPI detection flag. Keep this
    -- function's historical contract (API present is enough) by falling back to a direct read
    -- when the flag has not been set yet -- rather than loosening GetCachedPhaseID's guard,
    -- which would change behaviour for its own callers (ghost mode's start-phase check).
    if not self.hasEpsilonAPI then
        return tonumber(C_Epsilon.GetPhaseId())
    end
    return self:GetCachedPhaseID()
end

-- ===================================================================
-- PUBLIC API
-- ===================================================================

--- Short, non-reversible fingerprint of a salt, for DIAGNOSTICS ONLY.
--- Lets a user answer "is my cached salt the same as the API's?" or "did the salt change?"
--- without any salt material reaching chat, the debug window, or a pasted support log.
--- Never use this for verification -- it is a 32-bit hash, not a MAC.
--- @param salt string|nil
--- @return string - 8 hex chars, or a descriptive placeholder
function TRP3FW:GetSaltFingerprint(salt)
    if type(salt) ~= "string" or salt == "" then return "none" end
    return string.format("%08x", FNV1aHash(salt))
end

-- Export functions for external use
TRP3FW.SPVP = {
    GetGenerator = GetGenerator,
    ModPow = ModPow,
    FNV1aHash = FNV1aHash,
    HashKey = HashKey,
    GeneratePrivateKey = GeneratePrivateKey,
    GeneratePublicKey = GeneratePublicKey,
    DeriveSharedKey = DeriveSharedKey,
    IsValidPublicKey = IsValidPublicKey,
    GenerateSessionID = GenerateSessionID
}

TRP3FW:Debug("SPVP library loaded", "core")
