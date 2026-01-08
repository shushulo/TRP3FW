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

function TRP3FW.Context:GetTimestamp()
    return self.timestamp or GetTime()
end
