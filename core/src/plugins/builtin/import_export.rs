use super::super::{NoteContext, Plugin};

pub struct ImportExportPlugin;

impl Plugin for ImportExportPlugin {
    fn on_note(&self, _note: &NoteContext<'_>) -> Option<String> {
        None
    }

    fn on_export(&self, note: &NoteContext<'_>) -> Option<Vec<u8>> {
        if note.body.trim_start().starts_with('#') {
            Some(note.body.as_bytes().to_vec())
        } else {
            Some(format!("# {}\n\n{}", note.title, note.body).into_bytes())
        }
    }
}
