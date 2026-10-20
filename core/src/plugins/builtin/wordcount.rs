use super::super::{NoteContext, Plugin};

pub struct WordCountPlugin;

impl Plugin for WordCountPlugin {
    fn on_note(&self, note: &NoteContext<'_>) -> Option<String> {
        let words = note.body.split_whitespace().count();
        Some(format!("[wordcount] {words} words"))
    }
}
