//! Lumen terminal interface.
//!
//! Reads and edits the encrypted Markdown journal store (`STORE_JOURNAL`),
//! the same store the desktop app uses. Nothing is written in plaintext: the
//! store is unlocked with its passphrase for the lifetime of the process.

use std::collections::BTreeSet;
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::Command;

use chrono::{Duration, Local, NaiveDate};
use clap::{Parser, Subcommand};
use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    style::{Color as RColor, Modifier, Style},
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Wrap},
    Terminal,
};
use termimad::MadSkin;

use lumen_core::vault::{self, STORE_JOURNAL};

#[derive(Parser)]
#[command(author, version, about = "Lumen journal (terminal)", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    /// Folder holding the encrypted journal (.lumen/journal.json).
    #[arg(short, long, value_name = "DIR", env = "LUMEN_JOURNAL", global = true)]
    vault: Option<PathBuf>,

    /// Journal passphrase. Prefer the LUMEN_PASSWORD environment variable or
    /// the interactive prompt.
    #[arg(
        short,
        long,
        env = "LUMEN_PASSWORD",
        hide_env_values = true,
        global = true
    )]
    password: Option<String>,
}

#[derive(Subcommand)]
enum Commands {
    /// Create the encrypted journal at --vault.
    Init,
    /// List journal entries (newest first).
    List,
    /// Full-text search across the journal.
    Search { query: String },
    /// Print a single Markdown entry.
    View { path: String },
    /// Create (or open) today's entry in $EDITOR.
    Today,
    /// Edit an entry in $EDITOR.
    Edit { path: String },
    /// Consecutive days written, counting back from today.
    Streak,
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

fn entries() -> color_eyre::Result<Vec<vault::VaultEntry>> {
    let mut list: Vec<vault::VaultEntry> = vault::list("", STORE_JOURNAL)
        .map_err(|e| color_eyre::eyre::eyre!(e))?
        .into_iter()
        .filter(|e| !e.is_dir && is_markdown(&e.name))
        .collect();
    // Newest first; filenames are date-prefixed for entries created by Lumen.
    list.sort_by(|a, b| b.rel_path.cmp(&a.rel_path));
    Ok(list)
}

fn title_of(body: &str, fallback: &str) -> String {
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

fn read_entry(path: &str) -> color_eyre::Result<String> {
    vault::read_text(path, STORE_JOURNAL).map_err(|e| color_eyre::eyre::eyre!(e))
}

fn shell_temp_path(name: &str) -> PathBuf {
    std::env::temp_dir().join(format!("lumen-{}-{}", std::process::id(), name))
}

fn edit_in_editor(initial: &str) -> color_eyre::Result<Option<String>> {
    let editor = std::env::var("EDITOR")
        .or_else(|_| std::env::var("VISUAL"))
        .unwrap_or_else(|_| "vi".to_string());
    let path = shell_temp_path("edit.md");
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

fn cmd_list(cli: &Cli) -> color_eyre::Result<()> {
    unlock(cli)?;
    let list = entries()?;
    if list.is_empty() {
        println!("No entries yet. Press `n` in the TUI, or use `lumen today`.");
        return Ok(());
    }
    for e in list {
        let title = read_entry(&e.rel_path)
            .map(|b| title_of(&b, &e.name))
            .unwrap_or_else(|_| e.name.clone());
        println!("{:<20}  {}", e.rel_path, title);
    }
    Ok(())
}

fn cmd_search(cli: &Cli, query: &str) -> color_eyre::Result<()> {
    unlock(cli)?;
    let results =
        vault::search(query, 50, STORE_JOURNAL).map_err(|e| color_eyre::eyre::eyre!(e))?;
    if results.is_empty() {
        println!("No matches for {query:?}.");
        return Ok(());
    }
    for hit in results {
        let path = hit.get("rel_path").and_then(|v| v.as_str()).unwrap_or("");
        println!("{path}");
    }
    Ok(())
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
    match edit_in_editor(&initial)? {
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
    unlock(cli)?;
    let path = format!("{}.md", Local::now().format("%Y-%m-%d"));
    cmd_writer(cli, &path)
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

struct App {
    entries: Vec<vault::VaultEntry>,
    titles: Vec<String>,
    state: ListState,
    preview: String,
    preview_title: String,
}

impl App {
    fn new() -> color_eyre::Result<Self> {
        let mut app = App {
            entries: Vec::new(),
            titles: Vec::new(),
            state: ListState::default(),
            preview: String::new(),
            preview_title: String::new(),
        };
        app.reload()?;
        Ok(app)
    }

    fn reload(&mut self) -> color_eyre::Result<()> {
        let selected = self.selected_path();
        self.entries = entries()?;
        self.titles = self
            .entries
            .iter()
            .map(|e| {
                read_entry(&e.rel_path)
                    .map(|b| title_of(&b, &e.name))
                    .unwrap_or_else(|_| e.name.clone())
            })
            .collect();
        let index = selected
            .and_then(|p| self.entries.iter().position(|e| e.rel_path == p))
            .unwrap_or(0);
        if !self.entries.is_empty() {
            self.state.select(Some(index.min(self.entries.len() - 1)));
        }
        self.load_preview()
    }

    fn selected_path(&self) -> Option<String> {
        self.state
            .selected()
            .and_then(|i| self.entries.get(i))
            .map(|e| e.rel_path.clone())
    }

    fn move_by(&mut self, delta: i64) {
        if self.entries.is_empty() {
            return;
        }
        let len = self.entries.len() as i64;
        let current = self.state.selected().unwrap_or(0) as i64;
        let next = (current + delta).rem_euclid(len);
        self.state.select(Some(next as usize));
        let _ = self.load_preview();
    }

    fn load_preview(&mut self) -> color_eyre::Result<()> {
        match self.selected_path() {
            Some(path) => {
                self.preview_title = path.clone();
                self.preview = read_entry(&path).unwrap_or_else(|e| format!("Could not read: {e}"));
            }
            None => {
                self.preview_title = "No entries".into();
                self.preview = "Create one with `n` (today) or in the desktop app.".into();
            }
        }
        Ok(())
    }

    fn new_today(&mut self) -> color_eyre::Result<()> {
        let path = format!("{}.md", Local::now().format("%Y-%m-%d"));
        let initial = vault::read_text(&path, STORE_JOURNAL).unwrap_or_default();
        if let Some(text) = edit_in_editor(&initial)? {
            vault::write_text(&path, &text, STORE_JOURNAL)
                .map_err(|e| color_eyre::eyre::eyre!(e))?;
        }
        self.reload()
    }

    fn edit_selected(&mut self) -> color_eyre::Result<()> {
        let Some(path) = self.selected_path() else {
            return Ok(());
        };
        let initial = read_entry(&path)?;
        if let Some(text) = edit_in_editor(&initial)? {
            vault::write_text(&path, &text, STORE_JOURNAL)
                .map_err(|e| color_eyre::eyre::eyre!(e))?;
        }
        self.reload()
    }
}

fn draw(frame: &mut ratatui::Frame, app: &mut App) {
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(40), Constraint::Percentage(60)])
        .split(frame.size());

    let items: Vec<ListItem> = app
        .entries
        .iter()
        .enumerate()
        .map(|(i, e)| {
            let date = e.rel_path.get(..10).unwrap_or(&e.rel_path);
            let title = app.titles.get(i).map(String::as_str).unwrap_or(&e.name);
            ListItem::new(format!("{date}  {title}"))
        })
        .collect();

    let list = List::new(items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(" Journal  [n]ew  [e]dit  [r]eload  [q]uit "),
        )
        .highlight_style(
            Style::default()
                .bg(RColor::Indexed(238))
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol("› ");
    frame.render_stateful_widget(list, chunks[0], &mut app.state);

    let preview = Paragraph::new(app.preview.as_str())
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(format!(" {} ", app.preview_title)),
        )
        .wrap(Wrap { trim: false });
    frame.render_widget(preview, chunks[1]);
}

fn event_loop(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
) -> color_eyre::Result<()> {
    loop {
        terminal.draw(|frame| draw(frame, app))?;

        if event::poll(std::time::Duration::from_millis(200))? {
            if let Event::Key(key) = event::read()? {
                if key.kind != KeyEventKind::Press {
                    continue;
                }
                match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
                    KeyCode::Down | KeyCode::Char('j') => app.move_by(1),
                    KeyCode::Up | KeyCode::Char('k') => app.move_by(-1),
                    KeyCode::Char('n') => app.new_today()?,
                    KeyCode::Char('e') | KeyCode::Enter => app.edit_selected()?,
                    KeyCode::Char('r') => app.reload()?,
                    _ => {}
                }
            }
        }
    }
}

fn run_tui() -> color_eyre::Result<()> {
    // Build the app before switching terminals so an error leaves the shell
    // untouched.
    let mut app = App::new()?;

    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let result = event_loop(&mut terminal, &mut app);

    let _ = disable_raw_mode();
    let _ = execute!(terminal.backend_mut(), LeaveAlternateScreen);
    let _ = terminal.show_cursor();
    result
}

fn main() -> color_eyre::Result<()> {
    color_eyre::install()?;

    let cli = Cli::parse();
    match &cli.command {
        None => {
            unlock(&cli)?;
            run_tui()
        }
        Some(Commands::Init) => cmd_init(&cli),
        Some(Commands::List) => cmd_list(&cli),
        Some(Commands::Search { query }) => cmd_search(&cli, query),
        Some(Commands::View { path }) => cmd_view(&cli, path),
        Some(Commands::Today) => cmd_today(&cli),
        Some(Commands::Edit { path }) => cmd_writer(&cli, path),
        Some(Commands::Streak) => cmd_streak(&cli),
    }
}
