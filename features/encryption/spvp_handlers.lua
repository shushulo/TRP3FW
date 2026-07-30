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

    -- Check for async salt response (Epsilon API).
    --
    -- `prefix` is attacker-chosen: any player can SendAddonMessage with any prefix, and this
    -- handler sees every prefix the client surfaces. Epsilon's salt tickets are short,
    -- mixed-case strings (~15 chars) that were never designed to be unguessable secrets, so
    -- matching on the ticket ALONE let a remote player forge a salt response -- either caching
    -- a salt of their choosing for the phase, or (with a malformed body) negative-caching the
    -- phase for an hour and NOSALT-ing the legitimate peers queued in pendingSPVPInits.
    --
    -- Epsilon delivers the async response server-side. Observed deliveries carry either no
    -- sender at all or our OWN name -- never another player's, which is the one thing an
    -- attacker cannot forge (the client stamps `sender` itself; you cannot send an addon
    -- message that arrives attributed to someone else).
    --
    -- The test is deliberately "not a DIFFERENT player" rather than "no sender": which of the
    -- two server-side forms Epsilon uses is not something we can confirm from the client, and
    -- guessing wrong would silently break all salt loading. Rejecting only third-party senders
    -- closes the forgery path without depending on that detail.
    if TRP3FW.pendingSaltTickets and TRP3FW.pendingSaltTickets[prefix] then
        local isFromOtherPlayer = false
        if type(sender) == "string" and sender ~= "" then
            local cleaned = TRP3FW:CleanPlayerName(sender)
            local me = TRP3FW:CleanPlayerName(UnitName("player"))
            -- An unparseable sender is still a sender: treat it as third-party, not as server.
            isFromOtherPlayer = (cleaned == nil) or (cleaned ~= me)
        end

        if isFromOtherPlayer then
            TRP3FW:Debug("[SPVP] Ignoring salt-ticket-shaped packet from player "
                ..tostring(sender).." (prefix collision or forgery attempt)", "spvp")
            return
        end

        TRP3FW:HandleSaltResponse(prefix, message)
        return
    end

    if prefix ~= "TRP3FW_SPVP" then return end

    -- Feed the entropy pool from packet arrivals. Arrival timing is genuinely unpredictable to
    -- US, and critically it is a source the SENDER cannot fully observe either: they know when
    -- they sent, not the network delay or which frame we processed it on. Stirring here keeps
    -- the pool moving between handshakes rather than only at the moment a peer can bracket.
    -- Cheap (one FNV-1a round per fold) and this handler is already rate-bounded upstream.
    if TRP3FW.SPVP_StirEntropy then
        TRP3FW.SPVP_StirEntropy(message)
        TRP3FW.SPVP_StirEntropy(sender)
    end

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
