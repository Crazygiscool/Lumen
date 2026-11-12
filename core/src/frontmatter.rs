//! YAML frontmatter parsing and serialization.

use std::collections::HashMap;

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use serde_yaml;

/// Frontmatter metadata for a journal entry.
#[derive(Debug, Default, Clone, Serialize, Deserialize, PartialEq)]
pub struct Frontmatter {
    /// Tags for categorization.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tags: Vec<String>,

    /// Alternative titles/aliases for wikilink resolution.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub aliases: Vec<String>,

    /// Explicit title (overrides first heading).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,

    /// Entry date (overrides filename date).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub date: Option<NaiveDate>,

    /// CSS class for styling.
    #[serde(rename = "cssclass", skip_serializing_if = "Option::is_none")]
    pub css_class: Option<String>,

    /// Custom fields (arbitrary key-value).
    #[serde(flatten)]
    pub custom: HashMap<String, serde_json::Value>,
}

impl Frontmatter {
    /// Create empty frontmatter.
    pub fn new() -> Self {
        Self::default()
    }

    /// Get a custom field as string.
    pub fn get_string(&self, key: &str) -> Option<String> {
        self.custom.get(key).and_then(|v| v.as_str().map(|s| s.to_string()))
    }

    /// Set a custom field.
    pub fn set_string(&mut self, key: String, value: String) {
        self.custom.insert(key, serde_json::Value::String(value));
    }

    /// Remove a custom field.
    pub fn remove(&mut self, key: &str) {
        self.custom.remove(key);
    }

    /// Check if frontmatter has any content.
    pub fn is_empty(&self) -> bool {
        self.tags.is_empty()
            && self.aliases.is_empty()
            && self.title.is_none()
            && self.date.is_none()
            && self.css_class.is_none()
            && self.custom.is_empty()
    }
}

/// Parse frontmatter from a markdown body.
/// Returns (frontmatter, body_without_frontmatter).
pub fn parse_frontmatter(body: &str) -> (Frontmatter, String) {
    let trimmed = body.trim_start();
    if !trimmed.starts_with("---") {
        return (Frontmatter::default(), body.to_string());
    }

    // The opening delimiter has to be a line of its own, otherwise a body
    // that merely starts with three dashes is mistaken for frontmatter.
    let after_open = &trimmed[3..];
    if !(after_open.is_empty() || after_open.starts_with('\n') || after_open.starts_with("\r\n")) {
        return (Frontmatter::default(), body.to_string());
    }

    // Find the closing delimiter, which also has to be a line of its own.
    let mut yaml_end = None;
    let mut body_start = None;
    let mut offset = 0usize;
    for line in after_open.split_inclusive('\n') {
        if line.trim_end().trim_end_matches('\r') == "---" {
            yaml_end = Some(offset);
            body_start = Some(offset + line.len());
            break;
        }
        offset += line.len();
    }

    let (yaml_end, body_start) = match (yaml_end, body_start) {
        (Some(y), Some(b)) => (y, b),
        _ => return (Frontmatter::default(), body.to_string()),
    };

    let yaml_str = &after_open[..yaml_end];
    let body_after = &after_open[body_start..];

    match serde_yaml::from_str::<Frontmatter>(yaml_str) {
        Ok(fm) => (fm, body_after.trim_start().to_string()),
        // The block is malformed, so there are no tags to report — but the
        // body is still returned without it, so a rewrite does not end up
        // with two frontmatter blocks.
        Err(_) => (Frontmatter::default(), body_after.trim_start().to_string()),
    }
}

/// Serialize frontmatter and prepend to body.
pub fn serialize_frontmatter(fm: &Frontmatter, body: &str) -> String {
    if fm.is_empty() {
        return body.to_string();
    }

    let yaml = serde_yaml::to_string(fm).unwrap_or_default();
    // The closing delimiter needs its own line, so the trailing newline of
    // the YAML block is replaced rather than dropped.
    format!("---\n{}\n---\n{}", yaml.trim_end(), body.trim_start())
}

/// Extract frontmatter from a vault entry path.
pub fn read_frontmatter(store: &str, path: &str) -> crate::Result<Frontmatter> {
    let body = crate::vault::read_text(path, store)?;
    let (fm, _) = parse_frontmatter(&body);
    Ok(fm)
}

/// Update frontmatter for a vault entry (preserves body).
pub fn write_frontmatter(store: &str, path: &str, fm: &Frontmatter) -> crate::Result<()> {
    let body = crate::vault::read_text(path, store)?;
    let (_, body_without_fm) = parse_frontmatter(&body);
    let new_body = serialize_frontmatter(fm, &body_without_fm);
    crate::vault::write_text(path, &new_body, store)
}

/// The frontmatter as YAML.
///
/// This is the form the metadata is edited in, so the YAML is produced here
/// rather than in every client that offers an editor for it.
pub fn frontmatter_to_yaml(fm: &Frontmatter) -> String {
    serde_yaml::to_string(fm).unwrap_or_default()
}

/// Read frontmatter from YAML.
///
/// The error is the YAML parser's, so a user who mistyped a line is told
/// what is wrong with it.
pub fn frontmatter_from_yaml(yaml: &str) -> crate::Result<Frontmatter> {
    serde_yaml::from_str::<Frontmatter>(yaml).map_err(|e| e.to_string())
}

/// Query entries by frontmatter filter.
pub fn query_entries(
    store: &str,
    tag: Option<&str>,
    custom_key: Option<&str>,
    custom_value: Option<&str>,
) -> crate::Result<Vec<String>> {
    let mut results = Vec::new();

    let entries = crate::vault::list("", store)?;
    for entry in entries {
        if entry.is_dir || !entry.name.ends_with(".md") {
            continue;
        }

        let (fm, _) = parse_frontmatter(&crate::vault::read_text(&entry.rel_path, store)?);

        // Tag filter
        if let Some(tag) = tag {
            if !fm.tags.iter().any(|t| t.eq_ignore_ascii_case(tag)) {
                continue;
            }
        }

        // Custom field filter
        if let (Some(key), Some(value)) = (custom_key, custom_value) {
            if fm.custom.get(key) != Some(&serde_json::Value::String(value.to_string())) {
                continue;
            }
        }

        results.push(entry.rel_path);
    }

    Ok(results)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_frontmatter() {
        let body = r#"---
tags: [work, meeting]
aliases: ["Weekly Sync"]
title: "Team Meeting"
date: 2026-02-03
custom_field: "value"
---

# Meeting Notes

Body content."#;

        let (fm, remaining) = parse_frontmatter(body);
        assert_eq!(fm.tags, vec!["work", "meeting"]);
        assert_eq!(fm.aliases, vec!["Weekly Sync"]);
        assert_eq!(fm.title, Some("Team Meeting".to_string()));
        assert_eq!(fm.date, Some(NaiveDate::from_ymd_opt(2026, 2, 3).unwrap()));
        assert_eq!(fm.get_string("custom_field"), Some("value".to_string()));
        assert!(remaining.starts_with("# Meeting Notes"));
    }

    #[test]
    fn test_parse_no_frontmatter() {
        let body = "# Just a heading\n\nNo frontmatter here.";
        let (fm, remaining) = parse_frontmatter(body);
        assert!(fm.is_empty());
        assert_eq!(remaining, body);
    }

    #[test]
    fn test_serialize_frontmatter() {
        let mut fm = Frontmatter::new();
        fm.tags = vec!["tag1".to_string(), "tag2".to_string()];
        fm.title = Some("Test".to_string());
        fm.set_string("key".to_string(), "value".to_string());

        let body = "# Content\n\nBody.";
        let result = serialize_frontmatter(&fm, body);

        assert!(result.starts_with("---\n"));
        assert!(result.contains("tags:"));
        assert!(result.contains("tag1"));
        assert!(result.contains("key: value"));
        assert!(result.ends_with("# Content\n\nBody."));
    }

    #[test]
    fn test_serialize_empty_frontmatter() {
        let fm = Frontmatter::new();
        let body = "# Content";
        let result = serialize_frontmatter(&fm, body);
        assert_eq!(result, body);
    }

    /// The serialized block must be parseable again — the closing delimiter
    /// needs its own line, or the block cannot be read back.
    #[test]
    fn test_serialize_round_trips() {
        let mut fm = Frontmatter::new();
        fm.tags = vec!["work".to_string(), "urgent".to_string()];
        fm.title = Some("Beta".to_string());

        let body = "# Beta\n\nThe second note.";
        let serialized = serialize_frontmatter(&fm, body);

        let (parsed, remaining) = parse_frontmatter(&serialized);
        assert_eq!(parsed.tags, fm.tags);
        assert_eq!(parsed.title, fm.title);
        assert_eq!(remaining, body);
    }

    /// A frontmatter block that was written back must keep its tags.
    #[test]
    fn test_parse_multiline_yaml_block() {
        let body = "---\ntags:\n- work\n- urgent\ntitle: Beta\n---\n# Beta\n\nBody.";

        let (fm, remaining) = parse_frontmatter(body);
        assert_eq!(fm.tags, vec!["work", "urgent"]);
        assert_eq!(fm.title.as_deref(), Some("Beta"));
        assert_eq!(remaining, "# Beta\n\nBody.");
    }

    /// A body that merely starts with three dashes is not frontmatter.
    #[test]
    fn test_parse_ignores_non_delimiter_dashes() {
        let body = "--- not frontmatter\n\nBody.";

        let (fm, remaining) = parse_frontmatter(body);
        assert!(fm.is_empty());
        assert_eq!(remaining, body);
    }

    /// A malformed block is stripped rather than duplicated on rewrite.
    #[test]
    fn test_parse_malformed_block_is_stripped() {
        let body = "---\ntags: [work\n---\n# Body.";

        let (fm, remaining) = parse_frontmatter(body);
        assert!(fm.is_empty());
        assert_eq!(remaining, "# Body.");
    }

    /// The YAML form has to survive a round trip, or an editor that works on
    /// YAML would quietly lose the metadata.
    #[test]
    fn test_yaml_round_trips() {
        let mut fm = Frontmatter::new();
        fm.tags = vec!["work".to_string(), "urgent".to_string()];
        fm.title = Some("Beta".to_string());
        fm.set_string("project".into(), "lumen".into());

        let yaml = frontmatter_to_yaml(&fm);
        let parsed = frontmatter_from_yaml(&yaml).unwrap();

        assert_eq!(parsed.tags, fm.tags);
        assert_eq!(parsed.title, fm.title);
        assert_eq!(parsed.get_string("project").as_deref(), Some("lumen"));
    }

    /// YAML written by hand has to be understood as well.
    #[test]
    fn test_yaml_is_read_back() {
        let yaml = "tags:\n  - work\n  - urgent\ntitle: Beta\nproject: lumen\n";

        let fm = frontmatter_from_yaml(yaml).unwrap();

        assert_eq!(fm.tags, vec!["work", "urgent"]);
        assert_eq!(fm.title.as_deref(), Some("Beta"));
        assert_eq!(fm.get_string("project").as_deref(), Some("lumen"));
    }

    /// An empty document is empty metadata, not an error.
    #[test]
    fn test_empty_yaml_is_empty_frontmatter() {
        let fm = frontmatter_from_yaml("").unwrap();
        assert!(fm.is_empty());
    }

    /// Broken YAML has to say so, rather than quietly emptying the metadata.
    #[test]
    fn test_broken_yaml_is_an_error() {
        assert!(frontmatter_from_yaml("tags: [work\n").is_err());
    }
}
