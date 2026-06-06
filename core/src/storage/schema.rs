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
            priority        TEXT,
            status          TEXT DEFAULT 'todo',
            due_date        TEXT,
            parent_project_id TEXT,
            history         TEXT NOT NULL DEFAULT '[]',
            created_at      TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
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
    .map_err(|e| e.to_string())
}
