-- location/phase.lua
-- Epsilon phase checking functionality with batch processing and priority queue

local addonName, TRP3FW = ...

-- ===================== Epsilon Phase Checking =====================
-- Check if player is in the same phase using C_Epsilon.RunPrivileged()

-- Queue state
TRP3FW.pendingPhaseChecks = {}  -- List of {playerName, sendId, callback, priority, queuedAt}
TRP3FW.phaseCheckBatchTimer = nil

-- Priority levels mapping (must match utils.lua)
local PRIORITY_LEVELS = {
    HIGH = 1,
    NORMAL = 2,
    LOW = 3
}

-- Helper to queue a phase check with priority sorting
function TRP3FW:QueuePhaseCheck(playerName, sendId, callback, priority)
    priority = priority or "NORMAL"
    local entry = {
        playerName = playerName,
        sendId = sendId,
        callback = callback,
        priority = priority,
        queuedAt = TRP3FW:GetCurrentTime()
    }

    -- Insert sorted by priority (HIGH first, then NORMAL, then LOW)
    local inserted = false
    for i, queued in ipairs(self.pendingPhaseChecks) do
        local p1 = PRIORITY_LEVELS[priority] or 2
        local p2 = PRIORITY_LEVELS[queued.priority] or 2
        if p1 < p2 then
            table.insert(self.pendingPhaseChecks, i, entry)
            inserted = true
            break
        end
    end

    if not inserted then
        table.insert(self.pendingPhaseChecks, entry)
    end
    
    self:Debug("[Phase Queue] Enqueued "..playerName.." (priority: "..priority..", queue size: "..#self.pendingPhaseChecks..")", "phase")

    -- Check if we have enough items to justify an immediate full-capacity batch
    -- "If we get up to the point where we would consume all of the available tokens, we should immediately fire off the batch"
    local available = TRP3FW:GetAvailablePrivilegedTokens()
    
    -- Calculate capacity for immediate firing (aggressive) - matching ProcessPhaseCheckBatch formula
    local reserved = TRP3FW.Prefs.privilegedReservedTokens or 2
    local overhead = math.max(1, reserved)
    
    local immediateCap = math.floor(available) - overhead
    if immediateCap < 1 then immediateCap = 1 end

    -- Only fire immediately if we are filling the current capacity
    -- This prevents firing small batches constantly when tokens are low (refill wait)
    -- Rule: If timer is running, only interrupt if we have healthy capacity (>= 5 items)
    local healthyCapacity = (immediateCap >= 5)
    local shouldFire = false
    
    if #self.pendingPhaseChecks >= immediateCap and TRP3FW.Prefs.phaseCheckBatchMode then
        if self.phaseCheckBatchTimer then
            if healthyCapacity then
                shouldFire = true
            else
                -- Debug spam reduction: only log occasionally or if verbose?
                -- self:Debug("[Phase Queue] Deferring immediate fire (Low capacity: "..immediateCap..", Timer running)", "phase")
            end
        else
            shouldFire = true
        end
    end

    if shouldFire then
        self:Debug("[Phase Queue] Immediate fire triggered (Queue: "..#self.pendingPhaseChecks..", Cap: "..immediateCap..")", "phase")
        if self.phaseCheckBatchTimer then 
            self.phaseCheckBatchTimer:Cancel() 
            self.phaseCheckBatchTimer = nil
        end
        self:ProcessPhaseCheckBatch()
    end
end

function TRP3FW:SchedulePhaseCheckProcessing(customDelay)
    if self.phaseCheckBatchTimer or self.targetingInProgress then return end

    -- Use custom delay if provided (e.g. for refill waiting), otherwise default to setting
    local delay = customDelay or TRP3FW.Prefs.phaseCheckBatchDelay or 1.0
    
    self.phaseCheckBatchTimer = C_Timer.After(delay, function()
        self.phaseCheckBatchTimer = nil
        
        local queueSize = #self.pendingPhaseChecks
        local minSize = TRP3FW.Prefs.phaseCheckBatchMinSize or 3
        
        if queueSize >= minSize and TRP3FW.Prefs.phaseCheckBatchMode then
            self:ProcessPhaseCheckBatch()
        else
            self:ProcessPhaseCheckQueue()
        end
    end)
end

-- OPTIMIZATION #2: Batch Phase Check Processing
-- Processes a batch of phase checks with a single target restoration
function TRP3FW:ProcessPhaseCheckBatch()
    if not TRP3FW.Prefs.phaseCheckBatchMode then
        -- Batch mode disabled, process individually
        self:ProcessPhaseCheckQueue()
        return
    end

    -- Pull a batch from the queue (with deduplication)
    local batch = {}
    local batchIndices = {} -- Map playerName -> batch index
    
    -- DYNAMIC BATCH SIZING: Calculate max batch size based on available tokens
    -- "batch until we would run out of secure tokens"
    local availableTokens = TRP3FW:GetAvailablePrivilegedTokens()
    
    -- Calculate overhead based on reserved tokens setting
    -- Formula: available - max(1, reserved)
    -- We need at least 1 token for the restore action (HIGH priority), 
    -- and we must respect the reserved amount for NORMAL priority targeting calls.
    local reserved = TRP3FW.Prefs.privilegedReservedTokens or 2
    local overhead = math.max(1, reserved)
    
    local dynamicMax = math.floor(availableTokens) - overhead
    if dynamicMax < 1 then dynamicMax = 1 end -- Always try at least one if we're running
    
    local settingsMax = TRP3FW.Prefs.phaseCheckBatchSize or 5
    
    -- If we have plenty of tokens (full bucket), allow larger batches than default settings
    -- to clear the queue faster ("3 second window" accumulation implies larger bursts)
    -- BUT never exceed dynamicMax (token limit)
    if availableTokens >= 9 then
        settingsMax = math.max(settingsMax, 8)
    end
    
    local maxSize = math.min(settingsMax, dynamicMax)

    local count = 0
    local totalProcessed = 0
    
    while #self.pendingPhaseChecks > 0 and count < maxSize do
        totalProcessed = totalProcessed + 1
        local check = self.pendingPhaseChecks[1] -- Peek head
        
        if batchIndices[check.playerName] then
            -- Already have this player in THIS batch - merge callback and drop duplicate
            local idx = batchIndices[check.playerName]
            local existing = batch[idx]
            
            if check.callback then
                if not existing.callbacks then
                    existing.callbacks = { existing.callback }
                    existing.callback = nil
                end
                table.insert(existing.callbacks, check.callback)
            end
            
            TRP3FW:Debug("[Batch] Merged duplicate queue entry for "..check.playerName, "phase")
            table.remove(self.pendingPhaseChecks, 1)
        else
            -- New player for this batch
            local entry = table.remove(self.pendingPhaseChecks, 1)
            entry.callbacks = { entry.callback } -- Start list
            entry.callback = nil
            
            table.insert(batch, entry)
            count = count + 1
            batchIndices[entry.playerName] = count
        end
    end

    if #batch == 0 then return end

    local uniqueCount = #batch
    TRP3FW:Debug("[Batch] Starting - "..uniqueCount.." unique players (from "..totalProcessed.." requests)", "phase")

    -- Track batch statistics
    local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
    if hs then
        hs:IncrementStat("privilegedStats", "phaseCheckBatches")
        -- Tokens saved:
        -- Individual: 2 tokens per request (Target + Restore)
        -- Batch: 1 token per UNIQUE player + 1 token (Restore)
        -- Savings = (Requests * 2) - (Unique * 1 + 1)
        local tokensSaved = (totalProcessed * 2) - (#batch + 1)
        if tokensSaved > 0 then
            hs:IncrementStat("privilegedStats", "phaseCheckTokensSaved", tokensSaved)
        end
    end

    -- FIXED: HIGH-2 - Acquire mutex lock
    self.targetingInProgress = true
    self.phaseCheckTargeting = true
    
    -- Save current target state ONCE for the whole batch
    local hadTarget = UnitExists("target")
    local previousTargetGUID = hadTarget and UnitGUID("target") or nil
    local previousTargetName = hadTarget and GetUnitName("target", true) or nil -- Capture name with realm
    
    local currentIndex = 1
    local batchFrame = CreateFrame("Frame")
    local batchTimer = nil

    local function cleanupBatch()
        if batchTimer then batchTimer:Cancel() batchTimer = nil end
        if batchFrame then 
            batchFrame:UnregisterAllEvents() 
            batchFrame:SetScript("OnEvent", nil)
            batchFrame = nil 
        end
        
        -- Delay clearing the flag to ensure CacheService sees it during event propagation
        C_Timer.After(0.1, function() 
            TRP3FW.targetingInProgress = false 
            TRP3FW.phaseCheckTargeting = false

            -- Check if more items pending
            if #self.pendingPhaseChecks > 0 then
                -- "wait the appropriate amount of time before the next batch fires off to refill the bucket"
                -- Calculate delay based on token refill needs
                -- We want a reasonably full bucket for the next batch
                local currentTokens = TRP3FW:GetAvailablePrivilegedTokens()
                local targetTokens = 8 -- Aim for a healthy batch size
                local refillRate = 10 -- Tokens per second
                
                local delay = 0.1 -- Min delay
                if currentTokens < targetTokens then
                    delay = (targetTokens - currentTokens) / refillRate
                    if delay < 0.1 then delay = 0.1 end
                end
                
                TRP3FW:Debug("[Batch] Scheduling next batch in "..string.format("%.2fs", delay).." (Refill wait)", "phase")
                TRP3FW:SchedulePhaseCheckProcessing(delay)
            end
        end)
    end

    local function processNext()
        -- Clean up previous step's timer/event
        if batchTimer then batchTimer:Cancel() batchTimer = nil end
        batchFrame:UnregisterAllEvents()
        batchFrame:SetScript("OnEvent", nil)

        if currentIndex > #batch then
            -- Batch complete, restore target
            local success, err
            pcall(function()
                if hadTarget then
                    if UnitGUID("target") ~= previousTargetGUID then
                         -- TargetLastTarget unreliable for batches > 1, use explicit name
                         if previousTargetName then
                             local escapedName = previousTargetName:gsub('"', '\\"') -- Escape quotes
                             local restoreCmd = 'TargetUnit("' .. escapedName .. '")'
                             success, err = TRP3FW:RunPrivilegedSafe(restoreCmd, "phase_restore_target_by_name")
                             if not success then
                                  TRP3FW:Debug("[Batch] Target restore failed (by name): "..tostring(err), "phase")
                             end
                         else
                             -- Fallback (unlikely)
                             success, err = TRP3FW:RunPrivilegedSafe("TargetLastTarget()", "phase_restore_target")
                         end
                    else
                        TRP3FW:Debug("[Batch] Target didn't change from start, skipping restore", "phase")
                    end
                else
                    if UnitExists("target") then
                        success, err = TRP3FW:RunPrivilegedSafe("ClearTarget()", "phase_clear_target")
                    end
                end
            end)
            
            TRP3FW:Debug("[Batch] Complete - processed "..#batch.." players", "phase")
            cleanupBatch()
            return
        end

        local check = batch[currentIndex]
        
        local CI = TRP3FW.CacheInterface
        local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService") -- Get HS once
        
        -- OPTIMIZATION 1: Check interaction cache (Strongest "In Phase" signal)
        local interactionCached = CI and CI:Get("interaction", check.playerName)
        if interactionCached then
             local now = TRP3FW:GetCurrentTime()
             local ttl = TRP3FW.Prefs.interactionCacheDuration or 600
             if (now - interactionCached.timestamp) < ttl then
                 TRP3FW:Debug("[Batch] "..check.playerName.." - Interaction Cache HIT (skipping target)", "phase")
                 
                 if check.callbacks then
                     for _, cb in ipairs(check.callbacks) do
                         if cb then cb(true, "interaction_cache", nil, "batch") end
                     end
                 end
                 
                 currentIndex = currentIndex + 1
                 processNext()
                 return
             end
        end
        if hs then hs:IncrementStat("cacheStats", "interactionCacheMisses") end -- ADDED MISS

        -- OPTIMIZATION 2: Check allowed senders cache (Late Cache Hit)
        local allowedCached = CI and CI:Get("allowedSenders", check.playerName)
        if allowedCached then
            local now = TRP3FW:GetCurrentTime()
            local ttl = TRP3FW.Prefs.sendCacheDuration or 600
            if (now - allowedCached.timestamp) < ttl then
                 local r = allowedCached.reason
                 -- Only trust strong signals that imply phase presence
                 if r and (r == "phase_cache" or r == "phase_check_match" or r == "interaction" or r == "manual") then
                     TRP3FW:Debug("[Batch] "..check.playerName.." - Allowed Cache HIT ("..tostring(r)..")", "phase")
                     if check.callbacks then
                         for _, cb in ipairs(check.callbacks) do
                             if cb then cb(true, "allowed_cache", nil, "batch") end
                         end
                     end
                     currentIndex = currentIndex + 1
                     processNext()
                     return
                 end
            end
        end
        if hs then hs:IncrementStat("cacheStats", "allowedSendersCacheMisses") end -- ADDED MISS

                -- OPTIMIZATION 3: Check phase cache again (Late Cache Hit)

                local cached = CI and CI:Get("phaseCheck", check.playerName)

                if cached then

                     local now = TRP3FW:GetCurrentTime()

                     local ttl = TRP3FW.Prefs.phaseCacheDuration or 300

                     if cached.inPhase == false then ttl = TRP3FW.Prefs.phaseCacheFailureDuration or 10 end

                     

                     -- If this is a REFRESH (Low Prio), only skip if someone else refreshed it (Fresh)

                     -- If this is a CHECK (Normal Prio), skip if Valid (Stale or Fresh)

                     local isRefresh = (check.priority == "LOW")

                     local refreshThreshold = ttl * (TRP3FW.Prefs.phaseCacheRefreshThreshold or 0.2)

                     local isFresh = (now - cached.timestamp) < refreshThreshold

                     local isValid = (now - cached.timestamp) < ttl

                     

                                  if (isRefresh and isFresh) or (not isRefresh and isValid) then

                     

                                      TRP3FW:Debug("[Batch] "..check.playerName.." - Phase Cache HIT (skipping target)", "phase")

                     

                                      if hs then hs:IncrementStat("cacheStats", "phaseCacheHits") end

                     

                                      

                     

                                      if check.callbacks then

                             for _, cb in ipairs(check.callbacks) do

                                 if cb then cb(cached.inPhase, "cached_late", cached.mapID, "batch") end

                             end

                         end

                         

                         currentIndex = currentIndex + 1

                         processNext()

                         return

                     end

                end
        if hs then hs:IncrementStat("cacheStats", "phaseCacheMisses") end -- ADDED MISS

        local beforeGUID = UnitGUID("target")
        local processedThisStep = false -- Guard against double-processing (event + timer race)
        
        -- Determine category based on priority
        local category = "phase_check_target"
        if check.priority == "LOW" then
            category = "phase_check_target_low"
        end

        -- SECURITY: Sanitize name
        local sanitizedName = TRP3FW:SanitizePlayerName(check.playerName)
        if not sanitizedName then
            if check.callbacks then
                for _, cb in ipairs(check.callbacks) do
                    if cb then cb(nil, "invalid_name") end
                end
            end
            currentIndex = currentIndex + 1
            processNext()
            return
        end

        -- Handler for result processing
        local function finishStep(result, reason, mapID)
            if processedThisStep then return end
            processedThisStep = true
            
            if batchTimer then batchTimer:Cancel() batchTimer = nil end
            batchFrame:UnregisterAllEvents()
            
            -- Cache result
            local CI = TRP3FW.CacheInterface
            if CI then
                local now = TRP3FW:GetCurrentTime()
                CI:Set("phaseCheck", check.playerName, {
                    inPhase = result,
                    mapID = mapID,
                    timestamp = now,
                    method = reason
                })

                -- NEW LOGIC: Cross-populate WHO cache on successful target
                -- If we targeted them, they are in the same instance/zone
                if result and reason == "batch_targeting" then
                    local currentZone = TRP3FW.currentZoneName or GetRealZoneText()
                    CI:Set("whoName", check.playerName, {
                        found = true,
                        zone = currentZone,
                        timestamp = now,
                        mapID = mapID
                    })
                    TRP3FW:Debug("[Batch] Cross-populated WHO cache for "..check.playerName, "phase")
                end
            end

            -- Callback
            if check.callbacks then
                 for _, cb in ipairs(check.callbacks) do
                     if cb then cb(result, reason, mapID, "batch") end
                 end
            end

            currentIndex = currentIndex + 1
            processNext()
        end

        -- Event listener for immediate success
        batchFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        batchFrame:SetScript("OnEvent", function()
            local newName = UnitName("target")
            if newName == check.playerName then
                local targetMap = C_Map.GetBestMapForUnit("target")
                TRP3FW:Debug(function()
                    return "[Batch] "..check.playerName.." - IN PHASE (Event driven)"
                end, "phase")
                finishStep(true, "batch_targeting", targetMap)
            end
        end)

        local success, err, waitTime = TRP3FW:RunPrivilegedSafe('TargetUnit("'..sanitizedName..'")', category)

        if success then
            -- Set timeout timer
            local interDelay = TRP3FW.Prefs.phaseCheckInterTargetDelay or 0.1
            batchTimer = C_Timer.NewTimer(interDelay, function()
                if processedThisStep then return end
                
                local afterGUID = UnitGUID("target")
                local result = false
                local reason = "batch_not_targetable"
                local mapID = nil
                
                if beforeGUID == afterGUID then
                    -- Target didn't change - out of phase
                    TRP3FW:Debug(function()
                        return "[Batch] "..check.playerName.." - NOT IN PHASE (GUID unchanged)"
                    end, "phase")
                else
                    -- Target changed - verify name matches (sanity check)
                    local newName = UnitName("target")
                    if newName == check.playerName then
                        local targetMap = C_Map.GetBestMapForUnit("target")
                        TRP3FW:Debug(function()
                            return "[Batch] "..check.playerName.." - IN PHASE (Timer check)"
                        end, "phase")
                        result = true
                        reason = "batch_targeting"
                        mapID = targetMap
                    else
                        TRP3FW:Debug(function()
                            return "[Batch] "..check.playerName.." - NAME MISMATCH (got "..tostring(newName)..")"
                        end, "phase")
                        reason = "batch_name_mismatch"
                    end
                end
                
                finishStep(result, reason, mapID)
            end)
        else
            -- RunPrivileged failed
            if err == "deferred_low_priority" then
                TRP3FW:Debug("[Batch] "..check.playerName.." deferred (LOW priority), requeuing...", "phase")
                TRP3FW:QueuePhaseCheck(check.playerName, check.sendId, check.callbacks and check.callbacks[1] or check.callback, check.priority)
            else
                TRP3FW:Debug("[Batch] "..check.playerName.." - FAILED ("..tostring(err)..")", "phase")
                if check.callbacks then
                    for _, cb in ipairs(check.callbacks) do
                        if cb then cb(nil, "error", nil, "batch") end
                    end
                end
            end
            currentIndex = currentIndex + 1
            processNext()
        end
    end

    processNext()
end

-- Process queue individually (Legacy/Fallback mode)
function TRP3FW:ProcessPhaseCheckQueue()
    if #self.pendingPhaseChecks == 0 then return end
    
    local check = table.remove(self.pendingPhaseChecks, 1)
    
    -- Determine category
    local category = "phase_check_target"
    if check.priority == "LOW" then
        category = "phase_check_target_low"
    end
    
    -- Check capacity (Optimization #9) - if low priority and scarce, defer
    if check.priority == "LOW" and TRP3FW.GetCategoryPriority then
        local _, config = TRP3FW:GetCategoryPriority(category)
        if config and config.deferOnScarcity then
            -- Check available tokens manually or rely on RunPrivilegedSafe return
            -- We'll rely on ExecutePhaseCheck handling the deferral
        end
    end
    
    self:ExecutePhaseCheck(check)
end

-- Execute a single phase check (from queue or direct)
function TRP3FW:ExecutePhaseCheck(check)
    local playerName = check.playerName
    local callback = check.callback
    local priority = check.priority
    
    -- Sanitize
    local sanitizedName = self:SanitizePlayerName(playerName)
    if not sanitizedName then
        if callback then callback(nil, "invalid_name") end
        -- Process next
        if #self.pendingPhaseChecks > 0 then
            C_Timer.After(0.1, function() self:ProcessPhaseCheckQueue() end)
        end
        return
    end

    self.targetingInProgress = true
    self.phaseCheckTargeting = true
    self:Debug("[Phase Check] Acquired mutex for "..playerName, "phase")

    -- Save current target state
    local hadTarget = UnitExists("target")
    local previousTargetGUID = hadTarget and UnitGUID("target") or nil
    local previousTargetName = hadTarget and GetUnitName("target", true) or nil -- Capture name with realm
    
    -- Create event listener
    local targetCheckFrame = CreateFrame("Frame")
    local timeoutTimer = nil
    local eventHandled = false

    local function cleanup()
        if targetCheckFrame then
            targetCheckFrame:UnregisterAllEvents()
            targetCheckFrame:SetScript("OnEvent", nil)
            targetCheckFrame = nil
        end
        if timeoutTimer then
            timeoutTimer:Cancel()
            timeoutTimer = nil
        end
        
        -- Delay clearing the flag to ensure CacheService sees it during event propagation
        C_Timer.After(0.1, function() 
            self.targetingInProgress = false
            self.phaseCheckTargeting = false
            self:Debug("[Phase Check] Released mutex", "phase")

            -- Process next
            if #self.pendingPhaseChecks > 0 then
                -- Check if we should switch to batch mode based on queue size
                local minSize = TRP3FW.Prefs.phaseCheckBatchMinSize or 3
                if TRP3FW.Prefs.phaseCheckBatchMode and #self.pendingPhaseChecks >= minSize then
                     -- Trigger batch accumulation/processing
                     if not self.phaseCheckBatchTimer then
                         self:ProcessPhaseCheckBatch()
                     end
                else
                    -- Not enough for batch, continue individually
                    self:ProcessPhaseCheckQueue()
                end
            end
        end)
    end

    local function handleResult(success, mapID, reason)
        if eventHandled then return end
        eventHandled = true

        self:Debug("Phase check result for "..playerName..": "..(success and "IN PHASE" or "NOT IN PHASE"), "phase")

        -- Cache result
        local CI = self.CacheInterface
        if CI then
            local now = self:GetCurrentTime()
            CI:Set("phaseCheck", playerName, {
                inPhase = success,
                mapID = mapID,
                timestamp = now,
                method = reason
            })

            -- NEW LOGIC: Cross-populate WHO cache on successful target
            -- If we targeted them, they are in the same instance/zone
            if success and (reason == "targeting" or reason == "targeting_fallback") then
                local currentZone = self.currentZoneName or GetRealZoneText()
                CI:Set("whoName", playerName, {
                    found = true,
                    zone = currentZone,
                    timestamp = now,
                    mapID = mapID
                })
                self:Debug("[Phase Check] Cross-populated WHO cache for "..playerName, "phase")
            end
        end

        -- Check if target actually changed (Optimization #5)
        local currentGUID = UnitGUID("target")
        local targetActuallyChanged = (currentGUID ~= previousTargetGUID)

        -- Restore target
        pcall(function()
            if targetActuallyChanged then
                local restoreSuccess, err
                if hadTarget then
                    if previousTargetName then
                         local escapedName = previousTargetName:gsub('"', '\\"')
                         local restoreCmd = 'TargetUnit("' .. escapedName .. '")'
                         restoreSuccess, err = self:RunPrivilegedSafe(restoreCmd, "phase_restore_target_by_name")
                    else
                         restoreSuccess, err = self:RunPrivilegedSafe("TargetLastTarget()", "phase_restore_target")
                    end
                else
                    restoreSuccess, err = self:RunPrivilegedSafe("ClearTarget()", "phase_clear_target")
                end
            else
                -- OPTIMIZATION #5: Refund token if target didn't change
                if TRP3FW.Prefs.phaseCheckRefundOnNoChange then
                    self:Debug("[Phase Check] Target didn't change, refunding token", "phase")
                    self:RefundToken("phase_restore_skipped", 1)
                else
                    self:Debug("[Phase Check] Target didn't change, skipping restore", "phase")
                end
            end
        end)

        cleanup()
        if callback then callback(success, "checked", mapID, reason) end
    end

    targetCheckFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    targetCheckFrame:SetScript("OnEvent", function()
        local newName = UnitName("target")
        if newName == playerName then
            handleResult(true, C_Map.GetBestMapForUnit("target"), "targeting")
        end
    end)

    timeoutTimer = C_Timer.NewTimer(2.0, function()
        -- Fallback: If event didn't fire (e.g. target didn't change), verify manually
        if UnitName("target") == playerName then
            handleResult(true, C_Map.GetBestMapForUnit("target"), "targeting_fallback")
        else
            handleResult(false, nil, "timeout")
        end
    end)

    local category = (priority == "LOW") and "phase_check_target_low" or "phase_check_target"
    local success, err, waitTime = self:RunPrivilegedSafe('TargetUnit("'..sanitizedName..'")', category)

    if not success then
        if err == "deferred_low_priority" then
            -- Defer execution
            cleanup() -- Release mutex
            self:Debug("[Phase Check] Deferred "..playerName.." for "..tostring(waitTime).."s", "phase")
            C_Timer.After(waitTime, function()
                self:QueuePhaseCheck(playerName, check.sendId, callback, priority)
                if not self.phaseCheckBatchTimer then
                     self.phaseCheckBatchTimer = C_Timer.After(0.1, function() self:ProcessPhaseCheckBatch() end)
                end
            end)
        else
            cleanup()
            if callback then callback(nil, "error") end
        end
    end
end

-- Main entry point
function TRP3FW:CheckPlayerPhase(playerName, sendId, callback, priority)
    self:Debug("CheckPlayerPhase called for: "..tostring(playerName), "phase")

    if not self.hasEpsilonAPI or not self:IsPhaseCheckEnabled() then
        if callback then callback(nil, "unavailable") end
        return
    end

    -- SECURITY/DEDUPE: Sanitize name immediately to ensure consistent cache keys and deduplication
    local sanitizedName = self:SanitizePlayerName(playerName)
    if not sanitizedName then
        if callback then callback(nil, "invalid_name") end
        return
    end

    -- Group Check (Optional Bypass)
    if TRP3FW.Prefs.allowGroupPhaseBypass then
        if UnitInParty(sanitizedName) or UnitInRaid(sanitizedName) then
            self:Debug("Phase check passed (Group Bypass) for "..sanitizedName, "phase")
            if callback then callback(true, "group", nil, "group") end
            return
        end
    end

    -- Check Cache (Optimization #1)
    local CI = self.CacheInterface
    local cached = CI and CI:Get("phaseCheck", sanitizedName)
    
    local hs = self.ServiceContainer and self.ServiceContainer:Get("HistoryService")

    if cached then
        local now = self:GetCurrentTime()
        local age = now - cached.timestamp
        local ttl = TRP3FW.Prefs.phaseCacheDuration or 300
        local refreshThreshold = ttl * (TRP3FW.Prefs.phaseCacheRefreshThreshold or 0.2)
        
        -- Short failure TTL
        if cached.inPhase == false then
            ttl = TRP3FW.Prefs.phaseCacheFailureDuration or 10
        end

        if age < refreshThreshold then
            -- Fresh cache, return immediately
            self:Debug("Phase cache HIT (fresh) for "..sanitizedName, "phase")
            if hs then hs:IncrementStat("cacheStats", "phaseCacheHits") end
            if callback then callback(cached.inPhase, "cached", cached.mapID, cached.method) end
            return
        elseif age < ttl then
            -- Stale but valid - return result but queue refresh (LOW priority)
            self:Debug("Phase cache HIT (stale) for "..sanitizedName.." - scheduling refresh", "phase")
            if hs then hs:IncrementStat("cacheStats", "phaseCacheHits") end
            if callback then callback(cached.inPhase, "cached", cached.mapID, cached.method) end
            
            -- Queue low priority refresh
            self:QueuePhaseCheck(sanitizedName, sendId, nil, "LOW") -- No callback for refresh
            
            -- Trigger processing
            self:SchedulePhaseCheckProcessing()
            return
        end
        -- Else: Expired cache, fall through to queue
    end

    -- If we reach here, it was an initial phaseCache miss (or expired cache)
    if hs then hs:IncrementStat("cacheStats", "phaseCacheMisses") end

    -- Queue the request
    self:QueuePhaseCheck(sanitizedName, sendId, callback, priority or "NORMAL")

    -- Start batch timer if not running
    self:SchedulePhaseCheckProcessing()
end
