# Epsilon API Rate Limiting Adaptation Strategy

## 1. Overview
This document outlines the strategy for adapting `TRP3FW` to potential future rate limiting or deprecation of the `C_Epsilon` API on the Epsilon WoW private server. The primary threat is the restriction of `C_Epsilon.RunPrivileged`, which acts as the core mechanism for the firewall's "Secure Phase Verification" (SPVP) and location tracking features.

## 2. Current Architecture (Baseline)

### 2.1 Implementation
*   **Location:** `core/utils.lua` -> `TRP3FW:RunPrivilegedSafe(code, category)`
*   **Algorithm:** Token Bucket
*   **Rate Limit:** 10 calls per second (`RATE_LIMIT` constant).
*   **Logic:**
    *   Fills tokens based on elapsed time (up to max 10).
    *   Deducts 1 token per call.
    *   **Priority System:**
        *   **High:** Can use all tokens (e.g., SPVP security checks).
        *   **Low:** Deferred if tokens < `scarcityThreshold` (e.g., background WHO queries).

### 2.2 Critical Dependencies
The following features rely entirely on `RunPrivileged`:
1.  **SPVP (Secure Phase Verification Protocol):** Verifies a user's location by attempting to target them physically via server command.
2.  **Phase Checking:** Verifies if a user is in the same phase ID.
3.  **Ghost Mode:** Checks real location vs. pretended location.

---

## 3. Threat Scenarios & Impact

| Scenario | Probability | Impact on TRP3FW | Symptom |
| :--- | :--- | :--- | :--- |
| **A. Hard Cap** | High | **Partial Failure.** Server drops calls exceeding its limit (e.g., 5/sec). | `RunPrivilegedSafe` returns true, but server ignores the command. Targeting checks fail silently. |
| **B. Soft Cap (Lag)** | Medium | **Performance Degradation.** Server queues calls. | Checks complete but with 500ms+ latency, causing race conditions in `PhaseInStage`. |
| **C. Deprecation** | High | **Total Failure.** `RunPrivileged` is removed. | All security features break. Addon falls back to "Insecure" map checking. |
| **D. Function Whitelist** | Medium | **Feature Loss.** Specific functions like `SendWho` are blocked. | `TargetUnit` (used by SpellForge) works, but `SendWho` fails silently. |
| **E. Input Sanitization** | Medium | **Execution Block.** Strings containing "SendWho" are rejected. | `RunPrivileged` returns false or error "Forbidden pattern". |

---

## 4. Mitigation Strategy

### 4.1 Immediate Response (Configurable Throttling)
To adapt to Scenario A (Hard Cap), we must lower our internal limit to match or stay below the server's limit.

**Action Plan:**
1.  **Expose `RATE_LIMIT` as a CVar/Setting:**
    *   Currently hardcoded `local RATE_LIMIT = 10` in `core/utils.lua`.
    *   Move to `TRP3FW.constants.lua` or `TRP3FW.Prefs`.
    *   Allow runtime adjustment via slash command: `/trp3fw setlimit 5`.

### 4.2 Intelligent Batching (The "Mega-Call" Pattern)
Epsilon's `RunPrivileged` accepts a string of Lua code. Instead of 5 separate calls, we can bundle them.

**Current Pattern:**
```lua
-- 5 API Calls
RunPrivilegedSafe("TargetUnit('PlayerA')")
RunPrivilegedSafe("TargetUnit('PlayerB')")
...
```

**Proposed "Mega-Call" Pattern:**
```lua
-- 1 API Call
local batch = [[
    local targets = {"PlayerA", "PlayerB", "PlayerC"}
    local results = {}
    for _, t in ipairs(targets) do
        TargetUnit(t)
        results[t] = UnitName("target") == t
    end
    -- Return results via addon channel or hidden frame
]]
RunPrivilegedSafe(batch)
```
*   **Limitation:** `TargetUnit` requires client frame updates. "Mega-Batching" targeting works only if `TargetUnit` is processed sequentially by the server/client within the script execution, which is unconfirmed.
*   **Cost Analysis:** Minimum API calls = `N (targets) + 1 (restore)`.
*   **Threshold:** A limit below **2 calls/sec** renders targeting checks unusable for crowds.

### 4.3 Fallback Protocol (If `RunPrivileged` is Removed)
If Scenario C happens, we must switch to "Native API" mode.

1.  **Detect Capability:**
    *   Check for `C_Epsilon.CastSpell` or `C_Epsilon.TargetUnit` (hypothetical replacements).
2.  **Adapter Pattern:**
    *   Create `features/profiles/adapter_epsilon.lua`.
    *   If `RunPrivileged` is missing, map generic actions (`Target`, `GetPhase`) to specific new C_Epsilon methods.

### 4.4 The "Trojan Horse" Strategy (Whitelisting Bypass)
If Epsilon restricts `C_Epsilon` to only `SpellCreator` (SpellForge), we will proxy calls through SpellForge's global `ARC` API.

**Mechanism:**
1.  **Inject Action:** Use `ARC.RegisterAction` to define a "TRP3FW Secure Check" action.
    *   This registers a callback within SpellForge's environment.
2.  **Execute via Proxy:**
    *   Instead of calling `C_Epsilon.RunPrivileged` directly, TRP3FW calls the registered action.
    *   SpellForge executes the code, and the server sees `SpellCreator` as the caller.

**Proof of Concept:**
```lua
if ARC and ARC.RegisterAction then
   ARC.RegisterAction("TRP3FW", "secure_check", "script", "Security Check", {
      command = function(code)
         -- This runs inside SpellCreator's context
         C_Epsilon.RunPrivileged(code) 
      end
   })
end
```

### 4.5 The "Circuit Breaker" (Function Blocking)
If specific functions like `SendWho` are blocked (Scenario D):
1.  **Detection:** Monitor consecutive timeouts on `WHO_TIMEOUT_SECONDS`.
2.  **Trigger:** If 3 consecutive WHO queries timeout, assume `SendWho` is blocked.
3.  **Action:** Automatically disable WHO backend (`useWhoQuery = false`) for the session.
4.  **Fallback:** System immediately defaults to Map Scanning (slower but reliable), avoiding the 5-10s timeout penalty for every check.

### 4.6 Sanitization Evasion (Scenario E)
If they parse strings to block keywords like `SendWho`:

1.  **String Concatenation (Obfuscation):**
    ```lua
    local f = C_FriendList; local k = "Send".."Who"; f[k](...)
    ```
2.  **Global Table Lookup:**
    ```lua
    _G["C_Friend".."List"]["Send".."Who"](...)
    ```
3.  **Proxy Spell Persistence (The "Vault" Bypass):**
    *   If they sanitize on *save* but not *execution*, the **Persistent Proxy Spell** (Section 6.3 in `spvp_v3_map_exchange.md`) bypasses runtime checks entirely because the server just sees "Run Saved Spell ID X".

### 4.7 "Trust Profile Replies" (The Last Resort)
If all verification APIs (Phase Check, SendWho, Targeting) are blocked, we can fallback to **"Liveness Verification"**.
*   **Logic:** If a player replies to an MSP/TRP3 query (which happens automatically via addon channels), we assume they are present.
*   **Risk:** Epsilon allows cross-phase whispers, so this might allow profiles from other phases.
*   **Implementation:** Add a setting `TrustProfileReplies`. If enabled, receiving any MSP packet treats the sender as "Verified".

---

## 6. Low-Latency UX Strategy (Combating "Choppiness")
If the rate limit drops to extreme levels (e.g., 1 call/sec), we must decouple "Verification" from "Interaction" to preserve fluidity.

### 6.1 The "School Bus" Batching (Technical)
Instead of processing requests FIFO (First-In-First-Out) which creates a queue backlog:
1.  **Boarding Phase:** When a request arrives, start a `0.2s` timer.
2.  **Aggregation:** Any other requests arriving during this window are added to a `pending_batch` table.
3.  **Departure:** At the end of 0.2s, generate **one** `RunPrivileged` script that loops through all targets in `pending_batch`.
4.  **Result:** Verifies 1 or 50 users in a single API call cycle.

### 6.2 Optimistic "Grey" State (Visual)
Never block the UI for a server check.
*   **Action:** Display profile/data *immediately* upon receipt.
*   **Overlay:** Show a subtle "Verifying..." spinner or grey border.
*   **Resolution:** 
    *   **Success:** Spinner vanishes, border turns Green/Invisible.
    *   **Failure:** Collapse content and show "Security Alert: Location Mismatch".
*   **Philosophy:** "Trust but Verify" -> "Show but Redact Secrets".

### 6.3 Predictive Pre-Boarding (Proactive)
Don't wait for the user to click.
*   **Trigger:** On `UPDATE_MOUSEOVER_UNIT` or `NAME_PLATE_UNIT_ADDED`.
*   **Action:** Add unit to the "Low Priority" verification queue.
*   **Result:** By the time the user actually interacts (clicks/trades), the background bus has likely already verified them.

### 6.4 Latency Budget Extension
Since TRP3 protocol is lax (it doesn't "hang up" immediately), we can afford to extend timeouts if the server is slow.
*   **Current Timeouts:** ~5 seconds (`WHO_TIMEOUT_SECONDS`, `SPVP_TIMEOUT_SECONDS`).
*   **Proposed Extension:** If rate limiting is detected (i.e., tokens are empty), dynamically increase timeouts to **10 seconds**.
*   **Impact:** Prevents "Timeout" errors during heavy lag/throttling, relying on the "Optimistic Grey State" to keep the user happy while waiting.

### 6.5 "Invisible Focus" Verification (Targeting Alternative)
To prevent disrupting the user's primary target during checks:
1.  **Mechanism:** Use `FocusUnit("Stranger")` instead of `TargetUnit("Stranger")`.
2.  **Stealth:**
    *   Check if `FocusFrame:IsShown()`.
    *   If shown, temporarily hide it (`FocusFrame:Hide()`) to prevent UI flickering.
    *   Perform Check.
    *   Restore previous Focus (`FocusUnit("OldFocus")` or `ClearFocus()`).
    *   Restore Frame visibility.
3.  **Benefit:**
    *   User's main target (enemy/ally) is never lost.
    *   User can continue casting/attacking while verification runs in background.
    *   Visually seamless (if standard UI).

---

## 7. Implementation Roadmap

1.  **Phase 1 (Hardening):**
    *   Modify `core/utils.lua` to support dynamic rate limits.
    *   Add "Burst Protection" (wait 0.1s between calls even if tokens exist).
    *   Implement "Circuit Breaker" in `location/who.lua`.

2.  **Phase 2 (Optimization):**
    *   Refactor `location/phase.lua` to use "Invisible Focus" strategy by default.
    *   Implement "Pre-Boarding" via `NAME_PLATE_UNIT_ADDED`.
    *   Update `SPVP_TIMEOUT_SECONDS` logic to be dynamic based on current API load.

3.  **Phase 3 (Monitoring):**
    *   Add a "Health Check" tool that counts failed `RunPrivileged` calls (e.g., checks that return `false` or time out) to detect server-side throttling.