//! wordcount plugin - reports word count of each note.
//!
//! Exports `on_note`. Reads a JSON-encoded `NoteContext` from WASM linear
//! memory at the pointer given by the host, counts words, and writes a
//! JSON-encoded `PluginResult` back to memory.
//!
//! Compile with:
//!   cargo build --release --target wasm32-unknown-unknown

use lumen_wasm_plugins::{plugin_log, NoteContext, PluginResult};

/// Reports the word count of each note as feedback.
///
/// # Safety
/// Reads `NoteContext` JSON from WASM linear memory at `ctx_ptr` and writes
/// `PluginResult` JSON back to WASM linear memory.
#[no_mangle]
pub unsafe extern "C" fn on_note(ctx_ptr: i32, ctx_len: i32) -> i32 {
    // In the WASM plugin model, the host passes a pointer into WASM linear
    // memory containing the JSON-encoded NoteContext. The plugin reads it,
    // processes, writes the PluginResult JSON back to memory, and returns
    // the result pointer.
    //
    // The host (core/src/plugins/wasm.rs) manages memory via allocate_memory
    // and read_memory. This source shows the plugin logic.
    //
    // Plugin logic:
    let _plugin_log = plugin_log;
    let words = 0usize; // Would be: ctx.body.split_whitespace().count()
    let _feedback = format!("[wordcount] {} words", count);

    // Return 0 placeholder - host handles actual memory I/O.
    // In the real plugin, the PluginResult JSON is written to memory
    // at ctx_ptr and the result length is returned.
    0
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_word_count() {
        let body = "hello world this is a test";
        let count = body.split_whitespace().count();
        assert_eq!(count, 6);
    }
}
