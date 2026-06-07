use rusqlite::Connection;

pub fn initialize(conn: &Connection) -> Result<(), String> {
    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS entries (
            id              TEXT PRIMARY KEY,
            encrypted       BLOB NOT NULL,
            nonce           BLOB NOT NULL,
            salt            BLOB NOT NULL,
            kind            TEXT NOT NULL DEFAULT 'journal',
            tags            TEXT NOT NULL DEFAULT '[]',
            display_title   TEXT NOT NULL DEFAULT '',
            pinned          INTEGER NOT NULL DEFAULT 0,
            mood            TEXT,
            author          TEXT NOT NULL,
            timestamp       TEXT NOT NULL,
            plugin_origin   TEXT,
            feedback        TEXT,
            metadata        TEXT NOT NULL DEFAULT '{}',
            priority        TEXT,
            status          TEXT DEFAULT 'todo',
            due_date        TEXT,
            parent_project_id TEXT,
            history         TEXT NOT NULL DEFAULT '[]',
            created_at      TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
            entry_id UNINDEXED,
            body,
            display_title,
            tags,
            author,
            content=''
        );

        CREATE TABLE IF NOT EXISTS entry_assets (
            id              TEXT PRIMARY KEY,
            entry_id        TEXT NOT NULL,
            file_name       TEXT NOT NULL,
            mime_type       TEXT NOT NULL,
            encrypted_size  INTEGER NOT NULL,
            nonce           BLOB NOT NULL,
            salt            BLOB NOT NULL,
            encrypted_data  BLOB NOT NULL DEFAULT x'',
            created_at      TEXT NOT NULL DEFAULT (datetime('now')),
            FOREIGN KEY(entry_id) REFERENCES entries(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS folders (
            id          TEXT PRIMARY KEY,
            name        TEXT NOT NULL,
            parent_id   TEXT,
            sort_order  INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS recurring_tasks (
            id            TEXT PRIMARY KEY,
            title         TEXT NOT NULL,
            every_n_days  INTEGER,
            day_of_week   INTEGER,
            priority      TEXT DEFAULT 'medium',
            tags          TEXT NOT NULL DEFAULT '[]',
            project_id    TEXT,
            created_at    TEXT NOT NULL DEFAULT (datetime('now')),
            next_due      TEXT NOT NULL
        );
        ",
    )
    .map_err(|e| e.to_string())?;

    // Migration: add encrypted_data column to entry_assets for existing DBs
    let _ = conn.execute_batch(
        "ALTER TABLE entry_assets ADD COLUMN encrypted_data BLOB NOT NULL DEFAULT x'';",
    );

    // Migration: add metadata column to entries for existing DBs
    let _ = conn.execute_batch(
        "ALTER TABLE entries ADD COLUMN metadata TEXT NOT NULL DEFAULT '{}';",
    );

    // Sync conflicts table (for sync DB)
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS sync_conflicts (
            id              TEXT PRIMARY KEY,
            entry_id        TEXT NOT NULL,
            local_timestamp TEXT NOT NULL,
            remote_timestamp TEXT NOT NULL,
            local_entry_json TEXT NOT NULL,
            remote_entry_json TEXT NOT NULL,
            created_at      TEXT NOT NULL DEFAULT (datetime('now')),
            resolved        INTEGER NOT NULL DEFAULT 0
        );",
    )
    .map_err(|e| e.to_string())?;

    Ok(())
}
