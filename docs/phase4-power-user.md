# Phase 4: Power User Features

**Goal**: Advanced features for heavy users — automation, extensibility, AI, and visualization — while maintaining privacy-first architecture.

**Status**: 📋 Planned. Phases 1 and 2 are done; this one comes after
[Phase 3](phase3-cross-platform.md).

---

## 1. Command Palette (Flutter + TUI)

### Flutter: `Ctrl+K` / `Cmd+K` → Universal Action Search

**Implementation** (`ui/lib/command_palette.dart`):

```dart
class Command {
  final String id;
  final String title;
  final String description;
  final List<String> keywords;  // For fuzzy matching
  final VoidCallback action;
  final KeyBinding? keyBinding;
}

class CommandPalette extends StatefulWidget {
  // Fuzzy search over all commands
  // Shows: recent, frequent, matching
  // Keyboard: ↑↓ navigate, Enter execute, Esc close
}
```

**Core Commands** (extensible via plugins):

| Category | Commands |
|----------|----------|
| **Navigation** | Open Daily Note, Open Graph, Open Search, Open Settings, Go to Note... |
| **Capture** | New Note, New Daily Note, Quick Capture, Import..., Paste as Note |
| **Editing** | Toggle Preview, Insert Wikilink, Insert Tag, Insert Template, Word Count |
| **View** | Toggle Theme, Toggle Sidebar, Focus Editor, Zen Mode, Graph View |
| **Sync** | Sync Now, Show Conflicts, Pause/Resume Sync, Export Backup |
| **Plugins** | Run Plugin, Configure Plugin, Install Plugin, Plugin Store |
| **Advanced** | Rebuild Search Index, Rebuild Graph, Verify Vault, Debug Logs |

**Plugin API**: `contributes.commands[]` in `plugin.toml`

### TUI: Command Mode (`:`)

```
:command-name [args]
```

- Tab completion
- History (`↑`/`↓`)
- Same command registry as Flutter (shared via core)

**Implementation notes:**

Core (`core/src/commands.rs`): A command registry with `register_command`,
`list_commands`, `filter_commands` (fuzzy substring matching with word-boundary
bonuses), and `register_builtin_commands`. 22 built-in commands across 7
categories (navigation, capture, editing, view, sync, plugins, advanced).

FFI (`core/src/ffi.rs`): `kb.command.list` returns all registered commands;
`kb.command.execute` looks up a command by id. Both ensure built-ins are
registered first.

Flutter (`ui/lib/command_palette.dart`): `Ctrl+K` / `Cmd+K` opens a fuzzy
searchable dialog with keyboard navigation (↑↓/Enter/Esc). Commands are
grouped by category with section icons.

TUI (`tui/src/cli.rs`): `lumen command <id>` runs a command and shows its
title, description, keywords, and source. Unknown commands get fuzzy-match
suggestions.

---

## 2. Vim/Emacs Keybindings

### Flutter

**Package**: `flutter_keyboard_shortcuts` or custom `Shortcuts` + `Actions` map

```dart
// ui/lib/editor/keybindings.dart
enum KeybindingMode { Default, Vim, Emacs }

class KeybindingManager {
  static Map<KeybindingMode, Map<LogicalKeySet, Intent>> keymaps = {
    KeybindingMode.Vim: {
      // Normal mode
      LogicalKeySet(LogicalKeyboardKey.keyH): MoveCursorLeftIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyJ): MoveCursorDownIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyK): MoveCursorUpIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyL): MoveCursorRightIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyI): EnterInsertModeIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyX): DeleteCharIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyD): DeleteLineIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyY, LogicalKeyboardKey.keyY): YankLineIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyP): PasteAfterIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyU): UndoIntent(),
      LogicalKeySet(LogicalKeyboardKey.controlKey, LogicalKeyboardKey.keyR): RedoIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyG, LogicalKeyboardKey.keyG): GoToTopIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyG): GoToLineIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyF, LogicalKeyboardKey.keyF): FindIntent(),
      // Visual mode, command mode...
    },
    KeybindingMode.Emacs: {
      LogicalKeySet(LogicalKeyboardKey.controlKey, LogicalKeyboardKey.keyF): MoveCursorRightIntent(),
      LogicalKeySet(LogicalKeyboardKey.controlKey, LogicalKeyboardKey.keyB): MoveCursorLeftIntent(),
      LogicalKeySet(LogicalKeyboardKey.controlKey, LogicalKeyboardKey.keyN): MoveCursorDownIntent(),
      LogicalKeySet(LogicalKeyboardKey.controlKey, LogicalKeyboardKey.keyP): MoveCursorUpIntent(),
      LogicalKeySet(LogicalKeyboardKey.controlKey, LogicalKeyboardKey.keyA): MoveToLineStartIntent(),
      LogicalKeySet(LogicalKeyboardKey.controlKey, LogicalKeyboardKey.keyE): MoveToLineEndIntent(),
      LogicalKeySet(LogicalKeyboardKey.controlKey, LogicalKeyboardKey.keyK): KillLineIntent(),
      LogicalKeySet(LogicalKeyboardKey.controlKey, LogicalKeyboardKey.keyY): YankIntent(),
      LogicalKeySet(LogicalKeyboardKey.controlKey, LogicalKeyboardKey.keySpace): SetMarkIntent(),
      LogicalKeySet(LogicalKeyboardKey.controlKey, LogicalKeyboardKey.keyW): KillRegionIntent(),
      LogicalKeySet(LogicalKeyboardKey.controlKey, LogicalKeyboardKey.keyX, LogicalKeyboardKey.controlKey, LogicalKeyboardKey.keyS): SaveIntent(),
      // ...
    },
  };
}
```

- **Mode indicator** in status bar
- **Settings**: Choose mode, customize bindings
- **Vim**: Normal/Insert/Visual/Command modes
- **Emacs**: Modeless with Ctrl/Meta chords

### TUI

- Already uses `crossterm` — add keymap layer
- `lumen --vim` / `lumen --emacs` flags
- Config: `~/.config/lumen/keymap.toml`

---

## 3. Canvas / Whiteboard (Excalidraw-style)

### Why
- Spatial thinking, mind maps, diagrams
- Hand-drawn sketches, wireframes
- Embed in notes as `![[canvas-name.canvas]]`

### Implementation

**Format**: `.canvas` files (JSON, Excalidraw-compatible)

```json
{
  "type": "excalidraw",
  "version": 2,
  "source": "https://excalidraw.com",
  "elements": [
    { "id": "1", "type": "rectangle", "x": 100, "y": 100, "width": 200, "height": 150, "strokeColor": "#1e1e1e", "backgroundColor": "transparent" },
    { "id": "2", "type": "arrow", "x": 300, "y": 150, "points": [[0,0], [100,50]], "strokeColor": "#1e1e1e" },
    { "id": "3", "type": "text", "x": 120, "y": 120, "text": "Project Alpha", "fontSize": 20 }
  ],
  "appState": { "gridSize": 20, "viewBackgroundColor": "#ffffff" }
}
```

**Core**: Store as encrypted `.canvas` files in vault (same as `.md`)

**Flutter**: `flutter_excalidraw` or embed Excalidraw via WebView (WASM)

```dart
// ui/lib/canvas/canvas_editor.dart
class CanvasEditor extends StatefulWidget {
  final String path;
  
  // Toolbar: select, rectangle, ellipse, arrow, line, text, freehand, eraser
  // Layers, zoom, pan, undo/redo
  // Export: PNG, SVG, embed in note
}
```

**Wikilink Integration**:
- `[[canvas-name]]` → opens canvas editor
- `![[canvas-name.canvas]]` → renders preview in markdown
- Canvas elements can link to notes: `[[note-name]]` on shapes

**TUI**: Not applicable (launch Flutter for canvas)

---

## 4. Local AI (Ollama Integration)

### Privacy Model

| Component | Location | Data Sent |
|-----------|----------|-----------|
| **Ollama server** | User's machine (localhost:11434) | None to Lumen |
| **Lumen** | Client | Only selected note context (user-initiated) |
| **Models** | Local (llama3, phi3, qwen2, etc.) | Never leave machine |

**Zero cloud dependency** — user installs Ollama, pulls models.

### Features

| Feature | Trigger | Context Sent | Output |
|---------|---------|--------------|--------|
| **Summarize week** | Cmd palette / Dashboard | Last 7 daily notes | Bullet summary |
| **Find related** | Right-click note / Graph | Current note + embeddings | Linked notes list |
| **Chat with vault** | Sidebar panel | User question + relevant notes (RAG) | Answer with citations |
| **Suggest tags** | Save note | Note body | Tag suggestions |
| **Extract tasks** | Cmd palette | Note body | Checklist items |
| **Weekly review** | Dashboard button | Week's notes | Structured review |

### Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Lumen App     │────▶│  Ollama HTTP    │────▶│  Local Model    │
│  (Flutter/TUI)  │     │  (localhost)    │     │  (llama.cpp)    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        │ 1. User selects       │ 3. POST /api/chat   │ 5. Stream tokens
        │    notes + action     │    {model, messages} │
        │                       │                       │
        ▼                       ▼                       ▼
   2. Build prompt        4. Model inference      6. Render in UI
   (RAG: retrieve          (GPU/CPU)              (citations,
    relevant notes)                                 streaming)
```

### Core: AI Service (`core/src/ai.rs`)

```rust
use reqwest;

pub struct OllamaClient {
    base_url: String,  // http://localhost:11434
    client: reqwest::Client,
}

impl OllamaClient {
    pub async fn chat(&self, model: &str, messages: Vec<Message>, stream: bool) -> Result<ChatResponse> {
        // POST /api/chat
    }

    pub async fn embeddings(&self, model: &str, texts: Vec<String>) -> Result<Vec<Vec<f32>>> {
        // POST /api/embeddings
    }

    pub async fn list_models(&self) -> Result<Vec<ModelInfo>> {
        // GET /api/tags
    }
}

// RAG: Retrieve relevant notes via Tantivy + embeddings
pub async fn retrieve_context(&self, query: &str, store: &str, k: usize) -> Vec<NoteContext> {
    // 1. Embed query
    // 2. Search Tantivy for candidate notes
    // 3. Re-rank by embedding similarity
    // 4. Return top-k
}
```

### Flutter: AI Sidebar (`ui/lib/ai/ai_sidebar.dart`)

- **Model selector** (detected from Ollama)
- **Action buttons**: Summarize, Chat, Related, Tags, Tasks
- **Chat interface**: Streaming responses, citations inline
- **Context selector**: Current note / Selection / Date range / Tag / All
- **Privacy notice**: "Only selected notes sent to local Ollama"

### TUI: AI Commands

```bash
lumen ai summarize --week
lumen ai related --note 2026-02-03.md
lumen ai chat "What did I work on last month?"
lumen ai tags 2026-02-03.md
```

### Configuration

```toml
# ~/.config/lumen/config.toml
[ai]
enabled = true
ollama_url = "http://localhost:11434"
default_model = "llama3.1:8b"
embedding_model = "nomic-embed-text"
max_context_notes = 10
max_context_tokens = 4000
# Privacy: never send to external APIs
allow_external = false
```

---

## 5. Plugin System v2: WASM Sandbox

### Why WASM
- **Sandboxed**: No direct memory access, no syscalls
- **Language-agnostic**: Rust, Go, JS, Python (via wasm-pack/wasi)
- **Safe**: Crashes don't bring down Lumen
- **Portable**: Same `.wasm` works on all platforms

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Lumen Core                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              WASM Runtime (wasmtime)                 │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │    │
│  │  │ Plugin A    │  │ Plugin B    │  │ Plugin C    │  │    │
│  │  │ (wordcount) │  │ (ai-tags)   │  │ (export)    │  │    │
│  │  │ 5ms limit   │  │ 500ms limit │  │ 2s limit    │  │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### Plugin Manifest v2 (`plugin.toml`)

```toml
name = "ai-tag-suggester"
version = "1.0.0"
author = "user"
description = "Suggests tags using local LLM"
runtime = "wasm"  # or "native" (legacy)
entry = "plugin.wasm"

[permissions]
# Capability-based security
read_notes = true       # Can read note content (for on_note hook)
write_notes = false     # Cannot modify notes
network = false         # No network access
fs_read = ["templates/"] # Allowed filesystem paths
fs_write = []
max_memory_mb = 64
max_fuel = 10000000     # Instruction limit (wasmtime fuel)

[hooks]
on_note = true
on_export = false
on_startup = false

[config]
model = "llama3.1:8b"
max_tags = 5
```

### WASM Plugin SDK (Rust)

```rust
// lumen-plugin-sdk/src/lib.rs
use serde::{Deserialize, Serialize};
use wasm_bindgen::prelude::*;

#[derive(Deserialize)]
pub struct NoteContext {
    pub path: String,
    pub title: String,
    pub body: String,
    pub frontmatter: HashMap<String, serde_json::Value>,
}

#[derive(Serialize)]
pub struct PluginResult {
    pub feedback: Option<String>,      // UI toast
    pub frontmatter_patch: Option<HashMap<String, serde_json::Value>>,  // Auto-tag
    pub commands: Vec<PluginCommand>,  // Suggested actions
}

#[wasm_bindgen]
pub fn on_note(context: &str) -> String {
    let ctx: NoteContext = serde_json::from_str(context).unwrap();
    // ... plugin logic ...
    serde_json::to_string(&result).unwrap()
}

// Host functions (imported by plugin)
#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = host)]
    fn log(level: &str, msg: &str);
    
    #[wasm_bindgen(js_namespace = host)]
    fn get_config(key: &str) -> String;
    
    #[wasm_bindgen(js_namespace = host)]
    fn http_get(url: &str) -> String;  // Only if network permission granted
}
```

### Host Implementation (Core)

```rust
// core/src/plugins/wasm_host.rs
use wasmtime::*;

pub struct WasmPlugin {
    instance: Instance,
    memory: Memory,
    on_note_func: TypedFunc<(i32, i32), i32>,  // (ptr, len) -> ptr
    // ... other hooks
}

impl WasmPlugin {
    pub fn load(wasm_bytes: &[u8], config: PluginConfig) -> Result<Self> {
        let engine = Engine::new(Config::new()
            .consume_fuel(true)
            .max_memory_pages(config.max_memory_mb * 65536 / 65536)?);
        
        let mut linker = Linker::new(&engine);
        // Define host functions: log, get_config, http_get (if permitted)
        linker.func_wrap("host", "log", |caller: Caller<'_, _>, level_ptr: i32, level_len: i32, msg_ptr: i32, msg_len: i32| {
            // Read from guest memory, log to Lumen
        })?;
        
        let module = Module::new(&engine, wasm_bytes)?;
        let instance = linker.instantiate(&mut store, &module)?;
        
        Ok(Self { ... })
    }

    pub fn on_note(&mut self, context: &NoteContext) -> Result<PluginResult> {
        // 1. Serialize context → JSON
        // 2. Write to guest memory
        // 3. Call on_note_func(ptr, len)
        // 4. Read result from guest memory
        // 5. Deserialize PluginResult
    }
}
```

### Migration Path

| Phase | Action |
|-------|--------|
| 1 | Keep native `libloading` plugins working |
| 2 | Add WASM runtime alongside (opt-in) |
| 3 | Provide `cargo new --lib --edition 2021` template for WASM plugins |
| 4 | Port built-in plugins to WASM (wordcount, daily_summary, etc.) |
| 5 | Deprecate native external plugins (keep built-in native) |

### Plugin Store (Future)

- Curated WASM plugins in GitHub repo
- `lumen plugin install <name>` → downloads `.wasm` + verifies checksum
- Sandbox by default; user grants permissions per-plugin

---

## 6. Language Server Protocol (LSP)

### Goal: Markdown LSP for any editor (VS Code, Neovim, Helix, Zed)

**Features**:
- Wikilink completion (`[[` → fuzzy search)
- Frontmatter validation (schema)
- Broken link detection
- Tag/alias references
- Go to definition (note file)
- Rename note (updates all wikilinks)
- Document symbols (headings, tags, wikilinks)

### Implementation

**Server**: Rust (`tower-lsp` + Tantivy index)

```rust
// core/src/lsp/server.rs
use tower_lsp::{LanguageServer, LspService, Server};

#[derive(Debug)]
struct LumenLspServer {
    vault_path: PathBuf,
    index: Arc<SearchIndex>,
    wikilink_index: Arc<WikilinkIndex>,
}

#[tower_lsp::async_trait]
impl LanguageServer for LumenLspServer {
    async fn initialize(&self, params: InitializeParams) -> Result<InitializeResult> {
        Ok(InitializeResult {
            capabilities: ServerCapabilities {
                completion_provider: Some(CompletionOptions::default()),
                definition_provider: Some(OneOf::Left(true)),
                references_provider: Some(OneOf::Left(true)),
                rename_provider: Some(OneOf::Left(RenameOptions::default())),
                document_symbol_provider: Some(OneOf::Left(true)),
                text_document_sync: Some(TextDocumentSyncCapability::Kind(
                    TextDocumentSyncKind::INCREMENTAL,
                )),
                ..Default::default()
            },
            ..Default::default()
        })
    }

    async fn completion(&self, params: CompletionParams) -> Result<Option<CompletionResponse>> {
        // If trigger is `[[`, return wikilink completions
        // If in frontmatter, return tag/key completions
    }

    async fn goto_definition(&self, params: GotoDefinitionParams) -> Result<Option<GotoDefinitionResponse>> {
        // Resolve wikilink at position → file location
    }

    async fn references(&self, params: ReferenceParams) -> Result<Option<Vec<Location>>> {
        // Find all wikilinks pointing to this note
    }

    async fn rename(&self, params: RenameParams) -> Result<Option<WorkspaceEdit>> {
        // Rename note file + update all wikilinks
    }
}
```

**Distribution**: Single binary `lumen-lsp` (built from core)

**Editor Config** (VS Code):
```json
{
  "lumen.lsp.enable": true,
  "lumen.lsp.vaultPath": "~/Documents/lumen-journal"
}
```

---

## 7. Advanced Graph Features

### Graph Analytics

| Metric | Description | Use Case |
|--------|-------------|----------|
| **Centrality** | PageRank / Betweenness | Find hub notes |
| **Clusters** | Community detection (Louvain) | Topic discovery |
| **Orphans** | No in/out links | Notes needing connection |
| **Timeline** | Nodes by date | Temporal patterns |

### Graph Export

- **GraphML** → Gephi, Cytoscape
- **JSON** → D3.js, custom viz
- **Image** → PNG/SVG for sharing

---

## Task Breakdown

| # | Task | Area | Est. |
|---|------|------|------|
| 1 | ✅ Command palette (Flutter + TUI) | Core/Flutter/TUI | 3d |
| 2 | Vim/Emacs keymaps (Flutter + TUI) | Flutter/TUI | 3d |
| 3 | Canvas editor (Excalidraw) | Flutter | 5d |
| 4 | ✅ Ollama client + RAG (Core + Flutter) | Core/Flutter | 5d |
| 5 | ✅ WASM runtime + plugin SDK | Core | 7d |
| 6 | Port built-in plugins to WASM | Core | 3d |
| 7 | ✅ LSP server (lumen-lsp) | Core | 5d |
| 8 | Graph analytics + export | Flutter | 3d |
| 9 | Plugin permissions UI | Flutter | 2d |
| 10 | AI privacy settings + model mgmt | Flutter | 2d |

**Total**: ~38 days

---

## Definition of Done

- [x] `Ctrl+K` command palette with 30+ actions, plugin-extensible
- [ ] Vim/Emacs modes fully functional in Flutter editor
- [ ] Canvas editor creates `.canvas` files, embeds in notes, links to notes
- [ ] Local AI: summarize, chat, related notes, tags — all via Ollama, zero cloud
- [ ] WASM plugins run sandboxed with fuel/memory limits, native plugins still work
- [x] LSP server provides wikilink completion, goto def, rename, refs in VS Code/Neovim
- [ ] Graph shows clusters, centrality, exports to GraphML
- [ ] All features optional, privacy-preserving, work offline