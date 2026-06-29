-- hooks/installer.lua
-- Coordinates installation of all hooks

local addonName, TRP3FW = ...

local function GetFunctionSource(fn)
    if type(fn) ~= "function" then return nil end
    local info = debug and debug.getinfo and debug.getinfo(fn, "S")
    return info and (info.short_src or info.source)
end

-- Generic hook conflict detector
-- Returns {ok=bool, action="chain"|"refuse"|"skip", reason, found}
function TRP3FW:CheckHookConflict(hookName, current, cachedOriginal, ourWrapper)
    local status = {ok = true, action = "chain", found = current}

    if type(current) ~= "function" then
        status.ok = false
        status.action = "refuse"
        status.reason = "target_not_callable"
    elseif cachedOriginal and current ~= cachedOriginal and current ~= ourWrapper then
        status.ok = not TRP3FW.Prefs.strictHookMode
        status.action = TRP3FW.Prefs.strictHookMode and "refuse" or "chain"
        status.reason = "conflict_existing_hook"
    elseif not cachedOriginal and ourWrapper and current == ourWrapper then
        status.ok = false
        status.action = "skip"
        status.reason = "already_wrapped"
    end

    self.hookConflicts = self.hookConflicts or {}
    if status.reason then
        self.hookConflicts[hookName] = {
            reason = status.reason,
            source = GetFunctionSource(current),
            action = status.action,
        }
    end

    if TRP3FW.Prefs.logHookConflicts and status.reason then
        self:Warn(string.format("[Hook %s] conflict (%s) action=%s source=%s", hookName, status.reason, status.action, tostring(status.source)))
    end

    return status
end

-- Install all addon hooks
function TRP3FW:InstallHooks()
    if self.hookInstalled then return end

    self.hookStatus = self.hookStatus or {}
    self.hookConflicts = self.hookConflicts or {}
    self.disabledReason = nil
    self.mapScanDisabledReason = nil

    -- Detect available addons
    if TRP3_API then self.detectedAddons.TRP3 = true end
    if mrp then self.detectedAddons.MRP = true end
    if xrp then self.detectedAddons.XRP = true end

    -- Try to get LibMSP via LibStub if available
    if not msp and LibStub then
        local success, lib = pcall(LibStub, "LibMSP")
        if success and lib then
            msp = lib
        end
    end
    if msp then self.detectedAddons.MSP = true end

    -- Detect map scanning capability
    local hasMapScanner = false
    if TRP3_API and TRP3_API.MapScannersManager then
        hasMapScanner = true
        self.detectedAddons.MapScanner = "TRP3"
    elseif RPMapScan then
        hasMapScanner = true
        self.detectedAddons.MapScanner = "RPMapScan"
    end

    -- Abort if multiple RP addons detected (incompatibility)
    local rpCount = (self.detectedAddons.TRP3 and 1 or 0) + (self.detectedAddons.MRP and 1 or 0) + (self.detectedAddons.XRP and 1 or 0)
    if rpCount > 1 and TRP3FW.Prefs.abortOnMultipleRPAddons then
        self.disabledReason = "multiple_rp_addons"
        self:Warn("TRP3FW disabled: multiple RP addons detected (TRP3/MRP/XRP are incompatible together)")
        self:Info("Detected: TRP3="..tostring(self.detectedAddons.TRP3).." MRP="..tostring(self.detectedAddons.MRP).." XRP="..tostring(self.detectedAddons.XRP))
        self.monitorTRP3 = false
        self.monitorMRP = false
        self.monitorXRP = false
        return
    end

    -- Check if map scanning is needed but unavailable
    local needsMapScanner = (not self.detectedAddons.TRP3) and (self.detectedAddons.MRP or self.detectedAddons.XRP)
    if needsMapScanner and not hasMapScanner then
        self:Warn("Map scanning unavailable: MRP/XRP detected but no map scanner found")
        self:Warn("Install RPMapScan or TotalRP3 to enable map-based location checks")
    end

    -- RPMapScan incompatible with TRP3 map scanner usage
    if self.detectedAddons.TRP3 and self.detectedAddons.MapScanner == "RPMapScan" and TRP3FW.Prefs.disableMapScanOnTRP3 then
        self.mapScanDisabledReason = "trp3_with_rpmapscan"
        self:Warn("Map scanning disabled: TRP3 + RPMapScan detected (incompatible combo)")
    end

    self:Debug("Detected addons: TRP3="..(self.detectedAddons.TRP3 and "yes" or "no")..", MRP="..(self.detectedAddons.MRP and "yes" or "no")..", XRP="..(self.detectedAddons.XRP and "yes" or "no")..", MSP="..(self.detectedAddons.MSP and "yes" or "no")..", MapScanner="..(self.detectedAddons.MapScanner or "none"), "hooks")

    -- Debug: Check what TRP3 APIs are available
    if TRP3_API then
        self:Debug("TRP3_API exists", "hooks")
        self:Debug("  TRP3_API.Ellyb: "..(TRP3_API.Ellyb and "yes" or "no"), "hooks")
        if TRP3_API.Ellyb then
            self:Debug("  TRP3_API.Ellyb.AddonCommunication: "..(TRP3_API.Ellyb.AddonCommunication and "yes" or "no"), "hooks")
        end
    end
    self:Debug("AddOn_Chomp: "..(AddOn_Chomp and "yes" or "no"), "hooks")

    -- Install individual hook modules
    self:InstallSendQueryHook()      -- Track user-initiated TRP3 profile requests
    self:InstallMSPRequestHook()     -- Track user-initiated MSP/MRP/XRP profile requests
    self:InstallChompHook()          -- Location gating for TRP3/MSP sends
    -- self:InstallTRP3Hooks()       -- DEPRECATED: Removed (targeted non-existent API)
    self:InstallSendObjectHook()     -- TRP3 sendObject hook (pre-serialization ghost mode)
    -- self:InstallTRP3ExchangeHooks() -- DEPRECATED: Removed (redundant with SendObject hook)
    self:InstallMSPExchangeHooks()   -- LibMSP field exchange hooks (for ghost mode)
    self:InstallMSPHooks()
    self:InstallGradientHooks()
    self:InstallIconHooks()
    self:InstallFontSizeHooks()      -- Font size injection hooks
    if not self.mapScanDisabledReason then
        self:InstallTRP3ScanNotification()  -- TRP3 scan response notifications
    else
        self:Debug("Skipped TRP3 scan notification install (map scan disabled)", "hooks")
    end

    self.hookInstalled = true
    self:Info("TRP3 Firewall v"..self.VERSION.." loaded"..(self.hasEpsilonAPI and " |cff00ff00(Epsilon API available)|r" or ""))
    self:Info("Monitoring: "..self:GetDetectedAddonsString())
end
