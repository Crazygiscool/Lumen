use chrono::{DateTime, Utc};
use serde::{Deserialize, Deserializer, Serialize, Serializer};

pub(crate) mod encryption;
pub(crate) mod recurring;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Provenance {
    pub timestamp: DateTime<Utc>,
    pub plugin_origin: Option<String>,
    pub author: String,
    pub feedback: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EditRecord {
    pub timestamp: DateTime<Utc>,
    pub author: String,
    pub reason: String,
}

#[derive(Debug, Clone, Default)]
pub enum EntryKind {
    #[default]
    Journal,
    Note,
    Task,
    Project,
    Custom(String),
}

impl Serialize for EntryKind {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(self.as_str())
    }
}

impl<'de> Deserialize<'de> for EntryKind {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let s = String::deserialize(deserializer)?;
        Ok(EntryKind::from_str(&s))
    }
}

impl EntryKind {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "journal" => EntryKind::Journal,
            "note" => EntryKind::Note,
            "task" => EntryKind::Task,
            "project" => EntryKind::Project,
            _ => EntryKind::Custom(s.to_string()),
        }
    }

    pub fn as_str(&self) -> &str {
        match self {
            EntryKind::Journal => "journal",
            EntryKind::Note => "note",
            EntryKind::Task => "task",
            EntryKind::Project => "project",
            EntryKind::Custom(s) => s.as_str(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JournalEntry {
    pub id: String,

    // --- Encryption fields ---
    pub encrypted: Vec<u8>,

    pub nonce: Vec<u8>,

    pub salt: Vec<u8>,

    // --- Metadata ---
    pub provenance: Provenance,

    #[serde(default)]
    pub kind: EntryKind,

    #[serde(default)]
    pub tags: Vec<String>,

    #[serde(default)]
    pub display_title: String,

    #[serde(default)]
    pub pinned: bool,

    #[serde(default)]
    pub mood: Option<String>,

    #[serde(default)]
    pub priority: Option<String>,

    #[serde(default)]
    pub status: Option<String>,

    #[serde(default)]
    pub due_date: Option<String>,

    #[serde(default)]
    pub parent_project_id: Option<String>,

    #[serde(default)]
    pub history: Vec<EditRecord>,
}

impl JournalEntry {
    pub fn new(
        id: String,
        text: String,
        author: String,
        plugin_origin: Option<String>,
        password: &str,
        kind: EntryKind,
        tags: Vec<String>,
        display_title: String,
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
            kind,
            tags,
            display_title,
            pinned: false,
            mood: None,
            priority: None,
            status: None,
            due_date: None,
            parent_project_id: None,
            history: Vec::new(),
        }
    }

    pub fn decrypt_text(&self, password: &str) -> String {
        let key = encryption::derive_key(password, &self.salt);
        match encryption::decrypt(&self.encrypted, &self.nonce, &key) {
            Ok(s) => s,
            Err(e) => format!("ERROR: {}", e),
        }
    }
}
