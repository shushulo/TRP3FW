-- core/EventService.lua
-- Centralized event dispatcher to reduce overhead and ensure consistent execution order

local addonName, TRP3FW = ...

local EventService = TRP3FW.Service:New("EventService")
EventService.callbacks = {}

-- Event name aliases (unifying multiple Blizzard/Epsilon events)
EventService.Events = {
    ZONE_CHANGED = "ZONE_CHANGED",
    PHASE_CHANGED = "PHASE_CHANGED",
    PLAYER_READY = "PLAYER_READY", -- Combined LOGIN + ENTERING_WORLD
    TARGET_CHANGED = "TARGET_CHANGED",
}

function EventService:Initialize()
    TRP3FW.Service.Initialize(self)

    self.frame = CreateFrame("Frame")
    self.frame:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)

    -- Core events to listen for
    self:Listen("ADDON_LOADED")
    self:Listen("PLAYER_LOGIN")
    self:Listen("PLAYER_ENTERING_WORLD")
    self:Listen("ZONE_CHANGED_NEW_AREA")
    self:Listen("LOADING_SCREEN_DISABLED")
    self:Listen("SCENARIO_UPDATE")
    self:Listen("PLAYER_TARGET_CHANGED")
    self:Listen("UPDATE_MOUSEOVER_UNIT")
    self:Listen("WHO_LIST_UPDATE")
    self:Listen("CHAT_MSG_SYSTEM")

    -- Epsilon-specific events
    if TRP3FW.hasEpsilonAPI then
        pcall(function() self:Listen("EPSILON_PHASE_CHANGE") end)
    end
end

-- Start listening to a Blizzard event
function EventService:Listen(event)
    self.frame:RegisterEvent(event)
end

-- Register a callback for a centralized event
-- Priority: Lower numbers execute first (default: 50)
function EventService:RegisterCallback(event, func, priority)
    if not event or not func then return end

    self.callbacks[event] = self.callbacks[event] or {}
    table.insert(self.callbacks[event], {
        func = func,
        priority = priority or 50,
        active = true  -- cleared by UnregisterCallback; see Trigger
    })

    -- Sort by priority
    table.sort(self.callbacks[event], function(a, b)
        return a.priority < b.priority
    end)
end

-- Unregister a callback
function EventService:UnregisterCallback(event, func)
    if not event or not func or not self.callbacks[event] then return end

    for i, callback in ipairs(self.callbacks[event]) do
        if callback.func == func then
            -- Clear the flag as well as removing the entry: an in-flight Trigger
            -- is walking a snapshot taken before this call, and checks `active`
            -- so a callback unregistered mid-dispatch doesn't still fire.
            callback.active = false
            table.remove(self.callbacks[event], i)
            return
        end
    end
end

function EventService:OnEvent(event, ...)
    -- Debug WHO_LIST_UPDATE to diagnose issues
    if event == "WHO_LIST_UPDATE" then
        TRP3FW:Debug("[EventService] WHO_LIST_UPDATE event received from WoW", "who")
    end

    if event == "ADDON_LOADED" then
        self:Trigger("ADDON_LOADED", event, ...)
    elseif event == "PLAYER_LOGIN" then
        self:Trigger(EventService.Events.PLAYER_READY, event, ...)
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        self:Trigger(EventService.Events.ZONE_CHANGED, event, ...)
    elseif event == "SCENARIO_UPDATE" or event == "EPSILON_PHASE_CHANGE" then
        self:Trigger(EventService.Events.PHASE_CHANGED, event, ...)
    elseif event == "PLAYER_TARGET_CHANGED" then
        self:Trigger(EventService.Events.TARGET_CHANGED, event, ...)
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        self:Trigger("MOUSEOVER_CHANGED", event, ...)
    elseif event == "LOADING_SCREEN_DISABLED" then
        self:Trigger("LOADING_FINISHED", event, ...)
    elseif event == "WHO_LIST_UPDATE" then
        self:Trigger("WHO_LIST_UPDATE", event, ...)
    elseif event == "CHAT_MSG_SYSTEM" then
        self:Trigger("CHAT_MSG_SYSTEM", event, ...)
    end
end

-- Callbacks routinely mutate this event's own callback list while it is being
-- dispatched -- phase.lua's one-shot TARGET_CHANGED handler unregisters itself and
-- registers its successor from inside its own invocation (finishStep -> processNext).
-- Walking the live array with ipairs made that silently lossy: table.remove shifts
-- the following callback into the slot the loop has already passed, so it never runs
-- for that event. In practice CacheService's interaction tracker (the other
-- TARGET_CHANGED listener) was being skipped during batch phase checking -- precisely
-- the target events it most needs to see. RegisterCallback's table.sort could also
-- reorder entries mid-walk and run one twice. Both are order-dependent, so they only
-- reproduced in game and only sometimes.
--
-- Dispatch over a snapshot, skipping entries unregistered partway through.
-- Registrations made during dispatch take effect on the next event.
function EventService:Trigger(event, sourceEvent, ...)
    local callbacks = self.callbacks[event]
    if not callbacks then return end

    local snapshot = {}
    for i = 1, #callbacks do snapshot[i] = callbacks[i] end

    for _, callback in ipairs(snapshot) do
        if callback.active then
            local ok, err = pcall(callback.func, sourceEvent, ...)
            if not ok then
                TRP3FW:Error("Error in EventService callback for "..tostring(event)..": "..tostring(err))
            end
        end
    end
end

TRP3FW.ServiceContainer:Register(EventService)
