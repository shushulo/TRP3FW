-- hooks/icon.lua
-- Icon removal hooks - strip WoW texture strings from incoming profile fields

local addonName, TRP3FW = ...

-- Install icon filtering hooks
function TRP3FW:InstallIconHooks()
    if not TRP3FW.Prefs.filterIcons then
        return
    end

    -- Idempotency guard: InstallHooks re-runs on /trp3fw reloadhooks. Without this, each
    -- reload inserts another copy into msp.callback.received and re-wraps the TRP3 sanitizers
    -- (nesting our wrapper around itself), leaking hooks and multiplying per-receipt work.
    -- Mirrors the guard fontsize.lua already has.
    if self.iconHookInstalled then
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

            -- Strip icons from all MSP free-text fields (mirrors gradient.lua's field list, plus PH).
            -- Icon tags get stuffed into ANY field to sneak into wherever that field is displayed,
            -- so every user-editable string field needs stripping, not just NA/Name.
            -- DE/HI (Description/History) are deliberately excluded: they're large rich-text
            -- fields meant to keep supporting real icon tags.
            -- PE (glance/peek slots) is ALSO excluded here, unlike gradient.lua's color-code
            -- filter: at this point in the pipeline PE is still TRP3's raw serialized wire
            -- format ("|TInterface\Icons\<name>:32:32|t\n#Title\n\nText"), where the |T..|t
            -- tag IS the icon selection, not decoration - it's the only thing TRP3's own
            -- parsePeekString() matches against to read the slot's icon, and stripping it also
            -- eats the trailing newline that separates the tag from the title/text, breaking
            -- their pattern matches too. Net effect: every glance from every other player came
            -- through with a blank/default icon and no title/text - only your own profile
            -- (built locally, never passed through this filter) looked right. Icon fields
            -- within PE are covered independently server-side; nothing needs stripping here.
            local fieldsToStrip = {
                "VA", "NA", "NH", "NI", "NT", "RA", "CU", "FR", "FC", "PX", "RC",
                "CO", "AG", "AE", "HB", "AH", "AW", "MO", "TR", "PN",
                "PH"
            }

            for _, field in pairs(fieldsToStrip) do
                if data[field] and type(data[field]) == "string" then
                    data[field] = TRP3FW:StripAllIcons(data[field])
                end
            end

            -- NA (Name) also gets the bare-path check: unlike DE/HI, a Name field has no
            -- business containing a texture path fragment, lost tag markers or not.
            if data.NA and type(data.NA) == "string" then
                data.NA = TRP3FW:StripBarePathRemnants(data.NA)
            end

            -- IC is a bare icon name, not a |T..|t tag - other addons (e.g. MyRolePlay's
            -- ChatName.lua) wrap it into a texture tag unvalidated, so a malformed name here
            -- surfaces as a raw broken tag prefixed to the sender's name in chat.
            if data.IC and type(data.IC) == "string" then
                data.IC = TRP3FW:SanitizeIconName(data.IC)
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
                    local fieldsToStrip = {
                        "RA", "CL", "FN", "LN", "FT", "TI", "EC", "AG", "HE", "RE", "BP"
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

                    -- FN/LN (Name) also get the bare-path check - see NA handling in the MSP hook above.
                    local nameFields = {"FN", "LN"}
                    for _, field in pairs(nameFields) do
                        if structure[field] and type(structure[field]) == "string" then
                            local stripped = TRP3FW:StripBarePathRemnants(structure[field])
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

                    -- Strip from personality traits (PS)
                    if structure.PS and type(structure.PS) == "table" then
                        for _, trait in pairs(structure.PS) do
                            if trait.RT and type(trait.RT) == "string" then
                                local stripped = TRP3FW:StripAllIcons(trait.RT)
                                if stripped ~= trait.RT then
                                    trait.RT = stripped
                                    wasModified = true
                                end
                            end
                            if trait.LT and type(trait.LT) == "string" then
                                local stripped = TRP3FW:StripAllIcons(trait.LT)
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

        -- Hook misc sanitizer (Peek fields: title/text shown in the glance/peek popup)
        if TRP3_API.register.ui.sanitizeMisc then
            local originalSanitizer = TRP3_API.register.ui.sanitizeMisc

            TRP3_API.register.ui.sanitizeMisc = function(structure)
                local wasModified = false

                if structure then
                    if structure.PE and type(structure.PE) == "table" then
                        for _, peek in pairs(structure.PE) do
                            if type(peek) == "table" then
                                if peek.TI and type(peek.TI) == "string" then
                                    local stripped = TRP3FW:StripAllIcons(peek.TI)
                                    if stripped ~= peek.TI then
                                        peek.TI = stripped
                                        wasModified = true
                                    end
                                end
                                if peek.TX and type(peek.TX) == "string" then
                                    local stripped = TRP3FW:StripAllIcons(peek.TX)
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

        -- NOTE: No hook on TRP3_API.register.ui.sanitizeAbout. Description/History (T1/T2/T3.TX)
        -- are large rich-text fields meant to keep supporting real icon tags, so they're
        -- deliberately left untouched by the icon filter.
    end

    if #hooksApplied > 0 then
        self.iconHookInstalled = true
        self:Info("Icon filter enabled - hooked: " .. table.concat(hooksApplied, ", "))
    end
end