use crate::entry::JournalEntry;
use super::super::Plugin;

pub struct ExportMdPlugin;

impl Plugin for ExportMdPlugin {
    fn on_entry(&self, entry: &JournalEntry) -> Option<String> {
        let title = if entry.display_title.is_empty() {
            &entry.id
        } else {
            &entry.display_title
        };
        Some(format!("[export_md] Entry '{}' available for export", title))
    }

    fn on_export(&self, entry: &JournalEntry) -> Option<Vec<u8>> {
        let body = "[body would be decrypted here]";
        let md = format!(
            "## {}\n\n{}\n\n---\n*Tags: {}*\n",
            entry.display_title,
            body,
            entry.tags.join(", "),
        );
        Some(md.into_bytes())
    }
}
