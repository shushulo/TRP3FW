-- core/Context.lua
-- Base Context class for decision pipelines

local addonName, TRP3FW = ...

TRP3FW.Context = {}
TRP3FW.Context.__index = TRP3FW.Context

function TRP3FW.Context:New(data)
    local instance = data or {}
    setmetatable(instance, self)
    return instance
end

-- Decision contexts snapshot their clock read once as `now` (see
-- TRP3FW:CreateDecisionContext) so every stage reasons about the same instant --
-- that snapshot is the TOCTOU fix. Queued requests carry the same value as
-- `timestamp`. Prefer either snapshot over a fresh read, otherwise wrapping a
-- real context would silently hand back a different time than the pipeline is
-- working from. The fallback goes through TRP3FW:GetCurrentTime (monotonic), not raw GetTime().
function TRP3FW.Context:GetTimestamp()
    return self.now or self.timestamp or TRP3FW:GetCurrentTime()
end
