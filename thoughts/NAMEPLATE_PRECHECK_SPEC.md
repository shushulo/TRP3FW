# Nameplate Pre-Check — Implementation Spec

**Status:** Proposed, not implemented
**Author context:** Written 2026-07-27 following the phase-check targeting fixes
(`a55582e` + the `exactMatch` change)
**Target branch:** new branch off `v1.6-tests`

---

## 1. Motivation

Phase checking currently proves nearness by *targeting* the player:
`RunPrivileged('TargetUnit("Name", true)')`. That works, but it is expensive and
disruptive:

- It costs a privileged token (rate limit: 10/sec, shared with WHO queries).
- It **moves the player's target**, requiring a restore afterwards. Every bug in this
  module so far — the escaped-name mismatch, the NPC collision, the manual-retarget race
  — has been a consequence of moving the target and then trying to work out whether it is
  safe to move it back.
- It is subject to name collisions. `exactMatch=true` removed superstring matches, and
  `UnitIsPlayer` removed same-named NPCs, but both are *post-hoc verifications of a
  target we already moved to*.

A nameplate pre-check answers "is this specific player visibly nearby?" **without
targeting anything**: zero privileged tokens, zero target disruption, and therefore none
of the restore-related failure modes.

It cannot replace targeting — nameplates only exist for units the client has actually
rendered — so this is a **fast path in front of** targeting, not a replacement for it.

---

## 2. Background: why this is viable

`C_NamePlate.GetNamePlates()` returns the currently visible nameplates, each carrying a
`namePlateUnitToken` (`nameplate1`–`nameplate40`). Those tokens are ordinary unit tokens
usable from **insecure** addon code.

Verified precedent — TotalRP3 ships exactly this pattern:

- `other_addons/totalRP3/modules/NamePlates/NamePlates_Core.lua:440` — iterates
  `C_NamePlate.GetNamePlates()` and reads `nameplate.namePlateUnitToken`
- `other_addons/totalRP3/modules/NamePlates/NamePlates_Core.lua:128` — calls
  `UnitIsPlayer(unitToken)` on that token
- `other_addons/totalRP3/modules/NamePlates/NamePlates_Core.lua:161` — combines
  `UnitIsPlayer` / `UnitIsOtherPlayersPet` guards

**Provenance check (important — the local copy is not a neutral source).** The entire
`totalRP3` family in `other_addons/` is the build **shipped by Epsilon**, so "TRP3 does
it" is not by itself evidence about stock 9.2.7 behaviour. See the provenance table in
§11 — and note the `C_Epsilon` marker check is NOT a valid provenance test.

This specific pattern was therefore confirmed against **genuine upstream** at the matching
tag — `Total-RP/Total-RP-3` tag `2.3.13`, `totalRP3/modules/NamePlates/NamePlates_Core.lua`
— which contains the same `C_NamePlate.GetNamePlates()` / `namePlateUnitToken` iteration
and the same `UnitIsPlayer(unitToken)` calls. That upstream diff is the whole basis for
calling the pattern stock; it does not rest on anything observed in the local copy.

⚠️ **A public wiki page (warcraft.wiki.gg/wiki/UnitToken) claims nameplate tokens do not
work with `UnitName`/`UnitIsPlayer`. That claim is contradicted by upstream TRP3's shipping
code.** Treat the wiki as wrong here, but **still verify in-game** — see §7, Step 0.

⚠️ **No Epsilon-authored addon uses nameplate tokens at all** (checked across EpsilonLib,
Epsilon_*, SpellCreator, PhaseToolkit). Neither do MyRolePlay or XRP (both stock
CurseForge 9.2.7 builds). So the pattern is proven for stock 9.2.7 but has **no precedent
on Epsilon specifically**, and Epsilon runs a modified client. Step 0 is non-negotiable.

---

## 3. Scope

### In scope
- A `location/nameplates.lua` module exposing a synchronous name→result lookup.
- Integration as an early exit in `TRP3FW:CheckPlayerPhase`.
- A `nameplateCheckEnabled` setting (default **on**; it is strictly cheaper than what it
  short-circuits).
- Headless unit tests.

### Out of scope
- Replacing or removing the targeting path. Nameplates are additive.
- Nameplate *scanning for discovery* (enumerating who is nearby). This spec only answers
  "is player X nearby?" for a name we were already asked about.
- Any change to WHO, map scan, or SPVP.
- Any change to the restore logic.

---

## 4. Design

### 4.1 New module: `location/nameplates.lua`

```lua
-- Returns:
--   true          - a nameplate exists for a PLAYER with this exact name (confirmed near)
--   false, reason - a nameplate matched the name but failed a guard (see below)
--   nil           - no nameplate matched; caller must fall through to targeting
function TRP3FW:CheckNameplateProximity(sanitizedName)
```

**Contract notes — read before implementing:**

- The `nil` return is **"unknown", not "not nearby"**. A missing nameplate proves
  nothing: nameplates are capped (~40), can be disabled by the user entirely, and only
  exist for rendered units. Returning `false` on a miss would block every player whose
  nameplate is not currently drawn. **This distinction is the single most important part
  of the spec.**
- The parameter is the **sanitized** name (`SanitizePlayerName` output), because that is
  what `CheckPlayerPhase` has in hand. That value is **backslash-escaped** for
  `RunPrivileged` embedding, whereas `UnitName(token)` returns the **raw** name — so the
  implementation MUST unescape before comparing:
  ```lua
  local liveName = (sanitizedName:gsub("\\(.)", "%1"))
  ```
  This is the exact bug fixed in `a55582e`; do not reintroduce it. See
  `tests/unit/escaped_name_target_match_spec.lua`.
- Comparison must be **exact**, not substring — consistent with the `exactMatch=true`
  change to the targeting calls.
- Must call `UnitIsPlayer(token)` and reject non-players, mirroring the NPC guard in
  `phase.lua`. A nameplate for an NPC named "Grumble" must NOT confirm the player
  "Grumble".

### 4.2 Guards required

| Guard | Reason |
|---|---|
| `UnitIsPlayer(token)` | Same-named NPC must not confirm a player (see `npc_name_collision_spec`) |
| Exact name match | Prevents `Grumble` matching `Grumblesnout` |
| Unescape sanitized name | `UnitName` returns raw names; sanitized names are escaped |
| Skip `UnitIsUnit(token, "player")` | Never confirm proximity from your *own* nameplate |

### 4.3 Integration point

In `TRP3FW:CheckPlayerPhase` (`location/phase.lua:1135`), insert **after** the
sanitize/group-bypass block and **before** the `phaseCheck` cache read (~line 1161):

```lua
if TRP3FW.Prefs.nameplateCheckEnabled then
    local near = self:CheckNameplateProximity(sanitizedName)
    if near == true then
        CI:Set("phaseCheck", sanitizedName, {
            inPhase = true, mapID = C_Map.GetBestMapForUnit("player"),
            timestamp = self:GetCurrentTime(), method = "nameplate",
        })
        if callback then callback(true, "nameplate", nil, "nameplate") end
        return
    end
    -- nil or false: fall through to the existing cache/targeting path unchanged
end
```

Placement rationale: after sanitization (needs a valid name), before the cache read (a
live nameplate is *fresher* than a cached result, and this avoids a stale different-phase
cache entry suppressing someone who is demonstrably standing next to you).

`"nameplate"` is already accepted as a strong nearness signal by
`IsMethodStrong` in `location/cascading.lua:12`, and is already listed as a phase-detection
method in `thoughts/EPSILON_COMPATIBILITY.md`. **No cascading changes should be needed —
confirm this rather than assuming it.**

### 4.4 Caching

Do **not** add a new CacheInterface layer. Write results into the existing `phaseCheck`
cache with `method = "nameplate"`. Rationale: it is the same question with the same TTL
semantics, and a separate cache would need its own invalidation on zone/phase change.

Only cache **positive** results. A `nil` (unknown) must never be cached — it would
suppress a real check for the whole TTL.

---

## 5. Settings

Add to `core/init.lua` `defaultSettings`:

```lua
nameplateCheckEnabled = true,  -- Use visible nameplates as a free proximity fast-path
```

Surface in the Security tab alongside the other location toggles, and add a line to
`thoughts/SETTINGS_REFERENCE.md`.

---

## 6. Test plan (headless)

New spec: `tests/unit/nameplate_precheck_spec.lua`, registered in
`tests/run_headless.lua`.

Mock `_G.C_NamePlate = { GetNamePlates = function() return {...} end }` returning tables
shaped `{ namePlateUnitToken = "nameplate1" }`, and drive `UnitName` / `UnitIsPlayer` per
token.

| # | Case | Expected |
|---|---|---|
| 1 | Player nameplate with exact matching name | `true`; no `RunPrivilegedSafe` call at all |
| 2 | **NPC** nameplate with the same name | not `true`; falls through to targeting |
| 3 | No matching nameplate | `nil` (**not** `false`); falls through to targeting |
| 4 | Superstring name (`Grumblesnout` vs `Grumble`) | no match; falls through |
| 5 | Escaped name (`"'Grumble'"`, `"Shi'kala"`) matches raw `UnitName` | `true` |
| 6 | `C_NamePlate` missing/nil (non-Epsilon, or API absent) | `nil`, no error |
| 7 | Own nameplate (`UnitIsUnit(token,"player")`) | ignored, not a confirmation |
| 8 | `nameplateCheckEnabled = false` | pre-check skipped entirely |
| 9 | Positive result writes `phaseCheck` with `method = "nameplate"` | cache entry present |

**Assert the token-cost property explicitly** (case 1): the whole point is that a
nameplate hit issues **zero** `RunPrivilegedSafe` calls. Spy on it and assert the call
list is empty.

Also add a guard to `tests/harness.lua` defaulting `_G.C_NamePlate` to an empty-list stub,
**resetting it unconditionally per namespace** — the specs share one Lua state and a
previous spec's override will otherwise leak. (This exact leak broke
`location_dispatch_spec` while implementing the NPC guard.)

---

## 7. Implementation steps

**Step 0 — VERIFY THE PREMISE IN-GAME FIRST.** Before writing any module code, confirm on
an Epsilon client that nameplate tokens actually report names and player status:

```
/run for _,p in ipairs(C_NamePlate.GetNamePlates()) do local u=p.namePlateUnitToken; print(u, UnitName(u), UnitIsPlayer(u)) end
```

Expect one line per visible nameplate with a real name and `true` for players. If names
come back `nil`, **the feature is not viable on Epsilon — stop and close this spec.**
Everything below assumes this passed. Note nameplates must be enabled (`V` key) and in
range for output to appear.

1. Step 0 above.
2. Create `location/nameplates.lua` with `CheckNameplateProximity`.
3. Add the file to `TRP3FW.toc` in the Location section (order matters — before
   `cascading.lua`).
4. Add the `nameplateCheckEnabled` default in `core/init.lua`.
5. Wire the early exit into `CheckPlayerPhase`.
6. Write `tests/unit/nameplate_precheck_spec.lua`; register it; add the `C_NamePlate`
   harness default.
7. Run the full suite — must be green, with **no** pre-existing spec changed to
   accommodate the new path.
8. Verify each new test fails with the feature stubbed out (guards against vacuous tests).
9. In-game verification (§8).

---

## 8. In-game verification

Headless tests cannot cover any of this — `C_NamePlate` is mocked throughout.

```
/trp3fw debug
/trp3fw debugfilter phase
/trp3fw profile on
```

1. Stand near a player, trigger a profile request → expect a `nameplate` method result and
   **no** targeting (your target must not move at all).
2. Turn nameplates off (`V`) → expect fall-through to targeting; behaviour unchanged from
   today.
3. Stand near a same-named NPC → must NOT confirm; must fall through.
4. Player out of nameplate range → falls through to targeting; still resolves correctly.
5. `/trp3fw profile report` → privileged token usage should drop measurably in a busy area.

---

## 9. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Nameplate tokens don't expose names on Epsilon | **Blocks feature** | Step 0 verifies before any code is written |
| `nil` (unknown) treated as "not nearby" | **High** — blocks legitimate players | §4.1 contract; test case 3 asserts `nil` not `false` |
| Escaped-vs-raw name mismatch | Medium | Unescape per §4.1; test case 5 |
| Same-named NPC nameplate confirms a player | Medium — false allow | `UnitIsPlayer` guard; test case 2 |
| Nameplate cap (~40) in crowded areas | Low | Miss returns `nil` → falls through to targeting |
| User has nameplates disabled | Low | Same; feature is a pure fast path |

---

## 10. Success criteria

- Full headless suite green, no pre-existing spec modified to accommodate the feature.
- Each new test demonstrably fails with the feature stubbed out.
- In-game: a nameplate-confirmed check issues zero privileged calls and **never moves the
  target**.
- No regression when nameplates are unavailable or disabled — behaviour identical to
  today.

---

## 11. Related

- `location/phase.lua` — targeting path this fronts
- `location/cascading.lua:12` — `IsMethodStrong` already accepts `"nameplate"`
- `tests/unit/escaped_name_target_match_spec.lua` — escaped-name hazard
- `tests/unit/npc_name_collision_spec.lua` — NPC guard precedent
- `thoughts/LOCATION_DETECTION.md` — lists nameplate scanning as a planned method
- `other_addons/totalRP3/modules/NamePlates/NamePlates_Core.lua` — reference implementation

**Provenance of `other_addons/` — read before citing anything in it as evidence:**

| Source | Provenance | Safe to treat as stock 9.2.7? |
|---|---|---|
| `totalRP3`, `totalRP3_Data`, `totalRP3_Extended`, `totalRP3_Extended_Tools`, `totalRP3_Extended_ImpExport` | Shipped by **Epsilon** (whole family) | **No** — verify against upstream `Total-RP/Total-RP-3` at the matching tag |
| `EpsilonLib`, `Epsilon_*`, `PhaseToolkit`, `SpellCreator` | Epsilon-authored | **No** — authoritative for *Epsilon* APIs only |
| `MyRolePlay`, `XRP` | CurseForge | **Yes** — standard 9.2.7 |

When an API question turns on "is this stock WoW behaviour or an Epsilon extension?",
MRP/XRP are the trustworthy in-repo baseline; anything TRP3- or Epsilon-branded needs an
upstream diff before it counts as evidence.

⚠️ **Do not grep for `C_Epsilon` to decide provenance.** Only base `totalRP3` contains such
references (8 files); `totalRP3_Data` and all three `totalRP3_Extended*` contain **zero**
and are still Epsilon-shipped. Absence proves nothing — a customisation can be any
behavioural change. The same caveat applies to the NamePlates module having no `C_Epsilon`
markers: that is why §2 relies on the **upstream 2.3.13 diff**, not on the marker check.

**Doc note:** `CLAUDE.md` lists `location/check_interface.lua`, which does not exist
(the `location/` directory contains only `cascading.lua`, `maps.lua`, `phase.lua`,
`who.lua`). Unrelated to this work, but worth correcting while in the area.
