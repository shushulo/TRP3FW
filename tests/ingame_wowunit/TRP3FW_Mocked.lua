-- tests/wowunit/TRP3FW_Mocked.lua
-- The reason TRP3FW adopts WoWUnit: deterministic in-game tests that fake the
-- live APIs the headless suite cannot reach (C_Epsilon, the Epsilon flag, the
-- decision predicates' Prefs inputs, ApplyLocationDecision side effects).
--
-- Every test uses WoWUnit's Replace(), which is auto-reverted after the test
-- runs (Test:__call calls ClearReplaces()), so no test leaks mocked state into
-- the next one or into the live addon. That auto-revert is the whole point of
-- using the framework here instead of more hand-rolled /trp3fwtest cases.
--
-- Coverage focus = the live-namespace decision/Epsilon paths:
--   * ProcessLocationDecision  -> shouldBlock / shouldAlert / useGhost mapping
--     driven by the real ShouldAlertOnPhase/ShouldBlockOnMap predicates, which
--     read TRP3FW.Prefs.phaseCheckMode / mapCheckMode.
--   * GetCachedPhaseID          -> C_Epsilon.GetPhaseId() + hasEpsilonAPI gate.
--   * RunPrivilegedSafe         -> hasEpsilonAPI / code-validation gating.
--
-- Loaded only on v1.5-tests. Never shipped to v1.5/GitHub.

local addonName, TRP3FW = ...

if not _G.WoWUnit then return end

local AreEqual, IsTrue, IsFalse, Exists, Replace =
    WoWUnit.AreEqual, WoWUnit.IsTrue, WoWUnit.IsFalse, WoWUnit.Exists, WoWUnit.Replace

-- ============================================================================
-- Helpers
-- ============================================================================

-- A minimal locationResult that says "location check failed" for the given
-- alertType, which is what drives ProcessLocationDecision down its block path.
local function failedLocation(alertType)
    return {
        locationOK = false,
        alertType = alertType,
        cacheInfo = {},
        checkDetails = {},
    }
end

-- A context whose settings disable SPVP, so ProcessLocationDecision resolves
-- synchronously (the SPVP rescue branch needs spvpEnabled + hasEpsilonAPI and
-- goes async via a callback -- we exclude it here on purpose).
local function decisionContext()
    return {
        now = TRP3FW:GetCurrentTime(),
        playerName = "__WuDecisionTarget__",
        addon = "TRP3",
        isWhisper = false,
        sendId = "__wu_sendid__",
        originalFunc = nil,        -- no real send is attempted
        originalArgs = nil,
        settings = {
            notifyEnabled = false, -- keep NotificationService quiet during tests
            spvpEnabled = false,   -- force the synchronous decision path
            ghostOnStartPhase = false,
            ghostProfileID = nil,
        },
    }
end

-- Spy on ApplyLocationDecision: capture its (shouldBlock, shouldAlert, useGhost)
-- arguments instead of letting it run real side effects (notifications, sends,
-- history). Replace() auto-reverts it after the test.
local function spyOnApply()
    local captured = {}
    Replace(TRP3FW, "ApplyLocationDecision",
        function(_self, context, shouldBlock, shouldAlert, useGhost, locationResult)
            captured.shouldBlock = shouldBlock
            captured.shouldAlert = shouldAlert
            captured.useGhost = useGhost
            captured.called = true
        end)
    -- ReplayQueuedRequests would also fire; stub it so a real (empty) queue
    -- replay can't touch anything during the test.
    Replace(TRP3FW, "ReplayQueuedRequests", function() end)
    return captured
end

-- ============================================================================
-- Decision logic: phaseCheckMode -> block/alert/ghost
-- ============================================================================

local Decision = WoWUnit("TRP3FW Decision (mocked)")

function Decision:PhaseBlockMode_Blocks()
    Replace(TRP3FW.Prefs, "phaseCheckMode", "block")
    Replace(TRP3FW.Prefs, "mapCheckMode", "off")
    local cap = spyOnApply()

    TRP3FW:ProcessLocationDecision(decisionContext(), failedLocation("phase_not_nearby"))

    IsTrue(cap.called)
    IsTrue(cap.shouldBlock)
    IsFalse(cap.useGhost)        -- block mode is not ghost
end

function Decision:PhaseGhostMode_Ghosts()
    Replace(TRP3FW.Prefs, "phaseCheckMode", "ghost")
    Replace(TRP3FW.Prefs, "mapCheckMode", "off")
    local cap = spyOnApply()

    TRP3FW:ProcessLocationDecision(decisionContext(), failedLocation("phase_not_nearby"))

    IsTrue(cap.shouldBlock)
    IsTrue(cap.useGhost)         -- ghost mode blocks via ghost send
end

function Decision:PhaseAlertMode_AlertsOnly()
    Replace(TRP3FW.Prefs, "phaseCheckMode", "alert")
    Replace(TRP3FW.Prefs, "mapCheckMode", "off")
    local cap = spyOnApply()

    TRP3FW:ProcessLocationDecision(decisionContext(), failedLocation("phase_not_nearby"))

    IsTrue(cap.shouldAlert)
    IsFalse(cap.shouldBlock)     -- alert-only never blocks
    IsFalse(cap.useGhost)
end

function Decision:PhaseAlertBlockMode_AlertsAndBlocks()
    Replace(TRP3FW.Prefs, "phaseCheckMode", "alert_block")
    Replace(TRP3FW.Prefs, "mapCheckMode", "off")
    local cap = spyOnApply()

    TRP3FW:ProcessLocationDecision(decisionContext(), failedLocation("phase_not_nearby"))

    IsTrue(cap.shouldAlert)
    IsTrue(cap.shouldBlock)
    IsFalse(cap.useGhost)
end

function Decision:MapGhostMode_GhostsOnMapAlertType()
    Replace(TRP3FW.Prefs, "phaseCheckMode", "off")
    Replace(TRP3FW.Prefs, "mapCheckMode", "alert_ghost")
    local cap = spyOnApply()

    -- map-source failure -> map predicates drive the decision
    TRP3FW:ProcessLocationDecision(decisionContext(), failedLocation("map_not_nearby"))

    IsTrue(cap.shouldAlert)
    IsTrue(cap.shouldBlock)
    IsTrue(cap.useGhost)
end

function Decision:LocationOK_Allows()
    Replace(TRP3FW.Prefs, "phaseCheckMode", "block")
    Replace(TRP3FW.Prefs, "mapCheckMode", "block")
    local cap = spyOnApply()

    -- locationOK = true -> no alertType branch taken -> allow
    TRP3FW:ProcessLocationDecision(decisionContext(), {
        locationOK = true, alertType = nil, cacheInfo = {}, checkDetails = {},
    })

    IsTrue(cap.called)
    IsFalse(cap.shouldBlock)
    IsFalse(cap.shouldAlert)
    IsFalse(cap.useGhost)
end

function Decision:StartPhaseBlock_AlwaysBlocks()
    -- start_phase_block forces a block regardless of phase/map mode.
    Replace(TRP3FW.Prefs, "phaseCheckMode", "off")
    Replace(TRP3FW.Prefs, "mapCheckMode", "off")
    local ctx = decisionContext()
    ctx.settings.ghostOnStartPhase = false  -- block, not ghost
    local cap = spyOnApply()

    TRP3FW:ProcessLocationDecision(ctx, failedLocation("start_phase_block"))

    IsTrue(cap.shouldBlock)
    IsFalse(cap.useGhost)
end

function Decision:StartPhaseBlock_GhostsWhenConfigured()
    Replace(TRP3FW.Prefs, "phaseCheckMode", "off")
    Replace(TRP3FW.Prefs, "mapCheckMode", "off")
    local ctx = decisionContext()
    ctx.settings.ghostOnStartPhase = true   -- ghost the start-phase block
    local cap = spyOnApply()

    TRP3FW:ProcessLocationDecision(ctx, failedLocation("start_phase_block"))

    IsTrue(cap.shouldBlock)
    IsTrue(cap.useGhost)
end

-- ============================================================================
-- Epsilon phase API: GetCachedPhaseID with C_Epsilon mocked
-- ============================================================================

local Epsilon = WoWUnit("TRP3FW Epsilon (mocked)")

function Epsilon:GetCachedPhaseID_ReadsMockedAPI()
    Replace(TRP3FW, "hasEpsilonAPI", true)
    Replace("C_Epsilon", { GetPhaseId = function() return 169 end })
    -- bust the 1s TTL cache so the mocked API is actually consulted
    Replace(TRP3FW, "cachedPhaseID", nil)
    Replace(TRP3FW, "cachedPhaseTimestamp", 0)

    AreEqual(169, TRP3FW:GetCachedPhaseID())
end

function Epsilon:GetCachedPhaseID_NilWithoutAPI()
    Replace(TRP3FW, "hasEpsilonAPI", false)
    -- Even with a working C_Epsilon, the hasEpsilonAPI gate must short-circuit.
    Replace("C_Epsilon", { GetPhaseId = function() return 42 end })

    AreEqual(nil, TRP3FW:GetCachedPhaseID())
end

function Epsilon:RunPrivilegedSafe_BlockedWithoutAPI()
    Replace(TRP3FW, "hasEpsilonAPI", false)
    local ok, reason = TRP3FW:RunPrivilegedSafe('TargetUnit("Bob")', "wu_test")
    IsFalse(ok)
    AreEqual("api_unavailable", reason)
end

function Epsilon:RunPrivilegedSafe_RejectsNonStringCode()
    Replace(TRP3FW, "hasEpsilonAPI", true)
    local ok, reason = TRP3FW:RunPrivilegedSafe(nil, "wu_test")
    IsFalse(ok)
    AreEqual("invalid_code", reason)
end
