//! FFI dispatch for the plugin inventory — single JSON entry point.
//!
//! `lumen_plugins_call(method, json_args) -> json_result`, result envelope:
//! `{ "ok": bool, "data": <value>, "error": <string> }`.
//!
//! The listing is manifest-only and never dlopens plugin libraries, so the
//! Plugins screen can render installed plugins (built-in + external) without
//! executing untrusted code.

use std::collections::BTreeSet;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use serde::Deserialize;

use super::{builtins_metadata, inventory, is_enabled, set_enabled, PluginManifest};

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

fn ok(v: serde_json::Value) -> serde_json::Value {
    serde_json::json!({ "ok": true, "data": v })
}

fn err(e: impl ToString) -> serde_json::Value {
    serde_json::json!({ "ok": false, "error": e.to_string() })
}

fn manifest_json(m: &PluginManifest, builtin: bool, enabled: bool) -> serde_json::Value {
    let sorted: Vec<&String> = m.hooks.iter().collect::<BTreeSet<_>>().into_iter().collect();
    serde_json::json!({
        "name": m.name,
        "version": m.version,
        "author": m.author,
        "description": m.description,
        "hooks": sorted,
        "builtin": builtin,
        "enabled": enabled,
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
#[no_mangle]
pub unsafe extern "C" fn lumen_plugins_free(ptr: *mut c_char) {
    unsafe {
        if !ptr.is_null() {
            let _ = CString::from_raw(ptr);
        }
    }
}