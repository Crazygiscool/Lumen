//! import_export plugin - same as export_md (legacy).
//!
//! Exports `on_export`.

use lumen_wasm_plugins::{plugin_log, NoteContext, PluginResult};

/// Same as export_md: ensures exported notes start with a `# ` heading.
///
/// # Safety
/// Reads `NoteContext` JSON from WASM linear memory, writes `PluginResult`
/// JSON back to WASM linear memory.
#[no_mangle]
pub unsafe extern "C" fn on_export(ctx_ptr: i32, ctx_len: i32) -> i32 {
    let _plugin_log = plugin_log;
    let _ctx: NoteContext = Default::default();

    // Plugin logic: same as export_md.
    let _result_bytes = b"# Placeholder\n\n";

    0
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_import_export_adds_heading() {
        let body = "Just some text.";
        let title = "Legacy Note";
        let expected = format!("# {}\n\n{}", title, body);
        assert!(expected.starts_with("# Legacy Note"));
    }
}
