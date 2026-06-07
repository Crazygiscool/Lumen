use chrono::{NaiveDate, Utc};

use crate::entry::{EntryKind, JournalEntry};
use crate::storage::Storage;

pub fn process_recurring(storage: &Storage) -> Result<u32, String> {
    let tasks = storage.list_recurring_tasks()?;
    let today = Utc::now().date_naive();
    let mut count = 0u32;

    for task in tasks {
        let next_due_str = match task.get("next_due") {
            Some(v) => v.as_str().unwrap_or(""),
            None => continue,
        };
        let next_due = match NaiveDate::parse_from_str(next_due_str, "%Y-%m-%d") {
            Ok(d) => d,
            Err(_) => continue,
        };

        if next_due > today {
            continue;
        }

        // Generate a child entry of kind=task
        let id = generate_id();
        let title = task.get("title").and_then(|v| v.as_str()).unwrap_or("");
        let priority = task
            .get("priority")
            .and_then(|v| v.as_str())
            .unwrap_or("medium");
        let tags_str = task.get("tags").and_then(|v| v.as_str()).unwrap_or("[]");
        let project_id = task.get("project_id").and_then(|v| v.as_str());
        let task_id = task.get("id").and_then(|v| v.as_str()).unwrap_or("");

        let tags: Vec<String> = serde_json::from_str(tags_str).unwrap_or_default();

        let entry = JournalEntry {
            id: id.clone(),
            encrypted: Vec::new(),
            nonce: Vec::new(),
            salt: Vec::new(),
            assets: Vec::new(),
            provenance: crate::entry::Provenance {
                timestamp: Utc::now(),
                plugin_origin: Some("recurring".to_string()),
                author: "system".to_string(),
                feedback: None,
                metadata: serde_json::json!({}),
            },
            kind: EntryKind::Task,
            tags,
            display_title: title.to_string(),
            pinned: false,
            mood: None,
            priority: Some(priority.to_string()),
            status: Some("todo".to_string()),
            due_date: Some(next_due.to_string()),
            parent_project_id: project_id.map(|s| s.to_string()),
            history: Vec::new(),
        };

        storage.add_entry(&entry)?;

        // Compute next due date
        let new_next_due = compute_next_due(&next_due, &task);
        storage.update_recurring_task_next_due(task_id, &new_next_due.to_string())?;

        count += 1;
    }

    Ok(count)
}

fn generate_id() -> String {
    let ts = Utc::now().timestamp();
    let rand_part: u32 = rand::random();
    format!("{}_{:08x}", ts, rand_part)
}

fn compute_next_due(current: &NaiveDate, task: &serde_json::Value) -> NaiveDate {
    if let Some(days) = task.get("every_n_days").and_then(|v| v.as_i64()) {
        if let Some(next) = current.checked_add_signed(chrono::Duration::days(days)) {
            return next;
        }
    }
    if let Some(_dow) = task.get("day_of_week").and_then(|v| v.as_i64()) {
        // Add 7 days for weekly recurrence
        if let Some(next) = current.checked_add_signed(chrono::Duration::days(7)) {
            return next;
        }
    }
    // Default: add 1 day
    current
        .checked_add_signed(chrono::Duration::days(1))
        .unwrap_or(*current)
}
