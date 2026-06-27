use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Called when a new journal entry is created.
/// Receives the entry ID as a C string and returns optional feedback.
#[no_mangle]
pub unsafe extern "C" fn lumen_plugin_on_entry(entry_id: *const c_char) -> *mut c_char {
    let id = unsafe { CStr::from_ptr(entry_id) }
        .to_string_lossy()
        .into_owned();

    let feedback = format!("[example] Entry '{}' processed by example-plugin v0.1.0", id);

    CString::new(feedback).unwrap().into_raw()
}

/// Called when an entry is exported. Receives the entry ID and export format.
/// Returns a transformed version of the data, or NULL to pass through unchanged.
#[no_mangle]
pub unsafe extern "C" fn lumen_plugin_on_export(entry_id: *const c_char) -> *mut c_char {
    let id = unsafe { CStr::from_ptr(entry_id) }
        .to_string_lossy()
        .into_owned();

    let result = format!("[example] Export metadata for entry '{}'", id);

    CString::new(result).unwrap().into_raw()
}

/// Required: return the plugin's version string for provenance tracking.
#[no_mangle]
pub unsafe extern "C" fn lumen_plugin_version() -> *mut c_char {
    CString::new("0.1.0").unwrap().into_raw()
}
