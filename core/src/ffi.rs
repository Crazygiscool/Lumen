use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::sync::Mutex;
use std::sync::Once;
use chrono::Utc;
use lazy_static::lazy_static;

use crate::auth;
use crate::entry::{EntryKind, JournalEntry};
use crate::storage::Storage;
use crate::sync::SyncBackend;

lazy_static! {
    static ref STORAGE: Mutex<Option<Storage>> = Mutex::new(None);
    static ref DATA_PATH: PathBuf = {
        let mut path = dirs::data_dir().unwrap_or_else(|| PathBuf::from("."));
        path.push("lumen");
        let _ = std::fs::create_dir_all(&path);
        path.push("lumen.db");
        path
    };
    static ref BIN_PATH: PathBuf = {
        let mut path = dirs::data_dir().unwrap_or_else(|| PathBuf::from("."));
        path.push("lumen");
        path.push("journal.bin");
        path
    };
}

fn ensure_loaded() {
    static INIT: Once = Once::new();
    INIT.call_once(|| {
        let path = DATA_PATH.as_path();
        let storage = Storage::new(path).expect("Failed to open lumen.db");

        // Migrate from bincode if journal.bin exists
        let bin_path = BIN_PATH.as_path();
        if bin_path.exists() {
            eprintln!("[lumen] Found journal.bin — migrating to SQLite...");
            if let Ok(old_entries) = migrate_old_bincode(bin_path) {
                for entry in &old_entries {
                    let _ = storage.add_entry(entry);
                }
                let mut backup = bin_path.to_path_buf();
                backup.set_extension("bin.migrated");
                let _ = std::fs::rename(bin_path, &backup);
                eprintln!("[lumen] Migrated {} entries to lumen.db", old_entries.len());
            }
        }

        // Process recurring tasks on startup
        if let Err(e) = crate::entry::recurring::process_recurring(&storage) {
            eprintln!("[lumen] Failed to process recurring tasks: {e}");
        }

        *STORAGE.lock().unwrap() = Some(storage);
    });
}

fn migrate_old_bincode(path: &std::path::Path) -> Result<Vec<JournalEntry>, String> {
    let mut file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let mut buffer = Vec::new();
    std::io::Read::read_to_end(&mut file, &mut buffer).map_err(|e| e.to_string())?;
    bincode::deserialize(&buffer).map_err(|e| e.to_string())
}

fn with_storage<F, T>(f: F) -> T
where
    F: FnOnce(&Storage) -> T,
{
    let guard = STORAGE.lock().unwrap();
    f(guard.as_ref().expect("Storage not initialized"))
}

unsafe fn c_str_to_owned(ptr: *const c_char) -> String {
    CStr::from_ptr(ptr).to_string_lossy().into_owned()
}

unsafe fn c_str_opt(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        None
    } else {
        let s = CStr::from_ptr(ptr).to_string_lossy().into_owned();
        if s.is_empty() { None } else { Some(s) }
    }
}

fn to_json<T: serde::Serialize>(val: &T) -> *mut c_char {
    let json = serde_json::to_string(val).unwrap_or_default();
    CString::new(json).unwrap_or_default().into_raw()
}

// ------------------------------------------------------------
// ADD ENTRY
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_add_entry(
    id: *const c_char,
    text: *const c_char,
    author: *const c_char,
    password: *const c_char,
    kind: *const c_char,
    tags_json: *const c_char,
    display_title: *const c_char,
) { unsafe {
    ensure_loaded();
    let id_raw = c_str_to_owned(id);
    let text = c_str_to_owned(text);
    let author = c_str_to_owned(author);
    let password = c_str_to_owned(password);
    let kind_str = c_str_to_owned(kind);
    let tags_str = c_str_to_owned(tags_json);
    let display_title_raw = c_str_to_owned(display_title);

    let id = if id_raw.is_empty() {
        let ts = Utc::now().timestamp();
        let rand_part: u32 = rand::random();
        format!("{}_{:08x}", ts, rand_part)
    } else {
        id_raw
    };
    let kind = EntryKind::from_str(&kind_str);
    let tags: Vec<String> = if tags_str.is_empty() {
        Vec::new()
    } else {
        serde_json::from_str(&tags_str).unwrap_or_default()
    };
    let entry = JournalEntry::new(id, text, author, None, &password, kind, tags, display_title_raw);
    if let Err(e) = with_storage(|s| s.add_entry(&entry)) {
        eprintln!("[lumen] Failed to add entry: {e}");
    }
}}

// ------------------------------------------------------------
// LIST ENTRIES (JSON)
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_list_entries() -> *mut c_char {
    ensure_loaded();
    let entries = with_storage(|s| s.list_entries().unwrap_or_default());
    to_json(&entries)
}

// ------------------------------------------------------------
// GET SINGLE ENTRY BY ID
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_get_entry(id: *const c_char) -> *mut c_char {
    ensure_loaded();
    let id = unsafe { c_str_to_owned(id) };
    let entry = with_storage(|s| s.get_entry(&id).ok().flatten());
    to_json(&entry)
}

// ------------------------------------------------------------
// UPDATE ENTRY
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_update_entry(
    id: *const c_char,
    text: *const c_char,
    author: *const c_char,
    password: *const c_char,
    kind: *const c_char,
    tags_json: *const c_char,
    display_title: *const c_char,
) { unsafe {
    ensure_loaded();
    let id = c_str_to_owned(id);
    let text = c_str_to_owned(text);
    let author = c_str_to_owned(author);
    let password = c_str_to_owned(password);
    let kind_str = c_str_to_owned(kind);
    let tags_str = c_str_to_owned(tags_json);
    let display_title_raw = c_str_to_owned(display_title);

    // Fetch existing entry to preserve creation timestamp + history
    let old_entry = with_storage(|s| s.get_entry(&id).ok().flatten());
    let entry = if let Some(old) = old_entry {
        let key = crate::entry::encryption::derive_key(&password, &old.salt);
        let (encrypted, nonce) = crate::entry::encryption::encrypt(text.as_bytes(), &key);
        let mut updated = JournalEntry {
            encrypted,
            nonce,
            ..old
        };
        updated.provenance.author = author.clone();
        updated.provenance.timestamp = Utc::now();
        updated.kind = EntryKind::from_str(&kind_str);
        updated.tags = if tags_str.is_empty() {
            Vec::new()
        } else {
            serde_json::from_str(&tags_str).unwrap_or_default()
        };
        updated.display_title = display_title_raw;
        updated.history.push(crate::entry::EditRecord {
            timestamp: Utc::now(),
            author,
            reason: "Updated".to_string(),
        });
        updated
    } else {
        eprintln!("[lumen] Entry {id} not found for update");
        return;
    };

    // If mood/priority/status etc. are passed as additional params, they'd go here
    // For now, preserve existing values

    if let Err(e) = with_storage(|s| s.update_entry(&entry)) {
        eprintln!("[lumen] Failed to update entry: {e}");
    }
}}

// ------------------------------------------------------------
// SET ENTRY MOOD (metadata-only, no password needed)
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_set_entry_mood(id: *const c_char, mood: *const c_char) {
    ensure_loaded();
    let id = unsafe { c_str_to_owned(id) };
    let mood_opt = unsafe {
        if mood.is_null() {
            None
        } else {
            let s = CStr::from_ptr(mood).to_string_lossy().into_owned();
            if s.is_empty() { None } else { Some(s) }
        }
    };
    if let Err(e) = with_storage(|s| s.set_entry_mood(&id, mood_opt.as_deref())) {
        eprintln!("[lumen] Failed to set entry mood: {e}");
    }
}

// ------------------------------------------------------------
// SET ENTRY STATUS (metadata-only, no password needed)
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_set_entry_status(id: *const c_char, status: *const c_char) {
    ensure_loaded();
    let id = unsafe { c_str_to_owned(id) };
    let status = unsafe { c_str_to_owned(status) };
    if let Err(e) = with_storage(|s| s.set_entry_status(&id, &status)) {
        eprintln!("[lumen] Failed to set entry status: {e}");
    }
}

// ------------------------------------------------------------
// DELETE ENTRY
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_delete_entry(id: *const c_char) {
    ensure_loaded();
    let id = unsafe { c_str_to_owned(id) };
    if let Err(e) = with_storage(|s| s.delete_entry(&id)) {
        eprintln!("[lumen] Failed to delete entry: {e}");
    }
}

// ------------------------------------------------------------
// FOLDER OPERATIONS
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_list_folders() -> *mut c_char {
    ensure_loaded();
    let folders = with_storage(|s| s.list_folders().unwrap_or_default());
    to_json(&folders)
}

#[no_mangle]
pub unsafe extern "C" fn lumen_create_folder(
    name: *const c_char,
    parent_id: *const c_char,
) -> *mut c_char {
    ensure_loaded();
    let name = unsafe { c_str_to_owned(name) };
    let parent = unsafe { c_str_opt(parent_id) };
    let id = with_storage(|s| s.create_folder(&name, parent.as_deref()).unwrap_or_default());
    CString::new(id).unwrap_or_default().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn lumen_delete_folder(id: *const c_char) {
    ensure_loaded();
    let id = unsafe { c_str_to_owned(id) };
    if let Err(e) = with_storage(|s| s.delete_folder(&id)) {
        eprintln!("[lumen] Failed to delete folder: {e}");
    }
}

#[no_mangle]
pub unsafe extern "C" fn lumen_move_to_folder(
    entry_id: *const c_char,
    folder_id: *const c_char,
) {
    ensure_loaded();
    let entry_id = unsafe { c_str_to_owned(entry_id) };
    let folder = unsafe { c_str_opt(folder_id) };
    if let Err(e) = with_storage(|s| s.move_to_folder(&entry_id, folder.as_deref())) {
        eprintln!("[lumen] Failed to move entry: {e}");
    }
}

// ------------------------------------------------------------
// TOGGLE PIN
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_toggle_pin(entry_id: *const c_char) -> i32 {
    ensure_loaded();
    let entry_id = unsafe { c_str_to_owned(entry_id) };
    with_storage(|s| s.toggle_pin(&entry_id).unwrap_or(false)) as i32
}

// ------------------------------------------------------------
// SEARCH ENTRIES
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_search_entries(query: *const c_char) -> *mut c_char {
    ensure_loaded();
    let query = unsafe { c_str_to_owned(query) };
    let entries = with_storage(|s| s.search_entries(&query).unwrap_or_default());
    to_json(&entries)
}

// ------------------------------------------------------------
// GET STREAK
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_get_streak() -> u32 {
    ensure_loaded();
    with_storage(|s| s.get_streak().unwrap_or(0))
}

// ------------------------------------------------------------
// ASSET MANAGEMENT
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_add_asset(
    entry_id: *const c_char,
    file_name: *const c_char,
    mime_type: *const c_char,
    base64_data: *const c_char,
    password: *const c_char,
) -> *mut c_char { unsafe {
    ensure_loaded();
    let entry_id = c_str_to_owned(entry_id);
    let file_name = c_str_to_owned(file_name);
    let mime_type = c_str_to_owned(mime_type);
    let b64 = c_str_to_owned(base64_data);
    let password = c_str_to_owned(password);

    use base64::Engine;
    let plaintext = match base64::engine::general_purpose::STANDARD.decode(&b64) {
        Ok(d) => d,
        Err(e) => return to_json(&serde_json::json!({"error": format!("base64 decode: {e}")})),
    };

    let salt: [u8; 16] = rand::random();
    let key = crate::entry::encryption::derive_key(&password, &salt);
    let (encrypted_data, nonce) = crate::entry::encryption::encrypt(&plaintext, &key);

    let ts = chrono::Utc::now().timestamp();
    let rand_part: u32 = rand::random();
    let asset_id = format!("{}_{:08x}", ts, rand_part);

    let asset = crate::entry::EntryAsset {
        id: asset_id.clone(),
        entry_id,
        file_name,
        mime_type,
        encrypted_size: encrypted_data.len() as u64,
        nonce,
        salt: salt.to_vec(),
        encrypted_data,
        created_at: chrono::Utc::now(),
    };

    if let Err(e) = with_storage(|s| s.add_asset(&asset)) {
        return to_json(&serde_json::json!({"error": e}));
    }

    to_json(&serde_json::json!({"id": asset_id}))
}}

#[no_mangle]
pub unsafe extern "C" fn lumen_get_assets(entry_id: *const c_char) -> *mut c_char {
    ensure_loaded();
    let entry_id = unsafe { c_str_to_owned(entry_id) };
    let assets = with_storage(|s| s.get_assets_for_entry(&entry_id).unwrap_or_default());
    // Return metadata only (exclude encrypted payload)
    let list: Vec<serde_json::Value> = assets.iter().map(|a| {
        serde_json::json!({
            "id": a.id,
            "file_name": a.file_name,
            "mime_type": a.mime_type,
            "encrypted_size": a.encrypted_size,
            "created_at": a.created_at.to_rfc3339(),
        })
    }).collect();
    to_json(&list)
}

#[no_mangle]
pub unsafe extern "C" fn lumen_get_asset_data(asset_id: *const c_char, password: *const c_char) -> *mut c_char { unsafe {
    ensure_loaded();
    let asset_id = c_str_to_owned(asset_id);
    let password = c_str_to_owned(password);

    let asset = match with_storage(|s| s.get_asset(&asset_id).ok().flatten()) {
        Some(a) => a,
        None => return to_json(&serde_json::json!({"error": "Asset not found"})),
    };

    let key = crate::entry::encryption::derive_key(&password, &asset.salt);
    let plaintext = match crate::entry::encryption::decrypt(&asset.encrypted_data, &asset.nonce, &key) {
        Ok(d) => d,
        Err(e) => return to_json(&serde_json::json!({"error": e})),
    };

    use base64::Engine;
    let b64 = base64::engine::general_purpose::STANDARD.encode(&plaintext);
    to_json(&serde_json::json!({"data": b64, "mime_type": asset.mime_type, "file_name": asset.file_name}))
}}

// ------------------------------------------------------------
// STOIC IMPORT
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_import_stoic(
    export_dir: *const c_char,
    password: *const c_char,
) -> i32 { unsafe {
    ensure_loaded();
    let export_dir = c_str_to_owned(export_dir);
    let password = c_str_to_owned(password);
    with_storage(|s| crate::import_stoic::import_stoic(&export_dir, &password, s))
}}

// ------------------------------------------------------------
// DECRYPT ENTRY
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_decrypt_entry(
    id: *const c_char,
    password: *const c_char,
) -> *mut c_char { unsafe {
    ensure_loaded();
    let id = c_str_to_owned(id);
    let password = c_str_to_owned(password);

    let entry = with_storage(|s| s.get_entry(&id).ok().flatten());
    let decrypted = match entry {
        Some(e) => e.decrypt_text(&password),
        None => "ERROR: Entry not found".to_string(),
    };
    CString::new(decrypted).unwrap_or_else(|_| CString::new("ERROR: invalid decrypted string").unwrap()).into_raw()
}}

// ------------------------------------------------------------
// EXPORT PROJECT (decrypts all child tasks → Markdown)
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_export_project(
    project_id: *const c_char,
    password: *const c_char,
) -> *mut c_char {
    ensure_loaded();
    let project_id = unsafe { c_str_to_owned(project_id) };
    let password = unsafe { c_str_to_owned(password) };

    let all_entries = with_storage(|s| s.list_entries().unwrap_or_default());
    let project = all_entries.iter().find(|e| e.id == project_id);
    let project_title = project
        .map(|p| p.display_title.clone())
        .unwrap_or_else(|| project_id.clone());

    let child_entries: Vec<&JournalEntry> = all_entries
        .iter()
        .filter(|e| e.parent_project_id.as_deref() == Some(&project_id))
        .collect();

    let mut md = format!("# {}\n\n", project_title);

    for entry in &child_entries {
        let body = entry.decrypt_text(&password);
        let title = if entry.display_title.is_empty() {
            &entry.id
        } else {
            &entry.display_title
        };
        md.push_str(&format!("## {}\n\n", title));
        md.push_str(&body);
        md.push('\n');
    }

    CString::new(md).unwrap_or_default().into_raw()
}

// ------------------------------------------------------------
// PARSE TASK (natural language → JSON)
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_parse_task(text: *const c_char) -> *mut c_char {
    let input = unsafe { c_str_to_owned(text) };

    let mut title_parts = Vec::new();
    let mut priority: Option<String> = None;
    let mut due_date: Option<String> = None;
    let mut tags: Vec<String> = Vec::new();

    for token in input.split_whitespace() {
        if let Some(val) = token.strip_prefix("p:") {
            priority = Some(val.to_lowercase());
        } else if let Some(val) = token.strip_prefix("priority:") {
            priority = Some(val.to_lowercase());
        } else if let Some(val) = token.strip_prefix("due:") {
            due_date = parse_due_date(val);
        } else if let Some(tag) = token.strip_prefix('#') {
            tags.push(tag.to_string());
        } else {
            title_parts.push(token.to_string());
        }
    }

    let result = serde_json::json!({
        "title": title_parts.join(" "),
        "priority": priority,
        "due_date": due_date,
        "tags": tags,
    });

    let json = result.to_string();
    CString::new(json).unwrap_or_default().into_raw()
}

fn parse_due_date(val: &str) -> Option<String> {
    use chrono::Datelike;
    use chrono::NaiveDate;
    use chrono::Duration;

    let today = Utc::now().date_naive();

    // Try direct date parse: YYYY-MM-DD
    if let Ok(d) = NaiveDate::parse_from_str(val, "%Y-%m-%d") {
        return Some(d.to_string());
    }

    // Try day names
    let weekday = match val.to_lowercase().as_str() {
        "monday" | "mon" => Some(chrono::Weekday::Mon),
        "tuesday" | "tue" => Some(chrono::Weekday::Tue),
        "wednesday" | "wed" => Some(chrono::Weekday::Wed),
        "thursday" | "thu" => Some(chrono::Weekday::Thu),
        "friday" | "fri" => Some(chrono::Weekday::Fri),
        "saturday" | "sat" => Some(chrono::Weekday::Sat),
        "sunday" | "sun" => Some(chrono::Weekday::Sun),
        _ => None,
    };
    if let Some(wd) = weekday {
        let days_ahead = (wd.num_days_from_monday() as i32
            - today.weekday().num_days_from_monday() as i32
            + 7) % 7;
        let days_ahead = if days_ahead == 0 { 7 } else { days_ahead };
        return today
            .checked_add_signed(Duration::days(days_ahead as i64))
            .map(|d| d.to_string());
    }

    // Relative keywords
    match val.to_lowercase().as_str() {
        "today" => Some(today.to_string()),
        "tomorrow" => today.checked_add_signed(Duration::days(1)).map(|d| d.to_string()),
        "next week" => today.checked_add_signed(Duration::days(7)).map(|d| d.to_string()),
        _ => None,
    }
}

// ------------------------------------------------------------
// EXPORT ALL (JSON array of decrypted entries)
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_export_all(password: *const c_char) -> *mut c_char {
    ensure_loaded();
    let password = unsafe { c_str_to_owned(password) };
    let entries = with_storage(|s| s.list_entries().unwrap_or_default());

    let exported: Vec<serde_json::Value> = entries
        .iter()
        .map(|e| {
            let body = e.decrypt_text(&password);
            serde_json::json!({
                "id": e.id,
                "kind": e.kind.as_str(),
                "body": body,
                "tags": e.tags,
                "display_title": e.display_title,
                "author": e.provenance.author,
                "timestamp": e.provenance.timestamp.to_rfc3339(),
                "mood": e.mood,
                "priority": e.priority,
                "status": e.status,
                "due_date": e.due_date,
                "parent_project_id": e.parent_project_id,
            })
        })
        .collect();

    to_json(&exported)
}

// ------------------------------------------------------------
// IMPORT (batch insert from JSON array)
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_import(json: *const c_char) -> i32 {
    ensure_loaded();
    let json_str = unsafe { c_str_to_owned(json) };

    let entries: Vec<JournalEntry> = match serde_json::from_str(&json_str) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("[lumen] Failed to parse import JSON: {e}");
            return 0;
        }
    };

    match with_storage(|s| s.import_entries(&entries)) {
        Ok(count) => count as i32,
        Err(e) => {
            eprintln!("[lumen] Import failed: {e}");
            0
        }
    }
}

// ------------------------------------------------------------
// AUTH — password set, unlock, lock
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_has_password() -> i32 {
    if auth::has_password() { 1 } else { 0 }
}

#[no_mangle]
pub unsafe extern "C" fn lumen_set_password(password: *const c_char) -> i32 {
    let password = unsafe { c_str_to_owned(password) };
    match auth::set_password(&password) {
        Ok(()) => 1,
        Err(e) => {
            eprintln!("[lumen] Failed to set password: {e}");
            0
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn lumen_unlock(password: *const c_char) -> i32 {
    let password = unsafe { c_str_to_owned(password) };
    if auth::unlock(&password) { 1 } else { 0 }
}

#[no_mangle]
pub unsafe extern "C" fn lumen_lock() -> i32 {
    auth::lock();
    1
}

#[no_mangle]
pub unsafe extern "C" fn lumen_is_unlocked() -> i32 {
    if auth::is_unlocked() { 1 } else { 0 }
}

// ------------------------------------------------------------
// VAULTS
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_list_vaults() -> *mut c_char {
    let mut vaults: Vec<String> = Vec::new();
    if let Some(data_dir) = dirs::data_dir() {
        let lumen_dir = data_dir.join("lumen");
        if let Ok(entries) = std::fs::read_dir(&lumen_dir) {
            for entry in entries.flatten() {
                let vault_path = entry.path();
                if vault_path.is_dir() && vault_path.join("lumen.db").exists() {
                    if let Some(name) = vault_path.file_name() {
                        vaults.push(name.to_string_lossy().to_string());
                    }
                }
            }
        }
    }
    to_json(&vaults)
}

#[no_mangle]
pub unsafe extern "C" fn lumen_open_vault(name: *const c_char) -> i32 {
    let name = unsafe { c_str_to_owned(name) };
    let data_dir = match dirs::data_dir() {
        Some(d) => d,
        None => {
            eprintln!("[lumen] Cannot find data directory");
            return 0;
        }
    };
    let vault_dir = data_dir.join("lumen").join(&name);
    if let Err(e) = std::fs::create_dir_all(&vault_dir) {
        eprintln!("[lumen] Cannot create vault directory: {e}");
        return 0;
    }
    let db_path = vault_dir.join("lumen.db");
    match Storage::new(&db_path) {
        Ok(storage) => {
            if let Ok(mut guard) = STORAGE.lock() {
                *guard = Some(storage);
            }
            1
        }
        Err(e) => {
            eprintln!("[lumen] Failed to open vault '{name}': {e}");
            0
        }
    }
}

// ------------------------------------------------------------
// SYNC
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_sync_push(
    sync_db_path: *const c_char,
    entry_ids_json: *const c_char,
) -> i32 {
    ensure_loaded();
    let path = unsafe { c_str_to_owned(sync_db_path) };
    let ids_json = unsafe { c_str_to_owned(entry_ids_json) };

    let sync = match crate::sync::local_sqlite::LocalSqliteSync::open(&std::path::Path::new(&path))
    {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[lumen] Failed to open sync DB: {e}");
            return -1;
        }
    };

    let entry_ids: Vec<String> = match serde_json::from_str(&ids_json) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("[lumen] Invalid entry_ids JSON: {e}");
            return -1;
        }
    };

    // Fetch entries from primary storage
    let entries: Vec<JournalEntry> = with_storage(|s| {
        entry_ids
            .iter()
            .filter_map(|id| s.get_entry(id).ok().flatten())
            .collect()
    });

    match sync.push(&entries) {
        Ok(count) => count as i32,
        Err(e) => {
            eprintln!("[lumen] Sync push failed: {e}");
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn lumen_sync_pull(sync_db_path: *const c_char) -> *mut c_char {
    let path = unsafe { c_str_to_owned(sync_db_path) };

    let sync = match crate::sync::local_sqlite::LocalSqliteSync::open(&std::path::Path::new(&path))
    {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[lumen] Failed to open sync DB: {e}");
            return std::ptr::null_mut();
        }
    };

    match sync.pull() {
        Ok(entries) => to_json(&entries),
        Err(e) => {
            eprintln!("[lumen] Sync pull failed: {e}");
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn lumen_sync_list_conflicts(sync_db_path: *const c_char) -> *mut c_char {
    let path = unsafe { c_str_to_owned(sync_db_path) };

    let sync = match crate::sync::local_sqlite::LocalSqliteSync::open(&std::path::Path::new(&path))
    {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[lumen] Failed to open sync DB: {e}");
            return to_json(&serde_json::json!([]));
        }
    };

    match sync.list_conflicts() {
        Ok(conflicts) => to_json(&conflicts),
        Err(e) => {
            eprintln!("[lumen] Failed to list conflicts: {e}");
            to_json(&serde_json::json!([]))
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn lumen_sync_accept_conflict(
    sync_db_path: *const c_char,
    conflict_id: *const c_char,
    keep_local: i32,
) -> i32 { unsafe {
    let path = c_str_to_owned(sync_db_path);
    let cid = c_str_to_owned(conflict_id);

    let sync = match crate::sync::local_sqlite::LocalSqliteSync::open(&std::path::Path::new(&path))
    {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[lumen] Failed to open sync DB: {e}");
            return -1;
        }
    };

    match sync.accept_conflict(&cid, keep_local != 0) {
        Ok(()) => 1,
        Err(e) => {
            eprintln!("[lumen] Failed to accept conflict: {e}");
            0
        }
    }
}}

// ------------------------------------------------------------
// FREE STRING
// ------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn lumen_free_string(s: *mut c_char) { unsafe {
    if !s.is_null() {
        let _ = CString::from_raw(s);
    }
}}
