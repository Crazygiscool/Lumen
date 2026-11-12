//! The command line of the terminal client.
//!
//! These tests cover the commands that answer a question about the journal:
//! what is in it, and what matches a filter.

use std::sync::Mutex;

use clap::Parser;

use lumen_core::vault::{self, STORE_JOURNAL};
use lumen_tui::cli::{listed_entries, queried_entries, Cli, Commands};

/// The vault registry is process-global, so the tests that touch it take
/// turns.
static LOCK: Mutex<()> = Mutex::new(());

/// A journal with three notes: one tagged `work`, one tagged `home`, and one
/// with no tags at all.
fn journal() -> (tempfile::TempDir, Cli) {
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().to_string_lossy().to_string();

    vault::create_with_passphrase(&path, "testpass123", STORE_JOURNAL).unwrap();
    vault::unlock(&path, "testpass123", STORE_JOURNAL).unwrap();

    vault::write_text(
        "2026-02-03.md",
        "---\ntags: [work, meeting]\n---\n\n# Team meeting\n\nThe notes.",
        STORE_JOURNAL,
    )
    .unwrap();
    vault::write_text(
        "2026-02-04.md",
        "---\ntags: [home]\n---\n\n# Groceries\n\nMilk.",
        STORE_JOURNAL,
    )
    .unwrap();
    vault::write_text(
        "2026-01-01.md",
        "# Plain note\n\nNo metadata.",
        STORE_JOURNAL,
    )
    .unwrap();

    let cli = Cli::try_parse_from([
        "lumen",
        "--vault",
        &path,
        "--password",
        "testpass123",
        "list",
    ])
    .unwrap();

    (temp, cli)
}

#[test]
fn test_parses_a_tag_filter() {
    let cli = Cli::try_parse_from(["lumen", "list", "--tag", "work"]).unwrap();

    match cli.command {
        Some(Commands::List { tag }) => assert_eq!(tag.as_deref(), Some("work")),
        other => panic!("expected a list command, got {other:?}"),
    }
}

#[test]
fn test_parses_a_query() {
    let cli = Cli::try_parse_from(["lumen", "query", "tag:meeting date:2026-02"]).unwrap();

    match cli.command {
        Some(Commands::Query { query }) => {
            assert_eq!(query, "tag:meeting date:2026-02")
        }
        other => panic!("expected a query command, got {other:?}"),
    }
}

#[test]
fn test_parses_a_daily_date() {
    let cli = Cli::try_parse_from(["lumen", "daily", "2026-02-03"]).unwrap();

    match cli.command {
        Some(Commands::Daily { date }) => assert_eq!(date.as_deref(), Some("2026-02-03")),
        other => panic!("expected a daily command, got {other:?}"),
    }
}

#[test]
fn test_lists_every_note() {
    let _lock = LOCK.lock().unwrap();
    let (_temp, cli) = journal();

    let list = listed_entries(&cli, None).unwrap();

    // Newest first.
    let paths: Vec<&str> = list.iter().map(|(path, _)| path.as_str()).collect();
    assert_eq!(
        paths,
        vec!["2026-02-04.md", "2026-02-03.md", "2026-01-01.md"]
    );
    assert_eq!(list[1].1, "Team meeting");
}

#[test]
fn test_lists_only_the_tagged_notes() {
    let _lock = LOCK.lock().unwrap();
    let (_temp, cli) = journal();

    let list = listed_entries(&cli, Some("work")).unwrap();

    assert_eq!(list.len(), 1);
    assert_eq!(list[0].0, "2026-02-03.md");
}

#[test]
fn test_queries_by_tag_and_date() {
    let _lock = LOCK.lock().unwrap();
    let (_temp, cli) = journal();

    let found = queried_entries(&cli, "tag:meeting date:2026-02").unwrap();

    assert_eq!(found.len(), 1);
    assert_eq!(found[0].0, "2026-02-03.md");
}

#[test]
fn test_queries_by_free_text() {
    let _lock = LOCK.lock().unwrap();
    let (_temp, cli) = journal();

    let found = queried_entries(&cli, "groceries").unwrap();

    assert_eq!(found.len(), 1);
    assert_eq!(found[0].0, "2026-02-04.md");
}

#[test]
fn test_a_query_that_matches_nothing_is_empty() {
    let _lock = LOCK.lock().unwrap();
    let (_temp, cli) = journal();

    let found = queried_entries(&cli, "tag:missing").unwrap();

    assert!(found.is_empty());
}
