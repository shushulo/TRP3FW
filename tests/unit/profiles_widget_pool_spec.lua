-- tests/unit/profiles_widget_pool_spec.lua
-- Headless tests for ui/tabs/Profiles.lua's row widget pool.
--
-- RefreshProfileList used to Hide() the previous buttons, wipe() the list, then create three
-- brand-new CreateButton frames per profile plus the "+ Create new profile" button. WoW frames
-- are never garbage collected, so every profile switch, create, delete and rename permanently
-- added `3 * #profiles + 1` orphaned frames -- and the refresh is also wired to the tab's
-- refresh callback, so it fired on every SwitchToTab("profiles") too. Growth was bounded only
-- by how often the user opened the tab.
--
-- These tests drive the REAL render loop (via the tab's registered refresh callback) and count
-- CreateFrame calls, rather than asserting on source text: the bug was about how many frames
-- exist at runtime, so counting frames is the honest assertion.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshUI(profileNames)
    local fw = H.newNamespace()
    fw.Prefs = { uiComplexityLevel = 3 }
    fw.GlobalDB = { profiles = {}, profileKeys = {} }
    for _, n in ipairs(profileNames or { "Default" }) do
        fw.GlobalDB.profiles[n] = {}
    end
    function fw:GetCharacterKey() return "Tester - Realm" end

    _G.StaticPopupDialogs = _G.StaticPopupDialogs or {}
    _G.StaticPopup_Show = function() end

    H.loadModule("ui/Theme.lua", fw)
    H.loadModule("ui/TabManager.lua", fw)
    H.loadModule("ui/tabs/Profiles.lua", fw)
    return fw
end

-- Build the tab and return its refresh function.
--
-- RefreshProfileList opens with `if not content:IsVisible() then return end`, so every frame
-- in the chain must be shown or the render loop no-ops and any frame-count assertion passes
-- vacuously. Show all frames created during the build.
local function buildTab(fw)
    local tabDef = fw.TabManager.tabs["profiles"]

    -- mock.frames accumulates for the whole run; reset so counts and scans in each test see
    -- only this tab's widgets.
    mock.frames = {}

    local container = CreateFrame("Frame")
    container:Show()

    tabDef.create(container)

    for _, f in ipairs(mock.frames) do f:Show() end

    -- Re-run now that everything is visible: the build-time call bailed on the guard above.
    fw.RefreshProfilesTab()

    return fw.RefreshProfilesTab
end

T.describe("Profiles tab row pool", function()
    T.it("BUG (fixed): repeated refreshes do not create new frames", function()
        local fw = freshUI({ "Default", "Alt", "Raiding" })
        local refresh = buildTab(fw)
        T.not_nil(refresh, "sanity: the tab exposes its refresh function")

        local afterBuild = #mock.frames
        for _ = 1, 10 do refresh() end
        local afterRefreshes = #mock.frames

        T.eq(afterRefreshes, afterBuild,
            "10 refreshes of an unchanged list must reuse the pool, not allocate "
            .. (afterRefreshes - afterBuild) .. " new frames")
    end)

    T.it("grows the pool only when the profile count grows", function()
        local fw = freshUI({ "Default" })
        local refresh = buildTab(fw)

        local oneProfile = #mock.frames

        -- Two more profiles appear: the pool must extend by exactly two rows (3 buttons each).
        fw.GlobalDB.profiles.Alt = {}
        fw.GlobalDB.profiles.Raiding = {}
        refresh()
        local threeProfiles = #mock.frames

        T.eq(threeProfiles - oneProfile, 6,
            "two new rows = 6 buttons; got " .. (threeProfiles - oneProfile))

        -- Refreshing again at the same size allocates nothing further.
        refresh()
        T.eq(#mock.frames, threeProfiles, "no growth at a steady profile count")
    end)

    T.it("shrinking the list reuses the pool rather than allocating", function()
        local fw = freshUI({ "Default", "Alt", "Raiding" })
        local refresh = buildTab(fw)
        local threeProfiles = #mock.frames

        fw.GlobalDB.profiles.Raiding = nil
        fw.GlobalDB.profiles.Alt = nil
        refresh()
        T.eq(#mock.frames, threeProfiles, "shrinking must not allocate")

        -- And growing back reuses the rows that were hidden, not new ones.
        fw.GlobalDB.profiles.Alt = {}
        fw.GlobalDB.profiles.Raiding = {}
        refresh()
        T.eq(#mock.frames, threeProfiles,
            "regrowing to a previously-seen size must reuse the hidden tail")
    end)
end)

T.describe("Profiles tab row state hygiene", function()
    T.it("does not leave a deleted profile's row visible or clickable", function()
        local fw = freshUI({ "Default", "Alt", "Raiding" })
        local refresh = buildTab(fw)

        -- Find the row buttons by their parent card. The pool is a file-local, so reach the
        -- widgets the same way a user would: through the frames that were created.
        fw.GlobalDB.profiles.Raiding = nil
        refresh()

        -- Scan for a HIDDEN button that still carries a profile name. The tail row is hidden
        -- by the refresh; it must also have had its name and handler cleared, or it points at
        -- a profile that no longer exists.
        --
        -- NOTE: read with rawget. The mock's frame metatable returns a no-op FUNCTION for any
        -- unset field, so `f._profileName ~= nil` is true for every frame ever created and
        -- would make this assertion meaningless. rawget sees only what was actually assigned,
        -- which is what "did the refresh clear it?" actually means.
        local offenders, names = 0, {}
        for _, f in ipairs(mock.frames or {}) do
            local stored = rawget(f, "_profileName")
            if stored ~= nil and rawget(f, "shown") == false then
                offenders = offenders + 1
                names[#names + 1] = tostring(stored)
            end
        end
        T.eq(offenders, 0,
            "a hidden row must not retain the profile name it used to represent (found: "
            .. table.concat(names, ", ") .. ")")
    end)

    T.it("survives a refresh with only the Default profile", function()
        local fw = freshUI({ "Default" })
        local refresh = buildTab(fw)
        T.no_raise(function() refresh() end)
    end)
end)
