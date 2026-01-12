-- core/types.lua
-- Type definitions for AsyncResult pattern and other shared structures

local addonName, TRP3FW = ...

-- ===================== AsyncResult Pattern =====================

--[[
    Standard result object for asynchronous operations.
    Used by: CacheInterface, LocationCheck, GhostProvider
]]
TRP3FW.AsyncResult = {
    ok = true,           -- boolean: success flag
    value = nil,         -- any: result data (if ok=true)
    error = nil,         -- string: error message (if ok=false)
    source = "unknown",  -- string: data source (e.g., "cache", "api", "fallback")
    age = 0,             -- number: data age in seconds (0 for fresh)
    metadata = {}        -- table: additional context (optional)
}

-- Factory function to create a standard result object
function TRP3FW:CreateAsyncResult(ok, value, error, source, age, metadata)
    return {
        ok = ok or false,
        value = value,
        error = error,
        source = source or "unknown",
        age = age or 0,
        metadata = metadata or {}
    }
end

-- Factory for successful result
function TRP3FW:CreateSuccessResult(value, source, age, metadata)
    return self:CreateAsyncResult(true, value, nil, source, age, metadata)
end

-- Factory for error result
function TRP3FW:CreateErrorResult(error, source)
    return self:CreateAsyncResult(false, nil, error, source, 0, nil)
end
