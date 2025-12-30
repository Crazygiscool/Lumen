# 🔌 Lumen Plugin System(not implemented yet)

Lumen supports a modular plugin architecture designed for privacy-first journaling, expressive feedback, and provenance tracking. This document outlines how to build, register, and integrate plugins into the Lumen ecosystem.

---

## 🧠 Philosophy

Plugins are treated as expressive companions—not just utilities. Each plugin should:

- Respect Lumen’s **offline-first**, **encrypted**, and **non-commercial** principles.
- Be **modular**, with clear lifecycle hooks and minimal side effects.
- Provide **emotionally intelligent feedback** or expressive UX enhancements.
- Support **per-entry provenance**, including plugin name, version, and timestamp.

---

## 📦 Plugin Manifest

Every plugin must include a `plugin.toml` manifest with the following fields:

```toml
name = "lumen"
version = "0.3.1"
description = "AI-powered feedback engine for journal entries"
author = "crazygiscool"
license = "Lumen Non-Commercial License v1.0"
entrypoint = "lumen_plugin.rs"
hooks = ["on_entry", "on_export"]
```

Optional fields:

```toml
tags = ["feedback", "ai", "expressive"]
config_ui = "lumen_config.dart"  # Flutter config panel
```

---

## 🔁 Lifecycle Hooks

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

## 🧪 Example: Feedback Plugin

```rust
fn on_entry(entry: JournalEntry, ctx: PluginContext) -> PluginResult {
    let feedback = analyze_sentiment(&entry.text);
    let annotation = format!("Lumen says: {}", feedback.summary);
    Ok(entry.with_annotation(annotation))
}
```

---

## 🧩 Plugin Registry (Coming Soon)

We plan to launch a **Plugin Registry** for community-built plugins. All submissions must:

- Include a valid `plugin.toml`
- Pass security and privacy checks
- Be licensed under the Lumen Non-Commercial License

---

## 🛡️ Security & Privacy

Plugins run in a sandboxed environment. They must:

- Never transmit data externally
- Respect encryption boundaries
- Avoid persistent logging unless explicitly configured

---

## 🧠 Expressive UX

Plugins may include optional config panels (`config_ui`) written in Flutter. These should:

- Be minimal and intuitive
- Use emotionally intelligent copy
- Avoid clutter or log spam

---

## 🧾 Contribution Guidelines

To contribute a plugin:

1. Fork the [Lumen Plugin Template](we are not there yet, wait for a bit)
2. Build your plugin with clear lifecycle hooks
3. Submit a pull request with your `plugin.toml` and source files
4. Include a README with usage, philosophy, and provenance notes

---

## 💬 Questions?

Reach out via [Discussions](https://github.com/crazygiscool/lumen/discussions) or email **crazygiscool** directly.

Let’s build plugins that listen, reflect, and evolve.
