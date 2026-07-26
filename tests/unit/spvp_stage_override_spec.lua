-- tests/unit/spvp_stage_override_spec.lua
-- Headless tests for the SPVP enable/disable contract between features/stages/SPVPStage.lua,
-- features/stages/AlertFastPathStage.lua and location/cascading.lua.
--
-- Bug fixed: the "disable SPVP for this phase" setting (spvpPerPhaseOverrides) did nothing.
--
-- SPVPStage declines by returning { handled = false } WITHOUT setting context.spvpEnabled,
-- so the field stayed nil. LocationStage forwards it as options.spvpEnabled, and
-- CheckLocationCascading has a late-resolution block that fires precisely on
-- `spvpEnabled == nil` and re-derives it from live prefs + salt presence - with no
-- knowledge of per-phase overrides. So an explicit opt-out was silently re-enabled
-- downstream and the SPEKE handshake ran anyway.
--
-- nil had to mean two different things: "no opinion yet, salt still loading" (where late
-- resolution IS the intended mechanism) and "deliberately off". The fix makes deliberate
-- declines set context.spvpEnabled = false, leaving nil for the loading case only.
--
-- AlertFastPathStage had a second, independent leak of the same decision: it built an
-- `options` table and then never passed it to CheckLocationCascading.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW(opts)
    opts = opts or {}
    local fw = H.newNamespace()
    H.loadModule("core/Stage.lua", fw)

    fw.hasEpsilonAPI = (opts.hasEpsilonAPI ~= false)
    fw.Prefs = { spvpEnabled = true }
    local phaseID = opts.phaseID or 42
    local salt = opts.salt
    if salt == nil and opts.saltLoading ~= true then salt = "abc123def456xyz" end

    function fw:GetCurrentPhaseID() return phaseID end
    function fw:GetPhaseSalt() return salt end

    H.loadModule("features/stages/SPVPStage.lua", fw)
    return fw
end

local function ctx(settings)
    return { playerName = "Bob", addon = "TRP3", sendId = 1, settings = settings or { spvpEnabled = true } }
end

T.describe("SPVPStage: enabled path", function()
    T.it("sets spvpEnabled = true and publishes the phase/salt when everything is ready", function()
        local fw = freshFW({ phaseID = 42 })
        local c = ctx()
        local result = fw.SPVPStage:New("SPVP"):Process(c)

        T.falsy(result.handled, "SPVPStage only prepares context, it never handles")
        T.eq(c.spvpEnabled, true)
        T.eq(c.spvpPhaseID, 42)
        T.eq(c.spvpSalt, "abc123def456xyz")
    end)
end)

T.describe("SPVPStage: deliberate declines must be false, not nil", function()
    T.it("BUG (fixed): a per-phase override sets spvpEnabled = false", function()
        local fw = freshFW({ phaseID = 42 })
        local c = ctx({ spvpEnabled = true, spvpPerPhaseOverrides = { [42] = false } })
        fw.SPVPStage:New("SPVP"):Process(c)

        T.eq(c.spvpEnabled, false,
            "nil here lets cascading's late-resolution re-enable SPVP and defeat the override")
        T.not_nil(c.spvpEnabled, "explicitly false, not merely absent")
    end)

    T.it("an override for a DIFFERENT phase does not disable this one", function()
        local fw = freshFW({ phaseID = 42 })
        local c = ctx({ spvpEnabled = true, spvpPerPhaseOverrides = { [99] = false } })
        fw.SPVPStage:New("SPVP"):Process(c)
        T.eq(c.spvpEnabled, true)
    end)

    T.it("the master toggle sets spvpEnabled = false", function()
        local fw = freshFW()
        local c = ctx({ spvpEnabled = false })
        fw.SPVPStage:New("SPVP"):Process(c)
        T.eq(c.spvpEnabled, false)
    end)

    T.it("Start Phase (169) sets spvpEnabled = false", function()
        local fw = freshFW({ phaseID = 169 })
        local c = ctx()
        fw.SPVPStage:New("SPVP"):Process(c)
        T.eq(c.spvpEnabled, false, "the 169 exclusion is a hard rule, not a hint")
    end)

    T.it("a missing Epsilon API sets spvpEnabled = false", function()
        local fw = freshFW({ hasEpsilonAPI = false })
        local c = ctx()
        fw.SPVPStage:New("SPVP"):Process(c)
        T.eq(c.spvpEnabled, false)
    end)

    T.it("an empty salt sets spvpEnabled = false", function()
        local fw = freshFW({ salt = "" })
        local c = ctx()
        fw.SPVPStage:New("SPVP"):Process(c)
        T.eq(c.spvpEnabled, false)
    end)
end)

T.describe("SPVPStage: 'not ready yet' must stay nil", function()
    -- Per the SPVP salt contract, GetPhaseSalt returns nil while an async fetch is in
    -- flight. That is the one case cascading's late resolution exists to handle, so the
    -- stage must NOT claim a decision it hasn't made.
    T.it("leaves spvpEnabled nil while the salt is still loading", function()
        local fw = freshFW({ saltLoading = true })
        local c = ctx()
        fw.SPVPStage:New("SPVP"):Process(c)
        T.is_nil(c.spvpEnabled, "nil is reserved for 'no opinion' so late resolution can still run")
    end)
end)

T.describe("SPVPStage: settings-snapshot handling", function()
    T.it("falls back to live Prefs only when the snapshot omits spvpEnabled", function()
        local fw = freshFW()
        fw.Prefs.spvpEnabled = false
        local c = { playerName = "Bob", sendId = 1, settings = {} }  -- no snapshot value
        fw.SPVPStage:New("SPVP"):Process(c)
        T.eq(c.spvpEnabled, false, "live pref is consulted when the snapshot has nothing")
    end)

    T.it("does not raise when the context carries no settings table at all", function()
        local fw = freshFW()
        T.no_raise(function()
            fw.SPVPStage:New("SPVP"):Process({ playerName = "Bob", sendId = 1 })
        end, "the per-phase override lookup used to index a nil settings table")
    end)
end)

-- ===================================================================
-- AlertFastPathStage: the second leak of the same decision
-- ===================================================================

local function freshAlertFW()
    local fw = H.newNamespace()
    fw.Prefs = {}
    H.loadModule("core/Stage.lua", fw)

    fw.ServiceContainer = { Get = function() return nil end }
    function fw:ShouldAlertOnPhase() return true end
    function fw:ShouldBlockOnPhase() return false end
    function fw:ShouldAlertOnMap() return true end
    function fw:ShouldBlockOnMap() return false end
    function fw:IsPhaseCheckEnabled() return true end
    function fw:IsMapCheckEnabled() return true end
    function fw:IsProfileSwitchOverrideActive() return false end
    function fw:TrackAddonRequest() end
    function fw:AllowSender() end
    function fw:ProcessBurstAllows() end

    fw.cascadingCalls = {}
    function fw:CheckLocationCascading(playerName, sendId, callback, options)
        table.insert(fw.cascadingCalls, { playerName = playerName, options = options })
    end

    H.loadModule("features/stages/AlertFastPathStage.lua", fw)
    return fw
end

T.describe("AlertFastPathStage: SPVP context propagation", function()
    T.it("BUG (fixed): passes the options table to CheckLocationCascading", function()
        mock.setClock(1000)
        local fw = freshAlertFW()
        local c = {
            playerName = "Bob", addon = "TRP3", sendId = 1, isWhisper = true, now = 1000,
            settings = { blockStartPhase = false, ghostOnStartPhase = false },
            spvpEnabled = false, spvpPhaseID = 42, spvpSalt = "",
        }

        local result = fw.AlertFastPathStage:Process(c)
        T.truthy(result.handled)
        T.eq(#fw.cascadingCalls, 1)
        T.not_nil(fw.cascadingCalls[1].options,
            "options was built and then dropped, so SPVPStage's decision never reached cascading")
        T.eq(fw.cascadingCalls[1].options.spvpEnabled, false,
            "a deliberate opt-out must survive the alert-only path too")
    end)

    T.it("forwards an enabled SPVP context unchanged", function()
        mock.setClock(1000)
        local fw = freshAlertFW()
        local c = {
            playerName = "Bob", addon = "TRP3", sendId = 1, isWhisper = true, now = 1000,
            settings = { blockStartPhase = false, ghostOnStartPhase = false },
            spvpEnabled = true, spvpPhaseID = 42, spvpSalt = "abc123def456xyz",
        }

        fw.AlertFastPathStage:Process(c)
        T.eq(fw.cascadingCalls[1].options.spvpEnabled, true)
        T.eq(fw.cascadingCalls[1].options.spvpPhaseID, 42)
        T.eq(fw.cascadingCalls[1].options.spvpSalt, "abc123def456xyz")
    end)
end)

return T
