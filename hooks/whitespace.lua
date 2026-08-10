-- hooks/whitespace.lua
-- Collapse padded whitespace/newlines in short identity fields of incoming profiles

local addonName, TRP3FW = ...

-- Install whitespace filtering hooks
function TRP3FW:InstallWhitespaceHooks()
    if not TRP3FW.Prefs.filterNameWhitespace then
        return
    end

    -- Idempotency guard: InstallHooks re-runs on /trp3fw reloadhooks. Without this, each
    -- reload inserts another copy into msp.callback.received and re-wraps the TRP3 sanitizers
    -- (nesting our wrapper around itself), leaking hooks and multiplying per-receipt work.
    -- Mirrors the guard icon.lua and fontsize.lua already have.
    if self.whitespaceHookInstalled then
        return
    end

    local hooksApplied = {}

    -- Hook MSP callback to collapse incoming profile data
    if msp and msp.callback then
        table.insert(msp.callback.received, 1, function(senderID)
            local start = debugprofilestop()
            if not msp.char[senderID] or not msp.char[senderID].field then
                local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
                if hs then hs:RecordPerformance(debugprofilestop() - start) end
                return
            end

            local data = msp.char[senderID].field

            -- Short identity fields: name, titles, race/class, nickname/house, pronouns.
            -- These are all single-line by nature, so any newline or space run in them is
            -- padding rather than content.
            --
            -- DE/HI (Description/History) are deliberately excluded: they're large rich-text
            -- fields whose paragraph breaks are legitimate content.
            --
            -- PE (glance/peek slots) is ALSO excluded here, matching icon.lua rather than
            -- gradient.lua: at this point in the pipeline PE is still TRP3's raw serialized
            -- wire format ("|TInterface\\Icons\\<name>:32:32|t\n#Title\n\nText"), where the
            -- newlines are structural separators that parsePeekString() matches against.
            -- Collapsing them would fuse the icon tag, title and text into one line and break
            -- the parse - the same failure the icon filter hit when it stripped PE. Padded
            -- glance titles are handled on the sanitizeMisc hook below, where PE has already
            -- been parsed into per-slot fields and TI is safe to touch.
            local fieldsToCollapse = {
                "NA", "NT", "NH", "NI", "RA", "RC", "PN"
            }

            for _, field in pairs(fieldsToCollapse) do
                if data[field] and type(data[field]) == "string" then
                    data[field] = TRP3FW:CollapseWhitespace(data[field])
                end
            end

            local hs = TRP3FW.ServiceContainer and TRP3FW.ServiceContainer:Get("HistoryService")
            if hs then hs:RecordPerformance(debugprofilestop() - start, "Whitespace Filter (MSP)") end
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
                    -- FN/LN: first/last name. FT/TI: full and short title. CL: class. RA: race.
                    local fieldsToCollapse = {
                        "FN", "LN", "FT", "TI", "CL", "RA"
                    }

                    for _, field in pairs(fieldsToCollapse) do
                        if structure[field] and type(structure[field]) == "string" then
                            local collapsed = TRP3FW:CollapseWhitespace(structure[field])
                            if collapsed ~= structure[field] then
                                structure[field] = collapsed
                                wasModified = true
                            end
                        end
                    end

                    -- Misc traits (MI) carry Nickname, House, Motto and Pronouns in TRP3 -
                    -- they are not flat fields here, only converted to MSP's NI/NH/MO/PN on
                    -- the way out (see hooks/msp_exchange.lua). So covering nicknames and
                    -- pronouns on this path means walking MI, not naming a field.
                    if structure.MI and type(structure.MI) == "table" then
                        for _, trait in pairs(structure.MI) do
                            if type(trait) == "table" then
                                if trait.VA and type(trait.VA) == "string" then
                                    local collapsed = TRP3FW:CollapseWhitespace(trait.VA)
                                    if collapsed ~= trait.VA then
                                        trait.VA = collapsed
                                        wasModified = true
                                    end
                                end
                                if trait.NA and type(trait.NA) == "string" then
                                    local collapsed = TRP3FW:CollapseWhitespace(trait.NA)
                                    if collapsed ~= trait.NA then
                                        trait.NA = collapsed
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
            table.insert(hooksApplied, "TRP3 Characteristics")
        end

        -- Hook misc sanitizer (Peek fields: title shown in the glance/peek popup)
        if TRP3_API.register.ui.sanitizeMisc then
            local originalSanitizer = TRP3_API.register.ui.sanitizeMisc

            TRP3_API.register.ui.sanitizeMisc = function(structure)
                local wasModified = false

                if structure then
                    if structure.PE and type(structure.PE) == "table" then
                        for _, peek in pairs(structure.PE) do
                            if type(peek) == "table" then
                                -- TI (glance title) only. TX is the glance body - free text
                                -- where deliberate line breaks are legitimate content, so it
                                -- gets the same carve-out as DE/HI.
                                if peek.TI and type(peek.TI) == "string" then
                                    local collapsed = TRP3FW:CollapseWhitespace(peek.TI)
                                    if collapsed ~= peek.TI then
                                        peek.TI = collapsed
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

        -- NOTE: No hook on TRP3_API.dashboard.sanitizeCharacter. CU/CO (Currently/OOC) are
        -- free-text status fields where multi-line content is normal and expected.
    end

    if #hooksApplied > 0 then
        self.whitespaceHookInstalled = true
        self:Info("Whitespace filter enabled - hooked: " .. table.concat(hooksApplied, ", "))
    end
end
