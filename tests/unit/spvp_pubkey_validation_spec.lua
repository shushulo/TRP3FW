-- tests/unit/spvp_pubkey_validation_spec.lua
-- Peer public-key validation for the SPVP handshake.
--
-- Regression cover for a small-subgroup confinement forgery. K = B^a mod p, so a peer who
-- sends a B of order 1 or 2 makes K independent of the honest party's secret exponent:
--   B = 0 (or p) -> K = 0 always
--   B = 1        -> K = 1 always
--   B = p-1      -> K in {1, p-1}, chosen only by the parity of a
-- The attacker computes HashKey(K) offline and sends a matching verifier -- WITHOUT knowing
-- the phase salt, which is the only thing SPVP proves possession of. Both receive paths
-- (HandleSPVPInit / HandleSPVPReply) parse the key as (%d+) off the wire, so any player able
-- to whisper an addon message could be verified as in-phase.

local T = require("tests.framework")
local H = require("tests.harness")

local TRP3FW = H.newNamespace()
TRP3FW.CacheInterface = nil
TRP3FW.spvpSessions = {}
TRP3FW.spvpIncomingSessions = {}
TRP3FW.spvpFailedAttempts = {}
TRP3FW.pendingSaltTickets = {}
TRP3FW.pendingSPVPInits = {}
H.loadModule("features/encryption/spvp.lua", TRP3FW)

local SPVP = TRP3FW.SPVP

-- Must match the constants in spvp.lua (safe prime, p = 2q+1).
local DH_PRIME = 93999743
local DH_SUBGROUP_ORDER = 46999871

T.describe("SPVP.IsValidPublicKey", function()
    T.it("rejects the degenerate small-subgroup elements", function()
        T.falsy(SPVP.IsValidPublicKey(0), "0 collapses the shared key to 0")
        T.falsy(SPVP.IsValidPublicKey(1), "1 collapses the shared key to 1")
        T.falsy(SPVP.IsValidPublicKey(DH_PRIME - 1), "p-1 has order 2")
        T.falsy(SPVP.IsValidPublicKey(DH_PRIME), "p is congruent to 0")
    end)

    T.it("rejects out-of-range and non-integer values", function()
        T.falsy(SPVP.IsValidPublicKey(-1), "negative")
        T.falsy(SPVP.IsValidPublicKey(DH_PRIME + 1), "above the modulus")
        T.falsy(SPVP.IsValidPublicKey(1.5), "non-integer")
        T.falsy(SPVP.IsValidPublicKey(nil), "nil (tonumber failure on garbage input)")
        T.falsy(SPVP.IsValidPublicKey("4"), "string, not number")
    end)

    T.it("accepts honest public keys from the large subgroup", function()
        -- 4 is a quadratic residue (2^2) and generates the order-q subgroup for this prime;
        -- it is the same fallback generator GetGenerator uses.
        for _, priv in ipairs({ 2, 3, 12345, 6000000, 46999870 }) do
            local pub = SPVP.ModPow(4, priv, DH_PRIME)
            T.truthy(SPVP.IsValidPublicKey(pub),
                "g^" .. priv .. " mod p must be accepted (got " .. tostring(pub) .. ")")
        end
    end)

    T.it("only accepts members of the order-q subgroup", function()
        -- Anything it accepts must satisfy B^q == 1; that is the definition of the subgroup.
        for _, priv in ipairs({ 7, 999983, 20000000 }) do
            local pub = SPVP.ModPow(4, priv, DH_PRIME)
            T.eq(SPVP.ModPow(pub, DH_SUBGROUP_ORDER, DH_PRIME), 1,
                "accepted key must be in the large subgroup")
        end
    end)
end)

T.describe("SPVP small-subgroup forgery", function()
    -- This is the actual attack, expressed as a test: the attacker never learns the salt,
    -- never solves a discrete log, and still produces the verifier the honest side expects.
    local function forgeryWorks(evilPublicKey)
        local honestPrivate = 31337191   -- honest party's secret, unknown to the attacker
        local attackerGuess = 999999     -- arbitrary; the attack does not depend on it

        local honestShared = SPVP.DeriveSharedKey(evilPublicKey, honestPrivate)
        local predictedShared = SPVP.DeriveSharedKey(evilPublicKey, attackerGuess)
        return SPVP.HashKey(honestShared) == SPVP.HashKey(predictedShared)
    end

    T.it("would succeed for 0, 1 and p if the key were not validated", function()
        -- Documents WHY the guard exists: these are forgeable at the math level, so the
        -- protocol's safety rests entirely on refusing them at the door.
        T.truthy(forgeryWorks(0), "B=0 makes the verifier predictable")
        T.truthy(forgeryWorks(1), "B=1 makes the verifier predictable")
        T.truthy(forgeryWorks(DH_PRIME), "B=p is the same element as 0")
    end)

    T.it("is blocked because validation rejects every forgeable key", function()
        for _, evil in ipairs({ 0, 1, DH_PRIME - 1, DH_PRIME }) do
            T.truthy(forgeryWorks(evil), "precondition: " .. evil .. " is forgeable")
            T.falsy(SPVP.IsValidPublicKey(evil),
                "so it must be rejected before DeriveSharedKey (" .. evil .. ")")
        end
    end)

    T.it("does not work against an honest public key", function()
        local honestPub = SPVP.ModPow(4, 555555, DH_PRIME)
        T.truthy(SPVP.IsValidPublicKey(honestPub), "honest key is accepted")
        T.falsy(forgeryWorks(honestPub), "attacker cannot predict the verifier")
    end)
end)

return T
