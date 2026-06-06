pub mod schema;

use crate::entry::{EditRecord, EntryKind, JournalEntry, Provenance};
use chrono::{DateTime, Utc};
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::Mutex;

pub struct Storage {
    conn: Mutex<Connection>,
}

impl Storage {
    pub fn new(path: &Path) -> Result<Self, String> {
        let conn = Connection::open(path).map_err(|e| e.to_string())?;
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
            .map_err(|e| e.to_string())?;
        schema::initialize(&conn)?;
        Ok(Storage { conn: Mutex::new(conn) })
    }

    pub fn add_entry(&self, entry: &JournalEntry) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        conn.execute(
            "INSERT INTO entries (id, encrypted, nonce, salt, kind, tags, display_title,
             pinned, mood, author, timestamp, plugin_origin, feedback, priority,
             status, due_date, parent_project_id, history)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18)",
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
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn update_entry(&self, entry: &JournalEntry) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        conn.execute(
            "UPDATE entries SET encrypted=?2, nonce=?3, salt=?4, kind=?5, tags=?6,
             display_title=?7, pinned=?8, mood=?9, author=?10, timestamp=?11,
             plugin_origin=?12, feedback=?13, priority=?14, status=?15,
             due_date=?16, parent_project_id=?17, history=?18,
             updated_at=datetime('now')
             WHERE id=?1",
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
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn delete_entry(&self, id: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        conn.execute("DELETE FROM entries WHERE id=?1", params![id])
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn set_entry_mood(&self, id: &str, mood: Option<&str>) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        conn.execute(
            "UPDATE entries SET mood=?2, updated_at=datetime('now') WHERE id=?1",
            params![id, mood],
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn set_entry_status(&self, id: &str, status: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        conn.execute(
            "UPDATE entries SET status=?2, updated_at=datetime('now') WHERE id=?1",
            params![id, status],
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn get_entry(&self, id: &str) -> Result<Option<JournalEntry>, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let mut stmt = conn
            .prepare(
                "SELECT id, encrypted, nonce, salt, kind, tags, display_title,
                 pinned, mood, author, timestamp, plugin_origin, feedback,
                 priority, status, due_date, parent_project_id, history
                 FROM entries WHERE id=?1",
            )
            .map_err(|e| e.to_string())?;

        let mut rows = stmt.query(params![id]).map_err(|e| e.to_string())?;
        match rows.next().map_err(|e| e.to_string())? {
            Some(row) => Ok(Some(row_to_entry(row).map_err(|e| e.to_string())?)),
            None => Ok(None),
        }
    }

    pub fn list_entries(&self) -> Result<Vec<JournalEntry>, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let mut stmt = conn
            .prepare(
                "SELECT id, encrypted, nonce, salt, kind, tags, display_title,
                 pinned, mood, author, timestamp, plugin_origin, feedback,
                 priority, status, due_date, parent_project_id, history
                 FROM entries ORDER BY timestamp DESC",
            )
            .map_err(|e| e.to_string())?;

        let rows = stmt
            .query_map([], |row| row_to_entry(row))
            .map_err(|e| e.to_string())?;

        let mut entries = Vec::new();
        for row in rows {
            entries.push(row.map_err(|e| e.to_string())?);
        }
        Ok(entries)
    }

    pub fn search_entries(&self, query: &str) -> Result<Vec<JournalEntry>, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let pattern = format!("%{}%", query);
        let mut stmt = conn
            .prepare(
                "SELECT id, encrypted, nonce, salt, kind, tags, display_title,
                 pinned, mood, author, timestamp, plugin_origin, feedback,
                 priority, status, due_date, parent_project_id, history
                 FROM entries
                 WHERE kind LIKE ?1
                    OR tags LIKE ?1
                    OR display_title LIKE ?1
                    OR author LIKE ?1
                    OR id LIKE ?1
                 ORDER BY timestamp DESC",
            )
            .map_err(|e| e.to_string())?;

        let rows = stmt
            .query_map(params![pattern], |row| row_to_entry(row))
            .map_err(|e| e.to_string())?;

        let mut entries = Vec::new();
        for row in rows {
            entries.push(row.map_err(|e| e.to_string())?);
        }
        Ok(entries)
    }

    pub fn get_streak(&self) -> Result<u32, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let mut stmt = conn
            .prepare(
                "SELECT DISTINCT DATE(timestamp) as d FROM entries
                 WHERE kind='journal' ORDER BY d DESC",
            )
            .map_err(|e| e.to_string())?;

        let rows: Vec<String> = stmt
            .query_map([], |row| row.get::<_, String>(0))
            .map_err(|e| e.to_string())?
            .filter_map(|r| r.ok())
            .collect();

        if rows.is_empty() {
            return Ok(0);
        }

        let today = Utc::now().date_naive();
        let mut streak = 0u32;
        let mut expected = today;

        for date_str in &rows {
            if let Ok(d) = chrono::NaiveDate::parse_from_str(date_str, "%Y-%m-%d") {
                if d == expected {
                    streak += 1;
                    expected = expected.pred_opt().unwrap_or(expected);
                } else if d < expected {
                    break;
                }
            }
        }
        Ok(streak)
    }

    // Folder operations
    pub fn list_folders(&self) -> Result<Vec<Folder>, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let mut stmt = conn
            .prepare("SELECT id, name, parent_id, sort_order FROM folders ORDER BY sort_order")
            .map_err(|e| e.to_string())?;
        let rows = stmt
            .query_map([], |row| {
                Ok(Folder {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    parent_id: row.get(2)?,
                    sort_order: row.get(3)?,
                })
            })
            .map_err(|e| e.to_string())?;
        let mut folders = Vec::new();
        for row in rows {
            folders.push(row.map_err(|e| e.to_string())?);
        }
        Ok(folders)
    }

    pub fn create_folder(&self, name: &str, parent_id: Option<&str>) -> Result<String, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        use rand::Rng;
        let id: String = (0..16)
            .map(|_| {
                let c: u8 = rand::thread_rng().gen_range(0..36);
                if c < 10 {
                    (b'0' + c) as char
                } else {
                    (b'a' + c - 10) as char
                }
            })
            .collect();

        conn.execute(
            "INSERT INTO folders (id, name, parent_id) VALUES (?1, ?2, ?3)",
            params![id, name, parent_id],
        )
        .map_err(|e| e.to_string())?;
        Ok(id)
    }

    pub fn delete_folder(&self, id: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        conn.execute("DELETE FROM folders WHERE id=?1", params![id])
            .map_err(|e| e.to_string())?;
        // Unlink entries in this folder
        conn.execute(
            "UPDATE entries SET parent_project_id=NULL WHERE parent_project_id=?1",
            params![id],
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn move_to_folder(&self, entry_id: &str, folder_id: Option<&str>) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        conn.execute(
            "UPDATE entries SET parent_project_id=?2 WHERE id=?1",
            params![entry_id, folder_id],
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn toggle_pin(&self, entry_id: &str) -> Result<bool, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        conn.execute(
            "UPDATE entries SET pinned = CASE WHEN pinned=0 THEN 1 ELSE 0 END WHERE id=?1",
            params![entry_id],
        )
        .map_err(|e| e.to_string())?;
        let mut stmt = conn
            .prepare("SELECT pinned FROM entries WHERE id=?1")
            .map_err(|e| e.to_string())?;
        let pinned: i32 = stmt
            .query_row(params![entry_id], |row| row.get(0))
            .map_err(|e| e.to_string())?;
        Ok(pinned != 0)
    }

    // Batch import
    pub fn import_entries(&self, entries: &[JournalEntry]) -> Result<u32, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let mut count = 0u32;
        for entry in entries {
            let result = conn.execute(
                "INSERT OR IGNORE INTO entries (id, encrypted, nonce, salt, kind, tags,
                 display_title, pinned, mood, author, timestamp, plugin_origin,
                 feedback, priority, status, due_date, parent_project_id, history)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18)",
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
            )
            .map_err(|e| e.to_string())?;
            if result > 0 {
                count += 1;
            }
        }
        Ok(count)
    }

    pub fn list_recurring_tasks(&self) -> Result<Vec<serde_json::Value>, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let mut stmt = conn
            .prepare(
                "SELECT id, title, every_n_days, day_of_week, priority, tags,
                 project_id, created_at, next_due FROM recurring_tasks",
            )
            .map_err(|e| e.to_string())?;

        let rows = stmt
            .query_map([], |row| {
                Ok(serde_json::json!({
                    "id": row.get::<_, String>(0)?,
                    "title": row.get::<_, String>(1)?,
                    "every_n_days": row.get::<_, Option<i64>>(2)?,
                    "day_of_week": row.get::<_, Option<i64>>(3)?,
                    "priority": row.get::<_, String>(4)?,
                    "tags": row.get::<_, String>(5)?,
                    "project_id": row.get::<_, Option<String>>(6)?,
                    "created_at": row.get::<_, String>(7)?,
                    "next_due": row.get::<_, String>(8)?,
                }))
            })
            .map_err(|e| e.to_string())?;

        let mut tasks = Vec::new();
        for row in rows {
            tasks.push(row.map_err(|e| e.to_string())?);
        }
        Ok(tasks)
    }

    pub fn update_recurring_task_next_due(&self, id: &str, next_due: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        conn.execute(
            "UPDATE recurring_tasks SET next_due=?2 WHERE id=?1",
            params![id, next_due],
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Folder {
    pub id: String,
    pub name: String,
    pub parent_id: Option<String>,
    pub sort_order: i32,
}

pub(crate) fn row_to_entry(row: &rusqlite::Row) -> Result<JournalEntry, rusqlite::Error> {
    let ts_str: String = row.get(10)?;
    let timestamp = DateTime::parse_from_rfc3339(&ts_str)
        .map(|dt| dt.with_timezone(&Utc))
        .unwrap_or_else(|_| Utc::now());

    let tags_str: String = row.get(5)?;
    let tags: Vec<String> = serde_json::from_str(&tags_str).unwrap_or_default();

    let history_str: String = row.get(17)?;
    let history: Vec<EditRecord> = serde_json::from_str(&history_str).unwrap_or_default();

    Ok(JournalEntry {
        id: row.get(0)?,
        encrypted: row.get(1)?,
        nonce: row.get(2)?,
        salt: row.get(3)?,
        kind: EntryKind::from_str(&row.get::<_, String>(4)?),
        tags,
        display_title: row.get(6)?,
        pinned: row.get::<_, i32>(7)? != 0,
        mood: row.get(8)?,
        provenance: Provenance {
            timestamp,
            author: row.get(9)?,
            plugin_origin: row.get(11)?,
            feedback: row.get(12)?,
        },
        priority: row.get(13)?,
        status: row.get(14)?,
        due_date: row.get(15)?,
        parent_project_id: row.get(16)?,
        history,
    })
}
