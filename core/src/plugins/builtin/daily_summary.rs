use super::super::{NoteContext, Plugin};

pub struct DailySummaryPlugin;

impl Plugin for DailySummaryPlugin {
    fn on_note(&self, note: &NoteContext<'_>) -> Option<String> {
        let words = note.body.split_whitespace().count();
        Some(format!("[daily_summary] {} — {} words", note.title, words))
    }
}
