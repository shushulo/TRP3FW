-- features/ghostmode.lua
-- Ghost mode profile generation - send blank profiles instead of blocking

local addonName, TRP3FW = ...

-- ===================== Ghost Mode Profile Generation =====================

local function CreateBlankMSPFields()
    -- MSP uses field tables like {NA="Name", NH="Title", ...}
    -- Return table with minimal valid fields
    -- VA (addon version) is REQUIRED by LibMSP spec, will error if missing
    return {
        VP = "3",                                  -- Protocol version
        VA = "TRP3FW/"..TRP3FW.VERSION,           -- Addon version (REQUIRED)
        NA = UnitName("player") or "",             -- Character name
        GU = UnitGUID("player") or "",             -- GUID
        GC = select(2, UnitClass("player")) or "", -- Game class
        GR = select(2, UnitRace("player")) or "",  -- Game race
        GS = tostring(UnitSex("player")) or "",    -- Game sex
        GF = UnitFactionGroup("player") or ""      -- Game faction
        -- All other fields omitted = empty (NH, NI, NT, RA, RC, CU, CO, IC, DE, HI, AG, AE, AH, AW, HB, HH, etc.)
    }
end

local function CreateBlankTRP3Payload(infoType)
    if not TRP3_API or not TRP3_API.register or not TRP3_API.register.registerInfoTypes then
        return nil
    end

    local registerInfoTypes = TRP3_API.register.registerInfoTypes
    if infoType == registerInfoTypes.CHARACTERISTICS then
        return TRP3FW:GetBlankCharacteristicsData()
    elseif infoType == registerInfoTypes.ABOUT then
        return TRP3FW:GetBlankAboutData()
    elseif infoType == registerInfoTypes.MISC then
        return TRP3FW:GetBlankMiscData()
    elseif infoType == registerInfoTypes.CHARACTER then
        return TRP3FW:GetBlankCharacterData()
    end

    return nil
end

local function CreateBlankTRP3Profile(infoType)
    return CreateBlankTRP3Payload(infoType)
end

local blankChompPayload
local function CreateBlankChompMessage()
    if blankChompPayload then
        return blankChompPayload
    end

    -- Minimal payload: protocol version + addon marker
    local payload = {
        VP = "3",
        VA = "TRP3FW/"..TRP3FW.VERSION,
        NA = UnitName("player") or "",
        GU = UnitGUID("player") or "",
    }

    -- Serialize via Chomp if available; otherwise fall back to empty string
    if AddOn_Chomp and AddOn_Chomp.Serialize then
        local serialized = AddOn_Chomp.Serialize(payload)
        blankChompPayload = serialized or ""
    else
        blankChompPayload = ""
    end

    return blankChompPayload
end

function TRP3FW:ModifyArgsForGhostMode(addon, originalArgs)
    -- Create a copy of the args table to avoid modifying the original
    local modifiedArgs = {}
    for i, v in ipairs(originalArgs) do
        modifiedArgs[i] = v
    end

    -- Modify based on which addon/hook this is for
    if addon == "MSP" then
        -- LibMSP Reply hook: args = {sender, fields}
        -- Replace fields (arg 2) with blank
        modifiedArgs[2] = CreateBlankMSPFields()
        self:Debug("[Ghost Mode] Modified MSP fields to blank profile", "decision")
    elseif addon == "TRP3" then
        -- Args: {self, messageType, data, target, priority}
        if not TRP3_API or not modifiedArgs[3] or type(modifiedArgs[3]) ~= "table" then
            self:Debug("[Ghost Mode] Unable to modify TRP3 args (invalid payload)", "decision")
            return nil
        end

        local payload = modifiedArgs[3]
        local infoType = payload[1]
        if not infoType then
            self:Debug("[Ghost Mode] TRP3 payload missing infoType", "decision")
            return nil
        end

        local blankData = CreateBlankTRP3Profile(infoType)
        if not blankData then
            self:Debug("[Ghost Mode] Unsupported TRP3 infoType "..tostring(infoType)..", cannot ghost", "decision")
            return nil
        end

        -- Copy payload table so we don't mutate original args
        local newPayload = {}
        for k, v in pairs(payload) do
            newPayload[k] = v
        end
        newPayload[2] = blankData
        modifiedArgs[3] = newPayload
        self:Debug("[Ghost Mode] Modified TRP3 payload to blank profile", "decision")
    elseif addon == "Chomp" then
        if TRP3FW_Settings.enableChompGhost then
            -- Args: {prefix, text, chatType, target, priority, queue, callback, callbackArg}
            -- Replace payload text with a serialized blank message so Chomp hook can transmit it directly
            modifiedArgs[2] = CreateBlankChompMessage()
            self:Debug("[Ghost Mode] Replaced Chomp payload with blank profile text", "decision")
        else
            self:Debug("[Ghost Mode] Chomp ghosting disabled by setting", "decision")
            return nil
        end
    end

    return modifiedArgs
end

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
    if not TRP3FW_Settings.blockStartPhase and not TRP3FW_Settings.ghostOnStartPhase then
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
    if TRP3FW_Settings.ghostOnStartPhase and (self.hasTRP3ExchangeHooks or self.hasMSPExchangeHooks) then
        self:Debug("[Start Phase] Phase 169 detected, ghost mode enabled for "..playerName, "hooks")
        return true, "ghost"
    elseif TRP3FW_Settings.blockStartPhase then
        self:Debug("[Start Phase] Phase 169 detected, blocking send to "..playerName, "hooks")
        return true, "block"
    else
        -- ghostOnStartPhase enabled but no exchange hooks available
        self:Debug("[Start Phase] Phase 169 detected but ghost mode has no exchange hooks, allowing send", "hooks")
        return false, nil
    end
end

-- Get the current ghost target (if any active ghost flag exists)
-- REFACTORED: Returns single ghost flag target (no ambiguity)
-- Returns: playerName if should ghost, nil if normal send
function TRP3FW:GetCurrentGhostTarget()
    self:Debug("    ○ GetCurrentGhostTarget() called", "ghost")

    if not self.ghostNextSend then
        self:Debug("    ○ No active ghost flag", "ghost")
        return nil
    end

    local now = GetTime()

    -- BUG FIX: Validate structure integrity before accessing fields
    if not self.ghostNextSend.target or not self.ghostNextSend.expires then
        self:Error("[Ghost Flag] Corrupted ghost flag detected (missing target or expires), clearing")
        self:Error("  target: "..tostring(self.ghostNextSend.target)..", expires: "..tostring(self.ghostNextSend.expires))
        self.ghostNextSend = nil
        return nil
    end

    -- Check if expired
    if now > self.ghostNextSend.expires then
        local target = self.ghostNextSend.target
        self:Debug("[Ghost Flag] Ghost flag expired for "..target.." (expired "..string.format("%.1f", now - self.ghostNextSend.expires).."s ago)", "ghost")
        self.ghostNextSend = nil
        return nil
    end

    -- Return the single active ghost target
    local target = self.ghostNextSend.target
    local timeLeft = self.ghostNextSend.expires - now
    self:Debug("[Ghost Flag] Active ghost flag for "..target.." (expires in "..string.format("%.3f", timeLeft).."s)", "ghost")
    self:Debug("    ○ Ghost flag details: set at "..string.format("%.3f", self.ghostNextSend.timestamp or 0)..", expires at "..string.format("%.3f", self.ghostNextSend.expires), "ghost")

    return target
end
