//! Wikilink parsing and backlink index.
//!
//! Supports `[[note name]]` and `[[note name|display text]]` syntax.

use std::collections::{HashMap, HashSet};
use std::ops::Range;
use std::sync::Mutex;

use lazy_static::lazy_static;
use regex::Regex;

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
    s = s.chars().filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '.').collect();
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
        for entry in entries {
            if !entry.is_dir && entry.name.to_lowercase() == target_lower {
                return entry.rel_path;
            }
        }
    }
    normalized
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
}