-- ui/tabs/Dashboard.lua
-- Landing page for the redesigned settings shell: at-a-glance session stats,
-- detected environment, and cache hit rates -- built from the skinned widget
-- kit. Reads the same TRP3FW.sessionStats / detectedAddons the Status tab uses,
-- but presented as a compact dashboard rather than the dense diagnostic grid.

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

-- Small stat tile: caption + big colored number. Returns the tile (with .value).
local function statTile(parent, caption)
    local Theme = TRP3FW.Theme
    local tile = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    tile:SetBackdrop(Theme.BACKDROP_CHIP)
    tile:SetBackdropColor(Theme:Color("CARD"))
    tile:SetBackdropBorderColor(Theme:Color("BORDER"))

    local cap = tile:CreateFontString(nil, "OVERLAY", Theme.fonts.SUB)
    cap:SetPoint("TOPLEFT", 10, -8)
    cap:SetText(caption:upper())
    cap:SetTextColor(Theme:Color("TEXT_MUTED"))

    local val = tile:CreateFontString(nil, "OVERLAY", Theme.fonts.VALUE)
    val:SetPoint("TOPLEFT", 9, -20)
    val:SetText("0")
    tile.value = val
    return tile
end

-- Horizontal hit-rate bar: label + track + gold fill + percent readout.
local function hitBar(parent, label)
    local Theme = TRP3FW.Theme
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(16)

    local lbl = row:CreateFontString(nil, "ARTWORK", Theme.fonts.SUB)
    lbl:SetPoint("LEFT", 0, 0)
    lbl:SetWidth(90); lbl:SetJustifyH("LEFT")
    lbl:SetText(label)
    lbl:SetTextColor(Theme:Color("TEXT_SECONDARY"))

    local pct = row:CreateFontString(nil, "ARTWORK", Theme.fonts.SUB)
    pct:SetPoint("RIGHT", 0, 0)
    pct:SetWidth(70); pct:SetJustifyH("RIGHT")
    pct:SetTextColor(Theme:Color("TEXT_SECONDARY"))
    row.pct = pct

    local track = row:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    track:SetPoint("RIGHT", pct, "LEFT", -8, 0)
    track:SetHeight(6)
    track:SetTexture("Interface\\Buttons\\WHITE8X8")
    track:SetColorTexture(Theme:Color("TRACK"))
    row.track = track

    local fill = row:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetHeight(6)
    fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    fill:SetColorTexture(Theme:Color("GOLD"))
    row.fill = fill

    function row:SetRate(hits, misses)
        local total = (hits or 0) + (misses or 0)
        local rate = total > 0 and ((hits / total) * 100) or 0
        local w = self.track:GetWidth()
        if w and w > 0 then self.fill:SetWidth(math.max(1, w * rate / 100)) end
        if total == 0 then
            self.pct:SetText("--")
        else
            self.pct:SetText(string.format("%.0f%%", rate))
        end
    end
    return row
end

local dashWidgets = {}

local function CreateDashboardTab(container)
    local Theme = TRP3FW.Theme
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()

    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 460)
    local W = 640

    -- ---- Stat tiles (3 across) --------------------------------------------
    local tileW, tileH, gap = (W - 24) / 3, 56, 8
    local alertsTile = statTile(content, "Alerts")
    alertsTile:SetSize(tileW, tileH); alertsTile:SetPoint("TOPLEFT", 12, -10)
    alertsTile.value:SetTextColor(Theme:Color("WARN"))

    local blockedTile = statTile(content, "Blocked")
    blockedTile:SetSize(tileW, tileH); blockedTile:SetPoint("TOPLEFT", alertsTile, "TOPRIGHT", gap, 0)
    blockedTile.value:SetTextColor(Theme:Color("DANGER_T"))

    local ghostTile = statTile(content, "Ghosted")
    ghostTile:SetSize(tileW, tileH); ghostTile:SetPoint("TOPLEFT", blockedTile, "TOPRIGHT", gap, 0)
    ghostTile.value:SetTextColor(Theme:Color("GHOST"))

    dashWidgets.alerts = alertsTile.value
    dashWidgets.blocked = blockedTile.value
    dashWidgets.ghosted = ghostTile.value

    -- ---- Environment card --------------------------------------------------
    local envCard = TabManager:CreateCard(content, "Environment", W)
    envCard:SetPoint("TOPLEFT", alertsTile, "BOTTOMLEFT", 0, -10)
    envCard:SetWidth(W)
    local badges = envCard:CreateFontString(nil, "ARTWORK", Theme.fonts.LABEL)
    badges:SetPoint("TOPLEFT", 12, envCard:NextY(24))
    badges:SetPoint("RIGHT", envCard, "RIGHT", -12, 0)
    badges:SetJustifyH("LEFT")
    badges:SetText("...")
    dashWidgets.env = badges
    envCard:FitHeight(8)

    -- ---- Cache hit-rate card ----------------------------------------------
    local cacheCard = TabManager:CreateCard(content, "Cache hit rate", W)
    cacheCard:SetPoint("TOPLEFT", envCard, "BOTTOMLEFT", 0, -10)
    cacheCard:SetWidth(W)

    local barSpecs = { "Interaction", "Phase check", "WHO query", "Allowed senders" }
    dashWidgets.bars = {}
    for _, name in ipairs(barSpecs) do
        local bar = hitBar(cacheCard, name)
        bar:SetPoint("TOPLEFT", 12, cacheCard:NextY(22))
        bar:SetPoint("RIGHT", cacheCard, "RIGHT", -12, 0)
        dashWidgets.bars[name] = bar
    end
    cacheCard:FitHeight(8)

    -- ---- Recent activity card (fills the lower area with useful data) ------
    local recentCard = TabManager:CreateCard(content, "Recent activity", W)
    recentCard:SetPoint("TOPLEFT", cacheCard, "BOTTOMLEFT", 0, -10)
    recentCard:SetWidth(W)
    dashWidgets.recent = {}
    for i = 1, 6 do
        local rowY = recentCard:NextY(20)
        local time = recentCard:CreateFontString(nil, "ARTWORK", Theme.fonts.SUB)
        time:SetPoint("TOPLEFT", 12, rowY); time:SetWidth(64); time:SetJustifyH("LEFT")
        time:SetTextColor(Theme:Color("TEXT_MUTED"))
        local player = recentCard:CreateFontString(nil, "ARTWORK", Theme.fonts.SUB)
        player:SetPoint("TOPLEFT", 80, rowY); player:SetWidth(300); player:SetJustifyH("LEFT")
        player:SetTextColor(Theme:Color("TEXT_PRIMARY"))
        local outcome = recentCard:CreateFontString(nil, "ARTWORK", Theme.fonts.SUB)
        outcome:SetPoint("TOPRIGHT", recentCard, "TOPRIGHT", -12, rowY)
        outcome:SetWidth(120); outcome:SetJustifyH("RIGHT")
        dashWidgets.recent[i] = { time = time, player = player, outcome = outcome }
    end
    recentCard:FitHeight(8)

    return scrollFrame
end

-- Populate the dashboard from live session stats.
local function RefreshDashboard()
    if not dashWidgets.alerts then return end
    local s = TRP3FW.sessionStats
    if s then
        dashWidgets.alerts:SetText(tostring(s.alerts or 0))
        dashWidgets.blocked:SetText(tostring(s.blocks or 0))
        dashWidgets.ghosted:SetText(tostring(s.ghostSends or 0))
    end

    -- Environment badges (green = present, muted = absent).
    if dashWidgets.env then
        local Theme = TRP3FW.Theme
        local on = "|cff7fc07f%s|r"
        local off = "|cff707790%s|r"
        local d = TRP3FW.detectedAddons or {}
        local parts = {}
        table.insert(parts, string.format(d.TRP3 and on or off, "TRP3"))
        table.insert(parts, string.format(d.MRP and on or off, "MRP"))
        table.insert(parts, string.format(d.XRP and on or off, "XRP"))
        table.insert(parts, string.format(d.MSP and on or off, "MSP"))
        table.insert(parts, string.format(TRP3FW.hasEpsilonAPI and on or off, "Epsilon API"))
        dashWidgets.env:SetText(table.concat(parts, "   "))
    end

    -- Cache hit-rate bars.
    local cs = s and s.cacheStats
    if cs and dashWidgets.bars then
        local map = {
            ["Interaction"]     = { cs.interactionCacheHits, cs.interactionCacheMisses },
            ["Phase check"]     = { cs.phaseCacheHits, cs.phaseCacheMisses },
            ["WHO query"]       = { cs.whoCacheHits, cs.whoCacheMisses },
            ["Allowed senders"] = { cs.allowedSendersCacheHits, cs.allowedSendersCacheMisses },
        }
        for name, bar in pairs(dashWidgets.bars) do
            local v = map[name]
            if v then bar:SetRate(v[1] or 0, v[2] or 0) end
        end
    end

    -- Recent activity: newest entries from the notification history.
    if dashWidgets.recent then
        local function outcome(e)
            if e.wasGhost then return "|cff79b0ddGhosted|r"
            elseif e.wasBlocked then return "|cffd76b5eBlocked|r"
            elseif e.wasAlert then return "|cffc99a44Alert|r"
            else return "|cff7fc07fAllowed|r" end
        end
        local history = TRP3FW.notificationHistory or {}
        local n = #history
        for i, row in ipairs(dashWidgets.recent) do
            local e = history[n - i + 1]  -- newest first
            if e then
                row.time:SetText(e.timestamp and date("%H:%M:%S", e.timestamp) or "--")
                row.player:SetText(e.player or "Unknown")
                row.outcome:SetText(outcome(e))
            else
                row.time:SetText(""); row.outcome:SetText("")
                row.player:SetText(i == 1 and "|cff555555No recent activity|r" or "")
            end
        end
    end
end
TRP3FW.RefreshDashboard = RefreshDashboard

TabManager:RegisterTab("dashboard", "Dashboard", "Dashboard", CreateDashboardTab, RefreshDashboard,
    "Interface\\Icons\\INV_Misc_Spyglass_03")
