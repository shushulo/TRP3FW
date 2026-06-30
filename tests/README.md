# TRP3FW Tests

Two layers: **headless unit tests** (pure logic, run on your machine) and
**in-game integration tests** (need the WoW client).

## Headless unit tests

Pure-Lua tests for algorithmic code (crypto, name sanitization, cache LRU,
WHO-fallback classification). They load the real addon modules under a small
WoW API shim (`mock_wow.lua`) — no game required.

**Run them** from the addon root:

```sh
"C:\Program Files (x86)\Lua\5.1\lua.exe" tests/run_headless.lua
```

Exit code is non-zero if any test fails (CI-friendly).

### Layout

- `mock_wow.lua` — minimal WoW API + `bit` library shim
- `harness.lua` — builds a minimal `TRP3FW` namespace and loads module files
- `framework.lua` — tiny zero-dependency describe/it/assert framework
- `run_headless.lua` — runner; lists which specs to run
- `unit/*_spec.lua` — the specs

### Adding a spec

1. Create `unit/your_thing_spec.lua`:
   ```lua
   local T = require("tests.framework")
   local H = require("tests.harness")
   local TRP3FW = H.newNamespace()
   H.loadModule("path/to/module.lua", TRP3FW)
   T.describe("your thing", function()
     T.it("does x", function() T.eq(1 + 1, 2) end)
   end)
   return T
   ```
2. Add `"tests.unit.your_thing_spec"` to the `specs` list in `run_headless.lua`.

Use `H.mock.setClock(t)` / `H.mock.advance(s)` to control time, and
`H.mock.flushTimers()` to fire pending `C_Timer` callbacks.

### What's covered

- `spvp_crypto_spec` — ModPow, FNV-1a, HashKey, the SPEKE DH key agreement
  (both parties derive the same shared key; wrong salt diverges).
- `sanitize_spec` — SanitizePlayerName / CleanPlayerName (accented names
  accepted, digits rejected, nil-safe). Guards the name-regex fix.
- `cache_interface_spec` — LRU eviction, TTL expiry, Clear/Remove, and the
  unregistered-cache behavior that the spvpSessions fix relied on.
- `who_fallback_spec` — which WHO failure sources trigger the map-scan
  fallback (and which correctly don't).
- `utils_security_spec` — the security helpers in `core/utils.lua`:
  `SanitizeZoneName` (whitelist guard), `CreateVerifiedSendId`/`VerifySendId`
  (signature round-trip + spoof rejection), `RunPrivilegedSafe` (token-bucket
  rate limiting incl. reserved-token tiers and refill), `ValidateSettings`
  (bounds clamping to defaults), `GetCategoryPriority`, and `FormatTime`.
- `profile_adapters_spec` — the cross-addon profile adapters (TRP3/MRP/XRP) and
  the detection factory: availability gating, the common `{id,name,addon,
  isCurrent,data}` shape, the TRP3 register fallback, the MSP→TRP3 field
  mapping (MRP/XRP), and factory priority order + caching.
- `pipeline_spec` — the decision-pipeline engine (`Pipeline`/`Stage`/`Context`):
  stage ordering, early-exit on `handled`, malformed-stage tolerance, and
  `Context` timestamp behavior.
- `start_phase_spec` — `ShouldBlockForStartPhase` (the phase-169 start-phase
  decision): whitelist bypass, profile-send gating, profile-switch override,
  Epsilon-API-absent path, and the phase-169 ghost-vs-block precedence (ghost
  wins only when an exchange hook is present, else falls back to block/allow).
- `history_service_spec` — `HistoryService` accounting: per-type block/ghost
  breakdown (the combined `phase+map` `:find` logic), `start_phase_block`
  bucketing, `maxHistorySize` capping, `IncrementStat` nested/top-level guards,
  `TrackAddonRequest` dedup/case-folding, and the send-history suppression
  window (`IsFirstSend`/`RecordSend`).

## In-game integration tests

`integration_tests.lua` is loaded by the `.toc`. It needs the live addon
(services, pipeline, frames) so it only runs in-game:

```
/trp3fwtest
```

Output goes to chat. Tests are read-only / self-cleaning and never send addon
messages to other players. Covers service wiring, the decision pipeline,
cache registration, the ghost-flag lifecycle, minimap reset, and stat fields.

## In-game tests under WoWUnit

The same in-game coverage, plus deterministic mocking, runs under
[WoWUnit](https://github.com/Jaliborc/WoWUnit). WoWUnit's value over the
hand-rolled `/trp3fwtest` harness is `Replace()` — it temporarily fakes a global
or a table field for the duration of one test and auto-reverts afterward — which
lets us drive the *live* Epsilon/decision paths deterministically without a real
phase or a real `C_Epsilon`.

### Installing WoWUnit

WoWUnit is **vendored** at `tests/WoWUnit/` (pinned to upstream tag `9.0.1`, the
latest Shadowlands-era release — there is no `9.2` tag; its `.toc` Interface was
bumped to `90207` so it loads on a 9.2.7 client). WoW loads addons as siblings
under `Interface/AddOns/`, so the vendored copy must be made available there —
e.g. a directory junction (run once, from an elevated shell):

```cmd
mklink /J "<WoW>\Interface\AddOns\WoWUnit" "<repo>\TRP3FW\tests\WoWUnit"
```

TRP3FW lists `WoWUnit` in its `## OptionalDeps`, so when it's present WoWUnit
loads first and the test files register their groups. When it's absent, both
test files no-op (`if not _G.WoWUnit then return end`) and the firewall loads
normally — so missing WoWUnit is never an error.

### Running

Tests auto-run at `PLAYER_LOGIN` (and re-run when their registered events fire).
Open the results panel with WoWUnit's minimap-adjacent toggle button (its colour
reflects pass/fail; click a failing test to see the error log).

### What's covered (`tests/ingame_wowunit/`)

- `TRP3FW_Smoke.lua` — the `/trp3fwtest` cases ported to WoWUnit (no mocking):
  service wiring, pipeline-has-stages, cache registration, the `spvpSessions`
  round-trip, ghost-flag lifecycle, live name sanitization, minimap reset,
  per-type stat fields, and the whitelist round-trip.
- `TRP3FW_Mocked.lua` — the mocking layer (the reason for the dependency):
  - **Decision logic** — `ProcessLocationDecision` mapping of
    `phaseCheckMode`/`mapCheckMode` (block / ghost / alert / alert_block /
    alert_ghost) and `start_phase_block` to the `shouldBlock/shouldAlert/useGhost`
    args, captured by spying on `ApplyLocationDecision`. Drives the real
    `ShouldAlertOnPhase`/`ShouldBlockOnMap`/… predicates via mocked `Prefs`.
  - **Epsilon phase API** — `GetCachedPhaseID` against a mocked `C_Epsilon`
    (returns the mocked id; returns nil when `hasEpsilonAPI` is false).
  - **Privileged gating** — `RunPrivilegedSafe` returning `api_unavailable`
    without the Epsilon API and `invalid_code` for non-string code.

The `/trp3fwtest` command and the headless suite still work independently;
WoWUnit is an additional layer, not a replacement.
