-- hooks/msp_exchange.lua
-- LibMSP field exchange hooks for ghost mode

local addonName, TRP3FW = ...

-- Install LibMSP exchange hooks to intercept outgoing profile data
-- REFACTORED: Proxy hooks removed. We now intercept outgoing MSP messages in the Chomp hook
-- and replace the payload with ghost data if needed. This avoids complex table synchronization issues.
function TRP3FW:InstallMSPExchangeHooks()
    -- We no longer install the proxy table on msp.my
    -- Instead, we provide helper functions for the Chomp hook to generate ghost payloads
    self.hasMSPExchangeHooks = true -- Mark as "available" so other logic knows it can use ghost features
    self:Debug("MSP Exchange: Proxy hooks disabled. Using Chomp payload replacement strategy.", "hooks")
    return true
end

-- Generate a full MSP profile string for ghost mode
-- This constructs a payload like "VP:3`VA:TRP3FW...`NA:Name..."
function TRP3FW:GenerateMSPGhostPayload(target)
    local profileID = self:GetGhostProfileID(target) or TRP3FW_Settings.ghostProfileID
    local fields = self:GetProfileMSPFields(profileID)
    
    -- Fallback to blank if profile fetch fails
    if not fields then
        fields = self:GetBlankMSPFields()
    end
    
    local parts = {}
    local SEP = string.char(0x60) -- MSP field separator (backtick)
    
    for k, v in pairs(fields) do
        -- MSP protocol: FIELD:VALUE
        -- We don't need to send CRC (!FIELD:CRC) for updates, raw data is accepted
        if k and v then
            table.insert(parts, k .. ":" .. tostring(v))
        end
    end
    
    return table.concat(parts, SEP)
end

-- Verify and restore MSP hook integrity
function TRP3FW:VerifyMSPIntegrity()
    if not msp then return end

    local exchangeState = self.hookState and self.hookState.exchange
    if not exchangeState or not exchangeState.mspMyMeta then return end

    local meta = exchangeState.mspMyMeta
    local originalMSPMy = exchangeState.originalMSPMy

    -- Case 1: msp.my is not a table (nil or other)
    if type(msp.my) ~= "table" then
        self:Warn("[MSP Integrity] msp.my became "..type(msp.my).."; restoring table and metatable")
        msp.my = {}
        setmetatable(msp.my, meta)
        return
    end

    -- Case 2: Metatable missing or incorrect
    local currentMeta = getmetatable(msp.my)
    if currentMeta ~= meta then
        -- CRITICAL: This is a real problem - another addon dropped our metatable
        self:Warn("[MSP Integrity] Metatable dropped/changed! Restoring TRP3FW metatable")

        -- DIAGNOSTIC: Log details for troubleshooting (debug-only to avoid chat spam)
        self:Debug("[MSP Integrity] Old metatable: "..tostring(currentMeta)..", New metatable: "..tostring(meta), "hooks")

        -- Log stack trace for troubleshooting (only shows if security category enabled)
        local stackTrace = debugstack(2, 3, 3)
        self:Debug("[MSP Integrity] Caller stack:\n"..stackTrace, "security")

        -- SECURITY: Skip merge during active ghost sends (prevents ghost data leakage)
        if self.sendingGhostProfile or self.ghostNextSend then
            self:Debug("[MSP Integrity] Skipping merge during active ghost send (prevents ghost data leakage)", "security")
            setmetatable(msp.my, meta)
            return
        end

        -- SECURITY: Validate and merge physical fields (with whitelist, type checks, size limits)
        -- Known valid MSP fields (LibMSP specification)
        local VALID_MSP_FIELDS = {
            -- Protocol fields
            VP = true, VA = true,
            -- Name fields
            NA = true, NH = true, NI = true, NT = true, PX = true,
            -- Game fields
            GU = true, GC = true, GR = true, GS = true, GF = true,
            -- Character fields
            RA = true, RC = true, IC = true, CU = true, CO = true,
            -- Description fields
            DE = true, HI = true, MO = true,
            -- Physical appearance
            AG = true, AE = true, AH = true, AW = true,
            -- Location fields
            HB = true, HH = true,
            -- RP status fields
            FR = true, FC = true, RS = true,
            -- Additional fields
            PN = true, MU = true,
            -- TRP3-specific MSP extensions
            PS = true, PH = true, T1 = true, T2 = true, T3 = true
        }

        local merged = 0
        local rejected = 0
        local truncated = 0

        -- CRITICAL: Validate and merge into temporary table first
        -- DO NOT clear msp.my[k] until metatable is restored (prevents race condition)
        local pendingMerge = {}

        for k, v in pairs(msp.my) do
            -- Security check 1: Field whitelist
            if not VALID_MSP_FIELDS[k] then
                self:Debug("[MSP Integrity] Rejected unknown field: "..tostring(k), "security")
                rejected = rejected + 1
            -- Security check 2: Type validation (only primitives allowed)
            elseif type(v) ~= "string" and type(v) ~= "number" and type(v) ~= "boolean" then
                self:Debug("[MSP Integrity] Rejected non-primitive value for field "..tostring(k).." (type="..type(v)..")", "security")
                rejected = rejected + 1
            -- Security check 3: Size limit (prevent memory exhaustion)
            elseif type(v) == "string" and #v > 10000 then
                self:Warn("[MSP Integrity] Field "..tostring(k).." exceeds 10KB (size="..#v.."), truncating", "security")
                pendingMerge[k] = v:sub(1, 10000)
                truncated = truncated + 1
                merged = merged + 1
            else
                -- Safe to merge
                pendingMerge[k] = v
                merged = merged + 1
            end
        end

        -- Apply validated merges to originalMSPMy
        for k, v in pairs(pendingMerge) do
            originalMSPMy[k] = v
        end

        if rejected > 0 then
            self:Debug("[MSP Integrity] Rejected "..rejected.." suspicious fields during merge", "security")
        end
        if truncated > 0 then
            self:Debug("[MSP Integrity] Truncated "..truncated.." oversized fields", "security")
        end
        if merged > 0 then
            self:Debug("[MSP Integrity] Merged "..merged.." valid fields", "hooks")
        end

        -- Additional protection: Limit total field count
        local totalFields = self:CountTableEntries(originalMSPMy)
        if totalFields > 100 then
            self:Debug("[MSP Integrity] originalMSPMy has "..totalFields.." fields (>100), possible pollution", "security")
        end

        -- CRITICAL: Restore metatable BEFORE clearing physical keys
        -- This closes the race condition window where msp.my.NA would be nil
        setmetatable(msp.my, meta)

        -- NOW safe to clear physical keys (metatable __index will serve values)
        for k in pairs(pendingMerge) do
            msp.my[k] = nil
        end
    end
end

-- Get blank MSP field for ghost mode
function TRP3FW:GetGhostMSPField(playerName, field)
    local profileID = self:GetGhostProfileID(playerName)

    if profileID then
        -- Alternate profile mode: fetch field from alternate profile
        self:Debug("[Ghost MSP] Fetching field '"..field.."' from alternate profile: "..tostring(profileID), "ghost")
        local value = self:GetProfileMSPField(profileID, field)
        if value then
            return value
        else
            self:Debug("[Ghost MSP] Field not found in alternate profile, falling back to blank", "ghost")
        end
    end

    -- Blank mode or fallback: return minimal required fields
    return self:GetBlankMSPField(field)
end

-- Get all blank MSP fields (for pairs() iteration)
function TRP3FW:GetGhostMSPFields(playerName)
    local profileID = self:GetGhostProfileID(playerName)

    if profileID then
        -- Alternate profile mode
        self:Debug("[Ghost MSP] Fetching all fields from alternate profile: "..tostring(profileID), "ghost")
        local fields = self:GetProfileMSPFields(profileID)
        if fields then
            return fields
        else
            self:Debug("[Ghost MSP] Alternate profile not found, falling back to blank", "ghost")
        end
    end

    -- Blank mode or fallback
    return self:GetBlankMSPFields()
end

-- Get blank MSP fields (minimal valid MSP profile)
function TRP3FW:GetBlankMSPFields()
    -- Return minimal valid MSP profile
    -- VA (addon version) is REQUIRED by LibMSP spec
    return {
        VP = "3",                                  -- Protocol version
        VA = "TRP3FW/"..self.VERSION,             -- Addon version (REQUIRED)
        NA = UnitName("player") or "",             -- Character name (game name)
        GU = UnitGUID("player") or "",             -- GUID
        GC = select(2, UnitClass("player")) or "", -- Game class
        GR = select(2, UnitRace("player")) or "",  -- Game race
        GS = tostring(UnitSex("player")) or "",    -- Game sex
        GF = UnitFactionGroup("player") or "",     -- Game faction
        FC = "0",                                  -- RP Status: 0 (Neutral/N/A)
        CO = "",                                   -- Currently OOC: "" (Not OOC)
        -- All other RP fields omitted (NH, NI, NT, RA, RC, CU, IC, DE, HI, etc.)
    }
end

-- Get single blank MSP field
function TRP3FW:GetBlankMSPField(field)
    local fields = self:GetBlankMSPFields()
    return fields[field] or ""  -- Return empty string if field not in minimal set
end

-- Get MSP field from alternate profile
function TRP3FW:GetProfileMSPField(profileID, field)
    -- Get all MSP fields and return the requested one
    local allFields = self:GetProfileMSPFields(profileID)
    if allFields then
        return allFields[field]
    end
    return nil
end

-- Get all MSP fields from alternate profile
function TRP3FW:GetProfileMSPFields(profileID)
    if not profileID or profileID == "" then
        self:Debug("[MSP Conversion] Invalid profile ID", "ghost")
        return nil
    end

    -- Detect which addon we're using
    local detectedAddon = self:GetDetectedAddonName()
    if not detectedAddon then
        self:Debug("[MSP Conversion] No RP addon detected", "ghost")
        return nil
    end

    self:Debug("[MSP Conversion] Detected addon: "..detectedAddon, "ghost")

    -- If using MRP or XRP, profiles are already in MSP format - load directly
    if detectedAddon == "MRP" or detectedAddon == "XRP" then
        return self:GetProfileDirectMSP(profileID)
    end

    -- If using TRP3, need to convert TRP3 → MSP format
    if detectedAddon == "TRP3" then
        return self:GetProfileTRP3ToMSP(profileID)
    end

    self:Debug("[MSP Conversion] Unknown addon type: "..tostring(detectedAddon), "ghost")
    return nil
end

-- Convert TRP3 profile to MSP format
function TRP3FW:GetProfileTRP3ToMSP(profileID)
    -- OPTIMIZATION: Check MSP conversion cache first
    -- TRP3→MSP conversion is expensive (155 lines, string processing, table iteration)
    -- Profiles rarely change during play session, so cache aggressively
    local cached = self.mspConversionCache[profileID]
    if cached and cached.mspFields then
        self:Debug("[MSP Conversion] Cache HIT for profile: "..tostring(profileID), "ghost")
        return cached.mspFields
    end

    self:Debug("[MSP Conversion] Cache MISS for profile: "..tostring(profileID)..", performing full conversion", "ghost")

    -- Get profile data using adapter system
    local characteristics = self:GetProfileCharacteristics(profileID)
    local about = self:GetProfileAbout(profileID)
    local character = self:GetProfileCharacter(profileID)

    if not characteristics then
        self:Debug("[MSP Conversion] TRP3 profile not found: "..tostring(profileID), "ghost")
        return nil
    end

    self:Debug("[MSP Conversion] Converting TRP3 profile "..tostring(profileID).." to MSP format", "ghost")

    -- Convert TRP3 data to MSP fields
    local mspFields = {}

    -- Protocol and version fields (required)
    mspFields.VP = "3"  -- MSP protocol version
    mspFields.VA = "TRP3FW/"..self.VERSION  -- Addon version

    -- Game fields (always include)
    mspFields.GU = UnitGUID("player") or ""
    mspFields.GC = select(2, UnitClass("player")) or ""
    mspFields.GR = select(2, UnitRace("player")) or ""
    mspFields.GS = tostring(UnitSex("player")) or ""
    mspFields.GF = UnitFactionGroup("player") or ""

    -- Convert characteristics
    if characteristics then
        -- Name (with color if present)
        if characteristics.CH and characteristics.CH:len() > 0 then
            local completeName = self:GetCompleteName(characteristics)
            mspFields.NA = "|cff" .. characteristics.CH .. completeName .. "|r"
        else
            mspFields.NA = self:GetCompleteName(characteristics)
        end

        -- Icon
        mspFields.IC = characteristics.IC or "TEMP"

        -- Title and prefix
        mspFields.NT = characteristics.FT or nil  -- Full title
        mspFields.PX = characteristics.TI or nil  -- Title prefix

        -- Race
        mspFields.RA = characteristics.RA or nil

        -- Class (with color if present)
        if characteristics.CL and characteristics.CH and characteristics.CH:len() > 0 then
            mspFields.RC = "|cff"..characteristics.CH..characteristics.CL.."|r"
        else
            mspFields.RC = characteristics.CL or nil
        end

        -- Age
        mspFields.AG = characteristics.AG or nil

        -- Eye color (with eye height color if present - Dracthyr)
        if characteristics.EC and characteristics.EH and characteristics.EH:len() > 0 then
            mspFields.AE = "|cff"..characteristics.EH..characteristics.EC.."|r"
        else
            mspFields.AE = characteristics.EC or nil
        end

        -- Height
        mspFields.AH = characteristics.HE or nil

        -- Weight
        mspFields.AW = characteristics.WE or nil

        -- Residence (house/home)
        mspFields.HH = characteristics.RE or nil

        -- Birthplace
        mspFields.HB = characteristics.BP or nil

        -- Relationship status
        mspFields.RS = tostring(characteristics.RS or 0)

        -- Misc traits - convert to MSP fields (Motto, House, Nickname, Pronouns)
        if characteristics.MI then
            for _, miscData in pairs(characteristics.MI) do
                local name = miscData.NA
                if name == "Motto" then
                    mspFields.MO = miscData.VA
                elseif name == "House name" or name == "House" then
                    mspFields.NH = miscData.VA
                elseif name == "Nickname" or name == "Nick" then
                    mspFields.NI = miscData.VA
                elseif name == "Pronouns" then
                    mspFields.PN = miscData.VA
                end
            end
        end
    end

    -- Convert about data
    if about then
        -- Description and history depend on template type
        if about.TE == 3 then
            -- Template 3: Physical/Personality/History
            mspFields.HI = self:RemoveTextTags(about.T3 and about.T3.HI and about.T3.HI.TX)
            local PH = self:RemoveTextTags(about.T3 and about.T3.PH and about.T3.PH.TX) or ""
            local PS = self:RemoveTextTags(about.T3 and about.T3.PS and about.T3.PS.TX) or ""
            if PH ~= "" or PS ~= "" then
                mspFields.DE = ("#Physical Description\n\n%s\n\n---\n\n#Personality traits\n\n%s"):format(PH, PS)
            end
        elseif about.TE == 1 then
            -- Template 1: Simple text
            mspFields.DE = self:RemoveTextTags(about.T1 and about.T1.TX)
        elseif about.TE == 2 then
            -- Template 2: Multiple blocks
            local blocks = {}
            if about.T2 then
                for _, data in ipairs(about.T2) do
                    if data.TX then
                        table.insert(blocks, self:RemoveTextTags(data.TX))
                    end
                end
            end
            if #blocks > 0 then
                mspFields.DE = table.concat(blocks, "\n\n---\n\n")
            end
        end

        -- Music
        mspFields.MU = about.MU and tostring(about.MU) or nil
    end

    -- Convert character/status data
    if character then
        -- Currently IC/OOC
        mspFields.CU = character.CU or nil
        mspFields.CO = character.CO or nil

        -- RP experience (FR field)
        if character.XP == 1 then
            mspFields.FR = "4"  -- Beginner
        elseif character.XP == 2 then
            mspFields.FR = "Experienced roleplayer"
        else
            mspFields.FR = "Volunteer roleplayer"
        end

        -- RP status (FC field)
        if character.RP == 1 then
            mspFields.FC = "2"  -- IC
        else
            mspFields.FC = "1"  -- OOC
        end
    end

    self:Debug("[MSP Conversion] Converted "..(self:CountTableEntries(mspFields) or 0).." MSP fields", "ghost")

    -- OPTIMIZATION: Cache the conversion result for future use
    -- Profiles rarely change during a play session, so this dramatically reduces overhead
    self.mspConversionCache[profileID] = {
        mspFields = mspFields,
        timestamp = self:GetCurrentTime()
    }
    self:Debug("[MSP Conversion] Cached conversion result for profile: "..tostring(profileID), "ghost")

    return mspFields
end

-- Get complete name from characteristics (first + last name)
function TRP3FW:GetCompleteName(characteristics)
    if not characteristics then return UnitName("player") or "" end

    local firstName = characteristics.FN or UnitName("player") or ""
    local lastName = characteristics.LN or ""

    if lastName and lastName ~= "" then
        return firstName .. " " .. lastName
    end
    return firstName
end

-- Get direct MSP data from MRP/XRP profiles (no conversion needed - already MSP format)
function TRP3FW:GetProfileDirectMSP(profileID)
    -- Try loading MRP profile
    if mrp and mrpSaved and mrpSaved.Profiles and mrpSaved.Profiles[profileID] then
        self:Debug("[Direct MSP] Loading MRP profile: "..tostring(profileID), "ghost")
        local sourceProfile = mrpSaved.Profiles[profileID]

        -- MRP stores data directly in MSP format - copy all fields
        local mspFields = {}
        for field, value in pairs(sourceProfile) do
            mspFields[field] = value
        end

        -- Ensure required fields are present
        mspFields.VP = mspFields.VP or "3"
        mspFields.VA = mspFields.VA or ("TRP3FW/"..self.VERSION)
        mspFields.GU = UnitGUID("player") or ""
        mspFields.GC = select(2, UnitClass("player")) or ""
        mspFields.GR = select(2, UnitRace("player")) or ""
        mspFields.GS = tostring(UnitSex("player")) or ""
        mspFields.GF = UnitFactionGroup("player") or ""

        self:Debug("[Direct MSP] Loaded "..(self:CountTableEntries(mspFields) or 0).." MRP fields", "ghost")
        return mspFields
    end

    -- Try loading XRP profile
    if xrp and xrp.profiles and xrp.profiles[profileID] then
        self:Debug("[Direct MSP] Loading XRP profile: "..tostring(profileID), "ghost")
        local sourceProfile = xrp.profiles[profileID]

        -- XRP also stores in MSP-compatible format
        local mspFields = {}
        for field, value in pairs(sourceProfile) do
            mspFields[field] = value
        end

        -- Ensure required fields
        mspFields.VP = mspFields.VP or "3"
        mspFields.VA = mspFields.VA or ("TRP3FW/"..self.VERSION)
        mspFields.GU = UnitGUID("player") or ""
        mspFields.GC = select(2, UnitClass("player")) or ""
        mspFields.GR = select(2, UnitRace("player")) or ""
        mspFields.GS = tostring(UnitSex("player")) or ""
        mspFields.GF = UnitFactionGroup("player") or ""

        self:Debug("[Direct MSP] Loaded "..(self:CountTableEntries(mspFields) or 0).." XRP fields", "ghost")
        return mspFields
    end

    -- Profile not found
    self:Debug("[Direct MSP] Profile not found: "..tostring(profileID), "ghost")
    return nil
end

-- Remove TRP3 text tags for MSP compatibility
function TRP3FW:RemoveTextTags(text)
    if not text or type(text) ~= "string" then
        return nil
    end

    -- Convert TRP3 color tags {col:rrggbb}text{/col} to nothing (MSP doesn't support inline colors in description)
    text = text:gsub("%{col:.-}(.-){/col}", "%1")

    -- Convert TRP3 icons {icon:name:size} to [icon]
    text = text:gsub("%{icon:.-}", "[icon]")

    -- Convert TRP3 images {img:name:size} to [image]
    text = text:gsub("%{img:.-}", "[image]")

    -- Convert TRP3 links {link*url*text} to [text]( url )
    text = text:gsub("%{link%*(.-)%*(.-)%}", "[%2]( %1 )")

    -- Remove any remaining TRP3 tags
    text = text:gsub("%{.-%}", "")

    return text
end
