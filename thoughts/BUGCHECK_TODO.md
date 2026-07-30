# Module Bug-Check TODO

Tracks a systematic per-module review pass across the whole addon. 62 files, ~21,947 lines total. Order follows dependency layering — lower layers first, since a bug in a foundational module can produce misleading symptoms in everything built on top of it.

Check off each file as its window finishes. Line counts are included so windows can be balanced by effort, not just file count.

## 1. Core (foundation — check first)

- [x] `core/Context.lua` (17)
- [x] `core/Service.lua` (32)
- [x] `core/Pipeline.lua` (41)
- [x] `core/Stage.lua` (41)
- [x] `core/ServiceContainer.lua` (45)
- [x] `core/EventService.lua` (115)
- [x] `core/feature_flags.lua` (142)
- [x] `core/cache_interface.lua` (270)
- [x] `core/init.lua` (788)
- [x] `core/utils.lua` (893)

## 2. Services (depend on core)

- [x] `features/services/SecurityService.lua` (231)
- [x] `features/services/HistoryService.lua` (370)
- [x] `features/services/WhoService.lua` (615)
- [x] `features/services/NotificationService.lua` (674)
- [x] `features/services/CacheService.lua` (779)

## 3. Pipeline & Stages (depend on core + services)

- [x] `features/pipelines/DecisionPipeline.lua` (32)
- [x] `features/stages/BurstStage.lua` (46)
- [x] `features/stages/WhitelistStage.lua` (51)
- [x] `features/stages/SPVPStage.lua` (87)
- [x] `features/stages/AlertFastPathStage.lua` (97)
- [x] `features/stages/InteractionStage.lua` (143)
- [x] `features/stages/LocationStage.lua` (150)
- [x] `features/stages/CacheStage.lua` (194)

## 4. Location Detection (depend on core + services)

- [x] `location/who.lua` (120)
- [x] `location/cascading.lua` (538)
- [x] `location/maps.lua` (631)
- [x] `location/phase.lua` (1146)

## 4b. Encryption / SPVP (depends on core + services; sits between location and hooks)

Added late — this directory was missing from the original checklist entirely despite being in
the .toc and shipping.

- [x] `features/encryption/spvp_handlers.lua` (49)
- [x] `features/encryption/spvp_auto_init.lua` (87)
- [x] `features/encryption/spvp.lua` (834)

See "Section 4b findings" below. New spec `tests/unit/spvp_queue_bounds_spec.lua` (19 tests);
verified failing against the originals for every bug claimed.

SPVP was subsequently hardened within its current design (commit `0ac5af3`: safe prime, 64-bit
verifier, generator subgroup validation) — raising effective security from ~2^5.5 to ~2^12.7.
That is still low. Going further needs multi-limb arithmetic and a real hash, which is scoped
as a separate project in **[SPVP_CRYPTO_UPGRADE_SPEC.md](SPVP_CRYPTO_UPGRADE_SPEC.md)** — not
started, deliberately deferred.

## 5. Hooks (depend on core/services/location; intercept external addon APIs)

- [x] `hooks/installer.lua` (136)
- [x] `hooks/fontsize.lua` (225)
- [x] `hooks/icon.lua` (241)
- [x] `hooks/gradient.lua` (246)
- [x] `hooks/trp3_chomp_pipeline.lua` (297)
- [x] `hooks/trp3_scan_pipeline.lua` (417)
- [x] `hooks/msp.lua` (430)
- [x] `hooks/msp_exchange.lua` (537)
- [x] `hooks/trp3.lua` (655)

## 6. Profile Adapters (depend on core; used by features)

- [x] `features/profiles/adapter_interface.lua` (60)
- [x] `features/profiles/adapter_trp3.lua` (193)
- [x] `features/profiles/adapter_mrp.lua` (212)
- [x] `features/profiles/adapter_xrp.lua` (223)
- [x] `features/profiles/adapter_factory.lua` (226)

## 7. Features (depend on everything above)

- [x] `features/notifications.lua` (37)
- [x] `features/ghostmode.lua` (62)
- [x] `features/ghostmode_trp3.lua` (315)
- [x] `features/decision.lua` (600)
- [x] `features/profileswitch.lua` (994)

## 8. UI (depend on features; user-facing, check after logic is confirmed sound)

- [x] `ui/tabs/Filters.lua` (81)
- [x] `ui/tabs/Profiles.lua` (125)
- [x] `ui/tabs/Notifications.lua` (143)
- [x] `ui/Theme.lua` (227)
- [x] `ui/debugwindow.lua` (227)
- [x] `ui/tabs/Dashboard.lua` (280)
- [x] `ui/tabs/Security.lua` (292)
- [x] `ui/tabs/Debug.lua` (333)
- [x] `ui/tabs/Alerts.lua` (392)
- [x] `ui/tabs/Status.lua` (392)
- [x] `ui/historywindow.lua` (848)
- [x] `ui/TabManager.lua` (1106)
- [x] `ui/settings.lua` (1268)

## 9. Root / Entry Points (tie everything together — check last)

- [x] `status.lua` (343)
- [x] `TRP3FW.lua` (114)
- [x] `commands.lua` (1382)

## 10. Release Pass (v1.6.0)

Found during the pre-release once-over, after sections 1-9 were closed out.

- [x] **HIGH / security: SPVP salt responses could be forged over the network** (fixed) —
  `features/encryption/spvp_handlers.lua:22`. The `CHAT_MSG_ADDON` handler checked
  `pendingSaltTickets[prefix]` **before** the `prefix ~= "TRP3FW_SPVP"` guard, and `prefix` is
  attacker-chosen — any player can `SendAddonMessage` with any prefix. Epsilon's async salt
  tickets are short, non-secret, mixed-case strings (`hce1i9XrDGkCgWD` in the captured log at
  `thoughts/debug/output.txt.txt:71`), so a player who guessed or observed a live ticket could
  hand us a salt response as though the *server* had answered. Two consequences, both now
  covered by spec: a well-formed forgery caches an **attacker-chosen salt** for the phase, so
  every subsequent SPVP verification there runs against it; a malformed one negative-caches the
  phase for an hour **and** flushes `pendingSPVPInits` for it, NOSALT-ing the legitimate peers
  who were waiting on the real response.

  Fix: the ticket branch now rejects packets from a *different* player. Deliberately not "no
  sender" — which of Epsilon's two server-side sender forms (absent, or our own name) is used
  is not observable from the client, and guessing wrong would silently break all salt loading.
  Rejecting only third-party senders closes the forgery path without depending on that detail;
  an unparseable sender counts as third-party. New spec
  `tests/unit/spvp_prefix_confusion_spec.lua` (5 tests), verified by reverting the fix: the two
  attack tests fail, the three accept/ignore tests pass either way.

  **Note:** `other_addons/EpsilonLib/PhaseAddOnData.lua:262` has the identical
  `_queue[prefix]`-before-anything-else shape (and destructures `sender` without using it), so
  this is an ecosystem-wide idiom rather than a TRP3FW invention. The difference is that
  EpsilonLib is fetching data while TRP3FW is making a **security decision** on the result.

- [x] **`/trp3fwui` was documented everywhere and registered nowhere** (fixed) — the command
  appears in `status.lua` x4, `commands.lua` x3, the README and CLAUDE.md, but the only slash
  globals in the addon were `SLASH_TRP3FW1`, `SLASH_TRP3FWFLAGS1` and `SLASH_TRP3FWTEST1`.
  `settingsFrame` is file-local to `ui/settings.lua`, so the minimap button and the first-run
  complexity prompt were the *only* ways to open the settings window — and `/trp3fw minimap`
  hides the button, which locked the user out of their own settings with the on-screen help
  still telling them to type a command that did nothing.

  Fix: new exported `TRP3FW:ToggleSettingsWindow(action)` in `ui/settings.lua` (owns the frame,
  guards the not-yet-initialized case with a real error rather than silence), `/trp3fwui`
  registered in `commands.lua` with optional `show`/`hide`, plus `/trp3fw ui|config|options`
  aliases. 7 new tests in `tests/unit/commands_spec.lua`.

- [x] **README described a first-launch preset prompt that does not exist** (fixed) — it
  documented the five presets (Relaxed/Balanced/Recommended/Strict/Ghosty, all real, in
  `ui/tabs/Alerts.lua:104`) as a first-launch chooser with **Recommended** as the default. The
  actual first-run prompt is `ShowWelcomeWizard` (`ui/settings.lua:1311`), which asks for a
  UI **complexity level** (Basic/Intermediate/Advanced/Everything) and does not touch firewall
  behaviour at all. The shipped default is `phaseCheckMode = "alert"` / `mapCheckMode = "alert"`
  (`core/init.lua:77`), which is **Balanced** — i.e. the addon ships blocking nothing, the
  opposite of what the README promised. Also removed: an "Unknown Hooded Figure" ghost-profile
  example that appears nowhere in the code (the real default is `TRP3FW_BLANK`), and a
  "50+ concurrent requests instantly" performance claim with no measurement behind it.

- [x] **README/LICENSE licensing conflict** (resolved: GPLv3) — the badge and footer said
  "Personal Use Only" while `LICENSE` is the full GPLv3 text, present since the initial commit
  and therefore already shipped in v1.4 and v1.5. GPLv3 grants redistribution rights that
  "Personal Use Only" revokes, and the grant on already-distributed versions is irrevocable.
  Confirmed with the maintainer that GPLv3 is intended; README now says GPL-3.0 and links the
  file. No change to `LICENSE`.

- [ ] **Stale `v1.6` branch and `v1.6.0` tag exist locally and on gitea** — both were built from
  `f609437`, three commits behind the current dev tip (`be0ec30`). All three missing commits are
  tooling (`scripts/`, `.gitea/`), which `make-release.sh` strips anyway, so the *shipped* tree
  is equivalent — but `make-release.sh` correctly refuses to rebuild an already-tagged version.
  Before releasing: either delete and recreate the tag/branch from the new dev tip, or bump to
  1.6.1. Neither has been pushed to GitHub yet (`origin` has only up to v1.5).

## Deferred to Final Pass

Open items found during the review that were deliberately **not** fixed in place, either because
the fix is a design decision rather than a defect, or because it needs a later section's context.
Each links to the fuller write-up in Findings below. Roughly highest-value first.

- [x] **`Profiles.lua` leaks a button frame set on every refresh** —
  `ui/tabs/Profiles.lua:55`. `RefreshProfileList` `Hide()`s the previous rows and
  `wipe()`s `rowButtons`, then creates three brand-new `CreateButton` frames per
  profile plus the "+ Create new profile" button. WoW frames are never garbage
  collected, so every profile switch, create, delete and rename permanently adds
  `3 * #profiles + 1` orphaned frames, and the refresh is also wired to the tab's
  `refresh` callback — so it fires on every `SwitchToTab("profiles")` too. Bounded
  by how often the user opens the tab rather than by anything in the code. The
  standard fix is a widget pool keyed by row index (reuse + `SetText`), which is
  the same shape `historywindow.lua`'s `graph.bars` pool already uses. Not fixed
  here because it is a rewrite of the render loop rather than a defect in a line,
  and the leak is slow enough that it wants a measurement first.

- [x] **Two `AddRow` calls in `Security.lua` omit their `widgets` list** — FIXED. Both now pass
  `{ uiElements.spvpSaltStatus }` / `{ uiElements.spvpSecureButton }`, matching the
  `AddRow(reposition, height, level, widgets)` signature at `TabManager.lua:553` and every other
  call site.
  Original write-up:
  `ui/tabs/Security.lua:262` (`spvpSaltStatus`) and `:283` (`spvpSecureButton`).
  Every other `AddRow` in the codebase passes one. `Reflow` only Show/Hides the
  frames named in that list, so these two rows are never hidden by it — but both
  widgets ARE in `epsilonControls`, which `SetShown(false)`s them when the Epsilon
  API is absent. The result is that the SPVP card reserves 24px + 28px of blank
  vertical space for two invisible widgets on every non-Epsilon client. Cosmetic
  only (both rows are level 1, so complexity never gates them), and the fix is
  two literal tables — grouped here because it is a convention break worth fixing
  as a set rather than a bug.

- [x] **`hitBar:SetRate` reads `track:GetWidth()` at paint time** —
  `ui/tabs/Dashboard.lua:104`. The fill width is computed from the track's
  measured width, but the track is anchored (LEFT/RIGHT) rather than sized, so on
  the very first `RefreshDashboard` — which `PrebuildAllTabs` triggers before the
  frame has ever been laid out — `GetWidth()` can return 0 and the guard
  (`if w and w > 0`) silently skips the update, leaving the bar empty until the
  next refresh. This is exactly the failure mode `CreateSlider` documents and
  works around by anchoring its fill to the thumb (`TabManager.lua:816-823`)
  instead of computing a width. Same fix applies: anchor the fill's RIGHT edge
  proportionally, or re-run `SetRate` from an `OnSizeChanged` hook. Self-corrects
  within one refresh cycle, so it is a first-paint wart rather than a live bug.

- [x] **`UpdateStatusTab`'s recent-events dedup compares timestamps backwards** —
  `ui/settings.lua:341`. The window test is
  `(display[index].ts - ts) <= suppressWindow`. `notificationHistory` is newest-first
  (`HistoryService:RecordHistory` inserts at index 1), so for a later entry from
  the same player `ts` is always *smaller* and the difference is always positive —
  meaning the test reads "how much older is this one", which is the intended
  direction. But nothing bounds it below, so an entry from hours earlier still
  satisfies `<= 30` only if the gap is under 30s; a gap of, say, -5 (clock jitter
  between uptime samples) also passes. In practice the collapse works; the reason
  to revisit is that `suppressWindow` is a hardcoded `30` that ignores
  `Prefs.suppressionTime`, so the Status tab's "(xN)" grouping disagrees with the
  suppression the user actually configured. Decide whether to read the pref.

- [x] **`scanResponseRequireNonce` disables map checking outright when enabled** — RESOLVED by
  hard-disabling (decision: keep the code, make the setting inert).

  **The transmit gap is worse than the write-up said.** It noted the scan *request* can't carry
  a nonce (TRP3's own `MapScannersManager.launch("playerScan")` broadcast). Also checked the
  *reply* leg, which the write-up floated as "probably the only possible" route: TRP3FW's own
  scan-reply hook (`hooks/trp3.lua:627`) wraps TRP3's `sendP2PMessage` and forwards
  `unpack(args)` **verbatim**, appending nothing. So even two TRP3FW users scanning each other
  cannot produce a verified reply. `verified` is false for 100% of entries, always. Wiring it
  up needs a handshake telling the responder which nonce to echo — real protocol design.

  **What changed:** new `TRP3FW:IsScanNonceVerificationAvailable()` (`core/init.lua`) returns
  false, and all four `strictNonceRequired` read sites (`location/maps.lua` x2,
  `location/who.lua`, plus the cache-validity branch) now gate on it. The pref, the parser's
  4th-token handling and the mismatch-rejection branch are all left intact — inert, not
  deleted — so the protocol work can just flip the accessor. The UI checkbox is permanently
  disabled and relabelled "(unavailable)", `/trp3fw scanreply nonce` no longer toggles the pref
  and explains why, and `/trp3fw scanreply` status reports "unavailable".

  Call sites use `TRP3FW.IsScanNonceVerificationAvailable and TRP3FW:IsScan...()` because
  several specs load `maps.lua`/`who.lua` without `core/init.lua`; this also keeps it safe if
  load order ever shifts.

  New spec `tests/unit/scan_nonce_disabled_spec.lua` (4 tests). Verified by flipping the
  accessor to true: **2 fail** — the nonce-less reply is ignored and the mapScan cache never
  populates, i.e. exactly the fail-shut described. The mismatch test confirms the verification
  code still rejects a wrong nonce, so the feature is genuinely dormant rather than gutted.
  Original write-up:
  `location/maps.lua`. `MapScan` generates a per-scan `nonce` and stores it on the
  `activeScanCallbacks` entry, but **nothing ever transmits it** (verified repo-wide: the
  only other mentions are the setting itself). The scan request is TRP3's own
  `MapScannersManager.launch("playerScan")` broadcast, which knows nothing about a TRP3FW
  nonce, so no responder can echo one back. Every reply therefore lands in the "missing
  nonce" branch and every cached entry has `verified = false`. With the setting **off**
  (the default, `core/init.lua:87`) this is inert. Turn it on — there's a checkbox in
  `ui/tabs/Security.lua:170` and `/trp3fw scanreply nonce` — and every scan reply is
  ignored, every mapScan/broadcast cache entry reads as invalid, and map checking fails
  shut. **Decide: carry the nonce in the scan request (needs TRP3 protocol cooperation, so
  probably only possible for the whisper-reply leg), or remove the setting and the
  half-built verification with it.** Not fixed here because it is a protocol design call,
  not a defect in this file.

- [x] **MRP/XRP adapters hardcode `RP` and `XP` instead of mapping MSP `FC`/`FR`** —
  `adapter_mrp.lua:190-191`, `adapter_xrp.lua:202-203`. Both return `RP = 1` and `XP = 1` with
  the comment "MRP/XRP uses FC differently". They don't — the mapping is well-defined and TRP3
  itself implements both directions: `FC == "1"` means OOC → `RP = 2`, anything else → `RP = 1`
  (`totalRP3/modules/register/msp/register_msp.lua:437-443`, inverse at `:68-72`); `FR == "4"`
  is the "not looking for RP" end of the `XP` scale (`:450`). So a ghosted MRP/XRP profile
  always reports **in-character** even when the source profile is explicitly flagged OOC — the
  one direction where getting it wrong is user-visible and arguably a privacy signal. The MRP
  data confirms `FC` is live and populated (`other_addons/MyRolePlay/Command.lua:173-208` sets
  `FC` to "1".."4" from `/mrp ic`, `/mrp ooc`, etc.). Fix is ~6 lines per adapter; deferred
  only because it changes what goes out on the wire for every MRP/XRP ghost send and deserves
  an in-game confirmation of the `FR`→`XP` end, which is a 3-value scale mapped onto 2.

- [x] **`GetCharacteristics`/`GetAbout`/`GetMisc`/`GetCharacter` are 4 near-identical bodies
  per adapter** — all three adapters. Each is `GetProfileByID` → nil-guard → return a literal
  table; the TRP3 one repeats the same `profile.data.player.X` dig four times, and the MRP/XRP
  ones repeat their field-map literals. That is 12 functions that could be a table-driven
  mapping shared by the two MSP adapters (their maps differ only by the `fields.` indirection).
  Not a defect — flagged because the section-6 bug was *exactly* a copy-paste divergence
  between two branches that should have been one, and this is the same shape waiting to happen.

- [x] **The adapter interface is a comment, not a contract** — `adapter_interface.lua`. The
  file documents 11 required methods in prose and then defines none of them; there is no base
  table to inherit from and nothing verifies an adapter implements the set (contrast
  `core/Service.lua` / `core/Stage.lua`, which are real base classes). `TRP3FW.Adapters.X` is
  just a bare table assigned at the bottom of each adapter file. A missing method surfaces as
  "attempt to call a nil value" at ghost-send time. A `setmetatable` base with erroring
  defaults, or a one-loop conformance check at load, would catch it at startup instead.

- [x] **`ShouldLogProfileCount` throttles on a shared timestamp, not per adapter** —
  `adapter_interface.lua:50`. One `profileLogThrottle.last` is shared by all three adapters, so
  whichever calls `GetProfiles()` first suppresses the others' count logs for 3s. Only affects
  debug output, and only when more than one RP addon is installed. Also falls back to
  `os.time()` (1s resolution) when `GetTime` is absent, and uses raw `GetTime()` rather than
  the frame-cached `TRP3FW:GetCurrentTime()` every other hot path uses.

- [x] **`ClearAdapterCache` is never called in production** — `adapter_factory.lua:63`
  (verified repo-wide: the only caller is `profile_adapters_spec.lua:29`). Its docstring says
  it exists for the "user loads/unloads an RP addon at runtime" case, but nothing wires it to
  `ADDON_LOADED`, so detection is effectively frozen at first use for the session. Given the
  factory caches on the *first* successful detection and TRP3 is the highest priority, a user
  whose TRP3 finishes loading after something already triggered detection keeps the lower-
  priority adapter until `/reload`. Narrow (load order rarely works out that way), but it is
  the reason the cache-priority test in the spec exists at all.

- [x] **`GetCurrentTime`'s frame cache saves nothing** — RESOLVED by dropping the machinery
  (decision: option (a), don't build a real frame cache).

  `GetCurrentTime` is now a one-line return of `GetTimePreciseSec()`/`GetTime()`;
  `cachedTime`/`cachedTimeFrame` are deleted from `core/init.lua`.

  **A second defect the write-up didn't mention:** the cache key was **milliseconds, not
  frames**. At 60fps a frame is ~16.7ms, so `math.floor(now * 1000)` changed ~16 times per
  frame. Even had the syscall been moved below the check, this would have missed ~16x per
  frame — it was never a frame cache, just a millisecond cache with a misleading name.

  Rejected building a real one: it needs a permanent per-frame `OnUpdate` handler whose cost is
  **unconditional**, to buy a saving **nobody has measured**, and it would make every read
  within a frame identical (any in-frame duration measurement reads 0). Wrong trade for a
  function the headless harness stubs out entirely. If clock reads ever show up under
  `/trp3fw profile on`, build it then against a real number.

  **Claims corrected:** CLAUDE.md's "Frame-cached GetTime()" and "(frame-cached)" guidance now
  describe the real behaviour and point at the context `now` snapshot for per-request reads;
  the **"99% reduction in syscalls"** bullet rested entirely on this cache and is **withdrawn
  rather than restated**, since no measurement supports a replacement figure. Stale
  "frame-cached" comments fixed in `core/Context.lua`, `tests/harness.lua` (which now warns the
  stub means this function has no headless coverage) and `chomp_pipeline_timer_spec.lua` —
  that spec's shared-`queuedAt` assertion holds because the *mock clock* is frozen between
  calls, not because of the frame cache, so its test is unaffected.
  Original write-up: `core/utils.lua:145`. Calls
  `GetTimePreciseSec()` unconditionally *before* checking the cache, so the syscall happens on
  every call and the cache is pure added cost. `cachedTime` / `cachedTimeFrame` are read nowhere
  else (verified). Contradicts both the in-file comment ("~95 syscalls per request") and the
  CLAUDE.md performance guidance built on it. **Decide: build a real frame cache (OnUpdate-driven
  counter on `TRP3FW.frame`), or drop the machinery and correct the claim.** Note the headless
  harness stubs `GetCurrentTime`, so the suite will not catch a regression here — verify in game.

- [x] **`TRP3FW.Context` is dead code** — `core/Context.lua`. Only instantiated by tests;
  production contexts are plain tables from `CreateDecisionContext`. Adopt it in
  `CreateDecisionContext`, or delete it plus its .toc entry and its tests.

- [x] **Confirm `LocationStage` always returns `handled = true`** — done in section 3. All
  three return paths set it, so `Pipeline:Run`'s fall-through result is unreachable; pinned by
  two tests in `tests/unit/location_stage_timer_spec.lua`. The async path still returns no
  `allowed` field, so `CheckLocationAndNotify` returns `nil` for essentially every real
  request — that value reaches only `hooks/trp3.lua:371`, whose return the Chomp caller
  ignores, so it is inert. Left as-is.

- [x] **`GetAvailablePrivilegedTokens` ignores reserved tokens** — `core/utils.lua:327`. Returns
  the raw bucket though its comment claims it mirrors `RunPrivilegedSafe`. NORMAL-priority
  categories can't spend reserved tokens, so `location/phase.lua:356` sizes batches ~2 tokens
  optimistically and the tail of a batch can take `rate_limit` rejections. Proper fix passes the
  caller's priority in. Re-check when section 4 covers `phase.lua`.

- [x] **`TRP3FW.Prefs = TRP3FW.defaultSettings` early-access alias** — `core/init.lua:243`. If
  `MigrateSettings` ever throws, every settings write that session mutates `defaultSettings` and
  new profiles are born polluted. A copy is safer; nested-table semantics need thought.

- [x] **`profiler.stop` is O(n) per sample** — `core/init.lua:394`. `table.remove(stats.calls, 1)`
  shifts 1000 elements per measurement once the buffer fills, inside the profiler itself. Ring
  buffer would be O(1). Only active while profiling is on.

- [x] **`TRP3FW_DB.global.version` is never updated after creation** — `core/init.lua:580`.
  Records the install-time version forever. Nothing reads it today; any future migration keyed
  off it would read a stale value.

- [x] **Cache TTL boundary is inconsistent** — `core/cache_interface.lua`. `Get` treats
  `age >= ttl` as expired; `Prune` / `PruneIncremental` use `> ttl`. An entry at exactly
  `age == ttl` is expired on read but retained by a prune pass. Left alone because several TTL
  specs pin the current boundaries — changing it means re-checking those.

- [x] **`features/encryption/` is missing from this checklist entirely** — DONE. Added as
  section 4b and reviewed; see "Section 4b findings" below. The carried-over redaction gap was
  confirmed and turned out wider than described (salt previews were also going **straight to
  chat** via `/trp3fw spvpdebug`, not just to the debug log). The section also turned up a HIGH
  — auto-init could silently rotate a live phase salt — plus two unbounded network-fed
  collections and a cross-phase queue drain.

  Original write-up: `spvp.lua`, `spvp_auto_init.lua` and `spvp_handlers.lua` are in the .toc
  and shipping, but no section covers them. Add a section (they fit between 4 and 5). Related
  finding from section 2: SecurityService's SPVP redaction patterns assume **hex** salts
  (`salt: %x+`), but per `[[spvp-salt-contract]]` Epsilon returns 15-char **non-hex** tickets —
  so those are not redacted. `spvp_auto_init.lua:82` also logs `salt:sub(1,16)` and a raw phase
  ID in a format no redaction pattern matches at all.

- [x] **`CacheService:InitializeInteractionTracking` snapshots its refresh threshold at
  init** — `CacheService.lua:688-690`. `interactionCacheDuration` / `interactionRefreshRate`
  are read once into a closure, so changing either in the settings UI has no effect until
  `/reload`. Cheap to fix (read inside the handler); left alone because it's a hot path and
  the perf tradeoff deserves a measurement, not a guess.

- [x] **Interaction-cache read key ≠ write key on mouseover** — `CacheService.lua:718` reads
  `CI:Get("interaction", unitName)` with the **raw** name but writes with
  `CleanPlayerName(unitName)`. Deliberate ("check cache BEFORE expensive CleanPlayerName"),
  and harmless for the names Epsilon actually produces via `UnitName` (no realm suffix). But
  `CleanPlayerName` truncates at the first hyphen, so for a hyphenated name the read always
  misses and every mouseover redundantly re-Sets. Same defect *class* as 30ee55c. Fix is two
  lines (CleanPlayerName is itself cached twice over), so this is mostly a decision about
  whether the stated optimization is real.

- [x] **`currentZoneName` alternates between raw and sanitized forms** —
  `CacheService.lua:476` sets it raw from `GetRealZoneText()`; the prepopulate timer at
  `CacheService.lua:647` overwrites it with `SanitizeZoneName`'s output. It is used as a
  `whoZone` **cache key** and compared against `entry.zone` in
  `PruneInteractionZoneMismatch`, so for any zone name containing a character the sanitizer
  strips, the two forms are different keys — the prune would drop every interaction entry
  stored under the other form. Narrow (needs an unusual zone name, which Epsilon phase owners
  can create), but it's a correctness hole in a cache key. Pick one form and stick to it.

- [x] **`BurstStage`'s queue is the one unbounded collection in the addon** —
  `BurstStage.lua:26`. `queuedRequests` has no cap, and each entry retains `originalArgs`
  (a full profile payload). Bounded in practice by the check window — normally ~2s via
  cascading's deadline — but a hung check widens that to 30s, and CLAUDE.md states every
  cache has a `maxSize` limit specifically to prevent DoS. A cap plus a drop counter would
  match the rest of the codebase. Also note nothing calls `TrackAddonRequest` for a queued
  request, so burst siblings are invisible to the addon-request stats.

- [x] **Alert-only mode never burst-queues** — `AlertFastPathStage` sits *before* `BurstStage`
  in the pipeline, and only `LocationStage` ever creates a `pendingLocationChecks` entry. So
  in alert-only mode a burst of N requests from one player starts N independent
  `CheckLocationCascading` runs instead of one plus N-1 queued. Plausibly deliberate (nothing
  is being gated, so nothing needs to wait), but it is the configuration most exposed to
  incoming spam, and it is the opposite of what the stage ordering suggests. Decide.

- [x] **`pendingSends` is write-only state** — `LocationStage.lua:53` populates a rich entry
  (playerName, addon, isWhisper, isFirstTime, suppressedCount, originalFunc, originalArgs) and
  **nothing ever reads the payload** (verified repo-wide). Only its *existence* is tested, and
  now only by the housekeeping timer. Either it is a vestige of a pre-pipeline design and the
  table should shrink to a set, or something was meant to consume it and doesn't.

- [x] **`CacheStage` re-reads the clock instead of using the context snapshot** — FIXED. Now uses
  `context.now`. Note this surfaced a test-fixture gap: `cache_stage_ttl_spec.lua`'s hand-rolled
  context omitted `now` entirely (production's `CreateDecisionContext` always sets it), so the
  fixture now carries the clock snapshot the same way production does.
  Original write-up:
  `CacheStage.lua:30` calls `TRP3FW:GetCurrentTime()` for its TTL math while `context.now`
  is right there. Every other stage uses the snapshot; the whole point of `CreateDecisionContext`
  is that one request sees one clock. Difference is microseconds today, so it is a convention
  break rather than a live bug — but it is the same shape as the class of bug section 2 kept
  finding. Trivial to change; grouped here only because it touches a hot path.

- [ ] **`hasTRP3ExchangeHooks` needs an in-game confirmation** — `hooks/trp3.lua`. The flag is
  now set on successful `InstallSendObjectHook` (section 7), which **enables code paths that
  have never once run in production**: TRP3/Chomp burst siblings now actually ghost-send rather
  than being dropped, and phase-169 TRP3 ghosting now ghosts instead of hard-blocking. That is
  the intended behaviour and the headless suite covers the branch selection, but the payload
  those paths emit has no live mileage on it. **Verify in game before shipping:** trigger a
  burst from one player while ghosting, and confirm the siblings arrive as ghost profiles
  rather than real ones. This is the one section-7 change that alters what goes out on the
  wire.

- [x] **`ClearAllGhostFlags` doesn't clear `mspAllowDebounce`/`mspTargetWindow`** —
  `features/ghostmode_trp3.lua:194` vs `features/decision.lua:133`/`:142`. The "emergency
  cleanup" resets the ghost flag and its timer but leaves both per-target throttle tables
  populated, so a target throttled at the moment of the reset stays throttled for up to 10s
  afterwards. Both tables are pruned by `CacheService`, so this is a narrow
  emergency-path-only wart rather than a leak; flagged because "clear all" implies otherwise.

- [ ] **`StableHash` collapses `[1]` and `["1"]` to one slot** —
  `features/profileswitch.lua:133`. Keys are stringified for sorting then read back with
  `value[sk] ~= nil and value[sk] or value[tonumber(sk)]`, so a table holding both a numeric
  and a string form of the same key hashes them identically. Unreachable with TRP3's
  string-keyed MSP profile tables, and the hash is only a secondary guard behind a full
  `DeepCompare`, so this is a correctness note rather than a live bug.

- [x] **Docs reconciliation** (also in Notes): `CLAUDE.md` documents a `PhaseInStage` that does
  not exist (the real one is `SPVPStage.lua`), and omits `features/ghostmode_trp3.lua` from its
  file-structure listing. Section 3 adds two more: CLAUDE.md's pipeline overview lists
  `CacheStage` as stage 3 "Cached result? → ALLOW" with no mention of its different-phase
  fast-*fail* branch, and describes the pipeline as 7 stages without `SPVPStage`. Section 5
  adds three more: CLAUDE.md's file-structure listing omits `hooks/fontsize.lua`,
  `hooks/icon.lua` and `hooks/gradient.lua` (all three are in the .toc and shipping), the
  "Interaction (10min)" cache list numbers 10 entries under a "9 Layers" heading, and the
  stated "~3,400 lines / 60+ files" is well short of this checklist's own count (~21,947
  lines, 62 files). Section 7 adds one: `features/notifications.lua` is described nowhere,
  and it is a deprecated delegation shim — worth a line saying so, since its function names
  (`ShowChatNotification`, `RecordHistory`) are the ones a reader greps for first and the
  real implementations live in `features/services/`.

- [x] **`HandlePhaseResult` has no idempotence guard** — FIXED, and **the finding understated
  it**. The guard is now in place (`location/cascading.lua:258`), mirroring `HandleMapResult`.

  **Correction to the original assessment.** This was written up as "now latent" — a
  convention asymmetry worth one line. It is not latent. Verified by disabling the guard and
  running the new spec: a contradictory duplicate arriving **while the cascade is still
  in flight** overwrites `results.phaseCheck` to `true`, and `EvaluateResults`' `phaseCheck ==
  true` override (`:165`) then clears the alerts and **flips a pending block into an ALLOW**.
  That is a fail-*open* — the one direction this addon is not supposed to fail in.

  The reason it read as latent is that `results.resolved` already absorbs a duplicate arriving
  *after* the cascade completes, which is the common case. The exposed window is the one where
  phase reports twice before the map leg returns.

  New spec `tests/unit/cascading_idempotence_spec.lua` (3 tests); the flip-to-allow test fails
  against the unfixed code. The map-dispatch test passes either way — `RunMapCheck`'s own
  `mapCheckStarted` flag is a second line of defence — and says so in a comment rather than
  pretending to pin the guard.

  Original write-up: `location/cascading.lua:195` vs `:258`. `HandleMapResult` opens with
  `if results.mapCheck ~= nil then return end`; `HandlePhaseResult` has no equivalent and
  re-runs its whole body (including `RunMapCheck` dispatch) on a repeat delivery. That
  asymmetry is why the duplicate phase-check callback below went unnoticed for so long — the
  phase side quietly absorbed it. Now latent, but the guard costs one line and would make a
  future regression loud.

- [x] **`results.theirMapFromWho` is never written** — FIXED by deletion. Re-verified repo-wide
  before removing: exactly two mentions, the `nil` init and the read, with no assignment
  anywhere. `HandleMapResult` already folds the WHO-supplied map ID into `theirMapID`, so no
  data is lost. Both lines removed.
  Original write-up: `location/cascading.lua:436` (init)
  and `:97` (read, as `results.theirMapFromWho or results.theirMapID`). Nothing anywhere
  assigns it, so the notification's map detail always falls through to `theirMapID`. The
  WHO-supplied map ID isn't actually lost — `HandleMapResult` folds it into `theirMapID` —
  so this is a vestigial field, not missing data. Delete it, or wire it up if the intent
  was to distinguish "map ID we got from WHO" from "map ID we got from targeting" in the
  notification.

- [x] **`mspConversionCache` has no TTL, no invalidation and no cap** — FIXED via option (a), as
  the item itself recommended. The already-stored `timestamp` is now read against a new
  `mspConversionCacheDuration` pref (default 300s, `core/init.lua`), and a stale entry is
  dropped and reconverted. A 50-entry cap was added at the write site — a flat cap with a wipe
  rather than an LRU, since this is a plain table (not a `CacheInterface` cache) keyed by the
  user's *own* profile IDs, so there is nothing meaningful to rank. An entry with no timestamp
  is treated as stale rather than trusted.

  New spec `tests/unit/msp_conversion_cache_spec.lua` (7 tests); **5 fail against the unfixed
  code**, including the user-visible one: a ghost-profile edit now reaches the wire once the
  TTL lapses instead of never. Also added `wipe`/`table.wipe` to `tests/mock_wow.lua` — real
  WoW globals that production already used in three files, absent from the mock only because
  no spec had reached one of those lines yet.
  Original write-up:
  `hooks/msp_exchange.lua:275` / `:438`. Written with a `timestamp` that is **never read**,
  pruned by nothing (verified repo-wide: `core/init.lua:552` declares it and those two lines
  are the only other mentions), and invalidated by no profile-edit signal. It caches the
  TRP3→MSP conversion of the **ghost** profile, so editing that profile mid-session keeps
  every ghost send transmitting the pre-edit version until `/reload`. It is also the one
  cache in the addon with no `maxSize`, against CLAUDE.md's stated rule — though it is keyed
  by profile ID (your own profiles), so growth is bounded in practice, unlike a
  remote-keyed cache. **Decide: honour the timestamp with a TTL, or hook a profile-changed
  event to invalidate.** ~~The right signal lives in section 7
  (`features/profileswitch.lua`)~~ — **section 7 checked: it does not.** `profileswitch.lua`
  registers only `ZONE_CHANGED` and `PHASE_CHANGED` (`:989-990`) and there is no
  profile-edited event anywhere in the addon; `EventService` exposes none either. So there is
  no existing signal to hook, and the honest options narrow to (a) honour the already-stored
  `timestamp` with a TTL, which needs no new plumbing, or (b) add a TRP3
  `Events.REGISTER_DATA_UPDATED` listener. **(a) is the cheap correct fix** — recommend taking
  it rather than carrying this item further.

## Findings

### Final Pass (2026-07-25) — independent sweep over the whole codebase

Run after every section above was closed, deliberately *not* re-reading the earlier findings
first, so the sweep would not inherit their assumptions. Baseline before starting: 577 headless
tests passing, clean `luac -p` across all 68 loaded files, `.toc` consistent with disk.

Most defect classes came back clean, and those negative results are worth recording so the next
pass can skip them: no remove-during-iteration bugs (all 21 `table.remove` sites either iterate
in reverse or `return` immediately); no accidental globals (the three candidates are all
forward-declared locals); no unguarded division; no cache-name typos (all 13 `CacheInterface`
names resolve to a registration); no clock-source mixing; cache keys consistently
`CleanPlayerName`-normalized; every stage returns a well-formed `handled` contract; and no
command documented in `/trp3fw help` is unhandled.

Two real defects were found, both on the **network attack surface** rather than in the
logic the earlier sections concentrated on.

#### **CRITICAL: SPVP accepted unvalidated peer public keys — zero-cost handshake forgery** (fixed)

`features/encryption/spvp.lua`, both receive paths (`HandleSPVPInit`, `HandleSPVPReply`).

The wire pattern for a public key is `(%d+)`, and the parsed value went straight into
`DeriveSharedKey` → `ModPow(B, a, p)`. Nothing checked which group element `B` was. Sending
`B = 0`, `B = 1` or `B = p` (all plain digit strings, all matched by the pattern) makes
`K = B^a mod p` a **constant independent of the honest party's secret exponent** — 0, 1 and 0
respectively. `B = p-1` gives `K ∈ {1, p-1}`, decided only by the parity of `a`: one guess, 50%,
retryable.

The attacker then computes `HashKey(K)` offline and sends a verifier that matches. Confirmed
against the real module (not a reimplementation): an attacker using an arbitrary made-up private
key produces exactly the verifier the honest side expects, for `B ∈ {0, 1, p, p-1}`.

This defeated the only thing SPVP proves. No discrete log, no knowledge of the phase salt, no
phase membership — any player able to whisper an addon message could be cached as
`spvpVerified`. Cost **zero**, against ~2^12.7 for the group and ~2^32 for the verifier, making
it by far the cheapest attack on the protocol — the same "cheapest path bypasses everything"
shape as the 32-bit verifier fixed in `0ac5af3`, which this sat underneath and silently
outclassed.

Fix: `IsValidPublicKey` requires `2 <= B <= p-2` (excluding 0, 1, p-1, p and out-of-range in one
range test) and then confirms membership in the order-q subgroup via `B^q mod p == 1` — the same
standard `GetGenerator` already applied to its *own* generator, now applied to values arriving
from the network, where it matters more. Both receive paths gate on it.

Two deliberate choices in the fix:
- On the INIT path the check runs **before** `GetGenerator`/`GeneratePrivateKey`, so a hostile
  packet costs one `ModPow` rather than a generator derivation plus a keypair.
- On the REPLY path the session has already been consumed, so the guard must settle the callback
  or the caller hangs until timeout. It reports failure and records the attempt, but
  deliberately skips the salt-cache invalidation + forced refresh the verifier-mismatch branch
  does: a malformed public key says nothing about our salt being stale, and letting an attacker
  trigger a forced salt refetch per packet would be a cheap way to hammer the Epsilon salt API.

**No protocol version bump needed** — measured over 26,000 honest public keys (across six
generators and 2,000 real `GetGenerator` salts) the guard rejects **zero**, because
`GetGenerator` already guarantees the generator is in the order-q subgroup and every honest key
is `g^a` within it.

New spec `tests/unit/spvp_pubkey_validation_spec.lua` (11 tests), including the forgery itself
expressed as a test so the *reason* for the guard survives. Verified to fail (3 failures)
against the pre-fix behaviour.

#### **HIGH: the Chomp send hook was unprotected — a pipeline error broke TRP3's send** (fixed)

`hooks/trp3.lua:410`. `InstallChompHook` **replaces** `AddOn_Chomp.SmartAddonMessage` globally,
so the whole TRP3FW decision pipeline — 7 stages plus the location checks and SPVP beneath them
— executes inside TRP3's own send call for every profile message, with no `pcall` anywhere in
the chain.

Any Lua error in that pipeline propagated out of Chomp into TRP3: the message was never sent,
Chomp's queue was left mid-send, and the error surfaced as a *TRP3* bug against a stack that
never mentions TRP3FW. The codebase already knew this failure mode in two narrower spots — the
queue-drain path (`trp3_chomp_pipeline.lua:142`, whose comment describes exactly this latching
until `/reload`) and `sendObject` (`trp3.lua:588`) — but not at the outermost entry point, which
is the one that runs on every send.

Fixed by wrapping the pipeline call in `pcall` and **failing closed**: on error, report it and
**drop the send**.

**The first version of this fix failed OPEN (called `originalSend` on error) and was wrong.**
Recording the error because the reasoning is the trap, not the code. It weighed "profile
silently doesn't arrive" against "one unfiltered send" as comparable costs. They are not: this
is a privacy tool, so a missing profile is a visible, recoverable annoyance, while an unfiltered
send is an **irreversible disclosure to precisely the player the user configured the addon to
hide from**, which the user never learns about.

The decisive detail: the code most likely to be on the stack when this pipeline throws is the
code deciding *not* to transmit — `ShouldBlockForStartPhase`, `EnableGhostForNextSend`, the
location gating (`trp3_chomp_pipeline.lua:160-235`). A recover-by-sending handler therefore
converts a crash *in the blocking logic* into a full send of the real profile. That is a leak
path the **unguarded code never had** — there, the error simply killed the send. A fix for a
robustness bug had introduced a security regression.

It also misread the local convention while citing it as support. Both sites quoted as precedent
do the opposite: the `sendObject` hook **aborts** the send when the original throws
(`trp3.lua:620`) and **blocks** it when ghost data is unavailable (`:611`); the phase-in replay
`pcall` (`trp3_chomp_pipeline.lua:142`) exists only to restore a guard flag and does not
re-send. The addon's rule is consistent — when something goes wrong, do not transmit — and
failing closed both matches it and preserves the original security behaviour, adding containment
only.

New spec `tests/unit/chomp_hook_failclosed_spec.lua` (7 tests) exercising the installed wrapper
end to end: the error must not escape into TRP3, **nothing may reach the wire** (the security
assertion, also checked across repeated failures so no leak slips through on a later call), and
the failure must be reported with text saying the send was dropped, so a silent non-delivery is
explainable from the log. Verified to fail against both the unguarded version and the fail-open
version — the leak assertions catch the latter specifically.

**Generalisable rule:** in this addon, an error on a send path means *drop*, never *pass
through*. When adding a `pcall` around anything that gates transmission, the recovery branch
must not be able to transmit.

#### **HIGH: an unparseable recipient name sent ungated on both send paths** (fixed)

Found by a follow-up sweep dedicated to data leaks (prompted by the fail-open mistake above —
worth noting that the *category* of error was the thing that pointed here).

Two sites treated "`CleanPlayerName` returned nil" as permission to transmit:

- `hooks/trp3.lua:304` — `return originalFunc(...)`, skipping the entire Chomp pipeline.
- `hooks/trp3_scan_pipeline.lua:307` — literally commented `-- Invalid name, allow`.

In both cases a send addressed to a **specific named recipient** went out with no whitelist, no
cache check, no location check and no ghosting. The scan-reply one is the more sensitive: a
`C_SCAN` reply carries the player's exact map **coordinates**
(`PlayerMapScanner.lua:161` sends `x, y`), so an ungated reply discloses physical position to
someone who may be explicitly blocked — arguably worse than leaking profile text.

**Severity is bounded by reachability, and reachability is low.** Measured what actually makes
`CleanPlayerName` return nil: names under 2 chars, over 50 chars, containing control
characters, or `SecurityService` being unavailable. Normal names are unaffected — including
apostrophes (`Ahn'Qiraj`), realm-qualified (`Arthas-Silvermoon`), accented (`José`, `Müller`)
and Cyrillic (`Ыгорь`), all of which parse correctly. The target is a **server-supplied**
character name (TRP3 derives it from `CHAT_MSG_ADDON`, `communication_protocol_broadcast.lua:352`),
capped by WoW at 12 chars plus realm, so an attacker cannot craft one into the nil branch. The
service-unavailable route is also unreachable: services initialise at `PLAYER_LOGIN`
(`TRP3FW.lua:41`) and hooks install a full second later (`:56`).

So this is a **"should never happen" branch** — which is exactly why it had to change. An
unreachable branch that silently transmits is one whose failure nobody would ever notice. If we
cannot identify the recipient, we cannot conclude they are allowed.

**One distinction the fix preserves:** at the Chomp site the nil had *two* causes, needing
opposite handling. A nil **target** is a broadcast/channel send with no specific recipient —
normal protocol traffic, no per-recipient decision to make, must still pass through. Only a
non-nil target that fails to *parse* is blocked. Collapsing these would have broken ordinary
TRP3 traffic; the spec pins both directions.

New spec `tests/unit/unparseable_target_failclosed_spec.lua` (5 tests). Verified to fail on both
sites against the pre-fix code, while the broadcast-passthrough test stayed green.

#### Leak surfaces checked and found sound

Recording the negatives so the next pass need not redo them:

- **MSP ghost payload** (`msp_exchange.lua:19`) — falls back to `GetBlankMSPFields` when the
  profile fetch fails, and that blank set contains only already-public game data (name, GUID,
  class, race, faction), never RP fields.
- **Ghost flag lifecycle** (`ghostmode_trp3.lua`) — set and expiry both use `GetTime()`
  consistently, so no cross-clock mismatch; the existing `ghost_flag_window_spec.lua` already
  pins the window, timer cancellation and the fail-closed drop.
- **Burst queue block path** (`decision.lua:315-369`) — replays a queued request only when
  `EnableGhostForNextSend` *succeeded*; a ghost failure drops the request rather than sending
  real data. Explicitly documented as fail-closed at `:342`.
- **Debug output** — logs metadata and player names only; no message bodies or profile content
  reach the debug window or chat.
- **RPMapScan scan hook** (`trp3.lua:706`) — routes through the same pipeline, so it inherits
  the fix. Its two pass-through branches (map mismatch, no position) disclose nothing, because
  in both cases there are no coordinates to send.

#### Also corrected: four settings that are declared but read nowhere

`ignoreMapScan`, `useLibWhoBackend`, `whoQueuePolicy`, `cacheUserWhoResults` exist only in
`defaultSettings` — verified repo-wide that nothing reads them, so changing any of them has no
effect. The last three describe a configurable WHO backend that was never built (`WhoService`
has a single code path and fixed queue ordering).

Not deleted — that is a product call, and dropping them would silently discard existing
SavedVariables entries. Marked `INERT` in `core/init.lua` with the reason, and
`SETTINGS_REFERENCE.md` corrected, since it documented `ignoreMapScan` as a working setting
("legacy") with no indication it does nothing. A setting the user can toggle to no effect is a
support trap.

**Final pass pattern:** both real bugs were on the boundary where **external input crosses into
trusted computation** — an addon message body in one case, an error boundary in the other. The
earlier sections were organised by *module*, which is why these survived: neither is a defect in
a line of logic, both are a missing check at a seam. Worth scanning future work by
*trust boundary* as well as by file.

**Second pattern, from getting the Chomp fix wrong the first time:** when hardening a privacy
tool, "safe" is not a single axis. A change can improve *robustness* (no crash, no lost message)
while regressing *confidentiality*, and the failure directions are not symmetric — unavailability
is visible and recoverable, disclosure is neither. For any error path on a send route, state
which of the two is being preserved before writing the handler, and check the answer against what
the surrounding code already does rather than assuming.

Headless suite grew 577 → 590 tests.

### Section 4b — `features/encryption/` (SPVP)

#### **HIGH: auto-init could silently rotate a live phase salt** (fixed)

`spvp_auto_init.lua`. `GetPhaseSalt` is **three-valued** — `nil` = still loading (Epsilon
issued an async ticket), `""` = confirmed no salt, string = the salt. The guard was:

```lua
local existingSalt = TRP3FW:GetPhaseSalt(phaseID, false)
if existingSalt and existingSalt ~= "" then return end
```

`nil` fails the first clause, so **loading fell through to generation**. Auto-init runs 3s
after `PHASE_CHANGED` — precisely when the cache is cold and a ticket is outstanding — so it
would `SetPhaseAddonData` over a salt that was merely still being fetched.

Consequence: the phase secret rotates with no user action. Every peer's cached `spvpVerified`
entry for that phase becomes invalid, and in-flight handshakes fail with a verifier mismatch —
which `HandleSPVPReply` treats as a **hostile peer** and blocks for `spvpBlockDuration`. A
phase owner walking into their own phase could mass-block legitimate visitors.

Fixed by bailing on `nil` and retrying on the next phase-change/login pass. The manual
`SecureCurrentPhase` path is *not* affected — it is user-initiated and the UI already confirms
rotation via `StaticPopup` when a salt exists.

#### Two unbounded network-fed collections (fixed)

Both are written directly from the `CHAT_MSG_ADDON` handler — any player can whisper us an
SPVP packet — and neither had a cap or an expiry. Replay detection does not bound either:
it rejects a *repeated* `sessionID`, and the sender chooses their own, so a fresh one per
packet queues without limit.

- **`pendingSPVPInits`** — queued while a salt ticket resolves, drained only when a salt
  response arrives. If it never arrives, entries live until `/reload`. Now capped (50) with a
  30s TTL, dropping oldest first.
- **`spvpIncomingSessions`** — Bob's half-open handshake state, removed only by a matching
  `CONFIRM`. A peer that never confirms leaves one entry *per INIT*, each pinning a derived
  shared key. It already carried a `timestamp` that nothing read. Now capped (100) with a
  TTL of `SPVP_TIMEOUT_SECONDS * 4`, evicting oldest first.

`spvpFailedAttempts` was checked and left alone: it is keyed by player name, cleared lazily on
re-check, and fed by our *own* outbound failures, so it is bounded by distinct players
encountered rather than by packets received.

#### `pendingSPVPInits` drained across phase boundaries (fixed)

Entries recorded only `{sender, message}`, and **both** drain paths in `HandleSaltResponse`
walked the whole queue for whichever ticket resolved, then wiped it. Since `HandleSPVPInit`
re-reads `GetCurrentPhaseID()` on replay, an INIT queued in phase A that drained after a move
to phase B was verified against **phase B's salt**. Entries now carry `phaseID` and each drain
takes only its own phase's; the survivors are reassigned *before* replaying, since
`HandleSPVPInit` can re-enter the queue.

#### Salt material reached chat and the debug log (fixed)

The carried-over section-2 finding, confirmed and **wider than described**:

- `spvp_auto_init.lua:82` logged `salt:sub(1, 16)` — 16 chars of a 64-char secret — in a format
  **no** redaction pattern matched (they key off a literal `salt: ` prefix). Now logs a length.
- `commands.lua:938` / `:946` printed 8-char salt previews **straight to chat** via
  `/trp3fw spvpdebug`, which is worse: that output is exactly what a user pastes for support.
  Both now print a fingerprint (new `TRP3FW:GetSaltFingerprint`, FNV-1a → 8 hex chars), which
  still answers the "do the API and cached salts match?" question the readout exists for.
- The redaction patterns themselves required **hex** (`%x+`); per `[[spvp-salt-contract]]`
  Epsilon tickets are 15-char non-hex, so those sailed through. Widened to `%w+` and added a
  `salt for phase N: ...` pattern. Note these are now defence-in-depth — the real fix is that
  production no longer logs salt material at all.

#### `GetCurrentPhaseID` served phase IDs up to 5s stale (fixed)

Two caching implementations shared `TRP3FW.cachedPhaseID` but tracked freshness in different
fields, with different TTLs, on **different clocks** (`time()` wall-clock vs `GetCurrentTime()`
monotonic uptime — not even the same epoch):

| | TTL | timestamp field | clock |
|---|---|---|---|
| `GetCachedPhaseID` (core/utils.lua) | 1s | `cachedPhaseTimestamp` | `time()` |
| `GetCurrentPhaseID` (spvp.lua) | 5s | `cachedPhaseIDTime` | `GetCurrentTime()` |

Nearly every phase-sensitive caller uses `GetCurrentPhaseID` (SPVPStage, cascading, decision,
the salt paths, the UI), so all of them could act on a phase ID 5s out of date against a stated
1s contract. Now delegates to `GetCachedPhaseID`.

**Correction to my own first reading:** I initially wrote this up as also corrupting
`GetCachedPhaseID` (and therefore ghost mode's start-phase check). Direct execution disproved
that — the old `GetCurrentPhaseID` never wrote `cachedPhaseTimestamp`, so `GetCachedPhaseID`
always saw a huge apparent age and refetched. It failed *safe*. The exposure was confined to
`GetCurrentPhaseID`'s own callers. My first version of the test passed against both old and new
code for the same reason; it was rewritten to assert the staleness window and now fails against
the original.

#### Documented the threat model (no code change)

`spvp.lua` is named "Secure Phase Verification Protocol" and the UI offers "Secure this phase",
but nothing stated the security ceiling. Measured it: `DH_PRIME` is 90000049 (~2^26.4), and a
private exponent was recovered by brute force in **0.16s of plain interpreted Lua on one core**
(full sweep ~2s). The shared secret is then compressed to 32 bits by FNV-1a, a non-cryptographic
hash. The whole scheme also rests on the phase salt staying secret, which on Epsilon means
trusting every phase owner and officer.

These are inherent to Lua 5.1 (doubles give exact integers only to 2^53, so a modmul in a
meaningful group overflows) — a deliberate trade, not a defect. But a reader should not have to
infer the limit from a constant, so the file header now states it plainly: SPVP raises the cost
of *casual* phase spoofing and must not be treated as a security boundary.

#### Minor

- Removed a duplicated debug line in `HandleSPVPReply` (`SPVP SUCCESS` / `SPVP verified` for
  the same event).
- `StartSPVPHandshakeWithRetry` assigns `local session` in its timeout timer and never reads
  it — harmless leftover, left alone.
- Added `wipe`/`table.wipe` and `date` to `tests/mock_wow.lua`: all real WoW globals that
  production already used, absent only because no spec had reached those lines.



### `commands.lua` — **HIGH: three command families crashed on their first line** (fixed)

`SlashCmdList.TRP3FW` is one ~1,380-line function. Three of its branches build a
whitespace-split argument list, each as a **block-scoped** `local args = {}`:
`cache` (:433), `clearcache` (:479), `dumpcache` (:978). Three *other* branches —
`batch` (:1220), `priority` (:1287) and `refund` (:1328) — read `args[1]` / `args[2]`
without declaring one. A `local` is only visible to the end of the block that declares
it, so those reads fell through to the global environment, where nothing ever assigns
`args` (verified repo-wide). `attempt to index global 'args' (a nil value)` — a hard
error in Lua 5.1, confirmed by direct execution.

So **every subcommand of `/trp3fw batch`, `/trp3fw priority` and `/trp3fw refund` was
dead**, including the bare `status` forms, which are the ones a user reaches for first.
That is the entire command-line surface for phase-check batching (the four tunables the
section-8 slider bug was *also* about), the privileged-token priority system, and the
token-refund security toggle. The settings themselves are real and read by
`location/phase.lua` and `core/utils.lua`; only the way to see or change them from chat
was broken.

The same branch carried the same bug in a second costume: `batch interdelay`'s no-value
path called `self:Info(...)` three times. `SlashCmdList` handlers are plain functions,
not methods — `self` is nil there too, so that path was a crash even if `args` had
existed.

**Fix:** `args` is built once at the top of the handler, next to `cmd`/`rest`, and the
three redundant block-locals are removed so the two spellings cannot drift again. The
`self:` calls became `TRP3FW:`. Also made `msg` nil-safe (`(msg or ""):match`) — WoW can
hand a slash handler nil, and `msg:match` on nil is the same class of hard error.

**Worth noting why this survived:** the failure is total and immediate, not subtle. These
commands were almost certainly never run after whatever refactor moved the `args`
construction into the `cache` branch — the in-game testing regime that caught the
section-5/7 bugs exercises the settings UI, and every one of these settings is also
reachable there.

### `commands.lua` — **`/trp3fw reset` reset nothing at all** (fixed)

```lua
TRP3FW.Prefs = {}
TRP3FW:InitializeSettings()
```

`TRP3FW.Prefs` is an **alias** of `TRP3FW_DB.profiles[activeProfile]`, not a container of
its own (`core/init.lua:638`). Assigning `{}` rebound the alias to a fresh throwaway
table and left the saved profile untouched — and then `InitializeSettings` →
`LoadProfile` immediately repointed `Prefs` straight back at that same untouched
profile. `LoadProfile`'s backfill loop only fills keys that are `nil`, and none were, so
it changed nothing either. The throwaway table was garbage collected unread.

The command printed "|cff00ff00All settings reset to defaults!|r" and every setting kept
its old value. Same shape as the `hasTRP3ExchangeHooks` and `options.priority` findings:
a write that goes somewhere nobody reads.

**Fix:** clear the active profile table **in place** (`for k in pairs(profile) do
profile[k] = nil end`), which is what keeps `Prefs`, the SavedVariable and the DB entry
the same table, then let `LoadProfile`'s existing backfill repopulate from
`defaultSettings`. This also clears orphaned keys that are no longer in `defaultSettings`
— the old code could not have, even had it worked. Added a `/reload` warning, since
caches and hooks are built from the values at init.

**Also removed:** a **second, unreachable `elseif cmd == "reset"`** near the end of the
chain (old :1373), an exact copy of the first. Dead since the day it was added — an
if/elseif chain stops at the first match — but it is the kind of duplicate that gets
"fixed" in one copy and not the other.

### `commands.lua` — `debugfilter` could not reach two of its own categories (fixed)

`core/utils.lua:52`'s `DEBUG_CATEGORIES` is the authority on what `TRP3FW:Debug(msg, cat)`
accepts. Two entries — `ghost` → `debugGhost` and `spvp` → `debugSPVP` — had **no branch
in `/trp3fw debugfilter`**. Both are real: they have defaults (`core/init.lua:213-214`),
settings-UI checkboxes (`ui/settings.lua:6173`, `:6180`), and `CLAUDE.md` lists `ghost`
among the documented categories with `/trp3fw debugfilter ghost` as the worked example in
its "Ghost mode not working" troubleshooting recipe. Typing that documented command hit
the `else` and printed usage.

Cheap, but it lands on the two areas hardest to debug any other way — ghost sends and the
SPVP handshake are exactly the paths the deferred items keep saying need live logs, per
[[epsilon-runtime-bugs-need-live-logs]].

**Fix:** two branches, plus both categories added to the usage string and the
current-filters readout, and the category list written into `ShowHelp`.

### `commands.lua` — `/trp3fw phasecheck` could latch its mutex for the session (fixed)

`TRP3FW.phaseCheckInProgress` guards against concurrent zone scans. `commands.lua` is its
**only** owner — the sole assignment, the sole test, and the sole clear, all in this one
branch (verified repo-wide). Every clear sat on a success path, and the per-player one was
inside `if checked >= total`.

`checked` is incremented by a `CheckPlayerPhase` callback, one per player returned by the
WHO zone scan. Any single callback that never arrives leaves `checked < total` forever, and
the flag latches `true` for the rest of the session — every later `/trp3fw phasecheck`
answers "already in progress. Please wait." until `/reload`, with nothing in any log. The
command is also the one place that dispatches N phase checks at `"LOW"` priority in a
loop, so it is the most exposed to the queue, the token bucket and the deferral path that
section 4 was all about.

**Fix:** an idempotent `Finish()` plus a 120s watchdog, so the mutex is released on every
path. The watchdog reports partial results and says it timed out rather than pretending
the run completed. Deliberately generous — LOW-priority checks are batched and
token-throttled, so a large zone legitimately takes a while; this is a backstop, not a
deadline. Kept the "not a disabled timer" test the section-5 findings established: a spec
asserts the watchdog still fires for a genuinely stuck run *and* that a completed run is
never double-reported.

**Also added:** an `IsPhaseCheckEnabled()` guard. The command only checked
`hasEpsilonAPI`, but `CheckPlayerPhase` opens with
`if not self.hasEpsilonAPI or not self:IsPhaseCheckEnabled()` → `callback(nil,
"unavailable")`. With `phaseCheckMode = "off"` the command therefore spent a real
privileged WHO zone query and then reported "0/N in phase" with no hint why.

New spec `tests/unit/commands_spec.lua` (60 tests); **37 fail against the original**.
It drives the real `SlashCmdList.TRP3FW` handler rather than asserting on source text —
these are runtime failures, so a runtime test is the honest assertion. Added
`SlashCmdList` and the zone-text globals to `tests/mock_wow.lua`.

### `TRP3FW.lua` — unisolated init steps inside timer callbacks (fixed)

Four startup steps ran bare inside `C_Timer.After` callbacks, where an uncaught error is
swallowed by the client *after* aborting the rest of that callback. `InitializeUI` was
already pcall'd; its four neighbours were not, and each one abandons work that nothing
retries:

- **`InitializeSettings`** (`ADDON_LOADED`). The load-bearing one. If it throws,
  `LoadProfile` never runs and `TRP3FW.Prefs` stays aliased to `defaultSettings` — the
  exact scenario the deferred `core/init.lua:243` item warns about, where every setting
  written that session mutates the defaults table and any profile created afterwards is
  born polluted. Now pcall'd and **loud**: nothing downstream can distinguish this state
  from a healthy one, so the user is told to `/reload` and not to touch settings.
- **`InstallHooks`** — a throw here also took `HandleDependencySettings` and the nested
  blank-profile validation with it, leaving ghost mode enabled in the settings with no
  ghost profile to send.
- **`ShowWelcomeMessage`** — sets `hasSeenWelcome = true` *before* it prints, so a throw
  part-way through consumes the one-shot flag and skips `ShowWelcomeWizard`. A first-time
  user would then never see either, on any login.

**Not changed:** the `PLAYER_LOGOUT` cleanup. It clears three queues and cancels a timer
"to prevent memory leaks", but WoW discards the entire Lua state at logout, so the whole
handler is a no-op. Harmless and not worth the diff; noted because the comment claims
otherwise.

**Verified sound:** the XRP blank-profile guard here uses `AddOn_XRP and xrpSaved`, not
the long-dead `xrp` global that produced the section-6 finding.

### `status.lua` — help-text drift (fixed), no defects

The file is display-only — `print` calls and string concatenation — and its arithmetic is
correct. Four documentation errors fixed:

- `/trp3fw phasedelay` was advertised as "default: 3"; the real default is **4**
  (`core/init.lua:158`). Note `ui/settings.lua:73` also says 3, but that is a
  `SETTING_LEVELS` complexity entry, not a default — the two just look alike.
- The `/trp3fw cache <type>` list omitted `phasefail` and `scanfail`, both of which the
  command accepts.
- `debugfilter` was documented as `<category>` with no list; now lists all 15.
- **`Bug reports: https://github.com/[your-repo]/issues`** — an unfilled placeholder
  shipping in the help output. Pointed at the GitHub release remote.

**Checked and found sound** (all looked suspicious, none are bugs):
- `ShowStats`'s `successful = total - errors` is right, despite ignoring `blocked` and
  `deferred`. `RunPrivilegedSafe` increments `total` *after* the rate-limit and deferral
  checks pass (`core/utils.lua:574`), so those two are counted outside `total` while
  `errors` is counted inside it.
- Every unguarded `TRP3FW.Prefs.X` read in `ShowStatus` resolves to a key that exists in
  `defaultSettings`.
- `sessionStats.performance` is only aliased at HistoryService init, but that runs at
  `PLAYER_LOGIN`, long before a user can type a command.
- Every command advertised in `ShowHelp` and `ShowWelcomeMessage` is actually implemented
  (the reverse is not true — ~30 working commands are undocumented, which is a choice
  rather than a defect).
- `ShowWelcomeMessage`'s "Only show once per character" comment is wrong — `hasSeenWelcome`
  lives in the profile, so it is once per *profile*. Comment only; left alone.

### `ui/debugwindow.lua` — **auto-scroll read a nil global, so it never once ran** (fixed)

`RefreshDebugOutput` (`:103`) gates its scroll-to-bottom on
`if autoScrollCheck and autoScrollCheck:GetChecked() then`. But `autoScrollCheck`
was declared `local` at `:141` — **38 lines below the function that reads it**.
Lua resolves a name to a local only if the `local` statement is lexically *above*
the closure, so inside `RefreshDebugOutput` the name fell through to the global
environment, where nothing ever assigns it. Verified repo-wide: the only
`autoScrollCheck` in the addon is that one local.

So the guard was `if nil and ...`, permanently false. The checkbox renders,
tracks its own checked state, defaults to on — and controls nothing. Every debug
line appended to the window left the view pinned wherever the user last scrolled,
which for a freshly-opened window is the top. The one thing the window exists for
— watching debug output as it arrives — silently didn't work, and the control
that claims to govern it looked correct and enabled the whole time.

Worth noting *why* it survived: the `and` short-circuit turned what would
otherwise be an "attempt to index a nil value" error into a silent no-op. A bare
`autoScrollCheck:GetChecked()` would have thrown on the first debug message and
been fixed the same day. The nil-guard, written defensively, is what hid it.

**Fix:** forward-declare `local autoScrollCheck` above `RefreshDebugOutput` and
turn the later line into a plain assignment. The frame still has to be created
where it is (it anchors to the frame's bottom edge, after the scroll frame), so
the declaration and the construction genuinely do need to be separate statements.

### `ui/settings.lua` + `ui/tabs/Debug.lua` — **the four phase-batching sliders never showed their stored value** (fixed)

`RefreshUI` drives widgets through three loops keyed by setting name: `checks`
(booleans, `:SetChecked`), `edits` (numeric boxes, `:SetText`), and the dropdown
config. Sliders are not in any of them — they are handled by explicit lines, of
which there were exactly two (`spvpBlockDurationSlider`, `spvpSaltCacheDurationSlider`
at `:751-756`).

`ui/tabs/Debug.lua:205-217` registers four more under `uiElements.<key>Slider`:
`phaseCheckBatchSize`, `phaseCheckBatchDelay`, `phaseCheckBatchMinSize`,
`phaseCheckInterTargetDelay`. **No line in `ui/settings.lua` mentioned any of
them** (verified repo-wide). `CreateSlider` calls `SetMinMaxValues(minV, maxV)` on
a fresh slider, which clamps it to `minV`, and nothing ever moved it off that
value. So the Advanced tab displayed batch size 2 (real default 5), batch delay
0.1s (real default 1.0s), min batch size 2 (real default 3) and target delay 10ms
(real default 100ms) — on every open, regardless of what was saved.

This is worse than a cosmetic mismatch. The readouts are the only place these
values are visible in the UI, so the panel actively misreported the running
configuration; and because the slider was parked at its minimum, a user nudging it
one step wrote a value near the minimum into `Prefs` rather than adjusting from
where they actually were. Note the write direction was always fine —
`SetOnChange` is wired correctly — which is why `/trp3fw phasebatch` (commands.lua:1277)
and the UI disagreed with each other rather than the setting simply being dead.

**Fix:** a `batchSliders` table next to the SPVP pair, driving all four from their
prefs with the defaults from `core/init.lua:127-130`.

### `ui/settings.lua` — **`SETTING_LEVELS` classified a setting that does not exist** (fixed)

`:78` listed `phaseCheckBatchInterDelay = 3`. There is no such setting: the real
key, defined at `core/init.lua:130` and read at `location/phase.lua:679`, is
`phaseCheckInterTargetDelay`. So the phantom entry classified nothing, and the
real one — having no entry — took `TabManager:_registerSkinned`'s fallback of
level **4**.

Consequence: the target-delay slider was the only member of its group hidden
below the "Everything" complexity level, while the three settings it sits directly
beside (`phaseCheckBatchSize/Delay/MinSize`, all level 3) stayed visible at
Advanced. The Batching card therefore showed three of four related tunables with
a gap where the fourth belongs. Same defect class as the slider bug above and
found alongside it — a key that two files spell differently, with nothing checking
that the two spellings agree.

**Fix:** corrected to `phaseCheckInterTargetDelay = 3`, matching its siblings.

New spec `tests/unit/ui_refresh_spec.lua` (11 tests) covers all three; verified
**8 fail against the original**. Note the slider assertions read `ui/settings.lua`
as source text rather than driving `RefreshUI`: `uiElements` is a file-local with
no accessor, and adding a test-only hook to production code to reach it is a worse
trade than a source contract. The declaration-order test for `autoScrollCheck` is
source-based for the same reason — it is a *lexical* bug, so lexical position is
the honest thing to assert.

### `ui/Theme.lua`, `ui/TabManager.lua`, `ui/tabs/*` — reviewed, no further defects fixed

- **`Theme.lua` is clean.** `Color()` returns 4 values and every call site passes
  it straight into a `Set*Color`, which is the arrangement `settings.lua:955`
  documents a past bug about (`a and Theme:Color(X) or Theme:Color(Y)` truncates
  the multi-return to one value and paints the text red). Checked every
  `Theme:Color(` call in `ui/` for that shape: the only conditional ones pick the
  palette *name* first, as the comment instructs. `makeFont` correctly falls back
  when a Blizzard base object is missing, and the `Hex`/`ColorObject` caches are
  keyed by name with no invalidation need (the palette is immutable).
- **`Alerts.lua`'s `+ Add row` splice is correct**, despite reading like an
  off-by-one. `RenderOverrideRow` appends the new row *after* the button row, then
  `table.remove(_rows)` pops it back off and `table.insert(_rows, #_rows, newRow)`
  re-inserts it at the button row's index — pushing the button down. Traced by hand
  for the empty, one-row and at-cap cases; the button stays last in all three.
  Flagged only because this is the third reviewer-pass in this file to stop on it.
- **`Card:Reflow`'s dynamic-height contract is honoured everywhere it is used.**
  The three dynamic rows (`Notifications.lua:97` chip wrap, `Debug.lua:118` numeric
  grid, `Debug.lua:289` category grid) all return a height; every static row omits
  the return and falls back to `row.height`. Checked because a dynamic row that
  forgets to return would collapse the card's remaining rows on top of each other.
- **`TabManager:PrebuildAllTabs` correctly scopes `_buildingTab`** so
  `IndexSearchable` attributes each widget to the tab being built rather than to
  `activeTab` (which is nil during prebuild). This is what makes settings search
  work before the user has visited a tab.
- **`historywindow.lua`'s bar pool is sound** — `SetData` hides the tail beyond
  `#dataPoints` *and* clears `tooltipData`, and the hover scripts are set once at
  creation with data stored on the frame rather than captured in a closure, which
  is the correct fix for the leak its own comment describes.
- **`Status.lua`'s `recomputeHeight` is driven by `onToggleExtra`, not `onToggle`.**
  `CreateSection` accepts an `onToggle` parameter and calls it, but every call site
  passes `nil` and the tab wires `sec.onToggleExtra` afterwards instead. Both fire,
  so the behaviour is right; the `onToggle` parameter is simply dead. Left alone.

### `hooks/trp3.lua` — **HIGH: `hasTRP3ExchangeHooks` was never set, disabling TRP3 ghosting** (fixed)

`core/init.lua:349` declares `TRP3FW.hasTRP3ExchangeHooks = false` and **no production line ever
assigns it again** (verified repo-wide; the only other writes are in
`tests/unit/start_phase_spec.lua`, which set it `true` to make its own ghost cases reachable —
so the suite was pinning the intended behaviour while production never reached it).

But `InstallSendObjectHook` *is* the TRP3 exchange hook. It is the only thing that swaps an
outgoing `SI` profile payload for ghost data (`trp3.lua:537-580`), it installs successfully
whenever TRP3 is loaded, and it even logs that it did. The flag that means "TRP3 ghosting is
available" was therefore permanently `false` while the capability it describes was fully
installed. Its four read sites all failed in the same direction — toward *not* ghosting:

| site | intended | actual |
|---|---|---|
| `features/decision.lua:346` | ghost each queued TRP3/Chomp burst sibling | siblings silently dropped |
| `features/ghostmode.lua:51` | phase-169 ghost | falls through to hard **block** unless MSP hooks happen to be present |
| `NotificationService.lua:258` | "[GHOST MODE] sent alternate profile to" | labelled as a plain block |
| `NotificationService.lua:338`/`:463` | start-phase ghost wording | same mislabel |

The burst path is the one that loses data. `ProcessBurstBlocks` guards the TRP3/Chomp loop with
`if useGhostMode and self.hasTRP3ExchangeHooks`, then clears `q.tbl[playerName]` regardless — so
with the flag stuck false every queued sibling of a ghosted burst was dropped without being
sent, ghosted, *or* blocked, and the queue was emptied behind it. Same silent-non-arrival
symptom as the section-3 `LocationStage` timer bug and the section-5 Chomp give-up timer, and
the same root shape: state that decides whether work happens, owned by nobody.

Note this is *fail-safe* rather than fail-open — the failure mode is "blocked instead of
ghosted", never "real profile leaked". That is why it survived a live-testing regime: the
firewall still firewalled, it just did so more bluntly than configured, and the notification
text agreed with the wrong behaviour.

**Fix:** set the flag where the hook is actually installed, and on the `CheckHookConflict`
"skip" path too (an already-installed hook is still ours, so ghosting is still available).
The "refuse" and missing-`AddOn_TotalRP3.Communications` paths correctly leave it false.

### `features/ghostmode_trp3.lua` — **the ghost window's anti-timing-oracle jitter was inert** (fixed)

`EnableGhostForNextSend` computed a jittered expiry and then armed a **fixed** cleanup timer:

```lua
local jitter = math.random(0, 2000) / 1000  -- 0-2s
local expireTime = now + 2 + jitter          -- "2-4 second window"
...
self.ghostCleanupTimer = C_Timer.NewTimer(2, function() ... end)
```

The timer always wins that race, so `ghostNextSend` was torn down at a constant **2.000s** on
every send and the jitter widened the window by exactly zero frames. Verified by direct
execution: for every jitter value the flag dies 0–2s *before* its own recorded `expires`.

The comment says the jitter exists to prevent timing-oracle attacks (MEDIUM-3). A fixed 2.0s
teardown is precisely the constant interval the jitter is meant to hide, so the mitigation
defeated itself. `ShouldGhostSendTo` and `GetGhostProfileID` both check `expires` honestly,
which is what made the mismatch invisible — they simply never got the chance, because the
flag was already `nil`. Worth noting a *second*-order effect: any ghost send that landed
between 2s and the nominal expiry silently fell back to the no-flag path.

**Fix:** one `ghostWindow` local now feeds both the expiry and the timer. The debug line no
longer hardcodes "expires in 2s" either, since it never did.

**Not changed:** this file uses raw `GetTime()` rather than the frame-cached
`TRP3FW:GetCurrentTime()` the rest of the addon prefers. Left alone deliberately — the write
(`EnableGhostForNextSend`) and both reads (`ShouldGhostSendTo`, `GetGhostProfileID`) use the
same clock, so they are internally consistent, and per the deferred `GetCurrentTime` item the
"frame cache" currently saves nothing anyway.

New spec `tests/unit/ghost_flag_window_spec.lua` (11 tests) covers both bugs plus the
burst-ghost consequence; **4 fail against the original**.

### `features/notifications.lua`, `features/ghostmode.lua`, `features/decision.lua`, `features/profileswitch.lua` — reviewed, no further defects fixed

- **`ProcessBurstBlocks`'s drop path is correct, not a leak.** When ghosting is impossible the
  queued request is intentionally discarded without sending — not sending *is* the block, so
  the fall-through is fail-closed. Confirmed by simulation that the ghost flag is re-armed per
  iteration, so burst siblings each get their own flag rather than racing over one. Added a
  comment saying so, because the loop reads like a lost-request bug at a glance and this is the
  second reviewer-hours sink it has caused.
- **Ghost-flag key form verified clean** — the question that produced 30ee55c and the
  `AllowSender` bug. Every writer (`decision.lua:487`, `msp.lua:292`,
  `trp3_chomp_pipeline.lua:211`) and every reader (`trp3.lua:319`, `:542`,
  `msp_exchange.lua:20`, `:169`, `:188`) passes a `CleanPlayerName` result, and
  `CheckLocationAndNotify`'s `playerName` is already cleaned by its only caller
  (`trp3_chomp_pipeline.lua:303`). No raw/clean split on this keyspace.
- **`OnProfileSwitchEvent`'s `event == "PLAYER_ENTERING_WORLD"` test is sound.**
  `EventService:Trigger` passes the raw WoW event as the first callback arg
  (`EventService.lua:91`), so the handler does see the real event name and not the
  `ZONE_CHANGED` alias it is registered under. Checked because the file registers for two
  *aliased* events and this is exactly the shape that silently never matches.
- **`IsBurstRequestStale`'s zone/phase snapshots are consistently sourced** — every producer
  (`BurstStage.lua:32`, `LocationStage.lua:40`, `trp3_chomp_pipeline.lua:269`/`:283`) reads the
  same two `TRP3FW.lastZoneChangeTime`/`lastPhaseChangeTime` globals the comparison reads.
- **`features/notifications.lua` is a pure delegation shim** and correctly nil-guards every
  `ServiceContainer:Get`. `RecordHistory` routes to HistoryService rather than
  NotificationService, which is right but is the one line in the file worth a second look.
- **`profileswitch.lua`'s `StableHash` has a latent key-coercion quirk** (`:133`):
  it stringifies keys for sorting, then reads back with
  `value[sk] ~= nil and value[sk] or value[tonumber(sk)]`. For a numeric-keyed table this
  round-trips through `tostring`/`tonumber`, and a table holding **both** `[1]` and `["1"]`
  would hash them to the same slot. TRP3 profile tables are string-keyed MSP fields, so this
  is not reachable today; noted rather than fixed because the hash is only a cheap secondary
  guard behind a full `DeepCompare`.
- **`DeepCompare` is correctly bidirectional** (checks for extra keys in `t2`), which is what
  makes the blank-profile integrity check trustworthy. `DeepCopy` has no cycle guard, but
  profile data is acyclic.
- **`profileswitch.lua:881` carries a stray Korean comment** ("선택한 (또는 선택한) 프로필로
  전환" — "switch to the selected (or selected) profile"), duplicated word and all. Harmless,
  but it is the only non-English line in the addon.

### `features/profiles/*` — **XRP ghost sends read a global that no longer exists** (fixed)

The adapters themselves are clean — the defect is in their **consumer**.
`hooks/msp_exchange.lua:487` gated the XRP branch of `GetProfileDirectMSP` on
`xrp and xrp.profiles and xrp.profiles[profileID]`. Current XRP has no `xrp` global at all:
the namespace is `AddOn_XRP` (created in `Backend/Backend.xml:3`) and the profile store is
`xrpSaved.profiles`, which is what `adapter_xrp.lua` correctly reads. Verified repo-wide
against the real addon in `other_addons/XRP` — **zero** occurrences of `xrp.profiles` or an
`xrp` global assignment. The condition was therefore never true, so every XRP ghost send fell
through to the "profile not found" `nil` return, and `GenerateMSPGhostPayload:24` silently
substituted `GetBlankMSPFields()`. An XRP user selecting an alternate ghost profile got a
**blank** profile instead — failing safe, but not doing what the setting says.

Two further shape errors in the same branch, both now fixed:

- **`.fields` indirection.** XRP stores MSP data at `xrpSaved.profiles[name].fields`, not
  flat on the profile. The old `for field, value in pairs(sourceProfile)` would have copied
  the *container* keys (`fields`, `inherits`, `parent`) as if they were MSP fields — so even
  had the guard passed, the payload would have carried a table as a field value.
- **Parent inheritance ignored.** XRP resolves fields through a parent chain
  (`Backend/Profiles.lua:86-125`); a child profile stores **only its overrides**. Copying raw
  `.fields` would ghost a mostly-empty profile for anyone using XRP's inheritance feature. The
  fix walks the chain, honors the `inherits[field] == false` opt-out (XRP's "deliberately
  blank" marker), and bounds the walk at depth 10 so a cyclic `parent` can't hang the client.

**Left unfixed, documented in place:** XRP converts `AH`/`AW` into MSP units on its own send
path (`Backend/Profiles.lua:120`), but its converters live on XRP's *private* `AddOn` table,
not the public `AddOn_XRP` — unreachable from here. A ghosted XRP profile sends those two
fields in the user's raw stored units. Cosmetic and limited to height/weight; a comment now
records why rather than leaving a guard that could never fire.

New spec `tests/unit/direct_msp_xrp_spec.lua` (10 tests); **7 fail against the original**.

### `hooks/fontsize.lua` — **the whole wrapper normalizer matched exactly one string** (fixed)

`FONT_WRAPPER_PATTERN` was written in regex, not Lua patterns:

```lua
"^%s*{%s*([Hh][123]|[Pp])([:cCrR])?%s*}"
```

Lua patterns have no alternation and no `?` quantifier on a group. `|` is a literal pipe and
a `?` after `)` is a literal question mark, so this expression matched **one input in the
universe**: the string `{h1|Pc?}`. Verified by direct execution. Every real profile fell
through the `if not startBlock then return text end` guard untouched, so
`NormalizeFontWrappers` was a no-op for the entire life of the setting. A second copy of the
same broken alternation sat on the next line (`startBlock:match("([Hh][123]|[Pp])")`), so
even a corrected opening pattern would have bailed one line later.

**Consequence:** with "Minimum Font Size" on, a profile whose body is wrapped in an explicit
`{h1}...{/h1}` kept that wrapper. `toHTML` then emitted `<h1>`, which already outranks the
configured floor, so `EnsureMinimumHtmlFont` correctly left it alone — the profile rendered
at h1 regardless of what the user selected, which is precisely the case the setting exists
to handle. `CleanupLegacyFontWrappers` (which calls this with `force=true` across saved
CU/CO fields) also cleaned nothing and logged "Removed legacy font wrappers from 0 character
fields" every login.

**Fix:** two patterns tried in order, since one expression cannot express the alternation.
Checked against TRP3's real grammar rather than guessed: `structureTags` in totalRP3
`core/impl/utils.lua:856` is **lowercase-only** (`{h(%d)}`, `{h(%d):c}`, `{h(%d):r}`, `{p}`,
`{p:c}`, `{p:r}`), so `{H1}` is not a tag TRP3 renders and must not be stripped as if it
were — the old `[Hh]` classes implied otherwise.

`EnsureMinimumHtmlFont` itself was verified sound against real `toHTML` output, including
the `</P><img .../><P>` image tag, `<br/>` and `<a href>` — the `[hHpP]` letter class
correctly skips all of them.

New spec `tests/unit/fontsize_wrapper_spec.lua` (34 tests); 11 fail against the original.

### `hooks/trp3_chomp_pipeline.lua` — **two deferred timers tore down their successors** (fixed)

Both are the same shape as the section-3 `LocationStage` timer bug: a `C_Timer.After`
callback that identifies its work by a key or a value instead of by identity.

**1. The burst give-up timer** (`:271`) read
`if self.pendingChompSends[playerName] then ... = nil end` — presence, not ownership. The
stage itself replaces an entry older than 2s with a fresh one **under the same player key**,
so a second request from that player inside the 30s window installs a new burst entry, and
the first request's timer then deleted it along with every request queued behind it. Those
are never replayed: `ProcessBurstAllows` / `ProcessBurstBlocks`
(`features/decision.lua:289`, `:343`) both no-op on a missing key, so the queued sends were
neither sent, ghosted, nor blocked — the profile silently never arrived. Now compares against
the entry the stage actually created.

**2. The phase-in replay timer** (`:110`) located its send by
`queuedSend.target == target and queuedSend.queuedAt == now`. `GetCurrentTime()` is
frame-cached, so two sends to one target in the same frame share a `queuedAt` and are
indistinguishable by that predicate — both timers matched the **first** entry, replaying it
twice while the second sat queued until the TTL sweep dropped it unsent. Now matches by
table identity, which also makes the CacheService/logout paths that clear the queue wholesale
safe (the timer simply finds nothing).

**Same fix also closed a latch:** the replay called the *hooked* `SmartAddonMessage`
(re-entering our own wrapper, which is why the `replayingPhaseInSend` flag exists at all),
and **nothing in that chain is pcall-wrapped** — `hooks/trp3.lua:398` calls
`ChompHookPipeline` bare. An error anywhere in it skipped the `= false` line and latched the
flag `true` for the rest of the session, silently disabling *every* Chomp guard (recursion,
phase-in, location gating) until `/reload`. Now pcall'd, with the flag restored either way.

New spec `tests/unit/chomp_pipeline_timer_spec.lua` (8 tests), including a test that the
give-up path still fires for a burst that genuinely never resolved, so the fix cannot be
mistaken for "disable the timer". 2 fail against the original.

### `hooks/msp.lua` + `hooks/trp3.lua` — **one table, two colliding keyspaces** (fixed)

`TRP3FW.detectedAddons` served two unrelated purposes. `hooks/installer.lua:57-77` keys it by
**capability** — `.TRP3/.MRP/.XRP/.MSP` are booleans for "is this addon loaded locally",
`.MapScanner` is the string `"TRP3"` or `"RPMapScan"` — and it is read that way by
`status.lua`, `ui/`, `core/utils.lua:808` and `location/`. But `hooks/msp.lua:405` keyed the
**same table by remote player name**, storing which RP addon that player appears to run, and
`hooks/trp3.lua:350` read it back that way.

Player names and capability names share a namespace, so they collided in both directions:

- **Player → capability.** A request from a player named `MapScanner` set
  `detectedAddons.MapScanner = "MSP"`. That is truthy, so `location/maps.lua:361` and
  `location/cascading.lua:214` believed a map scanner was installed when none was — map
  checks proceeded and failed — and `status.lua:184` displayed "Map Scanner: MSP".
- **Capability → player.** The installer sets `detectedAddons.MSP = true`. A send to a player
  named literally `MSP` read that back as that player's addon, putting a **boolean** where
  every consumer expects a string. `HistoryService:TrackAddonRequest` type-guards it
  (`:371`) so the request goes untracked, but `NotificationService` formats it with `%s` at
  `:279` and `:506` — and `string.format("%s", true)` is a **hard error** in Lua 5.1
  (verified), inside the notification path of a profile send.

**Fix:** player-keyed data moved to a new `TRP3FW.playerAddonProtocol`, and the read site in
`trp3.lua` now type-checks the resolved value too. Also **bounded** it — it grows one entry
per unique player who ever requests your profile, values are bare strings with no timestamp
to age out on, and under the conflated table it could never be pruned at all without
destroying the capability flags sharing the keyspace. Its siblings (`mspCallbackSendIds`,
`pendingMSPAutoReplies`) are both pruned by `CacheService`.

New spec `tests/unit/addon_keyspace_spec.lua` (8 tests), including one pinning the
`string.format("%s", true)` premise the severity rests on.

### `hooks/trp3.lua` — **ghost defaults were written into the user's saved profile** (fixed)

`GetGhostDataForInformationType`'s CHARACTERISTICS branch filled two required defaults by
assigning onto the table it had just fetched:

```lua
if not ghostData.FN or ghostData.FN == "" then ghostData.FN = UnitName("player") end
if not ghostData.CH or ghostData.CH == "" then ghostData.CH = "ffffff" end
```

`GetProfileCharacteristics` does not copy — the TRP3 adapter returns
`profile.data.player.characteristics` **itself** (`features/profiles/adapter_trp3.lua:125`),
a live reference into `TRP3_Profiles`. So the first ghost send using a profile with an empty
first name or no name colour permanently stamped the player's own character name and
`#ffffff` onto their saved ghost profile — visible in TRP3's own editor and persisted to
SavedVariables.

`ValidateGhostTRP3Payload`, called a few lines later, *does* copy before sanitizing (`:174`).
That is exactly why only these two assignments leaked, and why it was easy to miss.
**Fix:** apply the defaults to a copy.

New spec `tests/unit/ghost_data_mutation_spec.lua` (7 tests); 3 fail against the original.

### `hooks/trp3_scan_pipeline.lua` — un-fixed copy of the section-2 WHO bug (fixed)

The WHO query-mode block in `PerformLocationCheck` is a copy of
`WhoService:CheckPlayer`'s zone-completeness test but was **missing that function's
load-bearing `lastZoneQueryTime > 0` guard** — the exact defect section 2 fixed in
`WhoService` (see `who_service_queue_spec.lua`, where the same false premise made WHO checks
fail shut). Both zone fields start at 0/nil and the clock is client uptime, so `now - 0 < 60`
held for the first 60 seconds of every session and a zone query that had **never run** read
as "queried just now, and complete".

This copy only chooses the query *type*, so it never failed shut — but it decided from a
false premise, and backwards: past 60s uptime with no zone query ever run, the old code
concluded "stale zone, refresh it" and issued a broad `whozone`. TRP3 holds the scan reply
window open for only ~3s, so with no zone data at all the direct `whoname` is the answer that
can actually arrive in time.

**Also collapsed five branches to two.** Of the old form's branches, three set
`whoNameOnly = true` with comments implying they differed, the fresh+complete branch's inner
`if recentMapScan` picked `true` either way, and the trailing `else` was **unreachable** (the
two `elseif` conditions are exhaustive once the first branch is excluded) — verified by
enumeration. Only one combination actually wants a zone query: queried, stale, was not
truncated, and no map scan competing for the window. Equivalence checked exhaustively across
750 input combinations of the four state variables: the **only** disagreements between old
and new are exactly those with `lastZoneQueryTime == 0`, i.e. the intended change.

New spec `tests/unit/scan_pipeline_who_mode_spec.lua` (10 tests); 1 fails against the
original.

### `hooks/installer.lua`, `hooks/icon.lua`, `hooks/gradient.lua`, `hooks/msp_exchange.lua` — no defects fixed

- **`InstallIconHooks` / `InstallGradientHooks` return early when their pref is off**, and
  `InstallHooks` sets `hookInstalled = true` afterwards, so enabling either filter in the
  settings UI does nothing until `/trp3fw reloadhooks` or `/reload`. Both filters *are*
  correctly idempotent once installed (the `iconHookInstalled` / `gradientHookInstalled`
  guards, added earlier, stop `reloadhooks` from nesting wrappers) — the gap is only the
  enable-at-runtime direction. Arguably by design given the hooks cannot be cleanly removed,
  but nothing tells the user that.
- **`msp_exchange.lua:9` `InstallMSPExchangeHooks` is a stub** that installs nothing and
  unconditionally sets `hasMSPExchangeHooks = true`. That flag gates ghost-mode paths
  (`hooks/msp.lua:290` treats it as "ghosting is available"). The comment explains the proxy
  strategy was replaced by Chomp payload replacement, so the flag now means "ghosting works
  by another route" rather than "these hooks are installed" — accurate in effect, misleading
  in name. `VerifyMSPIntegrity` in the same file still guards `hookState.exchange.mspMyMeta`,
  which nothing sets any more, so that whole function is dead with the proxy removed. Left
  alone: deleting it is a call about whether the proxy strategy might return.
- **`RemoveTextTags` verified sound** against `{col:}`, `{icon:}`, `{img:}`, `{link*}`,
  nested and unclosed tags — this was checked specifically because it is the same
  pattern-matching shape as the `fontsize.lua` bug above.
- **`ValidateGhostTRP3Payload` copies before sanitizing** (`trp3.lua:174`), one nested level
  deep, which is what limited the profile-mutation bug above to two fields.
- `installer.lua`'s `GetFunctionSource` / `CheckHookConflict` conflict detection reviewed and
  sound; `strictHookMode` correctly refuses rather than chains.

### `location/cascading.lua` — **HIGH: `options.priority` was read nowhere** (fixed)

`hooks/trp3_scan_pipeline.lua:188` sets `priority = "HIGH"` on every TRP3 scan reply,
because TRP3 only holds its reply window open for about 3 seconds.
`CheckLocationCascading` never read the field. It called `StartStandardChecks(results)`
with no priority at all, and `results` carried none either — so `nil` propagated into
every downstream decision and **every HIGH-keyed path in section 4 was unreachable from
the only caller that asks for one**:

| path | intended (HIGH) | actual |
|---|---|---|
| `StartStandardChecks` parallel map check | armed at 0.2s | never armed |
| `RunMapCheck` parallel map scan | armed at 0.3s | never armed |
| `RunMapCheck` skip-WHO-when-busy | skips a busy WHO | always waits on WHO |
| `CheckPlayerPhase` targeting timeout | 1.5s | 3.0s |
| `QueuePhaseCheck` immediate fire | fires at once | waits the 1.0s batch delay |
| `MapScan` rate limit | 5s | 60s |
| `MapScan` scan timeout | 2.5s | 5s |

Compounded, a scan reply could not resolve before ~4s even in the good case (1.0s batch
accumulation + 3.0s targeting), so it always lost to cascading's own 2.0s deadline and to
TRP3's window — and `MapScan`'s 60s rate limit meant most scan replies got
`scan_rate_limited` rather than a real answer. Note `maps.lua:333` carries a comment about
having already fixed a *different* break in the same chain ("Previously this was
(incorrectly) keyed off `sendId` being the string HIGH ... so the fast-path was dead"):
the inner plumbing was repaired but the outer end was still not connected.

**Fix:** read `options.priority` and pass it to `StartStandardChecks`. `OnSPVPResult`'s
hardcoded `"HIGH"`/`"NORMAL"` are left alone — those are deliberate (see the H3 comment
there). `LocationStage` and `AlertFastPathStage` pass no priority, so the ordinary send
path is unchanged; **this only alters the scan-reply path**, which is what it was written
for. ⚠ Behaviour change worth watching in game: HIGH also makes `QueuePhaseCheck` fire a
batch immediately per scan reply instead of accumulating, so a busy scan is now more
targeting-bursty. The mutex in `ProcessPhaseCheckBatch` serializes it, but this is the
one item in section 4 that wants a live look before it ships.

### `location/phase.lua` — **every phase check delivered its result twice** (fixed)

`QueuePhaseCheck` seeded `pendingPhaseCheckWaiters[playerName]` with
`callbacks = { callback }` — the originating caller's own callback — and then stored that
same function again on the queue entry (`entry.callback`). Every resolver delivers both:
`ExecutePhaseCheck`'s `handleResult` calls `check.callback(...)` and then
`ResolvePhaseCheckWaiters(...)`; `ProcessPhaseCheckBatch`'s `finishStep` fans out
`check.callbacks` and then calls `ResolvePhaseCheckWaiters` too; so do the three late-cache
-hit branches, the `api_error` branch, and `ResolveInspectDeferral`. `onTargetingStarted`
had the identical shape and double-fired the same way.

So **the caller that started a check was invoked twice, while callers that attached to it
were invoked once** — on every path, in both batch and individual mode.

Contained today rather than harmless: `CheckLocationCascading`'s `results.resolved` flag
swallows the second delivery once a request has resolved, and `HandlePhaseResult` is
idempotent enough to absorb it before then (see the deferred item above). The visible
leaks are `commands.lua:1185` (`/trp3fw` phase check prints its result twice) and wasted
re-evaluation. The real cost is that the contract stated in the file — "Call exactly once
per resolved player per check attempt" — was false, in the exact module where section 3
learned that ambiguous ownership of player-keyed state is where the bugs live.

**Fix:** the two mechanisms now own disjoint sets. The queue entry owns the caller that
created it (and carries it through batch merges and `deferred_low_priority` requeues); the
waiters group owns only the *additional* callers that attached to an already-pending check.
Both lists are seeded empty.

### `location/maps.lua` — **a second scan for the same player destroyed the first** (fixed)

`activeScanCallbacks` is keyed by player name alone, and `MapScan` assigned into it
unconditionally. A second scan for the same player replaced the first entry outright:

1. The first caller's callback was **discarded** — never told found, not-found or timed
   out, so whatever awaited it hung until its own deadline.
2. The first entry's 5s timer was never cancelled. When it fired it looked up
   `activeScanCallbacks[name]`, found the **second** entry, saw `found == false`, and
   resolved it as a timeout early — *and* wrote a `found = false` mapScan cache entry,
   which then suppressed that player for `scanCacheFailureDuration` (10s). So one dropped
   caller turned into a second wrong answer plus a poisoned cache.

Reachable inside a single request: on the HIGH path `RunMapCheck` arms a 0.3s parallel
`startMapScan` while `CheckPlayerViaWho` is still running, and a WHO failure is rerouted by
`TryMapFallbackForWho` (`location/who.lua:70`) into a *direct* `MapScan` call for the same
player — which bypasses cascading's own `mapScanTriggered` guard entirely. Two scans, same
name. (Note this became *more* reachable with the priority fix above, which is what put
the two paths in play together; before it, the 0.3s timer never armed.)

**Fix:** entries hold a `callbacks` list and a second scan for an in-flight player attaches
to it instead of registering — the same shape as `WhoService`'s queue dedupe (section 2)
and `pendingPhaseCheckWaiters`. Both resolution sites now clear the entry *before*
dispatching, so a callback that re-enters `MapScan` registers fresh rather than attaching
to a scan that is already resolving, and each callback is pcall'd so one throwing hook
continuation can't strand the others. The attaching caller inherits the running scan's
timeout window rather than getting its own — a HIGH caller attaching to a NORMAL scan waits
up to 5s instead of 2.5s, which its own cascading deadline covers.

New spec `tests/unit/location_dispatch_spec.lua` (12 tests) covers all three; verified
9 fail against the original code. Added a frame stub to `tests/mock_wow.lua` — `maps.lua`
builds its `CHAT_MSG_ADDON` listener at file scope, so `CreateFrame` had to exist just to
load it, and `Fire()` lets a spec replay a scan reply through the captured handler.

### `location/who.lua` — reviewed, no defects fixed

- **`checkEntry`'s map-match expression is a no-op**: `result = (mapID and myMapID and
  mapID == myMapID) or true` always evaluates to `true` — the mismatch case is handled by
  the branch above it, and `or true` swallows every other outcome. It reads like a
  conditional and isn't one. Left alone: the value it produces is the correct one.
- `WHO_FALLBACK_SOURCES` is rebuilt on every `CheckPlayerViaWho` call despite being a
  constant; it belongs at file scope like the same file's other locals.
- **Verified sound:** `source` can never arrive `nil` or non-string at the `source:find`
  calls in `cascading.lua:236` — checked every `callback(` site in `WhoService`. The one
  that passes a table (`pending.callback(true, playerList)`, WhoService.lua:565) is the
  `scanMode` path, which is only reachable via `ScanZoneForPlayers`, a different entry
  point that never routes through `CheckPlayerViaWho`.

### `features/stages/LocationStage.lua` — **HIGH: a finished request's timer tore down the next one** (fixed)

`LocationStage` arms a `C_Timer.After(30, ...)` give-up handler that deletes
`pendingLocationChecks[playerName]` **and** all three hook-layer burst queues
(`pendingChompSends` / `pendingTRP3Sends` / `pendingMSPReplies`) for that player. Its only
guard was `if TRP3FW.pendingSends[sendId] then` — read as "this check never resolved".

Nothing cleared `pendingSends[sendId]` when a check *did* resolve. The start-phase branch
cleared it (LocationStage.lua:114); the normal cascading callback did not. `CacheService`'s
sweeper only prunes `pendingSends` at 60s — twice the timer's delay — so the entry was
guaranteed to still be there. **The guard was therefore always true and the teardown ran for
every single request, 30 seconds after it completed.** And because `CheckLocationCascading`
has an unconditional 2.0s deadline (N2), a genuinely hung check barely exists — so in practice
essentially every firing of this timer was spurious.

Harmless while the player is idle, because it deletes already-nil keys. The damage is when a
*second* request from the same player started a check inside that 30s window — routine for
anyone actively RPing near you, and near-certain during incoming spam, which is exactly when
this state matters. The older request's timer then deleted the **newer** check's tracking
entry and its queued sends. Those requests were never replayed: not sent, not ghosted, not
blocked. `ReplayQueuedRequests`' own `if not pendingLocationChecks[playerName] then return end`
guard swallowed the loss, and `BurstStage` stopped seeing an in-flight check, so subsequent
requests started redundant parallel checks instead of queueing. Symptom: a profile
intermittently just never arrives, with nothing in any log.

**Fix (two halves, since either alone leaves a hole):**
1. The cascading callback now retires `pendingSends[sendId]`, restoring the guard's intended
   meaning — matching what the start-phase branch already did.
2. `pendingLocationChecks` entries carry the `sendId` that owns them, and the timer only tears
   down a check that is still its own. This is what protects the hook-layer queues, which are
   keyed by player and have no other owner marker.

New spec `tests/unit/location_stage_timer_spec.lua` (9 tests), including a test that the
give-up path still works for a genuinely hung check — so the fix can't be mistaken for
"disable the timer". Verified 3 fail against the original code.

### `features/stages/SPVPStage.lua` — **per-phase SPVP opt-out did nothing** (fixed)

`spvpPerPhaseOverrides` — the user-facing "disable SPVP for this phase" setting — had no
effect. `SPVPStage` declines by returning `{ handled = false }` **without setting
`context.spvpEnabled`**, so the field stayed `nil`. `LocationStage` forwards it as
`options.spvpEnabled`, and `CheckLocationCascading` has a late-resolution block
(`location/cascading.lua:423`) that fires precisely on `spvpEnabled == nil` and re-derives the
answer from live prefs plus salt presence — knowing nothing about per-phase overrides. So the
opt-out was silently reversed downstream and the SPEKE handshake ran anyway.

The root cause is that `nil` had to carry two meanings: "no opinion yet, salt still loading"
(where late resolution *is* the intended mechanism) and "deliberately off". **Fix:** deliberate
declines now set `context.spvpEnabled = false`; `nil` is reserved for the salt-loading case.
This also closes a TOCTOU gap — the master-toggle branch honours the settings snapshot, but
late resolution re-read the live pref.

**Two more leaks of the same decision, both fixed:**
- **`AlertFastPathStage` built an `options` table and never passed it** to
  `CheckLocationCascading` (LocationStage passes its equivalent). A dead local, so nothing
  flagged it — but it meant the alert-only path discarded the stage's decision entirely.
- **`ProcessLocationDecision`'s SPVP rescue** (`features/decision.lua:553`) re-derives its own
  eligibility rather than reading `context.spvpEnabled`, and checked the phase-169 exclusion
  but not the per-phase override. Fixed in place despite being a section-7 file: leaving half
  of a security control working is worse than the small cross-section diff.

New spec `tests/unit/spvp_stage_override_spec.lua` (12 tests); verified 9 fail against the
original code. Also hardened `context.settings` indexing in the override lookup — line 27
guards it, line 71 did not, and a context without settings crashed there.

### `features/pipelines/DecisionPipeline.lua` — comment drift (fixed)

Logged "initialized with 8 stages" while adding 7, numbered them 1, 2, 4, 5, 6, 7, 8 (no 3),
and every stage file's header comment carried a *different* number again (`CacheStage` said 5
where the pipeline said 4, `LocationStage` said 6 where the pipeline said 8). Cosmetic, but
this is the file you read to answer "what runs before what", and it is printed into debug
output that gets pasted into bug reports. Count is now derived from `#pipeline.stages`,
numbering is contiguous, and the stage files match.

### `features/stages/CacheStage.lua`, `InteractionStage.lua`, `WhitelistStage.lua`, `BurstStage.lua` — no defects fixed

- **`WhitelistStage` — verified clean on the key-form question** that produced 30ee55c and the
  `AllowSender` bug. `IsPlayerWhitelisted` and `RefreshWhitelistCache` (`core/utils.lua:710`,
  `:728`) normalise identically — `SanitizePlayerName or CleanPlayerName`, then `:lower()` —
  so an apostrophe name matches on both the write and read side.
- **`CacheStage`'s different-phase fast-fail reaches `ApplyLocationDecision` with
  `context.isFirstTime` / `suppressedCount` unset** (only `LocationStage` populates them).
  Those two are read at `decision.lua:421-422` and passed *only* to the legacy
  `ShowChatNotification` fallback, which fires solely when `NotificationService` is missing —
  so this is unreachable today. Noted rather than fixed because the right fix is deleting the
  fallback, which is a section-7 call. Same shape as the section-2 `Notify` bug: a value
  computed on one path and assumed present on another.
- **`InteractionStage:113`** — `if not suppressInteractionNotification and not isMutualExchange`
  is redundant; `suppressInteractionNotification` is `isLiveInteraction or isMutualExchange`,
  so the second clause can never change the outcome. Left alone: provably equivalent, and
  rewriting it adds diff noise to a bug-hunt pass.
- **`InteractionStage`** records no cache stat for a *live* target/mouseover match — it sets
  `hadInteractionCacheHit`, which suppresses the miss counter without incrementing the hit
  counter. Defensible (a live match isn't a cache hit) but it means hits + misses ≠ requests,
  which matters if the Status tab's hit rate is ever read as a percentage of traffic.
- **`BurstStage`** — the queue-cap and `TrackAddonRequest` gaps are on the deferred list above.

### `core/Context.lua` — reviewed, one fix applied

- **Fixed:** `GetTimestamp()` read `self.timestamp`, but real decision contexts store their
  clock snapshot as `now` (`TRP3FW:CreateDecisionContext`, `features/decision.lua`). Wrapping a
  live context would therefore have missed the snapshot and silently returned a *fresh* clock
  read — defeating the TOCTOU guarantee the snapshot exists to provide. Now reads
  `self.now or self.timestamp`, and the fallback uses the frame-cached
  `TRP3FW:GetCurrentTime()` instead of raw `GetTime()` (project convention). Two regression
  tests added to `tests/unit/pipeline_spec.lua`.
- **Open:** `TRP3FW.Context` is **not used by any production code**. The only callers of
  `Context:New` are in `tests/unit/pipeline_spec.lua`; the real pipeline context is a plain
  table from `CreateDecisionContext`, and `Pipeline:Run` treats it opaquely, so `GetTimestamp()`
  is never called in game. The class still ships via the .toc. Decide later whether to adopt it
  in `CreateDecisionContext` or drop it — until then its tests give coverage credit for an
  abstraction nothing exercises.
- **Noted, not a bug:** `New(data)` wraps the caller's table in place, clobbering any existing
  metatable. `pipeline_spec.lua` pins in-place wrapping as the intended contract.

### `core/EventService.lua` — **HIGH: callback silently dropped mid-dispatch** (fixed)

`Trigger` walked the live `self.callbacks[event]` array with `ipairs` while callbacks were
free to mutate it. `location/phase.lua`'s batch phase-check registers a one-shot
`TARGET_CHANGED` handler that, from *inside its own invocation*, unregisters itself
(`finishStep`, phase.lua:600) and registers its successor (`processNext` → phase.lua:652).

`UnregisterCallback`'s `table.remove` shifts every later entry down one, so `ipairs` then
skipped the callback that moved into the vacated slot. The other `TARGET_CHANGED` listener is
`CacheService`'s `OnInteractionEvent` (CacheService.lua:772) — the interaction-cache tracker,
which phase.lua itself calls the "strongest In Phase signal". So during batch phase checking
the interaction cache was missing precisely the target events it most needed. `RegisterCallback`
also runs `table.sort` on the same array mid-walk, which can reorder entries the loop has yet
to reach and run one twice.

Both listeners use the default priority 50, and `table.sort` is unstable for equal keys, so
which one landed first — and therefore whether the bug bit on a given dispatch — varied between
sessions. That is why it only ever showed in game, intermittently.

**Fix:** `Trigger` now dispatches over a snapshot of the array and skips entries whose `active`
flag was cleared by an `UnregisterCallback` during the same dispatch. Registrations made mid-
dispatch defer to the next event. New spec `tests/unit/event_service_spec.lua` (11 tests);
verified it fails without the fix. Also removed a dead `local now = TRP3FW:GetCurrentTime()`
in `OnEvent` (assigned, never read).

**Worth checking in game:** this is a plausible contributor to the intermittent
phase/interaction-cache misbehaviour noted elsewhere. Batch phase checks across several players
are the trigger.

### `core/ServiceContainer.lua` — robustness (fixed)

- `InitializeAll` had no error isolation. Because the loop runs in `pairs` order — arbitrary and
  varying per session — one throwing service left a *different* arbitrary subset uninitialized
  each login, with symptoms unrelated to the actual culprit. Each `Initialize` is now pcall'd
  and logged.
- `Register` validated that `service.GetName` exists but not that it returned anything;
  `self.services[nil] = service` is a hard "table index is nil" error that would abort the
  registering file's load. Now guarded with a clear message.
- **Not a bug:** the `pairs` ordering is currently safe. The one real constraint is that
  EventService initializes first (other services call `ES:RegisterCallback` from their own
  `Initialize`), and that is special-cased. Every other cross-service `ServiceContainer:Get`
  is in a runtime method, and `Get` only needs the service *registered* (file-load time), not
  initialized.

### `core/Service.lua`, `core/Stage.lua` — clean

Both are small factories with the singleton-vs-instance tradeoff already documented in-file
(Service.lua:9, Stage.lua:9). No defects found.

### `core/Pipeline.lua` — clean, one item to confirm during section 3

No defect in the file. But note `Run` returns `{ handled = false }` on full fall-through, and
`CheckLocationAndNotify` (decision.lua:214) returns `result.allowed` — which is then `nil`,
indistinguishable from an explicit block. Harmless only as long as `LocationStage` (the last
stage) always returns `handled = true`. **Verify that when section 3 is reviewed.** Also note
`Run` does not pcall `stage:Process`, so a stage error propagates into the intercepting hook;
whether to contain that is a design call best made with the stages in view.

### `core/cache_interface.lua` — LRU list integrity (fixed)

- **`MoveToTail` corrupted the list instead of protecting it.** The `if not nextKey then return`
  guard sat *after* the previous-side detach, so on a desynced node it unlinked the node from
  its predecessor and returned without re-attaching — orphaning it. With `prevKey == nil` it
  also set `cache.head = nil` while `cache.size` stayed > 0, which permanently disables
  head-based eviction: both `Set` (line ~149) and `PruneIncremental`'s
  `while cache.size > maxSize and cache.head` evict via `cache.head`, so the cache would grow
  past `maxSize` forever. Moved the guard ahead of all mutation so it leaves the list untouched.
  Only reachable from an already-desynced list, but it turned a recoverable inconsistency into
  a permanent one. Regression test added; verified it fails without the fix.
- **`Iterator` dereferenced `cache.data[key]` unguarded**, so removing entries while iterating
  (a natural pattern) would crash on the next step. Only production caller is the read-only
  debug dump at `commands.lua:992`, so this was latent. Now stops cleanly.
- **Added coverage** for `Iterator` and `PruneIncremental`, neither of which had any.
- **Noted, not changed:** TTL comparison is inconsistent — `Get` treats `age >= ttl` as expired
  (line 117) while `Prune` and `PruneIncremental` use `> ttl`. An entry at exactly `age == ttl`
  is expired on read but retained by a prune pass. Practically unreachable with float clocks,
  and several TTL specs pin the current boundaries, so left alone deliberately.
- **Verified safe:** `Prune` removes entries while walking `cache.data` with `pairs`, which
  looks wrong but is legal — `RemoveNode` only clears and modifies existing fields, never adds
  new ones.

### `core/feature_flags.lua` — clean

Only `enableRefactorLogging` remains and it is consumed. Flags are not persisted, so they reset
each reload — fine for a debug toggle, but the file header's "instant rollback without git reset"
claim slightly oversells it. Cosmetic only: the slash handler prints usage via `print` rather
than `TRP3FW:Info`, unlike the rest of the command surface.

### `core/init.lua` — **HIGH: settings bled across profiles** (fixed)

`LoadProfile` backfills any default key the active profile is missing. Table-valued defaults
(`ghostProfileOverrides`, `spvpPerPhaseOverrides`) were assigned **by reference**, so
`defaultSettings` and every profile that backfilled the key all pointed at one table.

This is not a corner case. Profiles saved before those settings were added lack the keys, so
any upgrading user hits it on the first profile switch (`ui/settings.lua:160` calls
`LoadProfile` from the profile-switch dialog). The UI mutates these tables in place —
`ui/tabs/Alerts.lua:328-339` writes `ghostProfileOverrides` element-by-element — so an override
configured on one profile appeared on all of them, and on every profile subsequently created
from `defaultSettings` (`init.lua:596`). Within a session the profiles were, in effect, one
profile for these settings.

**Fix:** deep-copy table defaults on backfill. New spec `tests/unit/profile_isolation_spec.lua`
(12 tests, also covers `MigrateSettings`); verified 3 fail without the fix, including the
user-visible "an override set on Default must not appear on Alt".

**Noted, not changed:**
- `TRP3FW.Prefs = TRP3FW.defaultSettings` (init.lua:243) aliases Prefs to the defaults table as
  an early-access fallback. `LoadProfile` replaces it, so the window is small — but if
  `MigrateSettings` ever throws, every settings write for that session silently mutates
  `defaultSettings`, and new profiles are then born polluted. A copy would be safer; left alone
  because the nested-table semantics need thought.
- `TRP3FW_DB.global.version` is only set when the DB is first created, so it records the
  install-time version forever, not the current one. Nothing reads it today — but anything that
  keys a future migration off it would be reading a stale value.
- `profiler.stop` does `table.remove(stats.calls, 1)` once the 1000-sample buffer is full —
  an O(n) shift per measurement, inside the profiler itself. Only active when profiling is on,
  but it distorts what it's measuring. A ring buffer would be O(1).

### `core/utils.lua` — phantom setting removed; one perf claim doesn't hold

- **Fixed: `phaseRefreshCooldown` was a phantom setting.** It appeared *only* in
  `ValidateSettings`' bounds table and existed nowhere else — not in `defaultSettings`, never
  read, never written. So every login it read as nil, failed the type check, logged a misleading
  `[SECURITY] Invalid phaseRefreshCooldown: nil, resetting to 0`, and wrote the phantom key into
  the user's saved profile permanently. Entry removed, with a comment explaining the invariant
  (every name in that table must exist in `defaultSettings`) so it doesn't recur.
- **Fixed:** four debug closures in `RunPrivilegedSafe` concatenated `category` unguarded while
  the rest of the function used `tostring(category)`. A nil category turned the message into
  `<Error evaluating debug message>` (contained by `Debug`'s pcall, so never a crash — just
  lost diagnostics at exactly the moment you want them). Now consistent.

- **⚠ Open — `GetCurrentTime`'s frame cache saves nothing** (utils.lua:145). The comment claims
  it "eliminates ~95 syscalls per request" and CLAUDE.md's performance guidance is built on that
  claim, but the function calls `GetTimePreciseSec()` **unconditionally on the first line**,
  before consulting the cache. The syscall happens on every single call. `cachedTime` /
  `cachedTimeFrame` are read nowhere else in the codebase (verified), so the machinery is
  entirely self-contained and is pure added cost — a multiply, a floor, two table reads and
  sometimes two writes *on top of* the syscall it was meant to replace. It is strictly slower
  than calling `GetTimePreciseSec()` directly.

  Not fixed: a real frame cache needs a per-frame signal (an OnUpdate-driven counter on
  `TRP3FW.frame`), which is a design change to a function called from everywhere, and the
  headless harness stubs `GetCurrentTime` so the suite would not catch a regression. **Decide
  whether to build the real cache or drop the machinery and the claim.**

- **Noted, not changed:** `GetAvailablePrivilegedTokens` returns the raw bucket without
  subtracting `RESERVED_TOKENS`, even though its comment says it "mirrors RunPrivilegedSafe
  defaults". NORMAL-priority categories (including `phase_check_target`) can't use reserved
  tokens, so `location/phase.lua:356` sizes batches against ~2 more tokens than it can actually
  spend, and the tail of a batch can take `rate_limit` rejections. Fixing it properly means
  passing the caller's priority in.
- **Noted:** `CleanPlayerName` / `SanitizePlayerName` return nil when `SecurityService` isn't
  available, which would make `RefreshWhitelistCache` silently drop every entry. Only reachable
  if the whitelist is refreshed before service init; current call paths run well after login.

### `features/services/WhoService.lua` — **HIGH: WHO checks failed shut while a zone query was in flight** (fixed)

`CheckPlayer` has a "the last zone scan was recent and complete, so a player who wasn't in
it genuinely isn't in this zone" shortcut that answers `false` **without querying**. Its
premise is the pair `lastZoneQueryTime` / `lastZoneResultCount`. Two independent ways that
pair lied:

1. **Both start at 0**, and `0` is indistinguishable from "scanned at t=0, found 0 players,
   therefore complete". The clock is `GetTimePreciseSec()` — *client uptime* — so while
   uptime was under 60s, `now - 0 < 60` held and **every** WHO check short-circuited to
   not-found. Anyone who reached the world quickly after launching had location checks
   silently failing shut until the first minute elapsed.
2. Worse and not time-limited: `lastZoneQueryTime` is stamped when a query is **issued**,
   `lastZoneResultCount` only when results **arrive**. So for the entire in-flight window of
   every zone query, the pair described two different scans — "scanned just now, found N" —
   and the shortcut fired on a stale count. This one has no uptime bound; it recurs on every
   zone query.

**Fix:** the shortcut now requires `lastZoneQueryTime > 0`, and `lastZoneResultCount` is
reset to `nil` (not 0) at init and whenever a zone query is issued, so the pair can never be
half-updated. New spec `tests/unit/who_service_queue_spec.lua`; verified the never-scanned
case fails without the fix, and the in-flight case surfaced *because* a queue test couldn't
enqueue behind a running scan.

**Also fixed in this file:**
- **Queue dedupe silently dropped a callback.** Enqueuing a second query for a player already
  queued **overwrote** the entry, discarding the first caller's callback — that caller was
  never told found, not-found, or timed out, so whatever awaited it just hung. Callbacks are
  now chained onto the surviving slot.
- **`ScanZoneForPlayers` never drained the queue** on timeout or on `RunPrivileged` failure.
  It cleared `pendingQuery`/`cooldownActive` (reopening the gate that made callers queue) but
  nothing pumped the queue, so entries sat until they aged out at 60s as `queue_timeout`.
  Every exit path in `CheckPlayer` already called `ProcessQueue`; these two now do too.
- **Dead `CI:Get("whoZone", playerName)`** whose result was never read. `Get` is not
  side-effect free — it counts a hit/miss and reorders the LRU — so it was skewing the
  whoZone stats the Status tab reports. Removed. (Also removed a duplicated
  `lastZoneQueryTime = 0` in `Initialize`.)

### `features/services/HistoryService.lua` — **history timestamps rendered as 1970** (fixed)

`RecordHistory` and `RecordPerformance` stored `TRP3FW:GetCurrentTime()` —
`GetTimePreciseSec()`, i.e. seconds since the client started, **not** a Unix epoch. Three UI
sites render those entries with `date(fmt, entry.timestamp)`: `ui/settings.lua` (Status tab
"Recent events"), `ui/tabs/Dashboard.lua`, and `ui/historywindow.lua`'s perf-graph tooltip.
`date()` reads its argument as an epoch, so every event displayed as a time in **January
1970** that drifted with client uptime.

The monotonic value can't simply be swapped for `time()` — it's also used for elapsed-time
math (the suppression-window rollup in `ui/settings.lua`, the already-rendered check in
`historywindow`). **Fix:** entries now carry both — `timestamp` (monotonic, for math) and
`wallTime` (`time()`, epoch, for display) — and the three render sites use `wallTime`.

**Also fixed:**
- **Apostrophe names were displayed escaped.** `RecordHistory` preferred
  `SanitizePlayerName`, whose output is escaped for embedding in a `RunPrivileged()` code
  string (`Il'tar` → `Il\'tar`, literal backslash). That value is *displayed* and is used as
  a dedup key in `ui/settings.lua:336`. Now uses `CleanPlayerName`, the canonical form —
  exactly the distinction commit 30ee55c drew for the `allowedSenders` cache key.
- **`TrackAddonRequest` crashed on a nil `sendId`** (`t[nil] = true` is a hard "table index
  is nil"). Not reachable today — every caller supplies one, hooks defaulting to 0 — but it
  runs inside the intercepting hook, where an uncaught error is expensive. Now counts the
  request and skips dedup, matching how WhoService guards the same pattern.
- **Found while here (fixed):** `ui/tabs/Dashboard.lua` read its "recent activity" rows as
  `history[n - i + 1]` under a `-- newest first` comment, but `RecordHistory` inserts at
  index 1, so index 1 *is* newest — the panel was showing its **oldest** entries.

### `features/services/NotificationService.lua` — suppressed-count rollup never rendered (fixed)

`ShouldSuppress` carefully tallies how many notifications it swallowed during a suppression
window and returns that count; `ShowChatNotification` knows how to render it as
`(+N suppressed in last Xs)`. But `Notify` passed a hardcoded `isFirstTime = true` into both
display functions, and the rollup is gated on `not isFirstTime and suppressedCount > 0`. So
the branch was unreachable: the count was computed and thrown away on the only path
production uses. The `(again)` marker and the repeat colour in `ShowOnScreenNotification`
were dead for the same reason.

Only `decision.lua`'s **fallback** path (used when NotificationService is missing — never in
practice) passed a real `isFirstTime`, which is why the dead code read as live.

**Fix:** `isFirstTime = (count == 0)`, matching `ShowStartPhaseBlockNotification`'s existing
semantics. New spec `tests/unit/notification_service_spec.lua` (9 tests); the
`ShouldSuppress` accounting tests passed *before* the fix and the two rollup tests failed,
which is what localised the bug to the `Notify` boundary rather than the tally.

**Noted, not changed:**
- `ShowOnScreenNotification` / `ShowChatNotification` use raw `GetTime()` for their 2-second
  ghost-dedup windows while the rest of the service uses `TRP3FW:GetCurrentTime()`. Each is
  self-consistent (stored and compared with the same clock) so there's no live bug, but it
  violates the project convention in CLAUDE.md.
- `Notify` takes a `settings` snapshot but the display functions read `TRP3FW.Prefs` live, so
  a snapshot is only half-honoured. Harmless today; worth deciding deliberately.
- The four suppression maps (`suppressionHistory`, `startPhaseNotifications`,
  `lastGhost{Screen,Chat}Notification`) grow one entry per unique player and are never
  pruned. Session-scoped and tiny, but unlike every other cache in the addon they have no cap.

### `features/services/SecurityService.lua` — clean, one guard added

- Added a `TRP3FW.Prefs and` guard on the `validatedNamesCacheDuration` read
  (`SecurityService.lua:112`); it was the one unguarded Prefs access in a file where every
  other one guards, and `CleanPlayerName` is reachable from hooks that can fire before
  `LoadProfile`.
- **Verified correct, despite looking wrong:** `SanitizePlayerName`'s negative results are
  cached as the boolean `false`, and `CI:Get` returns `nil, "miss"` on a real miss — so
  `if cached ~= nil then return cached ~= false and cached or nil end` does distinguish
  "known bad" from "not cached". The escaping (`'` → `\'`) is *deliberate* and only for
  `RunPrivileged` embedding; the backslash and double-quote escapes are unreachable because
  `SANITIZE_NAME_PATTERN` rejects both characters first.
- **Noted:** the SPVP redaction patterns assume hex salts — see the deferred item above.

### `features/services/CacheService.lua` — no defects fixed

Reviewed in full. Three items were referred to the deferred list rather than fixed (init-time
snapshot of the interaction refresh threshold; the mouseover read-key/write-key mismatch;
`currentZoneName` alternating between raw and sanitized forms) — each is a behaviour or
perf decision rather than a clear defect.

**Checked and found sound** (all looked suspicious, none are bugs):
- `cleanSendIdTable`'s `maxSendId - 500` threshold is safe: every sendId originates from the
  monotonic `TRP3FW.pendingSendId` counter (`CreateVerifiedSendId`), so ids are ordered.
- The `lastWhoCacheSendIdCount` counter is never incremented (unlike its siblings), but
  `cleanSendIdTable` counts the table itself and ignores the counter, so this is cosmetic
  drift, not a leak.
- `CleanupTableCache(TRP3FW.scanNotificationHistory, ...)` would `pairs(nil)` if that table
  didn't exist; it's created at `core/init.lua:328`.
- `PruneInteractionZoneMismatch` removes nodes while walking the LRU list but captures
  `nextKey` before each removal.

## Notes

- **Section 9 pattern — the code no automated or manual test ever runs.** Every section-9
  bug is in a path a *user types*, and every one is total rather than subtle: three command
  families that crash on their first line, a reset that resets nothing, two documented
  debug categories that print usage instead. This is the opposite of sections 2–4, whose
  bugs needed a second concurrent actor and degraded silently. These would have been caught
  by running the command **once**. The lesson is about coverage shape, not code: the
  in-game testing regime exercises the settings UI, and every setting these commands touch
  is also reachable there — so the entire chat surface went unexercised. `commands.lua` is
  the third-largest file in the addon and had **zero** tests before this pass.
- **Corollary for the deferred list:** the `args` bug means any past report of "`/trp3fw
  batch` does nothing" was accurate and not a misunderstanding. Worth re-checking whether
  the batching tunables were ever really tested in game, given section 8 found the four
  sliders for those same settings were also displaying their minimum rather than the stored
  value. Between the two bugs, `phaseCheckBatchSize`/`Delay`/`MinSize`/`InterTargetDelay`
  had **no working read-out and no working write path** outside the settings UI's own
  checkbox handlers.
- Headless suite grew 441 → 501 tests during section 9. Added `SlashCmdList` and the
  zone-text globals (`GetRealZoneText`/`GetZoneText`/`GetSubZoneText`/`GetMinimapZoneText`)
  to `tests/mock_wow.lua` — `commands.lua` registers its handler at file scope, so
  `SlashCmdList` had to exist merely to load it.
- **The checklist is now complete.** All 62 files across 9 sections have been reviewed. What
  remains is the Deferred list above plus the missing `features/encryption/` section, which
  is still not covered by any section (see the deferred item) — three shipping files
  (`spvp.lua`, `spvp_auto_init.lua`, `spvp_handlers.lua`) that are in the .toc and have
  never had a review pass.

- **Section 4 pattern — the wiring between modules, not the modules themselves.** All
  three bugs are at a *seam*, and none is visible from inside either file alone. The
  priority bug needed `trp3_scan_pipeline` and `cascading` side by side; the duplicate
  callback needed `QueuePhaseCheck` and its three resolvers side by side; the map-scan
  overwrite needed `who.lua`'s fallback and `cascading`'s `startMapScan` to be recognised
  as two doors into the same function. Section 2 lost values at a boundary, section 3 lost
  ownership; section 4 lost the *connection* — a field set on one side and read on
  neither, a contract stated in a comment that no caller honours. For sections 5–7:
  **for every option table passed between modules, check that each key is actually read
  at the far end.** `options.priority` was dead for the whole life of the feature and
  nothing — not a log line, not a test — said so.
- The priority fix is the one change in section 4 that alters live behaviour rather than
  just correcting it, and it only affects the scan-reply path. See the ⚠ in its finding;
  worth a look with `/trp3fw debugfilter phase` during an active map scan. Per
  [[epsilon-runtime-bugs-need-live-logs]], the headless suite can't see this one.
- Headless suite grew 339 → 351 tests during section 4.
- **Section 3 pattern — state whose owner is implicit.** Both real bugs here are the same
  shape, and it is a different shape from section 2's. Section 2 lost values at a boundary;
  section 3 loses *ownership*. `pendingLocationChecks[playerName]` and the three hook queues
  are keyed by player alone, so a request could not tell "my check" from "someone's check for
  the same player" — the fix was to add the owner tag. `context.spvpEnabled` used `nil` for
  both "no opinion" and "deliberately off", so a downstream default could not tell which — the
  fix was to make the decision explicit. Worth carrying into sections 4 and 5, which are full
  of player-keyed state with async lifetimes: **for each shared table, ask who owns an entry
  and how a second writer would know.**
- Both bugs are invisible to logs and to the headless suite as it stood, and both need a
  *second concurrent actor* to show up — which is why they read as "intermittent" in game.
  The LocationStage one in particular is a candidate explanation for profiles that
  occasionally never arrive from a nearby, actively-RPing player.
- Headless suite grew 318 → 339 tests during section 3.
- **Section 2 pattern:** four of the five bugs fixed here are the *same shape* — a value is
  computed correctly and then discarded or misread at a boundary (the suppressed count at
  `Notify`; the monotonic clock at `date()`; the escaped-vs-canonical name at the history
  write; the result count at the zone-completeness read). None of them throw, so none appear
  in an error log; they degrade silently into wrong output or a wrong decision. Worth
  scanning later sections specifically for producer/consumer disagreements rather than only
  for crashes.
- Headless suite grew 298 → 318 tests during section 2. Added
  `UpdateAddOnMemoryUsage`/`GetAddOnMemoryUsage` to `tests/mock_wow.lua` — without them the
  `performanceHistoryEnabled` branch of `RecordPerformance` was untestable.
- **Test-harness caution learned here:** the first draft of the WhoService spec set
  `lastZoneResultCount = nil` in its setup where production's `Initialize` set `0`, and the
  test passed against the buggy code. Harness state must mirror `Initialize` exactly, zeros
  included, or a spec silently tests a state production never reaches.
- `PhaseInStage` mentioned in `CLAUDE.md`'s architecture overview does not exist in the codebase; the actual stage is `SPVPStage.lua`. Docs may be stale on this point — worth reconciling once the stages pass is done.
- **Testing convention established during section 1:** every fix here got a regression test that
  was verified to *fail* against the original code before being kept. Worth continuing — two of
  the section-1 bugs (EventService dispatch, profile aliasing) were order-dependent and would
  otherwise have been easy to "fix" without proof.
- Headless suite grew 271 → 298 tests during section 1.
- `features/ghostmode_trp3.lua` is not mentioned in `CLAUDE.md`'s file structure listing — confirm whether it's a newer split-off from `ghostmode.lua` and whether docs need updating.
- Heaviest files (700+ lines): `CacheService.lua`, `init.lua`, `historywindow.lua`, `utils.lua`, `profileswitch.lua`, `TabManager.lua`, `phase.lua`, `settings.lua`, `commands.lua`. These 9 files are ~9,300 lines combined (over 40% of the codebase) — budget more time/windows for them.
