-- features/ghostmode.lua
-- Ghost mode profile generation - send blank profiles instead of blocking

local addonName, TRP3FW = ...

-- NOTE: Ghost-mode profile *generation* used to live here (ModifyArgsForGhostMode +
-- blank-payload helpers). That path was superseded and removed: TRP3 sends are ghosted
-- in the sendObject hook (pre-serialization), and MSP sends via GenerateMSPGhostPayload
-- in the Chomp hook. This file now only carries the start-phase block decision.

function TRP3FW:ShouldBlockForStartPhase(playerName, isProfileSend)
    if self:IsPlayerWhitelisted(playerName) then
        self:Debug("[Start Phase] "..tostring(playerName).." is whitelisted - skipping start phase protections", "hooks")
        return false, nil
    end

    -- Only apply start phase protections when we'd actually send profile data
    if not isProfileSend then
        return false, nil
    end

    -- Check if profile switch override is active (phase 169/map 1605 safety profile)
    if self.IsProfileSwitchOverrideActive and self:IsProfileSwitchOverrideActive() then
        self:Debug("[Start Phase] Profile switch override active - skipping block/ghost", "hooks")
        return false, nil
    end

    -- Check if EITHER start phase blocking OR ghost mode is enabled
    if not TRP3FW.Prefs.blockStartPhase and not TRP3FW.Prefs.ghostOnStartPhase then
        return false, nil
    end

    -- NOTE: Phase-in delay is now handled at Chomp hook level (queues sends before this check)
    -- so we don't need to check it here anymore

    -- Check if Epsilon API is available
    if not TRP3FW.hasEpsilonAPI then
        self:Debug("[Start Phase] blockStartPhase/ghostOnStartPhase enabled but Epsilon API not available", "hooks")
        return false, nil
    end

    -- OPTIMIZATION: Use cached phase ID instead of direct API call
    local phaseID = self:GetCachedPhaseID()
    self:Debug("[Start Phase] Current phase ID: "..tostring(phaseID), "hooks")

    if phaseID ~= 169 then
        return false, nil
    end

    -- Phase 169 detected - determine action (ghost takes priority over block)
    if TRP3FW.Prefs.ghostOnStartPhase and (self.hasTRP3ExchangeHooks or self.hasMSPExchangeHooks) then
        self:Debug("[Start Phase] Phase 169 detected, ghost mode enabled for "..playerName, "hooks")
        return true, "ghost"
    elseif TRP3FW.Prefs.blockStartPhase then
        self:Debug("[Start Phase] Phase 169 detected, blocking send to "..playerName, "hooks")
        return true, "block"
    else
        -- ghostOnStartPhase enabled but no exchange hooks available
        self:Debug("[Start Phase] Phase 169 detected but ghost mode has no exchange hooks, allowing send", "hooks")
        return false, nil
    end
end
