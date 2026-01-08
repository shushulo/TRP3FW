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
        -- Initialize settings
        TRP3FW:InitializeSettings()
        if TRP3FW.ValidateSettings then
            TRP3FW:ValidateSettings()
        end
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        -- Initialize WHO suppression
        TRP3FW:InitializeWhoSuppression()

        -- Initialize cache cleanup
        -- TRP3FW:InitializeCacheCleanup() -- Moved to CacheService

        -- Initialize zone cache clearing
        -- TRP3FW:InitializeZoneCacheClearing() -- Moved to CacheService

        -- Initialize Services
        TRP3FW.ServiceContainer:InitializeAll()

        -- Initialize Pipeline
        TRP3FW:InitializeDecisionPipeline()

        -- PERFORMANCE FIX: Defer interaction tracking to avoid load screen freeze
        -- In high-density areas (100+ players), synchronous events during login can cause blocking
        -- Delay by 5 seconds to let initial load complete
        C_Timer.After(5, function()
            -- Initialize interaction tracking (mouseover and target)
            -- TRP3FW:InitializeInteractionTracking() -- Moved to CacheService
            
            TRP3FW:Debug("[Init] Interaction tracking initialized (deferred to avoid login freeze)", "init")
        end)

        -- Install hooks (delay to ensure other addons are loaded)
        C_Timer.After(1, function()
            TRP3FW:InstallHooks()
            -- After hooks are installed, handle dependency-based settings
            TRP3FW:HandleDependencySettings()

            -- Validate/create blank profiles if ANY ghost mode setting is enabled
            C_Timer.After(1, function()
                local ghostModeEnabled = TRP3FW:IsGhostModeEnabled()

                if ghostModeEnabled then
                    -- TRP3
                    if TRP3_API and TRP3_Profiles then
                        TRP3FW:CreateBlankProfile_TRP3()
                    end

                    -- MRP
                    if mrp and mrpSaved then
                        TRP3FW:CreateBlankProfile_MRP()
                    end

                    -- XRP
                    if AddOn_XRP and xrpSaved then
                        TRP3FW:CreateBlankProfile_XRP()
                    end

                    TRP3FW:Debug("[Profile Switch] Validated/created blank profiles on addon load", "hooks")
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

        -- Show welcome message for first-time users (3 second delay to avoid login spam)
        C_Timer.After(3, function()
            TRP3FW:ShowWelcomeMessage()
            if TRP3FW.ShowWelcomeWizard then
                TRP3FW:ShowWelcomeWizard()
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

        if TRP3FW.pendingPhaseInRequests then
            TRP3FW.pendingPhaseInRequests = {}
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
