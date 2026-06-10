use clap::{Parser, Subcommand};
use lumen::storage::Storage;
use lumen::entry::EntryKind;
use std::path::PathBuf;
use chrono::DateTime;

#[derive(Parser)]
#[command(author, version, about = "Lumen Terminal Interface", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,

    /// Path to the lumen.db file. Defaults to ~/.local/share/lumen/lumen.db
    #[arg(short, long, value_name = "FILE")]
    database: Option<PathBuf>,
}

#[derive(Subcommand)]
enum Commands {
    /// List entries in the vault
    List {
        /// Filter by entry kind (journal, note, task, project)
        #[arg(short, long)]
        kind: Option<String>,

        /// Filter by author
        #[arg(short, long)]
        author: Option<String>,

        /// Limit the number of results
        #[arg(short, long, default_value_t = 20)]
        limit: usize,
    },
    /// Search entries using metadata
    Search {
        /// Search query
        query: String,
    },
    /// Decrypt and view a specific entry
    View {
        /// ID of the entry to view
        id: String,

        /// Password to decrypt the entry (optional if session is active/plaintext)
        #[arg(short, long)]
        password: Option<String>,
    },
    /// Show current journaling streak
    Streak,
}

fn get_default_db_path() -> PathBuf {
    let mut path = dirs::data_dir().unwrap_or_else(|| PathBuf::from("."));
    path.push("lumen");
    path.push("lumen.db");
    path
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();
    let db_path = cli.database.unwrap_or_else(get_default_db_path);

    if !db_path.exists() {
        eprintln!("Error: Database not found at {:?}", db_path);
        std::process::exit(1);
    }

    let storage = Storage::new(&db_path)?;

    match cli.command {
        Commands::List { kind, author, limit } => {
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
                println!("{:<20} | {:<10} | {:<15} | {}", "ID", "Kind", "Author", "Title");
                println!("{:-<20}-+-{:-<10}-+-{:-<15}-+---", "", "", "");
                for e in filtered {
                    println!("{:<20} | {:<10} | {:<15} | {}",
                        e.id,
                        e.kind.as_str(),
                        e.provenance.author,
                        if e.display_title.is_empty() { "(no title)" } else { &e.display_title }
                    );
                }
            }
        }
        Commands::Search { query } => {
            let entries = storage.search_entries(&query)?;
            if entries.is_empty() {
                println!("No results found for '{}'.", query);
            } else {
                println!("Search results for '{}':", query);
                println!("{:<20} | {:<10} | {}", "ID", "Kind", "Title");
                for e in entries {
                    println!("{:<20} | {:<10} | {}", e.id, e.kind.as_str(), e.display_title);
                }
            }
        }
        Commands::View { id, password } => {
            match storage.get_entry(&id)? {
                Some(entry) => {
                    println!("Entry: {}", entry.id);
                    println!("Kind:  {}", entry.kind.as_str());
                    println!("Date:  {}", entry.provenance.timestamp);
                    println!("Title: {}", entry.display_title);
                    println!("Tags:  {}", entry.tags.join(", "));
                    println!("----------------------------------------");

                    let pw = password.unwrap_or_default();
                    let key = if pw.is_empty() && entry.salt.is_empty() {
                        // Attempt with empty session key or something?
                        // Core usually handles this via ffi.
                        // For TUI, we'll try to derive from provided password.
                        None
                    } else if !entry.salt.is_empty() {
                        if pw.is_empty() {
                            println!("Error: Entry is encrypted. Please provide a password with --password.");
                            return Ok(());
                        }
                        Some(lumen::entry::encryption::derive_key(&pw, &entry.salt))
                    } else {
                        // plaintext or session key needed
                        None
                    };

                    if let Some(k) = key {
                        match entry.decrypt(&k) {
                            Ok(bytes) => {
                                let text = String::from_utf8_lossy(&bytes);
                                println!("{}", text);
                            },
                            Err(e) => println!("Error decrypting: {}", e),
                        }
                    } else if entry.salt.is_empty() {
                         println!("Error: Decryption requires a session key or master password. (Session key not supported in TUI yet)");
                    }
                },
                None => println!("Entry not found."),
            }
        }
        Commands::Streak => {
            let streak = storage.get_streak()?;
            println!("Current Streak: {} days 🔥", streak);
        }
    }

    Ok(())
}
