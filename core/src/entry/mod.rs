use chrono::{DateTime, Utc};
use serde::{Serialize, Deserialize};

mod encryption;

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

    // --- Encryption fields ---
    pub encrypted: Vec<u8>,
    pub nonce: Vec<u8>,
    pub salt: Vec<u8>,        // <-- REQUIRED for key derivation

    // --- Metadata ---
    pub provenance: Provenance,
}

impl JournalEntry {
    pub fn new(
        id: String,
        text: String,
        author: String,
        plugin_origin: Option<String>,
        password: &str,
    ) -> Self {
        let timestamp = Utc::now();

        let provenance = Provenance {
            timestamp,
            plugin_origin,
            author,
            feedback: None,
        };

        // Generate salt for PBKDF2/Argon2
        let salt: [u8; 16] = rand::random();

        // Derive key
        let key = encryption::derive_key(password, &salt[..]);

        // Encrypt
        let (encrypted, nonce) = encryption::encrypt(&text, &key);

        JournalEntry {
            id,
            encrypted,
            nonce,
            salt: salt.to_vec(),
            provenance,
        }
    }

    pub fn decrypt_text(&self, password: &str) -> String {
        let key = encryption::derive_key(password, &self.salt);
        encryption::decrypt(&self.encrypted, &self.nonce, &key)
    }
}
