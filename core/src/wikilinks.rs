//! Wikilink parsing and backlink index.
//!
//! Supports `[[note name]]` and `[[note name|display text]]` syntax.

use std::collections::{HashMap, HashSet};
use std::ops::Range;
use std::sync::Mutex;

use lazy_static::lazy_static;
use regex::Regex;

use crate::config;
use crate::vault::{self};

/// A parsed wikilink with its position in the source text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Wikilink {
    /// The target note name (normalized).
    pub target: String,
    /// Optional display text (from `[[target|display]]`).
    pub display: Option<String>,
    /// Byte range in the source markdown body.
    pub position: Range<usize>,
}

/// The backlink index and the stores it has been built for.
#[derive(Default)]
struct BacklinkState {
    /// Target note path -> paths of the notes that link to it.
    index: HashMap<String, Vec<String>>,
    /// Stores whose index has been built at least once.
    built: HashSet<String>,
}

lazy_static! {
    /// Global backlink index: note path -> list of paths that link to it.
    static ref BACKLINK_INDEX: Mutex<BacklinkState> = Mutex::new(BacklinkState::default());
}

/// Regex for `[[target]]` or `[[target|display]]`.
fn wikilink_regex() -> &'static Regex {
    lazy_static! {
        static ref RE: Regex = Regex::new(r"\[\[([^\]]+?)(?:\|([^\]]+))?\]\]").unwrap();
    }
    &RE
}

/// Normalize a wikilink target to a vault path.
/// Lowercase, trim, spaces/hyphens normalized, .md appended if missing.
pub fn normalize_target(target: &str) -> String {
    let mut s = target.trim().to_lowercase();
    // Replace spaces and underscores with hyphens
    s = s.replace(' ', "-").replace('_', "-");
    // Remove any non-alphanumeric/hyphen/dot characters (preserve .md extension)
    s = s
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '.')
        .collect();
    // Collapse multiple hyphens
    while s.contains("--") {
        s = s.replace("--", "-");
    }
    s = s.trim_matches('-').to_string();
    if !s.ends_with(".md") {
        s.push_str(".md");
    }
    s
}

/// Parse all wikilinks from a markdown body.
pub fn parse_wikilinks(body: &str) -> Vec<Wikilink> {
    wikilink_regex()
        .captures_iter(body)
        .map(|cap| {
            let target = cap[1].trim().to_string();
            let display = cap.get(2).map(|m| m.as_str().trim().to_string());
            let position = cap.get(0).unwrap().range();
            Wikilink {
                target: normalize_target(&target),
                display,
                position,
            }
        })
        .collect()
}

/// Resolve a normalized wikilink target to an actual vault entry path.
/// Returns the exact path if found, otherwise the normalized target.
pub fn resolve_wikilink(store: &str, target: &str) -> String {
    let normalized = normalize_target(target);
    // Try exact match first
    if vault::read_text(&normalized, store).is_ok() {
        return normalized;
    }
    // Try case-insensitive match by listing entries
    if let Ok(entries) = vault::list("", store) {
        let target_lower = normalized.to_lowercase();
        let target_slug = slugify(&normalized);
        for entry in &entries {
            if entry.is_dir {
                continue;
            }
            if entry.name.to_lowercase() == target_lower {
                return entry.rel_path.clone();
            }
        }
        // Fall back to comparing the folded names, so `[[My Note]]` finds
        // `My Note.md` and `my-note.md` alike. Without this, a note whose
        // name contains a space could not be linked to at all.
        for entry in &entries {
            if entry.is_dir {
                continue;
            }
            if slugify(&entry.name) == target_slug {
                return entry.rel_path.clone();
            }
        }
    }
    normalized
}

/// Create a note for a wikilink target that does not exist yet.
///
/// Only created when the `wikilinks.create_missing` setting is on, and only
/// when there is no note with that (normalized) target already. The note is
/// written empty, so the editor can open it and the user can fill it in.
pub fn create_missing(store: &str, target: &str) -> crate::Result<String> {
    let config = config::get_config();
    if !config.wikilinks.create_missing {
        return Err(
            "creating missing notes is disabled; turn on wikilinks.create_missing".to_string(),
        );
    }

    let normalized = normalize_target(target);

    // A note with this target already exists: nothing to create.
    if vault::read_text(&normalized, store).is_ok() {
        return Err(format!("{normalized} already exists"));
    }

    vault::write_text(&normalized, "", store)?;

    Ok(normalized)
}

/// Fold a name into a comparable form.
///
/// The name is lower-cased and every run of characters that is not a letter
/// or a digit becomes a single hyphen, so `My Note.md` and `my-note.md`
/// fold to the same thing.
fn slugify(name: &str) -> String {
    let mut out = String::with_capacity(name.len());
    let mut pending_separator = false;

    for c in name.chars() {
        if c.is_ascii_alphanumeric() {
            if pending_separator && !out.is_empty() {
                out.push('-');
            }
            pending_separator = false;
            out.push(c.to_ascii_lowercase());
        } else {
            pending_separator = true;
        }
    }

    out
}

/// Update the backlink index for a note that was just written.
/// Removes old backlinks for `path`, adds new ones from `wikilinks`.
pub fn update_backlinks(store: &str, path: &str, wikilinks: &[Wikilink]) {
    let mut state = BACKLINK_INDEX.lock().unwrap();

    // Remove this path from all backlink lists
    for backlinks in state.index.values_mut() {
        backlinks.retain(|p| p != path);
    }

    // Add new backlinks
    for wl in wikilinks {
        let target_path = resolve_wikilink(store, &wl.target);
        state
            .index
            .entry(target_path)
            .or_default()
            .push(path.to_string());
    }
}

/// Get all backlinks for a given note path.
///
/// The index is built on first use: scanning every note costs about as much
/// as reading the whole vault, which is too slow to do on every unlock.
pub fn get_backlinks(store: &str, path: &str) -> Vec<String> {
    if !is_built(store) {
        rebuild_backlink_index(store);
    }
    BACKLINK_INDEX
        .lock()
        .unwrap()
        .index
        .get(path)
        .cloned()
        .unwrap_or_default()
}

/// Whether the backlink index has been built for a store.
fn is_built(store: &str) -> bool {
    BACKLINK_INDEX.lock().unwrap().built.contains(store)
}

/// Clear the backlink index.
pub fn clear_backlink_index() {
    let mut state = BACKLINK_INDEX.lock().unwrap();
    state.index.clear();
    state.built.clear();
}

/// Rebuild the entire backlink index by scanning all notes.
pub fn rebuild_backlink_index(store: &str) {
    let mut state = BACKLINK_INDEX.lock().unwrap();
    state.index.clear();

    if let Ok(entries) = vault::list("", store) {
        for entry in entries {
            if !entry.is_dir && entry.name.ends_with(".md") {
                if let Ok(body) = vault::read_text(&entry.rel_path, store) {
                    let wikilinks = parse_wikilinks(&body);
                    for wl in wikilinks {
                        let target_path = resolve_wikilink(store, &wl.target);
                        state
                            .index
                            .entry(target_path)
                            .or_default()
                            .push(entry.rel_path.clone());
                    }
                }
            }
        }
    }

    state.built.insert(store.to_string());
}

/// Drop a store's backlink index, so it is rebuilt on next use.
pub fn init_backlink_index(store: &str) {
    BACKLINK_INDEX.lock().unwrap().built.remove(store);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_wikilinks() {
        let body = r#"See [[My Note]] and [[Other Note|display text]] here."#;
        let links = parse_wikilinks(body);
        assert_eq!(links.len(), 2);
        assert_eq!(links[0].target, "my-note.md");
        assert_eq!(links[0].display, None);
        assert_eq!(links[1].target, "other-note.md");
        assert_eq!(links[1].display, Some("display text".to_string()));
    }

    #[test]
    fn test_normalize_target() {
        assert_eq!(normalize_target("My Note"), "my-note.md");
        assert_eq!(normalize_target("My_Note"), "my-note.md");
        assert_eq!(normalize_target("  My Note  "), "my-note.md");
        assert_eq!(normalize_target("My Note.md"), "my-note.md");
        assert_eq!(normalize_target("Special!@#Chars"), "specialchars.md");
        assert_eq!(normalize_target("Multiple   Spaces"), "multiple-spaces.md");
    }

    #[test]
    fn test_resolve_wikilink() {
        // Just test normalization since we can't easily test vault
        assert_eq!(resolve_wikilink("", "My Note"), "my-note.md");
    }

    #[test]
    fn test_slugify_folds_names_together() {
        assert_eq!(slugify("My Note.md"), "my-note-md");
        assert_eq!(slugify("my-note.md"), "my-note-md");
        assert_eq!(slugify("My_Note.md"), "my-note-md");
        assert_eq!(slugify("My  Note.md"), "my-note-md");
    }

    /// A note whose name contains a space must still be linkable.
    #[test]
    fn test_resolve_wikilink_across_naming_styles() {
        let _guard = crate::testutil::TestGuard::new();
        let temp = tempfile::tempdir().unwrap();
        let vault_path = temp.path().to_string_lossy().to_string();

        crate::vault::create_with_passphrase(
            &vault_path,
            "testpass123",
            crate::vault::STORE_JOURNAL,
        )
        .unwrap();
        crate::vault::unlock(&vault_path, "testpass123", crate::vault::STORE_JOURNAL).unwrap();

        crate::vault::write_text("My Note.md", "# My Note", crate::vault::STORE_JOURNAL).unwrap();
        crate::vault::write_text("other.md", "# Other", crate::vault::STORE_JOURNAL).unwrap();

        // The exact name resolves.
        assert_eq!(
            resolve_wikilink(crate::vault::STORE_JOURNAL, "My Note.md"),
            "My Note.md"
        );
        // So does the folded form the parser produces.
        assert_eq!(
            resolve_wikilink(crate::vault::STORE_JOURNAL, "my-note.md"),
            "My Note.md"
        );
        // A note that does not exist keeps its normalized target.
        assert_eq!(
            resolve_wikilink(crate::vault::STORE_JOURNAL, "missing note"),
            "missing-note.md"
        );
    }

    #[test]
    fn test_create_missing_makes_a_new_note() {
        let _guard = crate::testutil::TestGuard::new();
        let temp = tempfile::tempdir().unwrap();
        let vault_path = temp.path().to_string_lossy().to_string();

        crate::vault::create_with_passphrase(
            &vault_path,
            "testpass123",
            crate::vault::STORE_JOURNAL,
        )
        .unwrap();
        crate::vault::unlock(&vault_path, "testpass123", crate::vault::STORE_JOURNAL).unwrap();

        // The setting is on by default, so a missing note gets created.
        let created = create_missing(crate::vault::STORE_JOURNAL, "Brand New Note").unwrap();
        assert_eq!(created, "brand-new-note.md");
        assert_eq!(
            crate::vault::read_text("brand-new-note.md", crate::vault::STORE_JOURNAL).unwrap(),
            ""
        );

        // Creating it again is an error.
        assert!(create_missing(crate::vault::STORE_JOURNAL, "Brand New Note").is_err());
    }

    #[test]
    fn test_create_missing_is_honoured_when_off() {
        let _guard = crate::testutil::TestGuard::new();
        let temp = tempfile::tempdir().unwrap();
        let vault_path = temp.path().to_string_lossy().to_string();

        crate::vault::create_with_passphrase(
            &vault_path,
            "testpass123",
            crate::vault::STORE_JOURNAL,
        )
        .unwrap();
        crate::vault::unlock(&vault_path, "testpass123", crate::vault::STORE_JOURNAL).unwrap();

        let mut config = config::get_config();
        config.wikilinks.create_missing = false;
        config::set_config(config);

        assert!(
            create_missing(crate::vault::STORE_JOURNAL, "Brand New Note").is_err(),
            "create_missing is off"
        );
    }
}
