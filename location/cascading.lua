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