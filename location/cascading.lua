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
        if results.checksComplete < results.checksExpected then
            return -- Wait for all checks
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
                return m and (m:find("target") or m == "nameplate" or m == "batch") 
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

        local function isMethodTargeting(m) 
            return m and (m:find("target") or m == "nameplate" or m == "batch") 
        end
        local isPhaseTargeting = isMethodTargeting(results.phaseMethod) or (results.phaseMethod == "spvp" and results.mapMethod == "target")

        -- Cleanup confusion: If phase verified via targeting, map check failure is irrelevant noise
        if (results.phaseCheck == true or spvpVerified) and isPhaseTargeting then
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
        -- Adjust expected count if we haven't set it yet
        if results.checksExpected == 0 or results.checksExpected == 1 then
            results.checksExpected = results.checksComplete + (phaseCheckEnabled and (results.phaseCheck == nil and 1 or 0) or 0) + (mapCheckEnabled and (results.mapCheck == nil and 1 or 0) or 0)
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
                    results.phaseCheck, results.theirMapID, results.phaseSource, results.phaseMethod = inPhase, theirMapID, source, phaseMethod
                    results.checksComplete = results.checksComplete + 1
                    if source and source:find("cached") then results.cacheInfo.phaseCache = "hit" end
                    evaluateResults()
                end
            else
                results.phaseCheckStarted = true
                TRP3FW:Debug("Starting standard phase check...", "location")
                self:CheckPlayerPhase(playerName, sendId, function(inPhase, source, theirMapID, phaseMethod)
                    results.phaseCheck, results.theirMapID, results.phaseSource, results.phaseMethod = inPhase, theirMapID, source, phaseMethod
                    results.checksComplete = results.checksComplete + 1
                    if source and source:find("cached") then results.cacheInfo.phaseCache = "hit" end
                    evaluateResults()
                end, priority)
            end
        elseif results.phaseCheck ~= nil then
            TRP3FW:Debug("Skipping standard phase check (Already set: "..tostring(results.phaseCheck)..")", "location")
        end

        -- Standard Map Check
        if mapCheckEnabled and results.mapCheck == nil and not results.mapCheckStarted then
            -- OPTIMIZATION: If phase check already passed via targeting/nameplate, skip map check
            if results.phaseCheck == true and (results.phaseMethod == "target" or results.phaseMethod == "nameplate") then
                TRP3FW:Debug("Skipping map check (Phase check passed via "..tostring(results.phaseMethod)..")", "location")
                results.mapCheck = true
                results.mapSource = "skipped_phase_verified"
                results.mapMethod = "skipped"
                results.mapSkippedBecausePhase = true
                results.checksComplete = results.checksComplete + 1
                evaluateResults()
                return -- Skip actual map check
            end

            results.mapCheckStarted = true
            local function handleMap(found, source, age, method, tMapID, tZone)
                results.mapCheck = found
                results.mapSource = source
                results.mapMethod = method or source
                results.mapCacheAge = age
                results.theirMapID = tMapID or results.theirMapID
                results.theirZone = tZone or results.theirZone
                results.checksComplete = results.checksComplete + 1
                evaluateResults()
            end

            -- Fast-path cache
            local CI = TRP3FW.CacheInterface
            if CI then
                local c = CI:Get("mapScan", playerName)
                local b = CI:Get("broadcast", playerName)
                local nowTs = TRP3FW:GetCurrentTime()
                if c and (nowTs - c.timestamp) < (c.found == false and 10 or 120) then
                    results.cacheInfo.mapScanCache = "hit"
                    return handleMap(c.found ~= false, "map_cache", nowTs - c.timestamp, "mapScan", c.mapID)
                end
                if b and (nowTs - b.timestamp) < 120 then
                    results.cacheInfo.broadcastCache = "hit"
                    return handleMap(true, "map_cache_broadcast", nowTs - b.timestamp, "broadcast", b.mapID)
                end
            end

            if useWhoInsteadOfMapScan then
                TRP3FW:Debug("Starting WHO query (preferred over map scan)...", "location")
                self:CheckPlayerViaWho(playerName, sendId, function(found, source, age, zone, tMapID)
                    if source == "cached" then results.cacheInfo.whoCache = "hit" end
                    local f = found
                    if not zone and tMapID and myMapID and tMapID ~= myMapID then f = false end
                    handleMap(f, source, age, source, tMapID, zone)
                end, true, forceWhoNameOnly, priority)
            else
                TRP3FW:Debug("Starting map scan...", "location")
                self:MapScan(playerName, sendId, function(found, source, age)
                    if source:find("cached") then results.cacheInfo.mapCache = "hit" end
                    handleMap(found, source, age)
                end)
            end
        end
    end

    -- Check Interaction Cache First (Instant)
    local CI = self.CacheInterface
    local interaction = CI and CI:Get("interaction", playerName)
    if interaction and (self:GetCurrentTime() - interaction.timestamp) < TRP3FW_Settings.interactionCacheDuration then
        TRP3FW.profiler.stop("CheckLocationCascading")
        if callback then callback(true, nil, "interaction_cache", self:GetCurrentTime() - interaction.timestamp, nil, nil, { interactionCache = "hit" }, inTransitionGracePeriod, timeSinceTransition, nil) end
        return
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
                    startStandardChecks()
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