-- tests/unit/target_sound_mute_spec.lua
-- Headless tests for the target-select sound suppression in core/utils.lua:
--   * InstallTargetSoundMute wraps the global PlaySound and swallows only the
--     target-select sound kits, and only while phase-check targeting is active
--     and the muteTargetSound pref is on. Everything else passes through.
--
-- The installer reads _G.PlaySound and _G.SOUNDKIT at call time, so the spec
-- provides its own stubs before installing.

local T = require("tests.framework")
local H = require("tests.harness")

-- Fake SOUNDKIT: the names the installer looks up plus an unrelated kit.
local FAKE_SOUNDKIT = {
    IG_CREATURE_NEUTRAL_SELECT   = 1001,
    IG_CREATURE_AGGRO_SELECT     = 1002,
    IG_CREATURE_SPECIAL_SELECT   = 1003,
    IG_CHARACTER_NPC_SELECT      = 1004,
    IG_CREATURE_NEUTRAL_LOST     = 1005,
    IG_CREATURE_AGGRO_LOST       = 1006,
    IG_CHARACTER_NPC_LOST        = 1007,
    IG_MAINMENU_OPEN             = 2001,  -- unrelated; must never be swallowed
}
local TARGET_SELECT_KIT = FAKE_SOUNDKIT.IG_CREATURE_NEUTRAL_SELECT
local UNRELATED_KIT      = FAKE_SOUNDKIT.IG_MAINMENU_OPEN

-- Build a fresh namespace + PlaySound spy + installed hook for each scenario so
-- state (flag, pref, install) never leaks between assertions.
local function freshInstall()
    local played = {}
    _G.SOUNDKIT = FAKE_SOUNDKIT
    _G.PlaySound = function(kit) table.insert(played, kit) end

    local fw = H.newNamespace()
    fw.Prefs = {}
    H.loadModule("core/utils.lua", fw)
    fw:InstallTargetSoundMute()
    return fw, played
end

T.describe("InstallTargetSoundMute gating", function()
    T.it("swallows target-select sound when muting during automated targeting", function()
        local fw, played = freshInstall()
        fw.Prefs.muteTargetSound = true
        fw.phaseCheckTargeting = true

        PlaySound(TARGET_SELECT_KIT)
        T.eq(#played, 0)  -- swallowed
    end)

    T.it("plays target-select sound when NOT automated targeting (manual target)", function()
        local fw, played = freshInstall()
        fw.Prefs.muteTargetSound = true
        fw.phaseCheckTargeting = false  -- user clicked a target themselves

        PlaySound(TARGET_SELECT_KIT)
        T.eq(#played, 1)
        T.eq(played[1], TARGET_SELECT_KIT)
    end)

    T.it("plays target-select sound when the mute pref is off", function()
        local fw, played = freshInstall()
        fw.Prefs.muteTargetSound = false
        fw.phaseCheckTargeting = true

        PlaySound(TARGET_SELECT_KIT)
        T.eq(#played, 1)
    end)

    T.it("never swallows unrelated sounds even during automated targeting", function()
        local fw, played = freshInstall()
        fw.Prefs.muteTargetSound = true
        fw.phaseCheckTargeting = true

        PlaySound(UNRELATED_KIT)
        T.eq(#played, 1)
        T.eq(played[1], UNRELATED_KIT)
    end)

    T.it("forwards extra PlaySound arguments to the original", function()
        local seen
        _G.SOUNDKIT = FAKE_SOUNDKIT
        _G.PlaySound = function(kit, channel) seen = { kit, channel } end
        local fw = H.newNamespace()
        fw.Prefs = {}
        H.loadModule("core/utils.lua", fw)
        fw:InstallTargetSoundMute()

        PlaySound(UNRELATED_KIT, "Master")
        T.eq(seen[1], UNRELATED_KIT)
        T.eq(seen[2], "Master")
    end)

    T.it("is idempotent (double install does not double-wrap)", function()
        local fw, played = freshInstall()
        fw:InstallTargetSoundMute()  -- second call is a no-op
        fw.Prefs.muteTargetSound = true
        fw.phaseCheckTargeting = false

        PlaySound(TARGET_SELECT_KIT)
        T.eq(#played, 1)  -- single wrapper, forwards once
    end)
end)
