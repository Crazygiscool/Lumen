//! fscore — Lumen file-system engine exposed over a single JSON dispatch FFI.
//!
//! All calls go through `fscore_call(method, json_args) -> json_result`.
//! The result envelope is `{ "ok": bool, "data": <value>, "error": <string> }`.

pub mod fs;
pub mod model;
pub mod system;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use model::*;

pub fn dispatch(method: &str, args: &serde_json::Value) -> serde_json::Value {
    let full = format!("{method}|{args}");
    let _ = full;
    macro_rules! parse {
        ($t:ty) => {
            match serde_json::from_value::<$t>(args.clone()) {
                Ok(v) => v,
                Err(e) => return err(format!("bad args for '{method}': {e}")),
            }
        };
    }

    let result = match method {
        // --- Filesystem ---
        "fs.list" => {
            let a = parse!(ListArgs);
            match fs::list_dir(&a.path, a.show_hidden) {
                Ok(entries) => serde_json::to_value(&entries).unwrap_or(err("serialize failed")),
                Err(e) => return err(e),
            }
        }
        "fs.stat" => {
            let a = parse!(StatArgs);
            match fs::stat_json(&a.path) {
                Ok(v) => v,
                Err(e) => return err(e),
            }
        }
        "fs.read" => {
            let a = parse!(ReadArgs);
            match fs::read_file_base64(&a.path, a.max_bytes) {
                Ok(v) => v,
                Err(e) => return err(e),
            }
        }
        "fs.write" => {
            let a = parse!(WriteArgs);
            if let Err(e) = fs::write_file(&a.path, &a.data) {
                return err(e);
            }
            serde_json::json!({ "written": true })
        }
        "fs.mkdir" => {
            let a = parse!(StatArgs);
            if let Err(e) = fs::create_dir(&a.path) {
                return err(e);
            }
            serde_json::json!({ "created": a.path })
        }
        "fs.rename" => {
            let a = parse!(MoveArgs);
            if let Err(e) = fs::rename(&a.from, &a.to) {
                return err(e);
            }
            serde_json::json!({ "from": a.from, "to": a.to })
        }
        "fs.copy" => {
            let a = parse!(MoveArgs);
            if let Err(e) = fs::copy(&a.from, &a.to) {
                return err(e);
            }
            serde_json::json!({ "from": a.from, "to": a.to })
        }
        "fs.trash" => {
            let a = parse!(StatArgs);
            if let Err(e) = fs::trash(&a.path) {
                return err(e);
            }
            serde_json::json!({ "trashed": a.path })
        }
        "fs.delete" => {
            let a = parse!(StatArgs);
            if let Err(e) = fs::delete(&a.path) {
                return err(e);
            }
            serde_json::json!({ "deleted": a.path })
        }
        "fs.search" => {
            let a = parse!(SearchArgs);
            match fs::search_names(&a.root, &a.query, a.show_hidden, a.max_results) {
                Ok(hits) => serde_json::json!(hits),
                Err(e) => return err(e),
            }
        }
        "fs.du" => {
            let a = parse!(DuArgs);
            match fs::du_tree_json(&a.path, a.max_depth) {
                Ok(v) => v,
                Err(e) => return err(e),
            }
        }

        // --- OS introspection (OS Lab) ---
        "sys.hardware" => system::hardware(),
        "sys.processes" => system::processes(),
        "sys.mounts" => system::mounts(),
        "sys.disks" => system::disks(),
        "sys.gtk" => system::gtk(),

        other => return err(format!("unknown method: {other}")),
    };

    ok(result)
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

/// Entry point FFI: `fscore_call(method, json_args)` → JSON result string.
/// The caller must `fscore_free` the returned pointer.
#[no_mangle]
pub unsafe extern "C" fn fscore_call(method: *const c_char, args: *const c_char) -> *mut c_char {
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

/// Free a string previously returned by `fscore_call`.
#[no_mangle]
pub unsafe extern "C" fn fscore_free(ptr: *mut c_char) {
    unsafe {
        if !ptr.is_null() {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::Engine;

    fn call(method: &str, args: serde_json::Value) -> serde_json::Value {
        dispatch(method, &args)
    }

    #[test]
    fn dispatch_unknown_method() {
        let r = call("nope", serde_json::json!({}));
        assert_eq!(r["ok"], false);
    }

    #[test]
    fn dispatch_bad_args() {
        let r = call("fs.list", serde_json::json!({}));
        assert_eq!(r["ok"], false);
    }

    #[test]
    fn dispatch_mkdir_and_write_and_read() {
        let tmp = std::env::temp_dir().join(format!("fscore_dispatch_{}", std::process::id()));
        let p = tmp.join("hello.txt").to_string_lossy().into_owned();

        let r = call("fs.mkdir", serde_json::json!({ "path": tmp }) );
        assert_eq!(r["ok"], true);

        let data = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, b"lumen");
        let r = call("fs.write", serde_json::json!({ "path": p, "data": data }));
        assert_eq!(r["ok"], true);

        let r = call("fs.read", serde_json::json!({ "path": p }));
        assert_eq!(r["ok"], true);
        let data = r["data"]["data"].as_str().unwrap();
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(data)
            .unwrap();
        assert_eq!(bytes, b"lumen");

        std::fs::remove_dir_all(&tmp).unwrap();
    }

    #[test]
    fn dispatch_system_returns_valid() {
        let r = call("sys.hardware", serde_json::json!({}));
        assert_eq!(r["ok"], true);
        assert!(r["data"]["cpu_count"].as_u64().unwrap() > 0);

        let r = call("sys.disks", serde_json::json!({}));
        assert_eq!(r["ok"], true);
    }

    #[test]
    fn dispatch_gtk_is_graceful() {
        // Must never error: on Linux it reflects gsettings (if present), otherwise
        // it reports available:false.
        let r = call("sys.gtk", serde_json::json!({}));
        assert_eq!(r["ok"], true);
        assert!(r["data"]["available"].is_boolean());
        let cs = r["data"]["color_scheme"].clone();
        assert!(cs.is_null() || cs.as_str().is_some());
    }
}