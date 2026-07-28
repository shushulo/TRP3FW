# UI UX Restructure Specification

**Status:** Draft — Pending Review  
**Date:** 2026-04-27  
**Scope:** Tab organization, complexity level assignments, information hierarchy  
**Companion Doc:** [UI_USABILITY_IMPROVEMENTS.md](UI_USABILITY_IMPROVEMENTS.md) (bug fixes)

---

## Framing: Who Are The Users?

Before getting into specifics, it helps to think about the actual population of users at each complexity level:

| Level | Who | What they want |
|-------|-----|----------------|
| **Basic (1)** | New install, casual RP player | "Make it work, don't bother me" |
| **Intermediate (2)** | Regular user, wants some control | "I want to understand what it's doing and tune the basics" |
| **Advanced (3)** | Power user, Epsilon officer/owner | "I want full control over all meaningful behaviors" |
| **Everything (4)** | Developer / debugger | "Show me the internals" |

The current complexity system works mechanically but its assignments reflect **implementation thinking** ("this is a technical setting") rather than **user-need thinking** ("when would a real user want this?"). Several settings are miscategorized in both directions — some things Basic users need are hidden at Level 2, and some things are at Level 3 that regular Epsilon users encounter naturally.

---

## Part 1 — Complexity Level Reassignments

### Settings Currently Too Hidden

#### `blockStartPhase` — Level 2 → Level 1

**Current:** Level 2 (Intermediate)  
**Proposed:** Level 1 (Basic)  
**Reasoning:** Phase 169 (the "Start Phase" / lobby) is where most Epsilon users spend time between events. Being blocked there is a first-session experience for most new users. This is one of the first things they'll ask about. It should be visible immediately at Basic level without needing to know about complexity levels.

---

#### `ghostOnStartPhase` — Level 2 → Level 1

**Current:** Level 2  
**Proposed:** Level 1  
**Reasoning:** Same argument as above — it's the direct follow-up question: "OK you're blocking in start phase, can it send a blank profile instead?" This is a paired option with `blockStartPhase` and should live at the same level.

---

#### `ghostProfileSwitch` — Level 2 → Level 1

**Current:** Level 2  
**Proposed:** Level 1  
**Reasoning:** Auto-switching to a blank profile in phase 169 is the most visible ghost mode behavior and the one users ask about first. It's currently the same level as detailed notification controls like `showAddonSource` and `showCacheInfo`, which is clearly wrong — those are customization; this is a core protection feature.

---

#### `allowGroupPhaseBypass` — Level 2 → Level 1

**Current:** Level 2  
**Proposed:** Level 1  
**Reasoning:** This directly affects whether your party members can see your profile. New users notice this immediately ("why can't my friend see my profile?") and it's conceptually simple. It should be at Basic.

---

#### `useWhoQuery` — Level 2 → Level 1

**Current:** Level 2  
**Proposed:** Level 1  
**Reasoning:** This is a core detection mechanism toggle. Turning it off meaningfully changes what protection the addon provides. A Basic-level user choosing between "Phase check + WHO" vs "Phase check only" is a meaningful decision they can understand. Compare to `showCacheInfo` (also Level 2) which is a cosmetic debug feature — those two should not be at the same level.

---

#### `filterGradients` / `filterIcons` — Level 2 → Level 1

**Current:** Level 2  
**Proposed:** Level 1  
**Reasoning:** These are pure quality-of-life display features with zero complexity — either you want profiles stripped of rainbow gradients and icon spam, or you don't. There is no nuance to understand. Currently a new Basic user sees no filter options at all, which is a missed opportunity for an immediately useful feature.

---

### Settings Currently Too Exposed

#### `showAddonSource` — Level 2 → Level 3

**Current:** Level 2  
**Proposed:** Level 3 (Advanced)  
**Reasoning:** Knowing whether a request came from TRP3 vs MRP vs XRP is diagnostic information, not user-facing. Most people don't know or care what addon their RP partner uses. This belongs alongside other check detail settings at Level 3.

---

#### `showCacheInfo` — Level 2 → Level 4

**Current:** Level 2  
**Proposed:** Level 4 (Everything)  
**Reasoning:** HIT/MISS cache annotations in notifications are purely developer/debugger information. There is no scenario where an Intermediate user benefits from knowing whether a result came from cache. This is noise at Level 2 and should be tucked behind Level 4 with the other internals.

---

#### `showCheckResults` — Level 3 → Level 4

**Current:** Level 3  
**Proposed:** Level 4 (Everything)  
**Reasoning:** "Phase: PASS (nameplate) / Map: FAIL (WHO)" in notifications — this is diagnostic output. An Advanced user tuning their mode doesn't need per-notification method breakdowns; a developer testing the pipeline does. Moving to Level 4 keeps Level 3 focused on behavioral control.

---

#### `refreshSuppression` — Level 3 → Level 2

**Current:** Level 3  
**Proposed:** Level 2 (Intermediate)  
**Reasoning:** This is conceptually simple ("should the suppression window reset when the same player pings again?") and is a natural question Intermediate users have once they notice repeated notifications. Doesn't belong in the same bucket as cache duration numbers and batch sizes.

---

#### `trackHistory` — Level 2 → Level 1

**Current:** Level 2  
**Proposed:** Level 1  
**Reasoning:** "Should the addon keep a log of what it's doing?" is a Basic toggle. It has no complexity — it's on or off. A Basic user who wants to understand what happened needs this. It's currently buried at the same level as technical controls.

---

#### `performanceHistoryEnabled` — Level 3 → Level 4

**Current:** Level 3  
**Proposed:** Level 4 (Everything)  
**Reasoning:** Performance graphs are a developer/profiler tool. An Advanced user managing a phase doesn't need CPU load charts. This belongs at Level 4 alongside the profiler settings.

---

#### `notifyOnBroadcast` — Level 2 → Level 3

**Current:** Level 2  
**Proposed:** Level 3  
**Reasoning:** The distinction between "whisper exchange" and "map scan broadcast" as sources of notifications is genuinely technical. Most Intermediate users don't know or care about the difference. Level 3 is the right home for this degree of notification fine-tuning.

---

#### `suppressAllWhoOutput` — Level 3 → Level 2

**Current:** Level 3  
**Proposed:** Level 2  
**Reasoning:** WHO output flooding in chat is immediately visible and annoying. This is one of the first things Epsilon users want to turn on, and "suppress WHO output" is a simple concept. Level 3 makes it seem scary/advanced when it's actually just a quality-of-life checkbox.

---

#### `spvpMode` / `spvpAutoInitialize` — Level 3 → Level 2 (for mode) / Level 3 (for auto-init)

**Current:** Both Level 3  
**Proposed:** `spvpMode` → Level 2, `spvpAutoInitialize` → stays Level 3  
**Reasoning:** SPVP mode selection ("Off / Optional / Preferred / Required") is a meaningful behavioral choice that an Intermediate Epsilon phase owner needs to make. The dropdown is the important part. `spvpAutoInitialize` is genuinely more advanced (it has security implications around auto-generating keys) and correctly sits at Level 3.

---

### Complexity Level Summary Table (Reassignments Only)

| Setting | Current Level | Proposed Level | Direction |
|---------|--------------|---------------|-----------|
| `blockStartPhase` | 2 | **1** | ↑ more visible |
| `ghostOnStartPhase` | 2 | **1** | ↑ more visible |
| `ghostProfileSwitch` | 2 | **1** | ↑ more visible |
| `allowGroupPhaseBypass` | 2 | **1** | ↑ more visible |
| `useWhoQuery` | 2 | **1** | ↑ more visible |
| `filterGradients` | 2 | **1** | ↑ more visible |
| `filterIcons` | 2 | **1** | ↑ more visible |
| `trackHistory` | 2 | **1** | ↑ more visible |
| `refreshSuppression` | 3 | **2** | ↑ more visible |
| `suppressAllWhoOutput` | 3 | **2** | ↑ more visible |
| `spvpMode` | 3 | **2** | ↑ more visible |
| `notifyOnBroadcast` | 2 | **3** | ↓ less visible |
| `showAddonSource` | 2 | **3** | ↓ less visible |
| `performanceHistoryEnabled` | 3 | **4** | ↓ less visible |
| `showCheckResults` | 3 | **4** | ↓ less visible |
| `showCacheInfo` | 2 | **4** | ↓ less visible |

---

## Part 2 — Tab Reorganization

### Current Tab Structure (Problems)

The current 7 tabs are:

1. **Alerts** — protection modes, ghost profile, SPVP, overrides
2. **Notifications** — notification types, scan reply, suppression, whitelist bypass
3. **Filters** — complexity level, filter settings, addon monitoring, hook safety
4. **Debug** — all cache tuning, batching, rate limits, history, redaction, debug toggles
5. **Profiles** — settings profile management
6. **Status** — live stats, recent activity, cache performance

**Problems:**

- **"Alerts" does too much.** It contains protection modes (what to block) AND ghost mode config AND SPVP AND 20 override rows. These are distinct concerns bundled together. New users hit this tab first and immediately see SPVP cryptographic settings and 20 override fields they don't understand.

- **"Notifications" is misnamed.** It's really "Notifications + Scan Reply Controls + Suppression + Whitelist Bypass." The whitelist bypass in particular is a security feature that has nothing to do with notifications — it's buried at the bottom of a notifications tab behind a red danger box.

- **"Filters" is a junk drawer.** It contains: UI complexity selector, profile content filters, addon monitoring toggles, and hook safety settings. These have nothing in common with each other. Users looking for "how do I stop gradient spam" would not look in "Filters."

- **"Debug" contains the most commonly needed Advanced settings.** Cache durations, batching config, and area-change clearing are things real power users tune. Calling the tab "Debug" signals "stay away" to anyone who isn't a developer.

- **Whitelist bypass is hidden in Notifications.** It's a security/access control feature. Someone looking to whitelist a trusted player's name would look in "Alerts" or a dedicated "Access" section, not "Notifications."

- **SPVP settings span two tabs.** The SPVP section in Alerts handles the security key and mode, while the SPVP cache durations live in Debug. A phase owner managing SPVP has to jump between tabs.

---

### Proposed Tab Structure

Rename and reorganize into 6 tabs (collapsing Filters into Protection, and splitting Debug into Advanced + keeping Status):

---

#### Tab 1: **Protection** (renamed from "Alerts")

*"What does the firewall actually do?"*

**Keep from current Alerts:**
- Quick Presets (stays at top — this is the primary entry point for new users)
- Location Checking section (Phase/Map mode dropdowns)
- Allow Party/Raid Bypass checkbox
- WHO Query toggle (`useWhoQuery`) — **moved up from "Other Options"**

**Move ghost config to a sub-section here:**
- Block in Start Phase
- Ghost Mode in Start Phase
- Auto-Switch to Blank Profile
- Ghost Profile dropdown

**Remove from this tab:**
- SPVP section → move to new **Security** tab (see Tab 3)
- Profile Overrides section → move to **Advanced** tab (fewer users need this)
- "Other Options" non-label → integrate its contents directly

**Why:** Protection tab should answer "what does this do when it fires?" clearly. Keep it focused on modes and immediate behaviors.

---

#### Tab 2: **Notifications** (refocused)

*"How does the firewall tell me what it's doing?"*

**Keep from current Notifications:**
- Enable Notifications master toggle
- Notify on Allow / Start Phase Block / Whisper
- Notification Appearance (chat, screen, sound)
- Suppression settings
- `refreshSuppression` (moved up from Level 3 — see Part 1)
- `showGhostNotifications`

**Move INTO this tab:**
- `suppressAllWhoOutput` — currently in Alerts, more logically a notification behavior
- `notifyOnStartPhaseBlock` (already here, but should be prominent)

**Remove from this tab:**
- Scan Reply Controls → move to **Security** tab (it's an access control feature, not a display feature)
- Whitelist Bypass section → move to **Security** tab (it's access control)
- `notifyOnBroadcast` → Level 3, or move to Advanced
- `showAddonSource`, `showCacheInfo`, `showCheckResults` → Level 3/4 per Part 1

**Why:** Notifications tab should only answer "how am I informed?" — display, sound, suppression. Scan reply controls and whitelist bypass are access control, not notification preferences.

---

#### Tab 3: **Security** (new tab — split from Alerts + Notifications)

*"Who is allowed through and how is that verified?"*

**Contents (drawn from Alerts + Notifications):**
- **Whitelist Bypass** section (moved from Notifications) — danger-styled box stays
- **Scan Reply Controls** section (moved from Notifications) — phase/map behavior for scan replies, nonce, cache, group bypass, scan reply whitelist
- **SPVP** section (moved from Alerts) — mode dropdown, auto-initialize, block duration, salt cache duration, secure phase button and status

**Why this grouping works:** Whitelist = explicit trust grant. Scan reply gate = implicit trust verification for map requests. SPVP = cryptographic trust for phase owners. These are all answers to "who do I trust and how do I verify it?" — a coherent security concern.

**Note:** This tab will be mostly greyed out for non-Epsilon users (SPVP and scan reply controls are Epsilon-only), but the whitelist bypass section is universal. The tab still makes sense for all users.

---

#### Tab 4: **Appearance** (renamed from "Filters")

*"How should profiles look after filtering?"*

**Keep from current Filters:**
- Settings Complexity Level dropdown (move to top — it affects the whole UI)
- Filter Settings (strip gradients, icons, minimum font size)

**Remove from this tab:**
- Addon Monitoring → move to **Advanced** tab
- Hook Safety → move to **Advanced** tab

**Why:** "Filters" as a tab name implies content filtering to most users but currently also contains hook safety settings that have nothing to do with appearance. Rename to "Appearance" and clean it up. The complexity dropdown stays here as it's always been the home for UI meta-settings.

---

#### Tab 5: **Advanced** (renamed from "Debug")

*"Fine-tune how the firewall behaves under the hood."*

**Keep from current Debug:**
- All cache duration settings
- Cache clearing on phase/zone change
- WHO prepopulation settings
- Batching & Rate Limiting
- Cache size limits and timing (phaseInDelay, transitionGracePeriod, etc.)
- History & Redaction settings

**Move INTO this tab:**
- Addon Monitoring (moved from Filters/Appearance)
- Hook Safety (moved from Filters/Appearance)
- Profile Overrides (moved from Alerts/Protection)

**Remove from this tab (keep only in Debug):**
- Debug mode toggles → keep a "Debug" subsection here, or create a separate Debug tab (see below)
- Performance History → move to Status tab (that's where the graphs live anyway)

**Why:** Calling this "Advanced" instead of "Debug" removes the "stay away" signal for power users who legitimately need cache tuning. The debug/developer stuff can stay in a subsection at the bottom, or be split to a separate tab if the tab is too long.

---

#### Tab 6: **Status** (unchanged in purpose, minor additions)

*"What is the firewall currently doing?"*

**Add to this tab:**
- Performance History enable/disable checkbox (currently in Debug — but the graph button and history tracking belong together)
- "Show Graphs" button (already here)

**Keep as-is:**
- Environment info (RP addons, Epsilon API, memory)
- Session statistics cards
- Detection breakdown
- Recent activity table
- Requests by addon bar
- Cache performance bars
- Cache status counts
- RunPrivileged API statistics
- Status refresh rate slider

---

#### Tab 7: **Profiles** (unchanged)

No changes proposed.

---

### Tab Order Recommendation

`Protection → Notifications → Security → Appearance → Advanced → Status → Profiles`

Rationale: Most-used first. New users go left-to-right naturally. Security after Notifications because it's a less frequent task. Profiles last because it's a meta operation.

---

## Part 3 — Section-Level Issues Within Tabs

### Protection Tab: "Other Options" Section Is a Catch-All

The current "Other Options" section in Alerts contains: Ghost Profile dropdown, Epsilon warning, Suppress WHO Output, Block in Start Phase, Ghost on Start Phase, Auto-Switch, Ghost Whitelist. This is not "other options" — these are core ghost mode settings. They should be a clearly named **Ghost Mode** section, not buried under a vague label.

**Proposed section structure for Protection tab:**
1. Quick Presets
2. Location Checking (phase/map modes + WHO + group bypass)
3. Ghost Mode (ghost on start phase, auto-switch, ghost profile dropdown, ghost whitelist)

---

### Notifications Tab: Mode Summary Is Buried

The "Current Modes Summary" text block at the bottom of Notifications is useful but invisible — users scroll past all the notification options to find it at the bottom. Consider moving it to the **top** of the Notifications tab (or the Protection tab), immediately below the presets, so users can see the active configuration at a glance without scrolling.

---

### Security Tab: SPVP Needs Context Before Controls

The SPVP info box currently reads:
> "SPVP uses cryptographic phase verification as a fallback when normal location checks fail. Requires phase owners to set a security key (salt)."

This is good, but it appears after the section header and before the mode dropdown. Users see the dropdown before they understand what SPVP does. The info box should come **first**, followed by the mode dropdown, then the phase-specific controls (secure button, status, sliders).

---

### Debug Tab: Cache Sections Are Not Grouped Visually

The Debug tab has 8+ sequential cache sections separated only by section headers with no visual grouping. After scrolling through Profile Exchange Cache → Interaction Cache → WHO & Zone Cache → Phase & Scan Cache → SPVP Cache Settings → Batching → Cache Limits → Area Change Clearing → History → Redaction → Debug Controls, users have no sense of where they are.

**Proposal:** Add two visual grouping containers (backdrop frames, similar to the scan group in Notifications) to cluster:
- **Cache Durations group**: Profile Exchange + Interaction + WHO & Zone + Phase & Scan + SPVP + Cache Limits
- **Behaviors group**: WHO Prepopulation + Batching + Rate Limiting + Area Change Clearing

This reduces the visual monotony without changing any functionality.

---

## Part 4 — Missing Quality-of-Life Gaps

### 4.1 — No "What Does This Do?" Summary for New Users

At Basic level, users see: phase/map mode dropdowns, notification toggles, filter checkboxes, and the whitelist. There's no brief explanation of what TRP3 Firewall *is* or what the mode dropdowns mean in plain language. A new user set to Basic complexity is dropped into a cold settings panel with no orientation.

**Proposal:** Add a short (2–3 line) description text at the top of the Protection tab that only shows at complexity Level 1:

> "TRP3 Firewall controls who can see your RP profile. Use the dropdowns below to choose what happens when someone from a different location requests your profile."

Hide it at Level 2+ since those users already understand the addon.

---

### 4.2 — Current Mode Summary Is Hard to Find

The "Current Modes Summary" block in Notifications is useful but only shows the current phase/map mode in a small font string at the bottom of a long tab. It's easy to miss. The minimap button tooltip does say "Right-click: Toggle Notifications" but gives no mode info.

**Proposal:** Elevate the mode summary to the top of the Protection tab (most natural home), visible at all complexity levels. Format it as two colored lines:

```
Phase: Alert+Block   Map: Alert+Block   WHO: On   Group Bypass: Off
Start Phase: Block   Ghost: Off   Profile Switch: Off
```

---

### 4.3 — Whitelist Has No Entry Count Indicator

The whitelist text box has no indicator of how many names are currently in it. A user can't tell at a glance if it's populated or empty, and has to scroll through the edit box.

**Proposal:** Add a small `(N names)` counter label next to the "Names (one per line):" header, updated when the text box loses focus.

---

### 4.4 — Ghost Profile Dropdown Shows TRP3 Profiles Only

The ghost profile dropdown populates from `TRP3FW:GetAllProfiles()` which appears to only return TRP3 profiles. Users running MRP or XRP as their primary addon get no profiles in the list. The `(No profiles found)` message gives no hint why.

**Proposal:** When the dropdown is empty, change the empty state message to:
> "(No TRP3 profiles found — TRP3FW_BLANK will be used)"

This sets expectations correctly and explains the fallback behavior.

---

## Part 5 — Map Scan Settings Audit

Map scan settings are spread across three tabs and have inconsistent complexity assignments. Some are never exposed at all because they're missing from `SETTING_LEVELS` entirely (defaulting to Level 4), which hides them from nearly every user.

### 5.1 — Settings Missing From SETTING_LEVELS (Invisible at Level 4)

Two map scan cache settings have **no entry** in `SETTING_LEVELS`, meaning they fall through to the default of Level 4 and are hidden from everyone except "Everything" mode:

| Setting | Default Value | What it does |
|---------|--------------|--------------|
| `scanCacheDuration` | 120s | How long a map scan result (positive) is trusted |
| `scanCacheFailureDuration` | 10s | How long a "not found" result is cached before retrying |

`scanCacheDuration` is the most directly user-impactful of all scan settings — it controls how long the firewall trusts a map scan result before it will do a fresh check. A user seeing repeated scan-triggered checks is almost certainly hitting this setting, yet it's completely hidden unless they're on "Everything." This should be **Level 3**.

`scanCacheFailureDuration` is a retry-timing tunable. It's less important but belongs at the same level as the other failure-duration settings (`phaseCacheFailureDuration` is Level 3 via the Debug tab). **Level 3** is appropriate.

**Proposed fix:** Add both to `SETTING_LEVELS`:
```lua
scanCacheDuration = 3,
scanCacheFailureDuration = 3,
```

---

### 5.2 — Scan Response Behavior Controls (Currently Level 3, Proposed Changes)

The scan reply controls in the Notifications tab are all currently Level 3. Looking at them individually:

#### `scanResponsePhaseMode` / `scanResponseMapMode` — Level 3 → **Level 2**

These are the primary behavior dropdowns for map scan replies — the equivalent of `phaseCheckMode`/`mapCheckMode` but for outgoing scan responses. If a user cares about scan reply security at all, these are the first thing they configure. They're conceptually identical to the protection mode dropdowns (which are Level 1) and should be visible to Intermediate users. Level 3 is too buried.

#### `notifyOnScanResponse` — Level 3 → **Level 2**

The master toggle for whether the addon tells you anything about scan replies. An Intermediate user who has enabled scan reply gating needs to know whether it's notifying them. This is as basic as `notifyEnabled` (Level 1).

#### `scanResponseAllowGroupBypass` — Level 3 → **Level 2**

"Always allow party/raid members to receive your scan reply" is a simple, conceptually obvious setting — the exact same mental model as `allowGroupPhaseBypass` (which is proposed to move to Level 1). Intermediate users understand "my group should always work."

#### `notifyOnScanAllow` — Level 3 → **Level 3** (keep)

Sub-notification for allowed scan replies. Fine at Level 3 — it's a refinement of `notifyOnScanResponse`.

#### `scanResponseAllowCacheBypass` — Level 3 → **Level 3** (keep)

"Skip WHO gate if player is already in allowed/interaction cache" — this is an optimization behavior that requires understanding what the caches are. Level 3 is correct.

#### `scanResponseCacheEnabled` — Level 3 → **Level 3** (keep)

Controls whether WHO results from scan replies get cached. Tuning-level behavior. Level 3 is correct.

#### `scanResponseRequireNonce` — Level 3 → **Level 3** (keep)

Nonce verification for scan replies — compatibility vs. security tradeoff. This requires understanding what a nonce is and why older scanners may not support it. Level 3 is correct.

#### `scanResponseWhitelistEnabled` — Level 3 → **Level 3** (keep)

Whitelist toggle for scan replies. Fine at Level 3 alongside the other whitelist controls.

---

### 5.3 — Map Scan Infrastructure Settings (Debug Tab)

These live in the Debug tab and are generally fine at Level 3, but two deserve a second look:

#### `mapScanMinInterval` — Level 3 → **Level 2**

This controls the minimum seconds between map scans (default: 60s). Users who find the map scanner firing too often or not often enough will look for this. It's the most operationally relevant map scan tuning knob and doesn't require deep technical knowledge to use. Moving to Level 2 makes it visible to Intermediate users who are actively tuning scan behavior.

#### `disableMapScanOnTRP3` — Level 3 → **Level 2**

This is a compatibility toggle for a specific addon combination (TRP3 + RPMapScan). If a user has both installed, this affects whether scan hooks even run. It's a "set once and forget" compatibility setting, not a tuning knob, and Intermediate users who run both addons will encounter the need for this. Level 2 is more appropriate.

---

### 5.4 — Summary of Map Scan Level Changes

| Setting | Current Level | Proposed Level | Reason |
|---------|--------------|---------------|--------|
| `scanCacheDuration` | **missing** (→4) | **3** | Most important scan tuning knob; hidden from everyone |
| `scanCacheFailureDuration` | **missing** (→4) | **3** | Consistent with other failure TTL settings |
| `scanResponsePhaseMode` | 3 | **2** | Equivalent to phaseCheckMode — primary behavior control |
| `scanResponseMapMode` | 3 | **2** | Equivalent to mapCheckMode — primary behavior control |
| `notifyOnScanResponse` | 3 | **2** | Master notification toggle for scan replies |
| `scanResponseAllowGroupBypass` | 3 | **2** | Same mental model as allowGroupPhaseBypass |
| `mapScanMinInterval` | 3 | **2** | Most common scan tuning knob |
| `disableMapScanOnTRP3` | 3 | **2** | Compatibility toggle, not tuning |
| `notifyOnScanAllow` | 3 | 3 | Fine as-is |
| `scanResponseAllowCacheBypass` | 3 | 3 | Fine as-is |
| `scanResponseCacheEnabled` | 3 | 3 | Fine as-is |
| `scanResponseRequireNonce` | 3 | 3 | Fine as-is |
| `scanResponseWhitelistEnabled` | 3 | 3 | Fine as-is |

---

### 5.5 — Tab Placement Note for Scan Response Controls

The scan response behavior dropdowns (`scanResponsePhaseMode`, `scanResponseMapMode`) are proposed to move to the **Security tab** (Part 2, Tab 3). With these now at Level 2, they'll be visible to Intermediate users when they open the Security tab — which is the right place to find "who do I respond to during a map scan?"

`mapScanMinInterval`, `scanCacheDuration`, and `scanCacheFailureDuration` remain in the **Advanced** tab (renamed from Debug) since they're cache/timing tuning knobs, not behavioral controls.

---

## Part 6 — Deeper UX Concerns (Second Pass)

This section covers UX concerns that span multiple tabs or address user journeys rather than individual settings. These are observations from a fresh pass focused on *flow* rather than *placement*.

### 6.1 — The First-Run Experience Has a Gap

The Welcome Wizard offers four complexity levels, then closes. The user is dropped into nothing — no panel opens, no tour, no indication that they should now `/trp3fwui` to configure. From their perspective, they picked a complexity level and… nothing visible happened.

**Observed flow:**
1. Player installs TRP3FW
2. Logs in, wizard appears
3. Picks "Intermediate"
4. Wizard closes
5. *Player has no idea what to do next*

**Proposal:** After complexity selection, automatically open the settings panel to the Protection tab (or new "Welcome" pseudo-tab). The user just told us they want to configure things — show them where to do it.

```lua
-- In ShowWelcomeWizard, after EnforceComplexityDefaults:
b:SetScript("OnClick", function()
    TRP3FW.Prefs.uiComplexityLevel = l[1]
    TRP3FW.Prefs.complexitySetupDone = true
    TRP3FW:EnforceComplexityDefaults(l[1])
    f:Hide()
    -- NEW: Open settings panel so user knows where to find configuration
    if settingsFrame then settingsFrame:Show() end
end)
```

Bonus: For Basic-level users specifically, consider showing a small "Quick Setup Done" toast: "TRP3 Firewall is active in Basic mode. Type /trp3fwui to configure later."

---

### 6.2 — Presets Are the Real Onboarding Tool, But They're Buried

The Quick Presets row at the top of the Alerts/Protection tab is genuinely the most useful feature for new users — five buttons that configure 8–10 settings at once. But:

- They're behind the "Alerts" tab — a user has to know to click that tab first
- There's no indication of which preset (if any) is currently active
- Switching presets silently changes settings without a confirmation or a "You changed: A, B, C" diff
- A user who tweaks individual settings after picking a preset has no way to know they've drifted from the preset baseline

**Proposals:**

1. **Show active preset state.** Track which preset (if any) the user currently matches and visually indicate it. If they've tweaked settings, show "Custom (drifted from Recommended)" instead.

2. **Add a "Reset to Preset" button** that re-applies the last-used preset. Right now, once you tweak after applying "Balanced," your only recovery is to re-click "Balanced."

3. **Show a one-line "what this changes" summary** under the preset buttons before clicking, not just in the tooltip. The tooltip is fine for power users; the under-button text helps everyone:

   ```
   Quick Presets: [Relaxed] [Balanced] [Recommended] [Strict] [Ghosty]
   Currently: Recommended (modified)  •  [Reset to Recommended]
   ```

4. **Move presets to the very top of every tab** (or at least Protection + Notifications). They're the most useful entry point to the addon. Right now they're only on Alerts.

---

### 6.3 — The Minimap Button Is Underutilized

The minimap button currently has only two actions:
- **Left-click:** Open settings
- **Right-click:** Toggle notifications

**Tooltip says:** "Left-click: Settings / Right-click: Toggle Notifications"

This is a missed opportunity. The minimap button is the most-glanced-at piece of TRP3FW UI for active users. It should:

1. **Show current state via icon color or overlay.** Currently it always shows the same Rogue Feign Death icon regardless of mode. Consider:
   - Green tint = passive (Off / Statistics / Alert only)
   - Yellow tint = active blocking
   - Blue tint = ghost mode active
   - Red overlay/dot = recent alert in last 30 seconds

2. **Show stats in the tooltip,** not just the action hints:
   ```
   TRP3 Firewall — Recommended
   ━━━━━━━━━━━━━━━━━━━━━━━
   Phase: Alert+Block   Map: Alert+Block
   This session: 12 alerts, 3 blocks, 0 ghosts
   ━━━━━━━━━━━━━━━━━━━━━━━
   Left-click: Settings
   Right-click: Toggle notifications
   Shift+click: Toggle phase mode
   ```

3. **Add Shift+click as a quick toggle.** Power users would appreciate cycling between "off / alert / block" without opening settings.

---

### 6.4 — Settings Have Hidden Dependencies That Aren't Surfaced

Several settings only do something useful when other settings are also configured. The UI does grey out dependent controls (which is good), but doesn't explain the dependency. A user enabling something and seeing nothing happen has no path forward.

**Examples found:**

- `ghostOnStartPhase` does nothing unless `blockStartPhase` is on. The UI greys it conditionally but no inline note explains why.
- `prepopulateWhoOnPhase` / `prepopulateWhoOnZone` are dependent on `prepopulateWhoCache`. Again, greyed out with no inline explanation.
- `notifyOnScanAllow` requires `notifyOnScanResponse` AND active gating. Two layers of dependency, no inline explanation.
- The whole **Scan Reply** section is greyed out unless gating modes are not "off" — but the section header doesn't say that, the controls just appear dead.
- `redactNames`, `redactLocations`, etc. require `redactEnabled`. No inline note.
- `clearPhaseCheckOnPhaseChange` etc. require `clearCacheOnPhaseChange`. No inline note.

**Proposal:** When a control is greyed out due to a parent dependency, change its tooltip dynamically to explain why. For example:

```
[disabled] Ghost Mode in Start Phase
Tooltip: "Requires 'Block in Start Phase' to be enabled.
         Currently: Block in Start Phase is OFF."
```

This is non-trivial but achievable by walking dependency chains in the tooltip-on-enter handler.

A lighter-weight version: add a small `(requires X)` italic label next to each dependent control.

---

### 6.5 — Status Tab Is Overwhelming for Most Users

The Status tab has roughly **15 distinct sections** stacked vertically:

1. Environment (4 lines)
2. Performance Metrics (4 lines)
3. History Controls (1 line)
4. Session Statistics (3 cards)
5. Detection Breakdown (2 lines)
6. Recent Activity (8-row table)
7. Requests by Addon (bar)
8. Cache Performance (8 progress bars)
9. Cache Status (10 entry counts)
10. RunPrivileged API Statistics (6 lines)
11. Status Tab Settings (slider)

For a regular user wanting to see "is the firewall working?", they have to scroll past 9 sections of cache internals to confirm it. The most user-relevant info (Session Statistics cards, Recent Activity) is sandwiched between performance metrics and cache internals.

**Proposal: Reorder by user relevance:**

1. **At-a-glance status** (NEW, top): Single row showing "Firewall: ON • Mode: Recommended • Last alert: 2m ago"
2. Session Statistics cards (was #4)
3. Recent Activity table (was #6)
4. Requests by Addon bar (was #7)
5. Detection Breakdown (was #5)
6. Environment (was #1) — collapsed
7. Performance Metrics (was #2) — collapsed unless `performanceHistoryEnabled`
8. Cache Performance (was #8) — collapsed by default at Level 2, visible at Level 3+
9. Cache Status (was #9) — collapsed by default at Level 2, visible at Level 3+
10. RunPrivileged API Statistics (was #10) — only visible at Level 4
11. Status Tab Settings (slider) — at bottom, fine where it is

**Implement with collapsible section headers.** Section headers become buttons that toggle visibility of their content. Default state varies by complexity:
- Level 1: Sections 1-5 expanded, rest collapsed
- Level 2: Sections 1-7 expanded, rest collapsed  
- Level 3: Sections 1-9 expanded, RunPrivileged collapsed
- Level 4: All expanded

---

### 6.6 — The "Reset" Button Is Globally Destructive With No Undo

The bottom-right Reset button calls `StaticPopup_Show("TRP3FW_RESET_CONFIRM")` which wipes ALL settings:

```lua
OnAccept = function() TRP3FW.Prefs = {}; TRP3FW:InitializeSettings(); TRP3FW:RefreshUI() end
```

**Problems:**

1. **No undo.** A user who clicks Reset by accident loses their entire configuration including whitelist entries, ghost overrides, cache tunings — everything.
2. **No granularity.** Most users want to reset *one tab* (e.g., "I messed up cache settings, reset just those") not the entire addon.
3. **No backup before reset.** A 5-second snapshot before destructive action would be trivial to add.
4. **The button is right next to "Close"** which makes accidental clicks very plausible.

**Proposals:**

1. **Move Reset away from Close.** Put Close on the right; put Reset on the far left, or behind a "More..." button.

2. **Make Reset tab-aware.** The popup should ask "Reset all settings in this tab, or all settings everywhere?" Buttons: `[This Tab Only] [Everything] [Cancel]`.

3. **Auto-snapshot before reset.** Save a copy of `TRP3FW.Prefs` to `TRP3FW_DB.lastResetBackup` so the user has a 1-click recovery path. Add an "Undo Last Reset" button that appears for one minute after a reset.

4. **Exclude profile data and whitelists from reset.** These are user-curated content, not configuration. A user who created a 50-name whitelist should not lose it because they wanted to reset cache durations.

---

### 6.7 — Naming Inconsistencies Confuse Users

The addon uses several different terms for the same concepts:

| Concept | Variants used |
|---------|--------------|
| "Allow request" | "Allow", "Send", "Pass", "Allowed Sender" |
| "Block request" | "Block", "Refuse", "Silent block", "Reject" |
| "Send blank profile" | "Ghost", "Ghost mode", "Blank profile", "TRP3FW_BLANK", "Ghosting" |
| "Phase 169" | "Start Phase", "Phase 169", "Lobby" |
| "Map" | "Map", "Zone", "Area" |
| "Notification" | "Notification", "Alert", "Message", "Toast" |

In particular:
- **"Alert" is overloaded.** It means both "the firewall detected something" (status) and "tell me about it" (action) and is used for the *tab name* containing protection modes. A user reading "Alert + Block" mode might think this is sequential ("alert me first, then block") when it actually means "do both."
- **"Ghost" vs "Ghosting" vs "Blank Profile"** — three terms for the same feature.
- **"Map" vs "Zone"** — Status tab uses both, sometimes for different things (mapID vs zone text), sometimes interchangeably.

**Proposals:**

1. **Pick canonical terms and apply consistently:**
   - Pass-through → "**Allow**"
   - Stop the request → "**Block**"
   - Send dummy data → "**Ghost**" (verb), "**Blank profile**" (noun)
   - Phase 169 → "**Start Phase**" (more friendly than the number)
   - Notifications → "**Notification**" (status visible to user)
   - Detections → "**Alert**" (firewall noticed something)

2. **Rename the "Alerts" tab to "Protection"** (already proposed in Part 2). This single change resolves a lot of the alert/notification ambiguity.

3. **Make mode dropdown labels more descriptive:**
   - Current: "Alert + Block" → Proposed: "Block (with notification)"
   - Current: "Ghost (Blank Profile)" → Proposed: "Send blank profile"
   - Current: "Alert + Ghost" → Proposed: "Send blank profile (with notification)"

   The current labels assume the user knows what "Alert" and "Ghost" mean separately. The proposed labels read as instructions.

---

### 6.8 — Color/Contrast and Accessibility Concerns

Reviewing the UI for accessibility issues:

1. **Status indicators rely entirely on color.** Cache hit rates use red/yellow/green progress bars with no shape or icon. The performance budget panel uses colored dots. A red/green colorblind user (~8% of men) cannot distinguish "good" from "bad" states.

   **Fix:** Add icons or shapes alongside colors. Green dot → green ✓. Red dot → red ✗. Yellow dot → yellow ⚠.

2. **Some text contrast is weak.** `SetTextColor(0.7, 0.7, 0.7)` is used for many labels (e.g., the cache status labels, Status tab inactive tab text). On a dark background this is borderline against WCAG AA.

   **Fix:** Use 0.85, 0.85, 0.85 minimum for label text. Reserve dimmer colors only for placeholder/empty states.

3. **The `|cffaaaaaa` gray used in many tooltips/hints is also weak contrast.** Same fix.

4. **Font sizes are hardcoded.** Users with vision impairment cannot scale TRP3FW's UI even if they've scaled WoW's UI globally — the addon uses fixed font templates (`GameFontNormalSmall`, etc.) without honoring `UIParent:GetEffectiveScale()` for elements like the recent activity table cells.

   **Fix:** Use `GameFontNormal` (not Small) as the default for any interactive control's label. Reserve "Small" templates for clearly secondary information.

5. **No keyboard navigation.** Tab key doesn't cycle through controls; arrow keys don't move focus between tabs. A user who cannot use a mouse cannot navigate TRP3FW settings.

   This is a larger fix. Documented as a known gap; not blocking.

---

### 6.9 — No Search/Filter for Settings

With 100+ settings spread across 6 tabs, a user looking for a specific setting (e.g., "where is the WHO cache duration?") has to either remember which tab it's on or scan everything.

**Proposal:** Add a simple search box at the top of the settings frame (not per-tab) that:
- Highlights matching control labels in the current tab
- Optionally jumps to the tab containing a match
- Searches both label text and tooltip text

This is a moderately-sized feature but pays off massively for a settings-heavy addon. Even a minimal version (highlight only, no auto-jump) would help.

---

### 6.10 — No Profile Diff / Compare

The Profiles tab lets users create and switch settings profiles, but provides no way to:
- Compare two profiles to see what differs
- Copy a single setting from one profile to another
- See when a profile was last modified

For a power user maintaining "Casual" and "Phase Owner" profiles, the inability to see what differs makes drift inevitable.

**Proposal:** Add a "Compare with active" button next to each non-active profile in the Profiles tab. Opens a popup listing the keys whose values differ:

```
Comparing 'Casual' to 'Phase Owner' (active):
  phaseCheckMode:       alert     →  alert_block   [Copy →] [← Copy]
  whitelistEntries:     (empty)   →  12 names      [Copy →] [← Copy]
  spvpMode:             optional  →  required      [Copy →] [← Copy]
```

This is a moderately complex feature and could be deferred to a future revision, but worth flagging.

---

### 6.11 — Section Anchor Pattern Is Fragile

Every tab uses a manually-tracked `y` variable that's decremented by hardcoded amounts as controls are placed. This pattern has produced several of the layout bugs already documented (Issue 4 and 5 in `UI_USABILITY_IMPROVEMENTS.md`).

A few specific fragility examples noted during this review:

- `Notifications.lua:206` adjusts `scanGroup`'s anchor based on `scanY` — but `scanY` was tracked separately from `y`, and the two variables interact incorrectly (already documented).
- `Alerts.lua` has `y = y - 30` mixed with `y = y - 35`, `y = y - 40`, `y = y - 45`, etc. with no consistent grid. Adding a single new setting in the middle would require manually retuning everything below.
- `Debug.lua` reaches `contentHeight = 3200` — that's a single 3200px scroll child with everything stacked. If any setting renders at a slightly different size than expected, everything below shifts.

**Proposal (long-term, not phase 1):** Build a layout helper that handles vertical stacking automatically:

```lua
-- Conceptual:
local layout = TabManager:CreateVerticalLayout(content, { padding = 10, sectionGap = 25 })
layout:AddSectionHeader("Notifications")
layout:AddCheckbox("notifyEnabled", ...)
layout:AddCheckbox("notifyOnAllow", ...)
layout:AddSectionHeader("Appearance")
layout:AddCheckbox("showInChat", ...)
-- etc.
```

This eliminates manual `y` tracking entirely and makes section reordering trivial. **Not required for this UX pass**, but would prevent future drift.

---

### 6.12 — No "Recently Changed" Indicator

Power users tweaking many settings have no audit trail of what they just changed. If a user reports "the firewall behaves differently than last week," they have no way to recall what they changed in the meantime.

**Proposal:** Maintain a session-level `recentChanges` log in `TRP3FW.sessionStats` that records `{key, oldValue, newValue, timestamp}` whenever a setting changes. Surface this in the Status tab as a "Recent Setting Changes" section (Level 3+).

Lightweight version: just show the last 10 changes with timestamps. No undo needed for a first version.

---

### 6.13 — Suppression Time Default Is Too Long

The default `suppressionTime` is **600 seconds (10 minutes)**. This means after one notification from a player, the user won't see anything else from that player for 10 minutes. For most users this is too long — they'll see one alert and then think the firewall stopped working.

**Proposal:** Change default to **60 seconds (1 minute)**. Most users will set it lower if anything; few set it higher. The sliding-window setting (`refreshSuppression`) is on by default which compounds the long suppression.

This is a default value change, which is technically out of scope for this UX doc, but it's a UX issue (the user *thinks* it's broken). Flagging here for awareness; defaults change tracked separately.

---

### 6.14 — Settings That Should Be Defaults-On Are Off

A few settings are off by default but are arguably what most users want:

- `playSound = false` — most users would benefit from a subtle sound when blocked. Currently silent unless they discover and enable it.
- `showOnScreen = false` — same argument.
- `showGhostNotifications = true` — already on, good.
- `notifyOnBroadcast = false` — fine for advanced users, but Basic users may wonder why broadcasts aren't visible at all.

**Not a recommendation to change defaults** — flagging as a potential conversation. Sometimes "off by default" is intentional to avoid spam, but it should be a deliberate choice rather than an oversight.

---

### 6.15 — The History Window Has Better UX Than the Settings Panel

A small irony noted during review: the standalone History Window (`historywindow.lua`) is genuinely well-designed:
- Graphs with budget lines
- Color-coded performance status
- Filterable context dropdown
- Tooltip-on-hover for individual data points
- Top-5 leaderboards with rank-based coloring

It's better than the Status tab in many ways. **Consider promoting some of its visual idioms back into the Status tab:**
- Budget line concept (good = green, warning = yellow, critical = red) for cache hit rates
- Tooltip-on-hover for cache progress bars showing entry counts and recent samples
- Top-5 most-frequent requesters (we have raw counts but no leaderboard)

The History Window also demonstrates that the addon *can* do good visual design — the Settings panel just hasn't been touched at the same level of care.

---

## Implementation Notes

**Phase 1 (Low risk, high value — pure data changes):**
- Complexity level reassignments (Part 1)
- Map scan level reassignments (Part 5) — add missing entries, adjust existing ones
- Mode summary moved to top of Protection tab
- Ghost Mode section rename
- Whitelist entry count label
- Wizard auto-opens settings panel after complexity selection (6.1)
- Suppression time default (6.13) — flag for separate review

**Phase 2 (Moderate effort — UI restructure):**
- Tab renaming (Filters → Appearance, Debug → Advanced)
- Move WHO query toggle up in Protection tab
- Move Addon Monitoring + Hook Safety to Advanced tab
- Move suppressAllWhoOutput to Notifications tab
- Mode dropdown label rewording (6.7) — "Block (with notification)" etc.

**Phase 3 (Structural — new Security tab + Status reorder):**
- Create Security tab
- Move SPVP from Alerts to Security
- Move Scan Reply Controls from Notifications to Security
- Move Whitelist Bypass from Notifications to Security
- Update scroll frame height estimates for affected tabs
- Reorder Status tab sections by user relevance (6.5)
- Implement collapsible section headers for Status tab (6.5)

**Phase 4 (Polish — feedback and clarity):**
- Basic-level orientation text in Protection tab
- Ghost profile dropdown empty-state message
- Visual grouping containers in Advanced/Debug tab
- Performance History enable checkbox moved to Status tab
- Active preset state indicator on Protection tab (6.2)
- "Reset to Preset" button (6.2)
- Inline dependency labels for greyed-out controls (6.4)
- Color/contrast fixes (6.8) — bump label gray from 0.7 to 0.85, add icons alongside color indicators

**Phase 5 (Feature additions — beyond pure UX cleanup):**
- Minimap button state-aware coloring + stats tooltip (6.3)
- Tab-aware Reset button with auto-snapshot/undo (6.6)
- Settings search box (6.9)
- Profile diff/compare tool (6.10)
- "Recently Changed" log in Status tab (6.12)
- Promote History Window visual idioms into Status tab (6.15)

**Phase 6 (Long-term refactor — optional):**
- Vertical layout helper to replace manual `y` tracking (6.11)
- Keyboard navigation support (6.8)

---

## What NOT to Change

- The 7-stage pipeline and decision logic — UI changes only
- `TRP3FW.Prefs` key names — all settings retain their existing keys
- Default values — no default changes proposed here (separate concern)
- The debug window and history window — standalone windows, not affected
- The profile system structure — Profiles tab stays as-is

---

**Last Updated:** 2026-04-27 (rev 3 — added Part 6: Deeper UX Concerns, expanded implementation phases)  
**Status:** Awaiting review  
**Next step:** Approve Phase 1 (complexity reassignments + map scan fixes + small wizard improvement) separately from structural tab changes  
**Reading order suggestion:** Skim Parts 1, 5, 6 first — these contain the most actionable findings. Parts 2 and 3 are larger structural proposals that can wait.
