//! Journal entry structs, encryption, provenance

use chrono::{DateTime, Utc};
mod encryption;
use serde::{Serialize, Deserialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Provenance {
    pub timestamp: DateTime<Utc>,
    pub plugin_origin: Option<String>,
    pub author: String,
    pub feedback: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JournalEntry {
    pub id: String,
    pub encrypted: Vec<u8>, // Encrypted content
    pub nonce: Vec<u8>,     // Nonce used for encryption
    pub provenance: Provenance,
}

impl JournalEntry {
    pub fn new(id: String, text: String, author: String, plugin_origin: Option<String>, password: &str) -> Self {
        let timestamp = Utc::now();
        let provenance = Provenance {
            timestamp,
            plugin_origin,
            author,
            feedback: None,
        };
        let salt: [u8; 16] = rand::random();
        let key = encryption::derive_key(password, &salt);
        let (encrypted, nonce) = encryption::encrypt(&text, &key);
        JournalEntry { id, encrypted, nonce, provenance }
    }

    pub fn decrypt_text(&self, password: &str, salt: &[u8]) -> String {
        let key = encryption::derive_key(password, salt);
        encryption::decrypt(&self.encrypted, &self.nonce, &key)
    }
}
