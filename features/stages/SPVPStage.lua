-- ===================================================================
-- TRP3 Firewall - SPVP Pipeline Stage
-- ===================================================================
-- Secure Phase Verification Protocol stage
-- Runs SPEKE handshake verification in parallel with phase checks
-- ===================================================================

local addonName, TRP3FW = ...

TRP3FW.SPVPStage = setmetatable({}, { __index = TRP3FW.Stage })

function TRP3FW.SPVPStage:New(name)
    local instance = TRP3FW.Stage:New(name or "SPVPStage")
    setmetatable(instance, { __index = self })
    return instance
end

--- Process SPVP stage
--- Runs cryptographic phase verification in parallel with normal checks
--- @param context table - Pipeline context
--- @return table - {handled = boolean, allowed = boolean (optional)}
function TRP3FW.SPVPStage:Process(context)
    -- Master toggle. Prefer the TOCTOU snapshot; fall back to the live pref only when the
    -- snapshot didn't capture it. Avoid the `a and b or c` idiom here: when the snapshot value
    -- is `false` it would wrongly fall through to the live pref (false is not nil).
    local spvpEnabled
    if context.settings and context.settings.spvpEnabled ~= nil then
        spvpEnabled = context.settings.spvpEnabled
    else
        spvpEnabled = TRP3FW.Prefs.spvpEnabled
    end

    if not spvpEnabled then
        TRP3FW:Debug("SPVP skipped: Master toggle (spvpEnabled) is disabled in settings", "spvp")
        return { handled = false }
    end

    -- Hard exclusion: NEVER use SPVP in Phase 169 (Start Phase)
    local currentPhaseID = TRP3FW:GetCurrentPhaseID()
    if currentPhaseID == 169 then
        TRP3FW:Debug("SPVP skipped: Start Phase (169) exclusion", "spvp")
        return { handled = false }
    end

    -- Check if Epsilon API available
    if not TRP3FW.hasEpsilonAPI then
        TRP3FW:Debug("SPVP skipped: Epsilon API unavailable", "spvp")
        return { handled = false }
    end

    -- Check if phase has a salt configured
    local phaseSalt = TRP3FW:GetPhaseSalt(currentPhaseID)

    if phaseSalt == nil then
        -- SALT LOADING (Async fetch in progress)
        TRP3FW:Debug("SPVP pending: Phase salt loading...", "spvp")

        -- We return async=true to tell the pipeline to wait
        -- BUT, since GetPhaseSalt doesn't take a callback here, we need a way to
        -- resume the pipeline.
        -- For now, let's skip SPVP if not ready, rather than blocking the whole pipeline.
        -- Preferred mode in Cascading Check will handle late-resolution.
        return { handled = false }
    elseif phaseSalt == "" then
        -- No salt set - skip SPVP
        TRP3FW:Debug("SPVP skipped: No phase salt configured", "spvp")
        return { handled = false }
    end

    -- Check per-phase overrides
    if context.settings.spvpPerPhaseOverrides and context.settings.spvpPerPhaseOverrides[currentPhaseID] == false then
        TRP3FW:Debug(string.format("SPVP skipped: Disabled for phase %d", currentPhaseID), "spvp")
        return { handled = false }
    end

    -- SPVP is enabled and ready
    context.spvpEnabled = true
    context.spvpPhaseID = currentPhaseID
    context.spvpSalt = phaseSalt

    TRP3FW:Debug(string.format("SPVP context prepared for %s (phase: %d)", context.playerName, currentPhaseID), "spvp")

    -- Pass to next stage
    return { handled = false }
end

TRP3FW:Debug("SPVPStage loaded", "core")
