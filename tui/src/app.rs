//! The interactive half of the terminal client.
//!
//! The browser shows the notes in the journal and lets the user move
//! through them, search, follow links and edit. Everything that needs the
//! terminal to itself — the editor — is handed back to the event loop, which
//! releases the screen for the duration of the edit.

use std::io;
use std::time::Duration;

use chrono::Local;
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind};
use crossterm::execute;
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use ratatui::backend::CrosstermBackend;
use ratatui::widgets::ListState;
use ratatui::Terminal;

use lumen_core::config;
use lumen_core::frontmatter;
use lumen_core::query;
use lumen_core::search;
use lumen_core::template;
use lumen_core::vault::{self, STORE_JOURNAL};
use lumen_core::wikilinks;

use crate::cli::{edit_in_editor, entries, read_entry, title_of};
use crate::ui;

/// What the client is doing right now.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    /// The journal list.
    Browse,
    /// Live search: the list shows the matches as they are typed.
    Search,
    /// The notes that link to the selected note.
    Backlinks,
    /// The fuzzy picker for a wikilink target.
    LinkPicker,
    /// A command line, started with `:`.
    Command,
}

/// A row in the list pane.
#[derive(Debug, Clone)]
pub struct Row {
    /// The note the row points at.
    pub path: String,
    /// The title shown next to the path.
    pub title: String,
}

/// An edit that needs the terminal to itself.
#[derive(Debug, Clone)]
pub enum Edit {
    /// The body of a note.
    Body { path: String, initial: String },
    /// The frontmatter of a note, as YAML.
    Frontmatter { path: String, yaml: String },
}

/// The keys the browser answers to.
const HELP: &str = "\
j / k      move through the list
e          edit the note in $EDITOR
n          new daily note (from the template)
f          edit the note's frontmatter
/          live search
b          backlinks of the note
[          insert a wikilink
:          command line (:frontmatter, :daily, :help)
r          reload
q          quit";

/// The state of the browser.
pub struct App {
    /// Every note in the journal.
    notes: Vec<Row>,
    /// The rows the list pane shows.
    pub rows: Vec<Row>,
    /// The selection in the list pane.
    pub state: ListState,
    /// The body shown in the preview pane.
    pub preview: String,
    /// The title of the preview.
    pub preview_title: String,
    /// What the client is doing right now.
    pub mode: Mode,
    /// The text being typed.
    pub input: String,
    /// The message shown under the panes.
    pub status: String,
    /// The note a wikilink is inserted into.
    link_source: Option<String>,
    /// The note the list was showing before an input mode was entered.
    origin: Option<String>,
    /// Whether the client should stop.
    pub quit: bool,
}

impl App {
    /// Read the journal and build the browser.
    pub fn new() -> color_eyre::Result<Self> {
        let mut app = App {
            notes: Vec::new(),
            rows: Vec::new(),
            state: ListState::default(),
            preview: String::new(),
            preview_title: String::new(),
            mode: Mode::Browse,
            input: String::new(),
            status: String::new(),
            link_source: None,
            origin: None,
            quit: false,
        };
        app.reload()?;
        Ok(app)
    }

    /// Read the journal again.
    pub fn reload(&mut self) -> color_eyre::Result<()> {
        let selected = self.selected_path();
        self.notes = notes()?;
        self.show_notes();
        if let Some(path) = selected {
            self.select_path(&path);
        }
        self.load_preview();
        Ok(())
    }

    /// The title of the list pane.
    pub fn list_title(&self) -> String {
        match self.mode {
            Mode::Browse => " Journal  [n]ew  [e]dit  [/]search  [b]acklinks  [q]uit ".to_string(),
            Mode::Search => " Search ".to_string(),
            Mode::Backlinks => " Backlinks ".to_string(),
            Mode::LinkPicker => " Link picker ".to_string(),
            Mode::Command => " Command ".to_string(),
        }
    }

    /// The line under the panes: the prompt, the message, or both.
    pub fn input_line(&self) -> String {
        let prompt = match self.mode {
            Mode::Search => format!("/{}", self.input),
            Mode::LinkPicker => format!("[[{}", self.input),
            Mode::Command => format!(":{}", self.input),
            _ => String::new(),
        };

        if prompt.is_empty() {
            self.status.clone()
        } else if self.status.is_empty() {
            prompt
        } else {
            format!("{prompt}   {}", self.status)
        }
    }

    /// Handle a key press.
    ///
    /// An edit that needs the terminal is handed back, so the event loop can
    /// release the screen before the editor runs.
    pub fn on_key(&mut self, key: KeyEvent) -> color_eyre::Result<Option<Edit>> {
        match self.mode {
            Mode::Browse => self.on_browse_key(key),
            Mode::Search => self.on_search_key(key),
            Mode::Backlinks => self.on_backlinks_key(key),
            Mode::LinkPicker => self.on_picker_key(key),
            Mode::Command => self.on_command_key(key),
        }
    }

    // --- The journal list ---------------------------------------------------

    fn on_browse_key(&mut self, key: KeyEvent) -> color_eyre::Result<Option<Edit>> {
        match key.code {
            KeyCode::Char('q') | KeyCode::Esc => self.quit = true,
            KeyCode::Down | KeyCode::Char('j') => self.move_by(1),
            KeyCode::Up | KeyCode::Char('k') => self.move_by(-1),
            KeyCode::Char('n') => return self.new_today(),
            KeyCode::Char('e') | KeyCode::Enter => return self.edit_selected(),
            KeyCode::Char('r') => self.reload()?,
            KeyCode::Char('/') => self.start_search(),
            KeyCode::Char('b') => self.show_backlinks(),
            KeyCode::Char('[') => self.start_link_picker(),
            KeyCode::Char(':') => self.start_command(),
            KeyCode::Char('f') => return self.edit_frontmatter(),
            _ => {}
        }
        Ok(None)
    }

    fn on_search_key(&mut self, key: KeyEvent) -> color_eyre::Result<Option<Edit>> {
        match key.code {
            KeyCode::Esc => self.leave_input(),
            KeyCode::Enter => self.accept_result(),
            KeyCode::Backspace => {
                self.input.pop();
                self.run_search();
            }
            KeyCode::Char(c) => {
                self.input.push(c);
                self.run_search();
            }
            KeyCode::Down => self.move_by(1),
            KeyCode::Up => self.move_by(-1),
            _ => {}
        }
        Ok(None)
    }

    fn on_backlinks_key(&mut self, key: KeyEvent) -> color_eyre::Result<Option<Edit>> {
        match key.code {
            KeyCode::Esc | KeyCode::Char('b') => self.leave_input(),
            KeyCode::Enter => self.accept_result(),
            KeyCode::Down | KeyCode::Char('j') => self.move_by(1),
            KeyCode::Up | KeyCode::Char('k') => self.move_by(-1),
            _ => {}
        }
        Ok(None)
    }

    fn on_picker_key(&mut self, key: KeyEvent) -> color_eyre::Result<Option<Edit>> {
        match key.code {
            KeyCode::Esc => self.leave_input(),
            KeyCode::Enter => return self.insert_link(),
            KeyCode::Backspace => {
                self.input.pop();
                self.run_picker();
            }
            KeyCode::Char(c) => {
                self.input.push(c);
                self.run_picker();
            }
            KeyCode::Down => self.move_by(1),
            KeyCode::Up => self.move_by(-1),
            _ => {}
        }
        Ok(None)
    }

    fn on_command_key(&mut self, key: KeyEvent) -> color_eyre::Result<Option<Edit>> {
        match key.code {
            KeyCode::Esc => self.leave_input(),
            KeyCode::Enter => return self.run_command(),
            KeyCode::Backspace => {
                self.input.pop();
            }
            KeyCode::Char(c) => self.input.push(c),
            _ => {}
        }
        Ok(None)
    }

    // --- The list ------------------------------------------------------------

    /// Show every note in the list.
    fn show_notes(&mut self) {
        self.rows = self.notes.clone();
        if self.rows.is_empty() {
            self.state.select(None);
        } else {
            let index = self.state.selected().unwrap_or(0).min(self.rows.len() - 1);
            self.state.select(Some(index));
        }
    }

    /// Put the cursor on a note, if it is in the list.
    fn select_path(&mut self, path: &str) {
        if let Some(index) = self.rows.iter().position(|row| row.path == path) {
            self.state.select(Some(index));
        }
    }

    /// The note the cursor is on.
    pub fn selected_path(&self) -> Option<String> {
        self.state
            .selected()
            .and_then(|i| self.rows.get(i))
            .map(|row| row.path.clone())
    }

    fn move_by(&mut self, delta: i64) {
        if self.rows.is_empty() {
            return;
        }
        let len = self.rows.len() as i64;
        let current = self.state.selected().unwrap_or(0) as i64;
        let next = (current + delta).rem_euclid(len);
        self.state.select(Some(next as usize));
        self.load_preview();
    }

    fn load_preview(&mut self) {
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
    }

    /// Rows for a list of note paths, newest first.
    fn rows_for_paths(&self, paths: &[String]) -> Vec<Row> {
        let mut rows: Vec<Row> = paths
            .iter()
            .filter_map(|path| self.notes.iter().find(|row| &row.path == path).cloned())
            .collect();
        rows.sort_by(|a, b| b.path.cmp(&a.path));
        rows
    }

    // --- Input modes ---------------------------------------------------------

    /// Enter an input mode, remembering where the list came from.
    fn begin_input(&mut self, mode: Mode) {
        self.origin = self.selected_path();
        self.mode = mode;
        self.input.clear();
    }

    /// Leave an input mode and go back to the journal list.
    fn leave_input(&mut self) {
        self.mode = Mode::Browse;
        self.input.clear();
        self.show_notes();
        if let Some(path) = self.origin.take() {
            self.select_path(&path);
        }
        self.load_preview();
    }

    /// Open the note the cursor is on.
    fn accept_result(&mut self) {
        let path = self.selected_path();
        // The input mode is left even when there was nothing to open, so
        // the search does not keep the keys the user meant for the list.
        self.leave_input();
        if let Some(path) = path {
            self.select_path(&path);
            self.load_preview();
        }
    }

    // --- Search --------------------------------------------------------------

    fn start_search(&mut self) {
        self.begin_input(Mode::Search);
        self.run_search();
    }

    /// Search the journal and show the matches.
    ///
    /// Plain words are a question for the full-text index. A filter — a tag,
    /// a field, a date — is a question for the notes themselves, because
    /// only they know what metadata they carry.
    fn run_search(&mut self) {
        let text = self.input.trim().to_string();
        if text.is_empty() {
            self.rows = self.notes.clone();
            self.select_first();
            self.status.clear();
            self.load_preview();
            return;
        }

        let parsed = query::parse(&text);
        let paths = if parsed.has_filters() {
            query::query_entries(STORE_JOURNAL, &parsed)
        } else if config::get_config().search.enabled {
            match search::search_entries(STORE_JOURNAL, &text, 50) {
                Ok(hits) => {
                    self.rows = hits
                        .into_iter()
                        .map(|hit| Row {
                            title: if hit.title.is_empty() {
                                stem(&hit.path).to_string()
                            } else {
                                hit.title
                            },
                            path: hit.path,
                        })
                        .collect();
                    self.select_first();
                    self.status = format!("{} match(es)", self.rows.len());
                    self.load_preview();
                    return;
                }
                Err(e) => {
                    // The index cannot answer every query — a bare `+` or an
                    // unbalanced quote, say — so the notes are read instead.
                    self.status =
                        format!("The index could not answer that ({e}); reading the notes.");
                    query::query_entries(STORE_JOURNAL, &parsed)
                }
            }
        } else {
            query::query_entries(STORE_JOURNAL, &parsed)
        };

        match paths {
            Ok(paths) => {
                self.rows = self.rows_for_paths(&paths);
                self.select_first();
                self.status = format!("{} match(es)", self.rows.len());
                self.load_preview();
            }
            Err(e) => self.fail(e),
        }
    }

    fn fail(&mut self, message: String) {
        self.rows.clear();
        self.state.select(None);
        self.status = message;
        self.load_preview();
    }

    fn select_first(&mut self) {
        self.state
            .select(if self.rows.is_empty() { None } else { Some(0) });
    }

    // --- Backlinks -----------------------------------------------------------

    /// Show the notes that link to the selected note.
    fn show_backlinks(&mut self) {
        let Some(path) = self.selected_path() else {
            self.status = "No note is selected.".into();
            return;
        };
        let links = wikilinks::get_backlinks(STORE_JOURNAL, &path);
        self.begin_input(Mode::Backlinks);
        self.rows = self.rows_for_paths(&links);
        self.select_first();
        self.status = if self.rows.is_empty() {
            format!("Nothing links to {path}.")
        } else {
            format!("{} note(s) link to {path}.", self.rows.len())
        };
        self.load_preview();
    }

    // --- Wikilinks -----------------------------------------------------------

    /// Open the picker for a wikilink target.
    fn start_link_picker(&mut self) {
        let Some(path) = self.selected_path() else {
            self.status = "No note is selected.".into();
            return;
        };
        self.link_source = Some(path);
        self.begin_input(Mode::LinkPicker);
        self.run_picker();
    }

    /// Filter the notes by what has been typed.
    fn run_picker(&mut self) {
        let text = self.input.trim();
        let mut scored: Vec<(i32, Row)> = self
            .notes
            .iter()
            .filter_map(|row| {
                let score = match (
                    fuzzy_score(text, stem(&row.path))
                        .into_iter()
                        .chain(fuzzy_score(text, &row.path))
                        .max(),
                    fuzzy_score(text, &row.title),
                ) {
                    (Some(name), Some(title)) => Some(name.min(title - 5)),
                    (Some(name), None) => Some(name),
                    (None, Some(title)) => Some(title),
                    (None, None) => None,
                }?;
                Some((score, row.clone()))
            })
            .collect();
        scored.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.path.cmp(&b.1.path)));
        self.rows = scored.into_iter().map(|(_, row)| row).collect();
        self.select_first();
        self.status = format!("{} match(es)", self.rows.len());
        self.load_preview();
    }

    /// Insert a wikilink to the picked note into the note it was picked from.
    fn insert_link(&mut self) -> color_eyre::Result<Option<Edit>> {
        let target = self.selected_path();
        let source = self.link_source.clone();

        let (Some(target), Some(source)) = (target, source) else {
            // Nothing was picked, so the picker is left as it was found.
            self.leave_input();
            return Ok(None);
        };

        // The name of the file is the link, so the link always resolves to
        // the note it points at.
        let name = stem(&target).to_string();
        let mut body = read_entry(&source)?;
        if !body.ends_with('\n') {
            body.push('\n');
        }
        body.push_str(&format!("\n[[{name}]]\n"));
        vault::write_text(&source, &body, STORE_JOURNAL).map_err(|e| color_eyre::eyre::eyre!(e))?;

        self.status = format!("Linked {source} to {name}.");
        self.leave_input();
        self.reload()?;
        Ok(None)
    }

    // --- Commands ------------------------------------------------------------

    fn start_command(&mut self) {
        self.begin_input(Mode::Command);
        self.status.clear();
    }

    /// Run the command that was typed.
    fn run_command(&mut self) -> color_eyre::Result<Option<Edit>> {
        let command = self.input.trim().to_string();
        self.leave_input();
        match command.as_str() {
            "frontmatter" => return self.edit_frontmatter(),
            "daily" => return self.new_today(),
            "help" => self.show_help(),
            "quit" | "q" => self.quit = true,
            "" => {}
            other => self.status = format!("Unknown command {other:?}. Try :help."),
        }
        Ok(None)
    }

    fn show_help(&mut self) {
        self.preview_title = "Keys".into();
        self.preview = HELP.to_string();
        self.status.clear();
    }

    // --- Editing -------------------------------------------------------------

    /// Start today's daily note, from the template when the day has none.
    fn new_today(&mut self) -> color_eyre::Result<Option<Edit>> {
        let date = Local::now().date_naive();
        let path = template::daily_note_path(date);
        let initial = match vault::read_text(&path, STORE_JOURNAL) {
            Ok(text) => text,
            Err(_) => {
                // A new day starts from the template.
                let text = template::render_daily_template(date);
                vault::write_text(&path, &text, STORE_JOURNAL)
                    .map_err(|e| color_eyre::eyre::eyre!(e))?;
                text
            }
        };
        Ok(Some(Edit::Body { path, initial }))
    }

    /// Edit the note the cursor is on.
    fn edit_selected(&mut self) -> color_eyre::Result<Option<Edit>> {
        let Some(path) = self.selected_path() else {
            return Ok(None);
        };
        let initial = read_entry(&path)?;
        Ok(Some(Edit::Body { path, initial }))
    }

    /// Edit the frontmatter of the note the cursor is on.
    fn edit_frontmatter(&mut self) -> color_eyre::Result<Option<Edit>> {
        let Some(path) = self.selected_path() else {
            self.status = "No note is selected.".into();
            return Ok(None);
        };
        let body = read_entry(&path)?;
        let (fm, _) = frontmatter::parse_frontmatter(&body);
        let yaml = frontmatter::frontmatter_to_yaml(&fm);
        Ok(Some(Edit::Frontmatter { path, yaml }))
    }
}

/// Every note in the journal, newest first.
fn notes() -> color_eyre::Result<Vec<Row>> {
    Ok(entries()?
        .into_iter()
        .map(|entry| {
            let title = read_entry(&entry.rel_path)
                .map(|body| title_of(&body, &entry.name))
                .unwrap_or_else(|_| entry.name.clone());
            Row {
                path: entry.rel_path,
                title,
            }
        })
        .collect())
}

/// The name of a note without its extension.
fn stem(path: &str) -> &str {
    path.strip_suffix(".md")
        .or_else(|| path.strip_suffix(".markdown"))
        .unwrap_or(path)
}

/// Score a fuzzy match: the lower the score the better, `None` when the
/// candidate does not hold the query at all.
pub fn fuzzy_score(query: &str, candidate: &str) -> Option<i32> {
    if query.is_empty() {
        return Some(0);
    }

    let needle: Vec<char> = query.to_lowercase().chars().collect();
    let haystack: Vec<char> = candidate.to_lowercase().chars().collect();

    // The score counts how well the candidate matched; the length is taken
    // off it at the end, so a shorter candidate wins a tie.
    let mut matched = 0i32;
    let mut at = 0usize;
    let mut previous: Option<usize> = None;

    for c in needle {
        let found = haystack[at..].iter().position(|h| *h == c)? + at;
        matched += 10;
        if let Some(prev) = previous {
            // A run of letters is worth more than letters scattered about.
            if found == prev + 1 {
                matched += 15;
            } else {
                matched -= 5;
            }
        }
        // A match at the start of a word is worth more than one in the middle.
        if found == 0 || !haystack[found - 1].is_alphanumeric() {
            matched += 10;
        }
        previous = Some(found);
        at = found + 1;
    }

    Some(haystack.len() as i32 - matched)
}

/// Run the interactive browser.
pub fn run_tui() -> color_eyre::Result<()> {
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

fn event_loop(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
) -> color_eyre::Result<()> {
    loop {
        terminal.draw(|frame| ui::draw(frame, app))?;

        if event::poll(Duration::from_millis(200))? {
            if let Event::Key(key) = event::read()? {
                if key.kind != KeyEventKind::Press {
                    continue;
                }
                if let Some(edit) = app.on_key(key)? {
                    // The editor wants the terminal to itself.
                    release_terminal(terminal)?;
                    let result = apply_edit(app, edit);
                    take_terminal(terminal)?;
                    result?;
                }
                if app.quit {
                    return Ok(());
                }
            }
        }
    }
}

/// Hand the terminal back to the shell.
fn release_terminal(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
) -> color_eyre::Result<()> {
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;
    Ok(())
}

/// Take the terminal back from the shell.
fn take_terminal(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>) -> color_eyre::Result<()> {
    enable_raw_mode()?;
    execute!(terminal.backend_mut(), EnterAlternateScreen)?;
    terminal.hide_cursor()?;
    Ok(())
}

/// Run an edit and put the result back in the journal.
fn apply_edit(app: &mut App, edit: Edit) -> color_eyre::Result<()> {
    match edit {
        Edit::Body { path, initial } => match edit_in_editor(&initial, "edit.md")? {
            Some(text) => {
                vault::write_text(&path, &text, STORE_JOURNAL)
                    .map_err(|e| color_eyre::eyre::eyre!(e))?;
                app.status = format!("Saved {path}.");
            }
            None => app.status = "No changes.".into(),
        },
        Edit::Frontmatter { path, yaml } => match edit_in_editor(&yaml, "frontmatter.yaml")? {
            Some(text) => match frontmatter::frontmatter_from_yaml(&text) {
                Ok(fm) => {
                    frontmatter::write_frontmatter(STORE_JOURNAL, &path, &fm)
                        .map_err(|e| color_eyre::eyre::eyre!(e))?;
                    app.status = format!("Frontmatter of {path} updated.");
                }
                Err(e) => app.status = format!("The frontmatter was not saved: {e}"),
            },
            None => app.status = "No changes.".into(),
        },
    }
    app.reload()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fuzzy_score_prefers_a_closer_match() {
        let close = fuzzy_score("note", "notes.md").unwrap();
        let scattered = fuzzy_score("note", "n-o-t-e.md").unwrap();
        assert!(close < scattered);
    }

    #[test]
    fn test_fuzzy_score_prefers_a_word_start() {
        let word = fuzzy_score("ab", "a big.md").unwrap();
        let middle = fuzzy_score("ab", "xa yb.md").unwrap();
        assert!(word < middle);
    }

    #[test]
    fn test_fuzzy_score_prefers_a_shorter_name() {
        let short = fuzzy_score("note", "notes.md").unwrap();
        let long = fuzzy_score("note", "my notes.md").unwrap();
        assert!(short < long);
    }

    #[test]
    fn test_fuzzy_score_needs_every_letter() {
        assert!(fuzzy_score("note", "notes.md").is_some());
        assert!(fuzzy_score("xyz", "notes.md").is_none());
    }

    #[test]
    fn test_fuzzy_score_of_an_empty_query() {
        assert_eq!(fuzzy_score("", "notes.md"), Some(0));
    }

    #[test]
    fn test_stem_drops_the_extension() {
        assert_eq!(stem("2026-02-03.md"), "2026-02-03");
        assert_eq!(stem("My Note.markdown"), "My Note");
        assert_eq!(stem("plain"), "plain");
    }
}
