-- location/phase.lua
-- Epsilon phase checking functionality with batch processing and priority queue

local addonName, TRP3FW = ...

-- ===================== Epsilon Phase Checking =====================
-- Check if player is in the same phase using C_Epsilon.RunPrivileged()

-- Queue state
TRP3FW.pendingPhaseChecks = {}  -- List of {playerName, sendId, callback, priority, queuedAt}
TRP3FW.phaseCheckBatchTimer = nil
TRP3FW.inspectRetryTimer = nil  -- Single shared 1s pump for inspect-open deferrals

-- Cross-request coordination for concurrent phase checks of the SAME player. Two
-- independent callers (e.g. an MSP send and a TRP3 map-scan reply both racing to
-- verify the same target within the same second) each used to get their own queue
-- entry and their own serialized TargetUnit() call - the second one could sit behind
-- the first's full targeting timeout, long enough that ITS OWN caller's correctness
-- deadline (see cascading.lua ArmDeadline) expired first, producing a phantom timeout
-- for a player who was definitely reachable (the first check proved it a moment later).
-- This registry lets a second caller for the same player attach to the first's
-- in-flight/queued check instead of starting a fully separate, serialized one: keyed by
-- sanitized playerName, each entry is { callbacks = {fn...}, onTargetingStartedList =
-- {fn...}, targetingStarted = bool }. Populated in QueuePhaseCheck for fresh (non-requeue)
-- calls, drained by whichever of ExecutePhaseCheck/ProcessPhaseCheckBatch resolves first.
TRP3FW.pendingPhaseCheckWaiters = {}

-- Priority levels mapping (must match utils.lua)
local PRIORITY_LEVELS = {
    HIGH = 1,
    NORMAL = 2,
    LOW = 3
}

-- Set the automated-targeting flag and keep the target-select sound mute in sync.
-- Muting is scoped to these windows so manual target selection keeps its sound.
function TRP3FW:SetPhaseCheckTargeting(active)
    self.phaseCheckTargeting = active
    if self.SetTargetSoundMuted then
        self:SetTargetSoundMuted(active and (self.Prefs and self.Prefs.muteTargetSound) or false)
    end
end

-- Helper to queue a phase check with priority sorting.
-- isRequeue: true when this call is the check's OWN retry (deferred_low_priority,
-- inspect-defer, batch-merge requeue) continuing its existing waiters entry - NOT a new
-- external caller. Only non-requeue calls create/merge into pendingPhaseCheckWaiters;
-- requeues skip that entirely since the entry (and its waiters) already exists.
function TRP3FW:QueuePhaseCheck(playerName, sendId, callback, priority, inspectDeadline, onTargetingStarted, isRequeue)
    priority = priority or "NORMAL"

    if not isRequeue and callback then
        local waiters = self.pendingPhaseCheckWaiters[playerName]
        if waiters then
            -- Someone is already checking this player (queued or in-flight): attach this
            -- caller to that check instead of starting a second, fully serialized one.
            table.insert(waiters.callbacks, callback)
            if onTargetingStarted then
                if waiters.targetingStarted then
                    -- Targeting already began for the first caller; this caller's own
                    -- correctness deadline still needs extending, so fire immediately
                    -- rather than waiting for a signal that already happened.
                    onTargetingStarted()
                else
                    table.insert(waiters.onTargetingStartedList, onTargetingStarted)
                end
            end
            self:Debug("[Phase Queue] "..playerName.." already has a pending check - attached, not re-queued", "phase")
            return
        end

        self.pendingPhaseCheckWaiters[playerName] = {
            callbacks = { callback },
            onTargetingStartedList = onTargetingStarted and { onTargetingStarted } or {},
            targetingStarted = false,
        }
    end

    local entry = {
        playerName = playerName,
        sendId = sendId,
        callback = callback,
        priority = priority,
        queuedAt = TRP3FW:GetCurrentTime(),
        -- Absolute deadline (GetCurrentTime seconds) for inspect-open deferral; set on
        -- the first inspect defer and carried across retries so the 10s window is stable.
        inspectDeadline = inspectDeadline,
        -- Fired once TargetUnit() is actually issued for this entry (queueing/mutex/token
        -- wait is over). Callers use this to extend correctness deadlines that would
        -- otherwise race against unbounded queue wait rather than just the targeting timeout.
        onTargetingStarted = onTargetingStarted,
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

    if priority == "HIGH" then
        shouldFire = true
    elseif #self.pendingPhaseChecks >= immediateCap and TRP3FW.Prefs.phaseCheckBatchMode then
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

    -- Suppress immediate firing while the inspect pump is mid-sweep: it re-queues checks
    -- and would otherwise reenter processing (ProcessPhaseCheckBatch -> ...Queue) and
    -- double-process an entry the sweep is about to handle. The pump re-arms itself.
    if shouldFire and not self.inspectPumping then
        self:Debug("[Phase Queue] Immediate fire triggered (Queue: "..#self.pendingPhaseChecks..", Cap: "..immediateCap..")", "phase")
        if self.phaseCheckBatchTimer then
            self.phaseCheckBatchTimer:Cancel()
            self.phaseCheckBatchTimer = nil
        end
        self:ProcessPhaseCheckBatch()
    end
end

-- Fire every onTargetingStarted attached to this player's waiters group (the check's
-- own + any concurrent callers that attached while it was queued) and mark the group so
-- a caller attaching AFTER this point fires immediately instead of waiting. Safe to call
-- even if no waiters entry exists (e.g. the LOW-priority background-refresh queue path,
-- which never creates one since it passes no callback).
function TRP3FW:FirePhaseCheckTargetingStarted(playerName)
    local waiters = self.pendingPhaseCheckWaiters[playerName]
    if not waiters or waiters.targetingStarted then return end
    waiters.targetingStarted = true
    for _, fn in ipairs(waiters.onTargetingStartedList) do fn() end
end

-- Deliver a phase check result to every caller attached to this player's waiters group
-- (not just the original check's own callback), then clear the group. Call exactly once
-- per resolved player per check attempt - the same single-flight point that already
-- exists in ExecutePhaseCheck (handleResult) and ProcessPhaseCheckBatch (finishStep).
-- Signature matches the standard callback order used everywhere else in this file:
-- (inPhase, source, theirMapID, phaseMethod).
function TRP3FW:ResolvePhaseCheckWaiters(playerName, inPhase, source, mapID, method)
    local waiters = self.pendingPhaseCheckWaiters[playerName]
    self.pendingPhaseCheckWaiters[playerName] = nil
    if not waiters then return end
    for _, cb in ipairs(waiters.callbacks) do
        if cb then cb(inPhase, source, mapID, method) end
    end
end

function TRP3FW:SchedulePhaseCheckProcessing(customDelay)
    if self.phaseCheckBatchTimer or self.targetingInProgress then return end

    -- Use custom delay if provided (e.g. for refill waiting), otherwise default to setting
    local delay = customDelay or TRP3FW.Prefs.phaseCheckBatchDelay or 1.0

    -- Must be C_Timer.NewTimer (cancelable object), not C_Timer.After (returns nil).
    -- Other code stores this field expecting to :Cancel() it (QueuePhaseCheck) and to
    -- detect a pending batch via the guard above; an `After` handle would be nil, breaking
    -- both and allowing overlapping batch timers to stack.
    self.phaseCheckBatchTimer = C_Timer.NewTimer(delay, function()
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

    -- MUTEX: If a batch or individual check is already running, don't start a new one.
    -- The new request is already in the queue and will be picked up when the current one finishes.
    if self.targetingInProgress then
        TRP3FW:Debug("[Batch] Deferring batch start - targeting already in progress", "phase")
        return
    end

    -- While the armory/inspect window is open, don't batch (retargeting would corrupt
    -- inspect data). Route through the individual path, which owns the per-check 10s
    -- deadline, retry, and forced resolution (inspectTimeoutResolution).
    if TRP3FW.Prefs.pausePhaseCheckOnInspect and self:IsInspectActive() then
        TRP3FW:Debug("[Batch] Inspect window open, routing to individual queue", "phase")
        self:ProcessPhaseCheckQueue()
        return
    end

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

            -- Merge onTargetingStarted the same way as callbacks: a dropped duplicate's
            -- caller (e.g. a second concurrent CheckLocationCascading for this player)
            -- still needs its own deadline extended once targeting actually starts, or it
            -- reopens the phantom-timeout bug for just that caller.
            if check.onTargetingStarted then
                if not existing.onTargetingStartedList then
                    existing.onTargetingStartedList = existing.onTargetingStarted and { existing.onTargetingStarted } or {}
                    existing.onTargetingStarted = nil
                end
                table.insert(existing.onTargetingStartedList, check.onTargetingStarted)
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
    self:SetPhaseCheckTargeting(true)

    -- Save current target state ONCE for the whole batch
    local hadTarget = UnitExists("target")
    local previousTargetGUID = hadTarget and UnitGUID("target") or nil
    local previousTargetName = hadTarget and GetUnitName("target", true) or nil -- Capture name with realm

    local currentIndex = 1
    local batchTimer = nil
    local onTargetChanged -- Declare ahead for recursion

    local function cleanupBatch()
        if batchTimer then batchTimer:Cancel() batchTimer = nil end
        local ES = TRP3FW.ServiceContainer:Get("EventService")
        if ES and onTargetChanged then
            ES:UnregisterCallback(ES.Events.TARGET_CHANGED, onTargetChanged)
        end

        -- Delay clearing the flag to ensure CacheService sees it during event propagation
        C_Timer.After(0.1, function()
            TRP3FW.targetingInProgress = false
            TRP3FW:SetPhaseCheckTargeting(false)

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
        local ES = TRP3FW.ServiceContainer:Get("EventService")
        if ES and onTargetChanged then
            ES:UnregisterCallback(ES.Events.TARGET_CHANGED, onTargetChanged)
        end

        if currentIndex > #batch then
            -- Batch complete, restore target
            local success, err
            pcall(function()
                if hadTarget then
                    if UnitGUID("target") ~= previousTargetGUID then
                        -- BUG FIX: A batch can run across several seconds and several
                        -- players - plenty of time for the player to manually retarget
                        -- someone during it. If the current target isn't the pre-batch
                        -- target AND isn't one of the players THIS batch actually
                        -- targeted, it's most likely a manual retarget - leave it alone
                        -- instead of overwriting/clearing it.
                        local currentName = UnitName("target")
                        local isOneOfOurTargets = false
                        for _, batchCheck in ipairs(batch) do
                            if batchCheck.playerName == currentName then
                                isOneOfOurTargets = true
                                break
                            end
                        end

                        if not isOneOfOurTargets then
                            TRP3FW:Debug("[Batch] Target changed to someone outside this batch (likely a manual retarget) - leaving it alone", "phase")
                        -- TargetLastTarget unreliable for batches > 1, use explicit name
                        elseif previousTargetName then
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
                        -- Same manual-retarget guard as above: only clear if the current
                        -- target is one of the players THIS batch targeted, not something
                        -- the player selected themselves during the batch.
                        local currentName = UnitName("target")
                        local isOneOfOurTargets = false
                        for _, batchCheck in ipairs(batch) do
                            if batchCheck.playerName == currentName then
                                isOneOfOurTargets = true
                                break
                            end
                        end

                        if isOneOfOurTargets then
                            success, err = TRP3FW:RunPrivilegedSafe("ClearTarget()", "phase_clear_target")
                        else
                            TRP3FW:Debug("[Batch] Target changed to someone outside this batch (likely a manual retarget) - leaving it alone", "phase")
                        end
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

        -- These three "late cache hit" reads below are cross-checking caches written by
        -- OTHER stages/services (InteractionStage, AllowSender) which all key on the
        -- unescaped/clean name - not check.playerName, which is SanitizePlayerName's
        -- escaped-for-RunPrivileged output (e.g. "Il\'tar"). Using check.playerName here
        -- guaranteed a miss for every apostrophe-containing name (harmless: it just skips
        -- the optimization and falls through to a real check). Unescape (don't re-run
        -- through CleanPlayerName's whitelist, which rejects the literal backslash and
        -- would reject every apostrophe name here the same way the historical
        -- double-sanitize bug did) to get back the same clean key those writers use.
        local cleanCheckName = check.playerName:gsub("\\(.)", "%1")

        -- OPTIMIZATION 1: Check interaction cache (Strongest "In Phase" signal)
        local interactionCached = CI and CI:Get("interaction", cleanCheckName)
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
                 TRP3FW:ResolvePhaseCheckWaiters(check.playerName, true, "interaction_cache", nil, "batch")

                 currentIndex = currentIndex + 1
                 processNext()
                 return
             end
        end
        if hs then hs:IncrementStat("cacheStats", "interactionCacheMisses") end -- ADDED MISS

        -- OPTIMIZATION 2: Check allowed senders cache (Late Cache Hit)
        local allowedCached = CI and CI:Get("allowedSenders", cleanCheckName)
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
                     TRP3FW:ResolvePhaseCheckWaiters(check.playerName, true, "allowed_cache", nil, "batch")
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

                         TRP3FW:ResolvePhaseCheckWaiters(check.playerName, cached.inPhase, "cached_late", cached.mapID, "batch")

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

        -- check.playerName was ALREADY sanitized once by CheckPlayerPhase before being
        -- queued (see QueuePhaseCheck callers) - do not re-sanitize here. SanitizePlayerName
        -- escapes quotes/backslashes for safe embedding in the TargetUnit() code string it
        -- returns; running it a SECOND time on its own escaped output (e.g. "Shi\'kala")
        -- fails, because a literal backslash isn't a valid raw player-name character. That
        -- previously rejected every apostrophe-containing name here with "invalid_name".
        local sanitizedName = check.playerName

        -- Handler for result processing
        local function finishStep(result, reason, mapID)
            if processedThisStep then return end
            processedThisStep = true

            if batchTimer then batchTimer:Cancel() batchTimer = nil end
            local ES = TRP3FW.ServiceContainer:Get("EventService")
            if ES and onTargetChanged then
                ES:UnregisterCallback(ES.Events.TARGET_CHANGED, onTargetChanged)
            end

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
            TRP3FW:ResolvePhaseCheckWaiters(check.playerName, result, reason, mapID, "batch")

            currentIndex = currentIndex + 1
            processNext()
        end

        -- Event listener for immediate success
        onTargetChanged = function()
            local newName = UnitName("target")
            if newName == check.playerName then
                local targetMap = C_Map.GetBestMapForUnit("target")
                TRP3FW:Debug(function()
                    return "[Batch] "..check.playerName.." - IN PHASE (Event driven)"
                end, "phase")
                finishStep(true, "batch_targeting", targetMap)
            end
        end
        if ES then
            ES:RegisterCallback(ES.Events.TARGET_CHANGED, onTargetChanged)
        end

        local success, err, waitTime = TRP3FW:RunPrivilegedSafe('TargetUnit("'..sanitizedName..'")', category)

        if success then
            if check.onTargetingStarted then check.onTargetingStarted() end
            if check.onTargetingStartedList then
                for _, fn in ipairs(check.onTargetingStartedList) do fn() end
            end
            TRP3FW:FirePhaseCheckTargetingStarted(check.playerName)

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
                local combinedStarted = check.onTargetingStarted
                if check.onTargetingStartedList then
                    combinedStarted = function()
                        if check.onTargetingStarted then check.onTargetingStarted() end
                        for _, fn in ipairs(check.onTargetingStartedList) do fn() end
                    end
                end
                -- BUG FIX: previously passed only check.callbacks[1], silently dropping
                -- every other merged caller (a batch entry that picked up duplicates
                -- before hitting deferred_low_priority). Fan out to a single closure that
                -- calls ALL of them, so the requeued entry's one `callback` slot still
                -- reaches every original caller once it resolves.
                local combinedCallback = check.callback
                if check.callbacks then
                    combinedCallback = function(...)
                        for _, cb in ipairs(check.callbacks) do
                            if cb then cb(...) end
                        end
                    end
                end
                TRP3FW:QueuePhaseCheck(check.playerName, check.sendId, combinedCallback, check.priority, nil, combinedStarted, true)
            else
                TRP3FW:Debug("[Batch] "..check.playerName.." - FAILED ("..tostring(err)..")", "phase")
                if check.callbacks then
                    for _, cb in ipairs(check.callbacks) do
                        -- Treat API error as "Not Found" (false) to trigger descriptive alerts
                        -- but keep the reason as "error" for technical tracking
                        if cb then cb(false, "api_error", nil, "batch") end
                    end
                end
                TRP3FW:ResolvePhaseCheckWaiters(check.playerName, false, "api_error", nil, "batch")
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

-- ===================== Inspect-open deferral (shared pump) =====================
-- While the inspect window is open, checks can't target (it corrupts inspect data).
-- Instead of each deferred check owning its own retry timer (which piles up and
-- serializes throughput under concurrency), all deferred checks share ONE 1s pump
-- that sweeps the whole queue: expired checks resolve, the rest stay queued.

-- Resolve a single inspect-deferred check as the user-selected phase result. Resolves
-- to in/out of phase (not an action) so the normal phase/map modes + SPVP still decide.
function TRP3FW:ResolveInspectDeferral(check)
    local assumeInPhase = (TRP3FW.Prefs.inspectTimeoutResolution ~= "out_of_phase")
    self:Debug("[Phase Check] Inspect still open after 10s, resolving "..tostring(check.playerName)..
        " as "..(assumeInPhase and "IN PHASE" or "NOT IN PHASE"), "phase")

    -- Support both single-callback and merged-callbacks (batch) entry shapes.
    if check.callbacks then
        for _, cb in ipairs(check.callbacks) do
            if cb then cb(assumeInPhase, "checked", nil, "inspect_timeout") end
        end
    elseif check.callback then
        check.callback(assumeInPhase, "checked", nil, "inspect_timeout")
    end
    self:ResolvePhaseCheckWaiters(check.playerName, assumeInPhase, "checked", nil, "inspect_timeout")
end

-- Ensure exactly one inspect pump timer is scheduled (idempotent).
function TRP3FW:ScheduleInspectPump()
    if self.inspectRetryTimer then return end
    self.inspectRetryTimer = C_Timer.NewTimer(1.0, function()
        self.inspectRetryTimer = nil
        self:PumpInspectDeferrals()
    end)
end

-- One sweep of the whole queue, giving EVERY queued check a single attempt this tick.
-- Called once per second while inspect stays open. Each check runs through
-- ExecutePhaseCheck, which (while inspect is open) either resolves it (deadline passed)
-- or re-queues it with its deadline; undeadlined fresh checks get stamped on first pass.
function TRP3FW:PumpInspectDeferrals()
    -- If inspect has since closed, clear stale inspect deadlines (so a check re-processed
    -- during a future inspect session gets a fresh 10s window, not an already-expired one)
    -- and resume normal processing.
    if not (TRP3FW.Prefs.pausePhaseCheckOnInspect and self:IsInspectActive()) then
        for _, check in ipairs(self.pendingPhaseChecks) do
            check.inspectDeadline = nil
        end
        if #self.pendingPhaseChecks > 0 then self:ProcessPhaseCheckQueue() end
        return
    end

    -- Snapshot-and-drain: ExecutePhaseCheck re-queues deferred checks onto
    -- pendingPhaseChecks, so we must iterate a detached copy to avoid mutating the
    -- list we're walking (and to avoid reprocessing a just-re-queued check this tick).
    -- inspectPumping suppresses QueuePhaseCheck's immediate-fire so re-queues during the
    -- sweep don't reenter processing; cleared even if a check errors.
    local snapshot = self.pendingPhaseChecks
    self.pendingPhaseChecks = {}
    self.inspectPumping = true
    for _, check in ipairs(snapshot) do
        local ok, err = pcall(function() self:ExecutePhaseCheck(check) end)
        if not ok then self:Debug("[Phase Check] Inspect pump error: "..tostring(err), "phase") end
    end
    self.inspectPumping = false

    -- ExecutePhaseCheck already re-armed the pump for any check it re-queued; this is a
    -- backstop in case the queue is non-empty but nothing re-scheduled.
    if #self.pendingPhaseChecks > 0 then self:ScheduleInspectPump() end
end

-- Execute a single phase check (from queue or direct)
function TRP3FW:ExecutePhaseCheck(check)
    local playerName = check.playerName
    local priority = check.priority

    -- check.callback may itself be a fan-out closure covering several original callers
    -- (see ProcessPhaseCheckBatch's deferred_low_priority requeue, which combines
    -- multiple merged callbacks into one function rather than dropping all but one).
    -- Defensively also honor a raw check.callbacks list if one is ever present.
    local callbacks = check.callbacks or (check.callback and { check.callback }) or nil
    local function callback(...)
        if not callbacks then return end
        for _, cb in ipairs(callbacks) do
            if cb then cb(...) end
        end
    end

    -- playerName was ALREADY sanitized once by CheckPlayerPhase before being queued (see
    -- QueuePhaseCheck callers) - do not re-sanitize here. SanitizePlayerName escapes
    -- quotes/backslashes for safe embedding in the TargetUnit() code string it returns;
    -- running it a SECOND time on its own escaped output (e.g. "Shi\'kala") fails, because
    -- a literal backslash isn't a valid raw player-name character. That previously
    -- rejected every apostrophe-containing name here with "invalid_name".
    local sanitizedName = playerName

    -- Skip automated targeting while the armory/inspect window is open, otherwise
    -- retargeting yanks inspect data out from under InspectFrame. Re-queue with a 10s
    -- deadline and hand off to the shared inspect pump (one timer for ALL deferred
    -- checks, not one per check) which retries once/second and resolves expired checks.
    if TRP3FW.Prefs.pausePhaseCheckOnInspect and self:IsInspectActive() then
        local now = self:GetCurrentTime()
        local deadline = check.inspectDeadline or (now + 10)

        if now >= deadline then
            self:ResolveInspectDeferral(check)
            return
        end

        self:Debug("[Phase Check] Inspect window open, deferring "..playerName..
            " (retrying, "..string.format("%.0fs", deadline - now).." left)", "phase")
        self:QueuePhaseCheck(playerName, check.sendId, callback, priority, deadline, check.onTargetingStarted, true)
        self:ScheduleInspectPump()
        return
    end

    self.targetingInProgress = true
    self:SetPhaseCheckTargeting(true)
    self:Debug("[Phase Check] Acquired mutex for "..playerName, "phase")

    -- Save current target state
    local hadTarget = UnitExists("target")
    local previousTargetGUID = hadTarget and UnitGUID("target") or nil
    local previousTargetName = hadTarget and GetUnitName("target", true) or nil -- Capture name with realm

    -- Create event listener
    local timeoutTimer = nil
    local eventHandled = false
    local onTargetChanged

    local function cleanup()
        local ES = TRP3FW.ServiceContainer:Get("EventService")
        if ES and onTargetChanged then
            ES:UnregisterCallback(ES.Events.TARGET_CHANGED, onTargetChanged)
        end
        if timeoutTimer then
            timeoutTimer:Cancel()
            timeoutTimer = nil
        end

        -- Delay clearing the flag to ensure CacheService sees it during event propagation
        C_Timer.After(0.1, function()
            self.targetingInProgress = false
            self:SetPhaseCheckTargeting(false)
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

        -- BUG FIX: If the current target is neither our own check's subject (playerName)
        -- nor unchanged from before, the most likely explanation is the player manually
        -- retargeted someone else while this check was in flight (TargetUnit + a 1.5-3s
        -- window is plenty of time for a manual /tar or click to land). Restoring in that
        -- case would silently overwrite/clear a target the player just chose on purpose.
        -- Only restore/clear when we're confident the current selection is ours to clean
        -- up: either it's still playerName (our TargetUnit() call is what's selected), or
        -- it never changed at all.
        local currentName = UnitName("target")
        local manualRetargetDetected = targetActuallyChanged and currentName ~= playerName

        -- Restore target
        pcall(function()
            if manualRetargetDetected then
                self:Debug("[Phase Check] Target changed to something other than "..playerName..
                    " during the check (likely a manual retarget) - leaving it alone", "phase")
            elseif targetActuallyChanged then
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
        self:ResolvePhaseCheckWaiters(playerName, success, "checked", mapID, reason)
    end

    onTargetChanged = function()
        local newName = UnitName("target")
        if newName == playerName then
            handleResult(true, C_Map.GetBestMapForUnit("target"), "targeting")
        end
    end
    local ES = TRP3FW.ServiceContainer:Get("EventService")
    if ES then
        ES:RegisterCallback(ES.Events.TARGET_CHANGED, onTargetChanged)
    end

    local timeoutDuration = 3.0
    if priority == "HIGH" then timeoutDuration = 1.5 end

    timeoutTimer = C_Timer.NewTimer(timeoutDuration, function()
        -- Fallback: If event didn't fire (e.g. target didn't change), verify manually
        if UnitName("target") == playerName then
            handleResult(true, C_Map.GetBestMapForUnit("target"), "targeting_fallback")
        else
            handleResult(false, nil, "timeout")
        end
    end)

    local category = (priority == "LOW") and "phase_check_target_low" or "phase_check_target"
    local success, err, waitTime = self:RunPrivilegedSafe('TargetUnit("'..sanitizedName..'")', category)

    if success then
        if check.onTargetingStarted then check.onTargetingStarted() end
        self:FirePhaseCheckTargetingStarted(playerName)
    end

    if not success then
        if err == "deferred_low_priority" then
            -- Defer execution
            cleanup() -- Release mutex
            self:Debug("[Phase Check] Deferred "..playerName.." for "..tostring(waitTime).."s", "phase")
            C_Timer.After(waitTime, function()
                self:QueuePhaseCheck(playerName, check.sendId, callback, priority, nil, check.onTargetingStarted, true)
                if not self.phaseCheckBatchTimer then
                     -- NewTimer (cancelable), not After (nil) — keep the field a real timer object.
                     self.phaseCheckBatchTimer = C_Timer.NewTimer(0.1, function()
                         self.phaseCheckBatchTimer = nil
                         self:ProcessPhaseCheckBatch()
                     end)
                end
            end)
        else
            cleanup()
            if callback then callback(nil, "error") end
            self:ResolvePhaseCheckWaiters(playerName, nil, "error")
        end
    end
end

-- Main entry point
-- onTargetingStarted (optional): fired once TargetUnit() is actually issued for this
-- request, i.e. queueing/mutex/token wait is over and the real timeout clock has started.
-- Callers with their own correctness deadlines (e.g. cascading.lua) use this to extend
-- those deadlines so they never race against unbounded queue depth.
function TRP3FW:CheckPlayerPhase(playerName, sendId, callback, priority, onTargetingStarted)
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

        -- Short failure TTL
        if cached.inPhase == false then
            ttl = TRP3FW.Prefs.phaseCacheFailureDuration or 10
        end

        -- BUG FIX: refreshThreshold must be computed from the TTL that actually applies
        -- (success or failure) - it used to be computed from phaseCacheDuration BEFORE the
        -- failure-ttl reassignment above, so a failed check's "freshness" window was wrongly
        -- stretched to match the success refresh window (e.g. 60s = 300*0.2) instead of being
        -- scaled to the much shorter failure ttl (e.g. 10s). That let a stale phase-check
        -- failure (age between the failure ttl and the success refresh window) still take the
        -- "fresh, return immediately" branch and get replayed well past its real 10s validity.
        local refreshThreshold = ttl * (TRP3FW.Prefs.phaseCacheRefreshThreshold or 0.2)

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
    self:QueuePhaseCheck(sanitizedName, sendId, callback, priority or "NORMAL", nil, onTargetingStarted)

    -- Start batch timer if not running
    self:SchedulePhaseCheckProcessing()
end
