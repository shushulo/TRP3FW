-- features/pipelines/DecisionPipeline.lua
-- Main Decision Pipeline Configuration

local addonName, TRP3FW = ...

function TRP3FW:InitializeDecisionPipeline()
    local pipeline = TRP3FW.Pipeline:New("DecisionPipeline")

    -- Stage 1: Whitelist (Fastest, bypasses everything)
    pipeline:AddStage(TRP3FW.WhitelistStage:New("Whitelist"))

    -- Stage 2: Phase-In Delay (Queues requests after zone change)
    pipeline:AddStage(TRP3FW.PhaseInStage:New("PhaseInDelay"))

    -- Stage 3: Cache Check (Phase, Map, Allowed Senders)
    pipeline:AddStage(TRP3FW.CacheStage:New("Cache"))

    -- Stage 4: Interaction Check (Mutual exchange, mouseover, target)
    pipeline:AddStage(TRP3FW.InteractionStage:New("Interaction"))

    -- Stage 5: Alert-Only Fast Path (Sends immediately if blocking disabled)
    pipeline:AddStage(TRP3FW.AlertFastPathStage:New("AlertFastPath"))

    -- Stage 6: Burst Handling (Queues requests if check in progress)
    pipeline:AddStage(TRP3FW.BurstStage:New("Burst"))

    -- Stage 7: Location Check (Async checks, decision logic)
    pipeline:AddStage(TRP3FW.LocationStage:New("Location"))

    TRP3FW.DecisionPipeline = pipeline
    TRP3FW:Debug("DecisionPipeline initialized with 7 stages.", "pipeline")
end
