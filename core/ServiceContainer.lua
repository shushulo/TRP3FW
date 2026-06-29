-- core/ServiceContainer.lua
-- Service Registry for TRP3FW

local addonName, TRP3FW = ...

TRP3FW.ServiceContainer = {
    services = {}
}

function TRP3FW.ServiceContainer:Register(service)
    if not service or not service.GetName then
        TRP3FW:Error("Attempted to register invalid service")
        return
    end

    local name = service:GetName()
    if self.services[name] then
        TRP3FW:Warn("Service already registered: " .. tostring(name))
        return
    end

    self.services[name] = service
    TRP3FW:Debug("Registered service: " .. tostring(name), "core")
end

function TRP3FW.ServiceContainer:Get(name)
    return self.services[name]
end

function TRP3FW.ServiceContainer:InitializeAll()
    -- Initialize EventService FIRST to ensure it's listening to events
    local eventService = self.services["EventService"]
    if eventService and eventService.Initialize and not eventService.initialized then
        TRP3FW:Debug("[ServiceContainer] Initializing EventService first", "core")
        eventService:Initialize()
    end

    -- Initialize all other services
    for name, service in pairs(self.services) do
        if name ~= "EventService" and service.Initialize and not service.initialized then
            TRP3FW:Debug("[ServiceContainer] Initializing service: " .. tostring(name), "core")
            service:Initialize()
        end
    end
end
