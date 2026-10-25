use super::super::{NoteContext, Plugin};

pub struct DashboardEntriesPlugin;

impl Plugin for DashboardEntriesPlugin {
    fn on_note(&self, _note: &NoteContext<'_>) -> Option<String> {
        None
    }
}
