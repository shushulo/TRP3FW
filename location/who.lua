-- location/who.lua
-- Wrapper for WHO Engine (WhoService)

local addonName, TRP3FW = ...

-- Helper: try map/broadcast cache or a map scan when WHO cannot run
-- This is kept in location/who.lua for now as it's tightly coupled with location/cascading.lua logic
local function TryMapFallbackForWho(playerName, sendId, callback, reasonTag)
    if not callback or playerName == "__PREPOPULATE__" then
        return false
    end

    local nowTs = TRP3FW:GetCurrentTime()
    local CI = TRP3FW.CacheInterface
    local cacheDuration = (TRP3FW.Prefs and TRP3FW.Prefs.scanCacheDuration) or 120
    local cacheFailDuration = (TRP3FW.Prefs and TRP3FW.Prefs.scanCacheFailureDuration) or 10
    -- Hard-disabled: nothing transmits the nonce, so every entry is verified=false and this
    -- would reject every cache hit. See TRP3FW:IsScanNonceVerificationAvailable.
    local strictNonceRequired = TRP3FW.IsScanNonceVerificationAvailable
        and TRP3FW:IsScanNonceVerificationAvailable()
        and TRP3FW.Prefs and TRP3FW.Prefs.scanResponseRequireNonce
    local myMapID = TRP3FW:GetCurrentMapID()

    local function checkEntry(entry, sourceBase, mismatchSource)
        if not entry then return false end
        local ts = type(entry) == "table" and entry.timestamp or entry
        local mapID = type(entry) == "table" and entry.mapID or nil
        local verified = type(entry) == "table" and entry.verified or nil
        local foundFlag = type(entry) == "table" and entry.found
        if not ts then return false end

        local duration = cacheDuration
        if foundFlag == false then
            duration = cacheFailDuration
        end
        if mapID and myMapID and mapID ~= myMapID then
            duration = cacheFailDuration
        end

        local age = nowTs - ts
        if age > duration then return false end
        if strictNonceRequired and verified == false then return false end

        local source = sourceBase
        local result = foundFlag
        if mapID and myMapID and mapID ~= myMapID then
            result = false
            source = mismatchSource or (sourceBase.."_mismatch")
        elseif result == nil then
            result = (mapID and myMapID and mapID == myMapID) or true
        end

        callback(result, source, age, nil, mapID)
        TRP3FW:Debug("[WHO Fallback] Resolved via "..source.." ("..tostring(reasonTag)..") for "..playerName.." age="..string.format("%.1f", age).."s", "who")
        return true
    end

    local cached = CI and CI:Get("mapScan", playerName)
    local broadcast = CI and CI:Get("broadcast", playerName)

    if checkEntry(cached, "map_cache_match", "map_cache_mismatch") then
        return true
    end

    if checkEntry(broadcast, "map_cache_match_broadcast", "map_cache_mismatch_broadcast") then
        return true
    end

    if not TRP3FW:IsMapCheckEnabled() then
        return false
    end

    TRP3FW:Debug("[WHO Fallback] Attempting map scan ("..tostring(reasonTag)..") for "..playerName, "who")
    TRP3FW:MapScan(playerName, sendId, function(found, source, cacheAge)
        callback(found, source or "map_scan", cacheAge, nil, nil)
    end)
    return true
end

-- ===================== Public API Wrapper =====================

function TRP3FW:CheckPlayerViaWho(playerName, sendId, callback, trackStats, forceNameQuery, priority)
    local service = self.ServiceContainer:Get("WhoService")
    if not service then
        if callback then callback(false, "service_unavailable") end
        return
    end

    -- Technical WHO failures worth a map-scan rescue. These are the actual source strings
    -- WhoService:CheckPlayer / RunPrivilegedSafe emit. The previous list checked for "error"
    -- and "full", which never matched the real values ("execution_error", "queue_full"),
    -- so those failures silently skipped the fallback. Bad-input failures (invalid_name,
    -- code_too_long) and legitimate negatives (cached_zone_complete, queue_timeout) are
    -- intentionally excluded — retrying via map scan won't help and would add noise.
    local WHO_FALLBACK_SOURCES = {
        timeout = true,
        rate_limit = true,
        execution_error = true,
        queue_full = true,
        api_error = true,
        api_unavailable = true,
    }

    service:CheckPlayer(playerName, sendId, function(found, source, age, zone, mapID)
        -- Handle Map Fallback for certain technical errors
        if not found and source and WHO_FALLBACK_SOURCES[source] then
            if TryMapFallbackForWho(playerName, sendId, callback, source) then
                return
            end
        end

        if callback then callback(found, source, age, zone, mapID) end
    end, trackStats, forceNameQuery, priority)
end

function TRP3FW:ScanZoneForPlayers(callback)
    local service = self.ServiceContainer:Get("WhoService")
    if service and service.ScanZoneForPlayers then
        service:ScanZoneForPlayers(callback)
    else
        -- Fallback
        if callback then callback(false, {}, "service_unavailable") end
    end
end
