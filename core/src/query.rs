//! A small query language over the notes in a vault.
//!
//! A query is a list of terms, and every term has to match:
//!
//! ```text
//! tag:work project:lumen date:2026-02 meeting
//! ```
//!
//! - `tag:<value>` — the note carries the tag.
//! - `date:<value>` — the note's date starts with the value, so `date:2026-02`
//!   matches every note in February 2026.
//! - `<key>:<value>` — a frontmatter field equals the value. `title:` and
//!   `aliases:` are understood as well as the note's own fields.
//! - anything else — free text, matched against the note's title and body.
//!
//! The language is deliberately small: it covers the filters the notes carry
//! themselves, and leaves full-text search to the search index.

use std::collections::HashMap;

use chrono::NaiveDate;

use crate::frontmatter::{self, Frontmatter};
use crate::vault;

/// One term of a query.
#[derive(Debug, Clone, PartialEq)]
pub enum Term {
    /// `tag:value` — the note carries this tag.
    Tag(String),
    /// `date:value` — the note's date starts with this.
    Date(String),
    /// `key:value` — a frontmatter field equals this.
    Field(String, String),
    /// Free text, matched against the title and the body.
    Text(String),
}

/// A parsed query.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Query {
    /// The terms, in the order they were written.
    pub terms: Vec<Term>,
}

impl Query {
    /// Whether the query has no terms at all.
    pub fn is_empty(&self) -> bool {
        self.terms.is_empty()
    }

    /// Whether the query asks for anything but free text.
    ///
    /// A full-text index can answer plain words, but only the notes
    /// themselves know what tags and fields they carry.
    pub fn has_filters(&self) -> bool {
        self.terms.iter().any(|term| !matches!(term, Term::Text(_)))
    }
}

/// Whether the part before a colon names a field.
///
/// A field name is a plain word, so `https://example.com` stays free text
/// rather than becoming a filter on a field called `https`.
fn is_field(key: &str) -> bool {
    !key.is_empty()
        && key
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

/// Whether the part after a colon can be a field's value.
///
/// A value may not start with a slash, which is what tells `https://…` apart
/// from `tag:work`.
fn is_field_value(value: &str) -> bool {
    !value.is_empty() && !value.starts_with('/')
}

/// Parse a query string into its terms.
///
/// A term that carries a colon is a filter, unless the part before the colon
/// is empty — `https://example.com` is free text, not a field named `https`.
pub fn parse(query: &str) -> Query {
    let mut terms = Vec::new();

    for word in query.split_whitespace() {
        let term = match word.split_once(':') {
            Some((key, value)) if is_field(key) && is_field_value(value) => {
                match key.to_ascii_lowercase().as_str() {
                    "tag" | "tags" => Term::Tag(value.to_string()),
                    "date" => Term::Date(value.to_string()),
                    _ => Term::Field(key.to_string(), value.to_string()),
                }
            }
            _ => Term::Text(word.to_string()),
        };
        terms.push(term);
    }

    Query { terms }
}

/// The note's date: the one in its frontmatter, or the one in its filename.
fn note_date(path: &str, fm: &Frontmatter) -> Option<NaiveDate> {
    if let Some(date) = fm.date {
        return Some(date);
    }

    let stem = path
        .rsplit('/')
        .next()
        .unwrap_or(path)
        .trim_end_matches(".md")
        .trim_end_matches(".markdown");
    NaiveDate::parse_from_str(stem.get(..10)?, "%Y-%m-%d").ok()
}

/// The note's title: the one in its frontmatter, or its first heading.
fn note_title(path: &str, body: &str, fm: &Frontmatter) -> String {
    if let Some(title) = &fm.title {
        return title.clone();
    }
    for line in body.lines() {
        if let Some(rest) = line.trim().strip_prefix("# ") {
            let title = rest.trim();
            if !title.is_empty() {
                return title.to_string();
            }
        }
    }
    path.rsplit('/')
        .next()
        .unwrap_or(path)
        .trim_end_matches(".md")
        .trim_end_matches(".markdown")
        .to_string()
}

/// Whether a frontmatter field equals `value`.
///
/// A field may hold a single value or a list of them, and the comparison
/// ignores case — the same way a tag filter does.
fn field_equals(fm: &Frontmatter, key: &str, value: &str) -> bool {
    let wanted = value.trim();
    let matches = |found: &str| found.trim().eq_ignore_ascii_case(wanted);

    match key.to_ascii_lowercase().as_str() {
        "title" => fm.title.as_deref().map(matches).unwrap_or(false),
        "alias" | "aliases" => fm.aliases.iter().any(|a| matches(a)),
        _ => match fm.custom.get(key) {
            Some(serde_json::Value::String(s)) => matches(s),
            Some(serde_json::Value::Array(items)) => items
                .iter()
                .any(|item| item.as_str().map(matches).unwrap_or(false)),
            Some(other) => other.to_string().eq_ignore_ascii_case(wanted),
            None => false,
        },
    }
}

/// Whether a note matches every term of a query.
pub fn matches(path: &str, body: &str, fm: &Frontmatter, query: &Query) -> bool {
    if query.terms.is_empty() {
        return false;
    }

    let title = note_title(path, body, fm);
    let haystack = format!("{title}\n{body}").to_lowercase();

    query.terms.iter().all(|term| match term {
        Term::Tag(tag) => fm.tags.iter().any(|t| t.eq_ignore_ascii_case(tag.trim())),
        Term::Date(value) => note_date(path, fm)
            .map(|date| {
                date.format("%Y-%m-%d")
                    .to_string()
                    .starts_with(value.trim())
            })
            .unwrap_or(false),
        Term::Field(key, value) => field_equals(fm, key, value),
        Term::Text(text) => haystack.contains(&text.to_lowercase()),
    })
}

/// The notes matching a query.
///
/// The vault is scanned rather than searched through the index: a query
/// filters on the metadata the note carries, and the metadata has to be read
/// to be compared.
pub fn query_entries(store: &str, query: &Query) -> crate::Result<Vec<String>> {
    let mut results = Vec::new();

    for entry in vault::list("", store)? {
        if entry.is_dir || !entry.name.ends_with(".md") {
            continue;
        }
        let body = match vault::read_text(&entry.rel_path, store) {
            Ok(b) => b,
            Err(_) => continue,
        };
        let (fm, _) = frontmatter::parse_frontmatter(&body);
        if matches(&entry.rel_path, &body, &fm, query) {
            results.push(entry.rel_path);
        }
    }

    Ok(results)
}

/// The notes matching a query string.
pub fn query(store: &str, query: &str) -> crate::Result<Vec<String>> {
    query_entries(store, &parse(query))
}

/// Every tag used in the vault, with how many notes carry it.
pub fn tag_counts(store: &str) -> crate::Result<HashMap<String, usize>> {
    let mut counts: HashMap<String, usize> = HashMap::new();

    for entry in vault::list("", store)? {
        if entry.is_dir || !entry.name.ends_with(".md") {
            continue;
        }
        let body = match vault::read_text(&entry.rel_path, store) {
            Ok(b) => b,
            Err(_) => continue,
        };
        let (fm, _) = frontmatter::parse_frontmatter(&body);
        for tag in fm.tags {
            *counts.entry(tag).or_insert(0) += 1;
        }
    }

    Ok(counts)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fm_with_tags(tags: &[&str]) -> Frontmatter {
        Frontmatter {
            tags: tags.iter().map(|t| t.to_string()).collect(),
            ..Frontmatter::default()
        }
    }

    #[test]
    fn test_parse_splits_filters_from_text() {
        let query = parse("tag:work project:lumen meeting");

        assert_eq!(
            query.terms,
            vec![
                Term::Tag("work".into()),
                Term::Field("project".into(), "lumen".into()),
                Term::Text("meeting".into()),
            ]
        );
    }

    #[test]
    fn test_parse_keeps_a_url_as_text() {
        let query = parse("https://example.com");

        assert_eq!(query.terms, vec![Term::Text("https://example.com".into())]);
    }

    #[test]
    fn test_parse_treats_tags_and_date_as_filters() {
        let query = parse("tags:work date:2026-02");

        assert_eq!(
            query.terms,
            vec![Term::Tag("work".into()), Term::Date("2026-02".into())]
        );
    }

    #[test]
    fn test_matches_a_tag() {
        let fm = fm_with_tags(&["work"]);
        let query = parse("tag:work");

        assert!(matches("a.md", "# A", &fm, &query));
        assert!(!matches("a.md", "# A", &fm, &parse("tag:home")));
    }

    #[test]
    fn test_matches_a_custom_field() {
        let mut fm = Frontmatter::default();
        fm.set_string("project".into(), "lumen".into());
        let query = parse("project:lumen");

        assert!(matches("a.md", "# A", &fm, &query));
        // The comparison ignores case.
        assert!(matches("a.md", "# A", &fm, &parse("project:Lumen")));
        assert!(!matches("a.md", "# A", &fm, &parse("project:other")));
    }

    #[test]
    fn test_matches_a_date_from_the_filename() {
        let query = parse("date:2026-02");

        assert!(matches(
            "2026-02-03.md",
            "# A",
            &Frontmatter::default(),
            &query
        ));
        assert!(!matches(
            "2026-03-03.md",
            "# A",
            &Frontmatter::default(),
            &query
        ));
    }

    #[test]
    fn test_matches_free_text_against_the_title_and_body() {
        let query = parse("meeting");

        assert!(matches(
            "a.md",
            "# The meeting\n\nnotes",
            &Frontmatter::default(),
            &query
        ));
        assert!(!matches(
            "a.md",
            "# Agenda\n\nnotes",
            &Frontmatter::default(),
            &query
        ));
    }

    #[test]
    fn test_every_term_has_to_match() {
        let mut fm = fm_with_tags(&["work"]);
        fm.set_string("project".into(), "lumen".into());

        assert!(matches(
            "a.md",
            "# Notes",
            &fm,
            &parse("tag:work project:lumen")
        ));
        assert!(!matches(
            "a.md",
            "# Notes",
            &fm,
            &parse("tag:work project:other")
        ));
    }

    #[test]
    fn test_an_empty_query_matches_nothing() {
        assert!(!matches("a.md", "# A", &Frontmatter::default(), &parse("")));
    }

    #[test]
    fn test_has_filters() {
        assert!(!parse("meeting").has_filters());
        assert!(parse("tag:work").has_filters());
        assert!(parse("meeting tag:work").has_filters());
        assert!(parse("").terms.is_empty());
    }
}
