-- location/check_interface.lua
-- Unified location check interface with flattened callbacks

local addonName, TRP3FW = ...

TRP3FW.LocationCheck = {}

-- ===================== Cascading Check =====================

function TRP3FW.LocationCheck:CheckCascading(playerName, options, callback)
    --[[
        Performs cascading location check: Phase -> Map -> WHO
        Uses flattened callback structure to avoid nesting hell.

        @param playerName string
        @param options table {sendId, ...}
        @param callback function(result) where result is AsyncResult
    ]]

    -- 1. Phase Check
    self:CheckPhase(playerName, options, function(phaseResult)
        if phaseResult.ok then
            -- Phase check passed (same phase) - return success immediately
            return callback(phaseResult)
        end

        -- Phase failed, try Map Scan
        self:CheckMap(playerName, options, function(mapResult)
            if mapResult.ok then
                -- Map check passed (same map/zone) - return success immediately
                return callback(mapResult)
            end

            -- Map failed, try WHO Query
            self:CheckWHO(playerName, options, function(whoResult)
                -- Final check - return whatever we found
                return callback(whoResult)
            end)
        end)
    end)
end

-- ===================== Individual Checks Wrappers =====================

function TRP3FW.LocationCheck:CheckPhase(playerName, options, callback)
    -- Wrap existing TRP3FW:CheckPlayerPhase
    TRP3FW:CheckPlayerPhase(playerName, options.sendId, function(inPhase, source, theirMapID)
        if inPhase then
            callback(TRP3FW:CreateSuccessResult(true, source, 0, {method="phase"}))
        else
            callback(TRP3FW:CreateErrorResult("Different phase", source))
        end
    end)
end

function TRP3FW.LocationCheck:CheckMap(playerName, options, callback)
    -- Wrap existing TRP3FW:MapScan
    TRP3FW:MapScan(playerName, options.sendId, function(found, source, age)
        if found then
            callback(TRP3FW:CreateSuccessResult(true, source, age, {method="map"}))
        else
            callback(TRP3FW:CreateErrorResult("Not found on map", source))
        end
    end)
end

function TRP3FW.LocationCheck:CheckWHO(playerName, options, callback)
    -- Wrap existing TRP3FW:CheckPlayerViaWho
    TRP3FW:CheckPlayerViaWho(playerName, options.sendId, function(found, source, age, zone, mapID)
        if found then
            callback(TRP3FW:CreateSuccessResult(true, source, age, {method="who", zone=zone, mapID=mapID}))
        else
            callback(TRP3FW:CreateErrorResult("Not found in WHO", source))
        end
    end)
end
