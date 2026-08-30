//! FFI dispatch for the encrypted tank — single JSON entry point.
//!
//! `lumen_tank_call(method, json_args) -> json_result`, result envelope:
//! `{ "ok": bool, "data": <value>, "error": <string> }`.
//!
//! The tank is a global encrypted store for arbitrary files; methods cover
//! setup/unlock/lock plus per-file encrypt/decrypt/delete/info.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use serde::Deserialize;

use super::{
    blob_inventory, decrypt_file, delete_file, encrypt_file, info_file, lock, set_path, setup,
    status, unlock,
};

#[derive(Deserialize)]
struct PathArgs {
    path: String,
}

#[derive(Deserialize)]
struct SetupArgs {
    path: String,
    passphrase: String,
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

    match method {
        "tank.setup" => {
            let a = parse!(SetupArgs);
            match setup(&a.path, &a.passphrase) {
                Ok(()) => ok(serde_json::json!({ "setup": a.path, "unlocked": true })),
                Err(e) => err(e),
            }
        }
        "tank.unlock" => {
            let a = parse!(SetupArgs);
            match unlock(&a.path, &a.passphrase) {
                Ok(()) => ok(serde_json::json!({ "unlocked": a.path })),
                Err(e) => err(e),
            }
        }
        "tank.lock" => {
            lock();
            ok(serde_json::json!({ "locked": true }))
        }
        "tank.set_path" => {
            let a = parse!(PathArgs);
            match set_path(&a.path) {
                Ok(()) => ok(serde_json::json!({ "path": a.path })),
                Err(e) => err(e),
            }
        }
        "tank.status" => ok(status()),
        "tank.blobs" => match blob_inventory() {
            Ok(blobs) => ok(serde_json::json!(blobs)),
            Err(e) => err(e),
        },
        "file.info" => {
            let a = parse!(PathArgs);
            match info_file(&a.path) {
                Ok(v) => ok(v),
                Err(e) => err(e),
            }
        }
        "file.encrypt" => {
            let a = parse!(PathArgs);
            match encrypt_file(&a.path) {
                Ok(v) => ok(v),
                Err(e) => err(e),
            }
        }
        "file.decrypt" => {
            let a = parse!(PathArgs);
            match decrypt_file(&a.path) {
                Ok(v) => ok(v),
                Err(e) => err(e),
            }
        }
        "file.delete" => {
            let a = parse!(PathArgs);
            match delete_file(&a.path) {
                Ok(v) => ok(v),
                Err(e) => err(e),
            }
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

/// Entry point FFI: `lumen_tank_call(method, json_args)` → JSON result string.
/// Caller must `lumen_tank_free` the returned pointer.
#[no_mangle]
pub unsafe extern "C" fn lumen_tank_call(method: *const c_char, args: *const c_char) -> *mut c_char {
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

/// Free a string returned by `lumen_tank_call`.
#[no_mangle]
pub unsafe extern "C" fn lumen_tank_free(ptr: *mut c_char) {
    unsafe {
        if !ptr.is_null() {
            let _ = CString::from_raw(ptr);
        }
    }
}