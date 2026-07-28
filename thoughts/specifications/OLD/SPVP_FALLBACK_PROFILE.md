# Feature Specification: SPVP Fallback Profile

**Status:** Implemented

## 1. Overview
This feature allows users to specify a dedicated fallback profile to be sent when **Secure Phase Verification Protocol (SPVP)** fails while in **Required** mode. 

Currently, if SPVP is set to "Required" and verification fails (e.g., timeout or salt mismatch), the request is blocked. This feature provides an option to "Ghost" (send a fake profile) instead of strictly blocking, but *only* for SPVP failures.

## 2. User Story
As a user who wants strict security but plausible deniability, I want to require cryptographic proof of phase presence. However, if that proof fails (indicating the other person is likely not in my phase), I don't want to simply block them (which confirms I exist but am blocking them). Instead, I want to send a specific "Decoy" profile automatically.

## 3. Requirements

### 3.1. Settings
*   **New Setting:** `spvpFallbackProfileID` (String/Nil)
    *   Stores the Profile ID of the profile to use as a fallback.
    *   Default: `nil` (No fallback, standard behavior).

### 3.2. Logic
*   **Trigger Condition:**
    1.  `spvpMode` is set to `required`.
    2.  SPVP verification **fails** (Timeout or Mismatch).
    3.  `phaseCheckMode` is **NOT** set to `block` (or `alert_block`).
        *   *Reasoning:* If the user explicitly wants to "Block" all cross-phase traffic via the main setting, we should respect that strict blocking preference over this specific fallback. If they use "Alert", "Ghost", or "Off", this fallback can apply.
        *   *Refinement:* Actually, if they use "Ghost" mode globally, they already send a ghost profile. This feature is most useful when they might want *standard* behavior normally, but a *specific* decoy for failed security checks, or simply to ensure a ghost send happens even if the global setting wouldn't normally ghost for this specific failure type.
        *   **Simplified Constraint:** If `phaseCheckMode` is strict "Block", this feature is disabled (warn user).

*   **Action:**
    *   Override the decision to `GHOST`.
    *   Use `spvpFallbackProfileID` as the profile source for this specific transaction.

### 3.3. UI Changes
*   **Location:** Settings -> Alerts & Blocking -> SPVP Section.
*   **Widget:** Dropdown Menu (`spvpFallbackProfileDropdown`).
*   **Content:** Same list as the "Ghost Profile" dropdown (Detected Addon Profiles + TRP3FW_BLANK).
*   **Visibility/State:**
    *   Enabled only when `spvpMode` is `required`.
    *   Displays a warning if `phaseCheckMode` is set to `block` or `alert_block`.

## 4. Technical Implementation

### 4.1. `core/init.lua`
*   Add `spvpFallbackProfileID = nil` to `defaultSettings`.

### 4.2. `features/decision.lua`
*   Modify `ProcessLocationDecision`:
    *   Detect SPVP failure case.
    *   Check for `spvpFallbackProfileID` and constraints.
    *   If valid, set `useGhostModeForThisSend = true` and attach `ghostProfileOverride` to the `locationResult` or context.
*   Modify `ApplyLocationDecision`:
    *   Accept override profile ID logic.

### 4.3. `ui/settings.lua`
*   Add the dropdown in the SPVP section.
*   Add update logic to show/hide based on `spvpMode`.
*   Add warning text logic.

## 5. Security Considerations
*   Sending a fallback profile confirms the addon is active and receiving data, whereas "Block" might look like a disconnect or absence. Users should be aware of this trade-off (plausible deniability vs. stealth).
*   The fallback profile itself must be sanitized/safe (standard Ghost Mode protections apply).
