# Settings Migration Specification: Per-Character Configuration

**Status:** Completed
**Created:** 2026-01-31
**Completed:** 2026-02-03
**Objective:** Transition `TRP3FW.Prefs` from a flat Account-wide structure to a Profile-based structure to support Per-Character settings while preserving existing user data.

## 1. Problem Statement
Currently, `TRP3FW.Prefs` is a global SavedVariable shared across all characters on an account. Changing settings on one character affects all others. Users need the ability to configure the firewall differently for different characters (e.g., stricter settings for a public RP character, looser for a guild officer).

## 2. Implemented Solution
We implemented a **Profile System** within the existing account-wide database.

### 2.1. Database Structure Changes

**Legacy (Flat):**
```lua
TRP3FW.Prefs = {
    notifyEnabled = true,
    suppressionTime = 600,
    -- ...
}
```

**New (Profile-based):**
```lua
TRP3FW_DB = {
    global = {
        -- System-wide settings (e.g., debug toggles, or minimap icon position if unified)
        version = "3.0",
    },
    profileKeys = {
        ["CharacterName - RealmName"] = "Default",
        ["AltName - RealmName"] = "Strict Mode",
    },
    profiles = {
        ["Default"] = {
            notifyEnabled = true,
            -- ... (all character-specific settings)
        },
        ["Strict Mode"] = {
            notifyEnabled = true,
            phaseCheckMode = "block",
            -- ...
        }
    }
}
```

## 3. Implementation Details (Completed)

### 3.1. TOC File Update
The SavedVariables in `TRP3FW.toc` were updated:
*   `## SavedVariables: TRP3FW_DB, TRP3FW.Prefs, ...`
*   `TRP3FW.Prefs` is kept temporarily to facilitate migration from the old flat structure.

### 3.2. Initialization Logic (`InitializeSettings`)

The `InitializeSettings` function in `core/init.lua` now performs the following steps:

1.  **Migration:** Checks if `TRP3FW.Prefs` contains legacy flat data. If so, it migrates it to `TRP3FW_DB.profiles["Default"]` and clears the old table.
2.  **Profile Loading:**
    *   Determines the current character's key (`Name - Realm`).
    *   Looks up the associated profile name in `TRP3FW_DB.profileKeys`.
    *   Defaults to "Default" if no profile is assigned.
3.  **Runtime Proxy (`TRP3FW.Prefs`):**
    *   `TRP3FW.Prefs` acts as a reference to the **active profile table** (`TRP3FW_DB.profiles[activeProfileName]`).
    *   All code references to `TRP3FW.Prefs` were refactored to use `TRP3FW.Prefs`.

### 3.3. Refactoring Strategy

Instead of using metatable magic on `TRP3FW.Prefs`, we performed a codebase-wide refactor:
*   **Renaming:** `TRP3FW.Prefs` (SavedVariable) -> Becomes the legacy container / migration source.
*   **New Global:** `TRP3FW_DB` -> The permanent profile storage.
*   **Runtime Table:** `TRP3FW.Prefs` -> Points to the active profile table.
*   **Global Replace:** Replaced 1,500+ occurrences of `TRP3FW.Prefs` with `TRP3FW.Prefs` in logic files.

### 3.4. UI Updates

A new **Profiles Tab** was added to the Settings UI (`ui/settings.lua`):
*   **Active Profile:** Displays the current profile name.
*   **List:** Shows all available profiles.
*   **Actions:**
    *   **Switch:** Change to a different profile (requires Reload UI? No, updates instantly via `TRP3FW.Prefs` pointer update).
    *   **Create:** Create a new profile (copies current settings).
    *   **Delete:** Delete unused profiles (cannot delete Active or Default).
    *   **Rename:** Rename existing profiles.

## 4. Verification Tests

*   **Fresh Install:** Creates `TRP3FW_DB` with a "Default" profile. Works correctly.
*   **Migration:** Detects old `TRP3FW.Prefs`, moves data to "Default" profile, and clears old var. User settings preserved.
*   **Multi-Character:**
    *   Char A changes a setting.
    *   Char B (on different profile) does not see the change.
    *   Char A logs back in, setting is persisted.
*   **Profile Switching:** User can switch profiles via the UI, and settings update immediately without reload.