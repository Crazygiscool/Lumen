//! FFI interface for Lumen core

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Mutex;
use lazy_static::lazy_static;

use crate::entry::JournalEntry;
use crate::storage::Storage;

lazy_static! {
    static ref STORAGE: Mutex<Storage> = Mutex::new(Storage::new());
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
) {
    let id = CStr::from_ptr(id).to_string_lossy().into_owned();
    let text = CStr::from_ptr(text).to_string_lossy().into_owned();
    let author = CStr::from_ptr(author).to_string_lossy().into_owned();
    let password = CStr::from_ptr(password).to_string_lossy().into_owned();

    let entry = JournalEntry::new(id, text, author, None, &password);
    STORAGE.lock().unwrap().add_entry(entry);
}

// ------------------------------------------------------------
// LIST ENTRIES (JSON)
// ------------------------------------------------------------
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumen_list_entries() -> *mut c_char {
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
) -> *mut c_char {
    let id = CStr::from_ptr(id).to_string_lossy().into_owned();
    let password = CStr::from_ptr(password).to_string_lossy().into_owned();

    let storage = STORAGE.lock().unwrap();
    let entries = storage.list_entries();
    let entry = entries.iter().find(|e| e.id == id).unwrap();

    let decrypted = entry.decrypt_text(&password);
    CString::new(decrypted).unwrap().into_raw()
}

// ------------------------------------------------------------
// FREE STRING
// ------------------------------------------------------------
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumen_free_string(s: *mut c_char) {
    if !s.is_null() {
        let _ = CString::from_raw(s);
    }
}
