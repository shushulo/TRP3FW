-- tests/run_headless.lua
-- Headless test runner. Run from the addon root with:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" tests/run_headless.lua
--
-- Loads each unit spec (which registers tests via the shared framework) and
-- prints a pass/fail summary. Exits non-zero on any failure (CI-friendly).

-- Make `require("tests.xxx")` and `require("tests.unit.xxx")` work regardless
-- of cwd by adding ./?.lua to package.path.
package.path = "./?.lua;" .. package.path

-- Spec files to run (add new ones here).
local specs = {
    "tests.unit.spvp_crypto_spec",
    "tests.unit.sanitize_spec",
    "tests.unit.cache_interface_spec",
    "tests.unit.who_fallback_spec",
    "tests.unit.utils_security_spec",
    "tests.unit.profile_adapters_spec",
    "tests.unit.pipeline_spec",
    "tests.unit.start_phase_spec",
    "tests.unit.history_service_spec",
}

local T = require("tests.framework")

for _, spec in ipairs(specs) do
    local ok, err = pcall(require, spec)
    if not ok then
        T.failed = T.failed + 1
        table.insert(T.failures, { label = spec .. " (load error)", err = err })
        io.write("E")
    end
end

local success = T.report()
os.exit(success and 0 or 1)
