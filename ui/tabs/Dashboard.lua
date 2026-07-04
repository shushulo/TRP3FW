-- ui/tabs/Dashboard.lua
-- Landing page for the redesigned settings shell: at-a-glance session stats,
-- detected environment, and cache hit rates -- built from the skinned widget
-- kit. Reads the same TRP3FW.sessionStats / detectedAddons the Status tab uses,
-- but presented as a compact dashboard rather than the dense diagnostic grid.

local addonName, TRP3FW = ...
local TabManager = TRP3FW.TabManager

-- Environment badge: a bordered pill chip. Present = green fill/border/text,
-- absent = muted slate. Sized to its label. Exposes :SetPresent(bool).
local function envBadge(parent, label)
    local Theme = TRP3FW.Theme
    local badge = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    badge:SetBackdrop(Theme.BACKDROP_CHIP)
    badge:SetHeight(20)

    local fs = badge:CreateFontString(nil, "OVERLAY", Theme.fonts.SUB)
    fs:SetPoint("CENTER")
    fs:SetText(label)
    badge.label = fs
    badge:SetWidth(fs:GetStringWidth() + 20)

    function badge:SetPresent(present)
        if present then
            self:SetBackdropColor(0.09, 0.16, 0.09, 1)          -- deep green tint
            self:SetBackdropBorderColor(0.28, 0.47, 0.28, 1)    -- green border
            fs:SetTextColor(Theme:Color("SUCCESS_T"))
        else
            self:SetBackdropColor(Theme:Color("INSET"))
            self:SetBackdropBorderColor(Theme:Color("BORDER"))
            fs:SetTextColor(Theme:Color("TEXT_MUTED"))
        end
    end
    badge:SetPresent(false)
    return badge
end

-- Small stat tile: caption + big colored number. Returns the tile (with .value).
local function statTile(parent, caption)
    local Theme = TRP3FW.Theme
    local tile = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    tile:SetBackdrop(Theme.BACKDROP_CHIP)
    tile:SetBackdropColor(Theme:Color("CARD"))
    tile:SetBackdropBorderColor(Theme:Color("BORDER"))

    -- Centered layout: caption centered near the top, big value centered below.
    local cap = tile:CreateFontString(nil, "OVERLAY", Theme.fonts.SUB)
    cap:SetPoint("TOP", 0, -8)
    cap:SetText(caption:upper())
    cap:SetTextColor(Theme:Color("TEXT_MUTED"))

    local val = tile:CreateFontString(nil, "OVERLAY", Theme.fonts.VALUE)
    val:SetPoint("TOP", cap, "BOTTOM", 0, -2)
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
    lbl:SetWidth(116); lbl:SetJustifyH("LEFT")
    lbl:SetText(label)
    lbl:SetTextColor(Theme:Color("TEXT_SECONDARY"))

    -- Readout inset from the row's right edge so "100%" doesn't touch the card.
    local pct = row:CreateFontString(nil, "ARTWORK", Theme.fonts.SUB)
    pct:SetPoint("RIGHT", -6, 0)
    pct:SetWidth(54); pct:SetJustifyH("RIGHT")
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
        if total == 0 then
            -- No data yet: hide the fill so an empty bar isn't a misleading red 0%.
            self.fill:SetWidth(1)
            self.fill:SetColorTexture(Theme:Color("TRACK"))
            self.pct:SetText("--")
            return
        end
        local w = self.track:GetWidth()
        if w and w > 0 then self.fill:SetWidth(math.max(1, w * rate / 100)) end
        -- Health color: <33% red, 33-66% yellow, >=66% green.
        local colorKey
        if rate >= 66 then colorKey = "SUCCESS"
        elseif rate >= 33 then colorKey = "WARN"
        else colorKey = "DANGER" end
        self.fill:SetColorTexture(Theme:Color(colorKey))
        self.pct:SetText(string.format("%.0f%%", rate))
    end
    return row
end

local dashWidgets = {}

local function CreateDashboardTab(container)
    local Theme = TRP3FW.Theme
    local tab = CreateFrame("Frame", nil, container)
    tab:SetAllPoints()

    local scrollFrame, content = TabManager:CreateScrollFrame(tab, 540)
    local W = 540

    -- ---- Stat tiles (3 across) --------------------------------------------
    local tileW, tileH, gap = (W - 24) / 3, 50, 8
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

    -- ---- Environment card (pill badges) -----------------------------------
    local envCard = TabManager:CreateCard(content, "Environment", W)
    envCard:SetPoint("TOPLEFT", alertsTile, "BOTTOMLEFT", 0, -10)
    envCard:SetWidth(W)
    local badgeY = envCard:NextY(26)
    local badgeSpecs = { "TRP3", "MRP", "XRP", "MSP", "Epsilon API" }
    local BADGE_GAP = 8
    dashWidgets.env = {}
    -- Create first, then center the whole row within the card.
    local made, total = {}, 0
    for _, name in ipairs(badgeSpecs) do
        local badge = envBadge(envCard, name)
        dashWidgets.env[name] = badge
        made[#made + 1] = badge
        total = total + badge:GetWidth() + BADGE_GAP
    end
    total = total - BADGE_GAP
    local bx = math.floor((W - total) / 2)
    for _, badge in ipairs(made) do
        badge:SetPoint("TOPLEFT", bx, badgeY)
        bx = bx + badge:GetWidth() + BADGE_GAP
    end
    envCard:FitHeight(8)

    -- ---- Cache hit-rate card ----------------------------------------------
    local cacheCard = TabManager:CreateCard(content, "Cache hit rate", W)
    cacheCard:SetPoint("TOPLEFT", envCard, "BOTTOMLEFT", 0, -10)
    cacheCard:SetWidth(W)

    local barSpecs = {
        "Interaction", "Phase check", "WHO query", "Allowed senders",
        "Map scan", "Broadcast", "SPVP salt", "SPVP verified",
    }
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
        outcome:SetPoint("TOPRIGHT", recentCard, "TOPRIGHT", -24, rowY)
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

    -- Environment badges (green pill = present, muted = absent).
    if dashWidgets.env then
        local d = TRP3FW.detectedAddons or {}
        local present = {
            TRP3 = d.TRP3, MRP = d.MRP, XRP = d.XRP, MSP = d.MSP,
            ["Epsilon API"] = TRP3FW.hasEpsilonAPI,
        }
        for name, badge in pairs(dashWidgets.env) do
            badge:SetPresent(present[name] and true or false)
        end
    end

    -- Cache hit-rate bars. Mirrors the 8 bars the Status tab tracks. Note SPVP
    -- salt lives at sessionStats.spvpCache.hits/misses, not cacheStats.*.
    local cs = s and s.cacheStats
    if cs and dashWidgets.bars then
        local spvpSalt = s.spvpCache or {}
        local map = {
            ["Interaction"]     = { cs.interactionCacheHits, cs.interactionCacheMisses },
            ["Phase check"]     = { cs.phaseCacheHits, cs.phaseCacheMisses },
            ["WHO query"]       = { cs.whoCacheHits, cs.whoCacheMisses },
            ["Allowed senders"] = { cs.allowedSendersCacheHits, cs.allowedSendersCacheMisses },
            ["Map scan"]        = { cs.mapCacheHits, cs.mapCacheMisses },
            ["Broadcast"]       = { cs.broadcastCacheHits, cs.broadcastCacheMisses },
            ["SPVP salt"]       = { spvpSalt.hits, spvpSalt.misses },
            ["SPVP verified"]   = { cs.spvpVerifiedCacheHits, cs.spvpVerifiedCacheMisses },
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
