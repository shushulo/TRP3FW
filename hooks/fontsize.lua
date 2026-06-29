-- hooks/fontsize.lua
-- Enforce minimum heading size when TRP3 renders HTML

local addonName, TRP3FW = ...

local strlower = string.lower

local HTML_PRIORITY = {
    h1 = 4,
    h2 = 3,
    h3 = 2,
    p  = 1,
}

local HTML_TAG_PATTERN = "<%s*(/?)%s*([hHpP])([123]?)([^>]*)>"

local FONT_WRAPPER_PATTERN = "^%s*{%s*([Hh][123]|[Pp])([:cCrR])?%s*}"
local LEGACY_CHARACTER_FIELDS = {"CU", "CO"}

local function NormalizeHtmlTag(letter, digit)
    if not letter then
        return nil
    end

    local base = strlower(letter)

    if base == "p" then
        return "p"
    end

    if digit == nil or digit == "" then
        return nil
    end

    return "h" .. digit
end

local function BuildHtmlTag(level, slash, attrs, useUppercase)
    local tagName = useUppercase and level:upper() or level
    attrs = attrs or ""

    if slash ~= nil and slash ~= "" then
        return "</" .. tagName .. ">"
    end

    return "<" .. tagName .. attrs .. ">"
end

function TRP3FW:EnsureMinimumHtmlFont(html)
    if not TRP3FW.Prefs.filterMinimumFontSize then
        return html
    end

    if not html or type(html) ~= "string" or html == "" then
        return html
    end

    local level = strlower(TRP3FW.Prefs.minimumFontSizeLevel or "h3")
    if not HTML_PRIORITY[level] then
        level = "h3"
    end
    local targetPriority = HTML_PRIORITY[level]
    local modified = false

    local upgraded = html:gsub(HTML_TAG_PATTERN, function(slash, letter, digit, attrs)
        local normalizedLevel = NormalizeHtmlTag(letter, digit)
        if not normalizedLevel then
            return "<" .. (slash or "") .. letter .. (digit or "") .. attrs .. ">"
        end

        local currentPriority = HTML_PRIORITY[normalizedLevel] or 0
        if currentPriority >= targetPriority then
            return "<" .. (slash or "") .. letter .. (digit or "") .. attrs .. ">"
        end

        modified = true
        local useUppercase = letter == letter:upper()
        return BuildHtmlTag(level, slash, attrs, useUppercase)
    end)

    if modified then
        return upgraded
    end

    return html
end

function TRP3FW:NormalizeFontWrappers(text, force)
	if not force and not TRP3FW.Prefs.filterMinimumFontSize then
		return text
	end

    if not text or type(text) ~= "string" or text == "" then
        return text
    end

    local startBlock = text:match(FONT_WRAPPER_PATTERN)
    if not startBlock then
        return text
    end

    local tag = startBlock:match("([Hh][123]|[Pp])")
    if not tag then
        return text
    end
    local lowerTag = tag:lower()
    local closingPattern
    if lowerTag == "p" then
        closingPattern = "{%s*/%s*[Pp]%s*}%s*$"
    else
        local digit = lowerTag:sub(2, 2)
        local letterPattern = "[Hh]" .. digit
        closingPattern = "{%s*/%s*" .. letterPattern .. "%s*}%s*$"
    end

    if not text:find(closingPattern) then
        return text
    end

    local cleaned = text:gsub(FONT_WRAPPER_PATTERN, "", 1)
    cleaned = cleaned:gsub(closingPattern, "", 1)
    return cleaned
end

function TRP3FW:InstallFontSizeHooks()
	if self.fontSizeHookInstalled then
		return
	end

    -- Prefer TRP3 renderer when available
    if TRP3_API and TRP3_API.utils and TRP3_API.utils.str and TRP3_API.utils.str.toHTML then
        local originalToHTML = TRP3_API.utils.str.toHTML

        TRP3_API.utils.str.toHTML = function(text, ...)
            local start = debugprofilestop()
            local sourceText = text
            if TRP3FW.Prefs.filterMinimumFontSize then
                sourceText = TRP3FW:NormalizeFontWrappers(sourceText)
            end

            local html = originalToHTML(sourceText, ...)
            local ret = TRP3FW:EnsureMinimumHtmlFont(html)
            local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
            if hs then hs:RecordPerformance(debugprofilestop() - start, "Font Size (TRP3)") end
            return ret
        end

        self.originalToHTML = originalToHTML
        self.fontSizeHookInstalled = true
        self:Debug("[FontSize] Installed HTML renderer hook (TRP3)", "hooks")
        self:CleanupLegacyFontWrappers()
        return
    end

    -- Fallback: hook MyRolePlay's HTML converter (MSP)
    if mrp and mrp.ConvertStringToHTML then
        local originalMRPToHTML = mrp.ConvertStringToHTML
        mrp.ConvertStringToHTML = function(text, ...)
            local start = debugprofilestop()
            local sourceText = text
            if TRP3FW.Prefs.filterMinimumFontSize then
                sourceText = TRP3FW:NormalizeFontWrappers(sourceText)
            end
            local html = originalMRPToHTML(sourceText, ...)
            local ret = TRP3FW:EnsureMinimumHtmlFont(html)
            local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
            if hs then hs:RecordPerformance(debugprofilestop() - start, "Font Size (MRP)") end
            return ret
        end

        self.originalToHTML = originalMRPToHTML
        self.fontSizeHookInstalled = true
        self:Debug("[FontSize] Installed HTML renderer hook (MyRolePlay/MSP)", "hooks")
        self:CleanupLegacyFontWrappers()
        return
    end

    self:Warn("[FontSize] Unable to install HTML font-size hook (no TRP3 or MyRolePlay HTML renderer found)")
    return
end

function TRP3FW:CleanupLegacyFontWrappers()
	if self.fontSizeCleanupDone then
		return
	end

	local cleanedCount = 0

	if TRP3_API and TRP3_API.register and TRP3_API.register.getProfileList then
		for _, profile in pairs(TRP3_API.register.getProfileList()) do
			if profile.character then
				for _, field in ipairs(LEGACY_CHARACTER_FIELDS) do
					local value = profile.character[field]
					if type(value) == "string" then
						local cleaned = self:NormalizeFontWrappers(value, true)
						if cleaned ~= value then
							profile.character[field] = cleaned
							cleanedCount = cleanedCount + 1
						end
					end
				end
			end
		end
	end

	if msp and msp.char then
		for _, data in pairs(msp.char) do
			if data.field then
				for _, field in ipairs(LEGACY_CHARACTER_FIELDS) do
					local value = data.field[field]
					if type(value) == "string" then
						local cleaned = self:NormalizeFontWrappers(value, true)
						if cleaned ~= value then
							data.field[field] = cleaned
							cleanedCount = cleanedCount + 1
						end
					end
				end
			end
		end
	end

	self.fontSizeCleanupDone = true
	self:Debug("[FontSize] Removed legacy font wrappers from "..cleanedCount.." character fields", "hooks")
end
