use clap::{Parser, Subcommand};
use lumen_core::storage::Storage;
use std::{io, path::PathBuf, process::Command};
use termimad::MadSkin;
use ratatui::{
    backend::CrosstermBackend,
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph},
    layout::{Layout, Constraint, Direction},
    style::{Style, Modifier, Color as RColor},
    Terminal,
};
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use termimad::crossterm::style::Color;

#[derive(Parser)]
#[command(author, version, about = "Lumen Terminal Interface", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    /// Path to the lumen.db file. Defaults to ~/.local/share/lumen/lumen.db
    #[arg(short, long, value_name = "FILE")]
    database: Option<PathBuf>,
}

#[derive(Subcommand)]
enum Commands {
    /// List entries in the vault
    List {
        #[arg(short, long)]
        kind: Option<String>,
        #[arg(short, long)]
        author: Option<String>,
        #[arg(short, long, default_value_t = 20)]
        limit: usize,
    },
    /// Search entries
    Search { query: String },
    /// View a specific entry
    View {
        id: String,
        #[arg(short, long)]
        password: Option<String>,
    },
    /// Show streak
    Streak,
    /// Launch interactive TUI
    Interactive,
}

fn get_default_db_path() -> PathBuf {
    lumen_core::paths::db_path()
}

fn find_gui_executable() -> Option<PathBuf> {
    let exe = std::env::current_exe().ok()?;
    let exe_dir = exe.parent()?;

    let candidates = if cfg!(target_os = "windows") {
        vec![
            exe_dir.join("Lumen.exe"),
            exe_dir.join("../../ui/build/windows/x64/runner/Release/Lumen.exe"),
            exe_dir.join("../../ui/build/windows/x64/runner/Debug/Lumen.exe"),
            exe_dir.join("../../ui/build/windows/x64/release/bundle/Lumen.exe"),
        ]
    } else if cfg!(target_os = "macos") {
        vec![
            exe_dir.join("../../ui/build/macos/Build/Products/Release/Lumen.app/Contents/MacOS/Lumen"),
        ]
    } else {
        vec![
            exe_dir.join("../../ui/build/linux/x64/release/bundle/Lumen"),
            exe_dir.join("../../ui/build/linux/x64/debug/bundle/Lumen"),
        ]
    };

    for path in &candidates {
        if path.exists() {
            if let (Ok(candidate), Ok(current)) = (path.canonicalize(), exe.canonicalize()) {
                if candidate == current {
                    continue;
                }
            }
            return Some(path.clone());
        }
    }
    None
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();
    let db_path = cli.database.unwrap_or_else(get_default_db_path);

    let storage = Storage::new(&db_path)?;

    match cli.command {
        Some(Commands::List { kind, author, limit }) => {
            let entries = storage.list_entries()?;
            let filtered: Vec<_> = entries.into_iter()
                .filter(|e| {
                    let kind_match = kind.as_ref().map_or(true, |k| e.kind.as_str() == k);
                    let author_match = author.as_ref().map_or(true, |a| e.provenance.author == *a);
                    kind_match && author_match
                })
                .take(limit)
                .collect();

            if filtered.is_empty() {
                println!("No entries found.");
            } else {
                let mut skin = MadSkin::default();
                skin.set_headers_fg(Color::Yellow);
                println!("| ID | Kind | Author | Title |");
                println!("|---|---|---|---|");
                for e in filtered {
                    println!("| {} | {} | {} | {} |",
                        e.id, e.kind.as_str(), e.provenance.author,
                        if e.display_title.is_empty() { "(no title)" } else { &e.display_title }
                    );
                }
            }
        }
        Some(Commands::Search { query }) => {
            let entries = storage.search_entries(&query)?;
            for e in entries {
                println!("- **{}** ({}): {}", e.id, e.kind.as_str(), e.display_title);
            }
        }
        Some(Commands::View { id, password }) => {
            if let Some(entry) = storage.get_entry(&id)? {
                let mut skin = MadSkin::default();
                skin.bold.set_fg(Color::Cyan);
                skin.set_headers_fg(Color::Yellow);

                skin.print_text(&format!("# {}\n", entry.display_title));
                skin.print_text(&format!("*ID:* `{}` | *Kind:* **{}** | *Date:* {}\n",
                    entry.id, entry.kind.as_str(), entry.provenance.timestamp));
                skin.print_text("---\n");

                let pw = password.unwrap_or_default();
                if entry.salt.is_empty() {
                    skin.print_text("> **Info:** Plaintext entry.\n");
                } else if !pw.is_empty() {
                    let key = lumen_core::entry::encryption::derive_key(&pw, &entry.salt);
                    match entry.decrypt(&key) {
                        Ok(bytes) => skin.print_text(&String::from_utf8_lossy(&bytes)),
                        Err(e) => println!("Error: {}", e),
                    }
                } else {
                    println!("Entry is encrypted. Use --password.");
                }
            }
        }
        Some(Commands::Streak) => {
            println!("Current Streak: **{} days** 🔥", storage.get_streak()?);
        }
        Some(Commands::Interactive) => {
            run_tui(storage)?;
        }
        None => {
            if let Some(gui_path) = find_gui_executable() {
                eprintln!("Launching GUI from {:?}", gui_path);
                Command::new(&gui_path).spawn()?;
            } else {
                eprintln!("Flutter GUI not found. Falling back to TUI.");
                run_tui(storage)?;
            }
        }
    }

    Ok(())
}

fn run_tui(storage: Storage) -> Result<(), Box<dyn std::error::Error>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let entries = storage.list_entries()?;
    let mut state = ListState::default();
    state.select(Some(0));

    loop {
        terminal.draw(|f| {
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .margin(1)
                .constraints([Constraint::Length(3), Constraint::Min(0)].as_ref())
                .split(f.size());

            let title = Paragraph::new("Lumen Journal - [q]uit [up/down] navigate")
                .block(Block::default().borders(Borders::ALL).title("Dashboard"));
            f.render_widget(title, chunks[0]);

            let items: Vec<ListItem> = entries
                .iter()
                .map(|e| {
                    ListItem::new(format!(
                        "{} | {:<10} | {}",
                        e.id,
                        e.kind.as_str(),
                        if e.display_title.is_empty() { "(no title)" } else { &e.display_title }
                    ))
                })
                .collect();

            let list = List::new(items)
                .block(Block::default().borders(Borders::ALL).title("Entries"))
                .highlight_style(Style::default().add_modifier(Modifier::BOLD).fg(RColor::Yellow))
                .highlight_symbol(">> ");

            f.render_stateful_widget(list, chunks[1], &mut state);
        })?;

        if let Event::Key(key) = event::read()? {
            match key.code {
                KeyCode::Char('q') => break,
                KeyCode::Down => {
                    let i = match state.selected() {
                        Some(i) => if i >= entries.len() - 1 { 0 } else { i + 1 },
                        None => 0,
                    };
                    state.select(Some(i));
                }
                KeyCode::Up => {
                    let i = match state.selected() {
                        Some(i) => if i == 0 { entries.len() - 1 } else { i - 1 },
                        None => 0,
                    };
                    state.select(Some(i));
                }
                _ => {}
            }
        }
    }

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen, DisableMouseCapture)?;
    terminal.show_cursor()?;

    Ok(())
}
