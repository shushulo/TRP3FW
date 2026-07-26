-- tests/unit/commands_spec.lua
-- Section 9 (root / entry points) regressions, all in commands.lua.
--
-- Four defects, three of them hard errors on a command the help text advertises:
--
--  1. `args` was read as a global by the batch/priority/refund handlers. The
--     three `local args = {}` declarations in the same function are each scoped
--     to their own elseif block, so those reads resolved to nil and every one of
--     those subcommands died on its first line ("attempt to index global 'args'").
--  2. The `batch interdelay` branch called `self:Info(...)` inside a plain
--     function, where `self` is nil -- the same crash by a different name.
--  3. `/trp3fw reset` assigned `TRP3FW.Prefs = {}` and then called
--     InitializeSettings, whose LoadProfile immediately repoints Prefs at the
--     still-populated saved profile. The throwaway table was the only thing
--     cleared, so "reset all settings to defaults" reset nothing.
--  4. `debugfilter` had no branch for the `ghost` and `spvp` categories, both of
--     which are real entries in core/utils.lua's DEBUG_CATEGORIES with their own
--     settings and UI checkboxes.
--
-- These drive the real SlashCmdList.TRP3FW handler rather than asserting on
-- source text: the bugs are runtime failures, so a runtime test is the honest
-- assertion. Only the fourth is checked structurally as well, since "the branch
-- exists" is a statement about the dispatch table.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

-- Build a namespace with the surface commands.lua touches, then load the file so
-- it registers its handler into the mocked SlashCmdList.
local function newEnv()
    local TRP3FW = H.newNamespace()

    TRP3FW.hasEpsilonAPI = false
    TRP3FW.detectedAddons = {}
    TRP3FW.profiler = {
        enabled = false,
        stats = {},
        toggle = function() end,
        report = function() end,
        reset = function() end,
    }

    -- Capture user-visible output so tests can assert on what was said.
    TRP3FW.output = {}
    local function record(_, msg) table.insert(TRP3FW.output, tostring(msg)) end
    TRP3FW.Info    = record
    TRP3FW.Warn    = record
    TRP3FW.Error   = record
    TRP3FW.Success = record

    function TRP3FW:IsPhaseCheckEnabled() return self.Prefs.phaseCheckMode ~= "off" end
    function TRP3FW:GetDetectedAddonsString() return "none" end
    function TRP3FW:ShowHelp() end
    function TRP3FW:ShowStatus() end
    function TRP3FW:ShowStats() end

    _G.SlashCmdList = {}
    H.loadModule("commands.lua", TRP3FW)

    return TRP3FW, _G.SlashCmdList.TRP3FW
end

-- Did any recorded line contain this substring?
local function said(TRP3FW, needle)
    for _, line in ipairs(TRP3FW.output) do
        if line:find(needle, 1, true) then return true end
    end
    return false
end

T.describe("commands.lua registers its slash handler", function()
    T.it("assigns SlashCmdList.TRP3FW as a function", function()
        local _, handler = newEnv()
        T.eq(type(handler), "function", "the whole command surface hangs off this")
    end)

    T.it("does not error on a nil msg", function()
        local _, handler = newEnv()
        T.no_raise(function() handler(nil) end,
            "WoW can hand a slash handler nil; msg:match would be a hard error")
    end)
end)

T.describe("subcommands that read args[] do not crash", function()
    -- Each of these reached `args[1]` or `args[2]` through a nil global before
    -- the fix. They are the three command families that took the bug.
    local cases = {
        "batch",
        "batch status",
        "batch size",
        "batch size 6",
        "batch delay",
        "batch delay 1.5",
        "batch min",
        "batch min 4",
        "batch interdelay",
        "batch interdelay 50",
        "batch enable",
        "batch disable",
        "priority",
        "priority status",
        "priority reserved",
        "priority reserved 3",
        "priority low",
        "priority low 5",
        "refund",
        "refund status",
        "refund enable",
        "refund disable",
    }

    for _, cmd in ipairs(cases) do
        T.it("/trp3fw " .. cmd, function()
            local _, handler = newEnv()
            T.no_raise(function() handler(cmd) end,
                "'" .. cmd .. "' indexed a nil global before the fix")
        end)
    end
end)

T.describe("batch subcommands apply their values", function()
    T.it("batch size 6 writes phaseCheckBatchSize", function()
        local TRP3FW, handler = newEnv()
        handler("batch size 6")
        T.eq(TRP3FW.Prefs.phaseCheckBatchSize, 6)
    end)

    T.it("batch size clamps to the documented 2-10 range", function()
        local TRP3FW, handler = newEnv()
        handler("batch size 99")
        T.eq(TRP3FW.Prefs.phaseCheckBatchSize, 10)
        handler("batch size 1")
        T.eq(TRP3FW.Prefs.phaseCheckBatchSize, 2)
    end)

    T.it("batch interdelay converts milliseconds to seconds", function()
        local TRP3FW, handler = newEnv()
        handler("batch interdelay 50")
        T.eq(TRP3FW.Prefs.phaseCheckInterTargetDelay, 0.05,
            "the command takes ms and the setting stores seconds")
    end)

    T.it("batch interdelay with no value reports rather than crashing", function()
        local TRP3FW, handler = newEnv()
        TRP3FW.Prefs.phaseCheckInterTargetDelay = 0.1
        handler("batch interdelay")
        T.truthy(said(TRP3FW, "Current inter-target delay"),
            "this branch used `self:Info`, where self is nil")
    end)

    T.it("priority reserved 3 writes privilegedReservedTokens", function()
        local TRP3FW, handler = newEnv()
        handler("priority reserved 3")
        T.eq(TRP3FW.Prefs.privilegedReservedTokens, 3)
    end)

    T.it("refund enable writes phaseCheckRefundOnNoChange", function()
        local TRP3FW, handler = newEnv()
        handler("refund enable")
        T.eq(TRP3FW.Prefs.phaseCheckRefundOnNoChange, true)
    end)
end)

T.describe("commands that already had their own args list still work", function()
    -- `cache`, `clearcache` and `dumpcache` each built a local `args` that
    -- shadowed nothing (there was no outer one). Removing those locals in favour
    -- of the shared list must not change their behaviour.
    T.it("cache phase 300 sets phaseCacheDuration", function()
        local TRP3FW, handler = newEnv()
        handler("cache phase 300")
        T.eq(TRP3FW.Prefs.phaseCacheDuration, 300)
    end)

    T.it("cache rejects an out-of-range duration", function()
        local TRP3FW, handler = newEnv()
        TRP3FW.Prefs.phaseCacheDuration = 111
        handler("cache phase 99999")
        T.eq(TRP3FW.Prefs.phaseCacheDuration, 111, "3600 is the documented ceiling")
    end)

    T.it("clearcache with no argument reports status", function()
        local TRP3FW, handler = newEnv()
        T.no_raise(function() handler("clearcache") end)
        T.truthy(said(TRP3FW, "Cache clearing settings"))
    end)

    T.it("clearcache phase interaction on sets the granular flag", function()
        local TRP3FW, handler = newEnv()
        handler("clearcache phase interaction on")
        T.eq(TRP3FW.Prefs.clearInteractionOnPhaseChange, true)
    end)
end)

T.describe("/trp3fw reset actually clears the active profile", function()
    -- The bug: Prefs is an alias of TRP3FW_DB.profiles[name]. Rebinding the
    -- alias to {} leaves the profile table untouched, and LoadProfile rebinds
    -- Prefs straight back to it.
    local function envWithProfile()
        local TRP3FW, handler = newEnv()

        TRP3FW.defaultSettings = { suppressionTime = 30, debug = false }

        local profile = { suppressionTime = 999, debug = true, staleKey = "leftover" }
        TRP3FW.db = { profiles = { Default = profile } }
        TRP3FW.Prefs = profile

        -- Stand in for core/init.lua's InitializeSettings -> LoadProfile: repoint
        -- Prefs at the saved profile, then backfill any missing defaults. This is
        -- the step that made the old reset a no-op.
        function TRP3FW:InitializeSettings()
            self.Prefs = self.db.profiles.Default
            for k, v in pairs(self.defaultSettings) do
                if self.Prefs[k] == nil then self.Prefs[k] = v end
            end
        end

        return TRP3FW, handler, profile
    end

    T.it("restores a modified setting to its default", function()
        local TRP3FW, handler = envWithProfile()
        handler("reset")
        T.eq(TRP3FW.Prefs.suppressionTime, 30,
            "reset must undo the user's 999; rebinding a local table did not")
    end)

    T.it("clears keys that are not in defaultSettings", function()
        local TRP3FW, handler = envWithProfile()
        handler("reset")
        T.is_nil(TRP3FW.Prefs.staleKey,
            "a reset that only backfills defaults leaves orphaned keys behind")
    end)

    T.it("keeps Prefs pointing at the saved profile table", function()
        local TRP3FW, handler, profile = envWithProfile()
        handler("reset")
        T.eq(TRP3FW.Prefs, profile,
            "clearing in place is what keeps the SavedVariable and Prefs the same table")
    end)

    T.it("tells the user to reload", function()
        local TRP3FW, handler = envWithProfile()
        handler("reset")
        T.truthy(said(TRP3FW, "/reload"),
            "caches and hooks were built from the old values")
    end)
end)

T.describe("debugfilter covers every real debug category", function()
    -- The authoritative list is DEBUG_CATEGORIES in core/utils.lua. Every entry
    -- that maps to its own setting needs a toggle here, or the setting is only
    -- reachable through the settings UI.
    local toggles = {
        { "channel",   "debugChannel"   },
        { "whisper",   "debugWhisper"   },
        { "who",       "debugWho"       },
        { "phase",     "debugPhase"     },
        { "location",  "debugLocation"  },
        { "decision",  "debugDecision"  },
        { "hooks",     "debugHooks"     },
        { "cache",     "debugCache"     },
        { "send",      "debugSend"      },
        { "ui",        "debugUI"        },
        { "utils",     "debugUtils"     },
        { "cleanname", "debugCleanName" },
        { "security",  "debugSecurity"  },
        { "ghost",     "debugGhost"     },  -- was missing
        { "spvp",      "debugSPVP"      },  -- was missing
    }

    for _, pair in ipairs(toggles) do
        local category, prefKey = pair[1], pair[2]
        T.it("debugfilter " .. category .. " toggles " .. prefKey, function()
            local TRP3FW, handler = newEnv()
            TRP3FW.Prefs[prefKey] = false
            handler("debugfilter " .. category)
            T.eq(TRP3FW.Prefs[prefKey], true,
                category .. " is a real DEBUG_CATEGORIES entry but had no command branch")
            handler("debugfilter " .. category)
            T.eq(TRP3FW.Prefs[prefKey], false, "the toggle must go both ways")
        end)
    end

    T.it("an unknown category prints usage instead of toggling", function()
        local TRP3FW, handler = newEnv()
        handler("debugfilter nonsense")
        T.truthy(said(TRP3FW, "Usage:"))
    end)

    T.it("the usage text lists ghost and spvp", function()
        local TRP3FW, handler = newEnv()
        handler("debugfilter nonsense")
        T.truthy(said(TRP3FW, "ghost"), "usage must advertise the categories it accepts")
        T.truthy(said(TRP3FW, "spvp"))
    end)
end)

T.describe("phasecheck releases its mutex", function()
    -- phaseCheckInProgress has exactly one owner (this command) and no other
    -- release path in the addon, so a callback that never arrives latches it
    -- true for the session and every later phasecheck answers "already in
    -- progress" until /reload.
    local function phaseEnv(opts)
        local TRP3FW, handler = newEnv()
        opts = opts or {}

        TRP3FW.hasEpsilonAPI = true
        TRP3FW.Prefs.phaseCheckMode = opts.mode or "alert"
        TRP3FW.currentZoneName = "Elwynn Forest"

        local players = opts.players or { "Alpha", "Bravo", "Charlie" }
        function TRP3FW:ScanZoneForPlayers(cb) cb(true, players) end

        -- answerCount controls how many of the per-player callbacks ever fire.
        local answered = 0
        local budget = opts.answers or #players
        function TRP3FW:CheckPlayerPhase(_, _, cb)
            if answered < budget then
                answered = answered + 1
                cb(true, "phase", 1519, "target")
            end
        end

        return TRP3FW, handler
    end

    T.it("clears the flag when every player answers", function()
        local TRP3FW, handler = phaseEnv()
        handler("phasecheck")
        T.falsy(TRP3FW.phaseCheckInProgress)
    end)

    T.it("clears the flag via the watchdog when a callback never arrives", function()
        local TRP3FW, handler = phaseEnv({ answers = 2 })  -- one player never answers
        handler("phasecheck")
        T.truthy(TRP3FW.phaseCheckInProgress, "still waiting on the third player")

        mock.advance(180)
        mock.flushTimers()

        T.falsy(TRP3FW.phaseCheckInProgress,
            "without a watchdog this stayed true for the rest of the session")
        T.truthy(said(TRP3FW, "timed out"), "a partial result must say so")
    end)

    T.it("reports the summary exactly once", function()
        local TRP3FW, handler = phaseEnv()
        handler("phasecheck")

        mock.advance(180)
        mock.flushTimers()  -- the watchdog still fires; Finish must be idempotent

        local n = 0
        for _, line in ipairs(TRP3FW.output) do
            if line:find("Phase check complete", 1, true) then n = n + 1 end
        end
        T.eq(n, 1, "the watchdog must not double-report a run that already finished")
    end)

    T.it("refuses to scan when phase check mode is off", function()
        local scanned = false
        local TRP3FW, handler = phaseEnv({ mode = "off" })
        function TRP3FW:ScanZoneForPlayers(cb) scanned = true; cb(true, {}) end

        handler("phasecheck")

        T.falsy(scanned, "a privileged WHO query for results that are all 'unavailable'")
        T.falsy(TRP3FW.phaseCheckInProgress, "the early return must not latch the mutex")
    end)

    T.it("clears the flag when the zone scan itself fails", function()
        local TRP3FW, handler = phaseEnv()
        function TRP3FW:ScanZoneForPlayers(cb) cb(false, {}, "unknown_zone") end

        handler("phasecheck")
        T.falsy(TRP3FW.phaseCheckInProgress)
    end)
end)

return T
