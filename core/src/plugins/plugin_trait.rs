use crate::entry::JournalEntry;

pub trait Plugin {
    fn on_entry(&self, entry: &JournalEntry) -> Option<String>;
    fn on_export(&self, entry: &JournalEntry) -> Option<Vec<u8>>;
}
