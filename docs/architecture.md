# Lumen Architecture Overview

Lumen is a modular, encrypted journaling engine built with a Rust core and Flutter UI. It's designed for privacy-first workflows, plugin extensibility, and expressive feedback. This document outlines the file structure and architectural principles that guide Lumen's development.

---

## File Structure

```txt
lumen/
├── core/                  # Rust journaling engine
│   ├── entry/             # Journal entry structs, encryption, provenance
│   ├── storage/           # SQLite storage, schema, migrations
│   ├── plugins/           # Plugin runtime, lifecycle hooks, builtin plugins
│   ├── sync/              # Local SQLite sync backend
│   ├── auth.rs            # Session manager, password hashing
│   ├── feedback.rs        # Feedback engine
│   ├── ffi.rs             # C-compatible FFI exports
│   └── lib.rs             # Core engine entrypoint
│
├── ui/                    # Flutter UI
│   ├── screens/           # Journal, entry, settings, lock, board, sync
│   ├── widgets/           # Reusable components
│   ├── core/              # FFI bindings, providers, models
│   ├── utils/             # Theme, wiki-links, frontmatter, responsive
│   ├── l10n/              # Localization (en, es, fr)
│   └── main.dart          # Flutter app entrypoint
│
├── tui/                   # Terminal UI
│   └── src/main.rs        # CLI + interactive TUI entrypoint
│
├── scripts/               # Build and packaging scripts
│   ├── build_linux.sh
│   ├── build_macos.sh
│   ├── build_windows.sh
│   ├── release.sh
│   └── sync.sh
│
├── docs/                  # Documentation
│   ├── architecture.md    # This file
│   ├── roadmap.md         # Development roadmap
│   ├── plugins.md         # Plugin system overview
│   ├── core.md            # Core engine documentation
│   ├── storage.md         # Storage format and schema
│   ├── tui.md             # TUI usage
│   └── stoic-export-format.md
│
├── DESIGN.md              # UI/UX design system
├── LICENSE                # Lumen Non-Commercial License
├── CONTRIBUTING.md        # Contribution guidelines
└── README.md              # Project overview
```

---

## Architectural Principles

### 1. Modularity

- Each component (core, UI, TUI, plugins) is independently testable and replaceable.
- Plugin system uses lifecycle hooks (`on_entry`, `on_export`, etc.) for extensibility.

### 2. Privacy-First

- All journal data is encrypted locally using per-entry keys (AES-256-GCM + Argon2id).
- No external transmission without explicit opt-in.
- Offline-first by default; sync adapters are optional and pluggable.

### 3. Provenance-Aware

- Every journal entry includes:
  - Timestamp
  - Plugin origin (if applicable)
  - Author context
  - Feedback annotations
  - Edit history

### 4. Expressive UX

- Flutter UI emphasizes clarity, emotional resonance, and minimalism.
- TUI mirrors this with intuitive commands and feedback loops.
- Plugins can inject feedback or annotations in a non-intrusive way.

### 5. Plugin Extensibility

- Built-in plugins compiled directly into the core.
- External plugins loaded dynamically via `libloading` from `~/.local/share/lumen/plugins/`.
- Runtime enforces lifecycle boundaries and provenance tracking.

---

## Data Flow

```text
[User Input]
   ↓
[Flutter/TUI UI]
   ↓
[Core Engine]
   ↓
[Plugin Hooks]
   ↓
[Encrypted Storage (SQLite)]
   ↓
[Optional Export/Sync]
```

- Feedback plugins may intercept entries post-creation.
- Export plugins transform encrypted entries into readable formats.
- All transformations are logged with provenance metadata.

---

## Testing Strategy

- Rust: Unit + integration tests for core logic and plugin runtime.
- Flutter: Widget + golden tests for expressive UI.
- TUI: Snapshot tests for command output.
- Plugins: Hook-specific test harnesses.

---

## Future Directions

- Plugin registry with provenance scoring
- Configurable journaling workflows (e.g. mood tracking, poetic mode)
- Branded onboarding experiences
- Sync adapters for encrypted cloud storage
- Biometric authentication (Windows Hello, macOS Touch ID)

---

Lumen is more than a journaling app—it's a reflective companion.
Let's build tools that listen, protect, and evolve.
