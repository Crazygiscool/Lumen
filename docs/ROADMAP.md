# Lumen Development Roadmap

**Vision**: A private, offline-first personal knowledge base with networked thought, privacy-first sync, and native cross-platform experience.

---

## Phase Overview

| Phase | Theme | Duration | Status |
|-------|-------|----------|--------|
| **1** | Knowledge Base Foundations | ~4 weeks | ✅ Complete |
| **2** | Privacy-First Sync | ~4 weeks | ✅ Complete |
| **3** | Cross-Platform Polish | ~6 weeks | 📋 Planned |
| **4** | Power User Features | ~6 weeks | 📋 Planned |

**Total**: ~20 weeks (5 months) for full roadmap

---

## Phase 1: Knowledge Base Foundations

**Goal**: Transform journal into PKM with wikilinks, search, templates, frontmatter, graph.

### Core Features
- **Wikilinks** `[[note]]` + backlinks panel
- **Daily note templates** with placeholders
- **YAML frontmatter** (tags, aliases, custom fields)
- **Tantivy full-text search** (<100ms for 10k notes)
- **Graph view** (force-directed, filterable, navigable)

### Deliverables
- Core: `wikilinks.rs`, `template.rs`, `frontmatter.rs`, `search.rs`, `graph.rs`
- FFI exports for all
- Flutter: Search UI, wikilink completion, backlinks panel, frontmatter editor, daily note button, graph view

### Dependencies
- `tantivy` in core
- `graph_view` / `flutter_graph` in Flutter

### What was built
- The core, the desktop app and the terminal client all carry the features.
- The search index lives in the configuration folder, not in the vault: it
  holds the plain text of every note, and the vault is what gets synced.
- A small query language (`tag:`, `date:`, `key:value`, free text) lets a
  client ask a question that spans the index and the metadata.
- The terminal client is a library crate, so its commands can be tested
  without a terminal.
- The graph layout is hand-written rather than a dependency.

See [Phase 1](phase1-knowledge-base.md) for the details.

---

## Phase 2: Privacy-First Sync

**Goal**: Sync encrypted journal across devices without Lumen holding keys.

### Core Features
- **Syncthing integration** (primary): Setup wizard, folder config, device pairing QR, conflict resolution
- **WebDAV backup** (secondary): Nextcloud/ownCloud, age encryption, scheduling
- **Encrypted export bundles** (`.lumen.bak.age`) for air-gapped backup
- **Conflict detection & resolution** (visual diff, merge, keep local/remote)

### Deliverables
- Core: `sync.rs` (status, conflicts, Syncthing config generator), `webdav.rs`, `backup.rs`
- Flutter: Syncthing wizard, sync dashboard, conflict resolution UI, WebDAV settings

### Security
- Zero plaintext in sync transport
- User owns passphrase; separate backup key derivation
- Credentials in OS keyring

### What was built
- Syncthing and WebDAV both work; the client is `remotefs-webdav` 1.0.
- The password of the WebDAV account and the passphrase that encrypts the
  uploads are two different secrets, both in the operating system's keyring.
  The server knows the first and not the second, so it cannot read the notes.
- A conflict is resolved by looking at the difference between the two
  versions. The difference is worked out in the core, because the version
  the other device sent is an encrypted file inside the vault.
- The devices and the pending changes are read from Syncthing's own REST
  interface, and the reason they could not be read is reported rather than
  hidden.

See [Phase 2](phase2-sync.md) for the details.

---

## Phase 3: Cross-Platform Polish

**Goal**: First-class native experience on all platforms.

### Platform Matrix

| Platform | Packaging | Distribution | Key Features |
|----------|-----------|--------------|--------------|
| **Linux** | AppImage, .deb, .rpm, AUR | GitHub, distro repos | Wayland, libsecret |
| **macOS** | Notarized .dmg, Homebrew | GitHub, Homebrew | Keychain, Touch Bar, Universal binary |
| **Windows** | Scoop, Inno Setup | winget, GitHub | Credential Manager, Windows Hello, WSL |
| **iOS** | IPA | TestFlight → App Store | Face ID, Share Extension, Keychain, BGAppRefresh |
| **Android** | AAB | Play Store → F-Droid | Biometric, Keystore, Intent Filter, WorkManager |

### Additional
- **Auto-update**: Sparkle (Mac), custom (Linux/Win), Store (Mobile)
- **CI/CD**: GitHub Actions building all 5 platforms

---

## Phase 4: Power User Features

**Goal**: Advanced automation, extensibility, AI, and editor integration.

### Features
1. **Command Palette** (`Ctrl+K`) — 30+ actions, plugin-extensible
2. **Vim/Emacs Keybindings** — Full modal editing in Flutter
3. **Canvas/Whiteboard** — Excalidraw-style, embed in notes, wikilinks on shapes
4. **Local AI (Ollama)** — Summarize, chat, related notes, tags, tasks — zero cloud
5. **WASM Plugin Sandbox** — `wasmtime`, fuel/memory limits, capability permissions
6. **LSP Server** — `lumen-lsp` for VS Code, Neovim, Helix, Zed
7. **Graph Analytics** — Centrality, clusters, orphans, export to GraphML

---

## Cross-Cutting Concerns

### Testing Strategy
| Layer | Tools | Coverage Target |
|-------|-------|-----------------|
| **Core (Rust)** | `cargo test`, `proptest` | 80% |
| **Flutter** | `flutter test`, `integration_test` | 70% |
| **E2E** | Custom (vault + sync) | Critical paths |

### Performance Budgets
| Metric | Target |
|--------|--------|
| App cold start (Flutter) | <2s |
| Vault unlock | <500ms |
| Search (10k notes) | <100ms |
| Graph render (5k nodes) | <2s / 60fps |
| Sync conflict check | <1s |
| WASM plugin call | <10ms |

### Privacy Checklist (Every Feature)
- [x] No network calls without explicit user action
- [x] Encryption keys never leave device
- [x] Optional features default to OFF
- [ ] Clear privacy notice in UI
- [ ] Data export/delete available

---

## Milestone Dates (Target)

| Milestone | Target Date |
|-----------|-------------|
| Phase 1 Core Complete | Week 3 |
| Phase 1 Flutter Complete | Week 6 |
| Phase 2 Sync Working | Week 10 |
| Phase 3 Desktop Packaged | Week 14 |
| Phase 3 Mobile Beta | Week 18 |
| Phase 4 Core Features | Week 22 |
| **v4.0 Release** | **Week 24** |

---

## Resource Requirements

| Role | Phase 1 | Phase 2 | Phase 3 | Phase 4 |
|------|---------|---------|---------|---------|
| **Rust (Core)** | 1.0 FTE | 1.0 FTE | 0.5 FTE | 1.0 FTE |
| **Flutter** | 1.0 FTE | 1.0 FTE | 1.0 FTE | 1.0 FTE |
| **DevOps/Packaging** | 0 | 0 | 1.0 FTE | 0.25 FTE |
| **Design/UX** | 0.25 FTE | 0.25 FTE | 0.5 FTE | 0.5 FTE |

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Tantivy index corruption | Medium | High | WAL + auto-rebuild + `lumen reindex` |
| Syncthing mobile limitations (iOS) | High | Medium | WebDAV as primary for iOS; document limitations |
| WASM plugin ecosystem slow | Medium | Low | Keep native plugin support; port built-ins first |
| macOS notarization delays | Medium | High | Start cert process early; test on CI |
| Flutter mobile FFI complexity | High | High | Use `flutter_rust_bridge`; prototype early |
| Local AI performance (no GPU) | Medium | Medium | Quantized models (Q4_K_M); streaming; progress UI |

---

## Success Metrics (v4.0)

| Metric | Target |
|--------|--------|
| **Daily active users** | 1,000+ |
| **Platforms supported** | 5 (Linux, Mac, Win, iOS, Android) |
| **Sync methods** | 2+ (Syncthing, WebDAV) |
| **Plugin ecosystem** | 10+ WASM plugins |
| **Search latency (10k notes)** | <100ms p95 |
| **Crash-free sessions** | >99.5% |
| **User satisfaction (NPS)** | >50 |

---

## Immediate Next Steps

Phase 1 and Phase 2 are done. Phase 3 is next:

1. **Package the desktop app for the three desktops** — Linux (AppImage,
   .deb, .rpm), Windows (Scoop, Inno Setup), macOS (zip)
2. **Auto-update** — Sparkle on macOS, a signed updater elsewhere
3. **CI that builds all three desktops** — GitHub Actions builds Linux,
   macOS, and Windows on every `v*` tag
4. **The mobile clients** — the FFI layer is ready for it, but the FFI
   calls have to be checked against the restrictions of the app stores

The one thing left over from Phase 1: a link to a note that does not exist
yet should offer to create it (`wikilinks.create_missing`).

---

## Documentation Index

- [Phase 1: Knowledge Base Foundations](phase1-knowledge-base.md)
- [Phase 2: Privacy-First Sync](phase2-sync.md)
- [Phase 3: Cross-Platform Polish](phase3-cross-platform.md)
- [Phase 4: Power User Features](phase4-power-user.md)
- [Plugin System](plugins.md)
- [Stoic Export Format](stoic-export-format.md)