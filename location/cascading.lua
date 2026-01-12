<<<<<<< Updated upstream
-- location/cascading.lua
-- Cascading location check logic - coordinates phase, WHO, and map scanning

local addonName, TRP3FW = ...

-- Constants
local START_PHASE_ID = 169  -- Epsilon start phase ID (blocks all transmissions)

-- ===================== Cascading Location Check =====================
-- Check location with multiple methods: Phase check AND/OR Map scan/WHO query

function TRP3FW:CheckLocationCascading(playerName, sendId, callback, options)
    options = options or {}
    TRP3FW.profiler.start("CheckLocationCascading")
    self:Debug("=== Starting cascading location check for "..playerName.." ===", "location")
    self:Debug("  hasEpsilonAPI: "..tostring(self.hasEpsilonAPI), "location")
    self:Debug("  phaseCheckMode: "..tostring(TRP3FW_Settings.phaseCheckMode), "location")
    self:Debug("  mapCheckMode: "..tostring(TRP3FW_Settings.mapCheckMode), "location")
    self:Debug("  useWhoQuery: "..tostring(TRP3FW_Settings.useWhoQuery), "location")

    -- NOTE: Start phase blocking is handled in hooks (trp3.lua, msp.lua) for OUTGOING profile sends
    -- This function evaluates INCOMING profile requests, so start phase check does not apply here
    -- Removing start phase check - it was incorrectly blocking outbound profile requests

    -- Level 1: Run checks if enabled (independent of alert/block settings)
    -- Allow overrides via options (e.g. for scan replies using different settings)
    local phaseCheckEnabled
    if options.phaseCheckEnabled ~= nil then
        phaseCheckEnabled = options.phaseCheckEnabled and self.hasEpsilonAPI
    else
        phaseCheckEnabled = self.hasEpsilonAPI and self:IsPhaseCheckEnabled()
    end

    local mapCheckEnabled
    if options.mapCheckEnabled ~= nil then
        mapCheckEnabled = options.mapCheckEnabled
    else
        mapCheckEnabled = self:IsMapCheckEnabled()
    end

    self:Debug("  phaseCheckEnabled: "..tostring(phaseCheckEnabled), "location")
    self:Debug("  mapCheckEnabled: "..tostring(mapCheckEnabled), "location")

    -- Prefer WHO query over map scan if Epsilon API is available and WHO query is enabled
    local useWhoInsteadOfMapScan = self.hasEpsilonAPI and TRP3FW_Settings.useWhoQuery and mapCheckEnabled
    local forceWhoNameOnly = options.whoNameOnly == true

    if not phaseCheckEnabled and not mapCheckEnabled then
        self:Debug("All location checks disabled or unavailable", "location")
        TRP3FW.profiler.stop("CheckLocationCascading")
        if callback then callback(nil, "disabled", "disabled") end
        return
    end

    -- Get player's current map and zone for comparison
    local myMapID = self:GetCurrentMapID()
    -- OPTIMIZATION: Use cached zone name instead of repeated API calls
    local myZone = TRP3FW.currentZoneName or "Unknown"

    if self.IsProfileSwitchOverrideActive and self:IsProfileSwitchOverrideActive() then
        self:Debug("[Cascading Check] Profile switch override active (phase 169 / map 1605) - bypassing location checks", "location")
        TRP3FW.profiler.stop("CheckLocationCascading")
        if callback then
            callback(true, nil, "profile_switch", nil, nil, myZone, {profileSwitch = true}, false, 0)
        end
        return
    end

    -- Check if we recently changed maps or phases (for warning about potential race conditions)
    local now = self:GetCurrentTime()
    local timeSinceTransition = now - self.lastZoneChangeTime
    local inTransitionGracePeriod = (TRP3FW_Settings.transitionGracePeriod > 0) and
                                     (timeSinceTransition < TRP3FW_Settings.transitionGracePeriod)

    -- Results storage
    local results = {
        phaseCheck = nil,    -- true/false/nil
        mapCheck = nil,      -- true/false/nil
        mapCacheAge = nil,   -- number: seconds since map check was cached (nil if not cached)
        theirMapID = nil,    -- Store their map if we can get it from phase check
        theirZone = nil,     -- Store their zone if we can get it from WHO query
        theirMapFromWho = nil, -- Store mapID at time of WHO query (our map context)
        mapSource = nil,     -- Track map check source (WHO cache, timeout, scan, etc.)
        myMapID = myMapID,
        myZone = myZone,
        checksComplete = 0,
        checksExpected = (phaseCheckEnabled and 1 or 0) + (mapCheckEnabled and 1 or 0),
        recentTransition = inTransitionGracePeriod,
        timeSinceTransition = timeSinceTransition,
        phaseDisabled = not phaseCheckEnabled,
        mapDisabled = not mapCheckEnabled,

        -- Cache tracking for notification display
        cacheInfo = {
            interactionCache = nil,  -- "hit" or nil
            phaseCache = nil,        -- "hit" or nil
            whoCache = nil,          -- "hit" or nil
            mapCache = nil,          -- "hit" or nil (for broadcast/scan caches)
            allowedSenders = nil,    -- "hit" or nil (tracked separately in decision.lua)
        }
    }

    local function evaluateResults()
        if results.checksComplete < results.checksExpected then
            return -- Wait for all checks to complete
        end

        TRP3FW:Debug("=== All location checks complete ===", "location")
        TRP3FW:Debug("  Phase check result: "..tostring(results.phaseCheck), "location")
        TRP3FW:Debug("  Map check result: "..tostring(results.mapCheck), "location")

        -- Determine final result and alert type
        -- Level 2 & 3: Evaluate check results and determine alerts
        local locationOK = true
        local alertType = nil
        local alertTypes = {}
        local checkDetails = {
            phase = {
                result = results.phaseCheck,
                source = results.phaseSource,
                method = results.phaseMethod,
                theirMapID = results.theirMapID,
                myMapID = results.myMapID,
                disabled = results.phaseDisabled
            },
            map = {
                result = results.mapCheck,
                source = results.mapSource,
                method = results.mapMethod,
                cacheAge = results.mapCacheAge,
                theirZone = results.theirZone,
                myZone = results.myZone,
                theirMapID = results.theirMapFromWho or results.theirMapID,
                myMapID = results.myMapID,
                skippedBecausePhase = results.mapSkippedBecausePhase,
                disabled = results.mapDisabled
            }
        }

    -- Phase Check Evaluation
    if phaseCheckEnabled then
        if results.phaseCheck == true then
            -- Confirmed same phase - phase OK
            TRP3FW:Debug("  Phase check: SAME PHASE", "location")
        elseif results.phaseCheck == false then
                -- Confirmed different phase
                TRP3FW:Debug("  Phase check FAILED: DIFFERENT PHASE", "location")

                -- BUGFIX: Check failed means locationOK should be false regardless of alert/block mode
                -- The block/alert setting only controls notification type, not whether the check matters
                -- Level 2: Mark as failed if blocking OR alerting is enabled
                if self:ShouldAlertOnPhase() or self:ShouldBlockOnPhase() then
                    locationOK = false
                    table.insert(alertTypes, "phase")
                    if self:ShouldAlertOnPhase() then
                        TRP3FW:Debug("    → Alert enabled, marking as failed with alert type", "location")
                    else
                        TRP3FW:Debug("    → Block enabled (no alert), marking as failed for blocking", "location")
                    end
                else
                    TRP3FW:Debug("    → Alert and block disabled, check failed silently", "location")
                end
            elseif results.phaseCheck == nil then
                -- API error or unavailable
                TRP3FW:Debug("  Phase check: UNAVAILABLE (API error or invalid name)", "location")
                
                -- SECURITY FIX: Fail-closed instead of fail-open
                -- Previously fell through to map check, allowing "Zone Match" to override "Phase Unknown"
                -- Now treats "Unknown" as a failure if strict checking is enabled
                if self:ShouldAlertOnPhase() or self:ShouldBlockOnPhase() then
                    locationOK = false
                    TRP3FW:Debug("  [DECISION] Setting locationOK=false due to phase=unknown (Fail-Closed active)", "location")
                    table.insert(alertTypes, "phase_unknown")
                    if self:ShouldAlertOnPhase() then
                        TRP3FW:Debug("    → Alert enabled, marking UNKNOWN phase as failed", "location")
                    else
                        TRP3FW:Debug("    → Block enabled, marking UNKNOWN phase as failed (fail-closed)", "location")
                    end
                else
                    TRP3FW:Debug("    → Alert/Block disabled, ignoring phase unknown state", "location")
                end
            end
        else
            TRP3FW:Debug("  Phase check: DISABLED/SKIPPED", "location")
        end

        -- Map Check Evaluation (independent of phase check)
        local mapSource = results.mapSource
        local function IsReliableMapFailure(source)
            if not source then return false end
            
            -- If phase check passed, treat transient WHO/Map failures (backoff, rate limit, timeout) as unreliable
            -- We only want to block if we have a definitive "NOT FOUND" or "MISMATCH"
            if results.phaseCheck == true then
                if source:find("backoff", 1, true) or 
                   source:find("rate_limit", 1, true) or 
                   source:find("timeout", 1, true) then
                    return false
                end

                -- If phase check passed via targeting/batch/nameplate (implies physical proximity),
                -- also treat generic "who_not_found" AND stale "cached" failures as unreliable.
                local phaseMethod = results.phaseMethod
                if phaseMethod and (phaseMethod:find("target", 1, true) or phaseMethod == "nameplate" or phaseMethod:find("group", 1, true) or phaseMethod == "batch") then
                    if source == "who_not_found" or source:find("who_not_found", 1, true) or source == "cached" then
                        TRP3FW:Debug("  Ignoring reliable failure '"..tostring(source).."' because phase check ("..tostring(phaseMethod)..") confirms physical presence", "location")
                        return false
                    end
                end
            end

            if source == "cached" then return true end
            if source:find("zone_mismatch", 1, true) or source:find("mapid_mismatch", 1, true) or source:find("no_zone", 1, true) then return true end
            -- Treat any WHO-based failure (including suffixes) as reliable
            if source:find("who", 1, true) then return true end
            -- Treat any map scan-based failure (including suffixes) as reliable
            if source:find("map_scan", 1, true) or source:find("scanned", 1, true) then return true end
            if source == "name_query" then return true end
            -- Treat phase check map mismatch as reliable
            if source:find("phase_check", 1, true) then return true end
            return false
        end

        if mapCheckEnabled then
            if results.mapCheck == true then
                -- Found in zone - map OK
                TRP3FW:Debug("  Map check: FOUND IN ZONE", "location")
            elseif results.mapCheck == false then
                if IsReliableMapFailure(mapSource) then
                    -- Check failed - not found in zone
                    TRP3FW:Debug("  Map check FAILED: NOT FOUND IN ZONE", "location")

                    -- BUGFIX: Check failed means locationOK should be false regardless of alert/block mode
                    -- The block/alert setting only controls notification type, not whether the check matters
                    -- Level 2: Mark as failed if blocking OR alerting is enabled
                    if self:ShouldAlertOnMap() or self:ShouldBlockOnMap() then
                        locationOK = false
                        table.insert(alertTypes, "map")
                        if self:ShouldAlertOnMap() then
                            TRP3FW:Debug("    → Alert enabled, marking as failed with alert type", "location")
                        else
                            TRP3FW:Debug("    → Block enabled (no alert), marking as failed for blocking", "location")
                        end
                    else
                        TRP3FW:Debug("    → Alert and block disabled, check failed silently", "location")
                    end
                else
                    TRP3FW:Debug("  Map check failed but source="..tostring(mapSource).." (treating as UNKNOWN)", "location")
                    -- SECURITY FIX: Fail-closed for map/WHO failures (rate_limit, timeout, etc)
                    if self:ShouldAlertOnMap() or self:ShouldBlockOnMap() then
                        locationOK = false
                        table.insert(alertTypes, "map_unknown")
                        TRP3FW:Debug("    → Map check UNKNOWN/FAILED ("..tostring(mapSource)..") - treating as fail (fail-closed)", "location")
                    end
                end
            else
                -- nil/undefined - shouldn't happen but handle gracefully
                TRP3FW:Debug("  Map check: NO RESULT", "location")
                -- SECURITY FIX: Fail-closed for no result
                if self:ShouldAlertOnMap() or self:ShouldBlockOnMap() then
                    locationOK = false
                    table.insert(alertTypes, "map_unknown")
                    TRP3FW:Debug("    → Map check NO RESULT - treating as fail (fail-closed)", "location")
                end
            end
        else
            TRP3FW:Debug("  Map check: DISABLED/SKIPPED", "location")
        end

        -- Special case: If phase check passed (true), player is definitely accessible
        -- Respect reliable map mismatches instead of always overriding
        if results.phaseCheck == true then
            local reliableMapFailure = mapCheckEnabled and results.mapCheck == false and IsReliableMapFailure(mapSource)
            if reliableMapFailure then
                TRP3FW:Debug("  Phase check passed but reliable map mismatch - keeping map alert/block", "location")
            else
                locationOK = true
                -- Still report map alert if map check failed (informational)
                -- but don't block
                TRP3FW:Debug("  Phase check passed - overriding locationOK to true (player is accessible)", "location")
            end
        end

        -- Create combined alert type
        if #alertTypes > 0 then
            alertType = table.concat(alertTypes, "+")
        end

        -- Log zone information if available
        if results.theirZone and results.myZone then
            if results.theirZone ~= results.myZone then
                TRP3FW:Debug("  Zone mismatch: theirs="..tostring(results.theirZone)..", mine="..tostring(results.myZone), "location")
            else
                TRP3FW:Debug("  Same zone: "..tostring(results.myZone), "location")
            end
        end

        TRP3FW:Debug("  Final result: locationOK="..tostring(locationOK)..", alertType="..tostring(alertType), "location")
        if results.recentTransition then
            TRP3FW:Debug("  Recent transition detected: "..string.format("%.1f", results.timeSinceTransition).."s ago (within "..TRP3FW_Settings.transitionGracePeriod.."s grace period)", "location")
        end
        TRP3FW.profiler.stop("CheckLocationCascading")
        if callback then callback(locationOK, alertType, "combined", results.mapCacheAge, results.theirZone, results.myZone, results.cacheInfo, results.recentTransition, results.timeSinceTransition, checkDetails) end
    end

    -- Helper function to start map check
    local function startMapCheck(priority)
        if not mapCheckEnabled then
            results.checksComplete = results.checksComplete + 1
            evaluateResults()
            return
        end

        -- Fast-path: use cached map scan / broadcast data before WHO/scan
        local CI = TRP3FW.CacheInterface
        local cacheDuration = TRP3FW_Settings.scanCacheDuration or 120
        local cacheFailDuration = TRP3FW_Settings.scanCacheFailureDuration or 10
        local strictNonceRequired = TRP3FW_Settings and TRP3FW_Settings.scanResponseRequireNonce
        local nowTs = TRP3FW:GetCurrentTime()
        if CI then
            local cached = CI:Get("mapScan", playerName)
            local broadcast = CI:Get("broadcast", playerName)
            local function isFresh(entry, mapID)
                if not entry then return false end
                local ts = type(entry) == "table" and entry.timestamp or entry
                if not ts then return false end
                local duration = cacheDuration
                local entryFound = type(entry) == "table" and entry.found
                if entryFound == false then
                    duration = cacheFailDuration
                end
                if mapID and myMapID and mapID ~= myMapID then
                    duration = cacheFailDuration
                end
                return (nowTs - ts) <= duration
            end

            -- Prefer explicit map scan cache
            if isFresh(cached, cached and cached.mapID) then
                local mapID = cached.mapID
                local age = nowTs - cached.timestamp
                local okNonce = not strictNonceRequired or cached.verified ~= false
                if okNonce then
                    if mapID and myMapID and mapID ~= myMapID then
                        results.mapCheck = false
                        results.mapSource = "map_cache_mismatch"
                        results.mapMethod = results.mapSource
                        results.mapCacheAge = age
                        results.checksComplete = results.checksComplete + 1
                        results.cacheInfo.mapScanCache = "hit" -- Specific mapScan cache hit
                        TRP3FW:Debug("Map cache mismatch (mapScan) for "..playerName.." mapID="..tostring(mapID).." myMapID="..tostring(myMapID).." (age="..string.format("%.1f", age).."s)", "location")
                        evaluateResults()
                        return
                    end
                    if cached.found ~= nil then
                        results.mapCheck = cached.found
                    else
                        results.mapCheck = (mapID and myMapID and mapID == myMapID) or true
                    end
                    results.mapSource = "map_cache_match"
                    results.mapMethod = results.mapSource
                    results.mapCacheAge = age
                    results.theirMapID = mapID or results.theirMapID
                    results.checksComplete = results.checksComplete + 1
                    results.cacheInfo.mapScanCache = "hit" -- Specific mapScan cache hit
                    TRP3FW:Debug("Map cache hit (mapScan) for "..playerName.." (age="..string.format("%.1f", age).."s, mapID="..tostring(mapID)..")", "location")
                    evaluateResults()
                    return
                end
            end

            -- Fallback: recent broadcast cache
            if isFresh(broadcast) then
                local ts = type(broadcast) == "table" and broadcast.timestamp or broadcast
                local mapID = type(broadcast) == "table" and broadcast.mapID or nil
                local age = nowTs - ts
                local okNonce = not strictNonceRequired or (type(broadcast) ~= "table" or broadcast.verified ~= false)
                if okNonce then
                    if mapID and myMapID and mapID ~= myMapID then
                        results.mapCheck = false
                        results.mapSource = "map_cache_mismatch_broadcast"
                        results.mapMethod = results.mapSource
                        results.mapCacheAge = age
                        results.checksComplete = results.checksComplete + 1
                        results.cacheInfo.broadcastCache = "hit" -- Specific broadcast cache hit
                        TRP3FW:Debug("Map cache mismatch (broadcast) for "..playerName.." mapID="..tostring(mapID).." myMapID="..tostring(myMapID).." (age="..string.format("%.1f", age).."s)", "location")
                        evaluateResults()
                        return
                    end
                    results.mapCheck = true
                    results.mapSource = "map_cache_match_broadcast"
                    results.mapMethod = results.mapSource
                    results.mapCacheAge = age
                    results.theirMapID = mapID or results.theirMapID
                    results.checksComplete = results.checksComplete + 1
                    results.cacheInfo.broadcastCache = "hit" -- Specific broadcast cache hit
                    TRP3FW:Debug("Map cache hit (broadcast) for "..playerName.." (age="..string.format("%.1f", age).."s, mapID="..tostring(mapID)..")", "location")
                    evaluateResults()
                    return
                end
            end
        end

        if useWhoInsteadOfMapScan then
            TRP3FW:Debug("Starting WHO query (preferred over map scan)...", "location")
            -- trackStats=true: This is a real profile request, count toward statistics
            -- For fast scan reply windows, callers can request whoName-only mode to avoid
            -- spending time on a zone query when prepopulation already warmed the cache.
            TRP3FW:CheckPlayerViaWho(playerName, sendId, function(found, source, cacheAge, theirZone, theirMapID)
                results.mapCheck = found
                results.mapCacheAge = cacheAge
                results.theirZone = theirZone
                results.theirMapFromWho = theirMapID or results.theirMapFromWho
                results.mapSource = source
                results.mapMethod = source

                if not theirZone and theirMapID and myMapID and theirMapID ~= myMapID then
                    results.mapCheck = false
                    results.mapSource = (source or "who_query") .. "_mapid_mismatch"
                    results.mapMethod = results.mapSource
                end

                -- If WHO provided a zone but no mapID, compare zones even if we know our mapID
                if theirZone and myZone and not theirMapID then
                    local sameZone = (theirZone == myZone)
                    if not sameZone then
                        results.mapCheck = false
                        results.mapSource = (source or "who_query") .. "_zone_mismatch"
                        results.mapMethod = results.mapSource
                    else
                        results.mapCheck = true
                        results.mapSource = (source or "who_query") .. "_zone_match"
                        results.mapMethod = results.mapSource
                    end
                end

                -- If we don't know our map ID (custom map), fall back to zone string comparison
                if not myMapID then
                    if theirZone and myZone then
                        local sameZone = theirZone == myZone
                        results.mapCheck = sameZone
                        results.mapSource = (source or "who_query") .. (sameZone and "_zone_match" or "_zone_mismatch")
                        results.mapMethod = results.mapSource
                        TRP3FW:Debug("[WHO Fallback] myZone="..tostring(myZone)..", theirZone="..tostring(theirZone)..", match="..tostring(sameZone), "location")
                    else
                        -- No zone info to compare; treat as a miss so user gets alerted
                        results.mapCheck = false
                        results.mapSource = (source or "who_query") .. "_no_zone"
                        results.mapMethod = results.mapSource
                        TRP3FW:Debug("[WHO Fallback] No zone info available (myZone="..tostring(myZone)..", theirZone="..tostring(theirZone).."), treating as not found", "location")
                    end
                end

                results.checksComplete = results.checksComplete + 1

                -- Track WHO cache hit if source is "cached"
                if source == "cached" then
                    results.cacheInfo.whoCache = "hit"
                end

                local mapInfoStr = results.theirMapFromWho and (" mapID:"..tostring(results.theirMapFromWho)) or ""
                TRP3FW:Debug("WHO query complete: "..(found and "FOUND" or "NOT FOUND")..(cacheAge and " (cached "..string.format("%.1f", cacheAge).."s ago)" or "")..(theirZone and " in zone: "..theirZone or "")..mapInfoStr, "location")
                evaluateResults()
            end, true, forceWhoNameOnly, priority)
        else
            TRP3FW:Debug("Starting map scan...", "location")
            TRP3FW:MapScan(playerName, sendId, function(found, source, cacheAge)
                results.mapCheck = found
                results.mapCacheAge = cacheAge
                results.mapSource = source
                results.mapMethod = source
                results.checksComplete = results.checksComplete + 1

                -- Track map cache hit if source is "cached" or "recent_broadcast"
                if source == "cached" or source == "recent_broadcast" then
                    results.cacheInfo.mapCache = "hit"
                end

                TRP3FW:Debug("Map scan complete: "..(found and "FOUND" or "NOT FOUND")..(cacheAge and " (cached "..string.format("%.1f", cacheAge).."s ago)" or ""), "location")
                evaluateResults()
            end)
        end
    end

    -- Check interaction cache first (mouseover/target)
    -- NOTE: Stats are tracked in decision.lua where the interaction cache is checked first
    -- This is a redundant safety check in case something calls CheckLocationCascading directly
    local CI = self.CacheInterface
    local interactionCached = CI and CI:Get("interaction", playerName) or nil
    if interactionCached then
        -- CacheInterface returns value directly (always table format)
        local timestamp = interactionCached.timestamp
        if timestamp and (self:GetCurrentTime() - timestamp) < TRP3FW_Settings.interactionCacheDuration then
            local age = self:GetCurrentTime() - timestamp
            self:Debug("Interaction cache hit for "..playerName.." (cached "..string.format("%.1f", age).."s ago) - allowing immediately", "location")
            local cacheInfo = { interactionCache = "hit" }
            TRP3FW.profiler.stop("CheckLocationCascading")
			if callback then callback(true, nil, "interaction_cache", age, nil, nil, cacheInfo, inTransitionGracePeriod, timeSinceTransition, nil) end
			return
		end
	end

    -- Start phase check if enabled (takes priority)
    if phaseCheckEnabled then
        self:Debug("Starting phase check...", "location")
        self:CheckPlayerPhase(playerName, sendId, function(inPhase, source, theirMapID, phaseMethod)
            results.phaseCheck = inPhase
            results.theirMapID = theirMapID
            results.phaseSource = source
            results.phaseMethod = phaseMethod
            results.checksComplete = results.checksComplete + 1

            -- Track cache hit if source is "cached" or "cached_late" (from batch optimization)
            if source == "cached" or source == "cached_late" then
                results.cacheInfo.phaseCache = "hit"
            elseif source == "interaction_cache" then
                results.cacheInfo.interactionCache = "hit"
            elseif source == "allowed_cache" then
                results.cacheInfo.allowedSenders = "hit"
            end

            TRP3FW:Debug("Phase check complete: "..(inPhase and "IN PHASE" or tostring(inPhase)), "location")
            if theirMapID then
                TRP3FW:Debug("  Their map ID: "..tostring(theirMapID)..", My map ID: "..tostring(results.myMapID), "location")
            end

            -- If phase check succeeded, player is accessible
            if inPhase == true then
                TRP3FW:Debug("  Player in same phase", "location")

                -- If we have their map ID, decide immediately
                if mapCheckEnabled and theirMapID and results.myMapID then
                    if theirMapID == results.myMapID then
                        TRP3FW:Debug("  Map ID match from phase check ("..tostring(theirMapID)..") - skipping WHO/Scan", "location")
                        results.mapCheck = true
                        results.mapSource = "phase_check_match"
                        results.mapMethod = phaseMethod
                        results.checksComplete = results.checksComplete + 1
                        evaluateResults()
                        return
                    else
                        TRP3FW:Debug("  Phase OK but map ID mismatch (their="..tostring(theirMapID).." mine="..tostring(results.myMapID)..") - treating as reliable map fail", "location")
                        results.mapCheck = false
                        results.mapSource = "phase_check_mismatch"
                        results.mapMethod = phaseMethod
                        results.checksComplete = results.checksComplete + 1
                        evaluateResults()
                        return
                    end
                end

                -- If phase was confirmed via target/nameplate/group/batch (implies visibility), assume same map unless a later reliable map fail overrides
                if mapCheckEnabled and phaseMethod and (phaseMethod:find("target", 1, true) or phaseMethod == "nameplate" or phaseMethod:find("group", 1, true) or phaseMethod == "batch") then
                    TRP3FW:Debug("  Phase via target/group/batch implies same map - scheduling low-priority map verification (method="..tostring(phaseMethod)..")", "location")
                    
                    -- Proceed with map check, but use LOW priority WHO query if needed
                    -- This ensures we don't block the profile send, but we still try to verify the map ID
                    startMapCheck("who_map_verification")
                    return
                end

                if mapCheckEnabled then
                     TRP3FW:Debug("  Proceeding with map check (map check enabled, no mapID from phase)", "location")
                     startMapCheck()
                else
                     TRP3FW:Debug("  Skipping map check (map check disabled)", "location")
                     results.checksComplete = results.checksComplete + 1
                     results.mapSkippedBecausePhase = true
                     evaluateResults()
                end
            else
                -- Phase check failed or returned nil - proceed with map check
                TRP3FW:Debug("  Player not in same phase - proceeding with map check", "location")
                startMapCheck()
            end
        end)
    else
        -- No phase check, go straight to map check
        startMapCheck()
    end
end
=======
-- location/cascading.lua
-- Cascading location check logic - coordinates phase, WHO, and map scanning

local addonName, TRP3FW = ...

-- Constants
local START_PHASE_ID = 169  -- Epsilon start phase ID (blocks all transmissions)

-- ===================== Cascading Location Check =====================
-- Check location with multiple methods: Phase check AND/OR Map scan/WHO query

function TRP3FW:CheckLocationCascading(playerName, sendId, callback, options)
    options = options or {}
    TRP3FW.profiler.start("CheckLocationCascading")
    self:Debug("=== Starting cascading location check for "..playerName.." ===", "location")
    
    local now = self:GetCurrentTime()

    -- OPTIMIZATION #1: Start Phase Early Exit (Fail Fast)
    if TRP3FW_Settings.blockStartPhase then
        local currentPhaseID = self:GetCurrentPhaseID()
        if currentPhaseID == START_PHASE_ID then
            TRP3FW.profiler.stop("CheckLocationCascading")
            if callback then callback(false, "start_phase_block", "start_phase", 0, nil, nil, {}, false, 0, nil) end
            return
        end
    end

    -- OPTIMIZATION #2: Interaction Cache Fast-Path (Success Fast)
    local CI = self.CacheInterface
    local interaction = CI and CI:Get("interaction", playerName)
    if interaction and (now - interaction.timestamp) < TRP3FW_Settings.interactionCacheDuration then
        local inTransitionGracePeriod = (now - (self.lastZoneChangeTime or 0)) < (TRP3FW_Settings.transitionGracePeriod or 3)
        TRP3FW.profiler.stop("CheckLocationCascading")
        if callback then callback(true, nil, "interaction_cache", now - interaction.timestamp, nil, nil, { interactionCache = "hit" }, inTransitionGracePeriod, 0, nil) end
        return
    end

    local myMapID = C_Map.GetBestMapForUnit("player")
    local myZone = GetRealZoneText()
    
    local timeSinceZoneChange = now - (self.lastZoneChangeTime or 0)
    local timeSincePhaseChange = now - (self.lastPhaseChangeTime or 0)
    local timeSinceTransition = math.min(timeSinceZoneChange, timeSincePhaseChange)
    local inTransitionGracePeriod = timeSinceTransition < (TRP3FW_Settings.transitionGracePeriod or 3)

    local phaseCheckEnabled = self.hasEpsilonAPI and (options.phaseCheckEnabled ~= false and self:IsPhaseCheckEnabled())
    local mapCheckEnabled = options.mapCheckEnabled ~= false and self:IsMapCheckEnabled()
    local spvpEnabled = options.spvpEnabled
    local spvpPhaseID = options.spvpPhaseID
    local spvpSalt = options.spvpSalt

    -- Fallback: If SPVPStage skipped it (e.g. during async load), try to resolve now
    if spvpEnabled == nil and TRP3FW_Settings.spvpEnabled and self.hasEpsilonAPI then
        local currentPhaseID = self:GetCurrentPhaseID()
        local salt = self:GetPhaseSalt(currentPhaseID)
        if salt and salt ~= "" then
            spvpEnabled = true
            spvpPhaseID = currentPhaseID
            spvpSalt = salt
            TRP3FW:Debug("SPVP enabled via late-resolution in Cascading Check", "location")
        end
    end

    -- MUTUAL EXCHANGE OPTIMIZATION: Check for existing SPVP session
    local existingSessionID = nil
    if spvpEnabled then
        for id, session in pairs(self.spvpSessions or {}) do
            if session.playerName == playerName then
                existingSessionID = id
                break
            end
        end
    end

    local spvpMode = TRP3FW_Settings.spvpMode or "off"

    -- Results storage
    local results = {
        phaseCheck = nil,    -- true/false/nil
        mapCheck = nil,      -- true/false/nil
        spvpCheck = nil,     -- true/false/nil
        mapCacheAge = nil,
        theirMapID = nil,
        theirZone = nil,
        theirMapFromWho = nil,
        mapSource = nil,
        spvpSource = nil,
        phaseSource = nil,
        phaseMethod = nil,
        myMapID = myMapID,
        myZone = myZone,
        checksComplete = 0,
        checksExpected = 0, -- Set dynamically
        recentTransition = inTransitionGracePeriod,
        timeSinceTransition = timeSinceTransition,
        phaseDisabled = not phaseCheckEnabled,
        mapDisabled = not mapCheckEnabled,
        spvpDisabled = not spvpEnabled, -- SYNCED: correctly reflects late resolution
        cacheInfo = {
            interactionCache = nil,
            phaseCache = nil,
            whoCache = nil,
            mapCache = nil,
            spvpCache = nil,
            allowedSenders = nil,
        }
    }

    local function evaluateResults()
        -- OPTIMIZATION #3: Early Success (Don't wait for slow SPVP if standard checks pass)
        if results.checksComplete < results.checksExpected then
            local canEarlySuccess = (results.phaseCheck == true and results.mapCheck == true)
            -- Only allow early success if phase verification is strong (Targeting/Nameplate/Group)
            -- We don't trust "cached" alone for early exit without SPVP confirming
            local function isMethodStrongLocal(m) 
                return m and (m:find("target") or m:find("batch") or m == "nameplate" or m == "group") 
            end
            local isStrongPhase = isMethodStrongLocal(results.phaseMethod)
            
            if canEarlySuccess and isStrongPhase and spvpMode ~= "required" then
                TRP3FW:Debug("Early Success triggered: Phase/Map verified via "..tostring(results.phaseMethod).." (skipping pending SPVP wait)", "location")
                -- Proceed to evaluation logic below
            else
                return -- Wait for all checks
            end
        end

        TRP3FW:Debug("=== All location checks complete ===", "location")
        local locationOK = true
        local alertType = nil
        local alertTypes = {}
        
        local checkDetails = {
            phase = { result = results.phaseCheck, source = results.phaseSource, method = results.phaseMethod, theirMapID = results.theirMapID, myMapID = results.myMapID, disabled = results.phaseDisabled },
            map = { result = results.mapCheck, source = results.mapSource, method = results.mapMethod, cacheAge = results.mapCacheAge, theirZone = results.theirZone, myZone = results.myZone, theirMapID = results.theirMapFromWho or results.theirMapID, myMapID = results.myMapID, skippedBecausePhase = results.mapSkippedBecausePhase, disabled = results.mapDisabled },
            spvp = { result = results.spvpCheck, source = results.spvpSource, disabled = results.spvpDisabled }
        }

        local spvpVerified = (results.spvpCheck == true) or (CI and CI:Get("spvpVerified", playerName) ~= nil)

        -- 1. SPVP Required failure
        if spvpEnabled and spvpMode == "required" and not spvpVerified then
            locationOK = false
            table.insert(alertTypes, results.spvpSource == "timeout" and "spvp_timeout" or "spvp_failed")
        end

        -- 2. Phase Check Evaluation
        if phaseCheckEnabled then
            if results.phaseCheck == false and not spvpVerified then
                if self:ShouldAlertOnPhase() or self:ShouldBlockOnPhase() then
                    locationOK = false
                    table.insert(alertTypes, "phase")
                end
            elseif results.phaseCheck == nil and not spvpVerified then
                if self:ShouldAlertOnPhase() or self:ShouldBlockOnPhase() then
                    locationOK = false
                    table.insert(alertTypes, "phase_unknown")
                end
            end
        end

        -- Update checkDetails for notification display
        if spvpVerified then
            checkDetails.phase.result = true
            checkDetails.phase.source = results.spvpSource or "spvp"
            checkDetails.phase.method = "spvp"
        end

        -- 3. Map Check Evaluation
        local function IsReliableMapFailure(source)
            if not source then return false end
            
            -- Throttles and backoffs are always unreliable signals of location
            if source:find("backoff") or source:find("rate_limit") then return false end

            local isVerified = results.phaseCheck == true or spvpVerified
            -- Nearness signal: proves they are physically nearby (not just same-phase)
            -- We check both phase and map methods for targeting evidence
            local function isMethodTargeting(m) 
                return m and (m:find("target") or m:find("batch") or m == "nameplate") 
            end
            local isNear = isMethodTargeting(results.phaseMethod) or isMethodTargeting(results.mapMethod)

            if isVerified then
                -- If we are SURE they are nearby (targeting confirmed), then timeouts and missing info are unreliable
                if isNear then
                    if source:find("timeout") or source == "who_not_found" or source == "cached" then return false end
                end
            end
            
            -- Standard reliable failure sources (mismatch, explicit who/scanned fail)
            local isReliable = (source == "cached" or source:find("mismatch") or source:find("no_zone") or source:find("who") or source:find("scanned"))
            
            -- Timeouts are considered reliable failures if we don't have a nearness signal (Targeting)
            -- (Unless we are in a transition grace period where everything is unreliable)
            if source:find("timeout") and not results.recentTransition then
                isReliable = not isNear
            end

            return isReliable
        end

        local function isMethodStrong(m) 
            return m and (m:find("target") or m:find("batch") or m == "nameplate" or m == "group") 
        end
        local isPhaseStrong = isMethodStrong(results.phaseMethod) or (results.phaseMethod == "spvp" and results.mapMethod == "target")

        -- Cleanup confusion: If phase verified via strong signal, map check failure is irrelevant noise
        if (results.phaseCheck == true or spvpVerified) and isPhaseStrong then
            if results.mapCheck == false then
                 results.mapCheck = true
                 results.mapSource = "ignored_targeting_verified"
                 results.mapSkippedBecausePhase = true
                 
                 -- Update details for display
                 checkDetails.map.result = true
                 checkDetails.map.source = "ignored_targeting_verified"
                 checkDetails.map.skippedBecausePhase = true
            end
        end

        if mapCheckEnabled then
            if results.mapCheck == false then
                if IsReliableMapFailure(results.mapSource) then
                    if self:ShouldAlertOnMap() or self:ShouldBlockOnMap() then
                        locationOK = false
                        table.insert(alertTypes, "map")
                    end
                else
                    if self:ShouldAlertOnMap() or self:ShouldBlockOnMap() then
                        locationOK = false
                        table.insert(alertTypes, "map_unknown")
                    end
                end
            elseif results.mapCheck == nil then
                if self:ShouldAlertOnMap() or self:ShouldBlockOnMap() then
                    locationOK = false
                    table.insert(alertTypes, "map_unknown")
                end
            end
        end

        -- 4. Overrides
        if results.phaseCheck == true or spvpVerified then
            local reliableMapFailure = mapCheckEnabled and results.mapCheck == false and IsReliableMapFailure(results.mapSource)
            if not reliableMapFailure then
                locationOK = true
                alertTypes = {} -- CLEAR ALERTS on success!
                
                -- FORCE NOTIFICATION TO SHOW SUCCESS
                if spvpVerified and results.phaseCheck ~= true then
                    results.phaseCheck = true
                    results.phaseSource = results.spvpSource or "spvp"
                    results.phaseMethod = "spvp"
                    
                    -- Update checkDetails for notification
                    checkDetails.phase.result = true
                    checkDetails.phase.source = results.phaseSource
                    checkDetails.phase.method = results.phaseMethod
                end
                
                TRP3FW:Debug("  Final decision: ALLOW (Phase verified and no reliable map fail)", "location")
            end
        end

        if #alertTypes > 0 then alertType = table.concat(alertTypes, "+") else alertType = nil end
        TRP3FW.profiler.stop("CheckLocationCascading")
        if callback then callback(locationOK, alertType, "combined", results.mapCacheAge, results.theirZone, results.myZone, results.cacheInfo, results.recentTransition, results.timeSinceTransition, checkDetails) end
    end

    local function startStandardChecks(priority)
        -- Determine expected checks (Phase + Map)
        -- We set this upfront so the cascading logic waits for both, even if serialized
        if results.checksExpected == 0 or results.checksExpected == 1 then
            results.checksExpected = results.checksComplete + (phaseCheckEnabled and (results.phaseCheck == nil and 1 or 0) or 0) + (mapCheckEnabled and (results.mapCheck == nil and 1 or 0) or 0)
        end

        local function runMapCheck()
            if not mapCheckEnabled or results.mapCheck ~= nil or results.mapCheckStarted then
                return
            end

            results.mapCheckStarted = true
            
            local function handleMap(found, source, age, method, tMapID, tZone)
                -- Avoid double-resolving if fallback already triggered
                if results.mapCheck ~= nil then return end
                
                results.mapCheck = found
                results.mapSource = source
                results.mapMethod = method or source
                results.mapCacheAge = age
                results.theirMapID = tMapID or results.theirMapID
                results.theirZone = tZone or results.theirZone
                results.checksComplete = results.checksComplete + 1
                evaluateResults()
            end

            local function runMapScan()
                TRP3FW:Debug("Starting map scan (final fallback)...", "location")
                self:MapScan(playerName, sendId, function(found, source, age)
                    if source:find("cached") then results.cacheInfo.mapCache = "hit" end
                    handleMap(found, source, age)
                end)
            end

            -- Priority 1: WHO Query (Epsilon only, silent)
            if useWhoInsteadOfMapScan then
                TRP3FW:Debug("Starting WHO query sequence (preferred over map scan)...", "location")
                
                self:CheckPlayerViaWho(playerName, sendId, function(found, source, age, zone, tMapID)
                    if source == "cached" then results.cacheInfo.whoCache = "hit" end
                    
                    -- Check if we should fall back to Map Scan
                    -- Technical failures (timeout, backoff, rate limit) should trigger Map Scan
                    -- Definitive results (who_query, who_not_found, cached) should NOT.
                    local isTechnicalFailure = source:find("timeout") or source:find("backoff") or source:find("rate_limit") or source:find("error") or source:find("full")
                    
                    if isTechnicalFailure and TRP3FW.detectedAddons.MapScanner then
                         -- If WHO failed due to technical reasons, try Map Scan if available.
                         TRP3FW:Debug("WHO failed technically ("..tostring(source).."), falling back to Map Scan", "location")
                         runMapScan()
                    else
                        local f = found
                        -- Verify map ID match if zone was returned but mapID is available
                        if not zone and tMapID and myMapID and tMapID ~= myMapID then f = false end
                        handleMap(f, source, age, source, tMapID, zone)
                    end
                end, true, forceWhoNameOnly, priority)
            else
                -- Priority 2: Map Scan (Visible broadcast)
                runMapScan()
            end
        end

        local function handlePhaseResult(inPhase, source, theirMapID, phaseMethod)
            results.phaseCheck, results.theirMapID, results.phaseSource, results.phaseMethod = inPhase, theirMapID, source, phaseMethod
            results.checksComplete = results.checksComplete + 1
            if source and source:find("cached") then results.cacheInfo.phaseCache = "hit" end
            
            -- CHECK: Can we skip the map check?
            if mapCheckEnabled and results.mapCheck == nil and not results.mapCheckStarted then
                local isStrongSignal = phaseMethod and (phaseMethod:find("target") or phaseMethod == "nameplate" or phaseMethod == "group")
                if inPhase == true and isStrongSignal then
                    TRP3FW:Debug("Skipping map check (Phase check passed via "..tostring(phaseMethod)..")", "location")
                    results.mapCheck = true
                    results.mapSource = "skipped_phase_verified"
                    results.mapMethod = "skipped"
                    results.mapSkippedBecausePhase = true
                    results.checksComplete = results.checksComplete + 1
                    evaluateResults()
                    return
                else
                    -- Phase check failed or wasn't authoritative about location - Proceed to Map Check
                    runMapCheck()
                end
            else
                evaluateResults()
            end
        end

        -- Standard Phase Check
        if phaseCheckEnabled and results.phaseCheck == nil and not results.phaseCheckStarted then
            -- MUTUAL EXCHANGE OPTIMIZATION: Check if already targeting this player
            local existingCheckIdx = nil
            for i, check in ipairs(self.pendingPhaseChecks or {}) do
                if check.playerName == playerName then
                    existingCheckIdx = i
                    break
                end
            end

            if existingCheckIdx then
                TRP3FW:Debug("Attaching to existing phase check for "..playerName, "location")
                results.phaseCheckStarted = true
                local originalCallback = self.pendingPhaseChecks[existingCheckIdx].callback
                self.pendingPhaseChecks[existingCheckIdx].callback = function(inPhase, source, theirMapID, phaseMethod)
                    if originalCallback then originalCallback(inPhase, source, theirMapID, phaseMethod) end
                    handlePhaseResult(inPhase, source, theirMapID, phaseMethod)
                end
            else
                results.phaseCheckStarted = true
                TRP3FW:Debug("Starting standard phase check...", "location")
                self:CheckPlayerPhase(playerName, sendId, handlePhaseResult, priority)
            end
        elseif results.phaseCheck ~= nil then
            TRP3FW:Debug("Skipping standard phase check (Already set: "..tostring(results.phaseCheck)..")", "location")
            -- If phase check was already done (e.g. SPVP path fallback?), we might need to trigger map check if it wasn't done
            if mapCheckEnabled and results.mapCheck == nil and not results.mapCheckStarted then
                 runMapCheck()
            end
        else
            -- Phase check disabled, go straight to map
            runMapCheck()
        end
    end

    -- Execution Flow based on SPVP Mode
    if spvpEnabled and (spvpMode == "preferred" or spvpMode == "required") then
        -- SEQUENTIAL: SPVP handshake first
        results.checksExpected = 1
        TRP3FW:Debug("Starting sequential SPVP check (Mode: "..spvpMode..")...", "location")
        
        local function onSPVPResult(verified, source)
            results.spvpCheck = verified
            results.spvpSource = source
            results.checksComplete = results.checksComplete + 1
            if source == "cached" then results.cacheInfo.spvpCache = "hit" end

            if verified then
                TRP3FW:Debug("SPVP Verified! Validating map via target...", "location")
                results.phaseCheck = true
                results.phaseSource = "spvp"
                results.phaseMethod = "spvp"
                
                if mapCheckEnabled then
                    -- Try to validate map via targeting (fastest/most reliable for same-map)
                    TRP3FW:CheckPlayerPhase(playerName, sendId, function(inPhase, source, theirMapID, phaseMethod)
                         if inPhase then
                             TRP3FW:Debug("SPVP + Target confirmed same map.", "location")
                             results.mapCheck = true
                             results.mapSource = "target_verification"
                             results.mapMethod = "target"
                             results.theirMapID = theirMapID
                             results.checksComplete = results.checksComplete + 1
                             
                             -- Ensure expected count covers this manual map check
                             if results.checksExpected < results.checksComplete then
                                 results.checksExpected = results.checksComplete
                             end
                             evaluateResults()
                         else
                             TRP3FW:Debug("SPVP valid, but targeting failed. Checking Who/MapScan...", "location")
                             -- Fallback to standard map checks (Who/Scan)
                             startStandardChecks("who_map_verification")
                         end
                     end, "who_map_verification")
                else
                    locationOK = true
                    alertTypes = {}
                    evaluateResults()
                end
            else
                TRP3FW:Debug("SPVP Failed/Timeout ("..tostring(source)..").", "location")
                if spvpMode == "required" then
                    evaluateResults() -- Fail now
                else
                    TRP3FW:Debug("Falling back to standard checks (Preferred Mode).", "location")
                    -- Use HIGH priority for fallback to recover from the timeout delay
                    startStandardChecks("HIGH")
                end
            end
        end

        if existingSessionID then
            TRP3FW:Debug("Attaching to existing SPVP session: "..existingSessionID, "location")
            local session = self.spvpSessions[existingSessionID]
            local originalCallback = session.callback
            session.callback = function(v, s)
                if originalCallback then originalCallback(v, s) end
                onSPVPResult(v, s)
            end
        else
            self:CheckPlayerViaSPVP(playerName, sendId, onSPVPResult)
        end
    else
        -- PARALLEL: Optional/Off or other
        results.checksExpected = (phaseCheckEnabled and 1 or 0) + (mapCheckEnabled and 1 or 0) + (spvpEnabled and 1 or 0)
        
        if spvpEnabled then
            local function onSPVPResult(verified, source)
                results.spvpCheck = verified
                results.spvpSource = source
                results.checksComplete = results.checksComplete + 1
                if source == "cached" then results.cacheInfo.spvpCache = "hit" end
                
                evaluateResults()
            end

            if existingSessionID then
                TRP3FW:Debug("Attaching to existing SPVP session (Parallel): "..existingSessionID, "location")
                local session = self.spvpSessions[existingSessionID]
                local originalCallback = session.callback
                session.callback = function(v, s)
                    if originalCallback then originalCallback(v, s) end
                    onSPVPResult(v, s)
                end
            else
                self:CheckPlayerViaSPVP(playerName, sendId, onSPVPResult)
            end
        end
        startStandardChecks()
    end
end
>>>>>>> Stashed changes
