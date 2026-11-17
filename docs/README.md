# Lumen Documentation

## Architecture & Design

| Document | Description |
|----------|-------------|
| [ROADMAP.md](ROADMAP.md) | Master development roadmap (Phases 1-4) |
| [phase1-knowledge-base.md](phase1-knowledge-base.md) | Wikilinks, search, templates, frontmatter, graph |
| [phase2-sync.md](phase2-sync.md) | Syncthing, WebDAV, encrypted backup, conflicts |
| [phase3-cross-platform.md](phase3-cross-platform.md) | Linux/macOS/Windows/iOS/Android packaging & features |
| [phase4-power-user.md](phase4-power-user.md) | Command palette, vim mode, canvas, local AI, WASM plugins, LSP |

## Reference

| Document | Description |
|----------|-------------|
| [plugins.md](plugins.md) | Plugin system: manifests, hooks, C ABI, security |
| [stoic-export-format.md](stoic-export-format.md) | Stoic iOS export format (17 JSON files + assets) |

## Quick Links

- **AGENTS.md** — Agent instructions (root)
- **CONTRIBUTING.md** — Contribution guidelines (root)
- **LICENSE** — Lumen Non-Commercial Software License v1.0 (root)
- **Makefile** — Build commands (root)
- **scripts/** — Build/release/sync scripts

---

## Phase Status

| Phase | Theme | Status |
|-------|-------|--------|
| 1 | Knowledge Base Foundations | ✅ Complete |
| 2 | Privacy-First Sync | ✅ Complete |
| 3 | Cross-Platform Polish | 📋 Planned |
| 4 | Power User Features | 📋 Planned |

See [ROADMAP.md](ROADMAP.md) for detailed timeline and milestones.

## Where things are

| Thing | Where |
|-------|-------|
| The vault, and its encryption | `core/src/vault/` |
| Wikilinks and backlinks | `core/src/wikilinks.rs` |
| The search index | `core/src/search.rs` |
| The query language | `core/src/query.rs` |
| Frontmatter | `core/src/frontmatter.rs` |
| Daily templates | `core/src/template.rs` |
| The graph | `core/src/graph.rs` |
| Sync, conflicts and backups | `core/src/sync.rs` |
| Syncthing's REST interface | `core/src/syncthing.rs` |
| The WebDAV client | `core/src/sync.rs` (`WebDAVSync`) |
| The keyring | `core/src/secrets.rs` |
| The difference between two versions | `core/src/diff.rs` |
| The knowledge-base API | `core/src/ffi.rs` (`lumen_kb_call`) |
| The desktop app | `ui/lib/` |