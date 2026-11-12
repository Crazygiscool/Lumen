//! Full-text search using Tantivy.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use lazy_static::lazy_static;
use tantivy::{
    collector::TopDocs,
    directory::MmapDirectory,
    query::QueryParser,
    schema::{Field, Schema, TextFieldIndexing, TextOptions, Value, STORED, FAST},
    snippet::SnippetGenerator,
    Index, IndexWriter, ReloadPolicy, Term, TantivyDocument,
};

use crate::vault::{self, VaultEntry};
use crate::frontmatter::Frontmatter;
use crate::config;
use chrono::{Utc};
use sha2::{Digest, Sha256};

lazy_static! {
    static ref SEARCH_INDEXES: Mutex<HashMap<String, Arc<SearchIndex>>> = Mutex::new(HashMap::new());
}

/// The folder holding the search index of a vault.
///
/// The index holds the plain text of the notes, so it is kept out of the
/// vault: the vault is what the user syncs, shares and backs up, and
/// everything in it is meant to be encrypted.
///
/// Each vault gets its own folder under the configured base, named after a
/// fingerprint of the store and its path, so two journals never share an
/// index.
fn index_dir(store: &str, vault_path: &str) -> PathBuf {
    let config = config::get_config();
    let base = Path::new(&config.search.index_path);
    let base = if base.is_absolute() {
        base.to_path_buf()
    } else {
        config::config_dir().join(base)
    };

    let mut hasher = Sha256::new();
    hasher.update(store.as_bytes());
    hasher.update([0]);
    hasher.update(vault_path.as_bytes());
    let fingerprint = hex::encode(&hasher.finalize()[..8]);

    base.join(format!("{store}-{fingerprint}"))
}

/// The place the index used to live, inside the vault.
///
/// The index holds the plain text of the notes, so it was moved out of the
/// vault. An old one is removed, so that it cannot be synced or backed up
/// along with the notes.
fn legacy_index_dir(vault_path: &str) -> PathBuf {
    Path::new(vault_path).join(".lumen").join("search")
}

/// Search result hit.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SearchHit {
    pub path: String,
    pub title: String,
    pub snippet: String,
    pub score: f32,
}

/// Tantivy search index wrapper.
pub struct SearchIndex {
    index: Index,
    writer: Mutex<IndexWriter>,
    schema: SearchSchema,
    /// Directory holding the index files and the sidecar manifest.
    index_path: PathBuf,
}

/// Sidecar manifest of the notes the index currently covers.
///
/// Comparing it against the vault lets the index be brought up to date
/// incrementally, which is far cheaper than a full rebuild — a rebuild of a
/// large vault takes seconds, while a directory walk takes milliseconds.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
struct IndexManifest {
    /// Relative note path -> modification time in milliseconds.
    entries: HashMap<String, i64>,
}

/// Schema field references.
struct SearchSchema {
    path: Field,
    title: Field,
    body: Field,
    frontmatter: Field,
    tags: Field,
    modified: Field,
}

impl SearchIndex {
    /// Open or create the search index for a vault.
    pub fn open_or_create(store: &str, vault_path: &str) -> crate::Result<Arc<Self>> {
        let index_path = index_dir(store, vault_path);
        std::fs::create_dir_all(&index_path).map_err(|e| e.to_string())?;

        let schema = Self::build_schema();
        let index = Index::open_or_create(MmapDirectory::open(&index_path).map_err(|e| e.to_string())?, schema.clone()).map_err(|e| e.to_string())?;
        let writer = index.writer(50_000_000).map_err(|e| e.to_string())?; // 50MB heap

        let search_index = Arc::new(Self {
            index,
            writer: Mutex::new(writer),
            schema: SearchSchema::from_schema(schema),
            index_path,
        });

        Ok(search_index)
    }

    /// Build the Tantivy schema.
    fn build_schema() -> Schema {
        let mut builder = Schema::builder();

        // Path - stored for retrieval, indexed for exact lookups
        let path_options = TextOptions::default().set_indexing_options(TextFieldIndexing::default().set_tokenizer("raw")).set_stored();
        builder.add_text_field("path", path_options);

        // Title - full text search + stored
        let title_options = TextOptions::default()
            .set_indexing_options(TextFieldIndexing::default().set_tokenizer("en_stem").set_index_option(tantivy::schema::IndexRecordOption::WithFreqsAndPositions))
            .set_stored();
        builder.add_text_field("title", title_options);

        // Body - full text search, stored so snippets can be generated
        let body_options = TextOptions::default()
            .set_indexing_options(TextFieldIndexing::default().set_tokenizer("en_stem").set_index_option(tantivy::schema::IndexRecordOption::WithFreqsAndPositions))
            .set_stored();
        builder.add_text_field("body", body_options);

        // Frontmatter - indexed as JSON for tag/field search
        let fm_options = TextOptions::default()
            .set_indexing_options(TextFieldIndexing::default().set_tokenizer("raw"))
            .set_stored();
        builder.add_text_field("frontmatter", fm_options);

        // Tags - for tag-based search (e.g., "tag:work")
        let tags_options = TextOptions::default()
            .set_indexing_options(TextFieldIndexing::default().set_tokenizer("raw"))
            .set_stored();
        builder.add_text_field("tags", tags_options);

        // Modified timestamp - fast field for sorting
        builder.add_u64_field("modified", FAST | STORED);

        builder.build()
    }

    /// Get the global search index for a store, initializing if needed.
    pub fn global(store: &str) -> crate::Result<Arc<Self>> {
        let mut guard = SEARCH_INDEXES.lock().unwrap();
        if let Some(idx) = guard.get(store) {
            return Ok(idx.clone());
        }

        // Resolve store name to vault path for index directory
        let vault_path = crate::vault::get_vault_root(store)?;
        let idx = Self::open_or_create(store, &vault_path)?;
        guard.insert(store.to_string(), idx.clone());
        Ok(idx)
    }

    /// Index or re-index a single entry.
    pub fn index_entry(&self, entry: &VaultEntry, frontmatter: &Frontmatter, body: &str) -> crate::Result<()> {
        let mut writer = self.writer.lock().map_err(|e| e.to_string())?;

        // Delete existing
        writer.delete_term(Term::from_field_text(self.schema.path, &entry.rel_path));

        // Build document using doc! macro - need &str for text fields
        let title = frontmatter.title.as_deref().unwrap_or(&entry.name);
        let fm_json = serde_json::to_string(frontmatter).unwrap_or_default();
        
        let mut doc = TantivyDocument::default();
        doc.add_text(self.schema.path, entry.rel_path.as_str());
        doc.add_text(self.schema.title, title);
        doc.add_text(self.schema.body, body);
        doc.add_text(self.schema.frontmatter, fm_json.as_str());
        // Add each tag as a separate value for the tags field
        for tag in &frontmatter.tags {
            doc.add_text(self.schema.tags, tag.as_str());
        }
        doc.add_u64(self.schema.modified, entry.modified_ms as u64);

        writer.add_document(doc).map_err(|e| e.to_string())?;
        writer.commit().map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Remove an entry from the index.
    pub fn remove_entry(&self, path: &str) -> crate::Result<()> {
        let mut writer = self.writer.lock().map_err(|e| e.to_string())?;
        writer.delete_term(Term::from_field_text(self.schema.path, path));
        writer.commit().map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Search the index.
    ///
    /// Snippets are returned as HTML with `<b>` around the matched terms, so
    /// the UI can highlight them without re-running the query.
    pub fn search(&self, query_str: &str, limit: usize) -> crate::Result<Vec<SearchHit>> {
        let reader = self
            .index
            .reader_builder()
            .reload_policy(ReloadPolicy::OnCommitWithDelay)
            .try_into()
            .map_err(|e| e.to_string())?;
        let searcher = reader.searcher();

        let query_parser = QueryParser::for_index(&self.index, vec![self.schema.title, self.schema.body, self.schema.frontmatter, self.schema.tags]);
        let query = query_parser.parse_query(query_str).map_err(|e| e.to_string())?;

        let top_docs = searcher.search(&query, &TopDocs::with_limit(limit)).map_err(|e| e.to_string())?;

        let snippet_generator = SnippetGenerator::create(&searcher, &*query, self.schema.body)
            .map_err(|e| e.to_string())?;

        let mut hits = Vec::new();
        for (score, doc_addr) in top_docs {
            let doc: TantivyDocument = searcher.doc(doc_addr).map_err(|e| e.to_string())?;
            let path = doc.get_first(self.schema.path).map(|v| v.as_str().unwrap_or("").to_string()).unwrap_or_default();
            let title = doc.get_first(self.schema.title).map(|v| v.as_str().unwrap_or("").to_string()).unwrap_or_default();

            let snippet = snippet_generator.snippet_from_doc(&doc).to_html();

            hits.push(SearchHit { path, title, snippet, score });
        }

        Ok(hits)
    }

    /// Whether the index holds no documents.
    pub fn is_empty(&self) -> crate::Result<bool> {
        let reader = self
            .index
            .reader_builder()
            .reload_policy(ReloadPolicy::OnCommitWithDelay)
            .try_into()
            .map_err(|e| e.to_string())?;
        Ok(reader.searcher().num_docs() == 0)
    }

    /// Rebuild the entire index from vault.
    pub fn rebuild(&self, store: &str) -> crate::Result<()> {
        let mut writer = self.writer.lock().map_err(|e| e.to_string())?;
        writer.delete_all_documents().map_err(|e| e.to_string())?;

        let entries = vault::list("", store)?;
        for entry in entries {
            if entry.is_dir || !entry.name.ends_with(".md") {
                continue;
            }
            if let Ok(body) = vault::read_text(&entry.rel_path, store) {
                let (fm, _) = crate::frontmatter::parse_frontmatter(&body);
                let title = fm.title.as_deref().unwrap_or(&entry.name);
                let fm_json = serde_json::to_string(&fm).unwrap_or_default();

                let mut doc = TantivyDocument::default();
                doc.add_text(self.schema.path, entry.rel_path.as_str());
                doc.add_text(self.schema.title, title);
                doc.add_text(self.schema.body, body.as_str());
                doc.add_text(self.schema.frontmatter, fm_json.as_str());
                // Add each tag as a separate value for the tags field
                for tag in &fm.tags {
                    doc.add_text(self.schema.tags, tag.as_str());
                }
                doc.add_u64(self.schema.modified, entry.modified_ms as u64);

                writer.add_document(doc).map_err(|e| e.to_string())?;
            }
        }
        writer.commit().map_err(|e| e.to_string())?;

        // Record what the index now covers, so the next sync is a no-op.
        self.write_manifest(&Self::vault_note_mtimes(store)?)?;
        Ok(())
    }

    /// Bring the index in line with the vault, touching only what changed.
    ///
    /// Returns whether anything was updated. Notes edited inside the app are
    /// already indexed by the write hook, so this mainly picks up notes that
    /// arrived out of band — through sync, or an external editor.
    pub fn sync_with_vault(&self, store: &str) -> crate::Result<bool> {
        let notes = Self::vault_note_mtimes(store)?;
        let manifest = self.read_manifest();

        let mut changed = false;
        {
            let mut writer = self.writer.lock().map_err(|e| e.to_string())?;

            // Drop notes that are no longer in the vault.
            for path in manifest.entries.keys() {
                if !notes.contains_key(path) {
                    writer.delete_term(Term::from_field_text(self.schema.path, path));
                    changed = true;
                }
            }

            // Add notes that are new or whose content changed.
            for (path, mtime) in &notes {
                if manifest.entries.get(path) == Some(mtime) {
                    continue;
                }
                let body = match vault::read_text(path, store) {
                    Ok(body) => body,
                    Err(_) => continue,
                };
                let (fm, _) = crate::frontmatter::parse_frontmatter(&body);
                let fallback_title = Path::new(path.as_str())
                    .file_name()
                    .map(|n| n.to_string_lossy().to_string())
                    .unwrap_or_else(|| path.clone());
                let title = fm.title.as_deref().unwrap_or(fallback_title.as_str());
                let fm_json = serde_json::to_string(&fm).unwrap_or_default();

                writer.delete_term(Term::from_field_text(self.schema.path, path));

                let mut doc = TantivyDocument::default();
                doc.add_text(self.schema.path, path.as_str());
                doc.add_text(self.schema.title, title);
                doc.add_text(self.schema.body, body.as_str());
                doc.add_text(self.schema.frontmatter, fm_json.as_str());
                for tag in &fm.tags {
                    doc.add_text(self.schema.tags, tag.as_str());
                }
                doc.add_u64(self.schema.modified, (*mtime).max(0) as u64);

                writer.add_document(doc).map_err(|e| e.to_string())?;
                changed = true;
            }

            if changed {
                writer.commit().map_err(|e| e.to_string())?;
            }
        }

        self.write_manifest(&notes)?;
        Ok(changed)
    }

    /// Modification times of every note in the vault, keyed by relative path.
    fn vault_note_mtimes(store: &str) -> crate::Result<HashMap<String, i64>> {
        let mut notes = HashMap::new();
        for entry in vault::list("", store)? {
            if entry.is_dir || !entry.name.ends_with(".md") {
                continue;
            }
            notes.insert(entry.rel_path, entry.modified_ms);
        }
        Ok(notes)
    }

    /// Path of the sidecar manifest.
    fn manifest_path(&self) -> PathBuf {
        self.index_path.join("lumen-index-manifest.json")
    }

    /// Read the sidecar manifest, treating an unreadable one as empty.
    fn read_manifest(&self) -> IndexManifest {
        std::fs::read_to_string(self.manifest_path())
            .ok()
            .and_then(|raw| serde_json::from_str(&raw).ok())
            .unwrap_or_default()
    }

    /// Write the sidecar manifest.
    fn write_manifest(&self, entries: &HashMap<String, i64>) -> crate::Result<()> {
        let manifest = IndexManifest {
            entries: entries.clone(),
        };
        let raw = serde_json::to_string(&manifest).map_err(|e| e.to_string())?;
        std::fs::write(self.manifest_path(), raw).map_err(|e| e.to_string())
    }
}

impl SearchSchema {
    fn from_schema(schema: Schema) -> Self {
        Self {
            path: schema.get_field("path").unwrap(),
            title: schema.get_field("title").unwrap(),
            body: schema.get_field("body").unwrap(),
            frontmatter: schema.get_field("frontmatter").unwrap(),
            tags: schema.get_field("tags").unwrap(),
            modified: schema.get_field("modified").unwrap(),
        }
    }
}

/// Initialize search index on vault unlock.
pub fn init_search_index(store: &str) -> crate::Result<()> {
    let config = config::get_config();
    if !config.search.enabled {
        return Ok(());
    }

    // The index used to live in the vault, where it held the plain text of
    // the notes. It lives outside the vault now, and an old one is removed
    // so it cannot be synced or backed up along with the notes.
    if let Ok(vault_path) = crate::vault::get_vault_root(store) {
        let legacy = legacy_index_dir(&vault_path);
        if legacy.exists() {
            let _ = std::fs::remove_dir_all(&legacy);
        }
    }

    let index = SearchIndex::global(store)?;

    // An incremental sync only touches the notes that changed, so it stays
    // fast enough to run on every unlock. A full rebuild is available via
    // `kb.search.reindex` for when the index itself is suspect.
    if config.search.auto_reindex {
        index.sync_with_vault(store)?;
    }

    Ok(())
}

/// Search entries in the vault.
pub fn search_entries(store: &str, query: &str, limit: usize) -> crate::Result<Vec<SearchHit>> {
    let index = SearchIndex::global(store)?;
    index.search(query, limit)
}

/// Index a single entry on write.
pub fn index_entry_on_write(store: &str, path: &str, body: &str) -> crate::Result<()> {
    let config = config::get_config();
    if !config.search.enabled {
        return Ok(());
    }

    let index = SearchIndex::global(store)?;
    let (fm, _) = crate::frontmatter::parse_frontmatter(body);

    // Create a minimal VaultEntry for indexing
    let entry = VaultEntry {
        name: Path::new(path)
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| path.to_string()),
        rel_path: path.to_string(),
        is_dir: false,
        modified_ms: Utc::now().timestamp_millis(),
        size: body.len() as u64,
    };

    index.index_entry(&entry, &fm, body)?;

    // Keep the manifest in step, so the next unlock does not see this note as
    // changed and rebuild it.
    let mut manifest = index.read_manifest();
    manifest.entries.insert(path.to_string(), entry.modified_ms);
    index.write_manifest(&manifest.entries)?;
    Ok(())
}

/// Remove an entry from index on delete.
pub fn remove_entry_from_index(store: &str, path: &str) -> crate::Result<()> {
    let config = config::get_config();
    if !config.search.enabled {
        return Ok(());
    }

    let index = SearchIndex::global(store)?;
    index.remove_entry(path)?;

    // Drop it from the manifest too, so the next sync does not try to
    // re-index a note that no longer exists.
    let mut manifest = index.read_manifest();
    manifest.entries.remove(path);
    index.write_manifest(&manifest.entries)?;
    Ok(())
}

/// Clear the global search index map (for testing).
pub fn clear_search_indexes() {
    let mut guard = SEARCH_INDEXES.lock().unwrap();
    guard.clear();
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vault::{self, STORE_JOURNAL};
    use crate::config::{self, SearchConfig, Config};
    use std::fs;
    use std::path::Path;

    fn setup_test_vault() -> (
        tempfile::TempDir,
        tempfile::TempDir,
        String,
        crate::testutil::TestGuard,
    ) {
        // The vault registry is process-global, so hold the shared lock for
        // the duration of the test.
        let guard = crate::testutil::TestGuard::new();

        // Clear global search indexes to avoid schema mismatch
        clear_search_indexes();

        let temp = tempfile::tempdir().unwrap();
        let config_temp = tempfile::tempdir().unwrap();
        let vault_path = temp.path().to_string_lossy().to_string();

        // The index lives outside the vault, so the configuration is pointed
        // at a temporary folder of its own — a test must not write to the
        // user's own configuration.
        config::set_config_dir(Some(config_temp.path().to_path_buf()));

        vault::create_with_passphrase(&vault_path, "testpass123", STORE_JOURNAL).unwrap();
        vault::unlock(&vault_path, "testpass123", STORE_JOURNAL).unwrap();

        // Set config to enable search
        let mut cfg = config::get_config();
        cfg.search = SearchConfig {
            enabled: true,
            index_path: "search".to_string(),
            auto_reindex: true,
        };
        config::set_config(cfg);

        (temp, config_temp, vault_path, guard)
    }

    #[test]
    fn test_search_index_basic() {
        let (_temp, _config, _vault_path, _guard) = setup_test_vault();

        // Write test entries
        vault::write_text("2026-01-01.md", "# Day One\n\nFirst day of the year.", STORE_JOURNAL).unwrap();
        vault::write_text("2026-01-02.md", "# Day Two\n\nSecond day, feeling good.", STORE_JOURNAL).unwrap();
        vault::write_text("meeting-notes.md", "# Meeting\n\nProject planning meeting.", STORE_JOURNAL).unwrap();

        // Initialize search
        init_search_index(STORE_JOURNAL).unwrap();

        // Search
        let results = search_entries(STORE_JOURNAL, "first", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert!(results[0].path.contains("2026-01-01"));

        let results = search_entries(STORE_JOURNAL, "meeting", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert!(results[0].path.contains("meeting-notes"));

        let results = search_entries(STORE_JOURNAL, "day", 10).unwrap();
        assert_eq!(results.len(), 2);
    }

    #[test]
    fn test_search_with_frontmatter() {
        let (_temp, _config, _vault_path, _guard) = setup_test_vault();

        let body = r#"---
tags: [work, important]
---

# Important Work Note

This is tagged."#;
        vault::write_text("tagged.md", body, STORE_JOURNAL).unwrap();

        init_search_index(STORE_JOURNAL).unwrap();

        let results = search_entries(STORE_JOURNAL, "tags:work", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert!(results[0].path.contains("tagged"));
    }

    /// The index holds the plain text of the notes, so it must not sit in
    /// the vault: the vault is synced and backed up, and everything in it
    /// is meant to be encrypted.
    #[test]
    fn test_the_index_stays_out_of_the_vault() {
        let (_temp, _config, vault_path, _guard) = setup_test_vault();

        vault::write_text(
            "2026-01-01.md",
            "# Day One\n\nFirst day of the year.",
            STORE_JOURNAL,
        )
        .unwrap();
        init_search_index(STORE_JOURNAL).unwrap();

        let index = index_dir(STORE_JOURNAL, &vault_path);
        assert!(!index.starts_with(Path::new(&vault_path)));
        assert!(index.exists());

        // Nothing in the vault holds the plain text of the note.
        for entry in walkdir::WalkDir::new(&vault_path) {
            let entry = entry.unwrap();
            if !entry.file_type().is_file() {
                continue;
            }
            let bytes = std::fs::read(entry.path()).unwrap();
            assert!(!String::from_utf8_lossy(&bytes).contains("First day of the year"));
        }
    }

    /// An index left in the vault by an older version is removed, so it
    /// cannot be synced or backed up along with the notes.
    #[test]
    fn test_an_old_index_in_the_vault_is_removed() {
        let (_temp, _config, vault_path, _guard) = setup_test_vault();

        let legacy = legacy_index_dir(&vault_path);
        std::fs::create_dir_all(&legacy).unwrap();
        std::fs::write(legacy.join("old-index"), "plain text of the notes").unwrap();

        init_search_index(STORE_JOURNAL).unwrap();

        assert!(!legacy.exists());
    }
}