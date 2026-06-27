# Lumen Plugin System

Lumen supports a modular plugin architecture designed for privacy-first journaling, expressive feedback, and provenance tracking. This document outlines how to build, register, and integrate plugins into the Lumen ecosystem.

---

## Philosophy

Plugins are treated as expressive companions—not just utilities. Each plugin should:

- Respect Lumen's **offline-first**, **encrypted**, and **non-commercial** principles.
- Be **modular**, with clear lifecycle hooks and minimal side effects.
- Provide **emotionally intelligent feedback** or expressive UX enhancements.
- Support **per-entry provenance**, including plugin name, version, and timestamp.

---

## Implementation Status

The plugin system is implemented in the Rust core (`core/src/plugins/`) and supports:

- **Built-in plugins** — compiled directly into the core library (Export Markdown, Daily Summary, Word Count Tracker)
- **External plugins** — loaded dynamically at runtime via `libloading` from `~/.local/share/lumen/plugins/`
- **Plugin manifest** — `plugin.toml` files parsed via `serde`/`toml`
- **Lifecycle hooks** — `on_entry` and `on_export` methods

---

## Plugin Manifest

Every external plugin must include a `plugin.toml` manifest with the following fields in its plugin directory:

```toml
name = "my-plugin"
version = "0.1.0"
description = "Description of what my plugin does"
author = "your-name"
license = "Lumen Non-Commercial License v1.0"
hooks = ["on_entry", "on_export"]
```

Optional fields:

```toml
tags = ["feedback", "expressive"]
```

---

## Lifecycle Hooks

Plugins may implement any of the following hooks:

| Hook         | Description                                                                 |
|--------------|-----------------------------------------------------------------------------|
| `on_entry`   | Triggered when a new journal entry is created. Can annotate or respond.     |
| `on_export`  | Invoked during export. Can transform or redact data.                        |
| `on_import`  | Used to parse external formats into Lumen entries.                          |
| `on_render`  | Enhances UI rendering (TUI/Flutter).                                        |
| `on_feedback`| Provides emotional or structural feedback on entries.                       |

Each hook receives a structured payload with metadata, encrypted content, and provenance context.

---

## Built-in Plugins

Three built-in plugins ship with Lumen:

- **Export Markdown** (`export_md`) — generates Markdown-formatted output for entry export
- **Daily Summary** (`daily_summary`) — logs daily entry summaries via the `on_entry` hook
- **Word Count Tracker** (`wordcount`) — estimates word count from encrypted body length

---

## External Plugins

External plugins are loaded at runtime from `~/.local/share/lumen/plugins/`. Each plugin is a subdirectory containing:

1. A `plugin.toml` manifest
2. A shared library (`lib<name>.so` on Linux, `lib<name>.dylib` on macOS)

The shared library must expose a C ABI function:

```c
char* lumen_plugin_on_entry(const char* entry_id);
```

Returns a feedback string, or NULL if no feedback. The caller frees the returned string.

---

## Plugin Trait (Rust)

Built-in plugins implement the `Plugin` trait:

```rust
pub trait Plugin {
    fn on_entry(&self, entry: &JournalEntry) -> Option<String>;
    fn on_export(&self, entry: &JournalEntry) -> Option<Vec<u8>>;
}
```

---

## Plugin Registry (Coming Soon)

We plan to launch a **Plugin Registry** for community-built plugins. All submissions must:

- Include a valid `plugin.toml`
- Pass security and privacy checks
- Be licensed under the Lumen Non-Commercial License

---

## Security & Privacy

- Built-in plugins run in-process and have access to decrypted content
- External plugins are loaded via `libloading` and **share the process address space** — there is no Wasm sandbox yet. Audit external plugins manually
- Plugins must never transmit data externally
- Plugins must respect encryption boundaries
- Avoid persistent logging unless explicitly configured

---

## Contribution Guidelines

To contribute a plugin:

1. Build your plugin using the Plugin trait or shared library ABI
2. Include a `plugin.toml` and source files
3. Submit a pull request with documentation
4. Include a README with usage, philosophy, and provenance notes

---

Let's build plugins that listen, reflect, and evolve.
