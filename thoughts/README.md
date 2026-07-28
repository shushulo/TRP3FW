# TRP3FW Architecture Documentation

**Comprehensive architecture reference for debugging, development, and understanding the codebase.**

## Purpose

This documentation provides in-depth architecture information without diving into actual code. Use these documents to:

- **Understand data flow** - How decisions are made from request to allow/block/ghost
- **Find variables/arrays** - Where specific data is stored and its structure
- **Debug issues** - Trace problems through the system without reading code
- **Add features** - Understand existing patterns before implementing new ones
- **Optimize performance** - Identify bottlenecks and caching opportunities

## Quick Start

**New to TRP3FW?** Start here:
1. [INDEX.md](INDEX.md) - Navigation hub for all documentation
2. [DECISION_LOGIC.md](DECISION_LOGIC.md) - Understand the core decision flow
3. [DATA_STRUCTURES.md](DATA_STRUCTURES.md) - Find where data is stored

**Working on a specific area?** Jump directly to:
- **Location checking** → [LOCATION_DETECTION.md](LOCATION_DETECTION.md)
- **Caching** → [CACHING_SYSTEM.md](CACHING_SYSTEM.md)
- **Settings** → [SETTINGS_REFERENCE.md](SETTINGS_REFERENCE.md)
- **Services** → [SERVICES_ARCHITECTURE.md](SERVICES_ARCHITECTURE.md)

## Documentation Files

### INDEX.md
**Navigation hub** - Start here to find specific information.

Contains:
- Quick navigation by topic
- Document summaries
- Cross-references between documents
- "How do I...?" lookup guide
- "Where is...?" lookup guide

**Use when:** You need to find information but don't know which document

---

### DECISION_LOGIC.md
**Decision pipeline and allow/block/ghost logic**

Contains:
- 7-stage pipeline architecture
- Entry point (`CheckLocationAndNotify`)
- Context creation (TOCTOU prevention)
- Each stage's logic (Whitelist, PhaseIn, Cache, Interaction, AlertFastPath, Burst, Location)
- Location decision processing
- Notification determination rules
- Burst request handling
- Settings fingerprinting

**Use when:**
- Debugging why a profile was allowed/blocked
- Understanding pipeline flow
- Adding new pipeline stages
- Modifying decision logic

---

### LOCATION_DETECTION.md
**Phase checking, WHO queries, map scanning, cascading**

Contains:
- Phase detection methods (party/raid, nameplate, target, batch)
- Batch targeting with dynamic token management
- Priority queue system
- WHO query system (zone/name queries)
- WHO caching (two-tier)
- WHO prepopulation
- Map scanning protocol (TRP3 broadcasts)
- Cascading evaluation logic
- Reliable vs unreliable failure detection
- Result combination rules

**Use when:**
- Understanding location check results
- Debugging phase/WHO/map checks
- Optimizing performance
- Troubleshooting Epsilon API issues

---

### CACHING_SYSTEM.md
**All cache layers, TTLs, eviction, optimization**

Contains:
- 9 cache types with detailed descriptions
- CacheInterface LRU implementation
- Cache TTLs and refresh thresholds
- Validated names persistent cache
- Cache cleanup (automatic & manual)
- Event-based cache clearing
- Cache size limits
- Performance optimizations (time caching, phase ID caching, MSP conversion caching)
- Cache monitoring commands

**Use when:**
- Understanding cache behavior
- Tuning cache durations
- Debugging cache-related issues
- Investigating performance
- Troubleshooting memory usage

---

### DATA_STRUCTURES.md
**Complete variable/array/queue/state reference**

Contains:
- Core namespace (`TRP3FW` table)
- Settings structure (`TRP3FW.Prefs`)
- All cache tables (9 types)
- Queue systems (phase-in, phase check, WHO, location check, burst)
- State tracking (zone/phase transitions, targeting, ghost)
- Hook state containers
- Session statistics
- Constants and priority levels
- Suppression & debouncing tables

**Use when:**
- Looking up a specific variable
- Understanding data persistence
- Debugging state issues
- Finding where data is stored
- Understanding queue mechanisms

---

### SERVICES_ARCHITECTURE.md
**Service container pattern, lifecycle, implementations**

Contains:
- Service base class
- ServiceContainer registry
- Service initialization flow
- CacheService (cache management, cleanup, events, interaction tracking)
- HistoryService (session stats, send history)
- NotificationService (notification dispatch, suppression)
- SecurityService (sanitization, redaction)
- Adding new services guide

**Use when:**
- Understanding service pattern
- Adding new services
- Debugging service initialization
- Working with notification/history/cache systems

---

### SETTINGS_REFERENCE.md
**All settings with descriptions, defaults, valid values**

Contains:
- Notification settings
- Location check modes (phase/map)
- Ghost mode settings
- Cache durations
- Cache size limits
- Phase check batching
- WHO query settings
- Transition settings
- Whitelisting
- Map scanning
- Hook safety
- Monitoring
- History & UI
- Cache clearing toggles
- Debug settings
- Redaction settings

**Use when:**
- Looking up setting purpose
- Finding valid setting values
- Understanding setting dependencies
- Debugging configuration

---

## Organization

```
thoughts/
├── README.md                      # This file - Overview and guide
├── INDEX.md                       # Navigation hub
├── DECISION_LOGIC.md              # Pipeline, stages, decision flow
├── LOCATION_DETECTION.md          # Phase, WHO, map, cascading
├── CACHING_SYSTEM.md              # All caches, TTLs, optimization
├── DATA_STRUCTURES.md             # Variables, arrays, queues, state
├── SERVICES_ARCHITECTURE.md       # Services, container, lifecycle
└── SETTINGS_REFERENCE.md          # Settings descriptions
```

## Documentation Principles

### What's Included
- **Architecture** - How systems work together
- **Data flow** - How requests are processed
- **Data structures** - What's stored where
- **Configuration** - What settings control
- **Integration points** - How to add new features

### What's Excluded
- **Actual code** - Read the source files for implementation
- **User guides** - See main README.md for user documentation
- **Tutorials** - These are reference docs, not tutorials
- **API documentation** - Function signatures are in comments in source

### Design Goals
1. **Find information quickly** - Good navigation and indexing
2. **Understand without reading code** - Sufficient detail for comprehension
3. **Debug efficiently** - Trace issues through systems
4. **Develop confidently** - Understand patterns before coding
5. **Maintain easily** - Clear structure for updates

## Maintenance

### When to Update

**Update docs when:**
- Adding new features (pipeline stages, services, caches)
- Changing data structures (adding fields, changing TTLs)
- Refactoring systems (changing flow, reorganizing)
- Fixing bugs that reveal missing documentation

**Update in same commit as code changes.**

### What to Update

**Always update:**
- File-specific content (e.g., add new cache to CACHING_SYSTEM.md)
- Cross-references in INDEX.md if adding new concepts
- DATA_STRUCTURES.md if adding global variables
- SETTINGS_REFERENCE.md if adding settings

**Consider updating:**
- INDEX.md "How do I...?" section for new use cases
- Related documents (e.g., if changing decision logic, update DECISION_LOGIC.md and INDEX.md)

### Validation

**Before committing doc changes:**
1. Check for broken cross-references
2. Verify code samples match actual patterns
3. Update file modification dates
4. Test navigation from INDEX.md to specific topics

## Contributing

When adding documentation:

1. **Follow existing structure** - Match formatting and organization
2. **Be specific** - Vague descriptions aren't helpful
3. **Show data structures** - Code blocks with actual structure
4. **Explain "why"** - Not just "what" but why it's designed that way
5. **Add cross-references** - Link to related sections in other docs
6. **Update INDEX.md** - Make new content discoverable

## Getting Help

**Can't find what you need?**

1. Check INDEX.md "How do I...?" section
2. Search across all .md files for keywords
3. Check DATA_STRUCTURES.md for variable locations
4. Look at cross-references in relevant docs
5. Read the actual source code as last resort

**Found an error?**
- Update the documentation
- Commit with descriptive message
- Consider if related docs also need updates

## Future Improvements

**Potential additions:**
- Sequence diagrams for complex flows
- Performance benchmarks and optimization targets
- Common debugging scenarios with solutions
- Testing strategies and test coverage
- Migration guides for major refactors

---

**Last Updated:** 2026-01-08
**Documentation Version:** 1.0
**Covers TRP3FW Version:** 2.9.2-hotfix
