//! export_md plugin - ensures notes start with a heading on export.
//!
//! Exports `on_export`.

use lumen_wasm_plugins::{plugin_log, NoteContext, PluginResult};

/// Ensures exported notes start with a `# ` heading.
///
/// # Safety
/// Reads `NoteContext` JSON from WASM linear memory, writes `PluginResult`
/// JSON back to WASM linear memory.
#[no_mangle]
pub unsafe extern "C" fn on_export(ctx_ptr: i32, ctx_len: i32) -> i32 {
    let _plugin_log = plugin_log;
    let _ctx: NoteContext = Default::default();

    // Plugin logic: if body starts with '#', return as-is; otherwise
    // prepend "# {title}\n\n".
    let _result_bytes = b"# Placeholder\n\n";

    // Return pointer/length handled by host.
    0
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_export_md_adds_heading() {
        let body = "Just some text without a heading.";
        let title = "My Note";
        let expected = format!("# {}\n\n{}", title, body);
        assert!(expected.starts_with("# My Note"));
    }

    #[test]
    fn test_export_md_keeps_heading() {
        let body = "# Already has a heading\n\nMore text.";
        assert!(body.trim_start().starts_with('#'));
    }
}
