use chrono::{DateTime, Utc};
use serde::{Serialize, Deserialize, Serializer};
use base64::{engine::general_purpose, Engine as _};

mod encryption;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Provenance {
    pub timestamp: DateTime<Utc>,
    pub plugin_origin: Option<String>,
    pub author: String,
    pub feedback: Option<String>,
}

fn as_base64<S>(bytes: &Vec<u8>, serializer: S) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    let encoded = general_purpose::STANDARD.encode(bytes);
    serializer.serialize_str(&encoded)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JournalEntry {
    pub id: String,

    // --- Encryption fields ---
    #[serde(serialize_with = "as_base64")]
    pub encrypted: Vec<u8>,

    #[serde(serialize_with = "as_base64")]
    pub nonce: Vec<u8>,

    #[serde(serialize_with = "as_base64")]
    pub salt: Vec<u8>,

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

        let salt: [u8; 16] = rand::random();
        let key = encryption::derive_key(password, &salt[..]);
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
