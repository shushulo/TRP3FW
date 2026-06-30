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
