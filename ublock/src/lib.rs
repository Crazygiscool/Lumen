//! ublock — Lumen's ad-blocking rule engine.
//!
//! Consumes uBlock Origin / Adblock Plus filter lists and compiles the subset
//! faithfully representable as WebKit content-rule JSON (the mechanism behind
//! Safari content blockers and GNOME Web / Epiphany's ad blocker), enforcing
//! WebKit's per-store rule and "ability" caps by splitting into parts.
//!
//! Exposed over a single JSON dispatch FFI identical in shape to fscore:
//!   `ublock_call(method, json_args) -> json_result`, freed by `ublock_free`.

mod compile;
mod convert;
mod filter;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use crate::compile::ListInput;

pub fn dispatch(method: &str, args: &serde_json::Value) -> serde_json::Value {
    match method {
        "ublock.compile" => {
            let lists: Vec<serde_json::Value> = match args.get("lists") {
                Some(serde_json::Value::Array(l)) => l.clone(),
                _ => {
                    return err("'lists' must be an array of {name, text}".to_string());
                }
            };
            let max_rules = args
                .get("max_rules_per_part")
                .and_then(serde_json::Value::as_u64)
                .map(|v| v as usize);

            let inputs: Vec<ListInput> = {
                let mut v = Vec::with_capacity(lists.len());
                for l in &lists {
                    let text = l.get("text").and_then(|s| s.as_str()).unwrap_or("");
                    v.push(ListInput { text });
                }
                v
            };

            match compile::compile(&inputs, max_rules) {
                Ok(c) => ok(serde_json::json!({
                    "parts": c.parts,
                    "stats": compile::stats_json(&c.stats),
                })),
                Err(e) => err(e),
            }
        }

        "ublock.version" => ok(serde_json::json!({
            "version": env!("CARGO_PKG_VERSION"),
        })),

        other => err(format!("unknown method: {other}")),
    }
}

fn ok(data: serde_json::Value) -> serde_json::Value {
    serde_json::json!({ "ok": true, "data": data })
}

fn err(msg: String) -> serde_json::Value {
    serde_json::json!({ "ok": false, "error": msg })
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

/// Entry point FFI: `ublock_call(method, json_args)` → JSON result string.
/// The caller must `ublock_free` the returned pointer.
#[no_mangle]
pub unsafe extern "C" fn ublock_call(
    method: *const c_char,
    args: *const c_char,
) -> *mut c_char {
    let method = unsafe { c_to_string(method) };
    let args_str = unsafe { c_to_string(args) };
    let args: serde_json::Value = if args_str.is_empty() {
        serde_json::json!({})
    } else {
        serde_json::from_str(&args_str).unwrap_or_else(|_| serde_json::json!({}))
    };
    let result = dispatch(&method, &args).to_string();
    string_to_cptr(result)
}

/// Free a string previously returned by `ublock_call`.
#[no_mangle]
pub unsafe extern "C" fn ublock_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = CString::from_raw(ptr);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn call(method: &str, args: serde_json::Value) -> serde_json::Value {
        dispatch(method, &args)
    }

    #[test]
    fn version() {
        let r = call("ublock.version", serde_json::json!({}));
        assert_eq!(r["ok"], true);
        assert!(r["data"]["version"].as_str().is_some());
    }

    #[test]
    fn unknown_method() {
        let r = call("nope", serde_json::json!({}));
        assert_eq!(r["ok"], false);
    }

    #[test]
    fn compile_end_to_end() {
        let lists = serde_json::json!([
            {
                "name": "t",
                "text": "||ads.example.com^$script\n##.ad\n@@||safe.example.com\n"
            }
        ]);
        let r = call(
            "ublock.compile",
            serde_json::json!({ "lists": lists, "max_rules_per_part": 100 }),
        );
        assert_eq!(r["ok"], true);
        let parts = r["data"]["parts"].as_array().unwrap();
        assert_eq!(parts.len(), 1);
        let stats = &r["data"]["stats"];
        assert_eq!(stats["network_blocked"], 1);
        assert_eq!(stats["cosmetic"], 1);
        assert_eq!(stats["exceptions"], 1);
    }

    #[test]
    fn compile_rejects_bad_args() {
        let r = call("ublock.compile", serde_json::json!({}));
        assert_eq!(r["ok"], false);
    }
}