-- hooks/gradient.lua
-- Gradient removal hooks - strip color codes from incoming profiles

local addonName, TRP3FW = ...

-- Install gradient filtering hooks
function TRP3FW:InstallGradientHooks()
    if not TRP3FW.Prefs.filterGradients then
        return
    end

    -- Idempotency guard: InstallHooks re-runs on /trp3fw reloadhooks. Without this, each
    -- reload inserts another copy into msp.callback.received and re-wraps the TRP3 sanitizers
    -- (nesting our wrapper around itself), leaking hooks and multiplying per-receipt work.
    -- Mirrors the guard fontsize.lua already has.
    if self.gradientHookInstalled then
        return
    end

    local hooksApplied = {}

    -- Hook MSP callback to strip incoming profile data
    if msp and msp.callback then
        table.insert(msp.callback.received, 1, function(senderID)
            local start = debugprofilestop()
            if not msp.char[senderID] or not msp.char[senderID].field then
                local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
                if hs then hs:RecordPerformance(debugprofilestop() - start) end
                return
            end

            local data = msp.char[senderID].field

            -- Guard: some addons crash if NA is nil; default to sender name
            if data.NA == nil then
                local senderName = senderID or ""
                data.NA = senderName
            end

            -- Strip color codes from all MSP fields
            local fieldsToStrip = {
                "VA", "NA", "NH", "NI", "NT", "RA", "CU", "FR", "FC", "PX", "RC",
                "CO", "PE", "AG", "AE", "HB", "AH", "AW", "MO", "DE", "HI", "TR", "PN"
            }

            for _, field in pairs(fieldsToStrip) do
                if data[field] and type(data[field]) == "string" then
                    data[field] = TRP3FW:StripAllColorCodes(data[field])
                end
            end
            local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
            if hs then hs:RecordPerformance(debugprofilestop() - start, "Gradient Filter (MSP)") end
        end)
        table.insert(hooksApplied, "MSP Protocol")
    end

    -- Hook TRP3 sanitizers
    if TRP3_API and TRP3_API.register and TRP3_API.register.ui then
        -- Hook characteristics sanitizer
        if TRP3_API.register.ui.sanitizeCharacteristics then
            local originalSanitizer = TRP3_API.register.ui.sanitizeCharacteristics

            TRP3_API.register.ui.sanitizeCharacteristics = function(structure)
                local wasModified = false

                if structure then
                    local fieldsToStrip = {
                        "RA", "CL", "FN", "LN", "FT", "TI", "EC", "AG", "HE", "RE", "BP"
                    }

                    for _, field in pairs(fieldsToStrip) do
                        if structure[field] and type(structure[field]) == "string" then
                            local stripped = TRP3FW:StripAllColorCodes(structure[field])
                            if stripped ~= structure[field] then
                                structure[field] = stripped
                                wasModified = true
                            end
                        end
                    end

                    -- Strip from misc traits (MI)
                    if structure.MI and type(structure.MI) == "table" then
                        for _, trait in pairs(structure.MI) do
                            if trait.VA and type(trait.VA) == "string" then
                                local stripped = TRP3FW:StripAllColorCodes(trait.VA)
                                if stripped ~= trait.VA then
                                    trait.VA = stripped
                                    wasModified = true
                                end
                            end
                            if trait.NA and type(trait.NA) == "string" then
                                local stripped = TRP3FW:StripAllColorCodes(trait.NA)
                                if stripped ~= trait.NA then
                                    trait.NA = stripped
                                    wasModified = true
                                end
                            end
                        end
                    end

                    -- Strip from personality traits (PS)
                    if structure.PS and type(structure.PS) == "table" then
                        for _, trait in pairs(structure.PS) do
                            if trait.RT and type(trait.RT) == "string" then
                                local stripped = TRP3FW:StripAllColorCodes(trait.RT)
                                if stripped ~= trait.RT then
                                    trait.RT = stripped
                                    wasModified = true
                                end
                            end
                            if trait.LT and type(trait.LT) == "string" then
                                local stripped = TRP3FW:StripAllColorCodes(trait.LT)
                                if stripped ~= trait.LT then
                                    trait.LT = stripped
                                    wasModified = true
                                end
                            end
                        end
                    end
                end

                local originalResult = originalSanitizer and originalSanitizer(structure) or false
                return wasModified or originalResult
            end
            table.insert(hooksApplied, "TRP3 Characteristics")
        end

        -- Hook character sanitizer
        if TRP3_API.dashboard and TRP3_API.dashboard.sanitizeCharacter then
            local originalSanitizer = TRP3_API.dashboard.sanitizeCharacter

            TRP3_API.dashboard.sanitizeCharacter = function(structure)
                local wasModified = false

                if structure then
                    local fieldsToStrip = {"CO", "CU"}

                    for _, field in pairs(fieldsToStrip) do
                        if structure[field] and type(structure[field]) == "string" then
                            local stripped = TRP3FW:StripAllColorCodes(structure[field])
                            if stripped ~= structure[field] then
                                structure[field] = stripped
                                wasModified = true
                            end
                        end
                    end
                end

                local originalResult = originalSanitizer and originalSanitizer(structure) or false
                return wasModified or originalResult
            end
            table.insert(hooksApplied, "TRP3 Character")
        end

        -- Hook misc sanitizer
        if TRP3_API.register.ui.sanitizeMisc then
            local originalSanitizer = TRP3_API.register.ui.sanitizeMisc

            TRP3_API.register.ui.sanitizeMisc = function(structure)
                local wasModified = false

                if structure then
                    if structure.PE and type(structure.PE) == "table" then
                        for _, peek in pairs(structure.PE) do
                            if type(peek) == "table" then
                                if peek.TI and type(peek.TI) == "string" then
                                    local stripped = TRP3FW:StripAllColorCodes(peek.TI)
                                    if stripped ~= peek.TI then
                                        peek.TI = stripped
                                        wasModified = true
                                    end
                                end
                                if peek.TX and type(peek.TX) == "string" then
                                    local stripped = TRP3FW:StripAllColorCodes(peek.TX)
                                    if stripped ~= peek.TX then
                                        peek.TX = stripped
                                        wasModified = true
                                    end
                                end
                            end
                        end
                    end
                end

                local originalResult = originalSanitizer and originalSanitizer(structure) or false
                return wasModified or originalResult
            end
            table.insert(hooksApplied, "TRP3 Misc")
        end

        -- Hook about sanitizer
        if TRP3_API.register.ui.sanitizeAbout then
            local originalSanitizer = TRP3_API.register.ui.sanitizeAbout

            TRP3_API.register.ui.sanitizeAbout = function(structure)
                local wasModified = false

                if structure then
                    -- Strip from template 1 (single text)
                    if structure.T1 and structure.T1.TX and type(structure.T1.TX) == "string" then
                        local stripped = TRP3FW:StripAllColorCodes(structure.T1.TX)
                        if stripped ~= structure.T1.TX then
                            structure.T1.TX = stripped
                            wasModified = true
                        end
                    end

                    -- Strip from template 2 (multiple sections)
                    if structure.T2 and type(structure.T2) == "table" then
                        for _, section in pairs(structure.T2) do
                            if section.TX and type(section.TX) == "string" then
                                local stripped = TRP3FW:StripAllColorCodes(section.TX)
                                if stripped ~= section.TX then
                                    section.TX = stripped
                                    wasModified = true
                                end
                            end
                        end
                    end

                    -- Strip from template 3 (structured sections)
                    if structure.T3 and type(structure.T3) == "table" then
                        for _, section in pairs(structure.T3) do
                            if type(section) == "table" and section.TX and type(section.TX) == "string" then
                                local stripped = TRP3FW:StripAllColorCodes(section.TX)
                                if stripped ~= section.TX then
                                    section.TX = stripped
                                    wasModified = true
                                end
                            end
                        end
                    end
                end

                local originalResult = originalSanitizer and originalSanitizer(structure) or false
                return wasModified or originalResult
            end
            table.insert(hooksApplied, "TRP3 About")
        end
    end

    if #hooksApplied > 0 then
        self.gradientHookInstalled = true
        self:Info("Gradient filter enabled - hooked: " .. table.concat(hooksApplied, ", "))
    end
end
