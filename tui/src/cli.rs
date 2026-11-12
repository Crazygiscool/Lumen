//! The command line of the Lumen terminal client.
//!
//! These commands are the non-interactive half of the client: they print or
//! edit a note and then get out of the way. The interactive half lives in
//! [`crate::app`].

use std::collections::BTreeSet;
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::Command;

use chrono::{Duration, Local, NaiveDate};
use clap::{Parser, Subcommand};
use termimad::MadSkin;

use lumen_core::config;
use lumen_core::diff::DiffLine;
use lumen_core::query;
use lumen_core::search;
use lumen_core::template;
use lumen_core::vault::{self, STORE_JOURNAL};
use lumen_core::wikilinks;

use crate::app;

#[derive(Parser)]
#[command(author, version, about = "Lumen journal (terminal)", long_about = None)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Commands>,

    /// Folder holding the encrypted journal (.lumen/journal.json).
    #[arg(short, long, value_name = "DIR", env = "LUMEN_JOURNAL", global = true)]
    pub vault: Option<PathBuf>,

    /// Journal passphrase. Prefer the LUMEN_PASSWORD environment variable or
    /// the interactive prompt.
    #[arg(
        short,
        long,
        env = "LUMEN_PASSWORD",
        hide_env_values = true,
        global = true
    )]
    pub password: Option<String>,
}

#[derive(Subcommand, Debug)]
pub enum Commands {
    /// Create the encrypted journal at --vault.
    Init,
    /// List journal entries (newest first).
    List {
        /// Only entries carrying this tag.
        #[arg(long, value_name = "TAG")]
        tag: Option<String>,
    },
    /// Full-text search across the journal.
    Search { query: String },
    /// Filter the journal with the query language.
    ///
    /// The terms are ANDed, so `tag:meeting date:2026-02` lists the meetings
    /// of February 2026.
    Query { query: String },
    /// Print a single Markdown entry.
    View { path: String },
    /// Create (or open) today's entry in $EDITOR.
    Today,
    /// Open (or create) the daily note for a date.
    Daily {
        /// The date of the note (YYYY-MM-DD). Defaults to today.
        date: Option<String>,
    },
    /// Show the daily note template.
    DailyTemplate,
    /// List the notes that link to an entry.
    Backlinks { path: String },
    /// Edit an entry in $EDITOR.
    Edit { path: String },
    /// Consecutive days written, counting back from today.
    Streak,
    /// Sync management.
    Sync {
        #[command(subcommand)]
        command: SyncCommands,
    },
}

#[derive(Subcommand, Debug)]
pub enum SyncCommands {
    /// Show sync status.
    Status,
    /// List detected conflicts.
    Conflicts {
        /// Show what changed between the two versions of each conflict.
        #[arg(long)]
        diff: bool,
    },
    /// Resolve a conflict.
    Resolve {
        /// Path of the conflicted file.
        path: String,
        /// Keep local version (default: remote).
        #[arg(long)]
        keep_local: bool,
    },
    /// Generate Syncthing folder configuration XML.
    GenSyncthingConfig,
    /// Create encrypted backup bundle.
    BackupCreate {
        /// Output path for the backup bundle.
        output: String,
        /// Passphrase for backup encryption.
        #[arg(short, long)]
        passphrase: Option<String>,
    },
    /// Restore encrypted backup bundle.
    BackupRestore {
        /// Path to the backup bundle.
        bundle: String,
        /// Target directory to restore to.
        target: String,
        /// Passphrase for backup decryption.
        #[arg(short, long)]
        passphrase: Option<String>,
    },
}

/// Run the client with the parsed command line.
pub fn run(cli: Cli) -> color_eyre::Result<()> {
    match &cli.command {
        None => {
            unlock(&cli)?;
            app::run_tui()
        }
        Some(Commands::Init) => cmd_init(&cli),
        Some(Commands::List { tag }) => cmd_list(&cli, tag.as_deref()),
        Some(Commands::Search { query }) => cmd_search(&cli, query),
        Some(Commands::Query { query }) => cmd_query(&cli, query),
        Some(Commands::View { path }) => cmd_view(&cli, path),
        Some(Commands::Today) => cmd_today(&cli),
        Some(Commands::Daily { date }) => cmd_daily(&cli, date.as_deref()),
        Some(Commands::DailyTemplate) => cmd_daily_template(&cli),
        Some(Commands::Backlinks { path }) => cmd_backlinks(&cli, path),
        Some(Commands::Edit { path }) => cmd_writer(&cli, path),
        Some(Commands::Streak) => cmd_streak(&cli),
        Some(Commands::Sync { command }) => cmd_sync(&cli, command),
    }
}

fn default_vault() -> PathBuf {
    dirs::document_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("lumen-journal")
}

#[cfg(not(unix))]
fn prompt_password() -> String {
    print!("Passphrase: ");
    let _ = io::stdout().flush();
    let mut line = String::new();
    let _ = io::stdin().read_line(&mut line);
    line.trim_end_matches(['\r', '\n']).to_string()
}

/// Prompts for a passphrase with terminal echo disabled when possible.
fn prompt_password_hidden() -> String {
    #[cfg(unix)]
    {
        // `stty` is portable across Linux and macOS and avoids hand-rolling
        // platform-specific termios layouts. The guard restores echo on early
        // returns and I/O errors.
        struct EchoGuard(bool);
        impl Drop for EchoGuard {
            fn drop(&mut self) {
                if self.0 {
                    let _ = Command::new("stty").arg("echo").status();
                }
            }
        }

        let hidden = Command::new("stty").arg("-echo").status().is_ok();
        let _guard = EchoGuard(hidden);
        print!("Passphrase: ");
        let _ = io::stdout().flush();
        let line = {
            let mut line = String::new();
            let _ = io::stdin().read_line(&mut line);
            line
        };
        println!();
        line.trim_end_matches(['\r', '\n']).to_string()
    }
    #[cfg(not(unix))]
    {
        prompt_password()
    }
}

fn unlock(cli: &Cli) -> color_eyre::Result<PathBuf> {
    let root = cli.vault.clone().unwrap_or_else(default_vault);
    if !vault::exists_store(&root.to_string_lossy(), STORE_JOURNAL) {
        color_eyre::eyre::bail!(
            "no journal at {}\nRun `lumen init --vault {}` or create it in the app.",
            root.display(),
            root.display()
        );
    }
    let password = cli.password.clone().unwrap_or_else(prompt_password_hidden);
    vault::unlock(&root.to_string_lossy(), &password, STORE_JOURNAL)
        .map_err(|e| color_eyre::eyre::eyre!(e))?;
    Ok(root)
}

fn is_markdown(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    lower.ends_with(".md") || lower.ends_with(".markdown")
}

/// The notes in the journal, newest first.
pub fn entries() -> color_eyre::Result<Vec<vault::VaultEntry>> {
    let mut list: Vec<vault::VaultEntry> = vault::list("", STORE_JOURNAL)
        .map_err(|e| color_eyre::eyre::eyre!(e))?
        .into_iter()
        .filter(|e| !e.is_dir && is_markdown(&e.name))
        .collect();
    // Newest first; filenames are date-prefixed for entries created by Lumen.
    list.sort_by(|a, b| b.rel_path.cmp(&a.rel_path));
    Ok(list)
}

/// The title of a note: its first heading, or its filename.
pub fn title_of(body: &str, fallback: &str) -> String {
    for line in body.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("# ") {
            if !rest.trim().is_empty() {
                return rest.trim().to_string();
            }
        }
    }
    fallback.trim_end_matches(".md").to_string()
}

/// Read a note from the journal.
pub fn read_entry(path: &str) -> color_eyre::Result<String> {
    vault::read_text(path, STORE_JOURNAL).map_err(|e| color_eyre::eyre::eyre!(e))
}

fn shell_temp_path(name: &str) -> PathBuf {
    std::env::temp_dir().join(format!("lumen-{}-{}", std::process::id(), name))
}

/// Edit some text in `$EDITOR`.
///
/// The editor is given the file name it is given, so the editor can pick its
/// syntax highlighting from the extension. `None` means the editor was left
/// without saving.
pub fn edit_in_editor(initial: &str, name: &str) -> color_eyre::Result<Option<String>> {
    let editor = std::env::var("EDITOR")
        .or_else(|_| std::env::var("VISUAL"))
        .unwrap_or_else(|_| "vi".to_string());
    let path = shell_temp_path(name);
    std::fs::write(&path, initial)?;
    let status = Command::new("sh")
        .arg("-c")
        .arg(format!("{} \"$1\"", editor))
        .arg("sh")
        .arg(&path)
        .status()?;
    let result = if status.success() {
        Some(std::fs::read_to_string(&path)?)
    } else {
        None
    };
    let _ = std::fs::remove_file(&path);
    Ok(result)
}

fn cmd_init(cli: &Cli) -> color_eyre::Result<()> {
    let root = cli.vault.clone().unwrap_or_else(default_vault);
    let root_str = root.to_string_lossy().to_string();
    if vault::exists_store(&root_str, STORE_JOURNAL) {
        println!("Journal already exists at {}", root.display());
        return Ok(());
    }
    let pass = cli.password.clone().unwrap_or_else(prompt_password_hidden);
    if pass.len() < 8 {
        color_eyre::eyre::bail!("passphrase must be at least 8 characters");
    }
    vault::create_with_passphrase(&root_str, &pass, STORE_JOURNAL)
        .map_err(|e| color_eyre::eyre::eyre!(e))?;
    vault::unlock(&root_str, &pass, STORE_JOURNAL).map_err(|e| color_eyre::eyre::eyre!(e))?;
    println!("Created journal at {}", root.display());
    Ok(())
}

fn cmd_list(cli: &Cli, tag: Option<&str>) -> color_eyre::Result<()> {
    let list = listed_entries(cli, tag)?;
    if list.is_empty() {
        match tag {
            Some(tag) => println!("No entries tagged {tag:?}."),
            None => println!("No entries yet. Press `n` in the TUI, or use `lumen today`."),
        }
        return Ok(());
    }
    for (path, title) in list {
        println!("{:<20}  {}", path, title);
    }
    Ok(())
}

/// The entries `lumen list` shows: their path and their title.
///
/// The list is newest first, and a tag filter narrows it down to the notes
/// that carry the tag.
pub fn listed_entries(cli: &Cli, tag: Option<&str>) -> color_eyre::Result<Vec<(String, String)>> {
    unlock(cli)?;
    let list = entries()?;
    let list = match tag {
        Some(tag) => {
            let tagged: BTreeSet<String> = query::query(STORE_JOURNAL, &format!("tag:{tag}"))
                .map_err(|e| color_eyre::eyre::eyre!(e))?
                .into_iter()
                .collect();
            list.into_iter()
                .filter(|e| tagged.contains(&e.rel_path))
                .collect()
        }
        None => list,
    };

    Ok(list
        .into_iter()
        .map(|e| {
            let title = read_entry(&e.rel_path)
                .map(|b| title_of(&b, &e.name))
                .unwrap_or_else(|_| e.name.clone());
            (e.rel_path, title)
        })
        .collect())
}

fn cmd_search(cli: &Cli, text: &str) -> color_eyre::Result<()> {
    unlock(cli)?;
    let mut paths: Vec<String> = Vec::new();

    match search::search_entries(STORE_JOURNAL, text, 50) {
        Ok(hits) => paths.extend(hits.into_iter().map(|hit| hit.path)),
        Err(e) => {
            // The index cannot answer every query — a bare `+` or an
            // unbalanced quote, say — so fall back to a plain scan.
            eprintln!("The search index could not answer that ({e}); scanning instead.");
            let hits =
                vault::search(text, 50, STORE_JOURNAL).map_err(|e| color_eyre::eyre::eyre!(e))?;
            paths.extend(
                hits.iter()
                    .filter_map(|hit| hit.get("rel_path").and_then(|v| v.as_str()))
                    .map(str::to_string),
            );
        }
    }

    if paths.is_empty() {
        println!("No matches for {text:?}.");
        return Ok(());
    }
    for path in paths {
        println!("{path}");
    }
    Ok(())
}

fn cmd_query(cli: &Cli, text: &str) -> color_eyre::Result<()> {
    let found = queried_entries(cli, text)?;
    if found.is_empty() {
        println!("No notes match {text:?}.");
        return Ok(());
    }
    for (path, title) in found {
        println!("{:<20}  {}", path, title);
    }
    Ok(())
}

/// The notes `lumen query` finds: their path and their title.
///
/// The notes are newest first, like the list.
pub fn queried_entries(cli: &Cli, text: &str) -> color_eyre::Result<Vec<(String, String)>> {
    unlock(cli)?;
    let mut paths = query::query(STORE_JOURNAL, text).map_err(|e| color_eyre::eyre::eyre!(e))?;
    paths.sort_by(|a, b| b.cmp(a));

    Ok(paths
        .into_iter()
        .map(|path| {
            let title = read_entry(&path)
                .map(|b| title_of(&b, &path))
                .unwrap_or_else(|_| path.clone());
            (path, title)
        })
        .collect())
}

fn cmd_view(cli: &Cli, path: &str) -> color_eyre::Result<()> {
    unlock(cli)?;
    let body = read_entry(path)?;
    let skin = MadSkin::default();
    skin.print_text(&body);
    Ok(())
}

fn cmd_writer(cli: &Cli, path: &str) -> color_eyre::Result<()> {
    unlock(cli)?;
    let initial = if vault::read_text(path, STORE_JOURNAL).is_ok() {
        read_entry(path)?
    } else {
        String::new()
    };
    match edit_in_editor(&initial, "edit.md")? {
        Some(text) => {
            vault::write_text(path, &text, STORE_JOURNAL)
                .map_err(|e| color_eyre::eyre::eyre!(e))?;
            println!("Saved {path}");
        }
        None => println!("No changes."),
    }
    Ok(())
}

fn cmd_today(cli: &Cli) -> color_eyre::Result<()> {
    let date = Local::now().date_naive();
    cmd_daily_note(cli, &template::daily_note_path(date), date)
}

fn cmd_daily(cli: &Cli, date: Option<&str>) -> color_eyre::Result<()> {
    let date = match date {
        Some(text) => NaiveDate::parse_from_str(text, "%Y-%m-%d")
            .map_err(|e| color_eyre::eyre::eyre!("{text:?} is not a date: {e}"))?,
        None => Local::now().date_naive(),
    };
    cmd_daily_note(cli, &template::daily_note_path(date), date)
}

/// Open a daily note in `$EDITOR`, starting it from the template when the
/// day has no note yet.
fn cmd_daily_note(cli: &Cli, path: &str, date: NaiveDate) -> color_eyre::Result<()> {
    unlock(cli)?;
    let initial = match vault::read_text(path, STORE_JOURNAL) {
        Ok(text) => text,
        Err(_) => template::render_daily_template(date),
    };
    match edit_in_editor(&initial, "edit.md")? {
        Some(text) => {
            vault::write_text(path, &text, STORE_JOURNAL)
                .map_err(|e| color_eyre::eyre::eyre!(e))?;
            println!("Saved {path}");
        }
        None => println!("No changes."),
    }
    Ok(())
}

fn cmd_daily_template(cli: &Cli) -> color_eyre::Result<()> {
    unlock(cli)?;
    let path = config::daily_template_path();
    // The template is written out if it is missing, so the path that is
    // printed is a file the user can edit.
    template::ensure_template_exists().map_err(|e| color_eyre::eyre::eyre!(e))?;
    let content = std::fs::read_to_string(&path).unwrap_or_default();
    println!("{}", path.display());
    println!();
    print!("{content}");
    Ok(())
}

fn cmd_backlinks(cli: &Cli, path: &str) -> color_eyre::Result<()> {
    unlock(cli)?;
    let mut links = wikilinks::get_backlinks(STORE_JOURNAL, path);
    if links.is_empty() {
        println!("Nothing links to {path}.");
        return Ok(());
    }
    links.sort();
    for link in links {
        let title = read_entry(&link)
            .map(|b| title_of(&b, &link))
            .unwrap_or_else(|_| link.clone());
        println!("{:<20}  {}", link, title);
    }
    Ok(())
}

fn journal_dates(cli: &Cli) -> color_eyre::Result<BTreeSet<NaiveDate>> {
    unlock(cli)?;
    let mut dates = BTreeSet::new();
    for e in entries()? {
        let stem = e
            .name
            .trim_end_matches(".md")
            .trim_end_matches(".markdown")
            .to_string();
        let candidate = stem.get(..10).unwrap_or("");
        if let Ok(d) = NaiveDate::parse_from_str(candidate, "%Y-%m-%d") {
            dates.insert(d);
        }
    }
    Ok(dates)
}

fn cmd_streak(cli: &Cli) -> color_eyre::Result<()> {
    let dates = journal_dates(cli)?;
    let today = Local::now().date_naive();
    let mut cursor = if dates.contains(&today) {
        today
    } else {
        today - Duration::days(1)
    };
    let mut streak = 0;
    while dates.contains(&cursor) {
        streak += 1;
        cursor -= Duration::days(1);
    }
    println!("{streak} day{}", if streak == 1 { "" } else { "s" });
    Ok(())
}

fn cmd_sync(cli: &Cli, cmd: &SyncCommands) -> color_eyre::Result<()> {
    use lumen_core::sync::{
        create_backup_bundle, generate_syncthing_config, get_sync_status, init_sync,
        resolve_conflict, restore_backup_bundle,
    };

    let root = unlock(cli)?;
    let root_str = root.to_string_lossy().to_string();

    match cmd {
        SyncCommands::Status => {
            for line in sync_status_lines(&root_str)? {
                println!("{line}");
            }
        }
        SyncCommands::Conflicts { diff } => {
            init_sync(&root_str).map_err(|e| color_eyre::eyre::eyre!(e))?;
            let status = get_sync_status().map_err(|e| color_eyre::eyre::eyre!(e))?;
            if status.conflicts.is_empty() {
                println!("No conflicts detected.");
            } else {
                println!("Conflicts ({}):", status.conflicts.len());
                for c in &status.conflicts {
                    println!("  {}", c.path);
                    println!("    Local:  {}  ({})", c.local_modified, c.local_hash);
                    println!("    Remote: {}  ({})", c.remote_modified, c.remote_hash);
                    if *diff {
                        print_difference(&root_str, &c.path);
                    }
                }
            }
        }
        SyncCommands::Resolve { path, keep_local } => {
            init_sync(&root_str).map_err(|e| color_eyre::eyre::eyre!(e))?;
            resolve_conflict(path, *keep_local).map_err(|e| color_eyre::eyre::eyre!(e))?;
            println!(
                "Resolved conflict for {} (kept {})",
                path,
                if *keep_local { "local" } else { "remote" }
            );
        }
        SyncCommands::GenSyncthingConfig => {
            let xml =
                generate_syncthing_config(&root_str).map_err(|e| color_eyre::eyre::eyre!(e))?;
            println!("{}", xml);
        }
        SyncCommands::BackupCreate { output, passphrase } => {
            let pass = passphrase.clone().unwrap_or_else(prompt_password_hidden);
            let out_path = std::path::Path::new(output);
            create_backup_bundle(&root_str, &pass, out_path)
                .map_err(|e| color_eyre::eyre::eyre!(e))?;
            println!("Backup created at {}", output);
        }
        SyncCommands::BackupRestore {
            bundle,
            target,
            passphrase,
        } => {
            let pass = passphrase.clone().unwrap_or_else(prompt_password_hidden);
            let bundle_path = std::path::Path::new(bundle);
            let target_path = std::path::Path::new(target);
            restore_backup_bundle(bundle_path, &pass, target_path)
                .map_err(|e| color_eyre::eyre::eyre!(e))?;
            println!("Backup restored to {}", target);
        }
    }
    Ok(())
}

/// The lines `lumen sync status` prints.
///
/// Syncthing not running is not a failure — the journal works either way
/// — but the reason is worth saying, so it is a line of its own.
pub fn sync_status_lines(vault_path: &str) -> color_eyre::Result<Vec<String>> {
    use lumen_core::sync::{get_sync_status, init_sync};

    init_sync(vault_path).map_err(|e| color_eyre::eyre::eyre!(e))?;
    let status = get_sync_status().map_err(|e| color_eyre::eyre::eyre!(e))?;

    let mut lines = vec![
        "Sync Status:".to_string(),
        format!("  Enabled:  {}", if status.enabled { "yes" } else { "no" }),
        format!("  Method:   {:?}", status.method),
        format!(
            "  Last sync: {}",
            status
                .last_sync
                .map(|d| d.to_rfc3339())
                .unwrap_or_else(|| "never".into())
        ),
        format!("  Pending:  {}", status.pending_changes),
        format!("  Conflicts: {}", status.conflicts.len()),
        format!("  Devices:   {}", status.device_status.len()),
    ];

    if let Some(reason) = &status.device_error {
        lines.push(format!("  Note:      {reason}"));
    }

    Ok(lines)
}

/// The difference between the two versions of a conflicted note.
///
/// Both versions are read through the vault, which is the only place that
/// can read them: the version the other device sent is an encrypted file
/// inside the vault.
pub fn conflict_diff(vault_path: &str, path: &str) -> color_eyre::Result<Vec<DiffLine>> {
    use lumen_core::sync::conflict_versions;

    let (local, remote) = conflict_versions(STORE_JOURNAL, vault_path, path)
        .map_err(|e| color_eyre::eyre::eyre!(e))?;
    Ok(lumen_core::diff::diff(&local, &remote))
}

/// Print what changed between the two versions of a conflicted note.
fn print_difference(vault_path: &str, path: &str) {
    use lumen_core::diff::DiffKind;

    let lines = match conflict_diff(vault_path, path) {
        Ok(lines) => lines,
        Err(e) => {
            println!("    Difference: could not be shown ({e})");
            return;
        }
    };

    println!("    Difference:");
    for line in lines {
        let marker = match line.kind {
            DiffKind::Added => '+',
            DiffKind::Removed => '-',
            DiffKind::Same => ' ',
        };
        println!("      {marker} {}", line.text);
    }
}
