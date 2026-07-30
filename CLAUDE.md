# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 📚 Architecture Documentation

**Complete architecture reference available in `thoughts/` folder:**

- **[thoughts/INDEX.md](thoughts/INDEX.md)** - Start here! Navigation hub for all architecture docs
- **[thoughts/DECISION_LOGIC.md](thoughts/DECISION_LOGIC.md)** - Pipeline flow, stages, allow/block/ghost logic
- **[thoughts/LOCATION_DETECTION.md](thoughts/LOCATION_DETECTION.md)** - Phase, WHO, map scanning, cascading
- **[thoughts/CACHING_SYSTEM.md](thoughts/CACHING_SYSTEM.md)** - All caches, TTLs, optimization
- **[thoughts/DATA_STRUCTURES.md](thoughts/DATA_STRUCTURES.md)** - All variables, arrays, queues, state
- **[thoughts/SERVICES_ARCHITECTURE.md](thoughts/SERVICES_ARCHITECTURE.md)** - Services, container, lifecycle
- **[thoughts/SETTINGS_REFERENCE.md](thoughts/SETTINGS_REFERENCE.md)** - All settings with descriptions

**When to use:**
- Debugging issues → Use INDEX.md to find relevant topic
- Understanding data flow → Read DECISION_LOGIC.md
- Finding variables → Check DATA_STRUCTURES.md
- Looking up settings → See SETTINGS_REFERENCE.md

## Project Overview

**TRP3 Firewall (TRP3FW)** is a World of Warcraft addon that monitors and controls RP (roleplay) profile sharing. It intercepts profile requests and uses intelligent location detection (phase checks, WHO queries, map scanning) to determine whether to allow, block, or "ghost" (send blank profiles to) requesters.

**Version**: 1.6.0 (deliberate step DOWN from the old 2.9.x line; see `core/init.lua:10`)
**Target**: WoW 9.2.7+ (Shadowlands/Dragonflight/TWW)
**Language**: Lua 5.1
**Platform**: World of Warcraft addon system

## No Build System

This is a standard WoW addon with **no build system or compilation step**. Development workflow:

1. Edit `.lua` and `.xml` files directly
2. In-game: `/reload` to reload the UI
3. Changes take effect immediately after reload
4. Test using `/trp3fw` commands

**Testing**: Manual in-game testing is primary verification method. Optional integration tests in `tests/integration_tests.lua` (loaded via .toc file).

## Development Commands

### Essential In-Game Commands

```bash
/trp3fwui               # Open settings UI (4 tabs)
/trp3fw status          # Show all settings and detected addons
/trp3fw stats           # Show session statistics (allows/blocks/ghosts)
/trp3fw debug           # Toggle debug mode
/trp3fw debugfilter <category>  # Filter debug output (15 categories)
/trp3fw test            # Play sample notifications
/trp3fw reloadhooks     # Reinstall hooks after addon updates
/reload                 # Reload WoW UI (CRITICAL for testing changes)
```

### Debug Categories
`channel`, `whisper`, `who`, `phase`, `location`, `decision`, `hooks`, `cache`, `send`, `ui`,
`utils`, `security`, `ghost`, `spvp`, `cleanname`

`DEBUG_CATEGORIES` in `core/utils.lua` is the authority. Note `init`, `core`, `pipeline`,
`queue` and `refactor` are also accepted as categories but route through `debugUtils`, so they
are silenced by `debugfilter utils` rather than having filters of their own.

**Enable debug for specific area:**
```bash
/trp3fw debug                    # Enable debug mode
/trp3fw debugtime                # Show timestamps
/trp3fw debugfilter decision     # Only show decision logic
/trp3fw debugfilter location     # Only show location checks
/trp3fw debugfilter cache        # Only show cache activity
```

### Profiling (Performance Testing)
```bash
/trp3fw profile on      # Enable performance profiling
/trp3fw profile report  # Show detailed performance report (P95, avg, min, max)
/trp3fw profile reset   # Reset statistics
/trp3fw profile off     # Disable profiling
```

### Cache Management
```bash
/trp3fw cache phase 300         # Set phase cache TTL (seconds)
/trp3fw cache interaction 600   # Set interaction cache TTL
/trp3fw cache whozone 180       # Set WHO zone cache TTL
/trp3fw namecache 7             # Set validated names retention (days)
/trp3fw namecachelimit 5000     # Set max validated names
```

## Quick Architecture Overview

### Core Pattern: 7-Stage Decision Pipeline (including SPVPStage)

Each profile send request flows through a **pipeline** with early exits:

```
1. WhitelistStage      → Whitelisted? → ALLOW (exit)
2. SPVPStage           → Prepare salt + enabled status; NEVER handles (no exit)
3. CacheStage          → Cached result? → ALLOW (exit)
                       → Cached DIFFERENT-phase result? → fast-FAIL (exit)
4. InteractionStage    → Recent interaction? → ALLOW (exit)
5. AlertFastPathStage  → Alerts only (no blocking)? → ALLOW + async check (exit)
6. BurstStage          → Check in progress? → QUEUE (exit)
7. LocationStage       → Run phase/WHO/map checks → ALLOW/BLOCK/GHOST
```

`features/pipelines/DecisionPipeline.lua` is the single source of truth for stage order.

Two things this summary previously got wrong, worth stating because they change how you read
the flow:
- **Stage 2 is `SPVPStage`, not a `PhaseInStage`.** There is no `PhaseInStage.lua` in the
  codebase. SPVPStage never returns `handled`, so it is a context-preparation step rather than
  an exit point -- the pipeline always continues through it.
- **`CacheStage` has a fast-FAIL branch, not just a fast-allow.** A cached *different-phase*
  result short-circuits to a block, so a stale entry there suppresses a player without any
  live check. (That branch is TTL-gated; see `tests/unit/cache_stage_ttl_spec.lua`.)

**See [thoughts/DECISION_LOGIC.md](thoughts/DECISION_LOGIC.md) for complete flow.**

### Service Container Pattern

Stateful systems managed as services. All six register with `TRP3FW.ServiceContainer` and are
initialized together at `PLAYER_LOGIN`:
- **EventService** - Centralized WoW event dispatch (`core/EventService.lua`)
- **CacheService** - Cache management, cleanup, event handling
- **HistoryService** - Session stats, send history
- **NotificationService** - Notification dispatch, suppression
- **SecurityService** - Input sanitization, debug redaction
- **WhoService** - WHO query queue, throttling, cooldowns

**See [thoughts/SERVICES_ARCHITECTURE.md](thoughts/SERVICES_ARCHITECTURE.md) for details.**

### Location Detection: Cascading System

Three methods with intelligent fallback:

1. **Phase Check** (Epsilon only) - Party/raid/nameplate/batch targeting
2. **WHO Query** (Epsilon only) - Zone/name queries with prepopulation
3. **Map Scan** (All servers) - TRP3 protocol broadcasts

**Priority:** Phase → WHO → Map Scan (first success wins)

**See [thoughts/LOCATION_DETECTION.md](thoughts/LOCATION_DETECTION.md) for implementation.**

### Caching: 13 CacheInterface Layers with LRU Eviction

All of these are registered with the unified `CacheInterface` (O(1) operations) in
`core/init.lua` -- that registration block is the authoritative list:

1. Allowed Senders (10min) - Players who passed checks
2. Interaction (10min) - Mouseover/target tracking
3. Phase Check (5min) - Phase verification results
4. WHO Name (3min) - Individual player queries
5. WHO Zone (3min) - Zone-wide query results
6. Map Scan (2min) - Map scan replies
7. Broadcast (2min) - Passive map events
8. SPVP Verified - Cryptographic verification results
9. SPVP Phase Salt - Per-phase salts
10. SPVP Sessions - Handshake session state
11. Clean Name (unlimited) - Name normalization cache
12. Sanitized Name (unlimited) - Validation cache
13. Map Name - Map ID to name lookups

Plus these stores that are NOT CacheInterface caches and so behave differently:
- **Validated Names** (7 days) - a persistent SavedVariable (`TRP3FW_ValidatedNames`), not
  registered with CacheInterface and not LRU-evicted.
- **MSP Conversion Cache** (`TRP3FW.mspConversionCache`) - a plain table keyed by your own
  profile IDs, with its own TTL (`mspConversionCacheDuration`) and a flat entry cap.
- **SPVP handshake state** (`features/encryption/spvp.lua`) - three plain tables fed from the
  network: `pendingSPVPInits` and `spvpIncomingSessions` are capped and TTL-pruned by
  `PrunePendingSPVPInits` / `PruneSPVPIncomingSessions`; `spvpFailedAttempts` is keyed by
  player and cleared lazily on re-check.

**See [thoughts/CACHING_SYSTEM.md](thoughts/CACHING_SYSTEM.md) for optimization details.**

## File Structure

```
TRP3FW/
├── thoughts/                   # 📚 ARCHITECTURE DOCS (START HERE)
│   ├── INDEX.md                # Navigation hub
│   ├── DECISION_LOGIC.md       # Pipeline, stages, decisions
│   ├── LOCATION_DETECTION.md   # Phase, WHO, map checking
│   ├── CACHING_SYSTEM.md       # All caches, optimization
│   ├── DATA_STRUCTURES.md      # Variables, arrays, queues
│   ├── SERVICES_ARCHITECTURE.md # Services, container
│   └── SETTINGS_REFERENCE.md   # All settings documented
│
├── core/                       # Core systems (loaded first)
│   ├── init.lua                # Namespace, settings, constants
│   ├── Service.lua             # Service base class
│   ├── ServiceContainer.lua    # Service registry
│   ├── Context.lua             # Pipeline context
│   ├── Pipeline.lua            # Pipeline runner
│   ├── Stage.lua               # Stage base class
│   ├── utils.lua               # Utilities
│   ├── types.lua               # Type definitions
│   ├── cache_interface.lua     # LRU cache system
│   └── feature_flags.lua       # Feature flags
│
├── features/
│   ├── services/               # Stateful services
│   │   ├── CacheService.lua    # Cache management, cleanup, events
│   │   ├── HistoryService.lua  # Session stats, send history
│   │   ├── NotificationService.lua # Notifications, suppression
│   │   └── SecurityService.lua # Sanitization, redaction
│   ├── services/ (cont.)
│   │   └── WhoService.lua      # WHO query queue, throttling
│   ├── stages/                 # Pipeline stages (7 total)
│   │   ├── WhitelistStage.lua
│   │   ├── SPVPStage.lua       # (NOT "PhaseInStage" -- no such file exists)
│   │   ├── CacheStage.lua
│   │   ├── InteractionStage.lua
│   │   ├── AlertFastPathStage.lua
│   │   ├── BurstStage.lua
│   │   └── LocationStage.lua
│   ├── encryption/             # SPVP (secure phase verification protocol)
│   │   ├── spvp.lua            # Crypto, salts, handshake
│   │   ├── spvp_auto_init.lua  # Startup/phase-change wiring
│   │   └── spvp_handlers.lua   # Message handlers
│   ├── pipelines/
│   │   └── DecisionPipeline.lua # Pipeline configuration (source of truth for stage order)
│   ├── decision.lua            # Decision logic entry point
│   ├── ghostmode.lua           # Ghost mode logic
│   ├── ghostmode_trp3.lua      # TRP3-specific ghost flag/window handling
│   ├── profileswitch.lua       # Profile switching
│   ├── notifications.lua       # DEPRECATED delegation shim -- the real implementations of
│   │                           # ShowChatNotification/RecordHistory live in features/services/
│   └── profiles/               # Cross-addon adapters
│
├── location/                   # Location detection
│   ├── phase.lua               # Phase checking (Epsilon)
│   ├── who.lua                 # WHO queries (Epsilon)
│   ├── maps.lua                # Map scanning (all servers)
│   ├── cascading.lua           # Cascading coordinator
│   └── check_interface.lua     # Unified interface
│
├── hooks/                      # Addon API interception
│   ├── installer.lua           # Hook installer, conflict detection
│   ├── trp3.lua                # TotalRP3 hooks
│   ├── trp3_chomp_pipeline.lua # TRP3 Chomp hook
│   ├── trp3_scan_pipeline.lua  # TRP3 scan reply hook
│   ├── msp.lua                 # LibMSP hooks
│   ├── msp_exchange.lua        # MSP exchange hooks
│   ├── fontsize.lua            # Minimum font size injection
│   ├── icon.lua                # Icon tag filtering
│   └── gradient.lua            # Gradient tag filtering
│
├── ui/                         # User interface
│   ├── settings.lua            # Settings panel + RefreshUI
│   ├── TabManager.lua          # Tab registry, widget kit, complexity gating
│   ├── Theme.lua               # Palette, fonts, colors
│   ├── tabs/                   # One file per settings tab
│   ├── debugwindow.lua         # Debug window
│   └── historywindow.lua       # Send history viewer
│
├── commands.lua                # Slash commands
├── status.lua                  # Status display
├── TRP3FW.lua                  # Main initialization
└── TRP3FW.toc                  # Addon metadata (load order)
```

## Common Development Tasks

### Debugging a Profile Decision

**Goal:** Understand why a profile was allowed, blocked, or ghosted

**Steps:**
1. Enable relevant debug categories:
   ```bash
   /trp3fw debug
   /trp3fw debugfilter decision
   /trp3fw debugfilter location
   /trp3fw debugfilter cache
   ```

2. Trigger the issue (mouseover player, receive request, etc.)

3. Read debug output showing:
   - Which pipeline stage handled request
   - Cache hits/misses
   - Location check results (phase/WHO/map)
   - Final decision (allow/block/ghost)

4. Check send history:
   ```bash
   /trp3fwui  # Tab 3: History
   ```

**See:** [thoughts/DECISION_LOGIC.md](thoughts/DECISION_LOGIC.md) for pipeline flow

---

### Understanding Cache Behavior

**Goal:** See why cache hit/miss occurred

**Steps:**
1. Enable cache debug:
   ```bash
   /trp3fw debug
   /trp3fw debugfilter cache
   ```

2. Check cache statistics:
   ```bash
   /trp3fw status  # Shows hit rates
   ```

3. Inspect specific cache:
   - See [thoughts/CACHING_SYSTEM.md](thoughts/CACHING_SYSTEM.md) for TTLs
   - See [thoughts/DATA_STRUCTURES.md](thoughts/DATA_STRUCTURES.md) for cache structures

4. Adjust cache duration if needed:
   ```bash
   /trp3fw cache interaction 1200  # Increase to 20 min
   ```

**Typical hit rates:**
- Interaction: 60-70%
- Phase Check: 40-50%
- WHO: 30-40%
- Allowed Senders: 50-60%

---

### Adding a New Pipeline Stage

**Example:** Add "FriendStage" to allow friends without checks

1. **Create stage file** `features/stages/FriendStage.lua`:
```lua
local addonName, TRP3FW = ...

TRP3FW.FriendStage = setmetatable({}, { __index = TRP3FW.Stage })

function TRP3FW.FriendStage:New(name)
    local instance = TRP3FW.Stage:New(name or "FriendStage")
    setmetatable(instance, { __index = self })
    return instance
end

function TRP3FW.FriendStage:Process(context)
    -- Check if player is friend
    local isFriend = C_FriendList.IsFriend(UnitGUID(context.playerName))

    if isFriend then
        TRP3FW:Debug("Player is friend, allowing", "decision")

        -- Allow immediately and stop pipeline
        context.allowed = true
        TRP3FW:AllowSender(context.playerName, "friend")
        if context.originalFunc then
            pcall(context.originalFunc, unpack(context.originalArgs))
        end

        return { handled = true, allowed = true }
    end

    -- Not a friend, continue to next stage
    return { handled = false }
end
```

2. **Add to TOC** in Stages section:
```
features\stages\FriendStage.lua
```

3. **Add to pipeline** in `features/pipelines/DecisionPipeline.lua`:
```lua
function TRP3FW:InitializeDecisionPipeline()
    local pipeline = TRP3FW.Pipeline:New("DecisionPipeline")

    pipeline:AddStage(TRP3FW.WhitelistStage:New("Whitelist"))
    pipeline:AddStage(TRP3FW.FriendStage:New("Friend"))  -- ADD HERE
    pipeline:AddStage(TRP3FW.SPVPStage:New("SPVP"))
    -- ... rest of stages
end
```

4. **Test:**
```bash
/reload
/trp3fw debug
/trp3fw debugfilter decision
# Trigger request from friend
```

**See:** [thoughts/DECISION_LOGIC.md](thoughts/DECISION_LOGIC.md) for stage pattern

---

### Adding a New Service

**Example:** Add "FriendService" to track friend interactions

1. **Create service file** `features/services/FriendService.lua`:
```lua
local addonName, TRP3FW = ...

local FriendService = setmetatable({}, { __index = TRP3FW.Service })

function FriendService:New()
    local instance = TRP3FW.Service:New("FriendService")
    setmetatable(instance, { __index = self })
    return instance
end

function FriendService:Initialize()
    if self.initialized then return end
    TRP3FW.Service.Initialize(self)

    -- Service state
    self.friendInteractions = {}

    -- Hook friend events
    self:RegisterEvents()

    TRP3FW:Debug("FriendService initialized", "core")
end

function FriendService:RegisterEvents()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("FRIENDLIST_UPDATE")
    frame:SetScript("OnEvent", function(self, event)
        FriendService:OnFriendListUpdate()
    end)
end

function FriendService:OnFriendListUpdate()
    -- Update friend list
end

function FriendService:IsFriend(playerName)
    -- Check if friend
    return false
end

-- Create singleton and register
local instance = FriendService:New()
TRP3FW.ServiceContainer:Register(instance)
```

2. **Add to TOC** in Services section:
```
features\services\FriendService.lua
```

3. **Service auto-initializes** on `PLAYER_LOGIN`

4. **Access service:**
```lua
local friendService = TRP3FW.ServiceContainer:Get("FriendService")
if friendService:IsFriend(playerName) then
    -- ...
end
```

**See:** [thoughts/SERVICES_ARCHITECTURE.md](thoughts/SERVICES_ARCHITECTURE.md) for service pattern

---

### Modifying Settings

**Example:** Add "friendBypassEnabled" setting

1. **Add default** in `core/init.lua`:
```lua
TRP3FW.defaultSettings = {
    -- ... existing settings
    friendBypassEnabled = true,  -- ADD THIS
}
```

2. **Add UI control** in `ui/settings.lua`:
```lua
-- In CreateTab1() or appropriate tab
local friendBypass = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
friendBypass:SetPoint("TOPLEFT", previousControl, "BOTTOMLEFT", 0, -10)
friendBypass.text:SetText("Bypass checks for friends")
friendBypass:SetChecked(TRP3FW_Settings.friendBypassEnabled)
friendBypass:SetScript("OnClick", function(self)
    TRP3FW_Settings.friendBypassEnabled = self:GetChecked()
end)
```

3. **Add command** (optional) in `commands.lua`:
```lua
elseif command == "friend" then
    TRP3FW_Settings.friendBypassEnabled = not TRP3FW_Settings.friendBypassEnabled
    local status = TRP3FW_Settings.friendBypassEnabled and "enabled" or "disabled"
    TRP3FW:Info("Friend bypass " .. status)
```

4. **Access setting:**
```lua
if TRP3FW_Settings.friendBypassEnabled then
    -- ...
end
```

**See:** [thoughts/SETTINGS_REFERENCE.md](thoughts/SETTINGS_REFERENCE.md) for all settings

---

### Tracing a Bug

**Scenario:** Player reports "ghost mode not working"

**Steps:**
1. **Gather info:**
   ```bash
   /trp3fw status  # Check ghost settings
   ```

2. **Enable debug:**
   ```bash
   /trp3fw debug
   /trp3fw debugfilter ghost
   /trp3fw debugfilter decision
   ```

3. **Reproduce issue** (trigger ghost send)

4. **Analyze debug output:**
   - Check if `EnableGhostForNextSend()` called
   - Check if ghost flag set correctly
   - Check if hook intercepted send
   - Check if blank profile generated

5. **Check relevant docs:**
   - [thoughts/DECISION_LOGIC.md](thoughts/DECISION_LOGIC.md) - Decision flow
   - [thoughts/DATA_STRUCTURES.md](thoughts/DATA_STRUCTURES.md) - `TRP3FW.ghostNextSend` structure
   - Source: `features/ghostmode.lua`

6. **Common causes:**
   - Ghost mode disabled in settings
   - Alert type doesn't match ghost trigger (phase vs map)
   - Profile switch override active (phase 169)
   - Hook not installed (`/trp3fw reloadhooks`)

---

## Namespace Pattern

All code uses shared namespace:

```lua
local addonName, TRP3FW = ...

-- Access settings
TRP3FW_Settings.notifyEnabled

-- Call functions
TRP3FW:Debug("message", "category")
TRP3FW:CleanPlayerName(name)
TRP3FW:GetCurrentTime()  -- Monotonic clock (GetTimePreciseSec, falling back to GetTime)

-- Access services
local cacheService = TRP3FW.ServiceContainer:Get("CacheService")
local historyService = TRP3FW.ServiceContainer:Get("HistoryService")

-- Access caches via CacheInterface
local CI = TRP3FW.CacheInterface
local cached = CI:Get("phaseCheck", playerName)
CI:Set("allowedSenders", playerName, {timestamp = now, reason = "location_ok"})
```

## Data Persistence

**SavedVariables** (declared in `TRP3FW.toc`):
- `TRP3FW_Settings` - All addon settings (100+ options)
- `TRP3FW_MinimapSettings` - Minimap button position
- `TRP3FW_ValidatedNames` - Persistent validated player cache (7 days)

Stored in: `WTF/Account/<account>/SavedVariables/TRP3FW.lua`

**See:** [thoughts/DATA_STRUCTURES.md](thoughts/DATA_STRUCTURES.md) for complete structure

## Code Quality Guidelines

### Lua Style
- **Indentation**: Tabs (WoW addon standard)
- **Naming**: camelCase for functions, UPPER_CASE for constants
- **Comments**: Use `--` for line comments, `-- ===` for section headers
- **Nil Checks**: Always validate player names and external data

### Security Considerations
- **Input Sanitization**: Use `TRP3FW:SanitizePlayerName()` for all player names
- **Cache Limits**: All caches have `maxSize` limits (prevent DoS)
- **Rate Limiting**: WHO queries and map scans are throttled
- **SendId Verification**: Use `TRP3FW.sendIdSalt` for request signing

### Performance Best Practices
- **Prefer `TRP3FW:GetCurrentTime()` over raw `GetTime()`**: it uses `GetTimePreciseSec` where
  available, which is monotonic and immune to system clock changes. Note it is NOT cached --
  an earlier "frame cache" here saved nothing and was removed; see `core/utils.lua`. Within a
  single request, read the context's `now` snapshot instead of re-reading the clock.
- **Cache aggressively**: Use `CacheInterface` for repeated lookups
- **Defer expensive ops**: Use `C_Timer.After()` for non-critical work
- **Object pooling**: Reuse tables instead of creating new ones
- **Profile before optimizing**: Use `/trp3fw profile on`

## Important Globals

### WoW API (commonly used)
- `CreateFrame()`, `UIParent`
- `GetTime()`, `C_Timer.After()`
- `UnitName()`, `UnitGUID()`, `UnitExists()`
- `C_Map.GetBestMapForUnit()`
- `GetZoneText()`, `GetSubZoneText()`
- `IsInGroup()`, `IsInRaid()`
- `C_FriendList.GetNumFriends()`, `C_FriendList.IsFriend()`

### TRP3FW Globals
- `TRP3FW` - Main namespace (see [DATA_STRUCTURES.md](thoughts/DATA_STRUCTURES.md))
- `TRP3FW_Settings` - Settings table (see [SETTINGS_REFERENCE.md](thoughts/SETTINGS_REFERENCE.md))
- `TRP3FW_MinimapSettings` - Minimap position
- `TRP3FW_ValidatedNames` - Persistent player cache

### External Addon APIs
- `TRP3_API` - TotalRP3 API
- `msp` - LibMSP (Mary Sue Protocol)
- `mrp` - MyRolePlay addon
- `xrp` - XRP addon
- `C_Epsilon` - Epsilon server API (Epsilon only)

## Debugging Tips

### Common Debug Patterns

**Debug a decision:**
```bash
/trp3fw debug
/trp3fw debugfilter decision
/trp3fw debugfilter location
```

**Debug caching:**
```bash
/trp3fw debug
/trp3fw debugfilter cache
/trp3fw status  # View hit rates
```

**Debug hooks:**
```bash
/trp3fw debug
/trp3fw debugfilter hooks
/trp3fw status  # Check hook status
```

**Debug WHO queries:**
```bash
/trp3fw debug
/trp3fw debugfilter who
```

### Common Issues

**Hooks not working:**
```bash
/trp3fw reloadhooks
/reload
/trp3fw status  # Verify hooks installed
```

**Phase checks fail:**
- Only works on Epsilon server
- Check: `/trp3fw status` → "Epsilon API available: Yes/No"
- Enable: `/trp3fw alert phase`

**Map checks fail:**
- Requires TRP3 or compatible addon
- Check: `/trp3fw status` → Detected addons section

**Notifications not showing:**
```bash
/trp3fw notify toggle      # Enable notifications
/trp3fw display chat       # Enable chat output
/trp3fw suppress 0         # Clear suppression
```

**Ghost mode not working:**
```bash
/trp3fw status            # Check ghost settings
/trp3fw ghost             # Enable ghost mode
/trp3fw block alert       # Enable blocking
/trp3fw debug
/trp3fw debugfilter ghost
```

### View Send History
```bash
/trp3fwui  # Tab 3: History - Last 50-100 sends
# Filter: All | Allowed | Blocked | Ghosted | Alerts
```

## Version Information

**Current Version**: 1.6.0 (`core/init.lua` is the single source of truth; the .toc, the README
badge and the release tag are all checked against it by `scripts/make-release.sh`)
**Interface Version**: 90207 (WoW 9.2.7+)
**Total Lines of Code**: ~21,300 across the 68 Lua files loaded by `TRP3FW.toc`
(measured 2026-07-25; the previously documented "~3,400" was off by roughly 6x)
**Files**: 68 Lua files in `TRP3FW.toc` (modular architecture)

**Performance**: substantially faster than v1.x
- 90% reduction in mouseover events
- 98% faster WHO queue processing

(A "99% reduction in syscalls" figure previously claimed here rested on the `GetCurrentTime`
frame cache, which on inspection read the clock unconditionally before consulting itself and
therefore saved nothing. The cache has been removed; the figure is withdrawn rather than
restated, since no measurement supports one. Use `/trp3fw profile on` for real numbers.)

## Additional Resources

### In This Repository
- **[thoughts/](thoughts/)** - 📚 Complete architecture documentation
- **[README.md](README.md)** - User documentation, features, commands
- **[TRP3FW.toc](TRP3FW.toc)** - File load order (critical for understanding initialization)
- **[tests/integration_tests.lua](tests/integration_tests.lua)** - Integration tests (optional)

### External Resources
- **WoW API**: https://wowpedia.fandom.com/
- **Lua 5.1 Reference**: https://www.lua.org/manual/5.1/
- **Epsilon WoW**: https://epsilonwow.net/ (for Epsilon API features)

---

**Quick Navigation:**
- 🏗️ **Understand architecture** → Start with [thoughts/INDEX.md](thoughts/INDEX.md)
- 🐛 **Debug an issue** → Enable debug, check [thoughts/DECISION_LOGIC.md](thoughts/DECISION_LOGIC.md)
- 📊 **Find a variable** → Check [thoughts/DATA_STRUCTURES.md](thoughts/DATA_STRUCTURES.md)
- ⚙️ **Look up a setting** → See [thoughts/SETTINGS_REFERENCE.md](thoughts/SETTINGS_REFERENCE.md)
- 🚀 **Add a feature** → Review [thoughts/](thoughts/) docs for patterns
