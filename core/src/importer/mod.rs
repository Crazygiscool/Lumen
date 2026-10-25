//! Importers for bringing existing journals into Lumen's encrypted store.
//!
//! Imports write Markdown files through [`crate::vault`], so the journal store
//! must be unlocked first. Nothing is ever written in plaintext.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use rand::rngs::OsRng;
use rand::RngCore;
use serde::de::DeserializeOwned;
use serde::Serialize;

use crate::vault;

#[derive(Debug, Default, Clone, Serialize)]
pub struct ImportResult {
    pub imported: usize,
    pub skipped: usize,
}

fn require_unlocked(store: &str) -> Result<(), String> {
    if vault::is_unlocked(store) {
        Ok(())
    } else {
        Err("Unlock the journal before importing".into())
    }
}

fn existing_files(store: &str) -> Result<HashSet<String>, String> {
    let mut out = HashSet::new();
    for entry in vault::list("", store)? {
        if !entry.is_dir {
            out.insert(entry.rel_path);
        }
    }
    Ok(out)
}

fn unique_name(existing: &mut HashSet<String>, desired: &str) -> String {
    let desired = desired.trim_start_matches('/').to_string();
    if existing.insert(desired.clone()) {
        return desired;
    }

    let path = Path::new(&desired);
    let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("entry");
    let ext = path.extension().and_then(|s| s.to_str()).unwrap_or("md");
    let parent = path.parent().filter(|p| !p.as_os_str().is_empty());

    for n in 2.. {
        let name = format!("{stem}-{n}.{ext}");
        let candidate = match parent {
            Some(p) => format!("{}/{}", p.to_string_lossy().replace('\\', "/"), name),
            None => name,
        };
        if existing.insert(candidate.clone()) {
            return candidate;
        }
    }
    unreachable!()
}

fn write_note(
    existing: &mut HashSet<String>,
    desired: &str,
    body: &str,
    store: &str,
    result: &mut ImportResult,
) -> Result<(), String> {
    let name = unique_name(existing, desired);
    vault::write_text(&name, body, store)?;
    result.imported += 1;
    Ok(())
}

fn slug(text: &str) -> String {
    let mut out = String::new();
    for ch in text.chars() {
        if ch.is_alphanumeric() {
            for c in ch.to_lowercase() {
                out.push(c);
            }
        } else if !out.ends_with('-') {
            out.push('-');
        }
        if out.len() >= 48 {
            break;
        }
    }
    let out = out.trim_matches('-').to_string();
    if out.is_empty() {
        "entry".into()
    } else {
        out
    }
}

fn is_heading(body: &str) -> bool {
    body.trim_start().starts_with('#')
}

fn with_title(body: &str, title: &str) -> String {
    let body = body.trim_start_matches(['\r', '\n']);
    if title.trim().is_empty() {
        return body.to_string();
    }
    if is_heading(body) {
        return body.to_string();
    }
    format!("# {}\n\n{}", title.trim(), body)
}

fn short_id(id: &str) -> String {
    let compact: String = id.chars().filter(|c| c.is_ascii_alphanumeric()).collect();
    let short: String = compact.chars().take(8).collect();
    if short.is_empty() {
        let mut bytes = [0u8; 4];
        OsRng.fill_bytes(&mut bytes);
        format!("{:08x}", u32::from_le_bytes(bytes))
    } else {
        short
    }
}

fn parse_date(raw: &str) -> Option<String> {
    let trimmed = raw.trim().replace('\\', "");
    let parts: Vec<&str> = trimmed.split('/').collect();
    if parts.len() == 3 {
        if let (Ok(d), Ok(m), Ok(y)) = (
            parts[0].parse::<u32>(),
            parts[1].parse::<u32>(),
            parts[2].parse::<i32>(),
        ) {
            if let Some(d) = chrono::NaiveDate::from_ymd_opt(y, m, d) {
                return Some(d.format("%Y-%m-%d").to_string());
            }
        }
    }
    chrono::NaiveDate::parse_from_str(&trimmed, "%Y-%m-%d")
        .ok()
        .map(|d| d.format("%Y-%m-%d").to_string())
}

fn date_from_stoic(raw: &str, fallback_ms: f64) -> String {
    if let Some(date) = parse_date(raw) {
        return date;
    }
    if fallback_ms <= 0.0 {
        return Utc::now().format("%Y-%m-%d").to_string();
    }
    let ts = if fallback_ms.abs() > 10_000_000_000.0 {
        fallback_ms / 1000.0
    } else {
        fallback_ms
    };
    DateTime::from_timestamp(ts as i64, 0)
        .unwrap_or_else(Utc::now)
        .format("%Y-%m-%d")
        .to_string()
}

fn json_date(obj: &serde_json::Map<String, serde_json::Value>) -> Option<String> {
    for key in ["date", "calendarDate", "calendar_date", "day"] {
        if let Some(s) = obj.get(key).and_then(|v| v.as_str()) {
            if let Some(date) = parse_date(s) {
                return Some(date);
            }
        }
    }
    for key in ["timestamp", "created_at", "createdAt"] {
        if let Some(v) = obj.get(key) {
            if let Some(s) = v.as_str() {
                if let Ok(dt) = DateTime::parse_from_rfc3339(s) {
                    return Some(dt.with_timezone(&Utc).format("%Y-%m-%d").to_string());
                }
                if let Ok(d) = chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d") {
                    return Some(d.format("%Y-%m-%d").to_string());
                }
            }
            if let Some(ms) = v.as_f64() {
                return Some(date_from_stoic("", ms));
            }
        }
    }
    None
}

fn json_string(obj: &serde_json::Map<String, serde_json::Value>, keys: &[&str]) -> Option<String> {
    for key in keys {
        if let Some(s) = obj.get(*key).and_then(|v| v.as_str()) {
            if !s.trim().is_empty() {
                return Some(s.to_string());
            }
        }
    }
    None
}

// ---------------------------------------------------------------------------
// JSON (including the JSON array written by Lumen's legacy export)
// ---------------------------------------------------------------------------

pub fn import_json(path: &str, store: &str) -> Result<ImportResult, String> {
    require_unlocked(store)?;
    let raw = fs::read_to_string(path).map_err(|e| format!("read {path}: {e}"))?;
    let value: serde_json::Value =
        serde_json::from_str(&raw).map_err(|e| format!("parse JSON: {e}"))?;

    let items: Vec<serde_json::Value> = if let Some(array) = value.as_array() {
        array.clone()
    } else if let Some(array) = value.get("entries").and_then(|v| v.as_array()) {
        array.clone()
    } else if let Some(object) = value.as_object() {
        let has_note_fields = [
            "body",
            "text",
            "content",
            "markdown",
            "display_title",
            "displayTitle",
            "title",
            "name",
        ]
        .iter()
        .any(|key| object.contains_key(*key));
        let is_file_map = !object.is_empty()
            && object.values().all(|v| v.is_string())
            && object
                .keys()
                .any(|k| k.ends_with(".md") || k.ends_with(".markdown"));

        if is_file_map {
            // A plain { "file.md": "contents" } map.
            object
                .iter()
                .map(|(name, content)| {
                    serde_json::json!({
                        "title": name.trim_end_matches(".md"),
                        "body": content.as_str().unwrap_or_default(),
                        "filename": name,
                    })
                })
                .collect()
        } else if has_note_fields {
            // A single entry object, e.g. { "title": "...", "body": "..." }.
            vec![value.clone()]
        } else {
            return Err(
                "expected a JSON array, an object with an 'entries' array, a single entry, or a file map"
                    .into(),
            );
        }
    } else {
        return Err("expected a JSON array or object".into());
    };

    let mut result = ImportResult::default();
    let mut existing = existing_files(store)?;

    for (i, item) in items.iter().enumerate() {
        let Some(obj) = item.as_object() else {
            result.skipped += 1;
            continue;
        };
        let body = json_string(obj, &["body", "text", "content", "markdown"]);
        let title = json_string(obj, &["display_title", "displayTitle", "title", "name"]);
        let Some(body) = body.or_else(|| title.clone()) else {
            result.skipped += 1;
            continue;
        };
        let body = with_title(&body, title.as_deref().unwrap_or(""));
        let date = json_date(obj);
        let stem = json_string(obj, &["filename", "file", "path"])
            .map(|s| {
                let s = s.trim_start_matches('/').replace('\\', "/");
                if s.ends_with(".md") {
                    s
                } else {
                    format!("{s}.md")
                }
            })
            .unwrap_or_else(|| {
                let title_slug = title
                    .as_deref()
                    .map(slug)
                    .unwrap_or_else(|| format!("entry-{:03}", i + 1));
                match &date {
                    Some(d) => format!("{d}-{title_slug}.md"),
                    None => format!("imported/{:04}-{title_slug}.md", i + 1),
                }
            });
        let desired = stem;
        write_note(&mut existing, &desired, &body, store, &mut result)?;
    }

    Ok(result)
}

// ---------------------------------------------------------------------------
// Markdown folder
// ---------------------------------------------------------------------------

fn collect_markdown(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(read) = fs::read_dir(dir) else { return };
    for entry in read.flatten() {
        let path = entry.path();
        let name = entry.file_name();
        if name == ".lumen" || name == "assets" {
            continue;
        }
        if path.is_dir() {
            collect_markdown(&path, out);
        } else if matches!(
            path.extension()
                .and_then(|e| e.to_str())
                .map(|e| e.to_ascii_lowercase())
                .as_deref(),
            Some("md") | Some("markdown")
        ) {
            out.push(path);
        }
    }
}

pub fn import_markdown_dir(root: &str, store: &str) -> Result<ImportResult, String> {
    require_unlocked(store)?;
    let root_path = Path::new(root);
    if !root_path.is_dir() {
        return Err(format!("not a folder: {root}"));
    }

    let mut files = Vec::new();
    collect_markdown(root_path, &mut files);
    files.sort();

    let mut result = ImportResult::default();
    let mut existing = existing_files(store)?;
    for path in files {
        let Ok(text) = fs::read_to_string(&path) else {
            result.skipped += 1;
            continue;
        };
        let rel = path
            .strip_prefix(root_path)
            .unwrap_or(&path)
            .to_string_lossy()
            .replace('\\', "/");
        let desired = format!("imported/{rel}");
        write_note(&mut existing, &desired, &text, store, &mut result)?;
    }
    Ok(result)
}

// ---------------------------------------------------------------------------
// Stoic iOS export (folder or .zip)
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawEntry {
    uuid: String,
    #[serde(default)]
    timestamp: f64,
    #[serde(default)]
    calendar_date: String,
    #[serde(default)]
    text: Option<String>,
    #[serde(default)]
    location: Option<String>,
    #[serde(default)]
    template: Option<String>,
    #[serde(default)]
    answers: Vec<String>,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default)]
    attributed_text: Option<serde_json::Value>,
}

#[derive(serde::Deserialize)]
struct RawAnswer {
    uuid: String,
    #[serde(default)]
    text: String,
    #[serde(default)]
    context: String,
    #[serde(default)]
    routine: Option<String>,
}

#[derive(Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawRoutine {
    uuid: String,
    #[serde(default)]
    name: String,
    #[serde(default)]
    timestamp: f64,
    #[serde(default)]
    date: String,
    #[serde(default)]
    answers: Vec<String>,
    #[serde(default, rename = "type")]
    routine_type: String,
    #[serde(default)]
    location: Option<String>,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawLocation {
    uuid: String,
    #[serde(default)]
    name: String,
}

#[derive(serde::Deserialize)]
struct RawTag {
    uuid: String,
    #[serde(default)]
    title: String,
    #[serde(default)]
    name: String,
}

fn tag_name(tag: &RawTag) -> String {
    if !tag.title.is_empty() {
        tag.title.clone()
    } else if !tag.name.is_empty() {
        tag.name.clone()
    } else {
        tag.uuid.clone()
    }
}

#[derive(Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawAsset {
    #[serde(default)]
    relative_path: String,
    #[serde(default)]
    uuid: String,
    #[serde(default)]
    answer: Option<String>,
    #[serde(default)]
    journal_entry: Option<String>,
    #[serde(default, rename = "type")]
    asset_type: String,
}

fn format_context(context: &str) -> String {
    let known = match context {
        "routine-evening" => "Evening Routine",
        "routine-morning" => "Morning Routine",
        "postlude-evening" => "Evening Reflection",
        "postlude-morning" => "Morning Reflection",
        "launch" => "Getting Started",
        "emotions-check-in" => "Emotions Check-in",
        "dream-journal" => "Dream Journal",
        "widget-intent" => "Quick Entry",
        "phq-9" => "PHQ-9 Assessment",
        "gad-7" => "GAD-7 Assessment",
        "movie-review" => "Movie Review",
        "on-lessons-learned" => "Lessons Learned",
        "last-year-highlights" => "Year Highlights",
        "back-to-school" => "Back to School",
        "thanksgiving" => "Thanksgiving Reflection",
        "morning-preparation" => "Morning Preparation",
        "henri-bergson-on-intuition" => "Reading: Bergson on Intuition",
        "safe-space-visualization" => "Safe Space Visualization",
        "intro-to-stoicism-prompt-0" => "Stoic Prompt",
        _ => "",
    };
    if !known.is_empty() {
        return known.to_string();
    }
    let mut result = String::new();
    let mut cap_next = true;
    for ch in context.chars() {
        if ch == '-' || ch == '_' {
            cap_next = true;
            result.push(' ');
        } else if cap_next {
            result.push(ch.to_ascii_uppercase());
            cap_next = false;
        } else {
            result.push(ch);
        }
    }
    if result.is_empty() {
        "Answer".into()
    } else {
        result
    }
}

fn find_json(root: &Path, filename: &str) -> Option<PathBuf> {
    let direct = root.join(filename);
    if direct.is_file() {
        return Some(direct);
    }
    let read = fs::read_dir(root).ok()?;
    for entry in read.flatten() {
        let path = entry.path();
        if path.is_dir() && entry.file_name() != "assets" {
            if let Some(found) = find_json(&path, filename) {
                return Some(found);
            }
        }
    }
    None
}

fn read_json<T: DeserializeOwned>(root: &Path, filename: &str) -> Vec<T> {
    let Some(path) = find_json(root, filename) else {
        return Vec::new();
    };
    let Ok(content) = fs::read_to_string(path) else {
        return Vec::new();
    };
    if content.trim_start().starts_with('[') {
        serde_json::from_str(&content).unwrap_or_default()
    } else {
        Vec::new()
    }
}

struct TempDir(PathBuf);

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn extract_json_from_zip(zip_path: &Path) -> Result<TempDir, String> {
    let file = fs::File::open(zip_path).map_err(|e| e.to_string())?;
    let mut archive = zip::ZipArchive::new(file).map_err(|e| format!("open zip: {e}"))?;
    let dir = std::env::temp_dir().join(format!(
        "lumen-stoic-{}-{}",
        std::process::id(),
        Utc::now().timestamp_nanos_opt().unwrap_or(0)
    ));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;

    for i in 0..archive.len() {
        let mut entry = archive.by_index(i).map_err(|e| e.to_string())?;
        if entry.is_dir() {
            continue;
        }
        let Some(rel) = entry.enclosed_name().map(|p| p.to_path_buf()) else {
            continue;
        };
        // Extract every file, including media under assets/, so encrypted
        // attachments can be imported and linked to their entries.
        let out = dir.join(rel);
        if let Some(parent) = out.parent() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let mut data = Vec::new();
        entry.read_to_end(&mut data).map_err(|e| e.to_string())?;
        fs::write(&out, data).map_err(|e| e.to_string())?;
    }
    Ok(TempDir(dir))
}

fn attributed_text(value: &serde_json::Value) -> String {
    value
        .get("runs")
        .and_then(|v| v.as_array())
        .map(|runs| {
            runs.iter()
                .filter_map(|r| r.get("text").and_then(|t| t.as_str()))
                .collect::<Vec<_>>()
                .join("")
        })
        .unwrap_or_default()
}

fn stoic_entry_body(
    entry: &RawEntry,
    answers: &std::collections::HashMap<String, RawAnswer>,
    routines: &std::collections::HashMap<String, RawRoutine>,
    locations: &std::collections::HashMap<String, RawLocation>,
    tags: &std::collections::HashMap<String, RawTag>,
    date: &str,
) -> String {
    let mut body = if let Some(text) = entry.text.as_ref().filter(|t| !t.trim().is_empty()) {
        text.clone()
    } else if let Some(attr) = entry.attributed_text.as_ref() {
        let text = attributed_text(attr);
        if text.trim().is_empty() {
            format!("# Stoic Entry — {date}\n\n")
        } else {
            text
        }
    } else {
        let mut lines = vec![format!("# Stoic Entry — {date}")];
        if let Some(loc) = entry.location.as_ref().and_then(|id| locations.get(id)) {
            if !loc.name.is_empty() {
                lines.push(format!("\n**Location:** {}", loc.name));
            }
        }
        if let Some(routine) = entry.template.as_ref().and_then(|id| routines.get(id)) {
            if !routine.name.is_empty() {
                lines.push(format!("\n**Template:** {}", routine.name));
            }
        }
        for id in &entry.answers {
            let Some(answer) = answers.get(id) else {
                continue;
            };
            if answer.text.trim().is_empty() {
                continue;
            }
            let mut label = Vec::new();
            if !answer.context.is_empty() {
                label.push(format_context(&answer.context));
            }
            if let Some(r) = answer.routine.as_ref().and_then(|id| routines.get(id)) {
                if !r.name.is_empty() {
                    label.push(r.name.clone());
                }
            }
            let label = if label.is_empty() {
                "Answer".to_string()
            } else {
                label.join(" / ")
            };
            lines.push(format!("\n- **{label}:** {}", answer.text));
        }
        lines.join("")
    };

    if !is_heading(&body) {
        body = format!("# Stoic Entry — {date}\n\n{body}");
    }
    let entry_tags: Vec<String> = entry
        .tags
        .iter()
        .filter_map(|id| tags.get(id))
        .map(tag_name)
        .collect();
    if !entry_tags.is_empty() {
        body.push_str(&format!("\n\n**Tags:** {}", entry_tags.join(", ")));
    }
    body
}

#[derive(Clone)]
struct AssetTarget {
    kind: String,
    id: String,
}

fn import_stoic_dir(root: &Path, store: &str) -> Result<ImportResult, String> {
    let answers: std::collections::HashMap<String, RawAnswer> =
        read_json::<RawAnswer>(root, "answers.json")
            .into_iter()
            .map(|a| (a.uuid.clone(), a))
            .collect();
    let routines: Vec<RawRoutine> = read_json(root, "routines.json");
    let routines_map: std::collections::HashMap<String, RawRoutine> = routines
        .iter()
        .cloned()
        .map(|r| (r.uuid.clone(), r))
        .collect();
    let locations: std::collections::HashMap<String, RawLocation> =
        read_json::<RawLocation>(root, "locations.json")
            .into_iter()
            .map(|l| (l.uuid.clone(), l))
            .collect();
    let tags: std::collections::HashMap<String, RawTag> = read_json::<RawTag>(root, "tags.json")
        .into_iter()
        .map(|t| (t.uuid.clone(), t))
        .collect();
    let assets: Vec<RawAsset> = read_json(root, "assets.json");

    let entries: Vec<RawEntry> = read_json(root, "journal-entries.json");
    let mut result = ImportResult::default();
    let mut existing = existing_files(store)?;

    // Map each answer UUID back to the journal entry/routine that owns it, so
    // media attached to an answer can be linked to the right dated note.
    let mut answer_owner: HashMap<String, AssetTarget> = HashMap::new();
    for entry in &entries {
        for answer_id in &entry.answers {
            answer_owner
                .entry(answer_id.clone())
                .or_insert(AssetTarget {
                    kind: "journal".to_string(),
                    id: entry.uuid.clone(),
                });
        }
    }
    for routine in &routines {
        for answer_id in &routine.answers {
            answer_owner
                .entry(answer_id.clone())
                .or_insert(AssetTarget {
                    kind: "routine".to_string(),
                    id: routine.uuid.clone(),
                });
        }
    }

    // Copy every linked asset into the encrypted vault and collect Markdown
    // references keyed by their owning entry/routine UUID.
    let mut journal_asset_lines: HashMap<String, Vec<String>> = HashMap::new();
    let mut routine_asset_lines: HashMap<String, Vec<String>> = HashMap::new();
    for asset in &assets {
        let rel = asset.relative_path.trim().replace('\\', "/");
        if rel.is_empty()
            || rel.starts_with('/')
            || rel.split('/').any(|p| p == ".." || p.is_empty())
        {
            continue;
        }
        let source_path = root.join(&rel);
        if !source_path.is_file() {
            // Location/contact-style placeholders do not exist on disk.
            continue;
        }
        let bytes = match fs::read(&source_path) {
            Ok(b) => b,
            Err(_) => continue,
        };
        if vault::write_bytes(&rel, &bytes, store).is_err() {
            continue;
        }

        let name = if asset.uuid.trim().is_empty() {
            rel.rsplit('/').next().unwrap_or("media").to_string()
        } else {
            asset.uuid.clone()
        };
        let link = if asset.asset_type.eq_ignore_ascii_case("image") {
            format!("![{}]({})", name, rel)
        } else {
            format!("[{}]({})", name, rel)
        };

        if let Some(journal_entry) = asset
            .journal_entry
            .as_ref()
            .filter(|s| !s.trim().is_empty())
        {
            journal_asset_lines
                .entry(journal_entry.clone())
                .or_default()
                .push(link.clone());
        }
        if let Some(answer) = asset.answer.as_ref().filter(|s| !s.trim().is_empty()) {
            if let Some(target) = answer_owner.get(answer) {
                match target.kind.as_str() {
                    "journal" => {
                        journal_asset_lines
                            .entry(target.id.clone())
                            .or_default()
                            .push(link.clone());
                    }
                    "routine" => {
                        routine_asset_lines
                            .entry(target.id.clone())
                            .or_default()
                            .push(link.clone());
                    }
                    _ => {}
                }
            }
        }
    }

    for entry in &entries {
        let date = date_from_stoic(&entry.calendar_date, entry.timestamp);
        let mut body = stoic_entry_body(entry, &answers, &routines_map, &locations, &tags, &date);
        if let Some(lines) = journal_asset_lines.get(&entry.uuid) {
            if !lines.is_empty() {
                body.push_str("\n\n**Attachments:**\n");
                body.push_str(&lines.join("\n"));
            }
        }
        let desired = format!("{date}-stoic-{}.md", short_id(&entry.uuid));
        write_note(&mut existing, &desired, &body, store, &mut result)?;
    }

    for routine in &routines {
        if routine.answers.is_empty() {
            result.skipped += 1;
            continue;
        }
        let date = date_from_stoic(&routine.date, routine.timestamp);
        let name = match routine.routine_type.as_str() {
            "morning" => "Stoic Morning Routine",
            "evening" => "Stoic Evening Routine",
            _ => {
                if routine.name.is_empty() {
                    "Stoic Daily Routine"
                } else {
                    &routine.name
                }
            }
        };
        let mut lines = vec![format!("# {name} — {date}")];
        if let Some(loc) = routine.location.as_ref().and_then(|id| locations.get(id)) {
            if !loc.name.is_empty() {
                lines.push(format!("\n**Location:** {}", loc.name));
            }
        }
        for id in &routine.answers {
            let Some(answer) = answers.get(id) else {
                continue;
            };
            if answer.text.trim().is_empty() {
                continue;
            }
            let label = if answer.context.is_empty() {
                "Answer".to_string()
            } else {
                format_context(&answer.context)
            };
            lines.push(format!("\n- **{label}:** {}", answer.text));
        }
        if let Some(asset_lines) = routine_asset_lines.get(&routine.uuid) {
            if !asset_lines.is_empty() {
                lines.push("\n\n**Attachments:**".to_string());
                for line in asset_lines {
                    lines.push(line.clone());
                }
            }
        }
        let desired = format!("{date}-routine-{}.md", short_id(&routine.uuid));
        write_note(&mut existing, &desired, &lines.join(""), store, &mut result)?;
    }

    Ok(result)
}

pub fn import_stoic(path: &str, store: &str) -> Result<ImportResult, String> {
    require_unlocked(store)?;
    let path = Path::new(path);
    if path.is_dir() {
        return import_stoic_dir(path, store);
    }
    let is_zip = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.eq_ignore_ascii_case("zip"))
        .unwrap_or(false);
    if path.is_file() && is_zip {
        let tmp = extract_json_from_zip(path)?;
        return import_stoic_dir(&tmp.0, store);
    }
    Err(format!("not a Stoic export folder or .zip: {path:?}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unique_names_get_suffixed() {
        let mut set = HashSet::from(["2026-01-01-entry.md".to_string()]);
        assert_eq!(
            unique_name(&mut set, "2026-01-01-entry.md"),
            "2026-01-01-entry-2.md"
        );
        assert_eq!(
            unique_name(&mut set, "2026-01-01-entry.md"),
            "2026-01-01-entry-3.md"
        );
    }

    #[test]
    fn stoic_dates_convert_to_iso() {
        assert_eq!(date_from_stoic("02/03/2026", 0.0), "2026-03-02");
        assert_eq!(date_from_stoic("2026-03-02", 0.0), "2026-03-02");
    }
}
