//! FFI interface for Lumen core

use std::ffi::{CStr, CString};
use std::os::raw::{c_char};
use crate::entry::JournalEntry;
use crate::storage::Storage;
use std::sync::Mutex;
use lazy_static::lazy_static;

lazy_static! {
    static ref STORAGE: Mutex<Storage> = Mutex::new(Storage::new());
}

#[no_mangle]
pub extern "C" fn lumen_add_entry(id: *const c_char, text: *const c_char, author: *const c_char, password: *const c_char) {
    let id = unsafe { CStr::from_ptr(id).to_string_lossy().into_owned() };
    let text = unsafe { CStr::from_ptr(text).to_string_lossy().into_owned() };
    let author = unsafe { CStr::from_ptr(author).to_string_lossy().into_owned() };
    let password = unsafe { CStr::from_ptr(password).to_string_lossy().into_owned() };
    let entry = JournalEntry::new(id, text, author, None, &password);
    STORAGE.lock().unwrap().add_entry(entry);
}

#[no_mangle]
pub extern "C" fn lumen_list_entries() -> *mut c_char {
    let storage = STORAGE.lock().unwrap();
    let titles: Vec<String> = storage.list_entries().iter().map(|e| e.id.clone()).collect();
    let joined = titles.join(",");
    CString::new(joined).unwrap().into_raw()
}

// Add more FFI functions as needed (e.g., decrypt, get entry text)
