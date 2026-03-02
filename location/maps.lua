-- location/maps.lua
-- Map checking and scanning functionality

local addonName, TRP3FW = ...

-- ===================== Map Helpers =====================

local MAP_SCAN_MIN_INTERVAL = 60 -- do not trigger new scans more often than once per minute

function TRP3FW:GetMapName(mapID)
    if not mapID then return "Unknown" end

    -- Check unified cache first
    local CI = self.CacheInterface
    if CI then
        local cached = CI:Get("mapName", mapID)
        if cached then
            return cached
        end
    end

    -- Cache miss or expired - fetch
    local mapInfo = C_Map.GetMapInfo(mapID)
    local name = mapInfo and mapInfo.name or ("Map "..tostring(mapID))

    -- Update unified cache
    if CI then
        CI:Set("mapName", mapID, name)
    end

    return name
end

function TRP3FW:FormatLocation(zone, map, phase)
    --[[
        Formats location information for display

        @param zone string - Zone name (e.g., "Stormwind City")
        @param map number|string - Map ID or map name (optional)
        @param phase number|string - Phase ID (optional)
        @return string - Formatted location string

        Examples:
        - FormatLocation("Stormwind", 1453) → "Stormwind (Stormwind City)"
        - FormatLocation("Stormwind", nil, 169) → "Stormwind (Phase 169)"
        - FormatLocation("Stormwind") → "Stormwind"
    --]]

    local parts = {zone or "Unknown"}

    if phase then
        table.insert(parts, "Phase " .. tostring(phase))
    elseif map then
        local mapName = type(map) == "number" and self:GetMapName(map) or map
        if mapName and mapName ~= zone then
            table.insert(parts, mapName)
        end
    end

    if #parts > 1 then
        return parts[1] .. " (" .. table.concat(parts, ", ", 2) .. ")"
    end

    return parts[1]
end

function TRP3FW:GetCurrentMapID()
    -- Try multiple methods to get current map ID
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then
        self:Debug("Got player map ID from GetBestMapForUnit: "..tostring(mapID), "channel")
        return mapID
    end

    -- Fallback: Try getting from currently opened map
    if WorldMapFrame and WorldMapFrame:IsShown() then
        mapID = WorldMapFrame:GetMapID()
        if mapID then
            self:Debug("Got map ID from WorldMapFrame: "..tostring(mapID), "channel")
            return mapID
        end
    end

    -- Last resort: Try TRP3's stored location data (DEPRECATED: Property removed in modern TRP3)
    -- if TRP3_API and TRP3_API.Ellyb and TRP3_API.Ellyb.GameEvents and TRP3_API.Ellyb.GameEvents.lastKnownMapID then
    --     mapID = TRP3_API.Ellyb.GameEvents.lastKnownMapID
    --     if mapID then
    --         self:Debug("Got map ID from TRP3 lastKnownMapID: "..tostring(mapID), "channel")
    --         return mapID
    --     end
    -- end

    self:Debug("Could not determine current map ID via any method", "channel")
    return nil
end

-- ===================== Map Scanning =====================

-- Create map scan frame
local mapScanFrame = CreateFrame("Frame")
mapScanFrame:RegisterEvent("CHAT_MSG_ADDON")

-- Active scan tracking
local activeScanCallbacks = {} -- playerName -> {callback, timer, found, scanMapID, nonce}
local activeScanForMap = false -- Are we currently scanning our current map?

-- Hook into TRP3's map scan events to auto-enable caching
-- Track which map is currently being scanned
local scannedMapID = nil

if TRP3_API and TRP3_API.Events then
    -- When ANY map scan starts (including manual scans from TRP3 UI), enable caching
    TRP3_API.Events.listenToEvent(TRP3_API.Events.MAP_SCAN_STARTED, function(scanDuration)
        activeScanForMap = true
        TRP3FW.lastMapScanAt = TRP3FW:GetCurrentTime()
        -- Store the map ID being scanned (from opened world map, not player location)
        if WorldMapFrame and WorldMapFrame.GetMapID then
            scannedMapID = WorldMapFrame:GetMapID() or TRP3FW:GetCurrentMapID()
        else
            scannedMapID = TRP3FW:GetCurrentMapID()
        end
        TRP3FW:Debug("[TRP3 Event] MAP_SCAN_STARTED - enabling cache population for "..tostring(scanDuration).."s (scanning mapID: "..tostring(scannedMapID)..")", "channel")
    end)

    -- When scan ends, disable caching after a brief delay (let final responses come in)
    TRP3_API.Events.listenToEvent(TRP3_API.Events.MAP_SCAN_ENDED, function()
        C_Timer.After(1, function() -- 1 second grace period for late responses
            -- Only disable if no active callbacks remain
            if next(activeScanCallbacks) == nil then
                activeScanForMap = false
                scannedMapID = nil
                TRP3FW:Debug("[TRP3 Event] MAP_SCAN_ENDED - disabling cache population", "channel")
            else
                TRP3FW:Debug("[TRP3 Event] MAP_SCAN_ENDED - but keeping cache active (callbacks pending)", "channel")
            end
        end)
    end)

    TRP3FW:Debug("[Map Scan Hooks] Hooked into TRP3 MAP_SCAN_STARTED/ENDED events", "channel")
end

-- Hook into RPMapScan if available
if RPMapScan and RPMapScan.RequestScan then
    local originalRequestScan = RPMapScan.RequestScan
    RPMapScan.RequestScan = function(self, mapID)
        -- Enable caching when RPMapScan triggers a scan
        activeScanForMap = true
        TRP3FW.lastMapScanAt = TRP3FW:GetCurrentTime()
        TRP3FW:Debug("[RPMapScan Hook] RequestScan called - enabling cache population", "channel")

        -- Call original function
        originalRequestScan(self, mapID)

        -- Disable after 6 seconds (RPMapScan scan window + 1s grace period)
        C_Timer.After(6, function()
            if next(activeScanCallbacks) == nil then
                activeScanForMap = false
                TRP3FW:Debug("[RPMapScan Hook] Scan window ended - disabling cache population", "channel")
            end
        end)
    end

    TRP3FW:Debug("[Map Scan Hooks] Hooked into RPMapScan.RequestScan", "channel")
end

mapScanFrame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
    local start = debugprofilestop()
    if event == "CHAT_MSG_ADDON" and prefix == "RPB1" then
        local senderName = TRP3FW:CleanPlayerName(sender)
        local strictNonceRequired = TRP3FW.Prefs and TRP3FW.Prefs.scanResponseRequireNonce

        -- Safety check: If CleanPlayerName returns nil, use raw sender name for debugging
        if not senderName then
            TRP3FW:Debug("[Global RPB1] Failed to clean sender name: "..tostring(sender)..", ignoring message", "channel")
            return
        end

        -- Detailed debugging - show everything
        TRP3FW:Debug("[Global RPB1] prefix="..tostring(prefix)..", channel="..tostring(channel)..", sender="..tostring(sender)..", message="..(message and message:sub(1, 50) or "nil"), "channel")

        if not message then
            TRP3FW:Debug("[WHISPER Response] Empty message from "..senderName..", ignoring", "whisper")
            return
        end

        -- Robust parsing: allow optional leading prefix token and optional coordinates
        local tokens = {}
        for token in message:gmatch("[^~]+") do
            table.insert(tokens, token)
        end
        if tokens[1] == "RPB1" then
            table.remove(tokens, 1)
        end

        local cmd = tokens[1]
        if cmd ~= "C_SCAN" then
            TRP3FW:Debug("[WHISPER Response] Non C_SCAN command from "..senderName.." ("..tostring(cmd).."), ignoring", "whisper")
            return
        end

        local x, y, respMapID, nonceToken
        if #tokens >= 3 then
            x = tonumber(tokens[2])
            y = tonumber(tokens[3])
            if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then
                TRP3FW:Debug("[WHISPER Response] Invalid coordinates from "..senderName.." (x="..tostring(tokens[2])..", y="..tostring(tokens[3]).."), ignoring", "whisper")
                return
            end
            nonceToken = tokens[4]
        elseif #tokens >= 2 then
            respMapID = tonumber(tokens[2])
            if not respMapID then
                TRP3FW:Debug("[WHISPER Response] Invalid mapID-only response from "..senderName.." ("..tostring(tokens[2])..")", "whisper")
                return
            end
            nonceToken = tokens[3]
        else
            TRP3FW:Debug("[WHISPER Response] Malformed C_SCAN response from "..senderName.." ("..message..")", "whisper")
            return
        end

        -- Only accept scan replies over WHISPER; treat other channels as scan requests and cache their mapID
        if channel ~= "WHISPER" then
            TRP3FW.recentScanRequests = TRP3FW.recentScanRequests or {}
            TRP3FW.recentScanRequests[senderName] = {
                timestamp = TRP3FW:GetCurrentTime(),
                mapID = respMapID
            }
            TRP3FW:Debug(function()
                return "[Scan Request] Cached mapID "..tostring(respMapID).." for "..senderName.." (channel "..tostring(channel)..")"
            end, "channel")
            return
        end

        local scanInfo = activeScanCallbacks[senderName]
        
        -- If no specific callback, check if we are in a global scan mode (manual scan initiated by user)
        if not scanInfo and not activeScanForMap then
            TRP3FW:Debug("[WHISPER Response] No active scan awaiting "..senderName.." and no global scan active, ignoring unsolicited response", "whisper")
            return
        end

        -- Nonce verification (optional token; reject mismatches, optionally require presence)
        local verifiedNonce = false
        if scanInfo and scanInfo.nonce then
            if nonceToken then
                if nonceToken ~= scanInfo.nonce then
                    TRP3FW:Debug("[WHISPER Response] Nonce mismatch from "..senderName.." (expected "..tostring(scanInfo.nonce).." got "..tostring(nonceToken).."), ignoring", "whisper")
                    return
                else
                    verifiedNonce = true
                end
            else
                if strictNonceRequired then
                    TRP3FW:Debug("[WHISPER Response] Missing nonce from "..senderName.." (strict nonce required, expected "..tostring(scanInfo.nonce).."), ignoring", "whisper")
                    return
                end
                TRP3FW:Debug("[WHISPER Response] Missing nonce from "..senderName.." (expected "..tostring(scanInfo.nonce).."), accepting as unverified", "whisper")
            end
        end

        -- Optional visibility check via TRP3 Map API (matches TRP3 behaviour)
        if AddOn_TotalRP3 and AddOn_TotalRP3.Map and AddOn_TotalRP3.Map.playerCanSeeTarget then
            local ok, canSee = pcall(AddOn_TotalRP3.Map.playerCanSeeTarget, senderName)
            if ok and canSee == false then
                TRP3FW:Debug("[WHISPER Response] "..senderName.." is not visible according to TRP3 Map API - ignoring response", "whisper")
                return
            end
        end

        local now = TRP3FW:GetCurrentTime()
        -- intendedMapID: What map was originally targeted by the scan?
        -- Prioritize our own active callback's target, then the global TRP3/RPMapScan target.
        -- Do NOT fall back to our current map for the 'intended' map, as the scan could be for a remote map.
        local intendedMapID = (scanInfo and scanInfo.scanMapID) or scannedMapID

        -- scanMapID: The actual map the player is on as reported or inferred.
        -- Prioritize the map reported in the response, then the intended scan map.
        local scanMapID = respMapID or intendedMapID

        -- Reject if responder claims a different map than intended when mapID is present
        if respMapID and intendedMapID and respMapID ~= intendedMapID then
            TRP3FW:Debug("[WHISPER Response] MapID mismatch for "..senderName.." (resp "..tostring(respMapID).." != intended "..tostring(intendedMapID).."), ignoring", "whisper")
            return
        end
        local CI = TRP3FW.CacheInterface
        
        local wasInCache = false
        if CI then
            wasInCache = CI:Get("broadcast", senderName) ~= nil
        end

        TRP3FW:Debug(function()
            return "[Map Scan Response] WHISPER from "..senderName.." - "..(wasInCache and "REFRESHED" or "CACHED").." for "..TRP3FW.Prefs.scanCacheDuration.."s (scanned mapID: "..tostring(scanMapID)..")"
        end, "whisper")

        if CI then
            -- Only populate mapScan cache for C_SCAN replies
            -- broadcast cache is now decoupled from map scan replies as requested.

            CI:Set("mapScan", senderName, {
                found = true,
                timestamp = now,
                mapID = scanMapID,
                nonce = (scanInfo and scanInfo.nonce),
                verified = verifiedNonce,
            })
            TRP3FW:Debug(function()
                return "[Cache Add] recentScans: Added "..senderName.." (map scan response, scanned mapID: "..tostring(scanMapID)..")"
            end, "cache")
        end

        if scanInfo and not scanInfo.found then
            scanInfo.found = true
            TRP3FW:Debug("  (resolving specific scan callback for "..senderName..")", "channel")

            if scanInfo.timer then
                scanInfo.timer:Cancel()
            end
            if scanInfo.callback then
                scanInfo.callback(true, verifiedNonce and "scanned_verified" or "scanned", 0)
            end
            activeScanCallbacks[senderName] = nil
        end
    end

    local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
    if hs then hs:RecordPerformance(debugprofilestop() - start, "Map Scan Response") end
end)

function TRP3FW:MapScan(name, sendId, callback)
    if not self:IsMapCheckEnabled() then
        self:Debug("Map scan skipped: disabled by user setting", "channel")
        if callback then callback(false, "disabled") end
        return
    end

    -- Check if map scanning is available
    if not self.detectedAddons.MapScanner then
        self:Debug("Map scan skipped: no map scanner available (need TRP3 or RPMapScan)", "channel")
        if callback then callback(false, "no_scanner") end
        return
    end

    self:Debug("[Map Scan] Starting map scan - Looking for: '"..tostring(name).."'", "channel")

    -- Check cache first
    local CI = self.CacheInterface
    local strictNonceRequired = TRP3FW.Prefs and TRP3FW.Prefs.scanResponseRequireNonce
    local cached = nil
    if CI then
        cached = CI:Get("mapScan", name)
    end

    local currentMapID = self:GetCurrentMapID()

    -- Skip map scan if we don't have a map ID
    if not currentMapID then
        self:Debug("Map scan skipped: no map ID available (likely in instance/protected area)", "channel")
        if callback then callback(false, "no_mapid") end
        return
    end

    if cached then
        local allowedDuration = TRP3FW.Prefs.scanCacheDuration or 120
        if cached.found == false then
            allowedDuration = TRP3FW.Prefs.scanCacheFailureDuration or allowedDuration
        end
        local ageNow = self:GetCurrentTime() - cached.timestamp
        if ageNow < allowedDuration then
        if strictNonceRequired and not cached.verified then
            self:Debug("Map scan cache INVALID for "..name.." - nonce not verified and strict nonce required", "channel")
        else
            -- Verify the cached mapID matches our current map (prevent false positives after zone change)
            if cached.mapID and cached.mapID ~= currentMapID then
                local age = ageNow
                self:Debug("Map scan cache INVALID for "..name.." - cached mapID "..tostring(cached.mapID).." doesn't match current mapID "..tostring(currentMapID).." (age: "..string.format("%.1f", age).."s)", "channel")
                -- Cache invalid - fall through to do fresh scan
            else
                local age = ageNow
                self:Debug("Map scan cache hit for "..name.." (cached "..string.format("%.1f", age).."s ago, mapID: "..tostring(cached.mapID)..")", "channel")

                -- Deduplicate by sendId: Only increment stats once per unique sendId FOR THIS CACHE TYPE
                if not self.lastMapCacheSendId then
                    self.lastMapCacheSendId = {}
                end

                if not self.lastMapCacheSendId[sendId] then
                    -- First time seeing this sendId for map cache - count it
                    self.sessionStats.cacheStats.mapCacheHits = self.sessionStats.cacheStats.mapCacheHits + 1
                    self.lastMapCacheSendId[sendId] = true
                    self.lastMapCacheSendIdCount = (self.lastMapCacheSendIdCount or 0) + 1
                    self:Debug("mapCache HIT for "..name.." (sendId: "..tostring(sendId)..")", "cache")
                else
                    -- Already counted this sendId for map cache - skip
                    self:Debug("Duplicate sendId "..tostring(sendId).." already counted for mapCache, skipping stat increment", "cache")
                end

                if callback then callback(cached.found, "cached", age) end
                return
            end
        end
    end
    end

    -- Cache miss - will do fresh scan
    -- Deduplicate by sendId: Only increment stats once per unique sendId FOR THIS CACHE TYPE
    if not self.lastMapCacheSendId then
        self.lastMapCacheSendId = {}
    end

    if not self.lastMapCacheSendId[sendId] then
        -- First time seeing this sendId for map cache - count it
        self.sessionStats.cacheStats.mapCacheMisses = self.sessionStats.cacheStats.mapCacheMisses + 1
        self.lastMapCacheSendId[sendId] = true
        self.lastMapCacheSendIdCount = (self.lastMapCacheSendIdCount or 0) + 1
        self:Debug("mapCache MISS for "..name.." (sendId: "..tostring(sendId)..")", "cache")
    else
        -- Already counted this sendId for map cache - skip
        self:Debug("Duplicate sendId "..tostring(sendId).." already counted for mapCache, skipping stat increment", "cache")
    end

    -- Check if we've seen a recent broadcast from this player (respects scanCacheDuration setting)
    -- This is more reliable than triggering a new scan
    -- Players broadcast when: opening map, changing zones, periodically
    self:Debug("[Map Scan] Checking recentBroadcasts for '"..name.."'", "channel")
    
    local recentBroadcast = nil
    if CI then
        recentBroadcast = CI:Get("broadcast", name)
    end
    
    if recentBroadcast then
        local timestamp = type(recentBroadcast) == "table" and recentBroadcast.timestamp or recentBroadcast
        local cachedMapID = type(recentBroadcast) == "table" and recentBroadcast.mapID or nil
        local cachedVerified = type(recentBroadcast) == "table" and recentBroadcast.verified or false

        local allowedDuration = TRP3FW.Prefs.scanCacheDuration or 120
        local ageNow = self:GetCurrentTime() - timestamp
        local mismatch = cachedMapID and cachedMapID ~= currentMapID
        if mismatch then
            allowedDuration = TRP3FW.Prefs.scanCacheFailureDuration or allowedDuration
        end

        if ageNow < allowedDuration then
            if strictNonceRequired and not cachedVerified then
                local age = ageNow
                self:Debug("Map scan: Recent broadcast from "..name.." INVALID - nonce not verified (age: "..string.format("%.1f", age).."s)", "channel")
            else
                -- Verify the cached mapID matches our current map (prevent false positives after zone change)
                if mismatch then
                    local age = ageNow
                    self:Debug("Map scan: Recent broadcast from "..name.." INVALID - cached mapID "..tostring(cachedMapID).." doesn't match current mapID "..tostring(currentMapID).." (age: "..string.format("%.1f", age).."s)", "channel")
                    -- Cache invalid - fall through to trigger new scan
                else
                    local age = ageNow

                    -- Deduplicate by sendId: Only increment stats once per unique sendId FOR THIS CACHE TYPE
                    if not self.lastBroadcastCacheSendId then
                        self.lastBroadcastCacheSendId = {}
                    end

                    if not self.lastBroadcastCacheSendId[sendId] then
                        -- First time seeing this sendId for broadcast cache - count it
                        self.sessionStats.cacheStats.broadcastCacheHits = self.sessionStats.cacheStats.broadcastCacheHits + 1
                        self.lastBroadcastCacheSendId[sendId] = true
                        self.lastBroadcastCacheSendIdCount = (self.lastBroadcastCacheSendIdCount or 0) + 1
                        self:Debug("broadcastCache HIT for "..name.." (sendId: "..tostring(sendId)..")", "cache")
                    else
                        -- Already counted this sendId for broadcast cache - skip
                        self:Debug("Duplicate sendId "..tostring(sendId).." already counted for broadcastCache, skipping stat increment", "cache")
                    end

                    self:Debug("Map scan: Found recent broadcast from "..name.." ("..string.format("%.1f", age).."s ago, mapID: "..tostring(cachedMapID)..")", "channel")
                    if callback then callback(true, "recent_broadcast", age) end
                    return
                end
            end
        end
    end

    -- Broadcast cache miss - will trigger scan below
    -- Deduplicate by sendId: Only increment stats once per unique sendId FOR THIS CACHE TYPE
    if not self.lastBroadcastCacheSendId then
        self.lastBroadcastCacheSendId = {}
    end

    if not self.lastBroadcastCacheSendId[sendId] then
        -- First time seeing this sendId for broadcast cache - count it
        self.sessionStats.cacheStats.broadcastCacheMisses = self.sessionStats.cacheStats.broadcastCacheMisses + 1
        self.lastBroadcastCacheSendId[sendId] = true
        self.lastBroadcastCacheSendIdCount = (self.lastBroadcastCacheSendIdCount or 0) + 1
        self:Debug("broadcastCache MISS for "..name.." (sendId: "..tostring(sendId)..")", "cache")
    else
        -- Already counted this sendId for broadcast cache - skip
        self:Debug("Duplicate sendId "..tostring(sendId).." already counted for broadcastCache, skipping stat increment", "cache")
    end

    self:Debug("Map scan: No recent broadcast from "..name.." found in cache", "channel")

    -- Decide if we can proceed with a scan (or piggyback on one)
    local now = self:GetCurrentTime()
    local minInterval = (TRP3FW.Prefs and TRP3FW.Prefs.mapScanMinInterval) or MAP_SCAN_MIN_INTERVAL
    if minInterval < 0 then minInterval = MAP_SCAN_MIN_INTERVAL end
    
    -- DYNAMIC RATE LIMITING:
    -- For HIGH priority requests (scan replies), we allow a much tighter interval (5s)
    -- to ensure we can always respond to new scanners if they aren't in cache.
    if sendId == "HIGH" or (type(sendId) == "table" and sendId.priority == "HIGH") then
        minInterval = 5 -- Allow fresh scans every 5s for scan replies
    end

    local lastScanAt = self.lastMapScanAt or 0
    local sinceLastScan = now - lastScanAt
    local scanInProgress = activeScanForMap

    -- If rate limited and NOT piggybacking, fail
    if not scanInProgress and sinceLastScan < minInterval then
        self:Debug("[Map Scan] Skipping scan (last scan "..string.format("%.1f", sinceLastScan).."s ago < "..tostring(minInterval).."s limit)", "channel")
        if callback then callback(false, "scan_rate_limited", sinceLastScan) end
        return
    end

    -- Register this specific player scan with a callback
    local currentScanMapID
    if WorldMapFrame and WorldMapFrame.GetMapID then
        currentScanMapID = WorldMapFrame:GetMapID()
    end
    currentScanMapID = currentScanMapID or self:GetCurrentMapID()

    activeScanCallbacks[name] = {
        callback = callback,
        timer = nil, -- Will be set below
        found = false,
        scanMapID = currentScanMapID,
        nonce = tostring(math.random(100000, 999999)),
    }
    self:Debug("[Active Scan Registered] Waiting for WHISPER response from: '"..name.."' (nonce: "..tostring(activeScanCallbacks[name].nonce)..")", "channel")

    if scanInProgress then
        self:Debug("[Map Scan] Scan already in progress - piggybacking request for '"..name.."'", "channel")
    else
        -- Set global flag that we're scanning our map
        activeScanForMap = true
        scannedMapID = currentScanMapID
        self.lastMapScanAt = now
        self:Debug("[Map Scan Started] Will cache responses for next 5 seconds (scanning mapID: "..tostring(scannedMapID)..")", "channel")
    end

    -- Use 5 second timeout for this specific player (shorter for HIGH priority)
    local timeoutDuration = 5
    if sendId == "HIGH" or (type(sendId) == "table" and sendId.priority == "HIGH") then
        timeoutDuration = 2.5
    end

    local timerId = C_Timer.NewTimer(timeoutDuration, function()
        local scanInfo = activeScanCallbacks[name]
        if scanInfo and not scanInfo.found then
            TRP3FW:Debug("Map scan timeout for "..name.." - not found", "channel")

            -- Cache negative result with the map we intended to scan (fallback to current map)
            local timeoutMapID = scanInfo.scanMapID or scannedMapID or TRP3FW:GetCurrentMapID()
            
            local CI = TRP3FW.CacheInterface
            if CI then
                CI:Set("mapScan", name, {
                    found = false,
                    timestamp = TRP3FW:GetCurrentTime(),
                    mapID = timeoutMapID
                })
                TRP3FW:Debug("[Cache Add] recentScans: Added "..name.." (NOT FOUND - timeout, mapID: "..tostring(timeoutMapID)..")", "cache")
            end

            if scanInfo.callback then
                scanInfo.callback(false, "timeout", 0) -- 0 = fresh scan just completed
            end
            activeScanCallbacks[name] = nil
        end

        -- If no more active callbacks, disable the global scan flag
        if next(activeScanCallbacks) == nil then
            activeScanForMap = false
            TRP3FW:Debug("[Map Scan Ended] No more active scan callbacks", "channel")
        end
    end)

    activeScanCallbacks[name].timer = timerId

    if not scanInProgress then
        -- Trigger scan using multiple methods
        local scanTriggered = false

        -- Method 1: TRP3 MapScannersManager (the proper way)
        if TRP3_API and TRP3_API.MapScannersManager and TRP3_API.MapScannersManager.launch then
            pcall(function()
                TRP3_API.MapScannersManager.launch("playerScan")
                scanTriggered = true
                TRP3FW:Debug("Triggered TRP3 map scan (MapScannersManager.launch)", "channel")
            end)
        end

        -- Method 2: TRP3 direct scanner access (fallback)
        if not scanTriggered and TRP3_API and TRP3_API.MapScannersManager and TRP3_API.MapScannersManager.getByID then
            pcall(function()
                local scanner = TRP3_API.MapScannersManager.getByID("playerScan")
                if scanner and scanner.Scan then
                    scanner:Scan()
                    scanTriggered = true
                    TRP3FW:Debug("Triggered TRP3 map scan (direct scanner)", "channel")
                end
            end)
        end

        -- Method 3: RPMapScan (for compatibility)
        if not scanTriggered and RPMapScan and RPMapScan.RequestScan then
            pcall(function()
                RPMapScan:RequestScan(currentScanMapID)
                scanTriggered = true
                TRP3FW:Debug("Triggered RPMapScan for mapID: "..tostring(currentScanMapID), "channel")
            end)
        end

        if not scanTriggered then
            self:Debug("WARNING: Could not trigger any map scan!", "channel")
        end
    end
end
