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
    if not TRP3FW.Prefs.spvpEnabled then return end

    -- Check if auto-initialize enabled
    if not TRP3FW.Prefs.spvpAutoInitialize then return end

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
    if TRP3FW.Prefs.spvpPerPhaseOverrides and TRP3FW.Prefs.spvpPerPhaseOverrides[phaseID] == false then
        TRP3FW:Debug(string.format("SPVP auto-init skipped: Disabled for phase %d", phaseID), "spvp")
        return
    end

    -- Check if salt already exists (use cached check).
    --
    -- GetPhaseSalt has a THREE-valued contract:
    --   nil  -> still loading (Epsilon issued an async ticket; we do not know yet)
    --   ""   -> confirmed no salt configured for this phase
    --   str  -> the salt
    --
    -- Only "" means it is safe to generate one. Treating nil as "no salt" -- which the old
    -- `if existingSalt and existingSalt ~= ""` check did, since nil fails the first clause and
    -- falls through -- meant that on a COLD cache (the common case right after a phase change,
    -- which is exactly when this runs) auto-init would SetPhaseAddonData over a salt that was
    -- merely still being fetched. That silently rotates the phase secret: every peer's cached
    -- verification for this phase becomes invalid, and in-flight handshakes fail with a
    -- verifier mismatch, which HandleSPVPReply then treats as a hostile peer and blocks.
    --
    -- Bail on nil and let the next phase-change or login pass retry once the salt has landed.
    local existingSalt = TRP3FW:GetPhaseSalt(phaseID, false)
    if existingSalt == nil then
        TRP3FW:Debug(string.format("SPVP auto-init deferred: Phase %d salt still loading", phaseID), "spvp")
        return
    end
    if existingSalt ~= "" then
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
    -- Do NOT log salt material, not even a prefix. This used to emit `salt:sub(1, 16)` in a
    -- format no SecurityService redaction pattern matched (the patterns key off a literal
    -- "salt: " prefix), so 16 chars of the phase secret reached the debug window and any log
    -- a user pastes for support. The salt is the shared secret the whole SPVP handshake rests
    -- on; length and presence are all that is useful for diagnostics.
    TRP3FW:Debug(string.format("SPVP auto-init: Generated salt for phase %d (%d chars)", phaseID, #salt), "spvp")
end

-- Exported for tests, following the SPVP_IsWellFormedSalt precedent in spvp.lua. The
-- salt-loading guard above is the kind of three-valued logic worth pinning, and the
-- alternative (driving it through a 3s C_Timer inside an EventService callback) would test
-- the plumbing rather than the decision.
TRP3FW.CheckAutoInitializeSalt = CheckAutoInitializeSalt

-- Hook into phase change and login events via EventService
C_Timer.After(1, function()
    local ES = TRP3FW.ServiceContainer:Get("EventService")
    if not ES then return end

    ES:RegisterCallback(ES.Events.PLAYER_READY, function()
        -- Wait for addon to fully load before prepopulating
        C_Timer.After(5, function()
            TRP3FW:PrepopulatePhaseSaltCache()
        end)
    end)

    ES:RegisterCallback(ES.Events.PHASE_CHANGED, function(event)
        -- Wait for phase to fully load before checking salt
        C_Timer.After(3, function()
            CheckAutoInitializeSalt()
            -- Also prepopulate the new phase's salt
            TRP3FW:PrepopulatePhaseSaltCache()
        end)
    end)
end)

TRP3FW:Debug("SPVP auto-initialization handlers registered", "core")
