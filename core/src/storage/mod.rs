pub mod schema;

use crate::entry::{EditRecord, EntryKind, JournalEntry, Provenance};
use chrono::{DateTime, Utc};
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

pub struct Storage {
    conn: Mutex<Connection>,
    base_path: PathBuf,
}

impl Storage {
    pub fn new(path: &Path) -> Result<Self, String> {
        let conn = Connection::open(path).map_err(|e| e.to_string())?;
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
            .map_err(|e| e.to_string())?;
        schema::initialize(&conn)?;

        let base_path = path.parent().unwrap_or(Path::new(".")).to_path_buf();
        let media_path = base_path.join("media");
        let _ = std::fs::create_dir_all(&media_path);

        Ok(Storage {
            conn: Mutex::new(conn),
            base_path,
        })
    }

    pub fn media_path(&self) -> PathBuf {
        self.base_path.join("media")
    }

    pub fn add_entry(&self, entry: &JournalEntry) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        conn.execute(
            "INSERT INTO entries (id, encrypted, nonce, salt, kind, tags, display_title,
             pinned, mood, author, timestamp, plugin_origin, feedback, metadata, priority,
             status, due_date, parent_project_id, history)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19)",
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
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn update_entry(&self, entry: &JournalEntry) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        conn.execute(
            "UPDATE entries SET encrypted=?2, nonce=?3, salt=?4, kind=?5, tags=?6,
             display_title=?7, pinned=?8, mood=?9, author=?10, timestamp=?11,
             plugin_origin=?12, feedback=?13, metadata=?14, priority=?15, status=?16,
             due_date=?17, parent_project_id=?18, history=?19,
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
                serde_json::to_string(&entry.provenance.metadata).unwrap_or_else(|_| "{}".to_string()),
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
        let _ = conn.execute("DELETE FROM entries_fts WHERE entry_id=?1", params![id]);
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
        let entry = {
            let conn = self.conn.lock().map_err(|e| e.to_string())?;
            let mut stmt = conn
                .prepare(
                    "SELECT id, encrypted, nonce, salt, kind, tags, display_title,
                     pinned, mood, author, timestamp, plugin_origin, feedback, metadata,
                     priority, status, due_date, parent_project_id, history
                     FROM entries WHERE id=?1",
                )
                .map_err(|e| e.to_string())?;

            let mut rows = stmt.query(params![id]).map_err(|e| e.to_string())?;
            match rows.next().map_err(|e| e.to_string())? {
                Some(row) => {
                    let entry = row_to_entry(row).map_err(|e| e.to_string())?;
                    Some(entry)
                },
                None => None,
            }
        };

        if let Some(mut entry) = entry {
            entry.assets = self.get_assets_for_entry(&entry.id)?;
            Ok(Some(entry))
        } else {
            Ok(None)
        }
    }

    pub fn list_entries(&self) -> Result<Vec<JournalEntry>, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let mut stmt = conn
            .prepare(
                "SELECT id, encrypted, nonce, salt, kind, tags, display_title,
                 pinned, mood, author, timestamp, plugin_origin, feedback, metadata,
                 priority, status, due_date, parent_project_id, history
                 FROM entries ORDER BY timestamp DESC",
            )
            .map_err(|e| e.to_string())?;

        let rows = stmt
            .query_map([], |row| row_to_entry(row))
            .map_err(|e| e.to_string())?;

        let mut entries = Vec::new();
        for row in rows {
            let entry = row.map_err(|e| e.to_string())?;
            entries.push(entry);
        }
        Ok(entries)
    }

    pub fn search_entries(&self, query: &str) -> Result<Vec<JournalEntry>, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let pattern = format!("%{}%", query);
        let mut stmt = conn
            .prepare(
                "SELECT id, encrypted, nonce, salt, kind, tags, display_title,
                 pinned, mood, author, timestamp, plugin_origin, feedback, metadata,
                 priority, status, due_date, parent_project_id, history
                 FROM entries
                 WHERE kind LIKE ?1
                    OR tags LIKE ?1
                    OR display_title LIKE ?1
                    OR author LIKE ?1
                    OR id LIKE ?1
                    OR metadata LIKE ?1
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

    pub fn add_asset(&self, asset: &crate::entry::EntryAsset) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        conn.execute(
            "INSERT INTO entry_assets (id, entry_id, file_name, mime_type, encrypted_size, nonce, salt, encrypted_data)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                asset.id,
                asset.entry_id,
                asset.file_name,
                asset.mime_type,
                asset.encrypted_size as i64,
                asset.nonce,
                asset.salt,
                asset.encrypted_data,
            ],
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn get_assets_for_entry(&self, entry_id: &str) -> Result<Vec<crate::entry::EntryAsset>, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let mut stmt = conn
            .prepare(
                "SELECT id, entry_id, file_name, mime_type, encrypted_size, nonce, salt, encrypted_data, created_at
                 FROM entry_assets WHERE entry_id=?1",
            )
            .map_err(|e| e.to_string())?;

        let rows = stmt
            .query_map(params![entry_id], |row| {
                let created_at_str: String = row.get(8)?;
                let created_at = DateTime::parse_from_rfc3339(&created_at_str)
                    .map(|dt| dt.with_timezone(&Utc))
                    .unwrap_or_else(|_| Utc::now());

                Ok(crate::entry::EntryAsset {
                    id: row.get(0)?,
                    entry_id: row.get(1)?,
                    file_name: row.get(2)?,
                    mime_type: row.get(3)?,
                    encrypted_size: row.get::<_, i64>(4)? as u64,
                    nonce: row.get(5)?,
                    salt: row.get(6)?,
                    encrypted_data: row.get(7)?,
                    created_at,
                })
            })
            .map_err(|e| e.to_string())?;

        let mut assets = Vec::new();
        for row in rows {
            assets.push(row.map_err(|e| e.to_string())?);
        }
        Ok(assets)
    }

    pub fn get_asset(&self, id: &str) -> Result<Option<crate::entry::EntryAsset>, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let mut stmt = conn
            .prepare(
                "SELECT id, entry_id, file_name, mime_type, encrypted_size, nonce, salt, encrypted_data, created_at
                 FROM entry_assets WHERE id=?1",
            )
            .map_err(|e| e.to_string())?;

        let mut rows = stmt.query(params![id]).map_err(|e| e.to_string())?;
        match rows.next().map_err(|e| e.to_string())? {
            Some(row) => {
                let created_at_str: String = row.get(8).map_err(|e| e.to_string())?;
                let created_at = DateTime::parse_from_rfc3339(&created_at_str)
                    .map(|dt| dt.with_timezone(&Utc))
                    .unwrap_or_else(|_| Utc::now());

                Ok(Some(crate::entry::EntryAsset {
                    id: row.get(0).map_err(|e| e.to_string())?,
                    entry_id: row.get(1).map_err(|e| e.to_string())?,
                    file_name: row.get(2).map_err(|e| e.to_string())?,
                    mime_type: row.get(3).map_err(|e| e.to_string())?,
                    encrypted_size: row.get::<_, i64>(4).map_err(|e| e.to_string())? as u64,
                    nonce: row.get(5).map_err(|e| e.to_string())?,
                    salt: row.get(6).map_err(|e| e.to_string())?,
                    encrypted_data: row.get(7).map_err(|e| e.to_string())?,
                    created_at,
                }))
            },
            None => Ok(None),
        }
    }

    // FTS5 full-text search support
    pub fn index_entry_fts(
        &self, id: &str, body: &str, title: &str, tags: &[String], author: &str,
    ) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        conn.execute(
            "INSERT OR REPLACE INTO entries_fts (entry_id, body, display_title, tags, author)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![
                id,
                body,
                title,
                &tags.join(" "),
                author,
            ],
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn remove_entry_fts(&self, id: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        conn.execute(
            "DELETE FROM entries_fts WHERE entry_id=?1",
            params![id],
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn search_entries_fts(&self, query: &str) -> Result<Vec<JournalEntry>, String> {
        let conn = self.conn.lock().map_err(|e| e.to_string())?;
        let mut stmt = conn
            .prepare(
                "SELECT e.id, e.encrypted, e.nonce, e.salt, e.kind, e.tags, e.display_title,
                 e.pinned, e.mood, e.author, e.timestamp, e.plugin_origin, e.feedback, e.metadata,
                 e.priority, e.status, e.due_date, e.parent_project_id, e.history
                 FROM entries e
                 INNER JOIN entries_fts fts ON e.id = fts.entry_id
                 WHERE entries_fts MATCH ?1
                 ORDER BY rank",
            )
            .map_err(|e| e.to_string())?;

        let rows = stmt
            .query_map(params![query], |row| row_to_entry(row))
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
                 feedback, metadata, priority, status, due_date, parent_project_id, history)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19)",
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entry::encryption;

    fn test_storage() -> Storage {
        Storage::new(Path::new(":memory:")).expect("in-memory SQLite")
    }

    fn make_entry(id: &str, kind: &str, title: &str, author: &str) -> JournalEntry {
        let salt: [u8; 16] = rand::random();
        let key = encryption::derive_key("password", &salt);
        JournalEntry::new(
            id.to_string(),
            format!("Body of {}", title),
            author.to_string(),
            None,
            &key,
            salt.to_vec(),
            EntryKind::from_str(kind),
            vec!["test".to_string()],
            title.to_string(),
        )
    }

    #[test]
    fn test_folder_crud() {
        let storage = test_storage();

        let id1 = storage.create_folder("Folder A", None).unwrap();
        let id2 = storage.create_folder("Folder B", None).unwrap();
        let _child = storage.create_folder("Sub Folder", Some(&id1)).unwrap();

        let folders = storage.list_folders().unwrap();
        assert_eq!(folders.len(), 3);

        storage.delete_folder(&id2).unwrap();
        assert_eq!(storage.list_folders().unwrap().len(), 2);

        // Move entry to folder
        let entry = make_entry("folder-entry", "note", "In Folder", "test");
        storage.add_entry(&entry).unwrap();
        storage.move_to_folder("folder-entry", Some(&id1)).unwrap();
        let fetched = storage.get_entry("folder-entry").unwrap().unwrap();
        assert_eq!(fetched.parent_project_id, Some(id1));
    }

    #[test]
    fn test_pin_toggle() {
        let storage = test_storage();
        let entry = make_entry("pin-test", "note", "Pin Me", "test");
        storage.add_entry(&entry).unwrap();

        let pinned = storage.toggle_pin("pin-test").unwrap();
        assert!(pinned);

        let unpinned = storage.toggle_pin("pin-test").unwrap();
        assert!(!unpinned);
    }

    #[test]
    fn test_status_and_mood() {
        let storage = test_storage();
        let entry = make_entry("status-mood-test", "task", "Test Task", "test");
        storage.add_entry(&entry).unwrap();

        storage.set_entry_status("status-mood-test", "done").unwrap();
        let fetched = storage.get_entry("status-mood-test").unwrap().unwrap();
        assert_eq!(fetched.status, Some("done".to_string()));

        storage.set_entry_mood("status-mood-test", Some("😊")).unwrap();
        let fetched = storage.get_entry("status-mood-test").unwrap().unwrap();
        assert_eq!(fetched.mood, Some("😊".to_string()));

        storage.set_entry_mood("status-mood-test", None).unwrap();
        let fetched = storage.get_entry("status-mood-test").unwrap().unwrap();
        assert_eq!(fetched.mood, None);
    }

    #[test]
    fn test_fts5_basic() {
        // Test FTS5 with a regular (non-contentless) table
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE VIRTUAL TABLE IF NOT EXISTS test_fts USING fts5(a, b);"
        ).unwrap();
        conn.execute(
            "INSERT INTO test_fts (a, b) VALUES (?1, ?2)",
            params!["test-1", "the quick brown fox"],
        ).unwrap();
        let count: i64 = conn.query_row("SELECT COUNT(*) FROM test_fts", [], |row| row.get(0)).unwrap();
        assert_eq!(count, 1, "Should have 1 row");
        let mut stmt = conn.prepare("SELECT a FROM test_fts WHERE test_fts MATCH ?1").unwrap();
        let found: Vec<String> = stmt.query_map(params!["fox"], |row| row.get(0))
            .unwrap().filter_map(|r| r.ok()).collect();
        assert_eq!(found.len(), 1, "Should find 'fox', found {found:?}");
    }

    #[test]
    fn test_fts5_full_text_search() {
        let storage = test_storage();

        let salt: [u8; 16] = rand::random();
        let key = encryption::derive_key("pw", &salt);
        let entry = JournalEntry::new(
            "fts-test-1".to_string(),
            "The quick brown fox jumps over the lazy dog".to_string(),
            "author1".to_string(),
            None,
            &key,
            salt.to_vec(),
            EntryKind::Journal,
            vec!["nature".to_string()],
            "Fox Story".to_string(),
        );
        storage.add_entry(&entry).unwrap();

        storage.index_entry_fts("fts-test-1", "The quick brown fox jumps over the lazy dog", "Fox Story", &["nature".to_string()], "author1").unwrap();

        let results = storage.search_entries_fts("fox").unwrap();
        assert_eq!(results.len(), 1);

        let results = storage.search_entries_fts("brown").unwrap();
        assert_eq!(results.len(), 1);

        let results = storage.search_entries_fts("elephant").unwrap();
        assert_eq!(results.len(), 0);

        // Verify metadata search also works
        let results = storage.search_entries("Fox Story").unwrap();
        assert_eq!(results.len(), 1);
    }

    #[test]
    fn test_bulk_import() {
        let storage = test_storage();
        let mut entries = Vec::new();

        for i in 0..10 {
            let salt: [u8; 16] = rand::random();
            let key = encryption::derive_key("pw", &salt);
            entries.push(JournalEntry::new(
                format!("bulk-{}", i),
                format!("Entry {}", i),
                "importer".to_string(),
                None,
                &key,
                salt.to_vec(),
                EntryKind::Note,
                vec![],
                format!("Bulk Entry {}", i),
            ));
        }

        let count = storage.import_entries(&entries).unwrap();
        assert_eq!(count, 10);
        assert_eq!(storage.list_entries().unwrap().len(), 10);

        // Duplicate IDs should be ignored
        let count = storage.import_entries(&entries).unwrap();
        assert_eq!(count, 0);
    }

    #[test]
    fn test_update_preserves_fields() {
        let storage = test_storage();

        let salt: [u8; 16] = rand::random();
        let key = encryption::derive_key("pw", &salt);
        let mut entry = JournalEntry::new(
            "update-test".to_string(),
            "Original body".to_string(),
            "author".to_string(),
            None,
            &key,
            salt.to_vec(),
            EntryKind::Task,
            vec!["initial".to_string()],
            "Original Title".to_string(),
        );
        entry.priority = Some("high".to_string());
        entry.due_date = Some("2026-07-01".to_string());
        storage.add_entry(&entry).unwrap();

        // Update with new title and tags
        let mut updated = entry.clone();
        updated.display_title = "Updated Title".to_string();
        updated.tags = vec!["updated".to_string()];
        storage.update_entry(&updated).unwrap();

        let fetched = storage.get_entry("update-test").unwrap().unwrap();
        assert_eq!(fetched.display_title, "Updated Title");
        assert_eq!(fetched.tags, vec!["updated"]);
        // Priority and due_date should be preserved
        assert_eq!(fetched.priority, Some("high".to_string()));
        assert_eq!(fetched.due_date, Some("2026-07-01".to_string()));
    }
}

pub(crate) fn row_to_entry(row: &rusqlite::Row) -> Result<JournalEntry, rusqlite::Error> {
    let ts_str: String = row.get(10)?;
    let timestamp = DateTime::parse_from_rfc3339(&ts_str)
        .map(|dt| dt.with_timezone(&Utc))
        .unwrap_or_else(|_| Utc::now());

    let tags_str: String = row.get(5)?;
    let tags: Vec<String> = serde_json::from_str(&tags_str).unwrap_or_default();

    let metadata_str: String = row.get(13)?;
    let metadata: serde_json::Value = serde_json::from_str(&metadata_str).unwrap_or_else(|_| serde_json::json!({}));

    let history_str: String = row.get(18)?;
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
            metadata,
        },
        priority: row.get(14)?,
        status: row.get(15)?,
        due_date: row.get(16)?,
        parent_project_id: row.get(17)?,
        history,
        assets: Vec::new(),
    })
}
