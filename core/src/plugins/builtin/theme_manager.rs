use super::super::{NoteContext, Plugin};

pub struct ThemeManagerPlugin;

impl Plugin for ThemeManagerPlugin {
    fn on_note(&self, _note: &NoteContext<'_>) -> Option<String> {
        None
    }
}
