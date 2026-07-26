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
    if name == nil then
        -- Guard before the store below: `self.services[nil] = service` is a hard
        -- "table index is nil" error, which would abort the registering file's
        -- load partway through rather than reporting a bad service.
        TRP3FW:Error("Attempted to register a service with no name")
        return
    end

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

-- Each service is initialized under pcall. The loop below runs in `pairs` order,
-- which is arbitrary and varies between sessions -- so an unguarded error partway
-- through would leave a *different* arbitrary subset of services uninitialized each
-- login, producing symptoms that look nothing like the service that actually broke.
-- Isolating failures keeps one bad service from silently disabling the rest.
local function initializeService(name, service)
    TRP3FW:Debug("[ServiceContainer] Initializing service: " .. tostring(name), "core")
    local ok, err = pcall(service.Initialize, service)
    if not ok then
        TRP3FW:Error("Service failed to initialize: " .. tostring(name) .. ": " .. tostring(err))
    end
    return ok
end

function TRP3FW.ServiceContainer:InitializeAll()
    -- Initialize EventService FIRST to ensure it's listening to events.
    -- This is the one real ordering constraint: other services call
    -- ES:RegisterCallback from their own Initialize.
    local eventService = self.services["EventService"]
    if eventService and eventService.Initialize and not eventService.initialized then
        initializeService("EventService", eventService)
    end

    -- Initialize all other services
    for name, service in pairs(self.services) do
        if name ~= "EventService" and service.Initialize and not service.initialized then
            initializeService(name, service)
        end
    end
end
