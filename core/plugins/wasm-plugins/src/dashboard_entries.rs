//! dashboard_entries plugin - placeholder for dashboard entries.
//!
//! Exports `on_note`.

use lumen_wasm_plugins::{plugin_log, NoteContext, PluginResult};

/// Placeholder for dashboard entries - does nothing on note save.
///
/// # Safety
/// Reads `NoteContext` JSON from WASM linear memory, writes `PluginResult`
/// JSON back to WASM linear memory.
#[no_mangle]
pub unsafe extern "C" fn on_note(ctx_ptr: i32, ctx_len: i32) -> i32 {
    let _plugin_log = plugin_log;
    let _ctx: NoteContext = Default::default();

    // Plugin logic: no-op (dashboard entries are handled elsewhere).
    let _result: PluginResult = PluginResult::default();

    0
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_dashboard_entries_noop() {
        let result: PluginResult = Default::default();
        assert!(result.feedback.is_none());
    }
}
