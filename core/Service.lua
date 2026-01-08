-- core/Service.lua
-- Base class for TRP3FW Services

local addonName, TRP3FW = ...

TRP3FW.Service = {}
TRP3FW.Service.__index = TRP3FW.Service

function TRP3FW.Service:New(name)
    local instance = {
        name = name,
        initialized = false
    }
    setmetatable(instance, self)
    return instance
end

function TRP3FW.Service:Initialize()
    self.initialized = true
    TRP3FW:Debug("Service initialized: " .. tostring(self.name), "core")
end

function TRP3FW.Service:GetName()
    return self.name
end
