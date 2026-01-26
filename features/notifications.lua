-- features/notifications.lua
-- DEPRECATED: Logic moved to features/services/NotificationService.lua
-- This file remains for backward compatibility of global function calls.

local addonName, TRP3FW = ...

function TRP3FW:ShowStartPhaseBlockNotification(...)
    local service = TRP3FW.ServiceContainer:Get("NotificationService")
    if service then service:ShowStartPhaseBlockNotification(...) end
end

function TRP3FW:ShowOnScreenNotification(...)
    local service = TRP3FW.ServiceContainer:Get("NotificationService")
    if service then service:ShowOnScreenNotification(...) end
end

function TRP3FW:ShowChatNotification(...)
    local service = TRP3FW.ServiceContainer:Get("NotificationService")
    if service then service:ShowChatNotification(...) end
end

function TRP3FW:PlayNotificationSound()
    local service = TRP3FW.ServiceContainer:Get("NotificationService")
    if service then service:PlayNotificationSound() end
end

function TRP3FW:DebugNotificationSuppression(...)
    local service = TRP3FW.ServiceContainer:Get("NotificationService")
    if service then service:DebugNotificationSuppression(...) end
end

function TRP3FW:RecordHistory(playerName, addon, wasAlert, wasBlocked, wasGhost, alertType)
    local historyService = TRP3FW.ServiceContainer:Get("HistoryService")
    if historyService then
        historyService:RecordHistory(playerName, addon, wasAlert, wasBlocked, wasGhost, alertType)
    end
end
