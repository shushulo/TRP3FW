# TRP3 Firewall - Project TODO

## Phase 2: Modularization & Decoupling (Current)

### UI Modularization
- [x] Create `TabManager` architecture for lazy loading tabs.
- [x] Extract **Status** tab to `ui/tabs/Status.lua`.
- [x] Extract **Notifications** tab to `ui/tabs/Notifications.lua`.
- [x] Extract **Alerts** tab (including SPVP & Overrides) to `ui/tabs/Alerts.lua`.
- [x] Extract **Filters** tab to `ui/tabs/Filters.lua`.
- [x] Extract **Debug** tab to `ui/tabs/Debug.lua`.
- [x] Extract **Profiles** tab to `ui/tabs/Profiles.lua`.
- [x] Refactor `ui/settings.lua` to serve as a coordinator.
- [x] Implement defensive guards in `RefreshUI` to handle lazy-loaded elements.
- [x] Fix `nil` self errors in modular tab refresh calls.

### Feature Completeness & Bug Fixes
- [x] **Status Tracking:** Fix `HistoryService` to correctly increment session stats (Alerts, Blocks, Ghosts).
- [x] **Live Updates:** Implement persistent status update timer that survives tab switching.
- [x] **Epsilon Visibility:** Ensure SPVP and Start Phase settings are hidden/shown correctly based on API availability.
- [x] **Missing Methods:** Add `TRP3FW:Success()` to `core/utils.lua`.
- [x] **Cleanup:** Remove duplicate/legacy code blocks from `ui/settings.lua`.

## Phase 3: Future Optimizations (Planned)
- [ ] **Locale Support:** Move hardcoded strings in tabs to a localization table.
- [ ] **Unit Tests:** Add unit tests for `HistoryService` and `TabManager`.
- [ ] **Advanced Profiling:** Expand `Status.lua` to show more granular per-function timing.
