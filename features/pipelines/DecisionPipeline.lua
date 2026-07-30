-- features/pipelines/DecisionPipeline.lua
-- Main Decision Pipeline Configuration

local addonName, TRP3FW = ...

function TRP3FW:InitializeDecisionPipeline()
    local pipeline = TRP3FW.Pipeline:New("DecisionPipeline")

    -- This list is the single source of truth for stage order. The numbers below are
    -- mirrored in each stage file's header comment - keep them in sync when reordering.
    -- Stage 1: Whitelist (Fastest, bypasses everything)
    pipeline:AddStage(TRP3FW.WhitelistStage:New("Whitelist"))

    -- Stage 2: SPVP Context (Prepares salt and enabled status; never handles)
    pipeline:AddStage(TRP3FW.SPVPStage:New("SPVP"))

    -- Stage 3: Cache Check (Phase, Allowed Senders, SPVP Verified)
    pipeline:AddStage(TRP3FW.CacheStage:New("Cache"))

    -- Stage 4: Interaction Check (Mutual exchange, mouseover, target)
    pipeline:AddStage(TRP3FW.InteractionStage:New("Interaction"))

    -- Stage 5: Alert-Only Fast Path (Sends immediately if blocking disabled)
    pipeline:AddStage(TRP3FW.AlertFastPathStage:New("AlertFastPath"))

    -- Stage 6: Burst Handling (Queues requests if check in progress)
    pipeline:AddStage(TRP3FW.BurstStage:New("Burst"))

    -- Stage 7: Location Check (Async checks with SPVP fallback). Always returns
    -- handled = true, so Pipeline:Run never falls through to its unhandled result.
    pipeline:AddStage(TRP3FW.LocationStage:New("Location"))

    TRP3FW.DecisionPipeline = pipeline
    TRP3FW:Debug("DecisionPipeline initialized with " .. #pipeline.stages .. " stages.", "pipeline")
end
