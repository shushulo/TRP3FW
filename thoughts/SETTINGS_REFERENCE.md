# Settings Reference

Quick reference for all settings available in `TRP3FW.Prefs` (the active profile).

> **Note:** All settings are now stored per-profile. `TRP3FW.Prefs` is a runtime reference to the currently active profile in `TRP3FW_DB`.

## Notification Settings

### notifyEnabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Master toggle for all notifications
- **Command:** `/trp3fw notify toggle`

### showInChat
- **Type:** boolean
- **Default:** `true`
- **Description:** Display notifications in chat window
- **Command:** `/trp3fw display chat`

### showOnScreen
- **Type:** boolean
- **Default:** `false`
- **Description:** Display on-screen alerts (UIErrorsFrame)
- **Command:** `/trp3fw display screen`

### playSound
- **Type:** boolean
- **Default:** `false`
- **Description:** Play sound on notifications
- **Command:** `/trp3fw display sound`

### suppressionTime
- **Type:** number (seconds)
- **Default:** `600` (10 minutes)
- **Range:** 0-3600
- **Description:** Suppress repeat notifications for same player
- **Command:** `/trp3fw suppress <seconds>`

### refreshSuppression
- **Type:** boolean
- **Default:** `true`
- **Description:** Extend suppression window on new activity (sliding window)

### notifyOnAllow
- **Type:** boolean
- **Default:** `true`
- **Description:** Show notifications for allowed profile sends

### notifyOnStartPhaseBlock
- **Type:** boolean
- **Default:** `true`
- **Description:** Show notifications for start phase (169) blocks

### notifyOnBroadcast
- **Type:** boolean
- **Default:** `false`
- **Description:** Show notifications for broadcast (non-whisper) requests

### notifyOnWhisper
- **Type:** boolean
- **Default:** `true`
- **Description:** Show notifications for whisper (direct) requests

### showAddonSource
- **Type:** boolean
- **Default:** `true`
- **Description:** Display addon source in notifications (e.g., "[via TotalRP3]")

### showCheckResults
- **Type:** boolean
- **Default:** `false`
- **Description:** Show pass/fail/method details for phase/map checks in notifications

### showCacheInfo
- **Type:** boolean
- **Default:** `false`
- **Description:** Append cache hit/miss info to allow notifications

### showGhostNotifications
- **Type:** boolean
- **Default:** `true`
- **Description:** Display chat/on-screen messages when ghost profiles sent

---

## Location Check Modes

### phaseCheckMode
- **Type:** string (dropdown)
- **Default:** `"alert"`
- **Valid Values:**
  - `"off"` - Disabled
  - `"statistics"` - Track stats only (no alerts/blocks)
  - `"alert"` - Alert only (no blocking)
  - `"block"` - Block only (no alerts)
  - `"ghost"` - Ghost only (no alerts)
  - `"alert_block"` - Alert + Block
  - `"alert_ghost"` - Alert + Ghost
- **Description:** Phase checking behavior (Epsilon only)
- **Commands:**
  - `/trp3fw alert phase` - Toggle phase alerts
  - `/trp3fw block alert` - Enable blocking
  - `/trp3fw ghost` - Enable ghost mode

### mapCheckMode
- **Type:** string (dropdown)
- **Default:** `"alert"`
- **Valid Values:** Same as phaseCheckMode
- **Description:** Map/WHO checking behavior
- **Commands:**
  - `/trp3fw alert map` - Toggle map alerts
  - `/trp3fw block alert` - Enable blocking
  - `/trp3fw ghost` - Enable ghost mode

---

## Ghost Mode Settings

### ghostOnStartPhase
- **Type:** boolean
- **Default:** `false`
- **Description:** Send blank/ghost profiles in start phase (169) instead of blocking
- **Requires:** `blockStartPhase` enabled
- **Command:** None (UI only)

### ghostProfileSwitch
- **Type:** boolean
- **Default:** `false`
- **Description:** Switch to blank profile in phase 169/map 1605
- **Command:** None (UI only)

### ghostProfileID
- **Type:** string
- **Default:** `nil`
- **Description:** TRP3 profile ID to send when ghosting (nil = blank profile)
- **Command:** None (UI only)

### ghostProfileName
- **Type:** string
- **Default:** `"TRP3FW_BLANK"`
- **Description:** Name of blank profile

### ghostProfileWhitelistEnabled
- **Type:** boolean
- **Default:** `false`
- **Description:** Enable additional phase/map whitelist for profile switching

### ghostProfileWhitelist
- **Type:** string (multi-line)
- **Default:** `""`
- **Format:** One entry per line: `<phase>` or `<phase>,<map>`
- **Description:** Phase/map combinations to allow profile switching

### ghostProfileOverrides
- **Type:** table
- **Default:** `{}`
- **Description:** List of overrides mapping phase/map to specific profile IDs/names.

### enableChompGhost
- **Type:** boolean
- **Default:** `true`
- **Description:** Enable ghosting via Chomp (TRP3/MSP payloads)

---

## Cache Durations

### phaseCacheDuration
- **Type:** number (seconds)
- **Default:** `300` (5 minutes)
- **Description:** Phase check cache TTL
- **Command:** `/trp3fw cache phase <seconds>`

### phaseCacheFailureDuration
- **Type:** number (seconds)
- **Default:** `10`
- **Description:** Failed phase check cache TTL (allows quick retries)

### phaseCacheRefreshThreshold
- **Type:** number (0-1)
- **Default:** `0.5` (50%)
- **Description:** Refresh cache when age > 50% of TTL (150s)

### scanCacheDuration
- **Type:** number (seconds)
- **Default:** `120` (2 minutes)
- **Description:** Map scan cache TTL
- **Command:** `/trp3fw cache scan <seconds>`

### scanCacheFailureDuration
- **Type:** number (seconds)
- **Default:** `10`
- **Description:** Failed/mismatched map scan cache TTL

### whoZoneCacheDuration
- **Type:** number (seconds)
- **Default:** `180` (3 minutes)
- **Description:** WHO zone cache TTL
- **Command:** `/trp3fw cache whozone <seconds>`

### whoNameCacheDuration
- **Type:** number (seconds)
- **Default:** `180` (3 minutes)
- **Description:** WHO name cache TTL
- **Command:** `/trp3fw cache whoname <seconds>`

### whoCacheRefreshThreshold
- **Type:** number (0-100)
- **Default:** `50` (50%)
- **Description:** Percentage of WHO cache duration after which a hit triggers background refresh

### interactionCacheDuration
- **Type:** number (seconds)
- **Default:** `600` (10 minutes)
- **Description:** Mouseover/target interaction cache TTL
- **Command:** `/trp3fw cache interaction <seconds>`

### sendCacheDuration
- **Type:** number (seconds)
- **Default:** `600` (10 minutes)
- **Description:** Allowed senders cache TTL
- **Command:** `/trp3fw cache send <seconds>`

### interactionRefreshRate
- **Type:** number (0-100 %)
- **Default:** `10` (10%)
- **Description:** Refresh interaction cache if age > 10% of TTL

### sendCacheRefreshRate
- **Type:** number (0-100 %)
- **Default:** `10` (10%)
- **Description:** Refresh send cache if age > 10% of TTL

---

## Cache Size Limits

### cacheSizeLimit
- **Type:** number
- **Default:** `1000`
- **Description:** General cache size limit (interaction, phase, WHO zone/name)

### whoQueueLimit
- **Type:** number
- **Default:** `100`
- **Description:** Maximum WHO query queue size

### cleanNameCacheSize
- **Type:** number
- **Default:** `500`
- **Description:** CleanPlayerName cache size

### sanitizedNameCacheSize
- **Type:** number
- **Default:** `500`
- **Description:** SanitizePlayerName cache size

### validatedNamesCacheDuration
- **Type:** number (seconds)
- **Default:** `604800` (7 days)
- **Description:** Validated names cache TTL (persistent)
- **Command:** `/trp3fw namecache <days>`

### validatedNamesCacheLimit
- **Type:** number
- **Default:** `5000`
- **Range:** 500-10000
- **Description:** Validated names cache max size
- **Command:** `/trp3fw namecachelimit <count>`

---

## Phase Check Batching

### phaseCheckBatchMode
- **Type:** boolean
- **Default:** `true`
- **Description:** Enable batched phase checks (Optimization #2)

### phaseCheckBatchSize
- **Type:** number
- **Default:** `5`
- **Range:** 2-10
- **Description:** Max batch size (capped by available tokens)

### phaseCheckBatchDelay
- **Type:** number (seconds)
- **Default:** `1.0`
- **Range:** 0.1-2.0
- **Description:** Delay before batching

### phaseCheckBatchMinSize
- **Type:** number
- **Default:** `3`
- **Description:** Only batch if queue >= this size

### phaseCheckInterTargetDelay
- **Type:** number (seconds)
- **Default:** `0.1` (100ms)
- **Range:** 0.01-0.2
- **Description:** Delay between targeting players in batch

### privilegedReservedTokens
- **Type:** number
- **Default:** `2`
- **Range:** 0-5
- **Description:** Tokens reserved for high-priority phase checks

### privilegedLowPriorityThreshold
- **Type:** number
- **Default:** `4`
- **Range:** 2-8
- **Description:** Defer low-priority requests if tokens < threshold

---

## WHO Query Settings

### useWhoQuery
- **Type:** boolean
- **Default:** `true`
- **Description:** Use WHO queries instead of map scans (Epsilon only)
- **Command:** `/trp3fw who`

### whoZoneQueryCooldown
- **Type:** number (seconds)
- **Default:** `20`
- **Description:** Cooldown between zone WHO queries

### suppressAllWhoOutput
- **Type:** boolean
- **Default:** `true`
- **Description:** Suppress ALL WHO output (not just TRP3FW queries)

### prepopulateWhoCache
- **Type:** boolean
- **Default:** `true`
- **Description:** Prepopulate WHO cache after zone/phase changes

### prepopulateWhoOnPhase
- **Type:** boolean
- **Default:** `true`
- **Description:** Run WHO prepopulation on phase change

### prepopulateWhoOnZone
- **Type:** boolean
- **Default:** `true`
- **Description:** Run WHO prepopulation on zone change

---

## Start Phase Settings

### blockStartPhase
- **Type:** boolean
- **Default:** `false`
- **Description:** Block profile sends in start phase (169)

---

## SPVP Settings

**SPVP** (Secure Phase Verification Protocol) uses cryptographic handshakes to verify phase presence. See [PHASE_ENCRYPTION.md](specifications/PHASE_ENCRYPTION.md) for full specification.

### spvpEnabled
- **Type:** boolean
- **Default:** `false`
- **Description:** Master toggle for SPVP cryptographic phase verification
- **Epsilon Only:** Yes (requires `C_Epsilon` API)
- **Command:** `/trp3fw spvp` (toggle)

**When Enabled:**
- Runs SPEKE handshake verification IN PARALLEL with normal phase checks
- Defense-in-depth: Both crypto AND physical checks must pass
- Detects "impossible states" (crypto pass + phase fail = attack)
- Requires phase owner to initialize salt (`/trp3fw spvp init`)

---

### spvpAutoInitialize
- **Type:** boolean
- **Default:** `true`
- **Description:** Automatically generate phase salt when entering phase (if you're owner/officer)
- **Requires:** `spvpEnabled = true`

**Behavior:**
- On PLAYER_LOGIN: Check if current phase needs salt, generate if owner
- On PLAYER_ENTERING_WORLD: Check if new phase needs salt
- Silently skips if not owner or salt already exists

---

### spvpBlockDuration
- **Type:** number (seconds)
- **Default:** `60`
- **Range:** 10-3600 (10 seconds to 1 hour)
- **Description:** Block profile sends to player after failed SPVP handshake
- **Command:** `/trp3fw spvpblock <seconds>`

**Purpose:** Rate limiting after handshake failure prevents:
- Repeated handshake spam
- Brute force attacks
- API token exhaustion

**Example:**
- Player fails SPVP handshake → blocked for 60s
- After 60s, can try again (cache cleared)

---

### spvpSaltCacheDuration
- **Type:** number (seconds)
- **Default:** `10800` (3 hours)
- **Range:** 300-43200 (5 min to 12 hours)
- **Description:** How long to cache phase salts before refetching from Epsilon API
- **Command:** `/trp3fw saltcache <seconds>`
- **UI:** Settings → Security → "Salt Cache Duration" slider

**Why Cache?**
- Reduces Epsilon API calls (rate-limited)
- Salts rarely change (phase owners rotate ~monthly)
- Improves performance for repeated handshakes

**Cache Invalidation:**
- Automatic on SPVP handshake failure (forces fresh salt)
- Manual: Phase owner rotates salt via `/trp3fw spvp rotate`

**See:** [CACHING_SYSTEM.md](CACHING_SYSTEM.md) - SPVP Phase Salt Cache

---

### spvpPerPhaseOverrides
- **Type:** table (key=phaseID, value=boolean)
- **Default:** `{}` (empty)
- **Description:** Per-phase SPVP enable/disable overrides

**Usage:**
```lua
-- Disable SPVP for specific phase
TRP3FW.Prefs.spvpPerPhaseOverrides[12345] = false

-- Enable for specific phase (if global setting is false)
TRP3FW.Prefs.spvpPerPhaseOverrides[67890] = true
```

**Priority:** Per-phase overrides take precedence over global `spvpEnabled`

---

## Transition Settings

### phaseInDelay
- **Type:** number (seconds)
- **Default:** `4`
- **Range:** 0-10
- **Description:** Delay profile request processing after zone change (prevents false alerts)

### transitionGracePeriod
- **Type:** number (seconds)
- **Default:** `3`
- **Range:** 0-30
- **Description:** Warn about potential false alerts during transition

---

## Whitelisting

### whitelistEnabled
- **Type:** boolean
- **Default:** `false`
- **Description:** Enable always-allow whitelist

### whitelistEntries
- **Type:** string (multi-line)
- **Default:** `""`
- **Format:** One player name per line
- **Description:** Players who bypass all checks

---

## Map Scanning

### mapScanMinInterval
- **Type:** number (seconds)
- **Default:** `60`
- **Description:** Minimum seconds between map scans

### ignoreMapScan
- **Type:** boolean
- **Default:** `true`
- **Status:** **INERT — read nowhere in the codebase.** Declared in `core/init.lua` only;
  verified repo-wide that nothing reads it. Changing it has no effect. Map-scan handling is
  actually gated by `disableMapScanOnTRP3` and the `scanResponse*` settings.
- **Description:** Ignore map scan broadcasts (legacy)

### notifyOnScanResponse
- **Type:** boolean
- **Default:** `false`
- **Description:** Show notification when TRP3 responds to map scans

### scanResponsePhaseMode
- **Type:** string
- **Default:** `"alert"`
- **Valid Values:** `"off"`, `"alert"`, `"block"`
- **Description:** Phase mismatch behavior for scan replies

### scanResponseMapMode
- **Type:** string
- **Default:** `"alert"`
- **Valid Values:** `"off"`, `"alert"`, `"block"`
- **Description:** Map/zone mismatch behavior for scan replies

### scanResponseRequireNonce
- **Type:** boolean
- **Default:** `false`
- **Description:** Require map scan replies to include issued nonce

### scanResponseCacheEnabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Cache WHO results when WHO query runs for scan replies

### scanResponseAllowCacheBypass
- **Type:** boolean
- **Default:** `true`
- **Description:** Allow scan replies to bypass WHO if cache valid

### scanResponsePhaseCheckEnabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Use phase check before WHO for scan replies

### scanResponseAllowGroupBypass
- **Type:** boolean
- **Default:** `true`
- **Description:** Allow scan replies to party/raid without checks

### scanResponseWhitelistEnabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Apply whitelist to scan replies

### scanResponseWhitelist
- **Type:** string (multi-line)
- **Default:** `""`
- **Description:** Whitelist for scan replies (one player per line)

---

## Hook Safety

### strictHookMode
- **Type:** boolean
- **Default:** `false`
- **Description:** Refuse to install hooks when another addon already wrapped target

### logHookConflicts
- **Type:** boolean
- **Default:** `true`
- **Description:** Log hook conflicts even when chaining allowed

### abortOnMultipleRPAddons
- **Type:** boolean
- **Default:** `true`
- **Description:** Disable TRP3FW if more than one of TRP3/MRP/XRP detected

### disableMapScanOnTRP3
- **Type:** boolean
- **Default:** `true`
- **Description:** Disable map-scan hooks when TRP3 and RPMapScan coexist

---

## Monitoring

### monitorTRP3
- **Type:** boolean
- **Default:** `true`
- **Description:** Monitor TotalRP3 sends

### monitorMRP
- **Type:** boolean
- **Default:** `true`
- **Description:** Monitor MyRolePlay sends

### monitorXRP
- **Type:** boolean
- **Default:** `true`
- **Description:** Monitor XRP sends

### monitorMSP
- **Type:** boolean
- **Default:** `true`
- **Description:** Monitor LibMSP sends

---

## History & UI

### trackHistory
- **Type:** boolean
- **Default:** `true`
- **Description:** Track send history (Tab 3)

### maxHistorySize
- **Type:** number
- **Default:** `100`
- **Description:** Maximum history entries

### uiComplexityLevel
- **Type:** number
- **Default:** `2`
- **Valid Values:** 1 (Basic), 2 (Intermediate), 3 (Advanced), 4 (Everything)
- **Description:** UI complexity level (reserved for future use)

### statusRefreshRate
- **Type:** number (seconds)
- **Default:** `30`
- **Range:** 2-120
- **Description:** Seconds between Status tab updates

### performanceHistoryEnabled
- **Type:** boolean
- **Default:** `false`
- **Description:** Enable tracking of performance metrics over time

---

## Cache Clearing Toggles

### clearCacheOnZoneChange
- **Type:** boolean
- **Default:** `true`
- **Description:** Master toggle for zone change clearing

### clearPhaseCheckOnZoneChange
- **Type:** boolean
- **Default:** `true`

### clearAllowedSendersOnZoneChange
- **Type:** boolean
- **Default:** `true`

### clearInteractionOnZoneChange
- **Type:** boolean
- **Default:** `true`

### clearSuppressionOnZoneChange
- **Type:** boolean
- **Default:** `true`

### clearWhoZoneOnZoneChange
- **Type:** boolean
- **Default:** `true`

### clearRecentBroadcastsOnZoneChange
- **Type:** boolean
- **Default:** `false`

### clearRecentScansOnZoneChange
- **Type:** boolean
- **Default:** `false`

### clearWhoNameOnZoneChange
- **Type:** boolean
- **Default:** `false`

---

### clearCacheOnPhaseChange
- **Type:** boolean
- **Default:** `true`
- **Description:** Master toggle for phase change clearing

### clearPhaseCheckOnPhaseChange
- **Type:** boolean
- **Default:** `true`

### clearAllowedSendersOnPhaseChange
- **Type:** boolean
- **Default:** `true`

### clearInteractionOnPhaseChange
- **Type:** boolean
- **Default:** `true`

### clearSuppressionOnPhaseChange
- **Type:** boolean
- **Default:** `true`

### clearRecentBroadcastsOnPhaseChange
- **Type:** boolean
- **Default:** `false`

### clearRecentScansOnPhaseChange
- **Type:** boolean
- **Default:** `false`

### clearWhoZoneOnPhaseChange
- **Type:** boolean
- **Default:** `false`

### clearWhoNameOnPhaseChange
- **Type:** boolean
- **Default:** `false`

---

## Debug Settings

### debug
- **Type:** boolean
- **Default:** `false`
- **Description:** Master debug toggle
- **Command:** `/trp3fw debug`

### debugTimestamp
- **Type:** boolean
- **Default:** `false`
- **Description:** Show timestamps in debug output
- **Command:** `/trp3fw debugtime`

### Debug Categories (all boolean, default varies)
- `debugChannel` - Channel debug
- `debugWhisper` - Whisper debug
- `debugWho` - WHO query debug
- `debugPhase` - Phase check debug
- `debugCleanName` - Name cleaning debug
- `debugLocation` - Location check debug
- `debugDecision` - Decision logic debug
- `debugHooks` - Hook system debug
- `debugCache` - Cache system debug
- `debugSend` - Send tracking debug
- `debugUI` - UI debug
- `debugUtils` - Utilities debug
- `debugSecurity` - Security debug
- `debugGhost` - Ghost mode debug

**Command:** `/trp3fw debugfilter <category>`

---

## Debug Output

While `debug` is enabled, every debug message is buffered for the debug window (last
1000 lines) whether or not the window is open, so you can open it after an event and
read the backlog. These three settings only control whether messages *also* print to
chat.

### debugOutputWindow
- **Type:** boolean
- **Default:** `false`
- **Description:** Window-only destination (suppresses chat output; the window buffer is fed regardless)

### debugOutputChat
- **Type:** boolean
- **Default:** `true`
- **Description:** Output debug to chat

### debugOutputBoth
- **Type:** boolean
- **Default:** `false`
- **Description:** Output to both chat and window

---

## Redaction

### redactEnabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Enable debug message redaction (security)

### redactNames
- **Type:** boolean
- **Default:** `true`
- **Description:** Redact player names in debug

### redactLocations
- **Type:** boolean
- **Default:** `true`
- **Description:** Redact zone/map names in debug

### redactNetwork
- **Type:** boolean
- **Default:** `true`
- **Description:** Redact GUIDs/IPs/emails in debug

---

## Feature Filters

### filterIcons
- **Type:** boolean
- **Default:** `false`
- **Description:** Strip WoW texture icons from incoming profile fields (Name, Titles, Class, Currently, OOC, Nicknames, House)
- **Command:** `/trp3fw filter icon` (toggle)

### filterGradients
- **Type:** boolean
- **Default:** `false`
- **Description:** Filter gradients from incoming profiles

### filterMinimumFontSize
- **Type:** boolean
- **Default:** `false`
- **Description:** Inject minimum font size into incoming profiles

### minimumFontSizeLevel
- **Type:** string
- **Default:** `"h3"`
- **Valid Values:** `"h1"`, `"h2"`, `"h3"`, `"p"`
- **Description:** Font size level to inject