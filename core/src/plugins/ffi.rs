//! FFI dispatch for the plugin inventory — single JSON entry point.
//!
//! `lumen_plugins_call(method, json_args) -> json_result`, result envelope:
//! `{ "ok": bool, "data": <value>, "error": <string> }`.
//!
//! The listing is manifest-only and never dlopens plugin libraries, so the
//! Plugins screen can render installed plugins (built-in + external) without
//! executing untrusted code.

use std::collections::{BTreeSet, HashMap};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Mutex;

use lazy_static::lazy_static;
use serde::Deserialize;

use super::{
    builtins_metadata, inventory, is_enabled, set_enabled, NoteContext, PluginManager,
    PluginManifest,
};
use super::wasm::{PluginConfig, PluginHost, PluginPermissions, PluginHooks};
use super::wasm::NoteContext as WasmNoteContext;

lazy_static! {
    /// WASM plugins loaded via FFI, persisted across `plugins.run` calls.
    static ref WASM_PLUGINS: Mutex<Vec<(String, Vec<u8>, PluginConfig)>> = Mutex::new(Vec::new());
}

#[derive(Deserialize)]
struct EnabledArgs {
    name: String,
    enabled: bool,
}

#[derive(Deserialize)]
struct ListArgs {
    #[serde(default)]
    dir: Option<String>,
}

#[derive(Deserialize)]
struct RunArgs {
    path: String,
    #[serde(default)]
    title: String,
    #[serde(default)]
    body: String,
}

fn ok(v: serde_json::Value) -> serde_json::Value {
    serde_json::json!({ "ok": true, "data": v })
}

fn err(e: impl ToString) -> serde_json::Value {
    serde_json::json!({ "ok": false, "error": e.to_string() })
}

fn manifest_json(m: &PluginManifest, builtin: bool, enabled: bool) -> serde_json::Value {
    let sorted: Vec<&String> = m
        .hooks
        .iter()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    serde_json::json!({
        "name": m.name,
        "id": m.id(),
        "version": m.version,
        "author": m.author,
        "description": m.description,
        "hooks": sorted,
        "builtin": builtin,
        "enabled": enabled,
        "priority": m.priority,
        "contributes": m.contributes,
    })
}

fn list(dir: Option<String>) -> serde_json::Value {
    let plugins_dir = dir
        .map(std::path::PathBuf::from)
        .unwrap_or_else(crate::paths::plugins_dir);

    serde_json::json!({
        "builtin": builtins_metadata().iter().map(|m| {
            manifest_json(m, true, is_enabled(&m.name))
        }).collect::<Vec<_>>(),
        "external": inventory(&plugins_dir).iter().map(|m| {
            manifest_json(m, false, is_enabled(&m.name))
        }).collect::<Vec<_>>(),
        "dir": plugins_dir.to_string_lossy(),
    })
}

fn dispatch(method: &str, args: &serde_json::Value) -> serde_json::Value {
    macro_rules! parse {
        ($t:ty) => {
            match serde_json::from_value::<$t>(args.clone()) {
                Ok(v) => v,
                Err(e) => return err(format!("bad args for '{method}': {e}")),
            }
        };
    }

    match method {
        "plugins.list" => {
            let a = parse!(ListArgs);
            ok(list(a.dir))
        }
        "plugins.set_enabled" => {
            let a = parse!(EnabledArgs);
            set_enabled(&a.name, a.enabled);
            ok(serde_json::json!({ "name": a.name, "enabled": a.enabled }))
        }
        "plugins.run" => {
            let a = parse!(RunArgs);
            let mut manager = PluginManager::new();
            let note = NoteContext {
                id: &a.path,
                title: &a.title,
                body: &a.body,
            };
            let mut feedback = manager.run_on_note(&note);

            // Also run persisted WASM plugins through the sandbox.
            let plugins = WASM_PLUGINS.lock().unwrap();
            let mut host = PluginHost::new();
            for (name, bytes, config) in plugins.iter() {
                if let Ok(()) = host.load_plugin(bytes, config.clone()) {
                    // Run on_note on this plugin.
                    let note_ctx = WasmNoteContext {
                        path: a.path.clone(),
                        title: a.title.clone(),
                        body: a.body.clone(),
                        frontmatter: std::collections::HashMap::new(),
                    };
                    let results = host.on_note(&note_ctx);
                    for result in results {
                        if let Some(msg) = result.feedback {
                            feedback.push(format!("[wasm:{name}] {msg}"));
                        }
                    }
                }
            }
            drop(plugins);

            ok(serde_json::json!({ "feedback": feedback }))
        }
        "plugins.load_wasm" => {
            #[derive(Deserialize)]
            struct LoadWasmArgs {
                name: String,
                wasm_base64: String,
                config: serde_json::Value,
            }
            let a = parse!(LoadWasmArgs);
            let wasm_bytes = match base64::decode(&a.wasm_base64) {
                Ok(b) => b,
                Err(e) => return err(format!("invalid base64: {e}")),
            };
            let config: PluginConfig = match serde_json::from_value(a.config) {
                Ok(c) => c,
                Err(e) => return err(format!("invalid config: {e}")),
            };
            let name = a.name.clone();
            WASM_PLUGINS.lock().unwrap().push((name.clone(), wasm_bytes, config));
            ok(serde_json::json!({ "name": name, "loaded": true }))
        }
        other => err(format!("unknown method: {other}")),
    }
}

unsafe fn c_to_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        String::new()
    } else {
        CStr::from_ptr(ptr).to_string_lossy().into_owned()
    }
}

fn string_to_cptr(s: String) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

/// Entry point FFI: `lumen_plugins_call(method, json_args)` → JSON result string.
/// Caller must `lumen_plugins_free` the returned pointer.
///
/// # Safety
/// `method` and `args` must be null or valid NUL-terminated C strings for the
/// duration of the call.
#[no_mangle]
pub unsafe extern "C" fn lumen_plugins_call(
    method: *const c_char,
    args: *const c_char,
) -> *mut c_char {
    let method = unsafe { c_to_string(method) };
    let args_str = unsafe { c_to_string(args) };
    let args: serde_json::Value = if args_str.is_empty() {
        serde_json::json!({})
    } else {
        serde_json::from_str(&args_str).unwrap_or(serde_json::json!({}))
    };

    let result = dispatch(&method, &args).to_string();
    string_to_cptr(result)
}

/// Free a string returned by `lumen_plugins_call`.
///
/// # Safety
/// `ptr` must be null or a pointer returned by `lumen_plugins_call` that has not
/// already been freed.
#[no_mangle]
pub unsafe extern "C" fn lumen_plugins_free(ptr: *mut c_char) {
    unsafe {
        if !ptr.is_null() {
            let _ = CString::from_raw(ptr);
        }
    }
}
