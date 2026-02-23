-- features/ghostmode_trp3.lua
-- TRP3-specific ghost mode functions
-- Generates blank profile data structures that match TRP3's expected format

local addonName, TRP3FW = ...

-- ===================== Blank Profile Generation =====================

-- Generate blank characteristics data (physical appearance, traits)
-- This matches TRP3's characteristics structure
function TRP3FW:GetBlankCharacteristicsData()
    return {
        v = 1,                       -- Version
        RA = "",                     -- Race (empty)
        CL = "",                     -- Class (empty)
        FN = UnitName("player"),     -- First name (keep real name - required)
        LN = "",                     -- Last name (empty)
        FT = "",                     -- Full title (empty)
        TI = "",                     -- Title prefix (empty)
        IC = "TEMP",                 -- Icon (default icon)
        EC = "",                     -- Eye color (empty)
        EH = "",                     -- Eye height (empty, Dracthyr only)
        AG = "",                     -- Age (empty)
        HE = "",                     -- Height (empty)
        WE = "",                     -- Weight (empty)
        RE = "",                     -- Residence (empty)
        BP = "",                     -- Birthplace (empty)
        RS = 0,                      -- Relationship status (0 = unknown)
        CH = "ffffff",               -- Name color (white, 6-char RGB hex only)
        MI = {},                     -- Misc traits (empty table)
        PS = {},                     -- Personality traits (empty table)
    }
end

-- Helper: detect if a profileID is the TRP3FW blank profile (TRP3FW_BLANK)
-- Made into a method so it can be accessed from hooks/trp3.lua
function TRP3FW:IsDefaultBlankProfileID(profileID)
	local blankName = TRP3FW.Prefs.ghostProfileName or "TRP3FW_BLANK"
	if not TRP3_Profiles or not profileID then
		return false
	end
	local profile = TRP3_Profiles[profileID]
	return profile and profile.profileName == blankName
end

-- Generate blank about data (description, backstory)
-- Uses Template 1 (simple text) with empty content
function TRP3FW:GetBlankAboutData()
    return {
        v = 1,                       -- Version
        TE = 1,                      -- Template type (1 = simple text)
        BK = 1,                      -- Background texture (default)
        MU = nil,                    -- Music (none)
        T1 = {                       -- Template 1 data
            TX = "",                 -- Text (empty)
        },
        -- T2 and T3 not needed for template 1
    }
end

-- Generate blank misc data (RP preferences, glances)
function TRP3FW:GetBlankMiscData()
    return {
        v = 1,                       -- Version
        PE = {},                     -- Peek/glance slots (empty)
        ST = {},                     -- RP style preferences (empty)
    }
end

-- Generate blank character data (current status)
-- Shows as OOC with no currently text (natural for "no profile")
function TRP3FW:GetBlankCharacterData()
    return {
        v = 1,                       -- Version
        RP = 2,                      -- RP status (2 = OOC, seems natural)
        XP = 1,                      -- Experience level (1 = beginner)
        CU = "",                     -- Currently IC (empty)
        CO = "",                     -- Currently OOC (empty)
    }
end

-- ===================== Ghost Flag Management =====================

-- Enable ghost mode for the next send to a specific player
-- REFACTORED: Sets single active ghost flag (only one ghost send at a time)
-- If a ghost flag is already active, this will REPLACE it (sequential processing)
-- @param playerName: Full "PlayerName-Realm" string
-- @param profileID: Optional profile ID to send instead of blank (nil = blank mode)
function TRP3FW:EnableGhostForNextSend(playerName, profileID)
    if not playerName or playerName == "" then
        self:Error("[Ghost Flag] Cannot enable ghost: invalid player name")
        return false
    end

    -- Check if another ghost flag is already active (warn about replacement)
    if self.ghostNextSend and self.ghostNextSend.target then
        local prevTarget = self.ghostNextSend.target
        if prevTarget ~= playerName then
            self:Debug("[Ghost Flag] WARNING: Replacing active ghost flag for "..prevTarget.." with "..playerName, "ghost")
            self:Debug("[Ghost Flag] This is expected for burst requests (sequential processing)", "ghost")
        end
    end

    local now = GetTime()
    -- FIXED: MEDIUM-3 - Add random jitter to prevent timing oracle attacks
    local jitter = math.random(0, 2000) / 1000  -- 0-2s random jitter
    local expireTime = now + 2 + jitter  -- 2-4 second window

    -- Generation counter to prevent race conditions (increment on each new ghost flag)
    self.ghostGeneration = (self.ghostGeneration or 0) + 1
    local currentGeneration = self.ghostGeneration

    -- BUG FIX: Cancel previous auto-cleanup timer to prevent accumulation
    if self.ghostCleanupTimer then
        self.ghostCleanupTimer:Cancel()
        self:Debug("[Ghost Flag] Cancelled previous auto-cleanup timer (generation: "..(currentGeneration-1)..")", "ghost")
        self.ghostCleanupTimer = nil
    end

    -- Set single ghost flag (replaces any previous flag)
    self.ghostNextSend = {
        target = playerName,
        expires = expireTime,
        addon = "TRP3",  -- or "MSP" depending on caller
        timestamp = now,
        profileID = profileID,  -- nil = blank mode, otherwise use specified profile
        generation = currentGeneration,  -- Track which generation this ghost flag belongs to
    }

    if profileID then
        self:Debug("[Ghost Flag] Enabled ghost mode for "..playerName.." with profile ID: "..tostring(profileID).." (expires in 2s, gen: "..currentGeneration..")", "ghost")
    else
        self:Debug("[Ghost Flag] Enabled ghost mode for "..playerName.." with blank profile (expires in 2s, gen: "..currentGeneration..")", "ghost")
    end

    -- Schedule automatic cleanup after 2 seconds (track timer for cancellation)
    self.ghostCleanupTimer = C_Timer.NewTimer(2, function()
        -- RACE CONDITION FIX: Only clear if this is still the current generation
        if self.ghostNextSend and self.ghostNextSend.generation == currentGeneration and self.ghostNextSend.target == playerName then
            self:Debug("[Ghost Flag] Auto-clearing expired ghost flag for "..playerName.." (gen: "..currentGeneration..")", "ghost")
            self.ghostNextSend = nil
        else
            self:Debug("[Ghost Flag] Skipping auto-cleanup - flag was replaced (gen: "..currentGeneration.." vs current: "..(self.ghostNextSend and self.ghostNextSend.generation or "none")..")", "ghost")
        end
        self.ghostCleanupTimer = nil  -- Clear timer reference after it fires
    end)

    return true
end

-- Check if a send to a specific player should be ghosted
-- REFACTORED: Checks if single ghost flag matches the target player
-- @param playerName: Full "PlayerName-Realm" string
-- @return: true if should ghost, false otherwise
function TRP3FW:ShouldGhostSendTo(playerName)
    if not self.ghostNextSend or not playerName then
        return false
    end

    -- Check if the single flag's target matches this player
    if self.ghostNextSend.target ~= playerName then
        return false
    end

    -- Check if expired
    if self.ghostNextSend.expires and GetTime() > self.ghostNextSend.expires then
        self:Debug("[Ghost Flag] Ghost flag for "..playerName.." expired", "ghost")
        self.ghostNextSend = nil
        return false
    end

    return true
end

-- Manually clear ghost flag for a player (after send completes)
-- REFACTORED: Clears single ghost flag if target matches
-- @param playerName: Full "PlayerName-Realm" string
function TRP3FW:ClearGhostFlag(playerName)
    if self.ghostNextSend and self.ghostNextSend.target == playerName then
        self:Debug("[Ghost Flag] Manually clearing ghost flag for "..playerName, "ghost")
        self.ghostNextSend = nil

        -- FIXED: HIGH-4 - Cancel cleanup timer when manually clearing flag
        if self.ghostCleanupTimer then
            self.ghostCleanupTimer:Cancel()
            self.ghostCleanupTimer = nil
            self:Debug("[Ghost Flag] Cancelled cleanup timer during manual clear", "ghost")
        end
    end
end

-- Clear all ghost flags (emergency cleanup)
-- REFACTORED: Simply clears the single flag
function TRP3FW:ClearAllGhostFlags()
    if self.ghostNextSend then
        local target = self.ghostNextSend.target or "unknown"
        self:Debug("[Ghost Flag] Clearing ghost flag (target: "..target..")", "ghost")
        self.ghostNextSend = nil
    end

    -- FIXED: HIGH-4 - Cancel cleanup timer when clearing all flags
    if self.ghostCleanupTimer then
        self.ghostCleanupTimer:Cancel()
        self.ghostCleanupTimer = nil
        self:Debug("[Ghost Flag] Cancelled cleanup timer during ClearAll", "ghost")
    end
end

-- Get the profile ID for a ghosted player (if alternate profile mode)
-- REFACTORED: Returns profileID if single flag matches target
-- @param playerName: Full "PlayerName-Realm" string
-- @return: profileID (string or nil)
function TRP3FW:GetGhostProfileID(playerName)
    if not self.ghostNextSend or not playerName then
        return nil
    end

    -- Check if target matches
    if self.ghostNextSend.target ~= playerName then
        return nil
    end

    -- Check if expired
    if self.ghostNextSend.expires and GetTime() > self.ghostNextSend.expires then
        return nil
    end

    return self.ghostNextSend.profileID  -- nil = blank mode
end

-- ===================== Profile Data Retrieval (Adapter Integration) =====================

-- Get characteristics data for ghost mode
-- If profileID is set, fetch from adapter; otherwise return blank
-- @param playerName: Player to ghost for (checks flag for profileID)
-- @return: characteristics table
function TRP3FW:GetGhostCharacteristics(playerName)
    local profileID = self:GetGhostProfileID(playerName)

    if profileID then
        -- Alternate profile mode: fetch from adapter
        self:Debug("[Ghost Data] Fetching characteristics for profile: "..tostring(profileID), "hooks")
        local data = self:GetProfileCharacteristics(profileID)
        if data then
            return data
        else
            self:Debug("[Ghost Data] Profile not found, falling back to blank", "hooks")
        end
    end

    -- Blank mode or fallback
    self:Debug("[Ghost Data] Using blank characteristics", "hooks")
    return self:GetBlankCharacteristicsData()
end

-- Get about data for ghost mode
-- @param playerName: Player to ghost for
-- @return: about table
function TRP3FW:GetGhostAbout(playerName)
    local profileID = self:GetGhostProfileID(playerName)

    if profileID then
        self:Debug("[Ghost Data] Fetching about for profile: "..tostring(profileID), "hooks")
        local data = self:GetProfileAbout(profileID)
        if data then
            return data
        else
            self:Debug("[Ghost Data] Profile not found, falling back to blank", "hooks")
        end
    end

    self:Debug("[Ghost Data] Using blank about", "hooks")
    return self:GetBlankAboutData()
end

-- Get misc data for ghost mode
-- @param playerName: Player to ghost for
-- @return: misc table
function TRP3FW:GetGhostMisc(playerName)
    local profileID = self:GetGhostProfileID(playerName)

    if profileID then
        self:Debug("[Ghost Data] Fetching misc for profile: "..tostring(profileID), "hooks")
        local data = self:GetProfileMisc(profileID)
        if data then
            return data
        else
            self:Debug("[Ghost Data] Profile not found, falling back to blank", "hooks")
        end
    end

    self:Debug("[Ghost Data] Using blank misc", "hooks")
    return self:GetBlankMiscData()
end

-- Get character data for ghost mode
-- @param playerName: Player to ghost for
-- @return: character table
function TRP3FW:GetGhostCharacter(playerName)
    local profileID = self:GetGhostProfileID(playerName)

    if profileID then
        self:Debug("[Ghost Data] Fetching character for profile: "..tostring(profileID), "hooks")
        local data = self:GetProfileCharacter(profileID)
        if data then
            return data
        else
            self:Debug("[Ghost Data] Profile not found, falling back to blank", "hooks")
        end
    end

    self:Debug("[Ghost Data] Using blank character", "hooks")
    return self:GetBlankCharacterData()
end

