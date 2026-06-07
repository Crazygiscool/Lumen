use std::collections::HashMap;
use std::path::Path;

use chrono::{DateTime, Utc};

use crate::entry::{EntryKind, JournalEntry};
use crate::storage::Storage;

#[derive(serde::Deserialize)]
struct RawEntry {
    uuid: String,
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
    assets: Vec<String>,
    #[serde(default)]
    is_completed: Option<bool>,
    #[serde(default)]
    tags: Vec<String>,
}

#[derive(serde::Deserialize)]
struct RawAnswer {
    uuid: String,
    text: String,
    #[serde(default)]
    context: String,
    #[serde(default)]
    routine: Option<String>,
}

#[derive(serde::Deserialize)]
struct RawRoutine {
    uuid: String,
    #[serde(default)]
    name: String,
}

#[derive(serde::Deserialize)]
struct RawAsset {
    uuid: String,
    #[serde(default)]
    relative_path: String,
    #[serde(default)]
    answer: String,
    #[serde(default)]
    r#type: String,
}

#[derive(serde::Deserialize)]
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

#[derive(serde::Deserialize)]
struct RawEmotionCheckin {
    uuid: String,
    timestamp: f64,
    #[serde(default)]
    mood: String,
    #[serde(default)]
    energy: Option<i64>,
    #[serde(default)]
    emotions: Vec<String>,
    #[serde(default)]
    calendar_date: String,
}

#[derive(serde::Deserialize)]
struct RawBreathing {
    uuid: String,
    #[serde(default)]
    start: f64,
    #[serde(default)]
    duration: f64,
    #[serde(default)]
    r#type: String,
}

fn parse_stoic_timestamp(ts: f64) -> DateTime<Utc> {
    let secs = (ts / 1000.0) as i64;
    let nanos = ((ts % 1000.0) * 1_000_000.0) as u32;
    DateTime::from_timestamp(secs, nanos).unwrap_or_else(|| {
        DateTime::from_timestamp(secs, 0).unwrap_or(Utc::now())
    })
}

fn generate_id() -> String {
    let ts = Utc::now().timestamp();
    let rand_part: u32 = rand::random();
    format!("{}_{:08x}", ts, rand_part)
}

fn read_json<T>(dir: &Path, filename: &str) -> Vec<T>
where
    T: serde::de::DeserializeOwned,
{
    let path = dir.join(filename);
    let content = match std::fs::read_to_string(&path) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };
    // Some files are objects, not arrays (manifest, routine-specifications)
    // Handle both cases
    let trimmed = content.trim();
    if trimmed.starts_with('[') {
        serde_json::from_str(&content).unwrap_or_default()
    } else {
        Vec::new()
    }
}

fn tag_name(tag: &RawTag) -> String {
    if !tag.title.is_empty() { tag.title.clone() }
    else if !tag.name.is_empty() { tag.name.clone() }
    else { tag.uuid.clone() }
}

pub fn import_stoic(export_dir: &str, password: &str, storage: &Storage) -> i32 {
    let dir = Path::new(export_dir);
    if !dir.is_dir() {
        eprintln!("[lumen] Stoic export directory not found: {export_dir}");
        return 0;
    }

    // Build lookup maps
    let answers: HashMap<String, RawAnswer> = read_json::<RawAnswer>(dir, "answers.json")
        .into_iter().map(|a| (a.uuid.clone(), a)).collect();
    let routines_map: HashMap<String, RawRoutine> = read_json::<RawRoutine>(dir, "routines.json")
        .into_iter().map(|r| (r.uuid.clone(), r)).collect();
    let locations_map: HashMap<String, RawLocation> = read_json::<RawLocation>(dir, "locations.json")
        .into_iter().map(|l| (l.uuid.clone(), l)).collect();
    let tags_map: HashMap<String, RawTag> = read_json::<RawTag>(dir, "tags.json")
        .into_iter().map(|t| (t.uuid.clone(), t)).collect();

    let entries: Vec<RawEntry> = read_json(dir, "journal-entries.json");
    let raw_assets: Vec<RawAsset> = read_json(dir, "assets.json");

    let mut imported_count: i32 = 0;

    for entry in &entries {
        let ts = parse_stoic_timestamp(entry.timestamp);
        let cal_date = entry.calendar_date.replace('\\', "");

        // Build body as Markdown
        let body = if let Some(ref text) = entry.text {
            if !text.trim().is_empty() {
                text.clone()
            } else {
                format!("# Stoic Entry — {}\n\n", cal_date)
            }
        } else {
            // Template entry — resolve answers
            let mut lines = Vec::new();
            lines.push(format!("# Stoic Entry — {}", cal_date));

            // Add location if available
            if let Some(ref loc_uuid) = entry.location {
                if let Some(loc) = locations_map.get(loc_uuid) {
                    if !loc.name.is_empty() {
                        lines.push(format!("\n**Location:** {}", loc.name));
                    }
                }
            }

            // Add template/routine info
            if let Some(ref tmpl_uuid) = entry.template {
                let routine_name = routines_map.get(tmpl_uuid)
                    .map(|r| {
                        if r.name.is_empty() { r.uuid.clone() } else { r.name.clone() }
                    })
                    .unwrap_or_else(|| tmpl_uuid.clone());
                lines.push(format!("\n**Template:** {}", routine_name));
            }

            // Resolve and format answers
            for ans_uuid in &entry.answers {
                if let Some(answer) = answers.get(ans_uuid) {
                    let mut parts = Vec::new();
                    if !answer.context.is_empty() {
                        parts.push(answer.context.clone());
                    }
                    if let Some(ref r_uuid) = answer.routine {
                        if let Some(r) = routines_map.get(r_uuid) {
                            if !r.name.is_empty() {
                                parts.push(r.name.clone());
                            }
                        }
                    }
                    let label = if parts.is_empty() {
                        "Answer".to_string()
                    } else {
                        parts.join(" / ")
                    };
                    lines.push(format!("\n- **{}:** {}", label, answer.text));
                }
            }

            lines.join("")
        };

        // Determine display title
        let display_title = extract_title(&body, &cal_date);

        // Tags
        let mut tags: Vec<String> = entry.tags.iter()
            .filter_map(|t| tags_map.get(t))
            .map(tag_name)
            .collect();
        // Add "stoic-imported" tag
        tags.push("stoic-imported".to_string());

        // Create provenance metadata
        let metadata = serde_json::json!({
            "stoic_uuid": entry.uuid,
            "stoic_date": cal_date,
            "stoic_template": entry.template,
            "stoic_location": entry.location,
            "stoic_is_completed": entry.is_completed,
        });

        // Encrypt and create entry
        let lumen_entry = JournalEntry {
            id: generate_id(),
            encrypted: Vec::new(),
            nonce: Vec::new(),
            salt: Vec::new(),
            assets: Vec::new(),
            provenance: crate::entry::Provenance {
                timestamp: ts,
                plugin_origin: Some("stoic-import".to_string()),
                author: "stoic-import".to_string(),
                feedback: None,
                metadata,
            },
            kind: EntryKind::Journal,
            tags,
            display_title,
            pinned: false,
            mood: None,
            priority: None,
            status: None,
            due_date: None,
            parent_project_id: None,
            history: Vec::new(),
        };

        // Re-encrypt the body with Lumen's encryption
        let salt: [u8; 16] = rand::random();
        let key = crate::entry::encryption::derive_key(password, &salt);
        let (encrypted, nonce) = crate::entry::encryption::encrypt(body.as_bytes(), &key);

        let mut final_entry = lumen_entry;
        final_entry.encrypted = encrypted;
        final_entry.nonce = nonce;
        final_entry.salt = salt.to_vec();

        if let Err(e) = storage.add_entry(&final_entry) {
            eprintln!("[lumen] Failed to import Stoic entry {}: {e}", entry.uuid);
            continue;
        }

        // Import associated assets
        let entry_asset_uuids: Vec<&str> = entry.assets.iter().map(|s| s.as_str()).collect();
        for raw_asset in &raw_assets {
            if !entry_asset_uuids.contains(&raw_asset.uuid.as_str()) {
                // Check if this asset belongs to one of the entry's answers
                let belongs = entry.answers.iter().any(|a| a == &raw_asset.answer);
                if !belongs {
                    continue;
                }
            }

            let asset_path = dir.join(&raw_asset.relative_path);
            let file_data = match std::fs::read(&asset_path) {
                Ok(d) => d,
                Err(e) => {
                    eprintln!("[lumen] Cannot read asset file {}: {e}", asset_path.display());
                    continue;
                }
            };

            // Encrypt asset data
            let asset_salt: [u8; 16] = rand::random();
            let asset_key = crate::entry::encryption::derive_key(password, &asset_salt);
            let (asset_encrypted, asset_nonce) = crate::entry::encryption::encrypt(&file_data, &asset_key);

            let mime = match raw_asset.r#type.as_str() {
                "image" => {
                    let ext = asset_path.extension().and_then(|e| e.to_str()).unwrap_or("bin").to_lowercase();
                    match ext.as_str() {
                        "jpg" | "jpeg" => "image/jpeg".to_string(),
                        "png" => "image/png".to_string(),
                        "heic" => "image/heic".to_string(),
                        _ => "image/octet-stream".to_string(),
                    }
                }
                "video" => "video/mp4".to_string(),
                "audio" => "audio/m4a".to_string(),
                _ => "application/octet-stream".to_string(),
            };

            let file_name = asset_path.file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("unknown")
                .to_string();

            let asset = crate::entry::EntryAsset {
                id: raw_asset.uuid.clone(),
                entry_id: final_entry.id.clone(),
                file_name,
                mime_type: mime,
                encrypted_size: asset_encrypted.len() as u64,
                nonce: asset_nonce,
                salt: asset_salt.to_vec(),
                encrypted_data: asset_encrypted,
                created_at: Utc::now(),
            };

            if let Err(e) = storage.add_asset(&asset) {
                eprintln!("[lumen] Failed to store asset {}: {e}", raw_asset.uuid);
            }
        }

        imported_count += 1;
    }

    // Import emotion check-ins as custom entries
    let emotions: Vec<RawEmotionCheckin> = read_json(dir, "emotion-check-in.json");
    for em in &emotions {
        let ts = parse_stoic_timestamp(em.timestamp);
        let body = format!(
            "# Emotion Check-in — {}\n\n**Mood:** {}\n**Energy:** {}\n**Emotions:** {}",
            em.calendar_date.replace('\\', ""),
            em.mood,
            em.energy.map(|e| e.to_string()).unwrap_or_else(|| "—".to_string()),
            em.emotions.join(", "),
        );

        let salt: [u8; 16] = rand::random();
        let key = crate::entry::encryption::derive_key(password, &salt);
        let (encrypted, nonce) = crate::entry::encryption::encrypt(body.as_bytes(), &key);

        let metadata = serde_json::json!({
            "stoic_type": "emotion_checkin",
            "stoic_uuid": em.uuid,
            "mood": em.mood,
            "energy": em.energy,
            "emotions": em.emotions,
        });

        let entry = JournalEntry {
            id: generate_id(),
            encrypted,
            nonce,
            salt: salt.to_vec(),
            assets: Vec::new(),
            provenance: crate::entry::Provenance {
                timestamp: ts,
                plugin_origin: Some("stoic-import".to_string()),
                author: "stoic-import".to_string(),
                feedback: None,
                metadata,
            },
            kind: EntryKind::Custom("emotion".to_string()),
            tags: vec!["stoic-imported".to_string(), "emotion".to_string()],
            display_title: format!("Emotion Check-in — {}", em.calendar_date.replace('\\', "")),
            pinned: false,
            mood: Some(em.mood.clone()),
            priority: None,
            status: None,
            due_date: None,
            parent_project_id: None,
            history: Vec::new(),
        };

        if let Err(e) = storage.add_entry(&entry) {
            eprintln!("[lumen] Failed to import emotion check-in: {e}");
        } else {
            imported_count += 1;
        }
    }

    // Import breathings as custom entries
    let breathings: Vec<RawBreathing> = read_json(dir, "breathings.json");
    for br in &breathings {
        let ts = parse_stoic_timestamp(br.start);
        let body = format!(
            "# Breathing Session — {}\n\n**Type:** {}\n**Duration:** {}s",
            ts.format("%Y-%m-%d"),
            br.r#type,
            br.duration,
        );

        let salt: [u8; 16] = rand::random();
        let key = crate::entry::encryption::derive_key(password, &salt);
        let (encrypted, nonce) = crate::entry::encryption::encrypt(body.as_bytes(), &key);

        let metadata = serde_json::json!({
            "stoic_type": "breathing",
            "stoic_uuid": br.uuid,
            "breathing_type": br.r#type,
            "duration": br.duration,
        });

        let entry = JournalEntry {
            id: generate_id(),
            encrypted,
            nonce,
            salt: salt.to_vec(),
            assets: Vec::new(),
            provenance: crate::entry::Provenance {
                timestamp: ts,
                plugin_origin: Some("stoic-import".to_string()),
                author: "stoic-import".to_string(),
                feedback: None,
                metadata,
            },
            kind: EntryKind::Custom("mindfulness".to_string()),
            tags: vec!["stoic-imported".to_string(), "mindfulness".to_string(), "breathing".to_string()],
            display_title: format!("Breathing — {}", br.r#type),
            pinned: false,
            mood: None,
            priority: None,
            status: None,
            due_date: None,
            parent_project_id: None,
            history: Vec::new(),
        };

        if let Err(e) = storage.add_entry(&entry) {
            eprintln!("[lumen] Failed to import breathing session: {e}");
        } else {
            imported_count += 1;
        }
    }

    imported_count
}

fn extract_title(body: &str, fallback_date: &str) -> String {
    for line in body.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("# ") {
            return trimmed[2..].trim().to_string();
        }
    }
    format!("Stoic Entry — {}", fallback_date)
}
