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

    pub fn save_to_file<P: AsRef<Path>>(&self, path: P) {
        let serialized = bincode::serialize(&self.entries).expect("Serialization failed");
        let mut file = File::create(path).expect("Unable to create file");
        file.write_all(&serialized).expect("Write failed");
    }

    pub fn load_from_file<P: AsRef<Path>>(&mut self, path: P) {
        let mut file = OpenOptions::new().read(true).open(path).expect("Unable to open file");
        let mut buffer = Vec::new();
        file.read_to_end(&mut buffer).expect("Read failed");
        self.entries = bincode::deserialize(&buffer).expect("Deserialization failed");
    }
}
