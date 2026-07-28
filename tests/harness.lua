-- tests/harness.lua
-- Builds a minimal TRP3FW namespace and loads addon module files headlessly.
-- Returns helpers for specs to load specific modules with the right varargs.

local mock = require("tests.mock_wow")

local H = { mock = mock }

-- Create a fresh, minimal TRP3FW namespace with the stubs that most modules
-- touch at load time (Debug, profiler, time, Prefs). Specs can augment it.
function H.newNamespace()
    local TRP3FW = {}
    TRP3FW.VERSION = "test"
    TRP3FW.Prefs = {}
    TRP3FW.defaultSettings = {}

    -- No-op logger
    function TRP3FW:Debug() end
    function TRP3FW:Info() end
    function TRP3FW:Warn() end
    function TRP3FW:Error() end
    function TRP3FW:Redact(t) return t end

    -- Profiler stub (spvp.lua calls profiler.start/stop)
    TRP3FW.profiler = { start = function() end, stop = function() end }

    -- Monotonic clock -> mock clock. NOTE: this stub replaces the real GetCurrentTime, so
    -- nothing in that function is covered by the headless suite; changes to it need in-game
    -- verification.
    function TRP3FW:GetCurrentTime() return mock.clock end

    -- Default UnitIsPlayer to true so specs that only care about names keep exercising the
    -- "target is a real player" path. In-game this global always exists; leaving it nil
    -- here would make phase.lua's NPC guard throw instead of testing what the spec means
    -- to test. Specs covering NPC name collisions override this explicitly AFTER calling
    -- newNamespace(). This RESETS unconditionally rather than only filling in a nil: these
    -- specs share one Lua state, so an NPC spec's `return false` would otherwise leak into
    -- every spec that runs after it.
    _G.UnitIsPlayer = function() return true end

    return TRP3FW
end

-- Load an addon Lua file with the (addonName, TRP3FW) vararg the modules expect.
-- Returns whatever the chunk returns (most modules return nothing but mutate TRP3FW).
function H.loadModule(path, TRP3FW)
    local chunk, err = loadfile(path)
    if not chunk then error("loadfile failed for " .. path .. ": " .. tostring(err)) end
    return chunk("TRP3FW", TRP3FW)
end

return H
