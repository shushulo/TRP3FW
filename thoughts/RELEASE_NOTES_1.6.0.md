# TRP3 Firewall 1.6.0

The largest release so far: 110 commits since v1.4 across 189 files. Rebuilt settings UI,
reorganised internals, hardened phase verification, and a 634-test suite running on every push.

**Upgrading is safe** — settings, profiles and whitelists all carry over.

---

## Highlights

**Rebuilt settings interface** — `/trp3fwui` opens a tabbed window skinned to match Total RP 3.

* Eight tabs: Dashboard, Protection, Notifications, Appearance, Profiles, Security, Status, Advanced
* Complexity levels (Basic → Everything) hide options above your level — display only, never changes behaviour
* Search any setting by name, with its full description in the result
* Dashboard with live cache hit rates, colour-coded by health
* Quick presets — Relaxed, Balanced, Recommended, Strict, Ghosty — each with a tooltip listing exactly what it sets

**`/trp3fwui` actually works now**

* The command was in the help text, README and on-screen tips but was **never registered**
* The minimap button and first-run prompt were the only ways in — hiding the button locked you out of your own settings
* Now registered, with `/trp3fwui show|hide` and `/trp3fw ui` (also `config`, `options`)

**Ghost mode reaches MSP addons** — the most consequential fix in this release if you ghost with MyRolePlay or XRP.

* Ghost replacement for MRP/XRP was gated on a flag that was never set, so those profiles **were never actually ghosted** — your real profile went out while the UI said ghosting was on
* Now wired to the real check, and it fails closed
* MSP `FC`/`FR` mapped properly, so a ghosted profile no longer reports **in-character** when the source is flagged OOC

**Phase verification (SPVP) hardened**

* Stronger cryptographic parameters throughout — protocol version bumped 2 → 3
* Closed a case where a malformed handshake could succeed regardless of actual phase
* Fixed a forged-salt path: incoming packets were matched against pending requests before the message prefix was checked, so a crafted message could impersonate a server response
* Replay protection now actually stores sessions — it was previously a silent no-op
* Handshake state fed from the network is now capped and expired
* Existing phase salts do **not** need rotating

**Phase checking**

* Target-acquired sound muted during automated targeting (`muteTargetSound`, on by default)
* Optionally defer targeting while the inspect frame is open (`pausePhaseCheckOnInspect`)
* An in-flight check no longer overwrites a target you picked yourself
* Exact-match targeting; targets verified by name *and* player type, so NPCs can't be mistaken for players
* Longer timeouts (3.0s/1.5s) and fixed deadline races that dropped callbacks
* `/trp3fw phasecheck` no longer reports "No other players found" when players were present

**Content filters (Appearance tab)** — changes take effect after `/reload`.

* Icons: no longer strips glance icons from other players' profiles; wider field coverage
* Minimum font size: enforce a floor so nobody can send unreadably small text
* Gradients: installer now idempotent, so `/trp3fw reloadhooks` stops stacking duplicate wrappers

---

## Reliability and correctness

Two systematic review passes worked through the codebase file by file. Most likely to have affected you:

* **Fail-closed send paths** — sends to an unparseable recipient were transmitted ungated; scan replies from invalid names were allowed through. Both now blocked, and Chomp pipeline errors are contained rather than passing the send through
* **Apostrophe names** (`Ahn'Qiraj`) — inconsistent cache keys across two caches meant one player could be treated as two
* **Accented names** were rejected outright by a malformed sanitizer pattern
* **Stale phase-cache reuse** — a cached failure could be treated as fresh for up to 60s instead of expiring at its own 10s TTL
* **Cross-phase verification** — a handshake queued in one phase could be verified against another phase's salt after you moved
* **Salt material** reached chat and the debug log in a form redaction didn't match; now fingerprinted
* **Infinite recursion** in the WHO service's background cache refresh
* **Statistics** — per-type block/ghost counts always showed 0
* **`/trp3fw minimapreset`** always reported "not available"; the function didn't exist
* **Memory** — the Profiles tab leaked frames on every refresh (WoW never garbage-collects frames); the profiler's sample buffer was unbounded

## Under the hood

* Service container — six services (events, caching, history, notifications, security, WHO) with a real lifecycle
* Staged decision pipeline — named stages with early exits, so *why* a request was allowed, blocked or ghosted is traceable
* Unified LRU cache layer — 13 caches, O(1) operations, size caps and TTLs
* 634 headless tests on every push via CI, plus in-game integration tests. Every regression test was verified to *fail* against the code it pins before being kept
* Dead code removed: superseded ghost generation, feature-flag scaffolding, a stale pipeline stage, no-op init/hook remnants

---

## Notes on upgrading

* **The version number went down.** This is **1.6.0**, while some installs report `2.9.2-hotfix`. Deliberate — versioning is now unified with the branch line and the old 2.9.x numbering was abandoned. 1.6.0 is *newer* despite the smaller number.
* **Default is alert-only.** Out of the box TRP3FW notifies but **blocks nothing** (equivalent to Balanced), so you can watch what it would do first. For blocking, apply **Recommended** or **Strict** on the Protection tab. Existing installs keep their current configuration.
* **SPVP 2 and 3 don't interoperate.** Players on an older version can't complete a handshake with you. This is a clean mutual rejection — the request falls through to the normal phase/WHO/map checks and is decided there. Nothing is blocked because of it.
* **Requires** Total RP 3, MyRolePlay, or XRP. Phase checks and WHO queries need Epsilon's API; map scanning works everywhere. `/trp3fw status` shows what was detected.

## Install

1. Download `TRP3FW.zip` and extract into `World of Warcraft/_retail_/Interface/AddOns/`
2. If the folder has a version number in its name, rename it to just `TRP3FW`
3. `/reload`, then `/trp3fwui`

**Interface:** 9.2.7 (90207) · **License:** GPL-3.0
