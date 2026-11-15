//! Lumen built-in WASM plugins.
//!
//! This crate contains the source code for WASM-compiled versions of
//! Lumen's built-in plugins. Compile with:
//!
//! ```bash
//! cd core/plugins/wasm-plugins
//! cargo build --release --target wasm32-unknown-unknown
//! ```
//!
//! The resulting `.wasm` files are loaded by `core/src/plugins/wasm.rs`
//! `PluginHost::load_plugin()`.

mod daily_summary;
mod dashboard_entries;
mod export_md;
mod import_export;
mod theme_manager;
mod wordcount;

use serde_json::Value;

/// Host function: log a message from the plugin.
#[link(name = "host")]
extern "C" {
    fn log(level_ptr: *const u8, level_len: i32, msg_ptr: *const u8, msg_len: i32);
}

/// Host function: make an HTTP GET request (only if network permission granted).
#[link(name = "host")]
extern "C" {
    fn http_get(url_ptr: *const u8, url_len: i32, out_ptr: *mut u8, out_len: i32) -> i32;
}

/// Note context passed from the host to the plugin.
#[derive(serde::Deserialize)]
pub struct NoteContext {
    pub id: String,
    pub title: String,
    pub body: String,
    pub frontmatter: Option<serde_json::Map<String, serde_json::Value>>,
}

/// Plugin result returned to the host.
#[derive(serde::Serialize)]
pub struct PluginResult {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub feedback: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub frontmatter_patch: Option<serde_json::Map<String, serde_json::Value>>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub commands: Vec<String>,
}

impl Default for PluginResult {
    fn default() -> Self {
        Self {
            feedback: None,
            frontmatter_patch: None,
            commands: Vec::new(),
        }
    }
}

/// Read a null-terminated JSON value from WASM linear memory.
///
/// # Safety
/// Reads from WASM linear memory at the given pointer.
pub unsafe fn read_json(mem: &[u8], ptr: i32, len: i32) -> Option<serde_json::Value> {
    let start = ptr as usize;
    let end = start.checked_add(len as usize)?;
    if end > mem.len() {
        return None;
    }
    serde_json::from_slice(&mem[start..end]).ok()
}

/// Write a JSON value into WASM linear memory at the given pointer.
/// Returns the number of bytes written, or -1 if the buffer is too small.
///
/// # Safety
/// Writes to WASM linear memory at the given pointer.
pub unsafe fn write_json(mem: &mut [u8], ptr: i32, value: &serde_json::Value) -> i32 {
    let bytes = match serde_json::to_vec(value) {
        Ok(b) => b,
        Err(_) => return -1,
    };
    let end = ptr.checked_add(bytes.len() as i32)? as usize;
    if end > mem.len() {
        return -1;
    }
    mem[ptr as usize..end].copy_from_slice(&bytes);
    bytes.len() as i32
}

/// Log a message from the plugin to the host.
pub fn plugin_log(level: &str, msg: &str) {
    unsafe {
        log(level.as_ptr(), level.len() as i32, msg.as_ptr(), msg.len() as i32);
    }
}

/// Make an HTTP GET request from the plugin (if network permission granted).
///
/// Returns the number of bytes written to the output buffer, or -1 on error.
pub fn plugin_http_get(url: &str, out_buf: &mut [u8]) -> i32 {
    unsafe {
        http_get(url.as_ptr(), url.len() as i32, out_buf.as_mut_ptr(), out_buf.len() as i32)
    }
}
