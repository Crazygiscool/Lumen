# Lumen Core Engine

The Rust core (`core/`) handles encryption, storage, entry management, authentication, plugin lifecycle, and sync. It compiles as both a `cdylib` (for FFI with the Flutter UI) and an `rlib` (for the TUI binary).

## Module Overview

```
core/src/
  entry/          # Journal entry structs, encryption, provenance
    mod.rs        # JournalEntry, EntryKind, Provenance, EditRecord
    encryption.rs # AES-256-GCM encrypt/decrypt, Argon2 key derivation
  storage/        # SQLite storage backend
    mod.rs        # Storage struct — CRUD, search, FTS5, folders, streak
    schema.rs     # SQL schema initialization and migrations
  auth.rs         # Session manager — password hashing, unlock/lock via Argon2
  plugins/        # Plugin runtime
    mod.rs        # PluginManager — orchestrates builtin + external plugins
    plugin_trait.rs # Plugin trait (on_entry, on_export)
    manifest.rs   # plugin.toml parser
    loader.rs     # Dynamic plugin loading via libloading
    builtin/      # Built-in plugins (export_md, daily_summary, wordcount)
  sync/           # Sync subsystem
    mod.rs        # SyncBackend trait, Conflict struct
    local_sqlite.rs # File-based SQLite sync with conflict detection
  feedback.rs     # Feedback engine (GEORGE)
  ffi.rs          # C-compatible FFI exports for Flutter/Dart
  lib.rs          # Crate root — re-exports all FFI functions
```

## Entry Module

`JournalEntry` is the core data structure:

- `id` — UUID v4 string
- `encrypted` / `nonce` / `salt` — AES-256-GCM encrypted body with per-entry key
- `kind` — `EntryKind` enum (Journal, Note, Task, Project, Custom)
- `tags` — `Vec<String>` for categorization
- `display_title` — optional plaintext title for list preview
- `pinned` — boolean, for pinboard functionality
- `mood` — optional mood string (journal entries)
- `priority` — task priority (low, medium, high)
- `status` — task status (todo, in_progress, done)
- `due_date` — optional due date (tasks/projects)
- `parent_project_id` — link to parent project
- `provenance` — author, timestamp, plugin_origin, feedback, metadata
- `history` — `Vec<EditRecord>` tracking edit history

Encryption uses AES-256-GCM with Argon2id key derivation (16-byte salt, 32-byte key).

## Storage Module

SQLite database at `{data_dir}/lumen/lumen.db`. Tables: `entries`, `entry_assets`, `folders`, `recurring_tasks`, `entries_fts` (FTS5 virtual table for full-text search). See `docs/storage.md` for schema details.

## Auth Module

Manages session keys in memory. Password-based unlock derives an Argon2 key, stores it in a `lazy_static Mutex`. FFI: `lumen_unlock`, `lumen_lock`, `lumen_has_password`, `lumen_set_password`, `lumen_is_unlocked`.

## Plugin System

`PluginManager` orchestrates built-in plugins (compiled in) and external plugins (loaded via `libloading` from `~/.local/share/lumen/plugins/`). Built-in plugins: Export Markdown, Daily Summary, Word Count Tracker. See `docs/plugins.md`.

## Sync

The `SyncBackend` trait defines push/pull/resolve. `LocalSqliteSync` syncs between SQLite databases on removable media or network shares. Conflict detection is timestamp-based; resolution is last-writer-wins with manual override.

## FFI Layer

All core functionality is exposed via `extern "C"` functions in `ffi.rs` for consumption by the Flutter UI and other C-compatible clients. Memory management uses `lumen_free_string` for strings returned to the caller.
