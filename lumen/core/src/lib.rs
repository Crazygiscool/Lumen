
use std::os::raw::c_char;

pub mod entry;
pub mod storage;
pub mod plugins;
pub mod feedback;
pub mod ffi;


#[cfg(test)]
mod tests {
	use crate::entry::JournalEntry;
	use crate::storage::Storage;
	use crate::plugins::{Plugin, PluginManager};
	use crate::feedback::GeorgeFeedback;

	struct TestPlugin;
	impl Plugin for TestPlugin {
		fn on_entry(&self, entry: &JournalEntry) -> Option<String> {
			Some(format!("Plugin feedback for entry {}", entry.id))
		}
		fn on_export(&self, _entry: &JournalEntry) -> Option<Vec<u8>> {
			None
		}
	}

	#[test]
	fn test_add_entry_with_encryption_and_plugin() {
		let password = "testpassword";
		let entry = JournalEntry::new(
			"1".to_string(),
			"My first journal entry.".to_string(),
			"crazygiscool".to_string(),
			None,
			password,
		);
		let mut storage = Storage::new();
		storage.add_entry(entry.clone());
		assert_eq!(storage.list_entries().len(), 1);

		// Feedback engine usage
		let feedback = GeorgeFeedback::analyze(&entry);
		assert_eq!(feedback, "Expressive feedback goes here.");

		// Plugin usage
		let mut manager = PluginManager::new();
		manager.register_plugin(Box::new(TestPlugin));
		manager.run_on_entry(&entry);
	}
}

