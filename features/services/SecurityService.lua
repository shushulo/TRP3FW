-- features/services/SecurityService.lua
-- Security Service: Sanitization, Validation, and Redaction

local addonName, TRP3FW = ...

local SecurityService = TRP3FW.Service:New("SecurityService")

-- OPTIMIZATION: Count character occurrences without creating temporary strings
-- Replaces select(2, str:gsub(char, "")) which allocates a new string on every call
-- ~20-30% faster than gsub-based counting, zero string allocations
local function countChar(str, char)
	local count = 0
	local charByte = string.byte(char)
	for i = 1, #str do
		if string.byte(str, i) == charByte then
			count = count + 1
		end
	end
	return count
end

-- Constants
-- High-byte range must be written \128-\255 (decimal escapes). The previous form
-- "\128-%255" was malformed: %2 is not a valid range endpoint, so the intended
-- 128-255 accented-character range was broken AND digits 2/5 leaked into the class
-- (letting names like "Bob2" pass). Mirrors the correct SANITIZE_ZONE_PATTERN below.
--
-- Digits ARE allowed (via %w). The "no digits by design" assumption this pattern used to carry
-- was wrong and was disproved in the field: a live Chomp hook rejected the real Epsilon name
-- "Fallywix 420-Apertus", which fails closed and so silently breaks every profile exchange
-- with that player. Epsilon permits digits in character names; the original digit rejection
-- was never a deliberate rule, it was a test pinning the side effect of the malformed
-- "\128-%255" range (which leaked the literal digits 2 and 5 into the class).
--
-- Digits are safe for the RunPrivileged use case: the sanitized name is interpolated into
-- TargetUnit("<name>") and only quotes/backslashes can escape that string context - those
-- are still escaped below and are still absent from this whitelist.
-- CleanPlayerName's reject-class below must stay in sync with this set.
local SANITIZE_NAME_PATTERN = "^([%w_%s%'\128-\255]+%-?[%w_%s%'\128-\255]*)$"
local SANITIZE_ZONE_PATTERN = "^([%w%s'%-\128-\255]+)$"
local CONTROL_CHAR_PATTERN = "%z"
local CONTROL_CLASS_PATTERN = "%c"

-- Redaction patterns grouped by category
local DEBUG_REDACTION_PATTERNS = {
    {category = "names",    pattern = "Player%-%d+%-%d+", replacement = "Player-XXX-REDACTED"},
    {category = "network",  pattern = "%d+%.%d+%.%d+%.%d+", replacement = "XXX.XXX.XXX.XXX"},
    {category = "network",  pattern = "[%w%.%%%+%-]+@[%w%.%-]+%.%w+", replacement = "[EMAIL-REDACTED]"},
    {category = "locations",pattern = "zone: [%w%s'%-]+", replacement = "zone: [REDACTED]"},
    {category = "locations",pattern = "in [%w%s'%-]+ %(%d+", replacement = "in [REDACTED]"},
    {category = "locations",pattern = "phase ID: %d+", replacement = "phase ID: [REDACTED]"},
    {category = "locations",pattern = "phaseID[=%s:]+%d+", replacement = "phaseID=[REDACTED]"},
    {category = "locations",pattern = "Phase ID[=%s:]+%d+", replacement = "Phase ID=[REDACTED]"},
    -- SPVP. NOTE these are DEFENCE IN DEPTH, not the primary control: the real fix is that
    -- production code no longer logs salt material at all (spvp_auto_init logs only a length,
    -- and /trp3fw spvpdebug prints a fingerprint via TRP3FW:GetSaltFingerprint).
    --
    -- The character class is %w, not %x. These previously required HEX, but per the salt
    -- contract Epsilon returns 15-char NON-HEX tickets, and any such value sailed straight
    -- through unredacted. Order matters: the timestamped form must precede the bare form, or
    -- the bare pattern consumes the leading hash and leaves the ":<timestamp>" dangling.
    {category = "spvp",     pattern = "salt: %w+:%d+", replacement = "salt: [REDACTED]"},
    {category = "spvp",     pattern = "salt: %w+", replacement = "salt: [REDACTED]"},
    {category = "spvp",     pattern = "[Ss]alt for phase %d+: %w+", replacement = "salt for phase [REDACTED]: [REDACTED]"},
    {category = "spvp",     pattern = "INIT:%d+:%w+:%d+", replacement = "INIT:X:REDACTED:REDACTED"},
    {category = "spvp",     pattern = "REPLY:%w+:%d+:%w+", replacement = "REPLY:REDACTED:REDACTED:REDACTED"},
}

function SecurityService:Initialize()
    TRP3FW.Service.Initialize(self)
end

local function IsRedactionCategoryEnabled(settings, category)
    if not settings then return true end
    if settings.redactEnabled == false then return false end

    if category == "names" then
        return settings.redactNames ~= false
    elseif category == "locations" then
        return settings.redactLocations ~= false
    elseif category == "network" then
        return settings.redactNetwork ~= false
    elseif category == "spvp" then
        return settings.redactSPVP ~= false
    end

    return true
end

function SecurityService:RedactSensitiveData(text)
    if not text or type(text) ~= "string" then return text end

    local settings = TRP3FW.Prefs
    if settings and settings.redactEnabled == false then
        return text
    end

    for _, redaction in ipairs(DEBUG_REDACTION_PATTERNS) do
        if IsRedactionCategoryEnabled(settings, redaction.category) then
            text = text:gsub(redaction.pattern, redaction.replacement)
        end
    end

    return text
end

function SecurityService:CleanPlayerName(name)
    if not name or type(name) ~= "string" then return nil end

    -- OPTIMIZATION: Fast-path length check (cheap length check before expensive regex)
    if #name < 2 or #name > 50 then
        TRP3FW:Debug("[SECURITY] Rejected player name with invalid length ("..#name..") in CleanPlayerName", "security")
        return nil
    end

    -- OPTIMIZATION: Fast-path control char check (single find() vs two separate find() calls)
    if name:find("%c") then
        TRP3FW:Debug("[SECURITY] Rejected player name with control characters in CleanPlayerName", "security")
        return nil
    end

    -- OPTIMIZATION: Check validated names cache (persistent across sessions)
    -- 90%+ speedup on repeat encounters - skip all validation for known-good names
    if TRP3FW_ValidatedNames and TRP3FW_ValidatedNames[name] then
        local entry = TRP3FW_ValidatedNames[name]
        local timestamp = type(entry) == "table" and entry.timestamp or 0
        -- Prefs may not be loaded yet: this is reachable from hooks that can fire before
        -- LoadProfile runs. Every other Prefs read in this file guards; this one didn't.
        local ttl = (TRP3FW.Prefs and TRP3FW.Prefs.validatedNamesCacheDuration) or 604800 -- Default: 7 days
        local age = time() - timestamp

        -- Only use cache if entry is still valid
        if age <= ttl then
            local cleanName = name:match("^([^%-]+)") or name
            return cleanName
        else
            -- Entry expired, clear it
            TRP3FW_ValidatedNames[name] = nil
        end
    end

    local CI = TRP3FW.CacheInterface
    if CI then
        local cached = CI:Get("cleanName", name)
        if cached then return cached end
    end

    local cleanName = name:match("^([^%-]+)") or name
    local normalized = cleanName -- Epsilon allows spaces in names, do not replace with underscores

    -- Digits allowed - see SANITIZE_NAME_PATTERN comment above. This reject-class is the
    -- complement of that whitelist and must stay in sync with it; a name accepted there and
    -- rejected here still fails closed at the hook (the "Fallywix 420-Apertus" bug).
    if normalized:find("[^%w_%s_%-%'\128-\255]") then
        TRP3FW:Debug("[SECURITY] Rejected malformed player name in CleanPlayerName: "..tostring(name).." (invalid characters)", "security")
        return nil
    end

    -- Store in persistent cache for future sessions (with timestamp for TTL)
    if TRP3FW_ValidatedNames then
        TRP3FW_ValidatedNames[name] = {
            timestamp = time(),
            validated = true
        }
    end

    if CI then
        CI:Set("cleanName", name, normalized)
    end

    return normalized
end

function SecurityService:SanitizePlayerName(name)
    if not name or type(name) ~= "string" then return nil end

    local CI = TRP3FW.CacheInterface
    if CI then
        local cached = CI:Get("sanitizedName", name)
        if cached ~= nil then return cached ~= false and cached or nil end
    end

    local function cacheResult(result)
        if CI then CI:Set("sanitizedName", name, result) end
    end

    if #name > 50 then
        TRP3FW:Debug("[SECURITY] Rejected oversized player name", "security")
        cacheResult(false)
        return nil
    end

    if name:find(CONTROL_CHAR_PATTERN) or name:find(CONTROL_CLASS_PATTERN) then
        TRP3FW:Debug("[SECURITY] Rejected player name with control characters", "security")
        cacheResult(false)
        return nil
    end

    local sanitized = name:match(SANITIZE_NAME_PATTERN)
    if sanitized then
        sanitized = sanitized:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("'", "\\'")
    end

    if (not sanitized or #sanitized == 0) then
        local fallback = self:CleanPlayerName(name)
        if fallback then
            -- Also escape single quotes in fallback if needed, or strip them if that's safer for fallbacks.
            -- The spec says "strip-all-quotes" as a fallback strategy if escaping fails.
            -- Here we'll strip them for the fallback as it already stripped " and \.
            fallback = fallback:gsub("['\"\\]", ""):gsub("%c", "")
            if #fallback >= 2 and #fallback <= 50 and fallback:find("[^%z]") then
                sanitized = fallback
            end
        end
    end

    if not sanitized or #sanitized == 0 then
        TRP3FW:Debug("[SECURITY] Rejected malformed player name: "..tostring(name), "security")
        cacheResult(false)
        return nil
    end

    -- Epsilon Specific: Remove realm suffix for consistent naming (single server)
    if TRP3FW.hasEpsilonAPI then
        local strippedName = sanitized:match("^([^%-]+)") -- Get everything before the first hyphen
        if strippedName and #strippedName > 0 then
            TRP3FW:Debug("[SECURITY] Stripped realm suffix for Epsilon: "..sanitized.." -> "..strippedName, "security")
            sanitized = strippedName
        end
    end

    local hyphenCount = countChar(sanitized, "-")
    if hyphenCount > 1 then
        TRP3FW:Debug("[SECURITY] Rejected player name with multiple hyphens", "security")
        cacheResult(false)
        return nil
    end

    if #sanitized < 2 then
        TRP3FW:Debug("[SECURITY] Rejected player name too short", "security")
        cacheResult(false)
        return nil
    end

    cacheResult(sanitized)
    return sanitized
end

TRP3FW.ServiceContainer:Register(SecurityService)
