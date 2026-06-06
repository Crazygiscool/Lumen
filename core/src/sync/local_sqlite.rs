use std::path::Path;
use std::sync::Mutex;

use rusqlite::params;

use crate::entry::JournalEntry;
use crate::storage::schema;

use super::{Conflict, SyncBackend};

pub struct LocalSqliteSync {
    conn: Mutex<rusqlite::Connection>,
}

impl LocalSqliteSync {
    pub fn open(path: &Path) -> Result<Self, String> {
        let conn = rusqlite::Connection::open(path).map_err(|e| e.to_string())?;
        schema::initialize(&conn)?;
        Ok(LocalSqliteSync {
            conn: Mutex::new(conn),
        })
    }
}

impl SyncBackend for LocalSqliteSync {
    fn push(&self, entries: &[JournalEntry]) -> Result<u32, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let mut count = 0u32;
        for entry in entries {
            let affected = conn.execute(
                "INSERT OR REPLACE INTO entries
                 (id, encrypted, nonce, salt, kind, tags, display_title, pinned,
                  mood, author, timestamp, plugin_origin, feedback, priority,
                  status, due_date, parent_project_id, history)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13,
                         ?14, ?15, ?16, ?17, ?18)",
                params![
                    entry.id,
                    entry.encrypted,
                    entry.nonce,
                    entry.salt,
                    entry.kind.as_str(),
                    serde_json::to_string(&entry.tags).unwrap_or_default(),
                    entry.display_title,
                    entry.pinned as i32,
                    entry.mood,
                    entry.provenance.author,
                    entry.provenance.timestamp.to_rfc3339(),
                    entry.provenance.plugin_origin,
                    entry.provenance.feedback,
                    entry.priority,
                    entry.status,
                    entry.due_date,
                    entry.parent_project_id,
                    serde_json::to_string(&entry.history).unwrap_or_default(),
                ],
            ).map_err(|e| e.to_string())?;
            if affected > 0 {
                count += 1;
            }
        }
        Ok(count)
    }

    fn pull(&self) -> Result<Vec<JournalEntry>, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let mut stmt = conn
            .prepare(
                "SELECT id, encrypted, nonce, salt, kind, tags, display_title,
                        pinned, mood, author, timestamp, plugin_origin, feedback,
                        priority, status, due_date, parent_project_id, history
                 FROM entries ORDER BY timestamp",
            )
            .map_err(|e| e.to_string())?;

        let entries = stmt
            .query_map([], |row| crate::storage::row_to_entry(row))
            .map_err(|e| e.to_string())?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())?;

        Ok(entries)
    }

    fn resolve(&self, conflicts: Vec<Conflict>) -> Result<Vec<JournalEntry>, String> {
        let mut resolved = Vec::new();
        for c in conflicts {
            // Last-writer-wins by provenance.timestamp
            let chosen = if c.local.provenance.timestamp >= c.remote.provenance.timestamp {
                c.local
            } else {
                c.remote
            };
            resolved.push(chosen);
        }
        Ok(resolved)
    }
}
