-- features/stages/PhaseInStage.lua
-- Stage 2: Checks if within phase-in delay window

local addonName, TRP3FW = ...

local PhaseInStage = TRP3FW.Stage:New("PhaseInStage")
PhaseInStage.__index = PhaseInStage

function PhaseInStage:Process(context)
    local phaseInDelay = context.settings.phaseInDelay or 0
    if phaseInDelay <= 0 then
        return {handled = false, queued = false}
    end

    local timeSinceZoneChange = context.now - (TRP3FW.lastZoneChangeTime or 0)
    if timeSinceZoneChange >= phaseInDelay then
        return {handled = false, queued = false}
    end

    -- Within delay window - queue this request
    local delayRemaining = phaseInDelay - timeSinceZoneChange
    TRP3FW:Debug("Within phase-in delay window ("..string.format("%.1f", delayRemaining).."s remaining), queuing request from "..context.playerName, "send")

    -- Initialize queue
    TRP3FW.pendingPhaseInRequests = TRP3FW.pendingPhaseInRequests or {}

    -- Store context
    table.insert(TRP3FW.pendingPhaseInRequests, {
        playerName = context.playerName,
        addon = context.addon,
        isWhisper = context.isWhisper,
        sendId = context.sendId,
        originalFunc = context.originalFunc,
        originalArgs = context.originalArgs,
        queuedAt = context.now
    })

    -- Set timer to process this request
    C_Timer.After(delayRemaining, function()
        for i, request in ipairs(TRP3FW.pendingPhaseInRequests) do
            if request.sendId == context.sendId then
                TRP3FW:Debug("Processing queued request from "..request.playerName.." after phase-in delay", "send")
                table.remove(TRP3FW.pendingPhaseInRequests, i)
                
                -- Re-run pipeline for this request
                -- Note: We need to reconstruct the context or pass it through
                -- For now, we'll just call CheckLocationAndNotify again which is the entry point
                TRP3FW:CheckLocationAndNotify(request.playerName, request.addon, request.isWhisper, request.sendId, request.originalFunc, request.originalArgs)
                break
            end
        end
    end)

    return {handled = true, queued = true, reason = "phase_in_delay"}
end

TRP3FW.PhaseInStage = PhaseInStage
