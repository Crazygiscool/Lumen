/// A Markdown note passed to plugins. Plugins never see the encrypted bytes.
pub struct NoteContext<'a> {
    /// Stable identifier: the note's path inside the journal store.
    pub id: &'a str,
    pub title: &'a str,
    pub body: &'a str,
}

pub trait Plugin: Send + Sync {
    /// Called after a note is saved. Return a short message to surface in the UI.
    fn on_note(&self, note: &NoteContext<'_>) -> Option<String>;

    /// Optional export rendering (used by the export_md built-in).
    fn on_export(&self, note: &NoteContext<'_>) -> Option<Vec<u8>> {
        let _ = note;
        None
    }
}
