-- ===================================================================
-- TRP3 Firewall - SPVP Auto-Initialization
-- ===================================================================
-- Automatically initializes phase salts when phase owners enter phases
-- ===================================================================

local addonName, TRP3FW = ...

--- Auto-initialize SPVP salt for current phase
--- Called when phase owner/officer enters a phase
local function CheckAutoInitializeSalt()
    -- Check if Epsilon API available
    if not TRP3FW.hasEpsilonAPI then return end

    -- Check if SPVP enabled
    if not TRP3FW_Settings.spvpEnabled then return end

    -- Check if auto-initialize enabled
    if not TRP3FW_Settings.spvpAutoInitialize then return end

    -- Check if we have the necessary API
    if not C_Epsilon or not C_Epsilon.IsOwner or not C_Epsilon.IsOfficer then return end
    if not C_Epsilon.GetPhaseAddonData or not C_Epsilon.SetPhaseAddonData then return end

    -- Check if user is phase owner or officer
    if not (C_Epsilon.IsOwner() or C_Epsilon.IsOfficer()) then
        TRP3FW:Debug("SPVP auto-init skipped: Not phase owner/officer", "spvp")
        return
    end

    -- Get current phase ID
    local phaseID = TRP3FW:GetCurrentPhaseID()
    if not phaseID then
        TRP3FW:Debug("SPVP auto-init skipped: No phase ID available", "spvp")
        return
    end

    -- Hard exclusion: Never auto-init in Phase 169 (Start Phase)
    if phaseID == 169 then
        TRP3FW:Debug("SPVP auto-init skipped: Start Phase (169) exclusion", "spvp")
        return
    end

    -- Check per-phase overrides
    if TRP3FW_Settings.spvpPerPhaseOverrides and TRP3FW_Settings.spvpPerPhaseOverrides[phaseID] == false then
        TRP3FW:Debug(string.format("SPVP auto-init skipped: Disabled for phase %d", phaseID), "spvp")
        return
    end

    -- Check if salt already exists (use cached check)
    local existingSalt = TRP3FW:GetPhaseSalt(phaseID, false)
    if existingSalt and existingSalt ~= "" then
        TRP3FW:Debug(string.format("SPVP auto-init skipped: Phase %d already has salt", phaseID), "spvp")
        return
    end

    -- Generate and set salt
    local salt = TRP3FW:GeneratePhaseSalt()
    
    -- Safety check
    if not salt or #salt < 32 then
        TRP3FW:Error("Generated salt is invalid or too weak. Aborting auto-init.")
        return
    end
    
    C_Epsilon.SetPhaseAddonData("TRP3FW_SPVP_KEY", salt)

    -- Update cache
    local CI = TRP3FW.CacheInterface
    if CI then
        CI:Set("spvpPhaseSalt", phaseID, {
            salt = salt,
            timestamp = TRP3FW:GetCurrentTime()
        })
    end

    -- Parse timestamp for user feedback
    local _, timestamp = TRP3FW:ParsePhaseSalt(salt)
    local dateStr = timestamp and date("%Y-%m-%d %H:%M UTC", timestamp) or "unknown"

    TRP3FW:Info(string.format("Phase %d secured with SPVP automatically. (Generated: %s)", phaseID, dateStr))
    TRP3FW:Debug(string.format("SPVP auto-init: Generated salt for phase %d: %s...", phaseID, salt:sub(1, 16)), "spvp")
end

-- Hook into phase change and login events
local autoInitFrame = CreateFrame("Frame")
autoInitFrame:RegisterEvent("PLAYER_LOGIN")      -- Login
autoInitFrame:RegisterEvent("SCENARIO_UPDATE")   -- Phase change fallback (Blizzard)

-- Custom Epsilon event for phase change (if supported natively)
pcall(function()
    autoInitFrame:RegisterEvent("EPSILON_PHASE_CHANGE")
end)

autoInitFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        -- Wait for addon to fully load before prepopulating
        C_Timer.After(5, function()
            TRP3FW:PrepopulatePhaseSaltCache()
        end)
    elseif event == "SCENARIO_UPDATE" or event == "EPSILON_PHASE_CHANGE" then
        -- Wait for phase to fully load before checking salt
        C_Timer.After(3, function()
            CheckAutoInitializeSalt()
            -- Also prepopulate the new phase's salt
            TRP3FW:PrepopulatePhaseSaltCache()
        end)
    end
end)

TRP3FW:Debug("SPVP auto-initialization handlers registered", "core")
