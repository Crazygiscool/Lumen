//! FFI dispatch for the encrypted vault — single JSON entry point.
//!
//! `lumen_vault_call(method, json_args) -> json_result`, result envelope:
//! `{ "ok": bool, "data": <value>, "error": <string> }`.
//!
//! Methods that touch a store accept an optional `store` (`"vault"` or
//! `"journal"`), defaulting to `"vault"`.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use base64::Engine;
use serde::Deserialize;

use super::{
    create_with_passphrase, delete, export, info, is_unlocked, list, lock, lock_all, mkdir,
    open_stores, read_bytes, read_text, rename, search, unlock, write_bytes, write_text,
};

fn default_store() -> String {
    "vault".to_string()
}

#[derive(Deserialize)]
struct PathArgs {
    path: String,
    #[serde(default = "default_store")]
    store: String,
}

#[derive(Deserialize)]
struct CreateArgs {
    path: String,
    passphrase: String,
    #[serde(default = "default_store")]
    store: String,
}

#[derive(Deserialize)]
struct TextArgs {
    path: String,
    text: String,
    #[serde(default = "default_store")]
    store: String,
}

#[derive(Deserialize)]
struct DataArgs {
    path: String,
    data: String,
    #[serde(default = "default_store")]
    store: String,
}

#[derive(Deserialize)]
struct MoveArgs {
    from: String,
    to: String,
    #[serde(default = "default_store")]
    store: String,
}

#[derive(Deserialize)]
struct SearchArgs {
    query: String,
    #[serde(default = "default_max")]
    max_results: usize,
    #[serde(default = "default_store")]
    store: String,
}

#[derive(Deserialize)]
struct StoreArgs {
    #[serde(default = "default_store")]
    store: String,
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
            match create_with_passphrase(&a.path, &a.passphrase, &a.store) {
                Ok(()) => serde_json::json!({ "created": a.path, "store": a.store }),
                Err(e) => return err(e),
            }
        }
        "vault.unlock" => {
            let a = parse!(CreateArgs);
            if let Err(e) = unlock(&a.path, &a.passphrase, &a.store) {
                return err(e);
            }
            serde_json::json!({ "unlocked": a.path, "store": a.store })
        }
        "vault.lock" => {
            let a = parse!(StoreArgs);
            lock(&a.store);
            serde_json::json!({ "locked": true, "store": a.store })
        }
        "vault.lock_all" => {
            lock_all();
            serde_json::json!({ "locked": true })
        }
        "vault.is_unlocked" => {
            let a = parse!(StoreArgs);
            ok(serde_json::json!({ "unlocked": is_unlocked(&a.store), "store": a.store }))
        }
        "vault.open_stores" => ok(serde_json::json!({ "stores": open_stores() })),
        "vault.info" => {
            let a = parse!(StoreArgs);
            match info(&a.store) {
                Ok(v) => v,
                Err(e) => return err(e),
            }
        }
        "vault.read" => {
            let a = parse!(PathArgs);
            match read_bytes(&a.path, &a.store) {
                Ok(bytes) => {
                    let b64 = base64::engine::general_purpose::STANDARD.encode(&bytes);
                    ok(serde_json::json!({ "data": b64 }))
                }
                Err(e) => return err(e),
            }
        }
        "vault.read_text" => {
            let a = parse!(PathArgs);
            match read_text(&a.path, &a.store) {
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
            if let Err(e) = write_bytes(&a.path, &bytes, &a.store) {
                return err(e);
            }
            ok(serde_json::json!({ "written": a.path }))
        }
        "vault.write_text" => {
            let a = parse!(TextArgs);
            if let Err(e) = write_text(&a.path, &a.text, &a.store) {
                return err(e);
            }
            ok(serde_json::json!({ "written": a.path }))
        }
        "vault.mkdir" => {
            let a = parse!(PathArgs);
            if let Err(e) = mkdir(&a.path, &a.store) {
                return err(e);
            }
            ok(serde_json::json!({ "created": a.path }))
        }
        "vault.delete" => {
            let a = parse!(PathArgs);
            if let Err(e) = delete(&a.path, &a.store) {
                return err(e);
            }
            ok(serde_json::json!({ "deleted": a.path }))
        }
        "vault.rename" => {
            let a = parse!(MoveArgs);
            if let Err(e) = rename(&a.from, &a.to, &a.store) {
                return err(e);
            }
            ok(serde_json::json!({ "from": a.from, "to": a.to }))
        }
        "vault.list" => {
            let a = parse!(PathArgs);
            match list(&a.path, &a.store) {
                Ok(entries) => {
                    let json = serde_json::to_value(&entries).unwrap_or(err("serialize failed"));
                    ok(json)
                }
                Err(e) => return err(e),
            }
        }
        "vault.search" => {
            let a = parse!(SearchArgs);
            match search(&a.query, a.max_results, &a.store) {
                Ok(hits) => ok(serde_json::json!(hits)),
                Err(e) => return err(e),
            }
        }
        "vault.export" => {
            let a = parse!(PathArgs);
            match export(&a.path, &a.store) {
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