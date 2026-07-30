-- core/Service.lua
-- Base class for TRP3FW Services

local addonName, TRP3FW = ...

TRP3FW.Service = {}
TRP3FW.Service.__index = TRP3FW.Service

-- H2: This factory intentionally produces SINGLETONS, not instances of a class.
-- Each service in this codebase calls `Service:New("Foo")` once and then attaches
-- methods directly to the returned table. Calling `Service:New` twice with the
-- same logical service would *share* the metatable (`self` at call-time), so
-- methods attached to one would bleed into the other. If you ever need a true
-- subclass-with-multiple-instances pattern, follow the example in SPVPStage.lua
-- (`setmetatable({}, { __index = TRP3FW.Stage })` plus an explicit `:New`).
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
