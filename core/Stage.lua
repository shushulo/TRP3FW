-- core/Stage.lua
-- Base class for Pipeline Stages

local addonName, TRP3FW = ...

TRP3FW.Stage = {}
TRP3FW.Stage.__index = TRP3FW.Stage

-- N14 — STAGE INHERITANCE CONVENTION:
-- Two patterns exist in this codebase. Both work; pick by use case:
--
-- (A) Singleton-per-stage (most common — see CacheStage, BurstStage, InteractionStage):
--         local FooStage = TRP3FW.Stage:New("FooStage")
--         FooStage.__index = FooStage
--         function FooStage:Process(context) ... end
--         TRP3FW.FooStage = FooStage
--
-- (B) Class-with-instances (see SPVPStage):
--         TRP3FW.FooStage = setmetatable({}, { __index = TRP3FW.Stage })
--         function TRP3FW.FooStage:New(name)
--             local instance = TRP3FW.Stage:New(name or "FooStage")
--             setmetatable(instance, { __index = self })
--             return instance
--         end
--
-- Use (A) when one stage instance per pipeline is enough (the default). Use (B) only
-- when you genuinely need multiple instances of the same stage class. Mixing inside a
-- single file is a smell — pick one and stick to it.
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
