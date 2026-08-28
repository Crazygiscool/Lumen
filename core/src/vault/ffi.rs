//! FFI dispatch for the encrypted vault — single JSON entry point.
//!
//! `lumen_vault_call(method, json_args) -> json_result`, result envelope:
//! `{ "ok": bool, "data": <value>, "error": <string> }`.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use base64::Engine;
use serde::Deserialize;

use super::{create_with_passphrase, delete, export, info, is_unlocked, list, lock, mkdir, read_bytes, read_text, rename, search, unlock, write_bytes, write_text};

#[derive(Deserialize)]
struct PathArgs {
    path: String,
}

#[derive(Deserialize)]
struct CreateArgs {
    path: String,
    passphrase: String,
}

#[derive(Deserialize)]
struct TextArgs {
    path: String,
    text: String,
}

#[derive(Deserialize)]
struct DataArgs {
    path: String,
    data: String,
}

#[derive(Deserialize)]
struct MoveArgs {
    from: String,
    to: String,
}

#[derive(Deserialize)]
struct SearchArgs {
    query: String,
    #[serde(default = "default_max")]
    max_results: usize,
}

fn default_max() -> usize {
    200
}

fn ok(v: serde_json::Value) -> serde_json::Value {
    serde_json::json!({ "ok": true, "data": v })
}

fn err(e: impl ToString) -> serde_json::Value {
    serde_json::json!({ "ok": false, "error": e.to_string() })
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

    let result = match method {
        "vault.create" => {
            let a = parse!(CreateArgs);
            match create_with_passphrase(&a.path, &a.passphrase) {
                Ok(()) => serde_json::json!({ "created": a.path }),
                Err(e) => return err(e),
            }
        }
        "vault.unlock" => {
            let a = parse!(CreateArgs);
            if let Err(e) = unlock(&a.path, &a.passphrase) {
                return err(e);
            }
            serde_json::json!({ "unlocked": a.path })
        }
        "vault.lock" => {
            lock();
            serde_json::json!({ "locked": true })
        }
        "vault.is_unlocked" => ok(serde_json::json!({ "unlocked": is_unlocked() })),
        "vault.info" => match info() {
            Ok(v) => v,
            Err(e) => return err(e),
        },
        "vault.read" => {
            let a = parse!(PathArgs);
            match read_bytes(&a.path) {
                Ok(bytes) => {
                    let b64 = base64::engine::general_purpose::STANDARD.encode(&bytes);
                    ok(serde_json::json!({ "data": b64 }))
                }
                Err(e) => return err(e),
            }
        }
        "vault.read_text" => {
            let a = parse!(PathArgs);
            match read_text(&a.path) {
                Ok(text) => ok(serde_json::json!({ "text": text })),
                Err(e) => return err(e),
            }
        }
        "vault.write" => {
            let a = parse!(DataArgs);
            let bytes = match base64::engine::general_purpose::STANDARD.decode(&a.data) {
                Ok(b) => b,
                Err(e) => return err(format!("base64 decode: {e}")),
            };
            if let Err(e) = write_bytes(&a.path, &bytes) {
                return err(e);
            }
            ok(serde_json::json!({ "written": a.path }))
        }
        "vault.write_text" => {
            let a = parse!(TextArgs);
            if let Err(e) = write_text(&a.path, &a.text) {
                return err(e);
            }
            ok(serde_json::json!({ "written": a.path }))
        }
        "vault.mkdir" => {
            let a = parse!(PathArgs);
            if let Err(e) = mkdir(&a.path) {
                return err(e);
            }
            ok(serde_json::json!({ "created": a.path }))
        }
        "vault.delete" => {
            let a = parse!(PathArgs);
            if let Err(e) = delete(&a.path) {
                return err(e);
            }
            ok(serde_json::json!({ "deleted": a.path }))
        }
        "vault.rename" => {
            let a = parse!(MoveArgs);
            if let Err(e) = rename(&a.from, &a.to) {
                return err(e);
            }
            ok(serde_json::json!({ "from": a.from, "to": a.to }))
        }
        "vault.list" => {
            let a = parse!(PathArgs);
            match list(&a.path) {
                Ok(entries) => {
                    let json = serde_json::to_value(&entries).unwrap_or(err("serialize failed"));
                    ok(json)
                }
                Err(e) => return err(e),
            }
        }
        "vault.search" => {
            let a = parse!(SearchArgs);
            match search(&a.query, a.max_results) {
                Ok(hits) => ok(serde_json::json!(hits)),
                Err(e) => return err(e),
            }
        }
        "vault.export" => {
            let a = parse!(PathArgs);
            match export(&a.path) {
                Ok(count) => ok(serde_json::json!({ "exported": count })),
                Err(e) => return err(e),
            }
        }
        other => return err(format!("unknown method: {other}")),
    };

    result
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

/// Entry point FFI: `lumen_vault_call(method, json_args)` → JSON result string.
/// Caller must `lumen_vault_free` the returned pointer.
#[no_mangle]
pub unsafe extern "C" fn lumen_vault_call(method: *const c_char, args: *const c_char) -> *mut c_char {
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

/// Free a string returned by `lumen_vault_call`.
#[no_mangle]
pub unsafe extern "C" fn lumen_vault_free(ptr: *mut c_char) {
    unsafe {
        if !ptr.is_null() {
            let _ = CString::from_raw(ptr);
        }
    }
}