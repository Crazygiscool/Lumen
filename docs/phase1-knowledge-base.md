# Phase 1: Knowledge Base Foundations

**Goal**: Transform Lumen from a journal into a personal knowledge base (PKM) with networked thought primitives.

**Status**: ✅ Shipped. The core, the desktop app and the terminal client all
carry the features below. What the build turned out to need is written down
at the end of this document, under *What the build changed*.

---

## 1. Wikilinks + Backlinks

### Core (Rust)

**New module**: `core/src/wikilinks.rs`

```rust
use std::ops::Range;

#[derive(Debug, Clone)]
pub struct Wikilink {
    pub target: String,           // Raw target: "note name"
    pub display: Option<String>,  // Optional: "display text"
    pub position: Range<usize>,   // Byte range in source body
}

pub fn parse_wikilinks(body: &str) -> Vec<Wikilink> {
    // Regex: \[\[([^\]]+?)(?:\|([^\]]+))?\]\]
    // Returns all matches with positions
}

pub fn normalize_wikilink_target(target: &str) -> String {
    // Lowercase, trim, spaces → hyphens, remove special chars
    // "My Note" → "my-note"
}
```

**Extend `VaultEntry`** (in `core/src/vault/mod.rs`):
```rust
pub struct VaultEntry {
    // ... existing fields
    pub backlinks: Vec<String>,  // Paths that link to this entry
}
```

**Backlink index** (in `core/src/vault/mod.rs`):
```rust
// In-memory index, rebuilt on vault unlock + updated on write
static BACKLINK_INDEX: Mutex<HashMap<String, Vec<String>>> = Mutex::new(HashMap::new());

pub fn update_backlinks(store: &str, path: &str, wikilinks: &[Wikilink]) {
    // 1. Remove old backlinks for `path`
    // 2. For each wikilink, resolve target to actual path
    // 3. Add `path` to target's backlink list
}

pub fn get_backlinks(store: &str, path: &str) -> Vec<String> {
    BACKLINK_INDEX.lock().unwrap().get(path).cloned().unwrap_or_default()
}
```

**Hook into `write_text`**:
```rust
pub fn write_text(path: &str, body: &str, store: &str) -> Result<()> {
    let wikilinks = wikilinks::parse_wikilinks(body);
    // ... existing encryption/write ...
    wikilinks::update_backlinks(store, path, &wikilinks);
    Ok(())
}
```

### FFI Exports (`core/ffi.rs`)

```rust
#[no_mangle]
pub extern "C" fn lumen_wikilinks_parse(body: *const c_char) -> *mut c_char {
    // Returns JSON array of {target, display, start, end}
}

#[no_mangle]
pub extern "C" fn lumen_backlinks_get(store: *const c_char, path: *const c_char) -> *mut c_char {
    // Returns JSON array of backlink paths
}

#[no_mangle]
pub extern "C" fn lumen_wikilink_resolve(store: *const c_char, target: *const c_char) -> *mut c_char {
    // Returns resolved path or NULL
}
```

### Flutter UI (`ui/lib/journal/`)

**Backlinks Panel** (`backlinks_panel.dart`):
- Right drawer or bottom sheet
- Lists all notes linking to current note
- Click → navigate
- Shows context snippet around link

**Wikilink Completion** (`wikilink_completion.dart`):
- Trigger on `[[` in editor
- Fuzzy search over entry titles (Tantivy or simple prefix)
- Insert `[[target|display]]` on select

**Preview Rendering** (`markdown_renderer.dart`):
- Custom syntax highlighter for `[[wikilink]]`
- Tap handler → `lumen_wikilink_resolve` → navigate or create

### TUI (`tui/src/main.rs`)

- `b` key in preview → show backlinks list
- `Enter` on backlink → jump to that note
- `[[` in editor → open fuzzy picker (reuse search)

---

## 2. Daily Note Templates

### Core

**Template file**: `~/.config/lumen/templates/daily.md` (user creates/edits)

**Placeholders**:
| Placeholder | Example Output |
|-------------|----------------|
| `{{date}}` | `2026-02-03` |
| `{{date:format}}` | `{{date:%A, %B %d, %Y}}` → `Tuesday, February 03, 2026` |
| `{{time}}` | `14:32` |
| `{{yesterday}}` | `2026-02-02` |
| `{{tomorrow}}` | `2026-02-04` |
| `{{week}}` | `2026-W05` |
| `{{month}}` | `2026-02` |
| `{{iso_week}}` | `2026-W05` |

**Module**: `core/src/template.rs`
```rust
use chrono::{NaiveDate, Datelike, Weekday};

pub fn render_daily_template(date: NaiveDate) -> String {
    let template_path = config::daily_template_path(); // ~/.config/lumen/templates/daily.md
    let template = fs::read_to_string(template_path).unwrap_or_default();
    
    let replacements = [
        ("{{date}}", date.format("%Y-%m-%d").to_string()),
        ("{{time}}", Local::now().format("%H:%M").to_string()),
        ("{{yesterday}}", (date - Duration::days(1)).format("%Y-%m-%d").to_string()),
        ("{{tomorrow}}", (date + Duration::days(1)).format("%Y-%m-%d").to_string()),
        ("{{week}}", format!("{}-W{:02}", date.year(), date.iso_week().week())),
        ("{{month}}", date.format("%Y-%m").to_string()),
        // {{date:format}} handled via regex
    ];
    
    let mut result = template;
    for (k, v) in replacements {
        result = result.replace(k, &v);
    }
    // Handle {{date:format}} with regex
    result
}

pub fn daily_note_path(date: NaiveDate) -> String {
    format!("{}.md", date.format("%Y-%m-%d"))
}
```

### FFI

```rust
#[no_mangle]
pub extern "C" fn lumen_daily_note_path(date_ms: i64) -> *mut c_char {
    // date_ms = milliseconds since epoch
    // Returns "YYYY-MM-DD.md"
}

#[no_mangle]
pub extern "C" fn lumen_render_daily_template(date_ms: i64) -> *mut c_char {
    // Returns rendered template string
}
```

### Flutter

- **Dashboard**: "New Daily Note" button → calls `lumen_daily_note_path(today)` → opens/creates
- **Settings**: Template editor with live preview
- **Command palette**: "Open Daily Note" for any date

### TUI

- `lumen today` → uses template (already exists, enhance)
- `lumen daily 2026-02-03` → open any date's daily note
- `lumen daily-template` → print template path for editing

---

## 3. Frontmatter (YAML)

### Core

**Parse on read** (`core/src/frontmatter.rs`):
```rust
use serde::{Deserialize, Serialize};
use serde_yaml;

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct Frontmatter {
    pub tags: Vec<String>,
    pub aliases: Vec<String>,
    pub title: Option<String>,
    pub date: Option<NaiveDate>,
    pub cssclass: Option<String>,
    #[serde(flatten)]
    pub custom: HashMap<String, serde_json::Value>,
}

pub fn parse_frontmatter(body: &str) -> (Frontmatter, String) {
    // Split on first `---` ... `---`
    // Parse YAML, return (frontmatter, body_without_frontmatter)
}

pub fn serialize_frontmatter(fm: &Frontmatter, body: &str) -> String {
    let yaml = serde_yaml::to_string(fm).unwrap();
    format!("---\n{}---\n{}", yaml, body)
}
```

**Extend `VaultEntry`**:
```rust
pub struct VaultEntry {
    // ...
    pub frontmatter: Frontmatter,
}
```

**Query API**:
```rust
pub fn query_entries(store: &str, filter: FrontmatterFilter) -> Vec<VaultEntry> {
    // filter: tag, key:value, date range, etc.
    // Scan all entries (or use Tantivy index for tagged fields)
}
```

### FFI

```rust
#[no_mangle]
pub extern "C" fn lumen_frontmatter_get(store: *const c_char, path: *const c_char) -> *mut c_char {
    // Returns JSON of Frontmatter
}

#[no_mangle]
pub extern "C" fn lumen_frontmatter_set(store: *const c_char, path: *const c_char, fm_json: *const c_char) -> i32 {
    // Updates frontmatter, rewrites file
}

#[no_mangle]
pub extern "C" fn lumen_query_entries(store: *const c_char, filter_json: *const c_char) -> *mut c_char {
    // Returns JSON array of matching entries
}
```

### Flutter

- **Frontmatter Editor** (`frontmatter_editor.dart`):
  - Collapsible panel above editor
  - Tags: chip input with autocomplete
  - Aliases: text list
  - Custom fields: key-value pairs
- **Journal List**: Filter/sort by tags, date, custom fields
- **Search**: `tag:project` syntax

### TUI

- `:frontmatter` command → opens `$EDITOR` with YAML frontmatter
- `lumen list --tag project` → filter by tag
- `lumen query 'tag:meeting date:2026-02'` → advanced query

---

## 4. Full-Text Search (Tantivy)

### Core

**Dependency**: `tantivy = "0.20"` in `core/Cargo.toml`

**Index location**: the configuration folder, not the vault

The index holds the plain text of every note. The vault is what the user
syncs, shares and backs up, and everything in it is meant to be encrypted —
so the index is kept outside the vault, one directory per vault:

```
<config_dir>/search/<store>-<sha256[..8] fingerprint>/
```

An index left in the vault by an older version is removed on unlock, so it
cannot be synced along with the notes. `search.index_path` in the
configuration says where the indexes live; a relative path is taken from the
configuration folder.

**Schema** (`core/src/search.rs`):
```rust
use tantivy::{schema::*, Index, IndexWriter, query::QueryParser};

lazy_static! {
    static ref SCHEMA: Schema = {
        let mut builder = Schema::builder();
        builder.add_text_field("path", STRING | STORED);
        builder.add_text_field("title", TEXT | STORED);
        builder.add_text_field("body", TEXT);
        builder.add_text_field("frontmatter", TEXT | STORED); // JSON string
        builder.add_u64_field("modified", STORED | FAST);
        builder.build()
    };
}

pub struct SearchIndex {
    index: Index,
    writer: Mutex<IndexWriter>,
}

impl SearchIndex {
    pub fn open_or_create(store_path: &str) -> Result<Self> {
        let index_path = Path::new(store_path).join(".lumen/search");
        fs::create_dir_all(&index_path)?;
        let index = Index::open_or_create(index_path, SCHEMA.clone())?;
        let writer = index.writer(50_000_000)?; // 50MB heap
        Ok(Self { index, writer: Mutex::new(writer) })
    }

    pub fn index_entry(&self, entry: &VaultEntry) -> Result<()> {
        let mut writer = self.writer.lock().unwrap();
        let mut doc = TantivyDocument::default();
        doc.add_text("path", &entry.rel_path);
        doc.add_text("title", &entry.frontmatter.title.as_deref().unwrap_or(&entry.name));
        doc.add_text("body", &entry.body);
        doc.add_text("frontmatter", &serde_json::to_string(&entry.frontmatter)?);
        doc.add_u64("modified", entry.modified.timestamp_millis() as u64);
        writer.delete_term(Term::from_field_text("path", &entry.rel_path));
        writer.add_document(doc)?;
        writer.commit()?;
        Ok(())
    }

    pub fn search(&self, query: &str, limit: usize) -> Result<Vec<SearchHit>> {
        let reader = self.index.reader()?;
        let searcher = reader.searcher();
        let query_parser = QueryParser::for_index(&self.index, vec![
            SCHEMA.get_field("title"),
            SCHEMA.get_field("body"),
            SCHEMA.get_field("frontmatter"),
        ]);
        let query = query_parser.parse_query(query)?;
        let top_docs = searcher.search(&query, &TopDocs::with_limit(limit))?;
        
        Ok(top_docs.into_iter().map(|(score, doc_addr)| {
            let doc = searcher.doc(doc_addr).unwrap();
            SearchHit {
                path: doc.get_first("path").unwrap().as_text().unwrap().to_string(),
                title: doc.get_first("title").unwrap().as_text().unwrap().to_string(),
                snippet: self.snippet(&doc, &query),
                score,
            }
        }).collect())
    }

    pub fn rebuild(&self, store: &str) -> Result<()> {
        // Iterate all vault entries, re-index
    }
}
```

**Hook into `write_text`**:
```rust
pub fn write_text(path: &str, body: &str, store: &str) -> Result<()> {
    // ... existing ...
    let entry = read_entry_with_frontmatter(path, store)?;
    SEARCH_INDEX.index_entry(&entry)?;
    Ok(())
}
```

### FFI

```rust
#[no_mangle]
pub extern "C" fn lumen_search_tantivy(store: *const c_char, query: *const c_char, limit: usize) -> *mut c_char {
    // Returns JSON array of SearchHit
}

#[no_mangle]
pub extern "C" fn lumen_rebuild_index(store: *const c_char) -> i32 {
    // Returns 0 on success
}
```

### Flutter

- **Search Bar** (`search_bar.dart`):
  - Debounced (150ms) as-you-type
  - Shows results in dropdown/overlay
  - Highlight matched terms in snippet
- **Search Screen** (`search_screen.dart`):
  - Full-screen results with filters
  - Filter chips: tags, date range, frontmatter fields
  - Keyboard shortcut: `Ctrl+K` / `Cmd+K`

### TUI

- `lumen search query` → uses Tantivy backend
- `/` in TUI → interactive search mode with live results

---

## 5. Graph View (Flutter)

### Data Model

```dart
// ui/lib/graph/graph_data.dart
class GraphNode {
  final String id;           // entry path
  final String title;
  final List<String> tags;
  final int weight;          // word count + link count
  final Map<String, dynamic> frontmatter;
}

class GraphEdge {
  final String source;
  final String target;
  final EdgeType type;       // Wikilink, Backlink, Tag
}

class GraphData {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
}
```

### Core FFI

```rust
#[no_mangle]
pub extern "C" fn lumen_graph_data(store: *const c_char) -> *mut c_char {
    // Build nodes from all entries
    // Build edges from wikilinks + backlinks + shared tags
    // Return JSON
}
```

### Flutter Implementation

**Package**: `flutter_graph` or `graph_view` (force-directed)

**Features**:
- **Layout**: Force-directed (D3-style) with `flutter_graph`
- **Nodes**: Sized by weight, colored by tag/topic
- **Edges**: Wikilinks (solid), backlinks (dashed), tags (dotted)
- **Interactions**:
  - Pan/zoom (mouse wheel, pinch)
  - Click node → open note
  - Hover → preview tooltip
  - Drag → reposition (sticky)
- **Filters** (sidebar):
  - Tag multi-select
  - Date range
  - Connected component only
  - Search highlight
- **Performance**:
  - Virtualized rendering (only visible nodes)
  - Level-of-detail (simplify edges at zoom < 0.5)
  - WebAssembly layout for 5k+ nodes (optional)

**File**: `ui/lib/graph/graph_view.dart`

---

## Task Breakdown & Timeline

| # | Task | Area | Depends On | Est. Days |
|---|------|------|------------|-----------|
| 1 | Tantivy schema + indexer | Core | — | 3 |
| 2 | Wikilink parser + backlink index | Core | — | 2 |
| 3 | Frontmatter parse/serialize | Core | — | 1 |
| 4 | Daily template rendering | Core | 3 | 1 |
| 5 | FFI exports for all | Core | 1-4 | 1 |
| 6 | Flutter search UI (Tantivy) | Flutter | 1, 5 | 3 |
| 7 | Wikilink completion + backlinks panel | Flutter | 2, 5 | 3 |
| 8 | Frontmatter editor | Flutter | 3, 5 | 2 |
| 9 | Daily note from template | Flutter | 4, 5 | 1 |
| 10 | Graph view | Flutter | 2, 5 | 5 |
| 11 | TUI search/wikilinks/backlinks | TUI | 1, 2, 5 | 3 |
| 12 | TUI daily template + frontmatter | TUI | 3, 4, 5 | 2 |

**Total**: ~27 days (sequential) / ~15 days (parallel core first, then Flutter/TUI)

**Critical Path**: Core tasks 1-5 → FFI → Flutter/TUI tasks

---

## Configuration

```toml
# ~/.config/Lumen/config.toml
[templates]
daily = "~/.config/Lumen/templates/daily.md"

[search]
enabled = true
# The index holds the plain text of the notes, so it stays out of the
# vault. A relative path is taken from the configuration folder.
index_path = "search"
auto_reindex = true

[graph]
enabled = true
layout = "force"  # force, hierarchical, circular
max_nodes = 5000

[wikilinks]
case_sensitive = false
create_missing = true
```

---

## Definition of Done

- [x] `[[wikilink]]` navigates in Flutter & TUI
- [x] `[[wikilink]]` *creates* a missing note when `wikilinks.create_missing`
      is on — tapping a link to a note that is not there yet offers to create
      it, and the note is written through the vault so the indexes stay in
      step. The setting is honoured: with it off, tapping a missing link says
      so instead (`wikilinks.create_missing`).
- [x] Backlinks panel shows all incoming links with context
- [x] Daily notes use template with all placeholders
- [x] Frontmatter editable in Flutter; queryable via `tag:`, `key:value`
- [x] Tantivy search returns results in <100ms for 10k notes
- [x] Graph view renders, filters, navigates, performs at 5k nodes
- [x] All features work offline, zero network calls
- [x] Tests pass: `cargo test --workspace`, `flutter test`

---

## What the build changed

The plan above is what was written before the work started. A few things
came out differently, and the difference is worth writing down.

### The index moved out of the vault

The plan put the Tantivy index in `.lumen/search/`, inside the vault. The
index holds the plain text of every note, so it was the one place where the
notes lay open — and Syncthing would have carried it to every device. The
index now lives in the configuration folder, one directory per vault, and an
old one inside the vault is removed on unlock.

### A query language, so a client knows where to look

The plan had a search box and a frontmatter editor. What the clients
actually needed was a way to ask a question that spans both: *every note
tagged `work` that mentions `release`*.

`core/src/query.rs` grew a small query language for this:

| Term | Means |
|------|-------|
| `tag:work` | the note carries the tag |
| `date:2026-02` | the note's date starts with that |
| `project:lumen` | a frontmatter field equals that |
| `release` | free text |

The terms are ANDed. A field name is letters, digits, `-` and `_`; a value
may not start with `/`, so `https://example.com` stays free text.

`Query::has_filters()` tells a client where to look: plain words are a
question for the full-text index, and a filter is a question for the notes
themselves, because only they know what metadata they carry.

### The FFI is one entry point, not one per feature

The plan sketched a `#[no_mangle]` function per feature. The build settled
on a single `lumen_kb_call(method, args)` that answers with JSON, plus a
separate `lumen_kb_free`. The methods are named `kb.<area>.<action>`, and
the Dart side has one wrapper per area.

Most methods take the **store name** (`journal`), not a path: the core
resolves the store to the vault that is unlocked. The exceptions are the
methods that need the vault itself — `kb.sync.*` takes the vault path.

### The frontmatter is edited as YAML, in the core

The editor holds the body and the frontmatter separately, and joins them
again on save. The YAML form is produced and read by the core
(`frontmatter_to_yaml` / `frontmatter_from_yaml`), so every client edits
the same thing and none of them invents a format of its own.

### The graph layout is hand-written

The plan named `flutter_graph` or `graph_view`. The build uses a
hand-written force-directed layout instead: one less dependency, and the
layout can be tuned for the shape of a note graph rather than for a generic
one.

### The terminal client is a library

The terminal client was one file. It is now a library crate (`lumen_tui`)
with `cli.rs` (the commands), `app.rs` (the state and the keys), `ui.rs`
(the drawing) and a thin `main.rs`. The commands can be tested without a
terminal, which is why there are tests for them at all.
