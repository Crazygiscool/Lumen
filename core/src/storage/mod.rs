//! Local-first storage, sync adapters

use crate::entry::JournalEntry;
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::Path;
// ...existing code...

#[derive(Default)]
pub struct Storage {
    entries: Vec<JournalEntry>,
}

impl Storage {
    pub fn new() -> Self {
        Storage { entries: Vec::new() }
    }

    pub fn add_entry(&mut self, entry: JournalEntry) {
        self.entries.push(entry);
    }

    pub fn list_entries(&self) -> &Vec<JournalEntry> {
        &self.entries
    }

    pub fn save_to_file<P: AsRef<Path>>(&self, path: P) -> Result<(), String> {
        let serialized = bincode::serialize(&self.entries).map_err(|e| e.to_string())?;
        File::create(path.as_ref())
            .and_then(|mut f| f.write_all(&serialized))
            .map_err(|e| e.to_string())
    }

    pub fn load_from_file<P: AsRef<Path>>(&mut self, path: P) -> Result<(), String> {
        if !path.as_ref().exists() {
            return Ok(());
        }
        let mut file = OpenOptions::new().read(true).open(path.as_ref()).map_err(|e| e.to_string())?;
        let mut buffer = Vec::new();
        file.read_to_end(&mut buffer).map_err(|e| e.to_string())?;
        self.entries = bincode::deserialize(&buffer).map_err(|e| e.to_string())?;
        Ok(())
    }
}
