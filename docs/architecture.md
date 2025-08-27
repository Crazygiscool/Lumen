# 🏗️ Lumen Architecture Overview

Lumen is a modular, encrypted journaling engine built with a Rust core and Flutter UI. It’s designed for privacy-first workflows, plugin extensibility, and expressive feedback. This document outlines the file structure and architectural principles that guide Lumen’s development.

---

## 📁 File Structure

```txt
lumen/
├── core/                  # Rust journaling engine
│   ├── entry/             # Journal entry structs, encryption, provenance
│   ├── storage/           # Local-first storage, sync adapters
│   ├── plugins/           # Plugin runtime, lifecycle hooks
│   ├── feedback/          # AI feedback engines (e.g. GEORGE)
│   └── lib.rs             # Core engine entrypoint
│
├── ui/                    # Flutter UI
│   ├── screens/           # Journal, entry, settings, plugin config
│   ├── widgets/           # Reusable expressive components
│   ├── themes/            # Light/dark modes, typography
│   └── main.dart          # Flutter app entrypoint
│
├── tui/                   # Terminal UI (optional)
│   ├── commands/          # CLI commands and flags
│   ├── render/            # TUI layout and feedback
│   └── lumen_tui.rs       # TUI entrypoint
│
├── plugins/               # Community and built-in plugins
│   ├── george/            # AI feedback plugin
│   ├── export_pdf/        # PDF export plugin
│   └── plugin.toml        # Manifest for each plugin
│
├── docs/                  # Documentation
│   ├── architecture.md    # This file
│   ├── plugins.md         # Plugin system overview
│   └── contributing.md    # Contribution guidelines
│
├── LICENSE                # Lumen Non-Commercial License
└── README.md              # Project overview
```

---

## 🧠 Architectural Principles

### 1. **Modularity**

- Each component (core, UI, TUI, plugins) is independently testable and replaceable.
- Plugin system uses lifecycle hooks (`on_entry`, `on_export`, etc.) for extensibility.

### 2. **Privacy-First**

- All journal data is encrypted locally using per-entry keys.
- No external transmission without explicit opt-in.
- Offline-first by default; sync adapters are optional and pluggable.

### 3. **Provenance-Aware**

- Every journal entry includes:
  - Timestamp
  - Plugin origin (if applicable)
  - Author context
  - Feedback annotations

### 4. **Expressive UX**

- Flutter UI emphasizes clarity, emotional resonance, and minimalism.
- TUI mirrors this with intuitive commands and feedback loops.
- Plugins can inject feedback or annotations in a non-intrusive way.

### 5. **Plugin Extensibility**

- Plugins are sandboxed and declared via `plugin.toml`.
- Runtime enforces lifecycle boundaries and provenance tracking.
- Future registry will support community discovery and validation.

---

## 🔄 Data Flow

```text
[User Input]
   ↓
[Flutter/TUI UI]
   ↓
[Core Engine]
   ↓
[Plugin Hooks]
   ↓
[Encrypted Storage]
   ↓
[Optional Export/Sync]
```

- Feedback plugins may intercept entries post-creation.
- Export plugins transform encrypted entries into readable formats.
- All transformations are logged with provenance metadata.

---

## 🧪 Testing Strategy

- Rust: Unit + integration tests for core logic and plugin runtime.
- Flutter: Widget + golden tests for expressive UI.
- TUI: Snapshot tests for command output.
- Plugins: Hook-specific test harnesses.

---

## 🛠️ Future Directions

- Plugin registry with provenance scoring
- Configurable journaling workflows (e.g. mood tracking, poetic mode)
- Branded onboarding experiences
- Sync adapters for encrypted cloud storage

---

Lumen is more than a journaling app—it’s a reflective companion.  
Let’s build tools that listen, protect, and evolve.
