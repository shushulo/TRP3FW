-- core/feature_flags.lua
-- Feature flag system for gradual refactoring rollout
-- Allows instant rollback without git reset

local addonName, TRP3FW = ...

-- ===================== Feature Flag Registry =====================

TRP3FW.FeatureFlags = {
    -- Debug: Extra logging during refactoring (the only flag still consumed;
    -- the Phase 2/4 rollout flags were removed once those refactors landed).
    enableRefactorLogging = false,
}

-- ===================== Feature Flag API =====================

function TRP3FW:IsFeatureEnabled(flagName)
    if self.FeatureFlags[flagName] == nil then
        return false
    end
    return self.FeatureFlags[flagName]
end

function TRP3FW:EnableFeature(flagName)
    if self.FeatureFlags[flagName] == nil then
        self:Error("[FeatureFlags] Unknown feature flag: "..tostring(flagName))
        return false
    end

    self.FeatureFlags[flagName] = true
    self:Info("[FeatureFlags] Enabled: "..flagName)
    return true
end

function TRP3FW:DisableFeature(flagName)
    if self.FeatureFlags[flagName] == nil then
        self:Error("[FeatureFlags] Unknown feature flag: "..tostring(flagName))
        return false
    end

    self.FeatureFlags[flagName] = false
    self:Info("[FeatureFlags] Disabled: "..flagName)
    return true
end

function TRP3FW:ToggleFeature(flagName)
    if self:IsFeatureEnabled(flagName) then
        return self:DisableFeature(flagName)
    else
        return self:EnableFeature(flagName)
    end
end

function TRP3FW:ShowFeatureFlags()
    self:Info("=== TRP3FW Feature Flags ===")
    local flags = {}
    for flag, _ in pairs(self.FeatureFlags) do
        table.insert(flags, flag)
    end
    table.sort(flags)

    for _, flag in ipairs(flags) do
        local enabled = self.FeatureFlags[flag]
        local status = enabled and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"
        self:Info(string.format("  %-40s: %s", flag, status))
    end
end

function TRP3FW:EnableAllFeatures()
    for flag, _ in pairs(self.FeatureFlags) do
        self.FeatureFlags[flag] = true
    end
    self:Info("[FeatureFlags] All features enabled")
end

function TRP3FW:DisableAllFeatures()
    for flag, _ in pairs(self.FeatureFlags) do
        self.FeatureFlags[flag] = false
    end
    self:Info("[FeatureFlags] All features disabled")
end

-- ===================== Slash Commands =====================

SlashCmdList.TRP3FWFLAGS = function(msg)
    local args = {strsplit(" ", msg)}
    local command = string.lower(args[1] or "")

    if command == "" or command == "list" then
        TRP3FW:ShowFeatureFlags()

    elseif command == "enable" then
        local flag = args[2]
        if flag then
            TRP3FW:EnableFeature(flag)
        else
            print("Usage: /trp3fwflags enable <flag_name>")
        end

    elseif command == "disable" then
        local flag = args[2]
        if flag then
            TRP3FW:DisableFeature(flag)
        else
            print("Usage: /trp3fwflags disable <flag_name>")
        end

    elseif command == "toggle" then
        local flag = args[2]
        if flag then
            TRP3FW:ToggleFeature(flag)
        else
            print("Usage: /trp3fwflags toggle <flag_name>")
        end

    elseif command == "enableall" then
        TRP3FW:EnableAllFeatures()

    elseif command == "disableall" then
        TRP3FW:DisableAllFeatures()

    elseif command == "help" then
        print("TRP3FW Feature Flags")
        print("Usage: /trp3fwflags [command] [args]")
        print("Commands:")
        print("  list                  - Show all flags and their states")
        print("  enable <flag>         - Enable a specific flag")
        print("  disable <flag>        - Disable a specific flag")
        print("  toggle <flag>         - Toggle a specific flag")
        print("  enableall             - Enable all flags")
        print("  disableall            - Disable all flags")
        print("  help                  - Show this help")

    else
        print("Unknown command: "..command)
        print("Use /trp3fwflags help for usage")
    end
end

SLASH_TRP3FWFLAGS1 = "/trp3fwflags"

TRP3FW:Debug("Feature Flags loaded. Use /trp3fwflags for commands", "init")
