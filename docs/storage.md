# Storage Format

Lumen uses SQLite as its single storage backend. The database is located at `{data_dir}/lumen/lumen.db`. On Linux this is typically `~/.local/share/lumen/lumen.db`.

## Schema

### entries

Main table for all journal entries, notes, tasks, and projects.

```sql
CREATE TABLE entries (
    id               TEXT PRIMARY KEY,
    encrypted        BLOB NOT NULL,
    nonce            BLOB NOT NULL,
    salt             BLOB NOT NULL,
    kind             TEXT NOT NULL DEFAULT 'journal',
    tags             TEXT NOT NULL DEFAULT '[]',
    display_title    TEXT NOT NULL DEFAULT '',
    pinned           INTEGER NOT NULL DEFAULT 0,
    mood             TEXT,
    author           TEXT NOT NULL,
    timestamp        TEXT NOT NULL,
    plugin_origin    TEXT,
    feedback         TEXT,
    metadata         TEXT NOT NULL DEFAULT '{}',
    priority         TEXT,
    status           TEXT DEFAULT 'todo',
    due_date         TEXT,
    parent_project_id TEXT,
    history          TEXT NOT NULL DEFAULT '[]',
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at       TEXT NOT NULL DEFAULT (datetime('now'))
);
```

- `encrypted`, `nonce`, `salt` — AES-256-GCM encrypted body and per-entry encryption parameters
- `kind` — lowercase string: `journal`, `note`, `task`, `project`, `custom`
- `tags`, `display_title`, `pinned` — plaintext metadata for searchability and list display
- `mood` — emoji mood string for journal entries
- `metadata` — JSON blob for kind-specific structured data (YAML frontmatter content)
- `priority`, `status`, `due_date`, `parent_project_id` — task/project management fields
- `history` — JSON array of `EditRecord` objects tracking provenance

### entries_fts (FTS5 virtual table)

Full-text search index for body content. Updated on every entry add/update/delete.

```sql
CREATE VIRTUAL TABLE entries_fts USING fts5(
    entry_id UNINDEXED,
    body,
    display_title,
    tags,
    author,
    content=''
);
```

The `body` column stores the **decrypted** plaintext of the entry. The table is contentless-external (`content=''`), meaning only indexed terms are stored, not the full text.

### entry_assets

Attachments linked to entries.

```sql
CREATE TABLE entry_assets (
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
```

### folders

Hierarchical folder structure for notes (max 3 levels deep).

```sql
CREATE TABLE folders (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    parent_id   TEXT,
    sort_order  INTEGER NOT NULL DEFAULT 0
);
```

### recurring_tasks

Template tasks that generate child entries on a schedule.

```sql
CREATE TABLE recurring_tasks (
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
```

### sync_conflicts

Conflict tracking for local sync. Created in both primary and sync databases.

```sql
CREATE TABLE sync_conflicts (
    id               TEXT PRIMARY KEY,
    entry_id         TEXT NOT NULL,
    local_timestamp  TEXT NOT NULL,
    remote_timestamp TEXT NOT NULL,
    local_entry_json TEXT NOT NULL,
    remote_entry_json TEXT NOT NULL,
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    resolved         INTEGER NOT NULL DEFAULT 0
);
```

## Encryption

Each entry is encrypted individually:

1. **Key derivation**: User's password + per-entry 16-byte random salt → Argon2id → 32-byte key
2. **Encryption**: Plaintext body → AES-256-GCM → ciphertext + 12-byte nonce
3. **Storage**: Ciphertext, nonce, and salt stored as BLOB columns in the `entries` table

Encryption is performed entirely on the Rust side. The Flutter UI never has access to unencrypted key material.

## Migration from bincode (Legacy)

Previous versions used `journal.bin` with bincode serialization. On first load after the SQLite migration, the engine detects `journal.bin`, reads all entries, writes them to SQLite, and renames `journal.bin` → `journal.bin.migrated`.
