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

## Phase 0 — Architectural Debt (must fix before building)

These are bugs and omissions in the current codebase that will block every subsequent phase if left unfixed.

### Persistent storage wiring

**Problem**: `Storage::save_to_file` and `load_from_file` exist in `core/src/storage/mod.rs` but are never called from the FFI layer. All data lives in a `Vec<JournalEntry>` in memory. Restarting the app erases everything.

**What to do**:
- Choose a default file path for the journal data file (e.g. `~/.lumen/journal.bin` on Unix, `%APPDATA%/Lumen/journal.bin` on Windows).
- Call `load_from_file` once during FFI initialization so existing entries survive restarts.
- Call `save_to_file` after every `add_entry` call. This is write-amortized enough for journaling, but may need deferral (batch save on timer) for high-frequency use later.
- Expose the data file path (or an alternative path) through the FFI so the Flutter side can offer "export journal" / "import journal" in settings.

### FFI memory leaks

**Problem**: `lumen_list_entries` and `lumen_decrypt_entry` return `*mut c_char` allocated by Rust (`CString::into_raw()`). The Dart side never calls `lumen_free_string`, so every call leaks memory.

**What to do**:
- On the Dart side (`ui/lib/core/lumen_core.dart`), look up the `lumen_free_string` function and call it on every returned pointer after the string has been read.
- Alternatively, change the FFI contract: return the string in a pre-allocated buffer passed by the caller, avoiding heap allocation on the Rust side. This is more idiomatic for FFI but requires changing all four exported functions.

### Flutter state management

**Problem**: `JournalListScreen` uses raw `setState` to reload the entire entry list after every operation. As features grow, this will cause unnecessary rebuilds, stale data, and tangled UI logic.

**What to do**:
- Introduce a state management library. Provider is the simplest path and is Flutter-endorsed. Riverpod is a more modern alternative with better testability.
- The `LumenCore` FFI wrapper should become a service class, registered at the app root, rather than threaded through widget constructors via `required this.lumen`.

### Cargo.lock missing for release builds

**Problem**: `Cargo.lock` exists in the repo but the build scripts run `cargo build --release` without `--locked`. This means different build machines may resolve different dependency versions, potentially introducing subtle bugs.

**What to do**:
- Add `--locked` to both `build_linux.sh` and `build_windows.sh` after verifying the lockfile is up to date with `cargo update`.

---

## Phase 1 — Data Model Expansion

The current `JournalEntry` represents a single encrypted text blob with provenance metadata. To support notes, tasks, and projects, this model must become polymorphic.

### Entry kind system

Introduce a `kind` field on `JournalEntry`:

```
entry_kind: enum {
    JournalEntry,
    Note,
    Task,
    Project,
    Milestone,
    Custom
}
```

Each kind carries optional type-specific metadata stored alongside the encrypted payload. The metadata itself is unencrypted (for searchability) but minimal to avoid leaking content:

- **Task**: `status` (todo/in_progress/done/archived), `due_date`, `priority`, `assignee`, `parent_project_id`
- **Project**: `start_date`, `target_date`, `status`, `color_label`, `member_ids`
- **Milestone**: `target_date`, `parent_project_id`, `is_complete`
- **Note**: `tags[]`, `pinned`, `word_count`

Because metadata is unencrypted, the search index never needs to decrypt entries. The encrypted payload remains the entry body.

### Content format upgrade

Current entries store plaintext. For notes and projects, Markdown is the natural format:

- Store body as Markdown text, encrypt the raw Markdown string.
- On the Flutter side, render with a `flutter_markdown` widget.
- For tasks, support Markdown checklists (`- [ ]` / `- [x]`) as a rendering convention.

### Tags and cross-cutting concerns

A simple tag system that sits outside the encrypted body so it is searchable without decryption:

```
tags: Vec<String>
```

Tags are stored in plaintext (alongside `provenance`). The tradeoff is accepted: tags are metadata, not content. A future enhancement could encrypt tag names with a separate key.

### Search index

Without a database, search means decrypting every entry and scanning — impractical at scale. A local search index solves this:

- Maintain a sidecar file alongside `journal.bin` (e.g. `journal.idx`) that maps term hashes to entry IDs.
- Build or update the index incrementally when entries are added/edited.
- The index itself is stored unencrypted (a hash of each word, not the word itself). For stronger privacy, encrypt the index with a derived key.
- On the Flutter side, expose a `search(query)` FFI function that consults the index, returns matching entry IDs, then lazily decrypts only those entries for display.

Do not attempt to build a general-purpose database. A flat-file index is sufficient for a single-user desktop app with thousands of entries.

### Migration path for existing entries

Existing entries have no `kind` field. On first launch after the migration:

- Entries without `kind` default to `JournalEntry`.
- The `tags` field defaults to an empty vector.
- No re-encryption needed; the struct change is additive.

---

## Phase 2 — Feature Modules

Once the data model supports multiple entry kinds, build the feature-specific UIs and backend logic.

### Journaling refinements

- **Writing prompt system** — a local bank of prompts; daily or random prompt shown on new entry creation.
- **Mood/emotional tagging** — before encrypted save, user selects a mood emoji; stored in unencrypted metadata.
- **Streak tracking** — count consecutive days with at least one journal entry; displayed as a widget in the journal view.
- **Entry history / edit provenance** — each edit appends to a `history: Vec<EditRecord>` where each record stores a timestamp and the plugin or user that made the change. Only the *latest* encrypted body need be stored, but the history chain proves integrity.

### Note-taking subsystem

- **Quick note capture** — a global hotkey (platform-native) that opens a small floating window. The note is saved as kind `Note`, tagged automatically with `inbox`.
- **Folders** — a lightweight hierarchical folder system mapped as `folder_id: Option<Uuid>`. Folders are stored as a separate flat file (`folders.json`, unencrypted). A folder contains only IDs — no content.
- **Linking between notes** — wiki-style `[[note-id-or-title]]` links. The renderer detects these and creates in-app navigation. The link target is resolved by ID lookup, not by decrypting content.
- **Pinboard / favorites** — pinned entries appear at the top of their respective list views.

### Task management

- **Task views** — "Today", "Upcoming", "All", "By Project". Each filters by `kind == Task` and applies the relevant metadata filter.
- **Quick-add task bar** — a text field at the top of the task view that parses `"Buy groceries p:high due:friday #personal"` into structured fields. Natural-language date parsing (e.g. `chrono` on the Rust side or `chrono`-like logic).
- **Kanban board** — a project-level view showing tasks grouped by `status`. Drag-and-drop changes status. Implemented entirely on the Flutter side; it merely re-orders displayed entries without changing their storage.
- **Recurring tasks** — a separate `RecurringTask` struct stored in a sidecar file. On each app launch, check if any recurring tasks are due and create the corresponding child tasks. Recurrence rules follow a simplified iCalendar subset.

### Project planning

- **Project entity** — a project is an entry of kind `Project` containing a Markdown description, a list of member IDs, and a status.
- **Milestone tracking** — milestones are child entries linked by `parent_project_id`.
- **Gantt / timeline view** — a horizontal timeline rendered on the Flutter canvas using `CustomPainter`, reading task `due_date` and `status` from metadata. All entries on screen are decrypted once and cached.
- **Project export** — export a project's entries (ordered by timestamp) as a single Markdown document. This reuses the existing export plugin hook.

### Entry import/export

The existing `import/export` feature is mentioned in README but not implemented:

- **Export** — iterate entries, decrypt each with the provided password, write to Markdown. Offer per-entry and batch export.
- **Import** — parse Markdown files (detecting frontmatter for metadata) and create entries. Unknown metadata fields are silently dropped.
- **Plaintext worry** — the exported Markdown is plaintext. The app must warn the user that exported files are not encrypted. Consider a "re-encrypt export" option that produces an encrypted `.lumenpack` archive instead.

---

## Phase 3 — State Management and UI Redesign

### State layer

Replace the ad-hoc `LumenCore` threading pattern with a proper service layer:

- `LumenService` — wraps all FFI calls and maintains an in-memory cache of the entry list.
- `AuthService` — manages the master password session (see Phase 5). Stores a session token derived from the password so the user does not re-enter it on every operation.
- `SearchService` — coordinates with the search index, returns entry references.
- `PluginService` — manages the plugin lifecycle and routes hook results.

On the Flutter side, these services are provided via dependency injection (Provider or Riverpod). Screens consume them without knowing about FFI.

### UI alignment with DESIGN.md

The current light-yellow theme differs significantly from the dark-mode design spec in `DESIGN.md`. A phased UI rewrite:

- **Theme system** — define light and dark variants. The dark variant matches `DESIGN.md` (obsidian background, deep cobalt primary, Geist typography). The light variant is an inversion (white background, dark text).
- **Sidebar navigation** — replace the default `AppBar` + FAB layout with a fixed left sidebar (matching the DESIGN.md spec). The sidebar contains: Journal, Notes, Tasks, Projects, Settings, and a search bar. Active section is highlighted with a primary-colored left border ("the lumen").
- **Writing view** — full-screen editor with minimal chrome. The text area is centered, max-width 900px. Title and metadata controls slide in on hover/focus.
- **Entry cards** — replace the `Card(elevation: 2)` with a border-only card (1px solid `#334155` in dark mode), matching the "sheets of paper" concept from DESIGN.md.
- **Typography** — add Geist font (open source, available from Vercel's CDN or bundled as an asset). Define text styles matching the DESIGN.md spec (body-lg at 18px/28px line height for reading, code-sm at 13px for inline code).
- **Status badges** — small colored dots next to entry titles indicating encryption status and sync status (if sync is configured).

### Responsive layout

- **Desktop** (default): three-column layout — sidebar | list | detail/editor. The list column is ~300px, the detail column is fluid with max 900px.
- **Narrow window** (< 800px): the list and detail columns collapse into a single stack, navigated by back/forward (like a mobile layout). The sidebar becomes a hamburger drawer.
- **Focus mode** — hides the sidebar and list columns, showing only the editor or reading view. Toggled by `Ctrl+.` (or `Cmd+.`).

---

## Phase 4 — Plugin System Wiring

The plugin infrastructure exists as Rust traits but is never invoked in the real data path. Completing it unlocks modular features without bloating the core.

### Current state

- `Plugin` trait: `on_entry`, `on_export` hooks
- `PluginManager`: register, run_on_entry — but `run_on_entry` discards plugin return values
- `plugin.toml` manifest is documented in `docs/plugins.md` but no parser exists
- No plugin loading mechanism (loading `.so`/`.dylib` plugins at runtime)

### What to build

- **Manifest parser** — read `plugin.toml` from `~/.lumen/plugins/<name>/plugin.toml`. Validate fields (name, version, hooks).
- **Dynamic loading** — use `libloading` (Rust crate) to load plugin `.so`/`.dylib` files from the plugins directory. Each plugin exports C-compatible functions matching the hook signatures.
- **Hook pipeline** — in the `add_entry` data path, after encryption but before save, call `run_on_entry` on all registered plugins. Collect feedback strings and attach them to `Provenance.feedback`. Do not allow plugins to modify the encrypted payload (read-only access to metadata, write access to feedback only).
- **Sandboxing** — plugins share the process address space. There is no memory sandbox (Wasm-based plugin runners are a much larger project). Audit plugins manually before inclusion. Document this limitation.
- **Plugin registry URL** — a future `~/.lumen/plugins/registry.toml` could point to a community registry. The app checks the registry for updates and new plugins. This is optional and disabled by default.

### Built-in plugin candidates

- **Export Markdown** — iterates entries, decrypts, writes `.md` files to a user-chosen directory.
- **Daily summary** — collects all today's entries (any kind) and renders a single read-only digest.
- **Word count tracker** — logs word counts per entry over time; displays a chart.

---

## Phase 5 — Authentication and Multi-Entry Support

Single-user offline app currently has no password management. The user types their password on every add and decrypt. This is unacceptable at scale.

### Session management

- On app launch, prompt for a master password. Derive a session key using Argon2 (same as encryption key derivation).
- Store the session key in memory for the duration of the app session. Use it to automatically decrypt entries without re-prompting.
- The master password is never stored on disk. The session key is derived fresh each launch.
- Add a "lock" button that clears the session key and returns to the password prompt.

### Multiple journals / workspaces

- A journal (or "vault") is a directory containing a `journal.bin`, optional `journal.idx`, and a `config.toml`.
- The user can create multiple vaults (`~/.lumen/Personal/`, `~/.lumen/Work/`, etc.).
- Vaults are independent — each has its own encryption keys and data files.
- The sidebar has a vault switcher at the top.
- Each vault remembers its open section (journal, notes, tasks, etc.) independently.

### Biometric unlock (platform-native)

- Use platform biometric APIs (Windows Hello, macOS Touch ID, Linux `libsecret`/`pam`) to unlock without typing the master password every time.
- On first unlock, derive the session key and store it in the platform keychain (encrypted with the biometric key).
- On subsequent launches, the keychain provides the session key after biometric verification.
- If the keychain is unavailable, fall back to password prompt.

---

## Phase 6 — Sync (Optional)

Sync is explicitly optional. The app works fully without it. When enabled, it should be end-to-end encrypted.

### Architecture

- **Sync adapter trait** — a new Rust trait `SyncBackend` with methods: `push(entry_ids)`, `pull() -> Vec<EntryId>`, `resolve(conflicts) -> Vec<Entry>`.
- **Conflict resolution** — last-writer-wins by `provenance.timestamp`. A future enhancement could show both versions and let the user choose.
- **Storage format** — the sync backend stores encrypted blobs. It never sees plaintext. The encryption is already handled by the entry layer; the sync layer just ships bytes.
- **Provider implementations**:
  - **Local file** — sync to a USB drive or network share. The `SyncBackend` writes `.lumenpack` files to a directory.
  - **WebDAV** — sync to a Nextcloud instance. Requires the user to enter a URL and credentials (stored in platform keychain).
  - **Custom S3-compatible** — for advanced users.
- **Frequency** — on every entry create/edit (debounced 30 seconds), or on manual "Sync Now". No background daemon is necessary for a desktop app.

### Conflict UI

- When conflicts are detected, show a list in the Flutter UI: "2 entries changed on another device." The user can accept remote, keep local, or view both.
- Conflicts are stored in a sidecar `conflicts.json` until resolved.

---

## Phase 7 — Localization

The UI is currently English-only. Localization should be added once the feature set stabilizes (to avoid re-translating moving targets).

### Approach

- Use Flutter's built-in `flutter_localizations` and ARB files.
- Extract all user-facing strings into `.arb` files under `ui/lib/l10n/`.
- Start with 2–3 languages (English, Spanish, French) as a proof of concept.
- Localize only the Flutter UI. The Rust core produces machine-readable output (JSON, error codes), not user-facing strings.

### What not to localize

- Encryption key material (obviously)
- Log output and debug strings
- Plugin feedback text (plugin authors manage their own strings)

---

## Build and Distribution

### Linux

Current `scripts/build_linux.sh` produces a relocatable tarball. For distribution:

- **AppImage** — package the Flutter bundle into an AppImage using `appimagetool`. Requires a desktop file and icon, both of which already exist in the AUR package.
- **Flatpak** — a `flatpak-builder` manifest. More complex but better sandboxing. The Flutter Linux bundle is self-contained, so the Flatpak definition is straightforward.
- **AUR** — already maintained. The PKGBUILD clones the tagged source and builds locally.

### macOS

- `scripts/build_macos.sh` produces a `.app` bundle inside a `.zip`.
- For distribution outside the Mac App Store: notarize the `.app` with `xcrun notarytool`.
- For distribution on the Mac App Store: requires sandbox entitlements and a full review. This conflicts with the non-commercial license.

### Windows

- `scripts/build_windows.sh` produces a `.zip` of the release bundle.
- For a proper installer, use `innosetup` or `wix` to create an `.msi` or `.exe` installer.
- The Flutter Windows bundle includes all dependencies except Visual C++ Redistributable, which must be installed separately or bundled.

### Automated nightly builds

- A GitHub Actions workflow (not yet in the repo) can build all three platforms on tag push.
- Linux builds on `ubuntu-latest`, macOS on `macos-latest`, Windows on `windows-latest`.
- The workflow checks out the tag, runs the appropriate `build_*.sh` script, and uploads artifacts to the release.

---

## Testing Strategy

The repo currently has one integration test in `core/src/lib.rs` and no Flutter tests. A sustainable testing approach for a multi-feature app:

### Rust core

- **Unit tests** — test encryption/decryption round-trips, `Storage::add_entry`/`list_entries`, tag parsing, search index building and querying.
- **Integration tests** — test the FFI functions through `unsafe` wrappers. Currently the only test lives at `core/src/lib.rs`. Expand this into `core/tests/` directory.
- **Property-based testing** — use `proptest` to verify that encryption/decryption is idempotent for arbitrary inputs.

### Flutter UI

- **Widget tests** — verify that each screen renders without crashing given empty state, populated state, and error state.
- **Golden tests** — capture rendered screenshots and compare against a baseline. Essential for catching visual regressions as the DESIGN.md theme is implemented.
- **Integration tests** — use `integration_test` package to run the full app (with a mock Rust backend) and simulate user flows: create entry → list → decrypt → delete.

### TUI

- Snapshot tests that compare CLI output against expected text. Use `insta` or `assert_cmd` for Rust CLI testing.

---

## Important Non-Goals

- **Cloud sync as default** — sync is optional, opt-in, and end-to-end encrypted. The app ships with zero cloud dependencies.
- **Mobile platforms** — the Flutter code can compile for iOS/Android, but the platform-specific code (FFI loading, biometric auth, file system paths) and the DESIGN.md layout assume desktop. Mobile would require a separate UX pass.
- **Real-time collaboration** — conflict resolution is last-writer-wins. Real-time collaboration (Operational Transform / CRDT) is an order of magnitude more complex and is not planned.
- **Plugin sandboxing beyond process isolation** — Wasm-based sandboxing would be ideal but is a significant engineering investment. The plugin system documents this limitation.
- **Self-hosted server** — sync is peer-to-peer. A "server" concept is not needed and would violate the offline-first principle.
