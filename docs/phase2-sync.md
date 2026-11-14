# Phase 2: Privacy-First Sync

**Goal**: Enable users to sync their encrypted journal across devices without Lumen ever holding keys or seeing plaintext. User owns the encryption passphrase; sync transports ciphertext only.

**Status**: ✅ Shipped. Syncthing and WebDAV both work, the secrets live in
the operating system's keyring, and a conflict is resolved by looking at the
difference between the two versions. What the build turned out to need is
written down at the end of this document, under *What the build changed*.

---

## Threat Model & Principles

| Principle | Implementation |
|-----------|----------------|
| **Zero-knowledge** | Lumen encrypts before write; sync tools see only `.lumen/` ciphertext |
| **User owns keys** | Passphrase never leaves device; no key escrow |
| **Transport agnostic** | Support Syncthing, WebDAV, S3, rsync — user chooses |
| **Conflict-aware** | Detect divergent edits; surface for manual resolution |
| **Offline-first** | Full read/write without network; sync is background |

---

## 1. Syncthing Integration (Primary)

### Why Syncthing
- **E2E encrypted** (TLS + device IDs)
- **No central server** — P2P, NAT traversal via relays
- **Cross-platform** — Linux, macOS, Windows, Android, iOS (via Möbius Sync)
- **Configurable** — ignore patterns, versioning, bandwidth limits
- **Mature** — 10+ years, used by Obsidian, Logseq, Joplin users

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Lumen App                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │ Vault (Rust) │───▶│ .lumen/      │───▶│ Syncthing    │   │
│  │ AES-256-GCM  │    │ journal.json │    │ (external)   │   │
│  │ + Argon2id   │    │ *.md.enc     │    │              │   │
│  └──────────────┘    └──────────────┘    └──────┬───────┘   │
└─────────────────────────────────────────────────│───────────┘
                                                   │
                    ┌──────────────────────────────┼──────────┐
                    ▼                              ▼          ▼
            ┌───────────────┐             ┌───────────────┐ ┌─────────┐
            │ Desktop       │             │ Mobile        │ │ Server  │
            │ (Linux/Mac/Win)             │ (Android/iOS) │ │ (VPS)   │
            └───────────────┘             └───────────────┘ └─────────┘
```

### Core: Sync Status API

**New module**: `core/src/sync.rs`
```rust
#[derive(Debug, Serialize, Deserialize)]
pub struct SyncStatus {
    pub enabled: bool,
    pub method: SyncMethod,
    pub last_sync: Option<DateTime<Utc>>,
    pub pending_changes: usize,
    pub conflicts: Vec<SyncConflict>,
    pub device_status: Vec<DeviceStatus>,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum SyncMethod {
    Syncthing { config_path: String },
    WebDAV { url: String, username: String },
    // S3, rsync, etc.
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncConflict {
    pub path: String,
    pub local_modified: DateTime<Utc>,
    pub remote_modified: DateTime<Utc>,
    pub local_hash: String,   // SHA256 of local ciphertext
    pub remote_hash: String,  // SHA256 of remote ciphertext
    pub source: String,       // "syncthing" or "webdav"
}
```

### Flutter: Syncthing Setup Wizard

**Flow** (`ui/lib/sync/syncthing_wizard.dart`):

```
1. Detect Syncthing
   ├── Not installed → "Install Syncthing" button (opens URL / package manager)
   └── Installed → Check version, API key

2. Configure Folder
   ├── Auto-detect .lumen/ journal folder
   ├── Generate folder ID: lumen-journal-{random}
   ├── Set ignore patterns:
   │   (?i)*.tmp
   │   (?i)*.swp
   │   .lumen/search/          # Tantivy index — rebuild locally
   │   .lumen/*.lock           # Vault lock files
   └── Enable versioning (staggered, 30 days)

3. Device Pairing
   ├── Show QR code with device ID
   ├── "Pair with Mobile" button → opens Möbius Sync / Syncthing app
   └── Wait for connection...

4. Verify
   ├── Create test note → wait for sync → verify on other device
   └── Show "Sync Active" badge in UI
```

**Settings UI** (`ui/lib/settings/sync_settings.dart`):
- Sync method selector (Syncthing / WebDAV / Manual)
- Status dashboard: last sync, pending, conflicts, connected devices
- "Resolve Conflicts" button → conflict resolution UI
- "Force Sync Now" button
- Advanced: bandwidth limits, ignore patterns editor

### TUI: Sync Commands

```bash
lumen sync status           # Show sync status
lumen sync conflicts        # List conflicts
lumen sync resolve <path>   # Interactive conflict resolution
lumen sync webdav           # Two-way sync with the WebDAV account
lumen sync setup syncthing  # Run setup wizard (text-based)
```

### Conflict Detection & Resolution

**Detection** (in `sync.rs`):
```rust
pub fn detect_conflicts(store: &str) -> Vec<SyncConflict> {
    // 1. List all .md files with mtime + SHA256
    // 2. Compare with Syncthing's .stversions/ or WebDAV etag
    // 3. If same file modified on both sides since last sync → conflict
}
```

**Resolution UI** (Flutter):
- Side-by-side diff (decrypted)
- Options: Keep Local / Keep Remote / Merge (opens both in editor)
- "Auto-resolve: newer wins" toggle (per-folder)

**Resolution TUI**:
```
Conflict: 2026-02-03.md
  Local:  modified 14:32, hash a1b2...
  Remote: modified 14:35, hash c3d4...

[L] Keep Local  [R] Keep Remote  [M] Merge in Editor  [S] Show Diff
```

---

## 2. WebDAV Sync (Two-Way)

### Use Cases
- User-controlled cloud (Nextcloud, ownCloud, Box, Yandex, etc.)
- Encrypted two-way sync between devices
- Scheduled, manual, or on demand

### Core: WebDAV Client

**Dependency**: `remotefs-webdav = "1.0"` (the `AsyncRemoteFs` trait)

```rust
// core/src/sync/webdav.rs
pub struct WebDAVConfig {
    pub url: String,
    pub username: String,
    pub password: Option<String>,   // Stored in keyring/keychain — never serialized
    pub encryption_passphrase: Option<String>, // Separate secret, never serialized
    pub encrypt: bool,
}

pub struct WebDAVSync {
    client: WebDAVFs,
    config: WebDAVConfig,
}

/// What one sync did: sent, taken, removed, conflicts, errors.
pub struct SyncReport {
    pub uploaded: Vec<String>,
    pub downloaded: Vec<String>,
    pub deleted: Vec<String>,
    pub conflicts: Vec<SyncConflict>,
    pub errors: Vec<String>,
}

impl WebDAVSync {
    /// Sync the notes of a vault both ways.
    ///
    /// The server keeps a manifest (`lumen-manifest.json`, age-encrypted
    /// when `encrypt` is on) of the notes it holds, with the SHA256 of each
    /// note's ciphertext. Every device keeps a local manifest of the notes
    /// the two sides last agreed on (`<config_dir>/webdav/<fingerprint>/`).
    /// Comparing the local notes, the remote manifest and the local manifest
    /// decides, per note:
    ///
    ///   Push   this device changed it, the other did not
    ///   Pull   the other side changed it, this device did not
    ///   Pull   this device removed it
    ///   Push   the other side removed it
    ///   Conflict  both sides changed it (or both created it) — left alone,
    ///             the remote version is kept in the vault for the user to compare
    ///   None   both sides agree
    ///
    /// Downloaded notes are written raw (the ciphertext the other device
    /// produced), so every device agrees on which bytes a note has. A note
    /// that does not hash to what the manifest promised is refused.
    pub async fn sync_vault(&mut self, store: &str, vault_path: &str) -> Result<SyncReport> { ... }
}
```

### Three-way planning

The decision itself is pure (`core/src/sync_plan.rs`): it takes the local
manifest, the remote manifest and the last-agreed base and returns one
`SyncAction` per note. Nothing is read, written or sent there, so the
decisions can be tested without a server.

### Encryption for Untrusted Storage (age)

**Why age**: Modern, simple, CLI + library, Rust (`rage`) + Go (`age`) implementations

```rust
// Encryption envelope for WebDAV uploads
// File format: age-encrypted with the account's passphrase-derived key
pub fn encrypt_for_upload(data: &[u8], passphrase: &str) -> Vec<u8> {
    let key = derive_backup_key(passphrase); // Argon2id, different salt than vault
    // ...
}
```

### Flutter: WebDAV Setup

- Connection test button
- Encryption toggle (recommended for untrusted providers)
- Schedule: daily / weekly / manual
- Retention: keep last N backups
- "Sync Now" runs a two-way sync and shows how many notes were sent, taken
  and removed, plus any conflicts that need the user

---

## 3. Encrypted Export Bundle

## 3. Encrypted Export Bundle

### Format: `.lumen.bak.age`

```
lumen-journal-2026-02-03.backup.age
├── (age encrypted)
│   ├── journal.json          # Passphrase container (re-encrypted with backup key)
│   ├── 2026-01-01.md
│   ├── 2026-01-02.md
│   └── ...
```

**Creation** (Core):
```rust
pub fn create_backup_bundle(store: &str, passphrase: &str, output: &Path) -> Result<()> {
    // 1. Tar .lumen/ to memory
    // 2. Encrypt with age (backup key derived from passphrase)
    // 3. Write to output
}
```

**Restoration** (Core):
```rust
pub fn restore_backup_bundle(bundle: &Path, passphrase: &str, target: &Path) -> Result<()> {
    // 1. Decrypt with age
    // 2. Untar to target
    // 3. Verify journal.json opens with passphrase
}
```

**Flutter**: "Export Backup" / "Restore Backup" in Settings
**TUI**: `lumen backup create`, `lumen backup restore`

---

## 4. Sync Configuration

```toml
# ~/.config/lumen/config.toml
[sync]
method = "syncthing"  # syncthing, webdav, none

[sync.syncthing]
config_path = "~/.config/syncthing/config.xml"
folder_id = "lumen-journal-a1b2c3"
ignore_patterns = [
    "*.tmp", "*.swp",
    ".lumen/search/",
    ".lumen/*.lock",
]
versioning = "staggered"
versioning_days = 30

[sync.webdav]
url = "https://nextcloud.example.com/remote.php/dav/files/user/lumen/"
username = "user"
# password stored in system keyring
encrypt = true
schedule = "daily"  # daily, weekly, manual
retention = 7

[backup]
auto_export = false
export_path = "~/Backups/Lumen/"
encrypt = true
```

---

## Security Considerations

| Risk | Mitigation |
|------|------------|
| Syncthing config exposes device IDs | Config is local; device IDs are public by design |
| WebDAV credentials in config | Store in OS keyring (libsecret/Keychain/Credential Manager) |
| The server could read the notes | The passphrase that encrypts the uploads is a separate secret from the password of the account, and the server knows only the latter |
| Backup passphrase reuse | Derive separate key via Argon2id with different salt |
| Conflict resolution leaks plaintext | Decrypt only in memory during merge; never log |
| Tantivy index sync | The index lives in the configuration folder, outside the vault; an index left in the vault by an older version is removed on unlock |

---

## Mobile Sync (Preview)

| Platform | Syncthing Client | Notes |
|----------|------------------|-------|
| Android | Syncthing-Fork / official | Background sync via foreground service |
| iOS | Möbius Sync (paid) / iOS Syncthing (limited) | Requires app open for sync; background limited |

**Flutter Mobile**: Reuse same sync status API; show pairing QR in mobile UI

---

## Task Breakdown

| # | Task | Area | Est. |
|---|------|------|------|
| 1 | Sync status core API + conflict detection | Core | 3d |
| 2 | Syncthing config generator + folder setup | Core/Flutter | 3d |
| 3 | Flutter Syncthing wizard (detect, config, pair) | Flutter | 4d |
| 4 | Flutter sync dashboard + conflict resolution UI | Flutter | 4d |
| 5 | TUI sync commands + conflict resolution | TUI | 2d |
| 6 | WebDAV client + age encryption | Core | 3d |
| 7 | Flutter WebDAV setup + schedule | Flutter | 2d |
| 8 | Encrypted backup bundle (create/restore) | Core/Flutter/TUI | 2d |
| 9 | Keyring integration for WebDAV credentials | Core | 1d |
| 10 | Mobile pairing QR + status | Flutter | 2d |

**Total**: ~26 days

---

## Definition of Done

- [ ] Syncthing wizard detects/installs/configures/pairs in <5 min — the
      wizard detects Syncthing, writes the folder configuration and shows
      the device pairing; the pairing QR code for mobile is Phase 3 work
- [x] Sync dashboard shows status, conflicts, devices
- [x] Conflicts resolvable in Flutter (visual diff) and TUI
- [x] WebDAV backup works with Nextcloud, encrypts with age
- [x] Encrypted backup bundle restores on fresh device
- [x] Zero plaintext leaves device; sync transports ciphertext only
- [x] Works offline; sync is background, non-blocking

---

## What the build changed

The plan above is what was written before the work started. A few things
came out differently, and the difference is worth writing down.

### The secrets live in the keyring, and the passphrase is its own secret

The plan said the password of the WebDAV account would be kept in the
keyring. The build went one step further, because the plan's own code had a
problem: the passphrase that encrypted the uploads was the password of the
account.

That is the wrong secret. The server knows the password of the account, so a
server that could decrypt the notes would know too much. The two are now
separate secrets, under separate accounts in the keyring:

| Account | What it is |
|---------|------------|
| `webdav-password` | the password of the account; the server knows it |
| `webdav-passphrase` | the passphrase that encrypts the uploads; the server does not |

Neither travels through the app: the core reads them from the keyring
itself, so the password is never in a call from Dart. The methods are
`kb.sync.credentials.set`, `.status` and `.clear`; the status says whether
the machine has a keyring at all, so a machine without one says so instead
of failing quietly.

### The difference between two versions is worked out in the core

The plan wanted a visual diff. The build had to answer a question first:
*which two versions?*

The version the other device sent is not a note. It is an encrypted file
Syncthing kept under `.stversions/`, and the app could not read it — only
the core can, because only the core can decrypt it with the vault's key.

So the difference is worked out there (`core/src/diff.rs`), and the app is
shown the result:

- `kb.sync.conflict_versions` — the two texts, decrypted
- `kb.sync.conflict_diff` — the difference between them
- `kb.diff.lines` — a difference between any two texts

The difference is line by line, worked out from the lines the two texts
have in common. A note of more than two thousand lines is compared line
against line instead, which is quicker and says less.

### Syncthing is asked, not guessed

The plan had the status showing devices and pending changes. The build had
no way to know either, and said zero.

Syncthing offers a REST interface on the machine, and its own configuration
file holds the address of that interface and the key it asks for. Lumen
reads both and asks the interface, so the status shows which devices are
connected and how much is left to sync. The folder is found by its path, so
a folder Syncthing set up itself works without the identifier having to be
configured.

Syncthing not running is not a failure — the journal works either way — so
the reason is reported alongside the status (`device_error`) rather than
failing it.

### The WebDAV client is `remotefs-webdav`, and the sync is two-way

The plan left the client open and imagined one-way backup. The build uses
`remotefs-webdav` 1.0 and its `AsyncRemoteFs` trait, and the sync goes both
directions:

- The server keeps `lumen-manifest.json` (age-encrypted when `encrypt` is on)
  mapping each note to the SHA256 of its ciphertext.
- Every device keeps a local manifest of the notes it last agreed on with
  the server, under `<config_dir>/webdav/<fingerprint>/`.
- Comparing the three — local notes, remote manifest, local manifest —
  decides per note whether to push, pull, delete, or leave a conflict for
  the user.
- Downloaded notes are written raw, so every device agrees on the bytes a
  note has, and a note that does not hash to its manifest entry is refused.

The pure planning lives in `core/src/sync_plan.rs`; the part that talks to
the server is behind a small `NoteStore` trait, so the whole sync can be
tested without a server.

The result is a `SyncReport` (`uploaded`, `downloaded`, `deleted`,
`conflicts`, `errors`), and the Flutter settings screen says what the sync
did in a snack bar. Conflicts surface in the same conflict-resolution UI
that Syncthing conflicts use, with the source noted (`syncthing` or
`webdav`).

### The method and the account are written to the configuration

The sync method is a setting, so choosing it in the app writes it to the
configuration (`kb.config.set`), and the choice is still there the next time
Lumen starts. The WebDAV address and the name of the account are written
the same way; the password and the passphrase are not.

### The backup is written where the user says

The backup was a fixed path in `/tmp`. The app now asks where the backup
should go and where it should be restored to, and the terminal client takes
both as arguments.
