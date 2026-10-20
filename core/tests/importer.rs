//! Integration coverage for importers writing into the encrypted journal.
//!
//! Kept as a separate test binary so it does not share the process-global
//! vault map with the unit tests.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard};

use lumen_core::importer;
use lumen_core::vault::{self, STORE_JOURNAL};

// The vault registry is process-global and keyed by store name, so tests in
// this binary must not unlock two different journal roots at the same time.
static LOCK: Mutex<()> = Mutex::new(());

fn test_lock() -> MutexGuard<'static, ()> {
    LOCK.lock().unwrap_or_else(|e| e.into_inner())
}

fn temp_path(name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("lumen_import_{name}_{}", std::process::id()));
    let _ = fs::remove_dir_all(&path);
    path
}

fn unlocked_journal(root: &Path) {
    let root = root.to_str().unwrap();
    vault::create_with_passphrase(root, "hunter2hunter2", STORE_JOURNAL).unwrap();
    vault::unlock(root, "hunter2hunter2", STORE_JOURNAL).unwrap();
}

fn markdown_entries() -> Vec<String> {
    vault::list("", STORE_JOURNAL)
        .unwrap()
        .into_iter()
        .filter(|e| !e.is_dir && e.name.ends_with(".md"))
        .map(|e| e.rel_path)
        .collect()
}

#[test]
fn imports_json_and_markdown_into_encrypted_journal() {
    let _guard = test_lock();
    let root = temp_path("store");
    fs::create_dir_all(&root).unwrap();
    unlocked_journal(&root);

    let source = temp_path("source");
    fs::create_dir_all(source.join("nested")).unwrap();
    let json = source.join("backup.json");
    fs::write(
        &json,
        r#"[
            {
              "display_title": "First entry",
              "body": "Hello from JSON",
              "timestamp": "2026-02-03T10:00:00Z"
            }
        ]"#,
    )
    .unwrap();
    fs::write(source.join("nested/note.md"), "# Nested\n\nMarkdown body").unwrap();

    let json_result = importer::import_json(json.to_str().unwrap(), STORE_JOURNAL).unwrap();
    assert_eq!(json_result.imported, 1);

    let md_result = importer::import_markdown_dir(source.to_str().unwrap(), STORE_JOURNAL).unwrap();
    assert_eq!(md_result.imported, 1);

    let entries = markdown_entries();
    assert_eq!(entries.len(), 2, "entries: {entries:?}");

    let json_name = entries
        .iter()
        .find(|p| p.starts_with("2026-02-03"))
        .expect("dated JSON entry");
    let text = vault::read_text(json_name, STORE_JOURNAL).unwrap();
    assert!(text.contains("# First entry"));
    assert!(text.contains("Hello from JSON"));

    let nested = entries
        .iter()
        .find(|p| p.contains("imported/nested/note.md"))
        .expect("nested markdown entry");
    assert!(vault::read_text(nested, STORE_JOURNAL)
        .unwrap()
        .contains("Markdown body"));

    // The ciphertext on disk must not contain the imported plaintext.
    let on_disk = fs::read(root.join(json_name)).unwrap();
    let raw = String::from_utf8_lossy(&on_disk);
    assert!(!raw.contains("Hello from JSON"));

    let _ = fs::remove_dir_all(&root);
    let _ = fs::remove_dir_all(&source);
}

#[test]
fn imports_single_json_object_and_file_map() {
    let _guard = test_lock();
    let root = temp_path("json_shapes_store");
    fs::create_dir_all(&root).unwrap();
    unlocked_journal(&root);

    let source = temp_path("json_shapes_source");
    fs::create_dir_all(&source).unwrap();

    let single = source.join("single.json");
    fs::write(
        &single,
        r#"{ "title": "Single note", "body": "Solo body", "date": "2026-04-05" }"#,
    )
    .unwrap();
    let result = importer::import_json(single.to_str().unwrap(), STORE_JOURNAL).unwrap();
    assert_eq!(result.imported, 1);
    let entries = markdown_entries();
    let single_path = entries
        .iter()
        .find(|p| p.starts_with("2026-04-05-single-note"))
        .expect("single object entry");
    let text = vault::read_text(single_path, STORE_JOURNAL).unwrap();
    assert!(text.contains("# Single note"));
    assert!(text.contains("Solo body"));

    let map = source.join("map.json");
    fs::write(&map, r##"{ "custom.md": "# Custom\n\nMap body" }"##).unwrap();
    let result = importer::import_json(map.to_str().unwrap(), STORE_JOURNAL).unwrap();
    assert_eq!(result.imported, 1);
    assert!(vault::read_text("custom.md", STORE_JOURNAL)
        .unwrap()
        .contains("Map body"));

    let _ = fs::remove_dir_all(&root);
    let _ = fs::remove_dir_all(&source);
}

#[test]
fn imports_stoic_export_folder() {
    let _guard = test_lock();
    let root = temp_path("stoic_store");
    fs::create_dir_all(&root).unwrap();
    unlocked_journal(&root);

    let source = temp_path("stoic_source");
    fs::create_dir_all(&source).unwrap();
    fs::write(
        source.join("journal-entries.json"),
        r#"[
            {
              "uuid": "abcd1234-0000-0000-0000-000000000000",
              "timestamp": 0,
              "calendarDate": "03/02/2026",
              "text": "A Stoic reflection."
            }
        ]"#,
    )
    .unwrap();

    let result = importer::import_stoic(source.to_str().unwrap(), STORE_JOURNAL).unwrap();
    assert_eq!(result.imported, 1);

    let entries = markdown_entries();
    let path = entries
        .iter()
        .find(|p| p.starts_with("2026-02-03-stoic"))
        .expect("stoic entry filename");
    let text = vault::read_text(path, STORE_JOURNAL).unwrap();
    assert!(text.contains("Stoic Entry"));
    assert!(text.contains("A Stoic reflection."));

    let _ = fs::remove_dir_all(&root);
    let _ = fs::remove_dir_all(&source);
}
