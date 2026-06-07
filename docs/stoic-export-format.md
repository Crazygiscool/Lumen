# Stoic iOS Export Format

> Reverse-engineered from a real Stoic iOS app export (v2.x). The export is a `.zip` file containing JSON files and an `assets/` directory.

## Overview

A Stoic export consists of:

- **17 JSON files** at the root — arrays of objects (one file is a single object: `manifest.json`)
- **`assets/` directory** — subdirectories `answers/` (254 dirs) and `journal/` (7 dirs), totalling ~5.1 GB of media

All UUIDs are version 4 UUIDs in uppercase hex with dashes (e.g. `9A4C5BDF-CEB9-4EE8-8871-CDFAABE918E2`).

Timestamps are **milliseconds since Unix epoch** stored as `f64` (with fractional millisecond precision).

Dates use the format `DD/MM/YYYY` (e.g. `"02/03/2026"`).

All JSON object keys are **camelCase**.

---

## File Reference

### `journal-entries.json` — 44 entries

The primary data. Each entry is either:

- **Template entry** (32 of 44) — has `template` (UUID of a routine specification) and `answers` (list of answer UUIDs). No free-text body.
- **Free-text entry** (12 of 44) — has `attributedText` with run-based rich text. No `template` or `answers`.
- **Empty entry** (12 of 44) — has neither `template`, `attributedText`, nor `answers`. Placeholder entries with just a date.

```
{
  "uuid": "9A4C5BDF-CEB9-4EE8-8871-CDFAABE918E2",
  "timestamp": 1772487817685.924,        // f64 ms since epoch
  "calendarDate": "02/03/2026",           // DD/MM/YYYY
  "isCompleted": true,
  "template": "B090A884-..." | null,      // UUID of routine specification
  "answers": [ "uuid1", "uuid2", ... ],   // answer UUIDs (template entries only)
  "attributedText": {                     // free-text entries only
    "runs": [
      {
        "text": "...",
        "attributes": {
          "blockPresentation": { "components": [...] },
          "inlinePresentation": 2
        }
      }
    ]
  } | null,
  "components": [                          // question UUIDs in order
    { "uuid": "...", "type": "question" },
    { "uuid": "...", "type": "feedback" }
  ],
  "tags": []                               // tag UUIDs (rarely populated here)
}
```

**Text extraction for free-text entries:** Concatenate all `runs[].text` values.

### `answers.json` — 4,465 answers

Each answer is a response to a question within a routine or check-in.

```
{
  "uuid": "DB17536F-...",
  "text": "2.9629629629629624",       // response text (can be numeric string for scale questions)
  "context": "routine-evening",        // see Context Types below
  "question": "14E2EE8A-...",          // question UUID
  "timestamp": 1780789241157.65,
  "version": 0
}
```

**Context types** (19 total, ordered by frequency):

| Context | Count | Description |
|---------|-------|-------------|
| `routine-evening` | 2,367 | Evening routine question responses |
| `launch` | 573 | First-launch onboarding questions |
| `postlude-evening` | 559 | Evening post-routine reflection |
| `routine-morning` | 524 | Morning routine question responses |
| `postlude-morning` | 226 | Morning post-routine reflection |
| `widget-intent` | 51 | Today widget quick-entry |
| `phq-9` | 50 | PHQ-9 depression screening |
| `movie-review` | 25 | Movie review entries |
| `emotions-check-in` | 15 | Emotion check-in answers |
| `dream-journal` | 15 | Dream journal entries |
| `on-lessons-learned` | 14 | Lessons learned reflection |
| `last-year-highlights` | 11 | Year-end highlights |
| `back-to-school` | 8 | Back-to-school reflection |
| `gad-7` | 8 | GAD-7 anxiety screening |
| `thanksgiving` | 6 | Thanksgiving reflection |
| `morning-preparation` | 6 | Morning preparation |
| `henri-bergson-on-intuition` | 4 | Philosophy reading reflection |
| `safe-space-visualization` | 2 | Guided visualization |
| `intro-to-stoicism-prompt-0` | 1 | First Stoic prompt |

### `assets.json` — 1,995 assets

Each asset is a file attached to an answer or journal entry.

```
{
  "order": 0,
  "relativePath": "assets/answers/99CCA511-.../E685FB78-....HEIC",
  "uuid": "E685FB78-...",
  "answer": "99CCA511-...",             // answer UUID this belongs to
  "journalEntry": "4869026B-..." | null, // direct journal entry UUID (rare)
  "type": "image",                       // "image", "video", "audio", "drawing", "location"
  "metadata": {
    "width": 4032,
    "height": 3024,
    "creationDate": 1738851753000,
    "filenameExtension": "HEIC",
    "longitude": -75.386,
    "latitude": 39.892,
    "voiceMemo": {},
    "localIdentifier": "..."
  }
}
```

**Type distribution:** HEIC (1,442), JPG (440), JPEG (22), PNG (30), pkdr (3), mov (1), location (2), contact (1).

**Special types:**
- `type: "drawing"` → `.pkdr` files (PKDrawing format, exist on disk)
- `type: "location"` → `.location` files (**do not exist** on disk — metadata-only references)
- `type: "video"` → `.mov` files
- `type: "image"` → `.HEIC`, `.jpg`, `.jpeg`, `.png` files

### `routines.json` — 828 routine completions

Each entry records one completed routine instance.

```
{
  "uuid": "B35CC955-...",
  "type": "morning" | "evening",
  "day": "72019A2C-...",              // day UUID from days.json
  "date": "10/01/2025",
  "timestamp": 1736566018339.927,
  "isCompleted": true,
  "template": {
    "specification": "standard",
    "prelude": [],
    "items": [ { "type": "question", "uuid": "..." }, ... ],
    "postlude": []
  },
  "questions": [ "uuid1", "uuid2", ... ],  // question UUIDs in order
  "answers": [ "uuid1", "uuid2", ... ],     // answer UUIDs
  "location": "813D5B0B-..." | null         // location UUID
}
```

Routines do **not** have a user-visible name. Identity is derived from `type` + `date`.

### `tags.json` — 5 tags

```
{
  "uuid": "B4BE0D38-...",
  "title": "Music",
  "icon": "paintpalette.fill"
}
```

Tags have a `title` (if non-empty) or fall back to `name` (legacy field).

### `locations.json` — 406 locations

```
{
  "uuid": "A8A66BDB-...",
  "coordinate": { "latitude": 40.47, "longitude": -75.07 },
  "altitude": 35.51,
  "timestamp": 1750566978376.6028,
  "routine": "28DDB247-..."   // routine UUID this location was recorded during
}
```

### `days.json` — 637 calendar days

```
{
  "uuid": "DB95278E-...",
  "date": "06/06/2026",
  "start": 1780729200000,    // ms epoch, start of day
  "end": 1780815600000       // ms epoch, end of day
}
```

### `emotion-check-in.json` — 5 check-ins

```
{
  "uuid": "11EFC9FE-...",
  "timestamp": 1763359408013.175,
  "calendarDate": "17/11/2025",
  "isCompleted": true,
  "emotions": ["emotion-proud", "emotion-happy", ...],
  "answers": ["uuid1", "uuid2", ...],    // answer UUIDs
  "breathing": "B974B935-..." | null     // linked breathing session UUID
}
```

The `mood` is the first emotion in the `emotions` list. There is no numeric mood/energy field — those are derived from the linked answers.

### `breathings.json` — 14 sessions

```
{
  "uuid": "B974B935-...",
  "start": 1763359462158.356,
  "end": 1763359536204.739,
  "duration": 74,                        // seconds
  "type": 0,                             // breathing pattern type (integer)
  "numberOfBreaths": 4,
  "pace": 0,
  "finalMood": 5,                        // 1-10 scale
  "calendarDate": "17/11/2025",
  "checkIn": "11EFC9FE-..."             // linked emotion check-in UUID
}
```

### `meditations.json` — 2 sessions

```
{
  "uuid": "56FE19AC-...",
  "start": 1730257809849.115,
  "end": 1730257857423.6099,
  "duration": 46.94,
  "calendarDate": "29/10/2024",
  "moodChange": 0,                      // mood delta
  "breaks": [ ... ],
  "location": "716BC097-..."
}
```

### `routine-specifications.json` — 1 specification

```
{
  "uuid": "126F8929-...",
  "type": "evening",
  "items": [
    { "type": "question", "uuid": "...", "order": 0 },
    { "type": "feedback", "uuid": "...", "order": 1 }
  ],
  "isEditedByUser": true
}
```

Defines a routine template structure. The `type` field matches the `type` in `routines.json`.

### `question-options.json` — 7 option definitions

```
{
  "uuid": "A1B2C3D4-...",
  "identifier": "question-option-focus-25",
  "title": "question-option-focus-25-title",
  "symbol": "person.2.fill",
  "choices": "5C5BC260-...",        // UUID of choices definition
  "isHidden": true,
  "isDeleted": false,
  "isEditedByUser": true
}
```

### `quote-reading-session.json` — 24 sessions

```
{
  "uuid": "443A286B-...",
  "start": 1779579755579.345,
  "end": 1779579792358.409,
  "duration": 36.78,
  "quotesIDs": [ "uuid1", "uuid2", ... ]
}
```

### `emotion-assessment.json` — 1 assessment

```
{
  "uuid": "1F0A5635-...",
  "timestamp": 1746065640000,
  "emotion": "emotion-frustrated",
  "checkIn": "B62633A9-...",
  "details": [ ... ],
  "items": [ ... ]
}
```

### `manifest.json` — metadata object (not an array)

```
{
  "osVersion": "18.x",
  "timestamp": 1779579755579,
  "build": "...",
  "os": "iOS",
  "appVersion": "2.x",
  "device": "iPhonexx,x"
}
```

---

## UUID Relationships

```
journal-entries.json
  ├── .template ──────► routine-specifications.json (by UUID)
  ├── .answers[] ─────► answers.json (by UUID)
  ├── .tags[] ────────► tags.json (by UUID)
  └── .location ──────► locations.json (by UUID)

assets.json
  ├── .answer ────────► answers.json (by UUID)
  └── .journalEntry ──► journal-entries.json (by UUID)

answers.json
  ├── .question ──────► (question UUID, not resolved — no questions.json)
  └── .routine ───────► routines.json (by UUID, in context field)

emotion-check-in.json
  ├── .answers[] ─────► answers.json (by UUID)
  └── .breathing ─────► breathings.json (by UUID)

routines.json
  ├── .day ───────────► days.json (by UUID)
  ├── .template.items[].uuid ──► routine-specifications.json items
  ├── .answers[] ─────► answers.json (by UUID)
  └── .location ──────► locations.json (by UUID)

breathings.json
  └── .checkIn ───────► emotion-check-in.json (by UUID)
```

**Known limitation:** Question UUIDs (`.question` in `answers.json`, `.components[].uuid` in journal entries) cannot be resolved to question text because the Stoic export does not include a `questions.json` file. Questions are identified by their context + routine association.

---

## Import Flow

```
User picks .zip or directory
        │
        ▼
  ┌─ Is .zip? ──► Extract to /tmp/lumen_stoic_import_{pid}
  │
  ▼
Read all JSON files into lookup maps (answers, routines, locations, tags)
        │
        ▼
For each journal entry:
  1. Parse timestamp (ms → DateTime)
  2. Build body Markdown:
     - Free-text: concatenate attributedText.runs[].text
     - Template: resolve answer UUIDs, format as "- **Context:** text"
     - Empty: date-based title only
  3. Determine display_title from first `# ` heading
  4. Add tag "stoic-imported"
  5. Encrypt body with AES-256-GCM (per-entry random salt, Argon2 key derivation)
  6. INSERT into entries table with Provenance metadata
  7. For each linked asset:
     - Read file from assets/{answers,journal}/{uuid}/{file}
     - Skip if file doesn't exist (e.g. .location placeholders)
     - Encrypt with shared Argon2 key + unique nonce
     - INSERT into entry_assets table

For each emotion check-in:
  → Create Custom("emotion") entry with emotion list

For each breathing session:
  → Create Custom("mindfulness") entry with breathing metadata
```
