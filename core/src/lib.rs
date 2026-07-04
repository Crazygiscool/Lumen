pub mod auth;
pub mod entry;
pub mod storage;
pub mod plugins;
pub mod feedback;
pub mod sync;
pub mod ffi;
pub mod import_stoic;
pub mod progress;
pub mod paths;

pub use ffi::{
    lumen_add_entry,
    lumen_list_entries,
    lumen_decrypt_entry,
    lumen_get_entry,
    lumen_update_entry,
    lumen_delete_entry,
    lumen_search_entries,
    lumen_search_entries_fts,
    lumen_get_streak,
    lumen_free_string,
    lumen_set_entry_status,
    lumen_set_entry_mood,
    lumen_list_folders,
    lumen_create_folder,
    lumen_delete_folder,
    lumen_move_to_folder,
    lumen_toggle_pin,
    lumen_parse_task,
    lumen_export_all,
    lumen_import,
    lumen_export_project,
    lumen_has_password,
    lumen_set_password,
    lumen_unlock,
    lumen_lock,
    lumen_is_unlocked,
    lumen_list_vaults,
    lumen_open_vault,
    lumen_sync_push,
    lumen_sync_pull,
    lumen_sync_list_conflicts,
    lumen_sync_accept_conflict,
    lumen_add_asset,
    lumen_get_assets,
    lumen_get_asset_data,
    lumen_import_stoic,
};

#[cfg(test)]
mod tests {
use crate::entry::{EntryKind, JournalEntry};
use crate::storage::Storage;
use crate::plugins::{Plugin, PluginManager};
use crate::feedback::GeorgeFeedback;
use std::path::Path;

    use crate::entry::encryption;

    struct TestPlugin;
    impl Plugin for TestPlugin {
        fn on_entry(&self, entry: &JournalEntry) -> Option<String> {
            Some(format!("Plugin feedback for entry {}", entry.id))
        }
        fn on_export(&self, _entry: &JournalEntry) -> Option<Vec<u8>> {
            None
        }
    }

    fn test_storage() -> Storage {
        Storage::new(Path::new(":memory:")).expect("in-memory SQLite")
    }

    #[test]
    fn test_add_entry_with_encryption_and_plugin() {
        let password = "testpassword";
        let salt: [u8; 16] = rand::random();
        let key = encryption::derive_key(password, &salt);
        let entry = JournalEntry::new(
            "1".to_string(),
            "My first journal entry.".to_string(),
            "crazygiscool".to_string(),
            None,
            &key,
            salt.to_vec(),
            EntryKind::Journal,
            vec![],
            String::new(),
        );
        let storage = test_storage();
        storage.add_entry(&entry).unwrap();
        assert_eq!(storage.list_entries().unwrap().len(), 1);

        // Feedback engine usage
        let feedback = GeorgeFeedback::analyze(&entry);
        assert_eq!(feedback, "Expressive feedback goes here.");

        // Plugin usage
        let mut manager = PluginManager::new();
        manager.register_plugin(Box::new(TestPlugin));
        let feedback = manager.run_on_entry(&entry);
        assert!(!feedback.is_empty());
    }

    #[test]
    fn test_sqlite_crud() {
        let storage = test_storage();
        let salt: [u8; 16] = rand::random();
        let key = encryption::derive_key("password", &salt);
        let entry = JournalEntry::new(
            "test-1".to_string(),
            "Hello world".to_string(),
            "test".to_string(),
            None,
            &key,
            salt.to_vec(),
            EntryKind::Note,
            vec!["tag1".to_string()],
            "Test Entry".to_string(),
        );

        // Create
        storage.add_entry(&entry).unwrap();
        assert_eq!(storage.list_entries().unwrap().len(), 1);

        // Read
        let fetched = storage.get_entry("test-1").unwrap().unwrap();
        assert_eq!(fetched.display_title, "Test Entry");

        // Search (metadata-only: body is encrypted)
        let results = storage.search_entries("Test Entry").unwrap();
        assert_eq!(results.len(), 1);
        let results = storage.search_entries("test-1").unwrap();
        assert_eq!(results.len(), 1);
        let results = storage.search_entries("notfound").unwrap();
        assert_eq!(results.len(), 0);

        // Delete
        storage.delete_entry("test-1").unwrap();
        assert_eq!(storage.list_entries().unwrap().len(), 0);
    }

    #[test]
    fn test_streak() {
        let storage = test_storage();
        use chrono::Utc;
        // Add entries for today and yesterday
        let today = Utc::now().date_naive();

        let salt1: [u8; 16] = rand::random();
        let key1 = encryption::derive_key("pw", &salt1);
        let mut e1 = JournalEntry::new(
            "s1".to_string(), "".to_string(), "u".to_string(),
            None, &key1, salt1.to_vec(), EntryKind::Journal, vec![], "".to_string(),
        );
        e1.provenance.timestamp = today.and_hms_opt(12, 0, 0).unwrap()
            .and_local_timezone(Utc).unwrap();
        storage.add_entry(&e1).unwrap();

        let salt2: [u8; 16] = rand::random();
        let key2 = encryption::derive_key("pw", &salt2);
        let mut e2 = JournalEntry::new(
            "s2".to_string(), "".to_string(), "u".to_string(),
            None, &key2, salt2.to_vec(), EntryKind::Journal, vec![], "".to_string(),
        );
        e2.provenance.timestamp = today.pred_opt().unwrap()
            .and_hms_opt(12, 0, 0).unwrap()
            .and_local_timezone(Utc).unwrap();
        storage.add_entry(&e2).unwrap();

        assert!(storage.get_streak().unwrap() >= 2);
    }

    #[test]
    fn test_stoic_import() {
        let manifest_dir = env!("CARGO_MANIFEST_DIR");
        let stoic_dir = format!("{}/../stoic", manifest_dir);
        let stoic_path = std::path::Path::new(&stoic_dir);
        if !stoic_path.join("journal-entries.json").exists() {
            eprintln!("Skipping stoic import test — test data not found at {stoic_dir}");
            return;
        }

        let storage = crate::storage::Storage::new(std::path::Path::new(":memory:")).unwrap();
        let count = crate::import_stoic::import_stoic(&stoic_dir, "testpassword", "test-user", &storage);
        assert!(count > 0, "Expected at least 1 imported entry, got {count}");

        let entries = storage.list_entries().unwrap();
        assert!(entries.len() as i32 >= count);

        // Verify entries have stoic tags and provenance
        let stoic_entries: Vec<_> = entries.iter().filter(|e| e.tags.contains(&"stoic-imported".to_string())).collect();
        assert!(stoic_entries.len() as i32 >= count);

        // Verify at least one entry can be decrypted
        let entry = &entries[0];
        let key = encryption::derive_key("testpassword", &entry.salt);
        let decrypted = entry.decrypt(&key).ok().and_then(|b| String::from_utf8(b).ok()).unwrap_or_default();
        assert!(!decrypted.is_empty(), "Decrypted text should not be empty");
        assert!(decrypted.contains("Stoic"), "Decrypted text should contain 'Stoic'");
    }
}
