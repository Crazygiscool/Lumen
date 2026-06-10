# Lumen Development Roadmap

From encrypted journaling engine to a full localized productivity platform — covering notes, project planning, task management, and more — while remaining offline-first, private, and modular.

---

## Guiding Principles

- **Offline-first** — every feature must work without internet. Sync is optional, never required.
- **Privacy by default** — all content encrypted locally. No telemetry, no cloud dependency.
- **Modular** — core engine decoupled from UI. Plugins add functionality without fork-bombing the monolith.
- **Provenance-aware** — every entry tracks origin, authorship, and edit history. Useful for journaling, critical for project collaboration.
- **Non-commercial** — the license forbids commercial use. The architecture reflects that: no SaaS hooks, no paywalls.

---

## Phase 0 — Architectural Debt ✅

- **Persistent storage wiring** — auto-load from `{data_dir}/lumen/journal.bin` on first FFI call, auto-save after every `add_entry`. Corrupted files renamed to `.bin.corrupted`.
- **FFI memory leaks** — fixed: `lumen_free_string` called from Dart after every `listEntries`/`decryptEntry`.
- **Flutter state management** — deferred to Phase 3 (Riverpod).
- **Cargo.lock for release builds** — deferred to build script updates (add `--locked`).

## Phase 1 — Data Model Expansion ✅

- **Entry kind system** — `EntryKind` enum (Journal/Note/Task/Project/Custom) with custom serde (lowercase strings).
- **Tags** — `tags: Vec<String>` in plaintext metadata for searchability.
- **Content format** — `flutter_markdown` rendering with selectable text and task checklist support.
- **YAML frontmatter** — kind-specific structured data (`title`, `priority`) saved as `---\nkey: value\n---` in encrypted body; parsed on decrypt for clean display.
- **`display_title`** — optional plaintext field for list preview. Toggle in UI to encrypt title or not.
- **Migration path** — `#[serde(default)]` on `kind`, `tags`, `display_title` so old entries load without stubs.
- **Search index** — replaced by SQLite FTS5 in Phase 1b.

### Files changed
- `core/src/entry/mod.rs`, `core/src/ffi.rs`, `core/src/lib.rs`
- `ui/lib/core/lumen_core.dart`, `ui/lib/core/models/journal_entry.dart`
- `ui/lib/screens/journal_list_screen.dart`, `ui/lib/screens/new_entry_screen.dart`, `ui/lib/screens/entry_view_screen.dart`
- `ui/lib/widgets/entry_card.dart`
- `ui/lib/utils/frontmatter.dart` (new)

---

## Phase 1b — SQLite Migration ✅

Replace bincode serialization with SQLite as the single storage backend. Combines persistent storage, search, and metadata filtering into one engine.

### What to do

#### core (Rust)
- **`core/Cargo.toml`** — add `rusqlite = { version = "0.34", features = ["bundled"] }`, remove `bincode`.
- **`core/src/storage/mod.rs`** — rewrite `Storage` to use SQLite at `{data_dir}/lumen/lumen.db`.
- **`core/src/storage/schema.rs`** — define and migrate the schema.

```sql
CREATE TABLE entries (
    id TEXT PRIMARY KEY,
    encrypted BLOB NOT NULL,
    nonce BLOB NOT NULL,
    salt BLOB NOT NULL,
    kind TEXT NOT NULL DEFAULT 'journal',
    tags TEXT NOT NULL DEFAULT '[]',
    display_title TEXT NOT NULL DEFAULT '',
    pinned INTEGER NOT NULL DEFAULT 0,
    mood TEXT,
    author TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    plugin_origin TEXT,
    feedback TEXT,
    priority TEXT,
    status TEXT DEFAULT 'todo',
    due_date TEXT,
    parent_project_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE folders (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE recurring_tasks (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    every_n_days INTEGER,
    day_of_week INTEGER,
    priority TEXT DEFAULT 'medium',
    tags TEXT NOT NULL DEFAULT '[]',
    project_id TEXT,
    created_at TEXT NOT NULL,
    next_due TEXT NOT NULL
);
```

- **Migration from bincode**: detect `journal.bin`, read entries, write to SQLite, rename `journal.bin` → `journal.bin.migrated`.
- **Search**: SQL `WHERE` / `LIKE` on plaintext columns (kind, tags, display_title, author, timestamp). Body stays encrypted — no FTS on ciphertext. Body content search can be added later via a `search_terms` column with hashed tokens.
- **New FFI functions**:
  - `lumen_update_entry(id, text, author, password, kind, tags_json, display_title)` — update body + metadata
  - `lumen_delete_entry(id)` — delete by ID
  - `lumen_search_entries(query)` — SQL WHERE on metadata fields, returns JSON array

#### ui (Flutter)
- **`ui/lib/core/lumen_core.dart`** — add `updateEntry()`, `deleteEntry()`, `searchEntries()` methods.
- **`ui/lib/core/models/journal_entry.dart`** — unchanged (JSON mapping stays the same).

#### Dependencies
```
Add:  rusqlite (bundled SQLite)
Remove:  bincode
Unchanged:  chrono, serde, serde_json, rand, aes-gcm, argon2, lazy_static, dirs, base64
```

---

## Phase 2 — Feature Modules ✅

### 2a: Journaling refinements

#### core
- **`core/src/entry/mod.rs`** — add `EditRecord { timestamp, author, reason }` struct. `Provenance.history: Vec<EditRecord>` appended on each `update_entry`.
- **FFI** — `lumen_get_streak() -> u32` — `SELECT DISTINCT DATE(timestamp) FROM entries WHERE kind='journal' ORDER BY timestamp DESC`, count consecutive days from today backward.

#### ui
- **`ui/lib/screens/new_entry_screen.dart`** — mood emoji picker row (😊 😐 😔 😡 😴) shown when `kind == 'journal'`. Saved as `mood` metadata.
- **`ui/lib/utils/journal_prompts.dart`** — local JSON bank of ~50 writing prompts. Random prompt displayed above body field on new journal entry.
- **`ui/lib/widgets/streak_widget.dart`** — calls `lumen_get_streak()`, displays flame icon + count in sidebar/journal view.
- **Edit history** — `entry_view_screen.dart` shows history timeline when kind=journal and `history` is non-empty.

### 2b: Note-taking subsystem

#### core
- **`core/src/ffi.rs`** — `lumen_list_folders()` → JSON, `lumen_create_folder(name, parent_id)` → folder ID, `lumen_delete_folder(id)`, `lumen_move_to_folder(entry_id, folder_id)`.
- Folders stored in the `folders` table (already in schema). Max nested depth: 3.

#### ui
- **`ui/lib/screens/note_list_screen.dart`** — folder tree sidebar + note list filtered by selected folder. "New Folder" context menu.
- **`ui/lib/utils/wiki_links.dart`** — regex `\[\[([^\]]+)\]\]` detected in Markdown body. Custom `MarkdownElementBuilder` that renders matched text as a tappable `TextSpan`. On tap → `Navigator.push` to view target entry (resolved by ID or display_title lookup).
- **Pinboard** — `pinned` column already in schema. Sort `pinned DESC, timestamp DESC` in list queries. Pin/unpin via long-press context menu.
- **Quick capture** — `ui/lib/screens/quick_note_screen.dart` — small floating window (popup). Saves as `kind=note`, tagged `inbox`. Platform hotkey implementation deferred (requires native plugin).

### 2c: Task management

#### core
- **`core/src/ffi.rs`** — `lumen_parse_task(text) -> *mut c_char` — Rust-side natural language parser returning JSON:
  ```json
  {"title": "Buy groceries", "priority": "high", "due_date": "2026-06-12", "tags": ["personal"]}
  ```
  Parses:
  - `p:high` / `priority:high` → priority
  - `due:friday` / `due:2026-06-10` / `due:next week` → due_date via `chrono`
  - `#tag` → tags
  - All other text → title

#### ui
- **`ui/lib/screens/task_list_screen.dart`** — filter tabs: Today / Upcoming / All / By Project. Each calls appropriate SQL query:
  - Today: `WHERE kind='task' AND due_date = date('now')`
  - Upcoming: `WHERE kind='task' AND due_date > date('now') AND status != 'done'`
  - All: `WHERE kind='task'`
  - By Project: `WHERE kind='task' AND parent_project_id = ?`
- **`ui/lib/widgets/quick_add_bar.dart`** — text field at top of task list. On submit → calls `lumen_parse_task` → shows populated form for confirmation → saves.
- **`ui/lib/screens/kanban_screen.dart`** — three columns: Todo / In Progress / Done. Tasks rendered as draggable cards. On drop into new column → calls `lumen_update_entry` to set `status`. Kanban is filtered by `parent_project_id` (project-level) or all tasks.
- **`core/src/entry/recurring.rs`** — on app init startup, query `recurring_tasks` table. For each task where `next_due <= now()`, generate a child entry of `kind=task` with the recurring task's metadata. Update `next_due` based on interval. Runs in `ensure_loaded()`.

### 2d: Project planning

#### ui
- **`ui/lib/screens/project_list_screen.dart`** — lists entries where `kind='project'`. Each project card shows status, task count, date range. Tap → project detail view with milestone list + kanban board filtered by `parent_project_id`.
- **Milestones** — entries with `kind` set in frontmatter or as a separate kind. Filtered by `parent_project_id`. Displayed as a timeline section in project detail.
- **`ui/lib/widgets/gantt_chart.dart`** — `CustomPainter` rendering tasks as horizontal bars on a date axis. X-axis = dates, Y-axis = tasks sorted by due_date. Scrollable horizontally, pinch-zoom. All entries decrypted once and cached for the view.
- **Project export** — `lumen_export_project(project_id, password)` → iterates project task entries, decrypts each, concatenates as a single Markdown document with `##` headings per task. Returns string via FFI.

### 2e: Entry import/export

#### core
- **`core/src/ffi.rs`** — `lumen_export_all(password) -> *mut c_char` — JSON array of `{id, kind, body, metadata}` with all entries decrypted. `lumen_import(json) -> i32` — batch INSERT, returns count of imported entries.

#### ui
- **`ui/lib/screens/export_screen.dart`** — wizard: select scope (single entry / project / all), choose format (Markdown / `.lumenpack` encrypted archive), pick save directory via file dialog. Warn user that Markdown export is plaintext.
- **`ui/lib/screens/import_screen.dart`** — file picker → parse JSON or Markdown frontmatter → preview list of detected entries → confirm import → batch insert.

---

## Phase 3 — State Management and UI Redesign ✅

### State layer

- **`ui/pubspec.yaml`** — add `flutter_riverpod`.
- **`ui/lib/core/services/lumen_service.dart`** — `StateNotifierProvider<LumenService, List<JournalEntry>>` wrapping all FFI calls. Entry list cached in memory, refreshed after every mutation (add/update/delete). Screens consume via `ref.watch(lumenServiceProvider)`.
- **`ui/lib/main.dart`** — wrap in `ProviderScope`. Remove `required this.lumen` threading; screens get services via Riverpod.
- **`ui/lib/core/services/auth_service.dart`** — wraps `lumen_unlock`/`lumen_lock` calls. Exposes `isUnlocked` state. Stub for Phase 5.

### UI alignment with DESIGN.md

- **`ui/lib/utils/theme.dart`** — complete rewrite to dark theme:
  - Background: `#0f172a` (obsidian)
  - Surface: `#1e293b` (charcoal) for cards, sidebar, inputs
  - Primary: `#1e2ebd` (deep cobalt) for buttons, focus states
  - Secondary: `#c4b5fd` (violet) for accents
  - Borders: 1px solid `#334155`
  - Border radius: `4px` (0.25rem) for components, up to `8px` for containers
  - All color values from `DESIGN.md`
- **Geist font** — bundled in `ui/fonts/`:
  - `Geist-Regular.ttf`, `Geist-Bold.ttf`, `Geist-Medium.ttf`, `Geist-SemiBold.ttf`, `Geist-Mono.ttf`
  - Declared in `pubspec.yaml` fonts section (offline-first, no network needed)
- **`ui/lib/screens/home_screen.dart`** — new root screen:
  - `Row` with fixed left sidebar (280px) + content area
  - Sidebar items: Journal, Notes, Tasks, Projects, Settings (icons + labels)
  - Active section highlighted with primary-colored left border (2px, the "lumen")
  - Search bar at top of sidebar
- **`ui/lib/widgets/entry_card.dart`** — replace `Card(elevation: 2)` with `Container`: 1px `#334155` border, `#1e293b` background, 0.25rem radius. No elevation (matches DESIGN.md "sheets of paper").
- **Status badges** — small `Container(8x8, circle)` colored dot next to each entry title: green (encrypted), grey (placeholder for future sync status).

### Responsive layout

- **`ui/lib/utils/responsive.dart`** — breakpoint utilities:
  - `isNarrow(context)` — `MediaQuery.of(context).size.width < 800`
  - `isWide(context)` — `MediaQuery.of(context).size.width >= 800`
- **Desktop (default, wide)** — sidebar (280px) | list (300px) | detail/editor (fluid, max 900px). Three-column `Row`.
- **Narrow (< 800px)** — list and detail collapse into single stack, navigated by back/forward (Navigator push/replace). Sidebar becomes a hamburger `Drawer`.
- **Writing view** — full-screen editor, centered column max-width 900px. Title and metadata controls visible on focus/hover (future enhancement).
- **Focus mode** — `Ctrl+.` / `Cmd+.` toggles. Hides sidebar + list columns, showing only editor or reading view. Implemented via `KeyboardListener` at `HomeScreen` level.

---

## Phase 4 — Plugin System Wiring ✅

### Current state

- `Plugin` trait: `on_entry`, `on_export` hooks exist but `run_on_entry` discards return values.
- `plugin.toml` manifest documented in `docs/plugins.md` but no parser exists.
- No dynamic loading mechanism.

### What to build

- **`core/Cargo.toml`** — add `libloading = "0.8"`.
- **`core/src/plugins/manifest.rs`** — `PluginManifest { name, version, author, description, hooks: Vec<String> }`. Parsed from `plugin.toml` files.
- **`core/src/plugins/loader.rs`** — scans `~/.lumen/plugins/*/plugin.toml`, loads each plugin's `.so`/`.dylib` via `libloading`. Each plugin exports C-compatible functions: `lumen_plugin_on_entry`, `lumen_plugin_on_export`.
- **`core/src/plugins/mod.rs`** — update `PluginManager`:
  - `run_on_entry(&self, entry: &JournalEntry) -> Vec<String>` — collects feedback strings instead of discarding.
  - `Provenance.feedback` — populated with plugin feedback in `lumen_add_entry`, after encryption but before save.
- **Plugin sandboxing** — document that plugins share the process address space. No Wasm sandbox; audit manually.

### Built-in plugin: Export Markdown

- **`core/src/plugins/builtin/export_md.rs`** — registered by default. Iterates entries of a given project, decrypts, writes `.md` files to a chosen directory.

### Built-in plugin: Daily summary
- **`core/src/plugins/builtin/daily_summary.rs`** — collects all today's entries, renders a single read-only Markdown digest.

### Built-in plugin: Word count tracker
- **`core/src/plugins/builtin/wordcount.rs`** — logs word counts per entry to a sidecar table. Displays a simple chart on the dashboard.

---

## Phase 5 — Authentication and Multi-Entry Support (v2.2.3 partial) ✅

### Session management

- **`core/src/auth.rs`** — `SessionManager` struct holding `Option<[u8; 32]>` session key in memory.
- **FFI**:
  - `lumen_unlock(password)` — derives Argon2 key, stores in `SessionManager`.
  - `lumen_lock()` — clears session key.
- **Existing FFI signatures unchanged** — `lumen_add_entry` and `lumen_decrypt_entry` still accept a `password` param. If a session key is active, the password param is ignored and the session key is used instead. This maintains backward compatibility while enabling the auto-unlock flow.
- **`ui/lib/screens/lock_screen.dart`** — full-screen password prompt on app launch. "Lock" button in sidebar to re-lock.
- **`ui/lib/core/services/auth_service.dart`** — wraps unlock/lock, exposes `isUnlocked` state to Riverpod.
- **User profiles** — Multi-author support with Admin/Member permissions and password-protected user switching.

### Multiple vaults

- **`core/src/ffi.rs`** — `lumen_open_vault(path)` changes `DATA_PATH` to a new directory. Each vault is a separate `lumen.db`. `lumen_list_vaults()` scans `~/.lumen/*/lumen.db`.
- **Vault config** — `~/.lumen/<vault>/config.toml` stores settings (theme preference, last-active section).
- **`ui/lib/widgets/vault_switcher.dart`** — dropdown at top of sidebar. "New Vault" button beside it.

### Biometric unlock (Deferred)

- **`ui/lib/core/services/biometric_service.dart`** — uses `local_auth` Flutter package for platform biometric prompt (Windows Hello, macOS Touch ID, Linux `libsecret`/`pam`).
- On first unlock, store a keychain entry that returns the Argon2-derived key after biometric verification.
- On subsequent launches, biometric prompt retrieves the session key from the keychain. If unavailable, fall back to password prompt.
- **Status**: Postponed for future security hardening pass.

---

## Phase 6 — Sync (Local SQLite - Manual) ✅

### Architecture

Sync is fully local (no cloud). Data is copied between SQLite databases on removable media or network shares.

- **`core/src/sync/mod.rs`** — `trait SyncBackend`:
  ```rust
  pub trait SyncBackend {
      fn push(&self, entry_ids: &[String]) -> Result<(), String>;
      fn pull(&self) -> Result<Vec<JournalEntry>, String>;
      fn resolve(&self, conflicts: Vec<Conflict>) -> Vec<JournalEntry>;
  }
  ```
- **`core/src/sync/local_sqlite.rs`** — opens a second SQLite DB at a user-specified path (e.g., USB drive `E:/lumen_sync.db`):
  - `push` — copies entries from primary DB to sync DB (INSERT OR REPLACE).
  - `pull` — copies entries from sync DB into primary DB.
  - `resolve` — last-writer-wins by `provenance.timestamp`. Stores conflicting versions in a `conflicts` table.
- **Frequency** — manual "Sync Now" implemented in UI. Auto-sync (debounced 30s) deferred.
- **`ui/lib/screens/sync_settings_screen.dart`** — configure sync directory path, "Sync Now" button, conflict list UI.
- **Conflict UI** — list of conflicted entries showing local vs remote. User can accept local, accept remote, or view both.

---

## Phase 7 — Localization ✅

- **`ui/pubspec.yaml`** — add `flutter_localizations` (sdk).
- **`ui/lib/l10n/`** — `app_en.arb`, `app_es.arb`, `app_fr.arb` with extracted strings.
- **`ui/lib/main.dart`** — add `localizationsDelegates`, `supportedLocales: [Locale('en'), Locale('es'), Locale('fr')]`.
- Extract all hardcoded user-facing strings from screens into ARB references. Rust core continues to produce machine-readable output (JSON, error codes), not user-facing strings.

---

## TUI ✅

Expand `tui/lumen_tui.rs` from welcome-message stub to a read-only terminal client:

- Open the SQLite DB at `{data_dir}/lumen/lumen.db`.
- List entries (paginated, with kind badge).
- Select an entry → enter password → decrypt and display body.
- Search by kind/date range via CLI flags (`--kind task`, `--since 2026-01-01`).
- Uses `clap` for argument parsing, `chrono` for date handling.

---

## Build and Distribution (v2.2.3) ✅

### Linux

- `scripts/build_linux.sh` — add `--locked` flag.
- **AppImage** — wrap Flutter bundle + `.so` into AppImage via `appimagetool`.
- **Flatpak** — `flatpak-builder` manifest.
- **AUR** — already maintained. Update PKGBUILD to handle SQLite dependency (bundled in binary, no extra dep needed).
- **TUI** — binary `lumen-cli` included in the distribution bundle.

### macOS

- `scripts/build_macos.sh` — add `--locked` flag.
- Notarize `.app` bundle with `xcrun notarytool` for distribution outside App Store.
- **TUI** — binary `lumen-cli` included in the release zip.

### Windows

- `scripts/build_windows.sh` — add `--locked` flag.
- **MSI installer** — WiX or InnoSetup for proper installer.
- **TUI** — binary `lumen-cli.exe` included in the release zip.

### CI/CD

- `.github/workflows/release.yml` — on tag push, build all 3 platforms, upload artifacts to release.
- Linux: `ubuntu-latest`, macOS: `macos-latest`, Windows: `windows-latest`.
- Each job runs the appropriate `build_*.sh` script.

---

## Testing Strategy ✅

### Rust core

- Unit tests for encryption/decryption round-trips, SQL queries, tag parsing.
- Integration tests for FFI functions through safe wrappers.
- `proptest` for property-based encryption idempotency checks.

### Flutter UI

- Widget tests for each screen (empty state, populated state, error state).
- Golden tests for visual regression during Phase 3 redesign.
- `integration_test` package with mock Rust backend for full user flows.

### TUI

- Snapshot tests with `insta` or `assert_cmd`.

---

## Important Non-Goals

- **Cloud sync as default** — sync is optional, opt-in, local-only. Zero cloud dependencies.
- **Mobile platforms** — desktop-only UX. iOS/Android would require a separate design pass.
- **Real-time collaboration** — last-writer-wins conflict resolution is sufficient.
- **Plugin sandboxing** — Wasm-based sandboxing is a significant project. Document the limitation.
- **Self-hosted server** — sync is peer-to-peer between SQLite databases on local media.
