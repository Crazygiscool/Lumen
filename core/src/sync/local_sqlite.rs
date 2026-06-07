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

    pub fn list_conflicts(&self) -> Result<Vec<serde_json::Value>, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let mut stmt = conn
            .prepare("SELECT id, entry_id, local_timestamp, remote_timestamp, resolved FROM sync_conflicts WHERE resolved=0")
            .map_err(|e| e.to_string())?;
        let rows = stmt
            .query_map([], |row| {
                Ok(serde_json::json!({
                    "id": row.get::<_, String>(0)?,
                    "entry_id": row.get::<_, String>(1)?,
                    "local_timestamp": row.get::<_, String>(2)?,
                    "remote_timestamp": row.get::<_, String>(3)?,
                    "resolved": row.get::<_, i32>(4)?,
                }))
            })
            .map_err(|e| e.to_string())?;
        let mut conflicts = Vec::new();
        for row in rows {
            conflicts.push(row.map_err(|e| e.to_string())?);
        }
        Ok(conflicts)
    }

    pub fn accept_conflict(&self, conflict_id: &str, keep_local: bool) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let conflict: (String, String, i32) = conn
            .query_row(
                "SELECT local_entry_json, remote_entry_json, resolved FROM sync_conflicts WHERE id=?1",
                params![conflict_id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .map_err(|e| e.to_string())?;
        if conflict.2 != 0 {
            return Err("Conflict already resolved".to_string());
        }
        let chosen_json = if keep_local { conflict.0 } else { conflict.1 };
        let chosen: JournalEntry = serde_json::from_str(&chosen_json).map_err(|e| e.to_string())?;

        conn.execute(
            "INSERT OR REPLACE INTO entries
             (id, encrypted, nonce, salt, kind, tags, display_title, pinned,
              mood, author, timestamp, plugin_origin, feedback, metadata, priority,
              status, due_date, parent_project_id, history)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13,
                     ?14, ?15, ?16, ?17, ?18, ?19)",
            params![
                chosen.id,
                chosen.encrypted,
                chosen.nonce,
                chosen.salt,
                chosen.kind.as_str(),
                serde_json::to_string(&chosen.tags).unwrap_or_default(),
                chosen.display_title,
                chosen.pinned as i32,
                chosen.mood,
                chosen.provenance.author,
                chosen.provenance.timestamp.to_rfc3339(),
                chosen.provenance.plugin_origin,
                chosen.provenance.feedback,
                serde_json::to_string(&chosen.provenance.metadata).unwrap_or_else(|_| "{}".to_string()),
                chosen.priority,
                chosen.status,
                chosen.due_date,
                chosen.parent_project_id,
                serde_json::to_string(&chosen.history).unwrap_or_default(),
            ],
        )
        .map_err(|e| e.to_string())?;

        conn.execute(
            "UPDATE sync_conflicts SET resolved=1 WHERE id=?1",
            params![conflict_id],
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    }
}

impl SyncBackend for LocalSqliteSync {
    fn push(&self, entries: &[JournalEntry]) -> Result<u32, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let mut count = 0u32;
        for entry in entries {
            // Check for existing entry with different timestamp
            let existing: Option<String> = conn
                .query_row(
                    "SELECT timestamp FROM entries WHERE id=?1",
                    params![entry.id],
                    |row| row.get(0),
                )
                .ok();

            if let Some(existing_ts) = existing {
                let new_ts = entry.provenance.timestamp.to_rfc3339();
                if existing_ts != new_ts {
                    // Conflict detected — store both versions
                    let conflict_id = format!("{}_{}", entry.id, chrono::Utc::now().timestamp());
                    let local_json = serde_json::to_string(entry).unwrap_or_default();
                    // Fetch the remote entry from the DB
                    let remote = conn
                        .query_row(
                            "SELECT encrypted, nonce, salt, kind, tags, display_title,
                                    pinned, mood, author, timestamp, plugin_origin, feedback,
                                    metadata, priority, status, due_date, parent_project_id, history
                             FROM entries WHERE id=?1",
                            params![entry.id],
                            |row| {
                                let ts_str: String = row.get(9)?;
                                let timestamp = chrono::DateTime::parse_from_rfc3339(&ts_str)
                                    .map(|dt| dt.with_timezone(&chrono::Utc))
                                    .unwrap_or_else(|_| chrono::Utc::now());
                                let tags_str: String = row.get(4)?;
                                let tags: Vec<String> = serde_json::from_str(&tags_str).unwrap_or_default();
                                let metadata_str: String = row.get(12)?;
                                let metadata: serde_json::Value = serde_json::from_str(&metadata_str).unwrap_or_else(|_| serde_json::json!({}));
                                let history_str: String = row.get(17)?;
                                let history: Vec<crate::entry::EditRecord> = serde_json::from_str(&history_str).unwrap_or_default();
                                Ok(JournalEntry {
                                    id: row.get::<_, String>(0)?,
                                    encrypted: row.get(1)?,
                                    nonce: row.get(2)?,
                                    salt: row.get(3)?,
                                    kind: crate::entry::EntryKind::from_str(&row.get::<_, String>(4)?),
                                    tags,
                                    display_title: row.get(5)?,
                                    pinned: row.get::<_, i32>(6)? != 0,
                                    mood: row.get(7)?,
                                    provenance: crate::entry::Provenance {
                                        timestamp,
                                        author: row.get(8)?,
                                        plugin_origin: row.get(10)?,
                                        feedback: row.get(11)?,
                                        metadata,
                                    },
                                    priority: row.get(13)?,
                                    status: row.get(14)?,
                                    due_date: row.get(15)?,
                                    parent_project_id: row.get(16)?,
                                    history,
                                    assets: Vec::new(),
                                })
                            },
                        )
                        .map_err(|e| e.to_string())?;
                    let remote_json = serde_json::to_string(&remote).unwrap_or_default();

                    let _ = conn.execute(
                        "INSERT OR REPLACE INTO sync_conflicts
                         (id, entry_id, local_timestamp, remote_timestamp,
                          local_entry_json, remote_entry_json)
                         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                        params![
                            conflict_id,
                            entry.id,
                            new_ts,
                            existing_ts,
                            local_json,
                            remote_json,
                        ],
                    );
                    continue;
                }
            }

            let affected = conn.execute(
                "INSERT OR REPLACE INTO entries
                 (id, encrypted, nonce, salt, kind, tags, display_title, pinned,
                  mood, author, timestamp, plugin_origin, feedback, metadata, priority,
                  status, due_date, parent_project_id, history)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13,
                         ?14, ?15, ?16, ?17, ?18, ?19)",
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
                    serde_json::to_string(&entry.provenance.metadata).unwrap_or_else(|_| "{}".to_string()),
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
                        metadata, priority, status, due_date, parent_project_id, history
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
