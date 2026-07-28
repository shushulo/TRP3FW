# Feature Specification: Phase Check Command (`/trp3fw phasecheck`)

## 1. Overview
This feature adds a command to identify all players in the user's current zone who are also in the same Epsilon phase. It utilizes a two-step process:
1.  **Zone WHO Query**: Retrieves a list of all players in the current zone.
2.  **Phase Check**: Verifies which of those players are in the same phase as the user.

Results are output to the chat window, and all data is cached using the existing TRP3FW caching infrastructure.

## 2. User Interface
*   **Command**: `/trp3fw phasecheck [verbose]`
*   **Aliases**: None initially.
*   **Modes**:
    *   Default: Summary output only (count and statistics)
    *   `verbose`: Lists all players found in phase
*   **Feedback**:
    *   "Starting phase check for zone: [Zone Name]..."
    *   "Found [X] players in zone. Checking phases..."
    *   Progress indicators: "Progress: [X]/[Y] checked..." (every 10 players)
    *   Verbose mode: "|cff00ff00✓|r [PlayerName]" for each player in phase
    *   "Phase check complete. [Y]/[X] in phase. (Maps: [UniqueMapCount])"

## 3. Technical Implementation

### 3.1. Components

#### A. Command Handler (`commands.lua`)
*   Register `phasecheck` command with optional `verbose` flag.
*   Add duplicate prevention: Check `TRP3FW.phaseCheckInProgress` flag.
*   Orchestrate the flow: Call Zone WHO -> callback -> Loop Phase Checks -> callback -> Print.
*   Track unique mapIDs for summary statistics.

#### B. Zone WHO Scanner (`location/who.lua`)
*   **New Function**: `TRP3FW:ScanZoneForPlayers(callback)`
*   **Logic**:
    *   Reuse `RunPrivileged` logic for `z-"ZoneName"`.
    *   Modify `TRP3FW.whoQueryPending` structure to support scan mode:
        ```lua
        TRP3FW.whoQueryPending = {
            playerName = nil,
            callback = nil,
            scanMode = false,  -- NEW: indicates zone scan vs single player
            results = {},      -- NEW: collect all results in scan mode
        }
        ```
    *   Update `whoFrame`'s `OnEvent` handler:
        *   If `scanMode` is true, collect *all* names from `C_FriendList.GetWhoInfo`.
        *   Pass the full list of names (and zone info) to the callback.
    *   **Caching**: Ensure `whoZone` cache is populated for all results (existing logic does this, verify it runs in `scanMode`).

#### C. Batch Phase Checker (`location/phase.lua`)
*   Reuse `TRP3FW:CheckPlayerPhase`.
*   **Logic**:
    *   Iterate through the list of names returned by the WHO scan.
    *   Call `CheckPlayerPhase` for each name.
    *   **Optimization**: Use `TRP3FW:QueuePhaseCheck` implicitly by calling `CheckPlayerPhase`.
    *   **Tracking Completion**:
        *   Since `CheckPlayerPhase` is async, we need a way to track when the entire batch is done to print a consolidated list.
        *   Alternatively, print results incrementally as they return to avoid complex state management and long delays in feedback. *Decision: Incremental output is acceptable and simpler for V1.*

### 3.2. Data Flow
1.  User types `/trp3fw phasecheck`.
2.  `commands.lua` gets current zone name.
3.  Calls `TRP3FW:ScanZoneForPlayers(function(success, playerList, error) ... end)`.
4.  `ScanZoneForPlayers` sends `z-"Zone"` WHO query via `RunPrivileged`.
5.  `WHO_LIST_UPDATE` fires.
6.  `whoFrame` handler collects all names, caches them in `whoZone`, and calls callback with `playerList`.
7.  Command callback receives `playerList`.
8.  Prints "Found # players. Checking phases...".
9.  Iterates `playerList`:
    *   Calls `TRP3FW:CheckPlayerPhase(playerName, nil, function(inPhase, reason, mapID) ... end)`.
10. `CheckPlayerPhase` uses existing batching/caching.
11. Callback prints `playerName` if `inPhase` is true.

### 3.3. Cache Updates
*   **WHO Results**: Automatically added to `whoZone` cache by `whoFrame` handler (existing functionality).
*   **Phase Results**: Automatically added to `phaseCache` by `CheckPlayerPhase` (existing functionality).
*   **Interaction Cache**: Explicit addition to `interactionCache` is NOT recommended for a passive scan command to avoid polluting the "recently interacted" list used for high-priority gating.

## 4. Edge Cases & Constraints
*   **Duplicate Prevention**: Check `TRP3FW.phaseCheckInProgress` flag to prevent multiple simultaneous scans.
*   **Rate Limits**: WHO queries are rate-limited. The command should respect `TRP3FW.whoQueryCooldown` and fail gracefully if on cooldown.
*   **Truncation**: WoW/Epsilon limits WHO results to 50.
    *   *Mitigation*: Report "First 50 players scanned" if limit reached. (Full pagination is out of scope for V1).
*   **Phase Check Batching**: Queuing 50 players might saturate the privileged token bucket.
    *   The existing `phase.lua` logic handles queuing and token bucket management. It will process them in batches over time.
    *   User feedback should imply this might take a moment.
    *   **Token Awareness**: Warn user if `#TRP3FW.phaseCheckQueue > 20` that checks may take longer than usual.
*   **No Epsilon API**: Fail gracefully with an error message.

## 5. Proposed Code Changes

### `location/who.lua`
*   Modify `CheckPlayerViaWho` or extract core query logic to support `scanMode`.
*   Update `whoFrame` `OnEvent` to handle `scanMode` extraction of all results.

### `commands.lua`
```lua
elseif cmd == "phasecheck" then
    -- Duplicate prevention
    if TRP3FW.phaseCheckInProgress then
        TRP3FW:Error("Phase check already in progress. Please wait.")
        return
    end

    -- Parse verbose flag
    local verbose = (args and args:match("verbose"))

    -- Use currentZoneName (already tracked)
    local zone = TRP3FW.currentZoneName or GetRealZoneText()
    TRP3FW:Info("Starting phase check for zone: " .. zone)

    -- Token awareness warning
    if #TRP3FW.phaseCheckQueue > 20 then
        TRP3FW:Warn("Phase check queue is busy. This may take longer than usual.")
    end

    TRP3FW.phaseCheckInProgress = true

    TRP3FW:ScanZoneForPlayers(function(success, players, err)
        if not success then
            TRP3FW:Error("Zone scan failed: " .. tostring(err))
            TRP3FW.phaseCheckInProgress = false
            return
        end

        TRP3FW:Info("Found " .. #players .. " players. Checking phases...")

        local passed = 0
        local checked = 0
        local total = #players
        local uniqueMaps = {}

        for _, name in ipairs(players) do
            TRP3FW:CheckPlayerPhase(name, nil, function(inPhase, reason, mapID)
                checked = checked + 1

                if inPhase then
                    passed = passed + 1
                    if mapID then
                        uniqueMaps[mapID] = true
                    end
                    if verbose then
                        TRP3FW:Info("|cff00ff00✓|r " .. name)
                    end
                end

                -- Progress indicator every 10 players
                if checked % 10 == 0 and checked < total then
                    TRP3FW:Info("Progress: " .. checked .. "/" .. total .. " checked...")
                end

                -- Final summary
                if checked >= total then
                    local mapCount = 0
                    for _ in pairs(uniqueMaps) do
                        mapCount = mapCount + 1
                    end

                    TRP3FW:Info("Phase check complete. " .. passed .. "/" .. total ..
                                " in phase. (Maps: " .. mapCount .. ")")
                    TRP3FW.phaseCheckInProgress = false
                end
            end, "LOW") -- Use LOW priority to avoid blocking active RP
        end
    end)
```

## 6. Additional Changes

### Help Text (`commands.lua`)
Add to help command output:
```lua
"  /trp3fw phasecheck [verbose] - Scan zone for players in your phase (Epsilon only)"
```

## 7. Future Improvements
*   Pagination for >50 results.
*   UI window to display results instead of chat.
*   Integration with "White List" to auto-add found players.
*   Export results to a sharable format.
