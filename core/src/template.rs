//! Daily note template rendering.

use std::fs;
use std::path::PathBuf;

use chrono::{Duration, Local, NaiveDate, Datelike};

use crate::config;

/// Placeholder keys for template substitution.
const PLACEHOLDERS: &[(&str, fn(NaiveDate) -> String)] = &[
    ("{{date}}", |d| d.format("%Y-%m-%d").to_string()),
    ("{{time}}", |_| Local::now().format("%H:%M").to_string()),
    ("{{yesterday}}", |d| (d - Duration::days(1)).format("%Y-%m-%d").to_string()),
    ("{{tomorrow}}", |d| (d + Duration::days(1)).format("%Y-%m-%d").to_string()),
    ("{{week}}", |d| format!("{}-W{:02}", d.year(), d.iso_week().week())),
    ("{{month}}", |d| d.format("%Y-%m").to_string()),
    ("{{iso_week}}", |d| format!("{}-W{:02}", d.year(), d.iso_week().week())),
];

/// Get the path to the daily template file.
fn template_path() -> PathBuf {
    config::daily_template_path()
}

/// Render the daily template for a given date.
pub fn render_daily_template(date: NaiveDate) -> String {
    let template_path = template_path();

    let template = fs::read_to_string(&template_path).unwrap_or_else(|_| default_template());

    let mut result = template;

    // Simple placeholders
    for (key, func) in PLACEHOLDERS {
        let value = func(date);
        result = result.replace(key, &value);
    }

    // Date format placeholder: {{date:%Y-%m-%d}} or {{date:%A, %B %d}}
    let date_format_regex = regex::Regex::new(r"\{\{date:([^}]+)\}\}").unwrap();
    result = date_format_regex
        .replace_all(&result, |caps: &regex::Captures| {
            let format_str = &caps[1];
            date.format(format_str).to_string()
        })
        .to_string();

    result
}

/// Get the vault path for a daily note.
pub fn daily_note_path(date: NaiveDate) -> String {
    format!("{}.md", date.format("%Y-%m-%d"))
}

/// Get the default daily template.
fn default_template() -> String {
    r#"# {{date}}

## Morning
- Intention:
- Priorities:

## Evening
- Reflection:
- Tomorrow:

---
*Tags: daily*# "#
        .to_string()
}

/// Ensure the template file exists (create default if missing).
pub fn ensure_template_exists() -> std::io::Result<()> {
    let path = template_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    if !path.exists() {
        fs::write(&path, default_template())?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::NaiveDate;

    #[test]
    fn test_daily_note_path() {
        let date = NaiveDate::from_ymd_opt(2026, 2, 3).unwrap();
        assert_eq!(daily_note_path(date), "2026-02-03.md");
    }

    #[test]
    fn test_render_placeholders() {
        let date = NaiveDate::from_ymd_opt(2026, 2, 3).unwrap();
        let template = "# {{date}}\n\n{{yesterday}} -> {{tomorrow}}\nWeek: {{week}}";
        let result = render_daily_template_for_test(date, template);

        assert!(result.contains("2026-02-03"));
        assert!(result.contains("2026-02-02"));
        assert!(result.contains("2026-02-04"));
        assert!(result.contains("2026-W"));
    }

    // Helper for testing with custom template
    fn render_daily_template_for_test(date: NaiveDate, template: &str) -> String {
        let mut result = template.to_string();
        for (key, func) in PLACEHOLDERS {
            let value = func(date);
            result = result.replace(key, &value);
        }
        let date_format_regex = regex::Regex::new(r"\{\{date:([^}]+)\}\}").unwrap();
        result = date_format_regex
            .replace_all(&result, |caps: &regex::Captures| {
                let format_str = &caps[1];
                date.format(format_str).to_string()
            })
            .to_string();
        result
    }

    #[test]
    fn test_date_format_placeholder() {
        let date = NaiveDate::from_ymd_opt(2026, 2, 3).unwrap();
        let template = "Formatted: {{date:%A, %B %d, %Y}}";
        let result = render_daily_template_for_test(date, template);
        assert!(result.contains("Tuesday, February 03, 2026"));
    }
}