-- hooks/icon.lua
-- Icon removal hooks - strip WoW texture strings from incoming profile fields

local addonName, TRP3FW = ...

-- Install icon filtering hooks
function TRP3FW:InstallIconHooks()
    if not TRP3FW.Prefs.filterIcons then
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

            -- Strip icons from requested MSP fields
            -- NA: Name, NT: Title, RC: Class, RA: Race, FC: Character type, CU: Currently, CO: OOC, NI: Nickname, NH: House
            local fieldsToStrip = {
                "NA", "NT", "RC", "RA", "FC", "CU", "CO", "NI", "NH"
            }

            for _, field in pairs(fieldsToStrip) do
                if data[field] and type(data[field]) == "string" then
                    data[field] = TRP3FW:StripAllIcons(data[field])
                end
            end

            local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
            if hs then hs:RecordPerformance(debugprofilestop() - start, "Icon Filter (MSP)") end
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
                    -- FN/LN: Name, TI/FT: Title, CL: Class, RA: Race
                    local fieldsToStrip = {
                        "FN", "LN", "TI", "FT", "CL", "RA"
                    }

                    for _, field in pairs(fieldsToStrip) do
                        if structure[field] and type(structure[field]) == "string" then
                            local stripped = TRP3FW:StripAllIcons(structure[field])
                            if stripped ~= structure[field] then
                                structure[field] = stripped
                                wasModified = true
                            end
                        end
                    end

                    -- Strip from misc traits (MI) - often used for House/Nickname in TRP3
                    if structure.MI and type(structure.MI) == "table" then
                        for _, trait in pairs(structure.MI) do
                            if trait.VA and type(trait.VA) == "string" then
                                local stripped = TRP3FW:StripAllIcons(trait.VA)
                                if stripped ~= trait.VA then
                                    trait.VA = stripped
                                    wasModified = true
                                end
                            end
                            if trait.NA and type(trait.NA) == "string" then
                                local stripped = TRP3FW:StripAllIcons(trait.NA)
                                if stripped ~= trait.NA then
                                    trait.NA = stripped
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

        -- Hook character sanitizer (Dashboard: Currently, OOC)
        if TRP3_API.dashboard and TRP3_API.dashboard.sanitizeCharacter then
            local originalSanitizer = TRP3_API.dashboard.sanitizeCharacter

            TRP3_API.dashboard.sanitizeCharacter = function(structure)
                local wasModified = false

                if structure then
                    -- CU: Currently, CO: OOC
                    local fieldsToStrip = {"CU", "CO"}

                    for _, field in pairs(fieldsToStrip) do
                        if structure[field] and type(structure[field]) == "string" then
                            local stripped = TRP3FW:StripAllIcons(structure[field])
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
    end

    if #hooksApplied > 0 then
        self:Info("Icon filter enabled - hooked: " .. table.concat(hooksApplied, ", "))
    end
end