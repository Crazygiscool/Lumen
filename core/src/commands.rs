//! Command registry for the command palette.
//!
//! Commands are named actions that the user can invoke from the command
//! palette (`Ctrl+K` / `Cmd+K`), the terminal client (`:command`), or
//! plugins. Built-in commands cover navigation, capture, editing, view,
//! sync, plugins, and advanced operations. Plugins can contribute their
//! own commands through `contributes.commands[]` in `plugin.toml`.

use std::collections::HashMap;
use std::sync::Mutex;

use lazy_static::lazy_static;
use serde::{Deserialize, Serialize};

/// A registered command.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Command {
    /// Unique command id (e.g. `journal.openDailyNote`).
    pub id: String,
    /// Human-readable title shown in the palette.
    pub title: String,
    /// Optional description shown as a subtitle.
    pub description: Option<String>,
    /// Keywords for fuzzy matching (title is always included).
    #[serde(default)]
    pub keywords: Vec<String>,
    /// Source of the command: `builtin` or a plugin id.
    #[serde(default = "default_source")]
    pub source: String,
}

fn default_source() -> String {
    "builtin".to_string()
}

/// The global command registry.
///
/// Built-in commands are registered at startup; plugin commands are added
/// when a plugin is enabled.
#[derive(Default)]
struct CommandRegistry {
    commands: HashMap<String, Command>,
}

lazy_static! {
    static ref COMMANDS: Mutex<CommandRegistry> = Mutex::new(CommandRegistry::default());
    static ref BUILTIN_REGISTERED: Mutex<bool> = Mutex::new(false);
}

/// Register a command. Returns an error if a command with the same id
/// already exists.
pub fn register_command(command: Command) -> crate::Result<()> {
    let mut guard = COMMANDS.lock().unwrap();
    if guard.commands.contains_key(&command.id) {
        return Err(format!("command '{}' is already registered", command.id));
    }
    guard.commands.insert(command.id.clone(), command);
    Ok(())
}

/// Unregister all commands from a given source (e.g. when a plugin is
/// disabled).
pub fn unregister_commands_from(source: &str) {
    let mut guard = COMMANDS.lock().unwrap();
    guard.commands.retain(|_, c| c.source != source);
}

/// List all registered commands.
pub fn list_commands() -> Vec<Command> {
    let guard = COMMANDS.lock().unwrap();
    let mut commands: Vec<Command> = guard.commands.values().cloned().collect();
    commands.sort_by(|a, b| a.id.cmp(&b.id));
    commands
}

/// Register all built-in commands. Safe to call multiple times.
pub fn register_builtin_commands() -> crate::Result<()> {
    let mut registered = BUILTIN_REGISTERED.lock().unwrap();
    if *registered {
        return Ok(());
    }
    let commands = [
        // Navigation
        Command {
            id: "journal.openDailyNote".into(),
            title: "Open Daily Note".into(),
            description: Some("Open today's daily note".into()),
            keywords: vec!["today".into(), "daily".into(), "journal".into()],
            source: "builtin".into(),
        },
        Command {
            id: "journal.openNote".into(),
            title: "Open Note...".into(),
            description: Some("Open any note by name".into()),
            keywords: vec!["open".into(), "note".into(), "file".into()],
            source: "builtin".into(),
        },
        Command {
            id: "navigation.openSearch".into(),
            title: "Open Search".into(),
            description: Some("Full-text search across notes".into()),
            keywords: vec!["search".into(), "find".into(), "query".into()],
            source: "builtin".into(),
        },
        Command {
            id: "navigation.openGraph".into(),
            title: "Open Graph".into(),
            description: Some("View the note graph".into()),
            keywords: vec!["graph".into(), "visual".into(), "map".into()],
            source: "builtin".into(),
        },
        Command {
            id: "navigation.openSettings".into(),
            title: "Open Settings".into(),
            description: Some("Configure Lumen".into()),
            keywords: vec!["settings".into(), "config".into(), "preferences".into()],
            source: "builtin".into(),
        },
        // Capture
        Command {
            id: "capture.newNote".into(),
            title: "New Note".into(),
            description: Some("Create a new blank note".into()),
            keywords: vec!["new".into(), "create".into(), "blank".into()],
            source: "builtin".into(),
        },
        Command {
            id: "capture.newDailyNote".into(),
            title: "New Daily Note".into(),
            description: Some("Create today's daily note".into()),
            keywords: vec!["daily".into(), "today".into(), "template".into()],
            source: "builtin".into(),
        },
        Command {
            id: "capture.quickCapture".into(),
            title: "Quick Capture".into(),
            description: Some("Jot down a quick thought".into()),
            keywords: vec!["capture".into(), "quick".into(), "note".into()],
            source: "builtin".into(),
        },
        // Editing
        Command {
            id: "editing.togglePreview".into(),
            title: "Toggle Preview".into(),
            description: Some("Switch between editor and preview".into()),
            keywords: vec!["preview".into(), "markdown".into(), "view".into()],
            source: "builtin".into(),
        },
        Command {
            id: "editing.insertWikilink".into(),
            title: "Insert Wikilink".into(),
            description: Some("Insert a `[[wikilink]]`".into()),
            keywords: vec!["wikilink".into(), "link".into(), "insert".into()],
            source: "builtin".into(),
        },
        Command {
            id: "editing.insertTag".into(),
            title: "Insert Tag".into(),
            description: Some("Insert a `#tag`".into()),
            keywords: vec!["tag".into(), "insert".into()],
            source: "builtin".into(),
        },
        Command {
            id: "editing.wordCount".into(),
            title: "Word Count".into(),
            description: Some("Count words in the current note".into()),
            keywords: vec!["count".into(), "words".into(), "stats".into()],
            source: "builtin".into(),
        },
        // View
        Command {
            id: "view.toggleTheme".into(),
            title: "Toggle Theme".into(),
            description: Some("Switch between light and dark theme".into()),
            keywords: vec!["theme".into(), "dark".into(), "light".into()],
            source: "builtin".into(),
        },
        Command {
            id: "view.focusEditor".into(),
            title: "Focus Editor".into(),
            description: Some("Hide sidebars, editor only".into()),
            keywords: vec!["focus".into(), "editor".into(), "zen".into()],
            source: "builtin".into(),
        },
        Command {
            id: "view.zenMode".into(),
            title: "Zen Mode".into(),
            description: Some("Full-screen distraction-free writing".into()),
            keywords: vec!["zen".into(), "focus".into(), "fullscreen".into()],
            source: "builtin".into(),
        },
        // Sync
        Command {
            id: "sync.syncNow".into(),
            title: "Sync Now".into(),
            description: Some("Run a sync with the configured method".into()),
            keywords: vec!["sync".into(), "now".into(), "push".into(), "pull".into()],
            source: "builtin".into(),
        },
        Command {
            id: "sync.showConflicts".into(),
            title: "Show Conflicts".into(),
            description: Some("List and resolve sync conflicts".into()),
            keywords: vec!["conflict".into(), "resolve".into(), "sync".into()],
            source: "builtin".into(),
        },
        Command {
            id: "sync.exportBackup".into(),
            title: "Export Backup".into(),
            description: Some("Create an encrypted backup bundle".into()),
            keywords: vec!["backup".into(), "export".into(), "bundle".into()],
            source: "builtin".into(),
        },
        // Plugins
        Command {
            id: "plugins.runPlugin".into(),
            title: "Run Plugin".into(),
            description: Some("Execute a plugin command".into()),
            keywords: vec!["plugin".into(), "run".into(), "execute".into()],
            source: "builtin".into(),
        },
        Command {
            id: "plugins.configurePlugin".into(),
            title: "Configure Plugin".into(),
            description: Some("Change plugin settings".into()),
            keywords: vec!["plugin".into(), "configure".into(), "settings".into()],
            source: "builtin".into(),
        },
        // Advanced
        Command {
            id: "advanced.rebuildSearchIndex".into(),
            title: "Rebuild Search Index".into(),
            description: Some("Re-index all notes for search".into()),
            keywords: vec!["reindex".into(), "search".into(), "index".into()],
            source: "builtin".into(),
        },
        Command {
            id: "advanced.rebuildGraph".into(),
            title: "Rebuild Graph".into(),
            description: Some("Re-compute the note graph".into()),
            keywords: vec!["graph".into(), "rebuild".into()],
            source: "builtin".into(),
        },
        Command {
            id: "advanced.verifyVault".into(),
            title: "Verify Vault".into(),
            description: Some("Check vault integrity".into()),
            keywords: vec!["verify".into(), "vault".into(), "integrity".into()],
            source: "builtin".into(),
        },
    ];
    let mut first_error: Option<String> = None;
    for command in commands {
        if let Err(e) = register_command(command) {
            first_error = Some(e);
        }
    }
    *registered = true;
    first_error.map_or(Ok(()), Err)
}

/// Fuzzy-match a query against a command.
///
/// Returns a score (higher = better match) or `None` if the query doesn't
/// match at all. The algorithm is a simple contiguous-subsequence match:
/// each query character must appear in order in the target, with bonuses
/// for consecutive matches and matches at word boundaries.
fn fuzzy_score(target: &str, query: &str) -> Option<i32> {
    if query.is_empty() {
        return Some(0);
    }
    let query_lower = query.to_lowercase();
    let target_lower = target.to_lowercase();

    let mut query_idx = 0;
    let mut score: i32 = 0;
    let mut prev_matched = false;

    for (i, ch) in target_lower.char_indices() {
        if query_idx >= query_lower.len() {
            break;
        }
        if ch == query_lower.chars().nth(query_idx).unwrap() {
            query_idx += 1;
            score += 10;
            if prev_matched {
                score += 5; // consecutive match bonus
            }
            // Word boundary bonus: match at start or after a separator.
            if i == 0 || !target_lower[..i].chars().last().unwrap().is_alphanumeric() {
                score += 15;
            }
            prev_matched = true;
        } else {
            prev_matched = false;
        }
    }

    if query_idx == query_lower.len() {
        Some(score)
    } else {
        None
    }
}

/// Filter and score commands against a query.
pub fn filter_commands(query: &str) -> Vec<(Command, i32)> {
    let query = query.trim();
    if query.is_empty() {
        return list_commands()
            .into_iter()
            .map(|c| (c, 0))
            .collect();
    }

    let mut results: Vec<(Command, i32)> = Vec::new();
    for command in list_commands() {
        let mut best: Option<i32> = None;

        // Score against title.
        if let Some(s) = fuzzy_score(&command.title, query) {
            best = Some(s.max(best.unwrap_or(0)));
        }
        // Score against description.
        if let Some(desc) = &command.description {
            if let Some(s) = fuzzy_score(desc, query) {
                best = Some(s.max(best.unwrap_or(0)));
            }
        }
        // Score against keywords.
        for keyword in &command.keywords {
            if let Some(s) = fuzzy_score(keyword, query) {
                best = Some(s.max(best.unwrap_or(0)));
            }
        }

        if let Some(score) = best {
            results.push((command, score));
        }
    }

    results.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.id.cmp(&b.0.id)));
    results
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_register_and_list_builtin_commands() {
        // Built-in commands are registered via lazy_static on first use;
        // call register_builtin_commands explicitly for a clean test.
        register_builtin_commands().unwrap();
        let commands = list_commands();
        assert!(!commands.is_empty());
        assert!(commands.iter().any(|c| c.id == "journal.openDailyNote"));
        assert!(commands.iter().any(|c| c.id == "sync.syncNow"));
    }

    #[test]
    fn test_fuzzy_score_matches() {
        assert_eq!(fuzzy_score("Open Daily Note", "odn"), Some(75));
        assert_eq!(fuzzy_score("Open Daily Note", "daily"), Some(85));
        assert_eq!(fuzzy_score("Open Daily Note", "xyz"), None);
    }

    #[test]
    fn test_filter_commands() {
        register_builtin_commands().unwrap();
        let results = filter_commands("daily");
        assert!(!results.is_empty());
        let ids: Vec<&str> = results.iter().map(|(c, _)| c.id.as_str()).collect();
        assert!(ids.contains(&"journal.openDailyNote"));
        assert!(ids.contains(&"capture.newDailyNote"));
    }

    #[test]
    fn test_filter_commands_empty_query() {
        register_builtin_commands().unwrap();
        let results = filter_commands("");
        assert!(!results.is_empty());
        // Empty query returns all commands with score 0.
        assert!(results.iter().all(|(_, score)| *score == 0));
    }

    #[test]
    fn test_command_registration_conflict() {
        register_command(Command {
            id: "test.unique".into(),
            title: "Test".into(),
            description: None,
            keywords: vec![],
            source: "test".into(),
        })
        .unwrap();
        assert!(register_command(Command {
            id: "test.unique".into(),
            title: "Test Again".into(),
            description: None,
            keywords: vec![],
            source: "test".into(),
        })
        .is_err());
        unregister_commands_from("test");
    }
}
