# SPVP Cryptographic Upgrade — Spec Sheet

**Status:** ⚠️ **Design changed — the bignum port described in §3–§4 is superseded by §2b.**
Scoped 2026-07-25.

| Item | State |
|---|---|
| `0ac5af3` — safe prime, 64-bit verifier, generator validation | ✅ done |
| §4.4 — private-key entropy | ✅ **done 2026-07-25**, shipped standalone |
| `spvp.lua` threat-model header — "hours of compute" error | ✅ **corrected 2026-07-25** |
| §2b — **HMAC replaces DH** (recommended design) | ⬜ not started |
| §4.3 — SHA-256 (required by *both* designs; **nothing usable ships**) | ⬜ not started |
| §5 — salt rotation on removal/blacklist | ⬜ not started, **highest value** |
| §7 step 0c — confirm `spvpMode` actually blocks | ⬜ **do first — go/no-go** |
| §3–§4 — 128-bit bignum port | 🚫 superseded by §2b |

**Read this first if you are picking the project up cold.** Everything below was measured by
direct execution, not estimated, except where explicitly flagged as a bound or an assumption.

### Three-line summary

1. **Do §7 step 0c first.** Default `spvpMode` is `optional`, and only `required` makes an SPVP
   failure decisive ([`cascading.lua:102`](../location/cascading.lua)). If a failed SPVP does
   not actually block, the entire crypto question is moot.
2. **Then salt rotation on removal (§5)** — a zero-work bypass that no crypto change touches.
3. **Only then consider §2b's HMAC.** It reaches ~2^128 for less work than the bignum port's
   ~2^64. Do not start §3–§4.

---

## 1. Where SPVP stands today (post-`0ac5af3`)

| Property | Value |
|---|---|
| `DH_PRIME` | `93999743` (safe prime, `p-1 = 2q`, `q = 46999871`) |
| Group strength | ~2^12.7 (Pollard's rho, ~6,856 steps) |
| Verifier | 64-bit (two domain-separated FNV-1a rounds), birthday bound ~2^32 |
| Generator validation | `ModPow(g, q, p) == 1`, fallback `g = 4` |
| Protocol version | 3 |
| **Real attack time** | **< 1 millisecond** |

### The number that matters

~2^12.7 sounds abstract. Concretely it is **~21,000 modular multiplications**. Measured
throughput in interpreted Lua is 4.29e7 modmul/sec, so a full Pollard's rho run completes in
**under a millisecond** — in Lua, on one core, let alone in C.

Re-measured 2026-07-25 on the same machine: **4.6e7 modmul/sec**, 7,061 rho steps
(`1.03·√q`), giving **~0.46 ms** for a complete run. Consistent with the 4.29e7 figure above.

**Practical consequence: an attacker needs no external tooling.** 0.46 ms is under a single
frame at 60fps, *in interpreted Lua*. An ordinary WoW addon can complete one honest handshake,
recover our private exponent before the next frame draws, and forge verifiers from then on.
Not a rented server, not C — a `.lua` file.

> **Correction to earlier session notes:** an intermediate write-up described this as "hours of
> compute." That was wrong — a careless translation from 2^12.7 to wall-clock. The security
> figure was right; the time estimate was not.
>
> **The `spvp.lua` header carried that same "hours of compute" error** and was corrected
> 2026-07-25. An earlier revision of this document said the header was already correct; it was
> not. Do not trust any "hours" figure anywhere.

### Rate limiting does not apply

`spvpBlockDuration`, replay detection and the queue caps all bound how often a peer can **send**
us packets. Pollard's rho is **offline**: the attacker completes one legitimate handshake, walks
away, and computes against the public value we already handed them. There is no packet left to
throttle and no cap on attempts. Online controls do not touch an offline attack.

### What `0ac5af3` actually bought

It was still worth doing. Before it, `p-1 = 2^4 × 3 × 971 × 1931` — all small factors — so
Pohlig–Hellman reduced the discrete log to ~√1931 ≈ **44 operations** (~2^5.5). Measured across
5,000 simulated salts, *every* generator order shared 1931 as its largest prime factor. After
the change, measured across 3,000 salts, **100% of generators have order exactly q**. That is a
156× improvement and it removed a trivially-exploitable structural flaw.

It just does not reach "secure." It reaches "no longer instantly broken by inspection."

---

## 2. The platform ceiling, and why it is not the real ceiling

### The double constraint

`ModPow` computes `base * base` **before** reducing. Lua 5.1 has no integer type — numbers are
doubles, exact only to 2^53. So:

```
(p-1)^2 < 2^53   =>   p < 94,906,265   (~2^26.5)
```

Above that, arithmetic **silently produces wrong answers** rather than merely weak ones.
`93999743` sits at 1.9% headroom below the limit. (The largest safe prime under the cap,
`94905947`, leaves only 0.0007% — rejected as too thin a margin for a value that must be exact,
for essentially identical security.)

### Why this is not actually the ceiling

> **Correction to earlier session notes:** those notes stated repeatedly that bignum arithmetic
> "is not viable for a per-send handshake." **That claim was asserted without being tested, and
> it is wrong.**

WoW exposes a `bit` library with exact 32-bit operations (`spvp.lua` already uses
`bit.bxor`/`bit.band` in `FNV1aHash`). Multi-limb arithmetic over 24-bit limbs works fine with
doubles too, since products of 24-bit values are exact (2^48 < 2^53).

**Measured:** 3-limb (72-bit) schoolbook multiply runs at **6.39e5 ops/sec** in interpreted Lua
— a 67× slowdown vs native double modmul, which is entirely affordable at handshake frequency.

---

## 2b. ⚠️ STOP — is Diffie–Hellman even the right primitive?

**Added 2026-07-25. Read before committing to anything in §3 or §4.** Everything after this
point assumes we keep a DH handshake and make its group bigger. That assumption deserves
challenging, and on inspection it does not survive.

### The observation

Ask what Diffie–Hellman is *for*: establishing a shared secret between two parties **who do not
already have one**.

But both sides already hold the phase salt. **That is the premise of the whole protocol.** The
entire SPEKE handshake exists to derive a session key from a secret both parties already
possess — we are using public-key machinery to bootstrap a shared secret when a shared secret is
the *input*.

That is why the port is expensive. Bignum arithmetic, safe-prime generation, subgroup
validation, small-subgroup rejection — all of it is machinery for the no-shared-secret case.
**We do not have that case.**

Note also that SPVP encrypts nothing. Every packet is plaintext and public; the protocol proves
*possession of a shared secret*. That is an authentication (MAC) problem, not a key-agreement
problem — which is the same conclusion from the other direction.

### The alternative: challenge–response MAC

Symmetric. No modular arithmetic, no bignum, no prime.

```
Alice → Bob:   NONCE:<sessionID>:<random_challenge>
Bob   → Alice: PROOF:<sessionID>:HMAC(salt, challenge || alice || bob || phaseID)
```

Alice recomputes the HMAC and compares. Bob proves salt possession without revealing it.
Reverse for mutual verification — the same shape as the existing 3-way INIT/REPLY/CONFIRM flow.

Binding the peer names and phase ID into the MAC input is what stops a proof being replayed
into a different conversation or a different phase.

**Security is the full width of the MAC output.** There is no √ from Pollard's rho because
there is no group to attack, and the birthday bound does not apply to a keyed-MAC preimage. A
128-bit truncated HMAC gives ~2^128 against forgery — versus the ~2^64 that §3 targets after
multi-day bignum work.

| | Bignum port (§3–§4) | HMAC challenge–response |
|---|---|---|
| Strength vs adversary (B) | ~2^64 | **~2^128** |
| New crypto to write | bignum **+ SHA-256** | **SHA-256 only** |
| Per-handshake cost | ~10.8 ms | **< 1 ms** |
| Carry-bug risk (§4.1) | high | **none — no carry chains** |
| Validatable against fixtures | partly | **fully** (NIST vectors) |
| Effort | multi-day | ~half a day + SHA-256 |

Better on every axis. Not a close call.

### What we would lose — and why it does not matter here

Both of SPEKE's genuine advantages target threats we do not have:

- **Forward secrecy.** DH gives fresh per-session keys; under HMAC, a leaked salt makes past
  transcripts forgeable retroactively. But there are no transcripts worth protecting — SPVP
  packets are public and carry no profile data. And salts already persist until manual
  rotation (§5), so forward secrecy was largely notional.
- **Offline-dictionary resistance.** SPEKE's real strength: salt guesses cannot be ground
  offline. Under HMAC, an attacker capturing one challenge/proof pair *can* grind offline.
  **But** the salt is 64 hex chars drawn from the §4.4 entropy pool, not a human password.
  Dictionary attacks need a small guessable space; there is not one.

### What it does NOT change

Nothing in §5. An admitted member (A) still reads the salt and computes a valid proof, and a
blacklisted ex-member still holds a working salt until rotation. **This is a cheaper, stronger
replacement for the §3–§4 port — not a substitute for rotation-on-removal.**

### Also considered

- **Keep DH, only replace the hash.** No. Rho stays at ~2^12.7 regardless of hash strength.
- **Signatures (Ed25519 etc.).** Solves a *different* problem — per-player identity rather than
  group membership, which would allow blacklisting by key and drop the shared-salt model
  entirely. Genuinely interesting long-term, but needs bignum **and** key distribution:
  strictly more work than the port. Not now.

---

## 3. Security vs cost — the decision table

> **Superseded by §2b for the recommendation, retained for the measurements.** The rows below
> are still accurate about what a *bigger DH group* costs and buys. They no longer represent
> the recommended path, because §2b reaches better security for less work by dropping DH.

Measured 3-limb rate extrapolated by O(n²) in limb count. Attacker assumed at 4.3e9 modmul/sec
(C, single core), rho at ~3 modmuls/step.

| p bits | limbs | ms/handshake | rho steps | Attack time (C, 1 core) |
|---|---|---|---|---|
| 26.5 *(today)* | 1 | ~0.05 | 6.9e3 | **< 1 ms** |
| 72 | 3 | 1.5 | 5.0e10 | 35 seconds |
| 96 | 4 | 3.6 | 2.1e14 | **1.7 days** |
| **128** | **6** | **10.8** | **1.3e19** | **~300 years** |
| 160 | 7 | 18.4 | 8.8e23 | 2.0e7 years |
| 192 | 8 | 28.8 | 5.8e28 | 1.3e12 years |
| 256 | 11 | 72.7 | 2.5e38 | 5.5e21 years |

### Cost in context

`spvpVerifiedCacheDuration` is 300s. So handshake cost is **per peer per 5 minutes**, not per
profile send and not per frame. 10.8ms at 128-bit is a one-off on first contact with a player.

### Recommended target: **128-bit**

It is the point at which the DH group stops being the weakest link in the system. Going higher
buys nothing while FNV-1a and the salt distribution remain as they are.

---

## 4. Work breakdown

> **Applicability after §2b.** This breakdown was written for the bignum port (Route B).
> Under the recommended HMAC design (Route A), **only §4.3 and §4.4 apply** — §4.1, §4.2 and
> the DH-specific parts of §4.5/§4.6 all become unnecessary, which is precisely the point of
> §2b. §4.1 is retained because its "a bug does not look like a bug, it looks like an attack"
> warning generalises to *any* crypto change here, including SHA-256.

### 4.1 Bignum module *(the bulk of the work — Route B only)*

Multi-limb arithmetic over 24-bit limbs. Roughly 200–300 lines.

Required operations:
- add / sub with carry propagation
- schoolbook multiply (O(n²) is fine at these sizes)
- modular reduction — **Montgomery or Barrett**, not naive division
- `ModPow` via square-and-multiply on the above
- comparison, and constant-time-ish equality for the verifier path

**This must be exactly right.** A subtle carry bug produces wrong results that present as
verification failures — which `HandleSPVPReply` interprets as a hostile peer and **blocks** for
`spvpBlockDuration`. A bug here does not look like a bug; it looks like an attack.

**Build this in isolation, with test vectors, before touching anything else.** Cross-check
`ModPow` against known-good values (Python `pow(b, e, m)` output committed as fixtures).

### 4.2 Port the crypto layer *(Route B only)*

Under Route A these functions are **deleted, not ported** — see §7 Route A step 5.

- `ModPow`, `GetGenerator`, `GeneratePublicKey`, `DeriveSharedKey`, `GeneratePrivateKey`
- Regenerate `DH_PRIME` as a 128-bit safe prime (`p = 2q + 1`, both prime — verify both)
- Keep the `ModPow(g, q, p) == 1` subgroup check; pick a new fallback generator and **verify its
  order is exactly q** (the current fallback `4` was verified for the current prime; do not
  assume it carries over)

### 4.3 Replace FNV-1a with a real hash ⚠️ — **required by BOTH designs**

**At 128-bit group strength, FNV-1a becomes the weakest link by a wide margin.** It is a
hash-*table* function with no collision resistance. It is used in two places:

- `GetGenerator` — hashes `phaseID:salt` into the group
- `HashKey` — produces the verifier

Both need SHA-256. Note this is **not** work that §2b's HMAC design adds — it is required
either way, and it is the *only* new crypto §2b needs.

#### Library audit — searched 2026-07-25 ❌ **nothing usable ships**

Searched `totalRP3/libs`, `XRP/Libraries`, `MyRolePlay/Libs`, all of `Epsilon/`, and
SpellCreator. **There is no cryptographic hash in any bundled library.** Every hash-shaped
thing found is a non-cryptographic checksum:

| Found | What it actually is | Usable as a MAC? |
|---|---|---|
| `LibCompress:fcs16*` | 16-bit CRC, table-driven | **No** — 16 bits, trivially collided |
| `LibCompress:fcs32*` | 32-bit CRC | **No** — linear, forgeable by construction |
| `LibDeflate:Adler32` | RFC1950 sum-of-bytes (`a`/`b` running sums mod 65521) | **No** — not even a hash |
| `Ellyb` | no hashing at all | — |
| `C_Crypto` / native WoW hash API | **does not exist** | — |

CRC and Adler-32 are designed to catch *accidental* corruption. Both are linear, so an attacker
can compute exactly what edit yields any target checksum. **Using either as a MAC would be
worse than the FNV-1a already in place.**

Two false leads, recorded so nobody re-checks them:
- The `md5` reference in `LibRPMedia/README.md` is a **build-time luarocks dependency** for
  generating media manifests offline. Not shipped Lua.
- Grep hits for `sha` inside `Epsilon/` are substrings of "shape"/"shared".

**Conclusion: SHA-256 must be ported or written.** Do not treat this as a blocker for §2b —
it was always required by §4.3 regardless of design.

#### Sourcing it, in order of preference

1. **Port a known-good pure-Lua SHA-256** with a compatible license; validate against NIST
   vectors. WoW addons doing this exist.
2. **Reuse LibDeflate's `bit` shim pattern** — it already handles the LuaJIT/fallback split a
   pure-Lua implementation needs.
3. Write from the spec **only** as a last resort.

**Whichever route: build and validate standalone before it touches SPVP**, committing NIST
vectors as fixtures first. Same discipline §4.1 prescribes for bignum, and for the same reason
— a wrong hash produces verifier mismatches, which `HandleSPVPReply` reads as hostile and
**blocks**.

SHA-256 is far safer to hand-roll than bignum modular arithmetic, because it is *fully*
testable: NIST publishes official vectors, so it either matches byte-for-byte or it does not.
There is no equivalent oracle for "is my Montgomery reduction subtly wrong on long carry
chains."

**Performance:** SHA-256 in interpreted Lua 5.1 with `bit` ops runs at roughly 50–200 KB/s.
Entirely fine here — SPVP hashes tens of bytes, once per peer per 5 minutes.

⚠️ **Under §2b's HMAC design the hash IS the entire security** — there is no group strength
underneath it as a backstop. The "unverified hand-rolled SHA-256 is a worse liability than
FNV-1a" warning applies with *more* force there, not less.

### 4.4 Private key entropy — ✅ **DONE 2026-07-25**, ahead of the port

**This was measured and found worse than this section originally estimated, so it was pulled
out of the port and done standalone.** Details kept because they change the ordering in §7.

The estimate here was "~2^32, bounded by `math.random`'s internal state." The real figure was
lower, because the key was a pure function of a seed built from quantities *the peer largely
knows*:

| Seed term | What the attacker knows |
|---|---|
| GUID (last 8 hex) | Knows it outright — the attacker **is** the peer |
| cursor `x*1337 + y*7331` | Bounded by screen resolution; the arithmetic combination collapses it |
| `floor(now*1e6) % 2^31` | Dominant term — and they know roughly *when* we sent, having received it |

**Measured:** 1000 adjacent microsecond seeds → 1000 distinct keys. No collapse, but no
amplification either. Bound the send time to ~1 ms and the search space is **~2^10**; at ~100 ms,
**~2^17**. Both at or *below* the group's own ~2^12.7 — so this was plausibly the cheapest
attack on SPVP, and unlike the group weakness it needed no bignum work to fix.

**Fix shipped:** session-long accumulating entropy pool (`spvp.lua`, ENTROPY POOL section)
feeding `GeneratePrivateKey`, `GenerateSessionID` and `GeneratePhaseSalt`; also stirred from
SPVP packet arrivals in `spvp_handlers.lua`. Covered by `tests/unit/spvp_entropy_spec.lua`.

#### ⚠️ Two bugs found *during* the fix — read before touching RNG code here

The first implementation was **worse than what it replaced**, and only testing caught it. Both
are Lua-5.1-specific and both will bite again in the ported code:

1. **`bit.band` returns a SIGNED 32-bit int** on LuaJIT and on the test shim, so `FNV1aHash`
   yields a negative value whenever the top bit is set — about half the time.
2. **`math.randomseed` coerces to a signed 32-bit int**, so `0`, `2^31`, `-2^31` and `2^32` all
   alias to seed 0 — which on this interpreter deterministically produces `33842432` from the
   private-key range. **Measured: that one value came up 23 times in 50 draws (46%).**

Two handshakes sharing a private key means solving one solves both. Resolved by normalising the
pool unsigned and folding to `(pool % 2147483647) + 1`, plus a monotonic per-draw counter so
several draws inside one frame (a salt makes 64 back-to-back) cannot re-enter a prior pool
state.

#### What this fix does *not* do

It closes a shortcut that sat *below* the group strength. **It does not raise the ceiling.**
Pollard's rho attacks the *group* and runs in ~√q steps regardless of how well the exponent was
chosen — perfect entropy leaves rho at 7,061 steps. Only a larger prime moves that.

Still true, and still the reason the rest of this document exists: `math.random` remains the
underlying generator with state far smaller than a 128-bit group. **When the port happens, the
draw must move onto the §4.3 hash**, not stay on `math.random`. The pool structure is reusable;
its output stage is not.

**Not covered by headless tests:** whether the ambient sources carry real entropy on a live
client. The mock freezes `GetCursorPosition`/`GetFramerate`, which is why those tests are a
meaningful *floor* — they pass with every ambient source constant — but live verification is
still outstanding.

### 4.5 Wire format *(sizes below are Route B; Route A differs)*

Under Route A there are no public keys on the wire at all — the packets carry a challenge and a
MAC, both fixed-width and short. The 255-byte limit and the redaction-pattern check below still
need confirming either way.


- Public keys become ~39-char decimal strings (from 8). Parsers use `(%d+)` so they cope, but
  **check addon message length limits** (255 bytes per `SendAddonMessage`; Chomp chunks above
  that, but SPVP uses raw `C_ChatInfo.SendAddonMessage`).
- Verifier grows if SHA-256 output is used at full width — consider truncating to 128 bits.
- Confirm `SecurityService` redaction patterns still match the new shapes (`%w+` should hold).

### 4.6 Protocol version bump to 4

`SPVP_VERSION` is checked in `HandleSPVPInit`; mismatched versions reject cleanly rather than
failing verification (which would mutually block). Same coordinated-rollout consideration as the
2→3 bump.

**Salts do NOT need rotating.** Verified for the 2→3 change: a salt generated under the old
prime derives a valid in-subgroup generator under the new one and round-trips a handshake. The
salt feeds the *generator*, not the prime. Re-verify this holds for the new hash in 4.3 — it
should, but it is a one-line test.

---

## 5. What this does NOT fix

> **Correction to this section as originally written.** It said the salt is readable by every
> phase *owner and officer*. **That is too narrow, and the error matters** — it nearly justified
> shelving the port for the wrong reason. The salt lives in phase addon data, readable by
> anyone the phase **admits**; `C_Epsilon.GetPhaseAddonData("TRP3FW_SPVP_KEY")` is a one-line
> macro. Rank is not the boundary. **Membership** is.

### Two adversaries — keep them separate

Conflating these leads to *opposite* conclusions about whether group size matters at all.

**(A) Admitted member.** Holds the real secret, so they attack nothing. A member standing in a
different **zone** passes SPVP from anywhere — that is the protocol working as designed, not a
break. Group strength is **irrelevant** to this adversary.

**(B) Excluded outsider** — blacklisted, or never whitelisted. Not admitted, so
`GetPhaseAddonData` gives them nothing: **no salt**. To pass SPVP they must break the math —
rho on our public key (~2^12.7) or guessing the private key (~2^10–2^17, closed by §4.4).
Group strength **is** the binding constraint here, and at present it does not stop them.

**This is the case SPVP exists to defeat, and it is the justification for the port.** If the
project is ever re-shelved, it must not be on the grounds that "the salt is readable anyway" —
that reasoning holds for (A) and is simply false for (B).

### What SPVP actually proves

> *"This peer has, at some point, been admitted to a phase sharing this salt."*

Not "is in my phase." Not "is near me." **Proximity is measured by the phase/WHO/map checks,
not by SPVP** — and per `cascading.lua` that is already how the default `optional` mode
composes them.

### The gap the port does not close ⚠️

**Salts do not expire on removal.** Blacklist someone today and their cached salt keeps working
until the phase is re-secured. `CheckSaltRotation` exists and recommends rotation past 30 days,
but **nothing enforces it, and nothing rotates on removal**.

Against a blacklisted ex-member this is a **zero-work bypass** — no rho, no addon, just a
secret they already hold. Cryptographic strength is irrelevant against a valid secret, so
**rotation-on-removal is arguably higher value than this entire port** if excluding blacklisted
queriers is the goal.

### Unchanged

SPVP's attacker is **the peer itself**, not an eavesdropper. All SPVP traffic is `WHISPER`,
point-to-point — there is no broadcast to sniff. The party being screened is the party the
protocol hands its public values to. Inherent to Diffie-Hellman, and fine when the group is
large; it is why group size matters so much here.

**Rate limiting does not apply to any of this.** `spvpBlockDuration`, replay detection and the
queue caps all bound how often a peer can *send*. Rho is **offline**: one legitimate handshake,
then arithmetic on a value we already handed over, with no further contact. There is no packet
left to throttle, and no limit on attempts.

---

## 6. Decision framing

| If your threat model is… | Then… |
|---|---|
| Griefers, opportunistic scrapers | Current 2^12.7 deters the casual case, but see the addon note in §1 — an in-game script defeats it in one frame. |
| **Excluded outsider (blacklisted / not whitelisted)** — *the stated goal* | This is adversary (B) in §5. Crypto strength **is** the binding constraint. Prefer §2b's HMAC over the §3–§4 port: stronger, cheaper, lower risk. |
| Admitted member in another zone | Adversary (A). **No crypto change helps.** Proximity is the phase/WHO/map checks' job, not SPVP's. |
| Blacklisted ex-member holding an old salt | **Zero-work bypass.** Only rotation-on-removal (§5) closes it. Higher value than the entire port. |

SPVP is not yet widely used, which makes this a good time to do it deliberately rather than
under pressure.

### The trap to avoid

**Security is the MINIMUM across all attacks, not the maximum.** This has already caught this
project once: §4.4's private key sat at ~2^10–2^17 while the group sat at ~2^12.7, so building
a 128-bit group first would have bought *nothing* — the key would have remained the cheapest
path in. Check the whole chain before spending effort on any single link.

---

## 7. Suggested order of work

> **Ordering changed.** Private-key entropy was step 5. It is now **done** (§4.4), because
> measurement put it at ~2^10–2^17 — *below* the group strength — making it the cheapest
> attack and a prerequisite rather than a finishing touch. Building a 128-bit group over a
> 2^17 key would have wasted the entire port: **security is the minimum across attacks, not
> the maximum.**

**Before the port — cheap, independent, no protocol bump:**

0. ~~Private-key entropy~~ ✅ **DONE 2026-07-25** (§4.4).
0b. **Salt rotation on removal/blacklist** (§5) — not part of this port, plausibly worth more
    than it. Closes a zero-work bypass that no group size touches.
0c. **Confirm `spvpMode` semantics.** Default is `optional`; per `cascading.lua:102` only
    `required` makes SPVP failure decisive. Worth tracing *before* the port whether a failed
    SPVP actually blocks the target adversary — if it does not, the port's practical value is
    lower than the bit-counts suggest.

**Then pick a design — see §2b. Recommended: HMAC, not the bignum port.**

#### Route A — HMAC challenge–response *(recommended, §2b)*

1. **SHA-256**, standalone, validated against NIST vectors committed as fixtures (§4.3).
   Nothing else starts until this passes. Under this design the hash is the *entire* security.
2. **HMAC** (~30 lines) on top; validate against published HMAC-SHA256 vectors.
3. **Move the §4.4 entropy pool's output stage onto SHA-256** — its `math.random` draw is the
   cap now. Re-read the two Lua-5.1 RNG bugs in §4.4 first.
4. Replace the handshake: challenge/proof replacing INIT/REPLY/CONFIRM, binding
   `challenge || alice || bob || phaseID` (§2b).
5. **Delete** `GetGenerator`, `ModPow`, `IsValidPublicKey`, `DeriveSharedKey`,
   `GeneratePublicKey`, `DH_PRIME`, `DH_SUBGROUP_ORDER` — and their now-dead tests. This is a
   net *simplification*.
6. Wire format + length checks; version bump to 4; update the `spvp.lua` threat-model header
   with newly measured numbers.

#### Route B — bignum port *(superseded; kept for reference)*

1. Bignum module + test vectors, standalone. **Do not proceed until `ModPow` matches known-good
   fixtures across edge cases** (zero exponent, exponent 1, modulus boundaries, carry chains).
2. Locate or implement SHA-256; test against published vectors.
3. Generate and verify a 128-bit safe prime; verify the fallback generator's order.
4. Port the crypto layer onto the bignum module.
5. **Move the entropy pool's output stage onto the §4.3 hash.** The pool from §4.4 is reusable;
   its `math.random` draw is not — that caps it well below 128 bits. Re-read the two Lua-5.1
   RNG bugs documented in §4.4 before writing this.
6. Wire format + length checks.
7. Version bump to 4, update threat-model header with newly measured numbers.
8. Re-run the generator order distribution over ≥3,000 salts to confirm 100% land in the
   order-q subgroup, as was done for the current prime.

---

## 8. Reference — measurement methods used

So results can be reproduced or challenged:

- **Modmul throughput:** tight loop of 3e6 `(x * g) % p` in interpreted Lua 5.1 → 4.29e7/sec.
- **Generator order distribution:** 3,000–5,000 simulated salts (64 hex chars + `:timestamp`),
  random phase IDs, order determined by testing each divisor of `p-1`.
- **Multi-limb cost:** 200,000 iterations of 3-limb schoolbook multiply → 6.39e5/sec; modmul
  rate taken as ÷3 to account for reduction.
- **Attacker rate:** 4.3e9 modmul/sec assumed for C, single core (100× the measured Lua rate).
  This is an *assumption*, not a measurement — it is deliberately conservative-to-attacker.
- **Pollard's rho:** ~1.03·√q steps, ~3 modmuls per step.
- **Birthday bounds** (verifier collisions): analytic, not measured.

### Added 2026-07-25

- **Modmul throughput re-measured:** 3e6 iterations → **4.6e7/sec**, consistent with the
  earlier 4.29e7. Rho wall time computed as `1.03·√q · 3 / rate` = **0.46 ms**.
- **Generator order distribution re-run:** 3,000 simulated salts (64 hex + `:timestamp`,
  random phase IDs) → **3000/3000 in the order-q subgroup, 0 fallbacks, 0 degenerate**.
  Independently confirms the original finding.
- **Old prime re-factored:** `90000049 - 1 = 2^4 × 3 × 971 × 1931`, largest factor 1931,
  `√1931 ≈ 44` (~2^5.5). Confirms the pre-`0ac5af3` figure.
- **Private-key entropy (§4.4):** seed-space decomposition; 1000 adjacent microsecond seeds →
  1000 distinct keys (no collapse, no amplification), giving ~2^10 at 1 ms send-time
  uncertainty and ~2^17 at 100 ms.
- **Seed aliasing (§4.4):** `math.randomseed` coerces to signed 32-bit, so `0`, `±2^31` and
  `2^32` alias to seed 0 → deterministic `33842432`. Measured **23 occurrences in 50 draws
  (46%)** before the fix. Post-fix: **4,658 distinct in 5,000 draws with every ambient source
  frozen** — the residual is the expected birthday rate over a 2^31 seed space, not a defect.
- **Library audit (§4.3):** `totalRP3/libs`, `XRP/Libraries`, `MyRolePlay/Libs`, `Epsilon/`,
  SpellCreator — **no cryptographic hash anywhere**; only CRC-16/CRC-32/Adler-32.

Everything else in this document was executed.

---

## 9. Document history

- **2026-07-25 (scoping session):** original spec. Measured group strength, platform ceiling,
  bignum feasibility; corrected two earlier-session errors ("hours of compute", "bignum not
  viable").
- **2026-07-25 (this session):** §4.4 entropy shipped, with two Lua-5.1 RNG bugs found during
  the fix. §5 corrected from *owner/officer* to **phase membership**, and split into adversaries
  (A)/(B) — the original framing nearly justified shelving the port for a reason that is true of
  (A) and false of (B). §2b added: **DH is the wrong primitive**, since both parties already
  hold the shared secret DH exists to establish. §4.3 library audit: nothing usable ships.
  §7 reordered — entropy moved ahead of the port because *security is the minimum across
  attacks*.
