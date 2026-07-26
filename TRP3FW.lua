-- TRP3FW.lua
-- Main initialization and event handling

local addonName, TRP3FW = ...

-- ===================== Initialization =====================

-- Detect Epsilon API
TRP3FW.hasEpsilonAPI = C_Epsilon and C_Epsilon.RunPrivileged and true or false

-- Main event frame
local mainFrame = CreateFrame("Frame")
mainFrame:RegisterEvent("ADDON_LOADED")
mainFrame:RegisterEvent("PLAYER_LOGIN")
mainFrame:RegisterEvent("PLAYER_LOGOUT")  -- FIXED: MEDIUM-6 - Cleanup on logout

mainFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Initialize settings. If this throws, LoadProfile never runs and Prefs
        -- stays aliased to defaultSettings (core/init.lua:243) -- every setting
        -- written that session then mutates the defaults table and any profile
        -- created afterwards is born polluted. Fail loudly rather than limping on
        -- silently, since nothing downstream can tell the difference.
        local ok, err = pcall(function() TRP3FW:InitializeSettings() end)
        if not ok then
            print("|cffff0000TRP3FW Settings Error:|r "..tostring(err))
            print("|cffff0000TRP3FW:|r settings failed to load; run /reload. Do not change settings until you do.")
        end

        if TRP3FW.ValidateSettings then
            ok, err = pcall(function() TRP3FW:ValidateSettings() end)
            if not ok then
                print("|cffff0000TRP3FW Validation Error:|r "..tostring(err))
            end
        end
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        -- Initialize Services (WHO suppression, cache cleanup, and zone-cache
        -- clearing are all set up by their respective services here).
        TRP3FW.ServiceContainer:InitializeAll()

        -- Initialize Pipeline
        TRP3FW:InitializeDecisionPipeline()

        -- Suppress the target-select sound during automated phase-check targeting
        -- (surgical PlaySound hook; only affects our own automated selects).
        TRP3FW:InstallTargetSoundMute()

        -- Install hooks (delay to ensure other addons are loaded).
        -- Each step is isolated: these run inside a C_Timer callback, where an
        -- uncaught error is swallowed by the client after aborting the rest of
        -- the callback. Unisolated, a throw in InstallHooks took
        -- HandleDependencySettings and the blank-profile validation with it --
        -- leaving ghost mode enabled in the settings but with no profile to send.
        C_Timer.After(1, function()
            local ok, err = pcall(function() TRP3FW:InstallHooks() end)
            if not ok then
                print("|cffff0000TRP3FW Hook Error:|r "..tostring(err))
            end

            -- After hooks are installed, handle dependency-based settings
            ok, err = pcall(function() TRP3FW:HandleDependencySettings() end)
            if not ok then
                print("|cffff0000TRP3FW Dependency Error:|r "..tostring(err))
            end

            -- Validate/create blank profiles if ANY ghost mode setting is enabled
            C_Timer.After(1, function()
                local success, perr = pcall(function()
                    if not TRP3FW:IsGhostModeEnabled() then return end

                    -- TRP3
                    if TRP3_API and TRP3_Profiles then
                        TRP3FW:CreateBlankProfile_TRP3()
                    end

                    -- MRP
                    if mrp and mrpSaved then
                        TRP3FW:CreateBlankProfile_MRP()
                    end

                    -- XRP. Guarded on AddOn_XRP/xrpSaved, not the long-gone `xrp`
                    -- global -- see the section-6 adapter finding.
                    if AddOn_XRP and xrpSaved then
                        TRP3FW:CreateBlankProfile_XRP()
                    end

                    TRP3FW:Debug("[Profile Switch] Validated/created blank profiles on addon load", "hooks")
                end)
                if not success then
                    print("|cffff0000TRP3FW Blank Profile Error:|r "..tostring(perr))
                end
            end)
        end)

        -- Initialize UI (delay to ensure templates are loaded and dependencies are checked)
        C_Timer.After(2.5, function()
            local success, err = pcall(function()
                TRP3FW:InitializeUI()
            end)
            if not success then
                print("|cffff0000TRP3FW UI Error:|r "..tostring(err))
            end
        end)

        -- Show welcome message for first-time users (3 second delay to avoid login spam).
        -- pcall'd because ShowWelcomeMessage sets hasSeenWelcome before it prints:
        -- a throw part-way through would consume the one-shot flag AND skip the
        -- wizard, so a first-time user would never see either, on any login.
        C_Timer.After(3, function()
            local ok, err = pcall(function()
                TRP3FW:ShowWelcomeMessage()
                if TRP3FW.ShowWelcomeWizard then
                    TRP3FW:ShowWelcomeWizard()
                end
            end)
            if not ok then
                print("|cffff0000TRP3FW Welcome Error:|r "..tostring(err))
            end
        end)

        self:UnregisterEvent("PLAYER_LOGIN")

    elseif event == "PLAYER_LOGOUT" then
        -- FIXED: MEDIUM-6 - Clean up queued requests on logout to prevent memory leaks
        TRP3FW:Debug("[Logout] Cleaning up pending sends and timers", "init")

        -- Clear all pending sends
        if TRP3FW.pendingPhaseInSends then
            TRP3FW.pendingPhaseInSends = {}
        end

        if TRP3FW.pendingTRP3Sends then
            TRP3FW.pendingTRP3Sends = {}
        end

        if TRP3FW.pendingChompSends then
            TRP3FW.pendingChompSends = {}
        end

        -- Cancel any active timers
        if TRP3FW.ghostCleanupTimer then
            TRP3FW.ghostCleanupTimer:Cancel()
            TRP3FW.ghostCleanupTimer = nil
        end

        TRP3FW:Debug("[Logout] Cleanup complete", "init")
    end
end)
