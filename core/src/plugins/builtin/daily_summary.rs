use crate::entry::JournalEntry;
use super::super::Plugin;

pub struct DailySummaryPlugin;

impl Plugin for DailySummaryPlugin {
    fn on_entry(&self, entry: &JournalEntry) -> Option<String> {
        Some(format!(
            "[daily_summary] Entry '{}' added {}",
            entry.display_title,
            entry.provenance.timestamp.format("%Y-%m-%d"),
        ))
    }

    fn on_export(&self, _entry: &JournalEntry) -> Option<Vec<u8>> {
        None
    }
}
