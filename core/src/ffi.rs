//! FFI interface for Lumen core

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::sync::Mutex;
use std::sync::Once;
use lazy_static::lazy_static;

use crate::entry::JournalEntry;
use crate::storage::Storage;

lazy_static! {
    static ref STORAGE: Mutex<Storage> = Mutex::new(Storage::new());
    static ref DATA_PATH: PathBuf = {
        let mut path = dirs::data_dir().unwrap_or_else(|| PathBuf::from("."));
        path.push("lumen");
        let _ = std::fs::create_dir_all(&path);
        path.push("journal.bin");
        path
    };
}

fn ensure_loaded() {
    static INIT: Once = Once::new();
    INIT.call_once(|| {
        let path = DATA_PATH.as_path();
        if path.exists() {
            let mut storage = STORAGE.lock().unwrap();
            if let Err(e) = storage.load_from_file(path) {
                eprintln!("[lumen] Failed to load journal: {e}");
            }
        }
    });
}

// ------------------------------------------------------------
// ADD ENTRY
// ------------------------------------------------------------
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumen_add_entry(
    id: *const c_char,
    text: *const c_char,
    author: *const c_char,
    password: *const c_char,
) { unsafe {
    let id = CStr::from_ptr(id).to_string_lossy().into_owned();
    let text = CStr::from_ptr(text).to_string_lossy().into_owned();
    let author = CStr::from_ptr(author).to_string_lossy().into_owned();
    let password = CStr::from_ptr(password).to_string_lossy().into_owned();

    ensure_loaded();
    let entry = JournalEntry::new(id, text, author, None, &password);
    STORAGE.lock().unwrap().add_entry(entry);

    if let Err(e) = STORAGE.lock().unwrap().save_to_file(DATA_PATH.as_path()) {
        eprintln!("[lumen] Failed to save journal: {e}");
    }
}}

// ------------------------------------------------------------
// LIST ENTRIES (JSON)
// ------------------------------------------------------------
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumen_list_entries() -> *mut c_char {
    ensure_loaded();
    let storage = STORAGE.lock().unwrap();
    let entries = storage.list_entries();

    let json = serde_json::to_string(&entries).unwrap();
    CString::new(json).unwrap().into_raw()
}

// ------------------------------------------------------------
// DECRYPT ENTRY
// ------------------------------------------------------------
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumen_decrypt_entry(
    id: *const c_char,
    password: *const c_char,
) -> *mut c_char { unsafe {
    let id = CStr::from_ptr(id).to_string_lossy().into_owned();
    let password = CStr::from_ptr(password).to_string_lossy().into_owned();

    ensure_loaded();
    let storage = STORAGE.lock().unwrap();
    let entries = storage.list_entries();
    let entry = entries.iter().find(|e| e.id == id).unwrap();

    let decrypted = entry.decrypt_text(&password);
    // Return decrypted text or an error message back to caller; avoid panics
    let out = CString::new(decrypted).unwrap_or_else(|_| CString::new("ERROR: invalid decrypted string").unwrap());
    out.into_raw()
}}

// ------------------------------------------------------------
// FREE STRING
// ------------------------------------------------------------
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumen_free_string(s: *mut c_char) { unsafe {
    if !s.is_null() {
        let _ = CString::from_raw(s);
    }
}}
