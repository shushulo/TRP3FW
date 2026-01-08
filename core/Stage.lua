-- core/Stage.lua
-- Base class for Pipeline Stages

local addonName, TRP3FW = ...

TRP3FW.Stage = {}
TRP3FW.Stage.__index = TRP3FW.Stage

function TRP3FW.Stage:New(name)
    local instance = {
        name = name
    }
    setmetatable(instance, self)
    return instance
end

function TRP3FW.Stage:Process(context)
    -- Override this method
    -- Return { handled = boolean, allowed = boolean, reason = string }
    return { handled = false }
end
