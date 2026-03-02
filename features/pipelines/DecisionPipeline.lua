-- features/pipelines/DecisionPipeline.lua
-- Main Decision Pipeline Configuration

local addonName, TRP3FW = ...

function TRP3FW:InitializeDecisionPipeline()
    local pipeline = TRP3FW.Pipeline:New("DecisionPipeline")

    -- Stage 1: Whitelist (Fastest, bypasses everything)
    pipeline:AddStage(TRP3FW.WhitelistStage:New("Whitelist"))

    -- Stage 2: SPVP Context (Prepares salt and enabled status)
    pipeline:AddStage(TRP3FW.SPVPStage:New("SPVP"))

    -- Stage 4: Cache Check (Phase, Map, Allowed Senders, SPVP Verified)
    pipeline:AddStage(TRP3FW.CacheStage:New("Cache"))

    -- Stage 5: Interaction Check (Mutual exchange, mouseover, target)
    pipeline:AddStage(TRP3FW.InteractionStage:New("Interaction"))

    -- Stage 6: Alert-Only Fast Path (Sends immediately if blocking disabled)
    pipeline:AddStage(TRP3FW.AlertFastPathStage:New("AlertFastPath"))

    -- Stage 7: Burst Handling (Queues requests if check in progress)
    pipeline:AddStage(TRP3FW.BurstStage:New("Burst"))

    -- Stage 8: Location Check (Async checks with SPVP fallback)
    pipeline:AddStage(TRP3FW.LocationStage:New("Location"))

    TRP3FW.DecisionPipeline = pipeline
    TRP3FW:Debug("DecisionPipeline initialized with 8 stages.", "pipeline")
end
