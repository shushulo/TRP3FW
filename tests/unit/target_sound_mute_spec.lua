-- tests/unit/target_sound_mute_spec.lua
-- Headless tests for the target-select sound mute in core/utils.lua.
--
-- The mute is TAINT-SAFE: it does NOT wrap the global PlaySound (that taints
-- Blizzard's secure logout path). It mutes the target-select FILES via
-- MuteSoundFile/UnmuteSoundFile, scoped to automated-targeting windows so manual
-- targeting keeps its sound. These tests assert the mute/unmute toggle only ever
-- touches the configured files and stays in sync.

local T = require("tests.framework")
local H = require("tests.harness")

-- Capture MuteSoundFile / UnmuteSoundFile calls.
local function freshInstall(extraFiles)
    local muted, unmuted = {}, {}
    _G.MuteSoundFile = function(fid) muted[fid] = (muted[fid] or 0) + 1 end
    _G.UnmuteSoundFile = function(fid) unmuted[fid] = (unmuted[fid] or 0) + 1 end

    local fw = H.newNamespace()
    fw.Prefs = { muteTargetSound = true, extraTargetSoundFiles = extraFiles }
    H.loadModule("core/utils.lua", fw)
    fw:InstallTargetSoundMute()
    return fw, muted, unmuted
end

local function count(t)
    local n = 0; for _ in pairs(t) do n = n + 1 end; return n
end

T.describe("Target-select sound mute (MuteSoundFile-based)", function()
    T.it("does NOT replace the global PlaySound (taint-safe)", function()
        local sentinel = function() end
        _G.PlaySound = sentinel
        local fw = freshInstall()
        T.eq(_G.PlaySound, sentinel)  -- untouched
    end)

    T.it("mutes the configured files when turned on", function()
        local fw, muted = freshInstall()
        fw:SetTargetSoundMuted(true)
        T.eq(count(muted), count(fw.targetSoundFiles))
        for fid in pairs(fw.targetSoundFiles) do
            T.eq(muted[fid], 1)
        end
    end)

    T.it("unmutes the same files when turned off", function()
        local fw, _, unmuted = freshInstall()
        fw:SetTargetSoundMuted(true)
        fw:SetTargetSoundMuted(false)
        T.eq(count(unmuted), count(fw.targetSoundFiles))
        for fid in pairs(fw.targetSoundFiles) do
            T.eq(unmuted[fid], 1)
        end
    end)

    T.it("is idempotent: repeated same-state calls do nothing", function()
        local fw, muted = freshInstall()
        fw:SetTargetSoundMuted(true)
        fw:SetTargetSoundMuted(true)   -- no-op
        for fid in pairs(fw.targetSoundFiles) do
            T.eq(muted[fid], 1)        -- muted exactly once, not twice
        end
    end)

    T.it("includes user-added extra files", function()
        local fw, muted = freshInstall({ 999001, 999002 })
        T.truthy(fw.targetSoundFiles[999001])
        T.truthy(fw.targetSoundFiles[999002])
        fw:SetTargetSoundMuted(true)
        T.eq(muted[999001], 1)
        T.eq(muted[999002], 1)
    end)

    T.it("does nothing before install", function()
        _G.MuteSoundFile = function() error("should not be called") end
        _G.UnmuteSoundFile = function() error("should not be called") end
        local fw = H.newNamespace()
        fw.Prefs = { muteTargetSound = true }
        H.loadModule("core/utils.lua", fw)
        -- No InstallTargetSoundMute call.
        local ok = pcall(function() fw:SetTargetSoundMuted(true) end)
        T.truthy(ok)  -- guarded, no MuteSoundFile call
    end)
end)
