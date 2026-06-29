-- core/Pipeline.lua
-- Generic Pipeline Runner

local addonName, TRP3FW = ...

TRP3FW.Pipeline = {}
TRP3FW.Pipeline.__index = TRP3FW.Pipeline

function TRP3FW.Pipeline:New(name)
    local instance = {
        name = name,
        stages = {}
    }
    setmetatable(instance, self)
    return instance
end

function TRP3FW.Pipeline:AddStage(stage)
    table.insert(self.stages, stage)
end

function TRP3FW.Pipeline:Run(context)
    TRP3FW:Debug("Pipeline '" .. self.name .. "' started.", "pipeline")

    for _, stage in ipairs(self.stages) do
        if stage.Process then
            local result = stage:Process(context)

            -- If result indicates handled, stop pipeline
            if result and result.handled then
                TRP3FW:Debug("Pipeline '" .. self.name .. "' handled by stage '" .. (stage.name or "unknown") .. "'", "pipeline")
                return result
            end
        else
            TRP3FW:Error("Invalid stage in pipeline '" .. self.name .. "'")
        end
    end

    TRP3FW:Debug("Pipeline '" .. self.name .. "' completed without handling.", "pipeline")
    return { handled = false }
end
