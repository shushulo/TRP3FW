# Feature Specification: Remove Icons from Names

## 1. Overview
This feature adds the ability to strip embedded icons from profile names and text fields. This is similar to the existing gradient removal feature and aims to reduce visual clutter and potential abuse of icon embedding in RP profiles.

## 2. Goals
- **Clean Text:** Provide an option to view profile text without embedded icons.
- **Consistency:** Align with the existing "Strip Color Gradients" feature in implementation and user experience.
- **Performance:** Ensure the stripping process is efficient and doesn't introduce significant overhead.

## 3. Technical Implementation

### 3.1. Settings
- **New Setting:** `filterIcons` (boolean)
- **Default:** `false` (Disabled)
- **Location:** `TRP3FW.Prefs`

### 3.2. Core Logic (`core/utils.lua`)
- **New Function:** `TRP3FW:StripAllIcons(text)`
- **Pattern Matching:**
    - Target WoW texture format: `|TtexturePath:height:width...|t`
    - Matches both case variations: `|T`...`|t`, `|t`...`|t` (though usually `|T`...`|t`).
    - **Pattern:** `text:gsub("|[Tt].-|[Tt]", "")`
    - This removes standard WoW icon/texture embeddings used in titles/names.

### 3.3. Hooks (`hooks/icon.lua`)
- **New File:** `hooks/icon.lua`
- **Function:** `TRP3FW:InstallIconHooks()`
- **Logic:**
    - Hook into TRP3/MSP profile reception methods.
    - Apply `StripAllIcons` to the following fields:
        - **MSP:** Name (`NA`), Titles (`NT`), Class (`RC`), Currently (`CU`), OOC (`CO`), Nicknames (`NI`), House (`NH`).
        - **TRP3 Characteristics:** First Name (`FN`), Last Name (`LN`), Title (`TI`), Full Title (`FT`), Class (`CL`), and Misc Traits (`MI`) to catch custom House/Nickname entries.
        - **TRP3 Dashboard:** Currently (`CU`), OOC (`CO`).
    - Mirror the structure of `hooks/gradient.lua` for consistency and performance tracking.

### 3.4. Installer (`hooks/installer.lua`)
- Call `InstallIconHooks()` during the installation phase.

### 3.5. User Interface (`ui/settings.lua`)
- Add a checkbox "Strip Icons from Profiles" in the "Filters" or "General" tab.
- Tooltip: "Remove embedded icons from player names, titles, class, currently, OOC, nicknames, and house fields (requires /reload)".

### 3.6. CLI (`commands.lua`)
- Add CLI support: `/trp3fw filter icon` (toggle).

## 4. Test Plan
1.  **Unit Test:** Verify `StripAllIcons` correctly removes `|T...|t` from strings.
2.  **Integration Test:** Enable setting, reload, receive a profile with icons in the Title. Verify icons are gone from Title but remain in Description if present there.
3.  **UI Test:** Verify checkbox toggles the setting and prints the "reload required" warning.
4.  **CLI Test:** Verify `/trp3fw filter icon` toggles the setting.

## 5. Security Considerations
- **Sanitization:** Ensuring the regex `|[Tt].-|[Tt]` doesn't cause ReDoS. Since `.` does not match newlines by default in many regex engines but Lua's `.` matches all chars? No, Lua `.` matches all characters. However, `.-` is non-greedy. It stops at the first `|t` or `|T`. This is generally safe unless there are mismatched tags.
- **Escape Sequences:** Ensure we don't accidentally strip other things if they look like `|T...|t`. The `|` character is the escape character in WoW, so this pattern is specific to texture strings.

## 6. Future Improvements
- Option to replace icons with text placeholders `[Icon: Name]` instead of full removal.
- Granular control: Remove from Names only, or from Description too.
