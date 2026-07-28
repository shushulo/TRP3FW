# TRP3FW Architecture Documentation Index

Complete architecture reference for TRP3FW. Use this index to find specific information.

## Quick Navigation

### For Understanding Data Flow
1. **[DECISION_LOGIC.md](DECISION_LOGIC.md)** - Start here to understand how allow/block decisions work
2. **[LOCATION_DETECTION.md](LOCATION_DETECTION.md)** - How phase, WHO, and map checking works
3. **[CACHING_SYSTEM.md](CACHING_SYSTEM.md)** - How caching optimizes performance

### For Understanding Code Structure
1. **[DATA_STRUCTURES.md](DATA_STRUCTURES.md)** - All variables, arrays, caches, queues
2. **[SERVICES_ARCHITECTURE.md](SERVICES_ARCHITECTURE.md)** - Service container and services
3. **[HOOK_SYSTEM.md](HOOK_SYSTEM.md)** - How TRP3FW hooks into other addons

### For Configuration & Troubleshooting
1. **[SETTINGS_REFERENCE.md](SETTINGS_REFERENCE.md)** - All settings with descriptions
2. **[GHOST_MODE.md](GHOST_MODE.md)** - Ghost mode implementation details
3. **[EPSILON_COMPATIBILITY.md](EPSILON_COMPATIBILITY.md)** - Epsilon server issues & workarounds
4. **[specifications/PHASE_ENCRYPTION.md](specifications/PHASE_ENCRYPTION.md)** - SPVP Cryptographic Protocol
5. [specifications/SPVP_FALLBACK_PROFILE.md](specifications/SPVP_FALLBACK_PROFILE.md) - SPVP Fallback Profile
6. [specifications/REMOVE_ICONS.md](specifications/REMOVE_ICONS.md) - Icon Removal Feature

## Document Summaries

### EPSILON_COMPATIBILITY.md
**What:** Complete guide for Epsilon server-specific features, known issues, and workarounds

**Key Topics:**
- WHO_LIST_UPDATE event not firing on Epsilon 9.2.5 (polling fallback)
- Custom map name detection (GetRealZoneText vs C_Map.GetMapInfo)
- Service initialization order race condition fix
- Privileged code syntax requirements (semicolon separators)
- C_Epsilon.RunPrivileged usage and rate limiting
- Phase system on Epsilon (Phase 169 blocking)
- Debugging commands for Epsilon issues
- Testing and validation procedures

**Use When:**
- WHO queries not populating caches
- Zone detection returning wrong names on custom maps
- WHO_LIST_UPDATE callbacks not firing
- RunPrivileged execution errors
- Debugging Epsilon-specific issues
- Understanding Epsilon API limitations

---

### REMOVE_ICONS.md
**What:** Feature specification for stripping WoW texture strings (icons) from profiles.

**Key Topics:**
- Regex-based icon stripping (`|[Tt].-|[Tt]`)
- MSP and TRP3 field coverage (Names, Titles, Class, Race, Currently, OOC, etc.)
- Known gap: `RA` (race) missing from TRP3 hook; `RA`/`FC` missing from MSP hook
- Performance tracking integration
- Alignment with gradient filtering logic

**Use When:**
- Understanding how icon stripping is implemented
- Expanding the set of fields to be filtered
- Debugging regex or field mapping issues


### DECISION_LOGIC.md
**What:** Complete decision pipeline flow from request to allow/block/ghost

**Key Topics:**
- 7-stage pipeline architecture (includes SPVP stage; phase-in delay handled in Chomp hook)
- Context creation and TOCTOU prevention
- Stage-by-stage processing logic
- Burst request handling (with snapshot-based staleness detection)
- Notification determination
- Decision application (allow/block/ghost)
- Per-kind cascading completion tracking (`expected`/`done` sets)
- Early fast-paths for interaction and start-phase protection

**Use When:**
- Understanding why a profile was allowed/blocked
- Debugging decision logic issues
- Adding new pipeline stages
- Modifying alert/block behavior

---

### LOCATION_DETECTION.md
**What:** Phase checking, WHO queries, map scanning, and cascading logic

**Key Topics:**
- Phase detection methods (party/raid, nameplate, target, batch)
- **New:** SPVP (Secure Phase Verification Protocol) integration
- Batch targeting with dynamic token management
- WHO query system (zone/name queries, caching, prepopulation)
- Map scanning protocol (TRP3 broadcasts)
- **Refined:** Sequential Cascading (Phase then Map)
- **New:** Early-Success optimization for parallel checks
- Reliable vs unreliable failures

**Use When:**
- Understanding location check results
- Debugging phase/map checks
- Optimizing WHO query performance
- Troubleshooting Epsilon API issues
- Understanding cache behavior

---

### CACHING_SYSTEM.md
**What:** All cache layers, TTLs, eviction policies, and optimization strategies

**Key Topics:**
- 12 cache types (interaction, phase, WHO, map, SPVP salt, etc.)
- **New:** Negative caching for missing phase salts (1h TTL)
- CacheInterface LRU implementation
- Cache TTLs and refresh logic
- Validated names persistent cache
- Event-based cache clearing
- Time caching optimization
- Phase ID caching
- MSP conversion caching

**Use When:**
- Understanding cache hit/miss behavior
- Tuning cache durations
- Debugging cache-related issues
- Understanding performance optimizations
- Troubleshooting memory usage

---

### DATA_STRUCTURES.md
**What:** Complete reference of all global variables, arrays, caches, state containers

**Key Topics:**
- Core namespace (TRP3FW table)
- Settings structure (TRP3FW.Prefs)
- All cache tables
- Queue systems (phase-in, phase check, WHO, location check, burst)
- State tracking (zone/phase transitions, targeting, ghost)
- **New:** SPVP session state and salt tickets
- Hook state containers
- Session statistics
- Constants and priority levels

**Use When:**
- Looking up a specific variable/array
- Understanding data persistence
- Debugging state issues
- Understanding queue mechanisms
- Finding where data is stored

---

### SERVICES_ARCHITECTURE.md
**What:** Service container pattern, service lifecycle, and service implementations

**Key Topics:**
- Service base class
- ServiceContainer registry
- Service initialization flow
- CacheService (cache management, cleanup, events)
- HistoryService (session stats, send history)
- NotificationService (notification dispatch, suppression)
- SecurityService (input sanitization, redaction)

**Use When:**
- Understanding service pattern
- Adding new services
- Debugging service initialization
- Understanding stateful systems
- Working with notification/history/cache systems

---

### HOOK_SYSTEM.md
**What:** Complete hook system architecture for intercepting RP addon communication

**Key Topics:**
- Hook installer with addon detection and compatibility checks
- Conflict detection system (strict mode, hook chaining)
- Request tracking hooks (TRP3 sendQuery, MSP Request)
- Send gating hooks (Chomp pipeline with 6 stages)
- Ghost mode hooks (SendObject pre-serialization, MSP exchange)
- MSP callback hooks (incoming request detection, NA guards)
- Scan reply hooks (TRP3, RPMapScan gating)
- Safety mechanisms (recursion prevention, state management)
- Hook state containers and guard flags
- Performance profiling and optimization

**Use When:**
- Understanding how TRP3FW intercepting profile sends
- Debugging hook conflicts or installation failures
- Adding new hooks to intercept other addons
- Troubleshooting addon compatibility issues
- Understanding Chomp pipeline stages
- Implementing ghost mode for new protocols

---

### GHOST_MODE.md
**What:** Complete ghost mode architecture for sending blank/alternate profiles

**Key Topics:**
- Ghost flag system (structure, setting, checking, consuming, expiration)
- Blank profile generation (TRP3 sections, MSP fields, minimal valid data)
- Alternate profile system (TRP3/MRP/XRP profile fetching)
- TRP3 → MSP conversion with caching (155-line conversion logic)
- Ghost mode triggering (location fail, start phase 169, alert-only)
- TRP3 ghost mode (SendObject pre-serialization hook)
- MSP ghost mode (callback detection, Chomp payload replacement)
- Start phase protection (Phase 169 detection and handling)
- Profile switch override integration
- Cleanup and expiration (30s TTL, corruption recovery)
- Security considerations (sanitization, validation, cache poisoning)
- Troubleshooting guide (common issues and fixes)

**Use When:**
- Understanding why blank profile sent instead of block
- Debugging ghost flag expiration issues
- Implementing alternate profile selection
- Understanding TRP3 vs MSP ghost mode differences
- Troubleshooting start phase protection
- Optimizing MSP conversion performance
- Fixing ghost mode activation failures

---

### SETTINGS_REFERENCE.md
**What:** All settings with descriptions, defaults, and valid values

**Key Topics:**
- Notification settings
- Location check modes (phase/map)
- SPVP (Secure Phase Verification Protocol) settings
- Ghost mode settings
- Cache durations
- Debug toggles
- Hook safety settings
- Batch processing settings
- Event-based clearing settings

**Use When:**
- Looking up a setting's purpose
- Understanding setting dependencies
- Finding valid setting values
- Debugging configuration issues
- Resetting to defaults

---

## Finding Specific Information

### "How do I...?"

**...understand why a profile was blocked?**
→ [DECISION_LOGIC.md](DECISION_LOGIC.md) - ProcessLocationDecision section

**...see what caches exist?**
→ [DATA_STRUCTURES.md](DATA_STRUCTURES.md) - Cache Systems section

**...know how phase checking works?**
→ [LOCATION_DETECTION.md](LOCATION_DETECTION.md) - Phase Detection section

**...add a new service?**
→ [SERVICES_ARCHITECTURE.md](SERVICES_ARCHITECTURE.md) - Adding Services section

**...configure cache TTLs?**
→ [CACHING_SYSTEM.md](CACHING_SYSTEM.md) - Configuration sections

**...understand ghost mode triggering?**
→ [GHOST_MODE.md](GHOST_MODE.md) - Triggering section

**...debug hook conflicts?**
→ [HOOK_SYSTEM.md](HOOK_SYSTEM.md) - Conflict Detection section

**...secure a phase with SPVP?**
→ [specifications/PHASE_ENCRYPTION.md](specifications/PHASE_ENCRYPTION.md) - Overview

**...debug WHO queries not working?**
→ [EPSILON_COMPATIBILITY.md](EPSILON_COMPATIBILITY.md) - Issue 1: WHO_LIST_UPDATE Event Not Firing

**...fix zone detection on custom Epsilon maps?**
→ [EPSILON_COMPATIBILITY.md](EPSILON_COMPATIBILITY.md) - Issue 2: Custom Map Names

**...understand Epsilon API limitations?**
→ [EPSILON_COMPATIBILITY.md](EPSILON_COMPATIBILITY.md) - Epsilon API Features

### "Where is...?"

**...the main decision entry point?**
→ [DECISION_LOGIC.md](DECISION_LOGIC.md) - CheckLocationAndNotify

**...the phase check queue?**
→ [DATA_STRUCTURES.md](DATA_STRUCTURES.md) - Queue Systems > Phase Check Queue

**...the WHO query logic?**
→ [LOCATION_DETECTION.md](LOCATION_DETECTION.md) - WHO Queries section

**...the cache cleanup code?**
→ [CACHING_SYSTEM.md](CACHING_SYSTEM.md) - Cache Cleanup section

**...the ghost flag stored?**
→ [DATA_STRUCTURES.md](DATA_STRUCTURES.md) - Ghost Mode State

**...session statistics tracked?**
→ [DATA_STRUCTURES.md](DATA_STRUCTURES.md) - History & Statistics

### "What does...?"

**...phaseCheckMode control?**
→ [SETTINGS_REFERENCE.md](SETTINGS_REFERENCE.md) - Location Check Modes

**...the burst stage do?**
→ [DECISION_LOGIC.md](DECISION_LOGIC.md) - Stage 6: BurstStage

**...CacheInterface do?**
→ [CACHING_SYSTEM.md](CACHING_SYSTEM.md) - Architecture Overview

**...the cascading system do?**
→ [LOCATION_DETECTION.md](LOCATION_DETECTION.md) - Cascading Logic Flow

**...EnableGhostForNextSend do?**
→ [GHOST_MODE.md](GHOST_MODE.md) - Ghost Flag System

## Cross-References

### Decision Pipeline → Location Detection
- Stage 7 (LocationStage) calls `CheckLocationCascading()`
- See [DECISION_LOGIC.md](DECISION_LOGIC.md) Stage 7 and [LOCATION_DETECTION.md](LOCATION_DETECTION.md) Cascading Logic

### Location Detection → Caching
- All location checks consult caches first
- See [LOCATION_DETECTION.md](LOCATION_DETECTION.md) cache checks and [CACHING_SYSTEM.md](CACHING_SYSTEM.md) cache descriptions

### Caching → Services
- CacheService manages cache cleanup and events
- See [CACHING_SYSTEM.md](CACHING_SYSTEM.md) Cleanup and [SERVICES_ARCHITECTURE.md](SERVICES_ARCHITECTURE.md) CacheService

### Decision Pipeline → Ghost Mode
- ApplyLocationDecision calls EnableGhostForNextSend
- See [DECISION_LOGIC.md](DECISION_LOGIC.md) ApplyLocationDecision and [GHOST_MODE.md](GHOST_MODE.md)

### Hooks → Decision Pipeline
- Hooks call CheckLocationAndNotify
- See [HOOK_SYSTEM.md](HOOK_SYSTEM.md) and [DECISION_LOGIC.md](DECISION_LOGIC.md) Entry Point

## File Organization

```
thoughts/
├── INDEX.md                       # This file
├── README.md                      # Overview and getting started
├── DECISION_LOGIC.md             # Pipeline, stages, decision flow
├── LOCATION_DETECTION.md         # Phase, WHO, map, cascading
├── CACHING_SYSTEM.md             # All caches, TTLs, optimization
├── DATA_STRUCTURES.md            # Variables, arrays, caches, state
├── SERVICES_ARCHITECTURE.md      # Services, container, lifecycle
├── HOOK_SYSTEM.md                # Hooks, conflicts, interception
├── GHOST_MODE.md                 # Ghost implementation
├── SETTINGS_REFERENCE.md         # Settings descriptions
├── EPSILON_COMPATIBILITY.md      # Epsilon server issues & workarounds
└── specifications/
    ├── PHASE_ENCRYPTION.md       # SPVP protocol specification (implemented)
    ├── SPVP_FALLBACK_PROFILE.md  # SPVP fallback profile spec
    └── REMOVE_ICONS.md           # Icon removal feature spec
```

## Maintenance Notes

**When adding new features:**
1. Update relevant architecture docs
2. Add cross-references to INDEX.md
3. Update DATA_STRUCTURES.md if new global variables added
4. Update SETTINGS_REFERENCE.md if new settings added

**When refactoring:**
1. Review all docs for outdated information
2. Update flow diagrams if pipeline changes
3. Update cache descriptions if caching logic changes
4. Update hook descriptions if hook targets change

**Keep docs in sync with code:**
- Architecture docs should reflect actual implementation
- Update docs in same commit as code changes
- Use docs for design validation before implementation

---

**Last Updated:** 2026-04-28
**Documentation Version:** 2.7
**Covers TRP3FW Version:** 2.9.2-hotfix

**Recent Updates:**
- 2026-04-28: Audit pass landed (see specifications/AUDIT_2026_BUGS_AND_GAPS.md):
  - Pipeline corrected from 8 to 7 stages (`PhaseInStage` was always the Chomp hook)
  - Cascading completion tracking refactored from counters to `expected`/`done` sets
  - HistoryService API hardened (`GetSendHistory`, `IsFirstSend`, `RecordSend`)
  - Burst replay: per-request `locationResult` cloning + `isUserInitiated` inheritance
  - `InteractionCache` invalidation now keys on mapID first, zone fallback
  - `EventService` registers `ZONE_CHANGED_NEW_AREA` (was missing)
  - Profile-send/scan history clears now `wipe()` instead of reassigning
  - Service singleton convention documented
- Added EPSILON_COMPATIBILITY.md documenting all Epsilon-specific fixes
- Updated LOCATION_DETECTION.md with WHO query workarounds and zone detection
- Updated SERVICES_ARCHITECTURE.md with service initialization order fix
- Updated CACHING_SYSTEM.md with negative caching documentation