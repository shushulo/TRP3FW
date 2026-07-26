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
    "tests.unit.target_sound_mute_spec",
    "tests.unit.inspect_defer_spec",
    "tests.unit.targeting_started_spec",
    "tests.unit.scan_reply_cache_veto_spec",
    "tests.unit.apostrophe_name_spec",
    "tests.unit.allowsender_apostrophe_key_spec",
    "tests.unit.icon_filter_pe_spec",
    "tests.unit.cache_stage_ttl_spec",
    "tests.unit.manual_retarget_race_spec",
    "tests.unit.phase_check_ttl_spec",
    "tests.unit.cascading_interaction_cache_ttl_spec",
    "tests.unit.interaction_stage_ttl_spec",
    "tests.unit.scan_cache_ttl_spec",
    "tests.unit.who_service_ttl_spec",
    "tests.unit.who_service_queue_spec",
    "tests.unit.profile_adapters_spec",
    "tests.unit.pipeline_spec",
    "tests.unit.event_service_spec",
    "tests.unit.profile_isolation_spec",
    "tests.unit.start_phase_spec",
    "tests.unit.history_service_spec",
    "tests.unit.notification_service_spec",
    "tests.unit.theme_spec",
    "tests.unit.search_spec",
    "tests.unit.complexity_preserve_spec",
    "tests.unit.debug_capture_spec",
    "tests.unit.location_stage_timer_spec",
    "tests.unit.spvp_stage_override_spec",
    "tests.unit.location_dispatch_spec",
    "tests.unit.fontsize_wrapper_spec",
    "tests.unit.chomp_pipeline_timer_spec",
    "tests.unit.scan_pipeline_who_mode_spec",
    "tests.unit.addon_keyspace_spec",
    "tests.unit.ghost_data_mutation_spec",
    "tests.unit.direct_msp_xrp_spec",
    "tests.unit.ghost_flag_window_spec",
    "tests.unit.ui_refresh_spec",
    "tests.unit.commands_spec",
    "tests.unit.msp_conversion_cache_spec",
    "tests.unit.cascading_idempotence_spec",
    "tests.unit.scan_nonce_disabled_spec",
    "tests.unit.privileged_tokens_spec",
    "tests.unit.spvp_queue_bounds_spec",
    "tests.unit.alert_fastpath_dedup_spec",
    "tests.unit.profiles_widget_pool_spec",
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
