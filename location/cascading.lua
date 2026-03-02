-- location/cascading.lua
-- Cascading location check logic - coordinates phase, WHO, and map scanning

local addonName, TRP3FW = ...

-- Constants
local START_PHASE_ID = 169  -- Epsilon start phase ID (blocks all transmissions)

-- ===================== Helpers =====================

local function IsMethodStrong(m) 
    return m and (m:find("target") or m:find("batch") or m == "nameplate" or m == "group") 
end

local function IsReliableMapFailure(results, source, spvpVerified)
    if not source then return false end
    
    -- Throttles and backoffs are always unreliable signals of location
    if source:find("backoff") or source:find("rate_limit") then return false end

    -- Nearness signal: proves they are physically nearby (not just same-phase)
    local isNear = IsMethodStrong(results.phaseMethod) or IsMethodStrong(results.mapMethod)

    if results.phaseCheck == true or spvpVerified then
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

local function EvaluateResults(results)
    local playerName = results.playerName
    local spvpEnabled = results.spvpEnabled
    local spvpMode = results.spvpMode or "off"
    local CI = TRP3FW.CacheInterface

    -- OPTIMIZATION: Early Success (Don't wait for slow SPVP if standard checks pass)
    if results.checksComplete < results.checksExpected then
        local canEarlySuccess = (results.phaseCheck == true and results.mapCheck == true)
        local isStrongPhase = IsMethodStrong(results.phaseMethod)
        
        if canEarlySuccess and isStrongPhase and spvpMode ~= "required" then
            TRP3FW:Debug("Early Success triggered for "..playerName..": Phase/Map verified (skipping pending SPVP)", "location")
        else
            return -- Wait for all checks
        end
    end

    TRP3FW:Debug("=== All location checks complete for "..playerName.." ===", "location")
    local locationOK = true
    local alertTypes = {}
    
    local spvpVerified = (results.spvpCheck == true) or (CI and CI:Get("spvpVerified", playerName) ~= nil)

    local checkDetails = {
        phase = { result = results.phaseCheck, source = results.phaseSource, method = results.phaseMethod, theirMapID = results.theirMapID, myMapID = results.myMapID, disabled = results.phaseDisabled },
        map = { result = results.mapCheck, source = results.mapSource, method = results.mapMethod, cacheAge = results.mapCacheAge, theirZone = results.theirZone, myZone = results.myZone, theirMapID = results.theirMapFromWho or results.theirMapID, myMapID = results.myMapID, skippedBecausePhase = results.mapSkippedBecausePhase, disabled = results.mapDisabled },
        spvp = { result = results.spvpCheck, source = results.spvpSource, disabled = results.spvpDisabled }
    }

    -- 1. SPVP Required failure
    if spvpEnabled and spvpMode == "required" and not spvpVerified then
        locationOK = false
        table.insert(alertTypes, results.spvpSource == "timeout" and "spvp_timeout" or "spvp_failed")
    end

    -- 2. Phase Check Evaluation
    if not results.phaseDisabled then
        if results.phaseCheck == false and not spvpVerified then
            if TRP3FW:ShouldAlertOnPhase() or TRP3FW:ShouldBlockOnPhase() then
                locationOK = false
                table.insert(alertTypes, "phase")
            end
        elseif results.phaseCheck == nil and not spvpVerified then
            if TRP3FW:ShouldAlertOnPhase() or TRP3FW:ShouldBlockOnPhase() then
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
    -- If phase verified via strong signal, map check failure is irrelevant noise
    local isPhaseStrong = IsMethodStrong(results.phaseMethod) or (results.phaseMethod == "spvp" and results.mapMethod == "target")
    if (results.phaseCheck == true or spvpVerified) and isPhaseStrong then
        if results.mapCheck == false then
             results.mapCheck = true
             results.mapSource = "ignored_targeting_verified"
             results.mapSkippedBecausePhase = true
             checkDetails.map.result = true
             checkDetails.map.source = "ignored_targeting_verified"
             checkDetails.map.skippedBecausePhase = true
        end
    end

    if not results.mapDisabled then
        if results.mapCheck == false then
            if IsReliableMapFailure(results, results.mapSource, spvpVerified) then
                if TRP3FW:ShouldAlertOnMap() or TRP3FW:ShouldBlockOnMap() then
                    locationOK = false
                    table.insert(alertTypes, "map")
                end
            else
                if TRP3FW:ShouldAlertOnMap() or TRP3FW:ShouldBlockOnMap() then
                    locationOK = false
                    table.insert(alertTypes, "map_unknown")
                end
            end
        elseif results.mapCheck == nil then
            if TRP3FW:ShouldAlertOnMap() or TRP3FW:ShouldBlockOnMap() then
                locationOK = false
                table.insert(alertTypes, "map_unknown")
            end
        end
    end

    -- 4. Overrides
    if results.phaseCheck == true or spvpVerified then
        local reliableMapFailure = not results.mapDisabled and results.mapCheck == false and IsReliableMapFailure(results, results.mapSource, spvpVerified)
        if not reliableMapFailure then
            locationOK = true
            alertTypes = {} -- CLEAR ALERTS on success!
            
            -- FORCE NOTIFICATION TO SHOW SUCCESS
            if spvpVerified and results.phaseCheck ~= true then
                results.phaseCheck = true
                results.phaseSource = results.spvpSource or "spvp"
                results.phaseMethod = "spvp"
                checkDetails.phase.result = true
                checkDetails.phase.source = results.phaseSource
                checkDetails.phase.method = results.phaseMethod
            end
            TRP3FW:Debug("  Final decision for "..playerName..": ALLOW", "location")
        end
    end

    local alertType = #alertTypes > 0 and table.concat(alertTypes, "+") or nil
    TRP3FW.profiler.stop("CheckLocationCascading")
    if results.callback then 
        results.callback(locationOK, alertType, "combined", results.mapCacheAge, results.theirZone, results.myZone, results.cacheInfo, results.recentTransition, results.timeSinceTransition, checkDetails) 
    end
end

local function HandleMapResult(results, found, source, age, method, tMapID, tZone)
    if results.mapCheck ~= nil then return end
    results.mapCheck, results.mapSource, results.mapMethod, results.mapCacheAge = found, source, method or source, age
    results.theirMapID, results.theirZone = tMapID or results.theirMapID, tZone or results.theirZone
    results.checksComplete = results.checksComplete + 1
    EvaluateResults(results)
end

local function RunMapCheck(results, priority)
    if not results.mapCheckEnabled or results.mapCheck ~= nil or results.mapCheckStarted then return end
    results.mapCheckStarted = true
    
    local playerName = results.playerName
    local sendId = results.sendId

    if TRP3FW.Prefs.useWhoQuery and TRP3FW.hasEpsilonAPI then
        TRP3FW:CheckPlayerViaWho(playerName, sendId, function(found, source, age, zone, tMapID)
            if source == "cached" then results.cacheInfo.whoCache = "hit" end
            if (source:find("timeout") or source:find("backoff") or source:find("rate_limit")) and TRP3FW.detectedAddons.MapScanner then
                    TRP3FW:MapScan(playerName, sendId, function(f, s, a) 
                    if s:find("cached") then results.cacheInfo.mapCache = "hit" end
                    HandleMapResult(results, f, s, a) 
                    end)
            else
                local f = found
                if not zone and tMapID and results.myMapID and tMapID ~= results.myMapID then f = false end
                HandleMapResult(results, f, source, age, source, tMapID, zone)
            end
        end, true, false, priority)
    else
        TRP3FW:MapScan(playerName, sendId, function(f, s, a) 
            if s:find("cached") then results.cacheInfo.mapCache = "hit" end
            HandleMapResult(results, f, s, a) 
        end)
    end
end

local function HandlePhaseResult(results, inPhase, source, theirMapID, phaseMethod, priority)
    results.phaseCheck, results.theirMapID, results.phaseSource, results.phaseMethod = inPhase, theirMapID, source, phaseMethod
    results.checksComplete = results.checksComplete + 1
    if source and source:find("cached") then results.cacheInfo.phaseCache = "hit" end
    
    if results.mapCheckEnabled and results.mapCheck == nil and not results.mapCheckStarted and inPhase == true and IsMethodStrong(phaseMethod) then
        results.mapCheck, results.mapSource, results.mapMethod, results.mapSkippedBecausePhase = true, "skipped_phase_verified", "skipped", true
        results.checksComplete = results.checksComplete + 1
        EvaluateResults(results)
    else
        if results.mapCheckEnabled and results.mapCheck == nil and not results.mapCheckStarted then 
            RunMapCheck(results, priority) 
        else 
            EvaluateResults(results) 
        end
    end
end

local function StartStandardChecks(results, priority)
    local phaseCheckEnabled = results.phaseCheckEnabled
    local playerName = results.playerName
    local sendId = results.sendId

    if results.checksExpected == 0 or results.checksExpected == 1 then
        results.checksExpected = results.checksComplete + (phaseCheckEnabled and (results.phaseCheck == nil and 1 or 0) or 0) + (results.mapCheckEnabled and (results.mapCheck == nil and 1 or 0) or 0)
    end

    if phaseCheckEnabled and results.phaseCheck == nil and not results.phaseCheckStarted then
        results.phaseCheckStarted = true
        TRP3FW:CheckPlayerPhase(playerName, sendId, function(inPhase, source, theirMapID, phaseMethod)
            HandlePhaseResult(results, inPhase, source, theirMapID, phaseMethod, priority)
        end, priority)
    elseif results.phaseCheck ~= nil then
        if results.mapCheckEnabled and results.mapCheck == nil and not results.mapCheckStarted then 
            RunMapCheck(results, priority) 
        end
    else
        RunMapCheck(results, priority)
    end
end

local function OnSPVPResult(results, verified, source)
    local playerName = results.playerName
    local sendId = results.sendId
    local mapCheckEnabled = results.mapCheckEnabled
    local spvpMode = results.spvpMode or "off"

    results.spvpCheck, results.spvpSource = verified, source
    results.checksComplete = results.checksComplete + 1
    if source == "cached" then results.cacheInfo.spvpCache = "hit" end

    if verified and (spvpMode == "preferred" or spvpMode == "required") then
        results.phaseCheck, results.phaseSource, results.phaseMethod = true, "spvp", "spvp"
        if mapCheckEnabled then
            TRP3FW:CheckPlayerPhase(playerName, sendId, function(inPhase, s, tMapID, pMethod)
                    if inPhase then
                        results.mapCheck, results.mapSource, results.mapMethod, results.theirMapID = true, "target_verification", "target", tMapID
                        results.checksComplete = results.checksComplete + 1
                        if results.checksExpected < results.checksComplete then results.checksExpected = results.checksComplete end
                        EvaluateResults(results)
                    else
                        StartStandardChecks(results, "who_map_verification")
                    end
                end, "who_map_verification")
        else
            EvaluateResults(results)
        end
    elseif not verified and spvpMode == "preferred" then
        StartStandardChecks(results, "HIGH")
    else
        EvaluateResults(results)
    end
end

-- ===================== Cascading Location Check =====================

function TRP3FW:CheckLocationCascading(playerName, sendId, callback, options)
    options = options or {}
    TRP3FW.profiler.start("CheckLocationCascading")
    
    local now = self:GetCurrentTime()

    -- OPTIMIZATION: Start Phase Early Exit (Fail Fast)
    if TRP3FW.Prefs.blockStartPhase and self:GetCurrentPhaseID() == START_PHASE_ID then
        TRP3FW.profiler.stop("CheckLocationCascading")
        if callback then callback(false, "start_phase_block", "start_phase", 0, nil, nil, {}, false, 0, nil) end
        return
    end

    -- OPTIMIZATION: Interaction Cache Fast-Path (Success Fast)
    local CI = self.CacheInterface
    local interaction = CI and CI:Get("interaction", playerName)
    if interaction and (now - interaction.timestamp) < TRP3FW.Prefs.interactionCacheDuration then
        local inTransitionGracePeriod = (now - (self.lastZoneChangeTime or 0)) < (TRP3FW.Prefs.transitionGracePeriod or 3)
        TRP3FW.profiler.stop("CheckLocationCascading")
        if callback then callback(true, nil, "interaction_cache", now - interaction.timestamp, nil, nil, { interactionCache = "hit" }, inTransitionGracePeriod, 0, nil) end
        return
    end

    local myMapID = C_Map.GetBestMapForUnit("player")
    local myZone = GetRealZoneText()
    local timeSinceTransition = math.min(now - (self.lastZoneChangeTime or 0), now - (self.lastPhaseChangeTime or 0))
    local inTransitionGracePeriod = timeSinceTransition < (TRP3FW.Prefs.transitionGracePeriod or 3)

    local phaseCheckEnabled = self.hasEpsilonAPI and (options.phaseCheckEnabled ~= false and self:IsPhaseCheckEnabled())
    local mapCheckEnabled = options.mapCheckEnabled ~= false and self:IsMapCheckEnabled()
    local spvpEnabled = options.spvpEnabled
    local spvpMode = TRP3FW.Prefs.spvpMode or "off"

    -- Late SPVP Resolution
    if spvpEnabled == nil and TRP3FW.Prefs.spvpEnabled and self.hasEpsilonAPI then
        local currentPhaseID = self:GetCurrentPhaseID()
        if currentPhaseID and currentPhaseID ~= 169 and self:GetPhaseSalt(currentPhaseID) ~= "" then
            spvpEnabled = true
        end
    end

    local results = {
        playerName = playerName, sendId = sendId, callback = callback,
        phaseCheck = nil, mapCheck = nil, spvpCheck = nil,
        mapCacheAge = nil, theirMapID = nil, theirZone = nil, theirMapFromWho = nil,
        mapSource = nil, spvpSource = nil, phaseSource = nil, phaseMethod = nil,
        myMapID = myMapID, myZone = myZone,
        checksComplete = 0, checksExpected = 0,
        recentTransition = inTransitionGracePeriod, timeSinceTransition = timeSinceTransition,
        phaseDisabled = not phaseCheckEnabled, mapDisabled = not mapCheckEnabled, spvpDisabled = not spvpEnabled,
        phaseCheckEnabled = phaseCheckEnabled, mapCheckEnabled = mapCheckEnabled,
        spvpEnabled = spvpEnabled, spvpMode = spvpMode,
        cacheInfo = {}
    }

    -- SPVP Execution
    if results.spvpEnabled and (results.spvpMode == "preferred" or results.spvpMode == "required") then
        results.checksExpected = 1
        self:CheckPlayerViaSPVP(playerName, sendId, function(verified, source)
            OnSPVPResult(results, verified, source)
        end)
    else
        results.checksExpected = (results.phaseCheckEnabled and 1 or 0) + (results.mapCheckEnabled and 1 or 0) + (results.spvpEnabled and 1 or 0)
        if results.spvpEnabled then 
            self:CheckPlayerViaSPVP(playerName, sendId, function(verified, source)
                OnSPVPResult(results, verified, source)
            end)
        end
        StartStandardChecks(results)
    end
end