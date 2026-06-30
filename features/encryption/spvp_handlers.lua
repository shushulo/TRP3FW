-- ===================================================================
-- TRP3 Firewall - SPVP Packet Handlers
-- ===================================================================
-- Registers addon message prefix and handles INIT/REPLY packets
-- ===================================================================

local addonName, TRP3FW = ...

-- Register SPVP addon prefix
C_ChatInfo.RegisterAddonMessagePrefix("TRP3FW_SPVP")

TRP3FW:Debug("SPVP addon prefix registered: TRP3FW_SPVP", "spvp")

-- Packet handler frame
local spvpFrame = CreateFrame("Frame")
spvpFrame:RegisterEvent("CHAT_MSG_ADDON")

spvpFrame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
    if event ~= "CHAT_MSG_ADDON" then return end

    -- Check for async salt response (Epsilon API)
    if TRP3FW.pendingSaltTickets and TRP3FW.pendingSaltTickets[prefix] then
        TRP3FW:HandleSaltResponse(prefix, message)
        return
    end

    if prefix ~= "TRP3FW_SPVP" then return end

    -- This is our network attack surface: messages arrive from arbitrary players.
    -- CHAT_MSG_ADDON can deliver a nil/empty body, and CleanPlayerName can reject a
    -- malformed sender. Guard both before any :match/concatenation to avoid a nil-index
    -- crash in the OnEvent handler.
    if type(message) ~= "string" or message == "" then return end

    -- Clean sender name
    local cleanSender = TRP3FW:CleanPlayerName(sender)
    if not cleanSender then
        TRP3FW:Debug("[SPVP] Dropping packet from unparseable sender: "..tostring(sender), "spvp")
        return
    end

    -- Determine packet type
    if message:match("^INIT:") then
        -- INIT packet (we are Bob, the prover)
        TRP3FW:HandleSPVPInit(message, cleanSender)
    elseif message:match("^REPLY:") then
        -- REPLY packet (we are Alice, the verifier)
        TRP3FW:HandleSPVPReply(message, cleanSender)
    elseif message:match("^CONFIRM:") then
        -- CONFIRM packet (we are Bob, receiving proof from Alice)
        TRP3FW:HandleSPVPConfirm(message, cleanSender)
    elseif message:match("^NOSALT:") then
        -- NOSALT packet (Peer has no salt)
        TRP3FW:HandleSPVPNosalt(message, cleanSender)
    else
        TRP3FW:Debug(string.format("Unknown SPVP packet type from %s: %s", cleanSender, message:sub(1, 50)), "spvp")
    end
end)

TRP3FW:Debug("SPVP packet handlers registered", "core")
