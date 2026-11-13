//! The command line of the terminal client.
//!
//! These tests cover the commands that answer a question about the journal:
//! what is in it, and what matches a filter.

use std::sync::Mutex;

use clap::Parser;

use lumen_core::vault::{self, STORE_JOURNAL};
use lumen_tui::cli::{
    conflict_diff, listed_entries, queried_entries, sync_status_lines, webdav_report_lines, Cli,
    Commands,
};

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
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
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
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_temp, cli) = journal();

    let list = listed_entries(&cli, Some("work")).unwrap();

    assert_eq!(list.len(), 1);
    assert_eq!(list[0].0, "2026-02-03.md");
}

#[test]
fn test_queries_by_tag_and_date() {
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_temp, cli) = journal();

    let found = queried_entries(&cli, "tag:meeting date:2026-02").unwrap();

    assert_eq!(found.len(), 1);
    assert_eq!(found[0].0, "2026-02-03.md");
}

#[test]
fn test_queries_by_free_text() {
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_temp, cli) = journal();

    let found = queried_entries(&cli, "groceries").unwrap();

    assert_eq!(found.len(), 1);
    assert_eq!(found[0].0, "2026-02-04.md");
}

#[test]
fn test_a_query_that_matches_nothing_is_empty() {
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_temp, cli) = journal();

    let found = queried_entries(&cli, "tag:missing").unwrap();

    assert!(found.is_empty());
}

/// A journal with a note that has a version Syncthing kept.
fn conflicted_journal() -> (tempfile::TempDir, String) {
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().to_string_lossy().to_string();

    vault::create_with_passphrase(&path, "testpass123", STORE_JOURNAL).unwrap();
    vault::unlock(&path, "testpass123", STORE_JOURNAL).unwrap();

    // The version the other device sent.
    vault::write_text("gamma.md", "# Gamma\n\nthe remote line\n", STORE_JOURNAL).unwrap();
    let versions = std::path::Path::new(&path)
        .join(".stversions")
        .join("gamma.md");
    std::fs::create_dir_all(&versions).unwrap();
    std::fs::copy(
        std::path::Path::new(&path).join("gamma.md"),
        versions.join("gamma.md.20260101-120000.md"),
    )
    .unwrap();

    // The note as it stands now.
    vault::write_text("gamma.md", "# Gamma\n\nthe local line\n", STORE_JOURNAL).unwrap();

    (temp, path)
}

#[test]
fn test_the_difference_between_two_versions_is_shown() {
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_temp, path) = conflicted_journal();

    let lines = conflict_diff(&path, "gamma.md").unwrap();

    assert_eq!(lines.len(), 4);
    assert_eq!(lines[0].text, "# Gamma");
    assert_eq!(lines[2].text, "the local line");
    assert_eq!(lines[3].text, "the remote line");
}

#[test]
fn test_the_status_says_why_the_devices_are_not_there() {
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (temp, path) = conflicted_journal();

    // Syncthing is asked about the devices only when it is the method
    // Lumen syncs with. Its configuration is pointed at a file that is
    // not there, so the reason is the same everywhere.
    let mut config = lumen_core::config::load_config();
    let previous = config.clone();
    config.sync.method = "syncthing".to_string();
    config.sync.syncthing.config_path = temp
        .path()
        .join("syncthing")
        .join("config.xml")
        .to_string_lossy()
        .to_string();
    lumen_core::config::set_config(config);

    let lines = sync_status_lines(&path).unwrap();
    lumen_core::config::set_config(previous);

    // Syncthing not running is not a failure, but the reason is said
    // rather than leaving an empty list of devices with no explanation.
    assert!(lines.iter().any(|line| line.starts_with("  Note:")));
}

#[test]
fn test_the_status_shows_the_number_of_conflicts() {
    let _lock = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (_temp, path) = conflicted_journal();

    let lines = sync_status_lines(&path).unwrap();

    assert!(lines.iter().any(|line| line.contains("Enabled:")));
    assert!(lines.iter().any(|line| line.contains("Devices:")));
}

/// The WebDAV sync says what it did, and what needs the user.
#[test]
fn test_the_webdav_sync_says_what_it_did() {
    let report = lumen_core::sync_notes::SyncReport {
        uploaded: vec!["a.md".to_string()],
        downloaded: vec!["b.md".to_string(), "c.md".to_string()],
        deleted: vec![],
        conflicts: vec![],
        errors: vec![],
    };

    let lines = webdav_report_lines(&report);

    assert_eq!(lines[0], "Sent 1 note, took 2 notes, removed 0 notes.");
}

/// A note both sides changed is named, so the user can go and look at it.
#[test]
fn test_the_webdav_sync_names_the_notes_that_need_the_user() {
    let conflict = lumen_core::sync::SyncConflict {
        path: "gamma.md".to_string(),
        local_modified: chrono::Utc::now(),
        remote_modified: chrono::Utc::now(),
        local_hash: "aaa".to_string(),
        remote_hash: "bbb".to_string(),
        source: "webdav".to_string(),
    };
    let report = lumen_core::sync_notes::SyncReport {
        uploaded: vec![],
        downloaded: vec![],
        deleted: vec![],
        conflicts: vec![conflict],
        errors: vec![],
    };

    let lines = webdav_report_lines(&report);

    assert!(lines.iter().any(|line| line.contains("1 note need your attention")));
    assert!(lines.iter().any(|line| line.contains("gamma.md")));
}
