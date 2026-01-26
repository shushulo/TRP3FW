-- hooks/icon.lua
-- Icon removal hooks - strip WoW texture strings from incoming profile titles

local addonName, TRP3FW = ...

-- Install icon filtering hooks
function TRP3FW:InstallIconHooks()
    if not TRP3FW_Settings.filterIcons then
        return
    end

    local hooksApplied = {}

    -- Hook MSP callback to strip incoming profile data
    if msp and msp.callback then
        table.insert(msp.callback.received, 1, function(senderID)
            local start = debugprofilestop()
            if not msp.char[senderID] or not msp.char[senderID].field then
                return
            end

            local data = msp.char[senderID].field

            -- Strip icons from Title (NT)
            if data.NT and type(data.NT) == "string" then
                data.NT = TRP3FW:StripAllIcons(data.NT)
            end

            local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
            if hs then hs:RecordPerformance(debugprofilestop() - start, "Icon Filter (MSP)") end
        end)
        table.insert(hooksApplied, "MSP Protocol")
    end

    -- Hook TRP3 sanitizers
    if TRP3_API and TRP3_API.register and TRP3_API.register.ui then
        -- Hook characteristics sanitizer for Title (TI)
        if TRP3_API.register.ui.sanitizeCharacteristics then
            local originalSanitizer = TRP3_API.register.ui.sanitizeCharacteristics

            TRP3_API.register.ui.sanitizeCharacteristics = function(structure)
                local wasModified = false

                if structure and structure.TI and type(structure.TI) == "string" then
                    local stripped = TRP3FW:StripAllIcons(structure.TI)
                    if stripped ~= structure.TI then
                        structure.TI = stripped
                        wasModified = true
                    end
                end

                local originalResult = originalSanitizer and originalSanitizer(structure) or false
                return wasModified or originalResult
            end
            table.insert(hooksApplied, "TRP3 Characteristics")
        end
    end

    if #hooksApplied > 0 then
        self:Info("Icon filter enabled - hooked: " .. table.concat(hooksApplied, ", "))
    end
end
