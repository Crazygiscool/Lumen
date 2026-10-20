# Lumen Plugin System

Lumen has a small plugin system for reacting to saved journal notes. Plugins
never see ciphertext; they receive the decrypted note body only while a save is
being processed, and their feedback is shown in the UI.

## Implementation

Plugins live in the Rust core (`core/src/plugins/`) and come in two kinds:

- **Built-in** — compiled into `liblumen_core`:
  - `wordcount` — reports the word count of a saved note.
  - `daily_summary` — reports the note title and word count.
  - `export_md` — renders Markdown for export.
- **External** — loaded with `libloading` from
  `~/.config/Lumen/plugins/` (honors `XDG_CONFIG_HOME`).

The Plugins screen lists both kinds and persists enable/disable choices. Disabled
plugins are skipped when notes are saved.

## Manifest

Each external plugin is a directory containing `plugin.toml` plus a shared
library named `lib<name>.so` (Linux), `lib<name>.dylib` (macOS), or
`<name>.dll` (Windows):

```toml
name = "my-plugin"
version = "0.1.0"
author = "your-name"
description = "What this plugin does"
hooks = ["on_note"]
```

Only `name` and `version` are required; `author`, `description`, and `hooks` are
optional.

## Hooks

| Hook | When it runs | Input |
|------|--------------|-------|
| `on_note` | After a note is saved | Decrypted note path, title, body |
| `on_export` | When a plugin is asked to render a note | Decrypted note path, title, body |

The built-in trait:

```rust
pub struct NoteContext<'a> {
    pub id: &'a str,    // path inside the journal store
    pub title: &'a str,
    pub body: &'a str,
}

pub trait Plugin: Send + Sync {
    fn on_note(&self, note: &NoteContext<'_>) -> Option<String>;
    fn on_export(&self, note: &NoteContext<'_>) -> Option<Vec<u8>> { None }
}
```

## External C ABI

An external plugin must export one function:

```c
char* lumen_plugin_on_entry(const char* note_path);
```

It receives the note path, returns a feedback string (allocated with `malloc` or
equivalent and freed by the caller), or `NULL` for no feedback.

## Running plugins

The UI calls the `plugins.run` FFI method after saving a note:

```json
{ "path": "2026-02-03.md", "title": "Tuesday", "body": "# Tuesday\n…" }
```

It returns `{ "feedback": ["[wordcount] 42 words"] }`. Plugin failures never
block a save.

## Security

- Built-in plugins run in-process and receive decrypted content.
- External plugins are loaded with `libloading` and share Lumen's address space;
  there is no sandbox. Only install plugins you trust.
- Plugins must not transmit data externally, log plaintext, or write to the
  encrypted store directly.
- The plugin inventory (`plugins.list`) reads manifests only and never executes
  plugin code. Code runs only when a note is saved (`plugins.run`).

## Installing a plugin

1. Create `~/.config/Lumen/plugins/my-plugin/`.
2. Add `plugin.toml` and the compiled `libmy-plugin.so`.
3. Open **Plugins** in Lumen and enable it.
