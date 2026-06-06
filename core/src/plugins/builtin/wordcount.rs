use crate::entry::JournalEntry;
use super::super::Plugin;

pub struct WordCountPlugin;

impl Plugin for WordCountPlugin {
    fn on_entry(&self, entry: &JournalEntry) -> Option<String> {
        // Estimate word count from encrypted body length
        let approx_words = entry.encrypted.len() / 6;
        Some(format!(
            "[wordcount] Entry '{}': ~{} words",
            entry.display_title, approx_words,
        ))
    }

    fn on_export(&self, _entry: &JournalEntry) -> Option<Vec<u8>> {
        None
    }
}
