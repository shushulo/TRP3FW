-- tests/unit/privileged_tokens_spec.lua
-- Headless tests for GetAvailablePrivilegedTokens' reserved-token accounting (core/utils.lua).
--
-- Its comment always claimed it "mirrors RunPrivilegedSafe defaults", but it returned the RAW
-- bucket. RunPrivilegedSafe subtracts RESERVED_TOKENS for any priority whose config lacks
-- canUseReserved, so a NORMAL-priority caller sizing work off this number was optimistic by
-- exactly RESERVED_TOKENS -- location/phase.lua's batch sizing compensated by subtracting
-- Prefs.privilegedReservedTokens by hand, i.e. two places independently guessing at one rule,
-- and the tail of a batch still took rate_limit rejections it had "budgeted" for.

local T = require("tests.framework")
local H = require("tests.harness")
local mock = H.mock

local function freshFW()
    local fw = H.newNamespace()
    fw.Prefs = {
        privilegedReservedTokens = 2,
        privilegedLowPriorityThreshold = 4,
    }
    H.loadModule("core/utils.lua", fw)
    return fw
end

T.describe("GetAvailablePrivilegedTokens reserved-token accounting", function()
    T.it("returns the raw bucket when no category is given", function()
        mock.setClock(1000)
        local fw = freshFW()
        fw.privilegedRate = { tokens = 10, lastRefill = 1000 }

        T.eq(fw:GetAvailablePrivilegedTokens(), 10,
            "omitting the category keeps the previous raw-bucket behaviour")
    end)

    T.it("BUG (fixed): deducts reserved tokens for a NORMAL-priority category", function()
        mock.setClock(1000)
        local fw = freshFW()
        fw.privilegedRate = { tokens = 10, lastRefill = 1000 }

        -- phase_check_target is NORMAL priority, which cannot spend reserved tokens.
        local available = fw:GetAvailablePrivilegedTokens("phase_check_target")
        T.eq(available, 8,
            "a NORMAL caller can only spend RATE_LIMIT - RESERVED_TOKENS")
    end)

    T.it("agrees with RunPrivilegedSafe about what a NORMAL caller may spend", function()
        -- The real contract: peeking must not promise tokens the spend path would refuse.
        mock.setClock(1000)
        local fw = freshFW()
        -- RunPrivilegedSafe bails at "api_unavailable" without these, so the spend path would
        -- never reach the token accounting this test is about.
        fw.hasEpsilonAPI = true
        _G.C_Epsilon = { RunPrivileged = function() return true end }
        fw.privilegedRate = { tokens = 10, lastRefill = 1000 }

        local promised = math.floor(fw:GetAvailablePrivilegedTokens("phase_check_target"))
        local spent = 0
        for _ = 1, promised do
            if fw:RunPrivilegedSafe("-- no-op", "phase_check_target") then
                spent = spent + 1
            end
        end

        T.eq(spent, promised,
            "every token the peek promised must actually be spendable ("..spent.."/"..promised..")")
    end)

    T.it("does not deduct for a priority that CAN use reserved tokens", function()
        mock.setClock(1000)
        local fw = freshFW()
        fw.privilegedRate = { tokens = 10, lastRefill = 1000 }

        -- phase_restore_target is HIGH priority - the restore leg is exactly what the
        -- reserved pool exists for, so it must see the full bucket.
        T.eq(fw:GetAvailablePrivilegedTokens("phase_restore_target"), 10,
            "a HIGH-priority category may spend the reserved pool")
    end)

    T.it("tracks the reserved-tokens setting rather than a hardcoded 2", function()
        mock.setClock(1000)
        local fw = freshFW()
        fw.Prefs.privilegedReservedTokens = 4
        fw:UpdateValidatedPrioritySettings()
        fw.privilegedRate = { tokens = 10, lastRefill = 1000 }

        T.eq(fw:GetAvailablePrivilegedTokens("phase_check_target"), 6,
            "raising the reserve must lower what a NORMAL caller is promised")
    end)
end)
