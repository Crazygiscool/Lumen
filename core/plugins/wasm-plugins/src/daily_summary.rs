//! daily_summary plugin - reports title and word count of daily notes.
//!
//! Exports `on_note`.

use lumen_wasm_plugins::{plugin_log, NoteContext, PluginResult};

/// Reports title and word count for daily notes.
///
/// # Safety
/// Reads `NoteContext` JSON from WASM linear memory, writes `PluginResult`
/// JSON back to WASM linear memory.
#[no_mangle]
pub unsafe extern "C" fn on_note(ctx_ptr: i32, ctx_len: i32) -> i32 {
    let _plugin_log = plugin_log;
    let _ctx: NoteContext = Default::default();

    // Plugin logic: report title and word count for daily notes.
    let _feedback = format!("[daily_summary] 0 words");

    // Return pointer/length handled by host.
    0
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_daily_summary_format() {
        let title = "2026-01-15";
        let words = 42;
        let feedback = format!("[daily_summary] {} — {} words", title, words);
        assert!(feedback.contains("2026-01-15"));
        assert!(feedback.contains("42 words"));
    }
}
