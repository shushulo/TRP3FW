# Icon Removal Feature — Specification

**Status:** Partially implemented; Class field gap identified  
**File:** `hooks/icon.lua`  
**Setting:** `TRP3FW.Prefs.filterIcons` (default: `false`)

---

## Overview

The icon-removal feature strips embedded WoW texture strings (`|T...|t`) from incoming profile fields before they are rendered. This prevents other players from embedding large or distracting icons inside their RP profile fields.

The core strip function lives in `core/utils.lua`:

```lua
function TRP3FW:StripAllIcons(text)
    text = text:gsub("|[Tt].-|[Tt]", "")
    return text
end
```

The pattern `|[Tt].-|[Tt]` non-greedily matches any WoW texture tag regardless of case.

---

## Hook Points

`TRP3FW:InstallIconHooks()` (called on `PLAYER_LOGIN`) installs up to three hooks depending on which addon APIs are present:

| Hook | Addon API | Fields covered |
|------|-----------|----------------|
| MSP callback (`msp.callback.received`) | LibMSP | `NA`, `NT`, `RC`, `CU`, `CO`, `NI`, `NH` |
| `TRP3_API.register.ui.sanitizeCharacteristics` | TotalRP3 | `FN`, `LN`, `TI`, `FT`, `CL` |
| `TRP3_API.dashboard.sanitizeCharacter` | TotalRP3 | `CU`, `CO` |

---

## Field Glossary

### MSP fields (LibMSP / `msp.char[senderID].field`)

| Key | Meaning |
|-----|---------|
| `NA` | Name |
| `NT` | Title |
| `RC` | Custom class (free-text) |
| `RA` | Custom race (free-text) |
| `CU` | Currently |
| `CO` | OOC note |
| `NI` | Nickname |
| `NH` | House / guild name |
| `FC` | Character type / faction |

### TRP3 characteristics structure (`TRP3_API.register.ui.sanitizeCharacteristics`)

| Key | Meaning |
|-----|---------|
| `FN` | First name |
| `LN` | Last name |
| `TI` / `FT` | Title (prefix / suffix) |
| `CL` | Custom class |
| `RA` | Custom race |
| `EC`, `AG`, `HE`, `RE`, `BP` | Eye color, age, height, relationship status, birthplace |

---

## Known Gap: Class Field

### Problem

The TRP3 `sanitizeCharacteristics` hook strips icons from `CL` (class) but does **not** strip them from `RA` (race).

Comparing icon coverage against the gradient filter (which is the reference for complete field coverage) reveals:

| Field | Gradient filter (TRP3) | Icon filter (TRP3) |
|-------|------------------------|--------------------|
| `FN` | ✅ | ✅ |
| `LN` | ✅ | ✅ |
| `TI` | ✅ | ✅ |
| `FT` | ✅ | ✅ |
| `CL` | ✅ | ✅ |
| `RA` | ✅ | ❌ **missing** |
| `EC`, `AG`, `HE`, `RE`, `BP` | ✅ | ❌ not covered |

Additionally, on the MSP side the icon filter covers `RC` (class) but not `RA` (race) or `FC` (character type). The gradient filter covers both.

> **User-reported behavior:** Icons embedded in a sender's Class field survive icon filtering because `RA` is absent from the TRP3 hook and `FC`/`RA` are absent from the MSP hook.

---

## Proposed Change

### 1. TRP3 `sanitizeCharacteristics` hook — add `RA`

**File:** `hooks/icon.lua`, line 61–63  
**Current:**
```lua
local fieldsToStrip = {
    "FN", "LN", "TI", "FT", "CL"
}
```
**After:**
```lua
local fieldsToStrip = {
    "FN", "LN", "TI", "FT", "CL", "RA"
}
```

`RA` is the TRP3 custom race field, structurally identical to `CL`; adding it here brings icon coverage into parity with the gradient filter.

### 2. MSP hook — add `RA` and `FC`

**File:** `hooks/icon.lua`, line 34–36  
**Current:**
```lua
local fieldsToStrip = {
    "NA", "NT", "RC", "CU", "CO", "NI", "NH"
}
```
**After:**
```lua
local fieldsToStrip = {
    "NA", "NT", "RC", "RA", "FC", "CU", "CO", "NI", "NH"
}
```

`RA` is the MSP custom race field and `FC` is character type / faction — both are free-text and can contain texture strings. The gradient filter already covers both.

---

## Out of Scope

The following TRP3 fields exist in the gradient filter but are intentionally **not** added to the icon filter in this change:

- `EC`, `AG`, `HE`, `RE`, `BP` — short structured fields (eye color, age, height, relationship, birthplace). Icons are theoretically possible but extremely rare in practice. Can be added in a follow-up.
- TRP3 `About` sections (`T1.TX`, `T2[].TX`, `T3[].TX`) — long-form text; icon stripping would be desirable but is a larger surface area that should be a separate hook block, consistent with how gradient.lua handles it via `sanitizeAbout`.
- Personality traits (`PS`) and misc traits (`MI`) — same reasoning as About.

---

## Testing

Manual verification after `/reload`:

1. Enable icon filter: `/trp3fw filter icons` (or Filters tab in UI).
2. Request a profile from a player who has icons embedded in their Class and Race fields.
3. Open their tooltip — neither field should show any `|T...|t` texture strings.
4. Confirm Name, Title, Currently, OOC, Nickname, House fields are also clean.
5. Disable filter (`/trp3fw filter icons`) and confirm icons reappear (proves hook is the cause).

Edge cases to check:
- Player with icons in Class only, Race only, both.
- Profile sent via TRP3 native protocol (hits `sanitizeCharacteristics` hook).
- Profile sent via MSP/MRP/XRP protocol (hits `msp.callback.received` hook).
- Nil `RA` or `RC` field — should not error (nil guard already present in loop).

---

## Implementation Notes

- No new settings required; the change is additive to existing `filterIcons` logic.
- No `/reload` behavior changes; hooks are installed once at login.
- Performance impact is negligible — the additional fields follow the same loop path already measured by `HistoryService:RecordPerformance`.
- The `NA` nil guard in the MSP hook block is not needed for `RA` or `FC` (no addon depends on them being non-nil), but the existing loop's `if data[field]` check handles nil safely.

---

**Last Updated:** 2026-05-28  
**Covers TRP3FW Version:** 2.9.2-hotfix
