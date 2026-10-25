use super::super::{NoteContext, Plugin};

pub struct ImportExportPlugin;

impl Plugin for ImportExportPlugin {
    fn on_note(&self, _note: &NoteContext<'_>) -> Option<String> {
        None
    }
}
