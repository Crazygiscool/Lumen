pub mod local_sqlite;

use crate::entry::JournalEntry;

#[derive(Debug, Clone)]
pub struct Conflict {
    pub entry_id: String,
    pub local: JournalEntry,
    pub remote: JournalEntry,
}

pub trait SyncBackend {
    fn push(&self, entries: &[JournalEntry]) -> Result<u32, String>;
    fn pull(&self) -> Result<Vec<JournalEntry>, String>;
    fn resolve(&self, conflicts: Vec<Conflict>) -> Result<Vec<JournalEntry>, String>;
}
