# TRP3 Firewall 1.6.0

The largest release so far: 110 commits since v1.4, touching 189 files. The settings UI was
rebuilt from scratch, the internals were reorganised into services and a staged pipeline, a
headless test suite was added (634 tests), and the SPVP phase-verification crypto was hardened
substantially.

**Upgrading is safe.** Your settings, profiles and whitelists carry over — nothing needs to be
reconfigured or reset. See *Notes on upgrading* below for two things worth knowing.

---

## Highlights

### Rebuilt settings interface

`/trp3fwui` now opens a tabbed window skinned to match Total RP 3's look, replacing the single
long scroll of checkboxes.

* **Eight tabs** — Dashboard, Protection, Notifications, Appearance, Profiles, Security, Status,
  Advanced.
* **Complexity levels** — pick Basic, Intermediate, Advanced or Everything and the UI hides
  options above that level instead of burying you in all of them. Changing the level only
  changes what you *see*; it never changes how the firewall behaves.
* **Search** — jump straight to any setting by name, with its full description in the result.
  Settings above your complexity level are shown greyed with a note, rather than hidden.
* **Dashboard** — live cache hit rates, colour-coded by health, plus recent activity.
* **Quick presets** — Relaxed, Balanced, Recommended, Strict, Ghosty, each with a tooltip
  spelling out exactly what it sets.

### `/trp3fwui` actually works now

The command has been in the help text, the README and the on-screen tips for a long time, but it
was **never registered** — the minimap button and the first-run prompt were the only ways into
the settings window. If you had hidden the minimap button, you were locked out of your own
settings with the help text still telling you to type a command that did nothing.

Now registered, with `/trp3fwui show`, `/trp3fwui hide`, and `/trp3fw ui` (also `config`,
`options`) as aliases.

### SPVP phase verification hardened

SPVP is the cryptographic handshake that proves two players are in the same Epsilon phase. Its
effective security went from roughly **2^5.5 to 2^12.7** — about 156x — via three fixes:

* **Safe prime.** The old modulus was correctly sized but factored into small pieces, letting
  Pohlig-Hellman collapse the work to ~44 operations. The size was never the problem; the
  factorisation was. The new prime has no such structure.
* **64-bit verifier.** The old 32-bit verifier could be collided in ~2^16 tries by the birthday
  bound — *without solving any discrete log*, which made it the cheapest attack on the protocol
  and would have stayed the binding constraint even after fixing the prime. Now ~2^32.
* **Generator validation.** Two degenerate generator values collapsed the shared key to a single
  constant, making the handshake succeed for *anyone* regardless of phase. Both now rejected.

Also fixed: a **forgeable salt response**. The addon-message handler matched incoming packets
against pending salt tickets *before* checking the message prefix, and the prefix is chosen by
whoever sends the message. Since Epsilon's salt tickets are short and not secret, a player who
guessed or observed a live ticket could deliver a fake salt response as though the server had
answered — either installing a salt of their choosing for the phase, or poisoning the phase for
an hour and cutting off legitimate peers mid-handshake. Now rejected.

Protocol version bumped 2 → 3. Existing phase salts do **not** need rotating.

**Honest scope note:** SPVP raises the cost of forging a phase claim; it is not strong
cryptography. The modulus is bounded by Lua 5.1's exact-integer range, and a private exponent
was recovered by brute force in 0.16 seconds of interpreted Lua on a single core. This is
inherent to the platform, not a defect — but the file is named "Secure Phase Verification
Protocol" and previously did not say so anywhere. Treat it as a deterrent against casual
spoofing, not a security boundary.

### Ghost mode reaches MSP addons

Ghost replacement for MyRolePlay and XRP profiles was gated on a flag that was **never set**, so
MSP-protocol profiles were never actually ghosted — they went out as your real profile. Now
wired to the real check, and it fails closed. MSP `FC`/`FR` (in-character flag and RP-experience
level) are also mapped properly, so a ghosted MRP/XRP profile no longer reports
**in-character** when the source profile is flagged OOC.

If you use ghost mode with MyRolePlay or XRP, this is the most consequential fix in the release.

### Content filters (Appearance tab)

Filter changes take effect after `/reload`.

* **Icons** — no longer strips glance icons from other players' profiles; coverage widened to
  more fields, and leftover whitespace is cleaned up.
* **Minimum font size** — enforce a floor so nobody can send you unreadably small text.
* **Gradients** — colour-gradient stripping, with the installer now idempotent so
  `/trp3fw reloadhooks` stops stacking duplicate wrappers.

### Phase checking

* **Quieter** — WoW's target-acquired sound is muted during automated phase-check targeting
  (`muteTargetSound`, on by default). Done via `MuteSoundFile` rather than wrapping the global
  `PlaySound`, which taints the UI and breaks logout.
* **Inspect-aware** — optionally defer targeting while the armory/inspect frame is open
  (`pausePhaseCheckOnInspect`), so automated checks stop interrupting you.
* **Respects manual targeting** — an in-flight check no longer overwrites a target you picked
  yourself.
* **More reliable** — exact-match targeting, targets verified by unescaped name *and* player
  type (so NPCs with player-like names can't be mistaken for the player), longer timeouts
  (3.0s/1.5s), and fixed deadline races that dropped callbacks.
* `/trp3fw phasecheck` no longer reports "No other players found" when players were present.

---

## Reliability and correctness

Two systematic review passes worked through the codebase file by file, closing out roughly 100
tracked items. The ones most likely to have affected you:

* **Fail-closed send paths.** A send to an unparseable recipient used to be transmitted
  ungated; a scan reply from an invalid name was allowed through. Both now blocked. Errors
  inside the Chomp hook pipeline are contained instead of passing the send through.
* **Apostrophe names.** Cache keys for names like `Ahn'Qiraj` were built inconsistently across
  two caches, so the same player could be treated as two different people.
* **Accented names** were rejected outright by a malformed sanitizer pattern.
* **Replay protection was a no-op** — the SPVP session cache was never registered, so nothing
  was stored and replays weren't detected.
* **Stale phase-cache reuse.** A cached phase-check *failure* could be treated as fresh for up
  to 60s instead of expiring at its own 10s TTL.
* **Unbounded network-fed state.** Two tables written directly from incoming addon messages had
  no cap and no expiry. Replay detection didn't bound them, because the sender picks their own
  session ID. Both now capped and expired.
* **Cross-phase verification.** A handshake queued in one phase could be verified against a
  different phase's salt after you moved.
* **Salt material reached chat and the debug log** in a form no redaction pattern matched. Now
  fingerprinted.
* **Infinite recursion** in the WHO service's background cache refresh.
* **Statistics were wrong** — per-type block/ghost counts always showed 0.
* **`/trp3fw minimapreset`** always reported "not available"; the function didn't exist.
* **Memory** — the Profiles tab leaked frames on every refresh (WoW never garbage-collects
  frames); the profiler's sample buffer was unbounded.

## Under the hood

* **Service container** — six services (events, caching, history, notifications, security, WHO)
  with a real lifecycle, replacing scattered global state.
* **Staged decision pipeline** — every profile request flows through named stages with early
  exits, so *why* a request was allowed, blocked or ghosted is traceable rather than inferred.
* **Unified LRU cache layer** — 13 caches with O(1) operations, size caps and TTLs.
* **634 headless tests**, run on every push via CI, plus in-game integration tests (WoWUnit).
  Every regression test in this release was verified to *fail* against the code it pins before
  being kept — including the two salt-forgery tests.
* Dead code removed: superseded ghost generation, abandoned feature-flag scaffolding, a stale
  pipeline stage, and no-op init/hook remnants.

---

## Notes on upgrading

**The version number went down.** This release is **1.6.0**, while some installs report
`2.9.2-hotfix`. That is deliberate — the addon version is now unified with its branch line, and
the old 2.9.x numbering was abandoned. 1.6.0 is *newer* than 2.9.2 despite the smaller number.
Nothing breaks; just don't be alarmed.

**Default behaviour is alert-only.** Out of the box TRP3FW notifies you but **blocks nothing**
(equivalent to the Balanced preset), so you can watch what it would do before letting it act. If
you want blocking, apply **Recommended** or **Strict** on the Protection tab. Existing
installs keep whatever they already had configured.

**SPVP 2 and 3 don't interoperate.** Players still on an older version can't complete a
handshake with you. This is a clean mutual rejection, not a failure — the request simply falls
through to the normal phase/WHO/map checks and is decided there. Nothing gets blocked because of
it.

**Requires** Total RP 3, MyRolePlay, or XRP. Phase checks and WHO queries need the Epsilon
server's API; map scanning works everywhere. `/trp3fw status` shows what was detected.

---

## Install

1. Download `TRP3FW.zip` and extract into `World of Warcraft/_retail_/Interface/AddOns/`.
2. If the folder has a version number in its name, rename it to just `TRP3FW`.
3. `/reload`, then `/trp3fwui`.

**Interface:** 9.2.7 (90207) · **License:** GPL-3.0
