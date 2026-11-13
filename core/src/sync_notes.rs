//! The sync itself: what to send, what to take, and what to ask about.
//!
//! The notes of a journal live in two places: on this device, and on the
//! server the journal is synced with. This module is the half that decides
//! what happens to each note; the half that talks to the server is the
//! [`NoteStore`]. Keeping the two apart means the decisions can be worked
//! out — and tested — without a server anywhere near.
//!
//! The notes that travel between the devices are the encrypted bytes of the
//! vault, never the plain text: the note is encrypted once, by the device
//! that wrote it, and every other device keeps those same bytes. That is
//! what lets two devices agree on which version of a note they have.

use std::path::Path;

use chrono::{DateTime, Utc};
use remotefs::async_trait;

use crate::sync::SyncConflict;
use crate::sync_plan::{self, Manifest, SyncAction};

/// What a sync did.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct SyncReport {
    /// The notes that were sent to the other side.
    pub uploaded: Vec<String>,
    /// The notes that were taken from the other side.
    pub downloaded: Vec<String>,
    /// The notes that were removed.
    pub deleted: Vec<String>,
    /// The notes that both sides changed.
    pub conflicts: Vec<SyncConflict>,
    /// The notes that could not be synced, and why.
    pub errors: Vec<String>,
}

/// What this device remembers about the other side.
///
/// It lives outside the vault: it is the state of this device, and every
/// device has its own.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct LocalState {
    /// The notes as they were the last time both sides agreed.
    pub base: Manifest,
    /// The notes both sides changed since then.
    #[serde(default)]
    pub conflicts: Vec<SyncConflict>,
}

/// Read what this device remembers about the other side.
pub fn read_local_state(dir: &Path) -> LocalState {
    let raw = match std::fs::read_to_string(dir.join("state.json")) {
        Ok(raw) => raw,
        Err(_) => return LocalState::default(),
    };
    serde_json::from_str(&raw).unwrap_or_default()
}

/// Write down what this device remembers about the other side.
pub fn write_local_state(dir: &Path, state: &LocalState) -> crate::Result<()> {
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let json = serde_json::to_string_pretty(state).map_err(|e| e.to_string())?;
    std::fs::write(dir.join("state.json"), json).map_err(|e| e.to_string())
}

/// A place where the notes of a journal live.
///
/// The store does not read the notes: it carries the encrypted bytes from
/// one device to another, and keeps the manifest that says which notes it
/// has.
#[async_trait]
pub trait NoteStore: Send + Sync {
    /// Send a note.
    async fn put(&mut self, rel_path: &str, data: Vec<u8>) -> crate::Result<()>;

    /// Take a note.
    async fn get(&mut self, rel_path: &str) -> crate::Result<Vec<u8>>;

    /// Remove a note.
    async fn remove(&mut self, rel_path: &str) -> crate::Result<()>;

    /// When the note was last changed.
    async fn modified(&mut self, rel_path: &str) -> crate::Result<DateTime<Utc>>;

    /// The notes the other side has.
    async fn read_manifest(&mut self) -> crate::Result<Manifest>;

    /// Tell the other side what it has.
    async fn write_manifest(&mut self, notes: &Manifest) -> crate::Result<()>;
}

/// Sync the notes of a vault with the other side, both ways.
///
/// The notes are compared with what the other side has and with what the
/// two sides last agreed on, so the sync knows what to send, what to take,
/// and what the user has to decide.
///
/// The notes that both sides changed are left alone: the version the other
/// side has is kept in the vault, so the user can look at the two versions
/// and choose. The sync never decides that itself.
pub async fn sync_notes(
    notes: &mut impl NoteStore,
    vault_store: &str,
    vault_path: &str,
    state_dir: &Path,
) -> crate::Result<SyncReport> {
    let local = crate::sync::local_manifest(vault_path)?;
    let remote = notes.read_manifest().await?;

    let state = read_local_state(state_dir);
    let actions = sync_plan::plan(&local, &remote, &state.base);
    let mut report = SyncReport::default();

    for (rel_path, action) in &actions {
        match action {
            SyncAction::None => {}
            SyncAction::Push => {
                let path = Path::new(vault_path).join(rel_path);
                let data = std::fs::read(&path).map_err(|e| e.to_string())?;
                notes.put(rel_path, data).await?;
                report.uploaded.push(rel_path.clone());
            }
            SyncAction::Pull => {
                match take_note(notes, vault_store, rel_path, remote.get(rel_path)).await {
                    Ok(()) => report.downloaded.push(rel_path.clone()),
                    Err(e) => report.errors.push(e),
                }
            }
            SyncAction::DeleteRemote => {
                notes.remove(rel_path).await?;
                report.deleted.push(rel_path.clone());
            }
            SyncAction::DeleteLocal => {
                crate::vault::delete(rel_path, vault_store)?;
                report.deleted.push(rel_path.clone());
            }
            SyncAction::Conflict => {
                match keep_conflict(
                    notes,
                    vault_store,
                    vault_path,
                    rel_path,
                    remote.get(rel_path),
                )
                .await
                {
                    Ok(conflict) => report.conflicts.push(conflict),
                    Err(e) => report.errors.push(e),
                }
            }
        }
    }

    // The manifest the other side gets holds the notes of both sides. The
    // notes that conflicted keep the version the other side has, because
    // the sync does not decide which of the two is the right one.
    let mut merged = sync_plan::merged_remote(&local, &remote, &actions);
    let fresh = notes.read_manifest().await.unwrap_or_default();
    for (path, hash) in fresh {
        merged.entry(path).or_insert(hash);
    }
    for path in &report.deleted {
        merged.remove(path);
    }
    notes.write_manifest(&merged).await?;

    // The base the next sync starts from keeps the notes that conflicted,
    // so the conflict is still there next time — until the user has had a
    // look at it and made a choice.
    let base = sync_plan::merged_base(&state.base, &merged, &actions);
    let mut new_state = LocalState {
        base,
        conflicts: state.conflicts,
    };
    new_state
        .conflicts
        .retain(|c| !report.conflicts.iter().any(|r| r.path == c.path));
    new_state.conflicts.extend(report.conflicts.clone());
    write_local_state(state_dir, &new_state)?;

    Ok(report)
}

/// Take a note from the other side and put it in the vault.
///
/// The note is checked against the hash the other side gave, so a note that
/// was changed on the way is not written into the journal.
async fn take_note(
    notes: &mut impl NoteStore,
    vault_store: &str,
    rel_path: &str,
    expected: Option<&String>,
) -> crate::Result<()> {
    let blob = notes.get(rel_path).await?;
    let hash = crate::sync::hash_bytes(&blob);
    if let Some(expected) = expected {
        if expected != &hash {
            return Err(format!(
                "the note {rel_path} on the other side does not match its hash"
            ));
        }
    }
    crate::vault::put_encrypted_note(rel_path, &blob, vault_store)
}

/// Keep the version the other side has, so the user can compare it with the
/// local one.
async fn keep_conflict(
    notes: &mut impl NoteStore,
    vault_store: &str,
    vault_path: &str,
    rel_path: &str,
    remote_hash: Option<&String>,
) -> crate::Result<SyncConflict> {
    let blob = notes.get(rel_path).await?;
    let hash = crate::sync::hash_bytes(&blob);
    if let Some(expected) = remote_hash {
        if expected != &hash {
            return Err(format!(
                "the note {rel_path} on the other side does not match its hash"
            ));
        }
    }

    let copy = crate::sync::conflict_copy_path(rel_path);
    crate::vault::put_encrypted_copy(&copy, &blob, vault_store)?;

    let local_path = Path::new(vault_path).join(rel_path);
    let local_modified = crate::sync::file_modified(&local_path)?;
    let remote_modified = notes.modified(rel_path).await?;

    Ok(SyncConflict {
        path: rel_path.to_string(),
        local_modified,
        remote_modified,
        local_hash: crate::sync::file_hash(&local_path)?,
        remote_hash: hash,
        source: "webdav".to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::TestGuard;
    use crate::vault::{self, STORE_JOURNAL};
    use std::collections::BTreeMap;
    use std::path::{Path, PathBuf};
    use tempfile::tempdir;

    /// Run an async test without waiting for a whole runtime of its own.
    fn block_on<F: std::future::Future>(future: F) -> F::Output {
        tokio::runtime::Runtime::new().unwrap().block_on(future)
    }

    /// A store of notes that keeps them in memory.
    ///
    /// It stands in for the server, so the sync can be worked out without a
    /// network anywhere near.
    struct MemoryStore {
        notes: BTreeMap<String, Vec<u8>>,
        manifest: Manifest,
    }

    impl MemoryStore {
        fn new() -> Self {
            Self {
                notes: BTreeMap::new(),
                manifest: Manifest::new(),
            }
        }

        /// Put a note there, the way another device would have sent it.
        fn add(&mut self, rel_path: &str, data: Vec<u8>) {
            self.manifest
                .insert(rel_path.to_string(), crate::sync::hash_bytes(&data));
            self.notes.insert(rel_path.to_string(), data);
        }
    }

    #[remotefs::async_trait]
    impl NoteStore for MemoryStore {
        async fn put(&mut self, rel_path: &str, data: Vec<u8>) -> crate::Result<()> {
            self.notes.insert(rel_path.to_string(), data);
            Ok(())
        }

        async fn get(&mut self, rel_path: &str) -> crate::Result<Vec<u8>> {
            self.notes
                .get(rel_path)
                .cloned()
                .ok_or_else(|| format!("there is no note {rel_path}"))
        }

        async fn remove(&mut self, rel_path: &str) -> crate::Result<()> {
            self.notes.remove(rel_path);
            Ok(())
        }

        async fn modified(&mut self, _rel_path: &str) -> crate::Result<DateTime<Utc>> {
            Ok(Utc::now())
        }

        async fn read_manifest(&mut self) -> crate::Result<Manifest> {
            Ok(self.manifest.clone())
        }

        async fn write_manifest(&mut self, notes: &Manifest) -> crate::Result<()> {
            self.manifest = notes.clone();
            Ok(())
        }
    }

    /// A vault to sync, and the place the state of the sync is kept.
    fn setup() -> (
        tempfile::TempDir,
        tempfile::TempDir,
        String,
        PathBuf,
        TestGuard,
    ) {
        // The vault registry is process-global, so hold the shared lock for
        // the duration of the test.
        let guard = TestGuard::new();

        let vault_temp = tempdir().unwrap();
        let config_temp = tempdir().unwrap();
        let vault_path = vault_temp.path().to_string_lossy().to_string();

        // The index lives outside the vault, so the configuration is pointed
        // at a temporary folder of its own — a test must not write to the
        // user's own configuration.
        crate::config::set_config_dir(Some(config_temp.path().to_path_buf()));

        vault::create_with_passphrase(&vault_path, "testpass123", STORE_JOURNAL).unwrap();
        vault::unlock(&vault_path, "testpass123", STORE_JOURNAL).unwrap();

        let state_dir = config_temp.path().join("webdav-state");
        (vault_temp, config_temp, vault_path, state_dir, guard)
    }

    #[test]
    fn a_new_note_is_sent_to_the_other_side() {
        block_on(async {
            let (_vault, _config, vault_path, state_dir, _guard) = setup();
            vault::write_text("2026-01-01.md", "# Day One", STORE_JOURNAL).unwrap();

            let mut store = MemoryStore::new();
            let report = sync_notes(&mut store, STORE_JOURNAL, &vault_path, &state_dir)
                .await
                .unwrap();

            assert_eq!(report.uploaded, vec!["2026-01-01.md".to_string()]);
            assert!(report.downloaded.is_empty());
            assert!(report.conflicts.is_empty());
            assert!(report.errors.is_empty());
            assert!(store.notes.contains_key("2026-01-01.md"));
            assert!(store.manifest.contains_key("2026-01-01.md"));
        })
    }

    #[test]
    fn a_note_the_other_side_has_is_taken() {
        block_on(async {
            let (_vault, _config, vault_path, state_dir, _guard) = setup();

            // A note another device wrote, encrypted with this vault's key.
            // It is written here first so the vault can encrypt it, and then
            // taken away again: the other device is the one that has it.
            vault::write_text("2026-02-02.md", "a note from another device", STORE_JOURNAL)
                .unwrap();
            let blob = std::fs::read(Path::new(&vault_path).join("2026-02-02.md")).unwrap();
            vault::delete("2026-02-02.md", STORE_JOURNAL).unwrap();

            let mut store = MemoryStore::new();
            store.add("2026-02-02.md", blob.clone());

            let report = sync_notes(&mut store, STORE_JOURNAL, &vault_path, &state_dir)
                .await
                .unwrap();

            assert_eq!(report.downloaded, vec!["2026-02-02.md".to_string()]);
            assert!(report.uploaded.is_empty());
            assert!(report.errors.is_empty());
            assert_eq!(
                vault::read_text("2026-02-02.md", STORE_JOURNAL).unwrap(),
                "a note from another device"
            );

            // The note keeps the bytes it had on the other device: they are
            // what the two devices agree on.
            let on_disk = std::fs::read(Path::new(&vault_path).join("2026-02-02.md")).unwrap();
            assert_eq!(on_disk, blob);
        })
    }

    #[test]
    fn a_note_both_sides_changed_is_a_conflict() {
        block_on(async {
            let (_vault, _config, vault_path, state_dir, _guard) = setup();

            vault::write_text("2026-01-01.md", "the local version", STORE_JOURNAL).unwrap();
            let local = std::fs::read(Path::new(&vault_path).join("2026-01-01.md")).unwrap();

            // The other side has another version of the same note.
            vault::write_text("other.md", "the other version", STORE_JOURNAL).unwrap();
            let remote = std::fs::read(Path::new(&vault_path).join("other.md")).unwrap();
            vault::delete("other.md", STORE_JOURNAL).unwrap();

            let mut store = MemoryStore::new();
            store.add("2026-01-01.md", remote.clone());

            let report = sync_notes(&mut store, STORE_JOURNAL, &vault_path, &state_dir)
                .await
                .unwrap();

            assert_eq!(report.conflicts.len(), 1);
            assert_eq!(report.conflicts[0].path, "2026-01-01.md");
            assert_eq!(report.conflicts[0].source, "webdav");
            assert!(report.uploaded.is_empty());
            assert!(report.downloaded.is_empty());

            // Neither side was changed.
            let still_local = std::fs::read(Path::new(&vault_path).join("2026-01-01.md")).unwrap();
            assert_eq!(still_local, local);
            assert_eq!(store.notes["2026-01-01.md"], remote);

            // The version of the other side is kept, so the user can look at it.
            let copy =
                Path::new(&vault_path).join(crate::sync::conflict_copy_path("2026-01-01.md"));
            assert!(copy.exists());
            assert_eq!(std::fs::read(&copy).unwrap(), remote);
        })
    }

    #[test]
    fn a_second_sync_sends_nothing() {
        block_on(async {
            let (_vault, _config, vault_path, state_dir, _guard) = setup();
            vault::write_text("2026-01-01.md", "# Day One", STORE_JOURNAL).unwrap();

            let mut store = MemoryStore::new();
            sync_notes(&mut store, STORE_JOURNAL, &vault_path, &state_dir)
                .await
                .unwrap();

            let report = sync_notes(&mut store, STORE_JOURNAL, &vault_path, &state_dir)
                .await
                .unwrap();

            assert!(report.uploaded.is_empty());
            assert!(report.downloaded.is_empty());
            assert!(report.deleted.is_empty());
            assert!(report.conflicts.is_empty());
        })
    }

    #[test]
    fn a_note_that_was_removed_here_is_removed_there() {
        block_on(async {
            let (_vault, _config, vault_path, state_dir, _guard) = setup();
            vault::write_text("2026-01-01.md", "# Day One", STORE_JOURNAL).unwrap();

            let mut store = MemoryStore::new();
            sync_notes(&mut store, STORE_JOURNAL, &vault_path, &state_dir)
                .await
                .unwrap();
            assert!(store.notes.contains_key("2026-01-01.md"));

            vault::delete("2026-01-01.md", STORE_JOURNAL).unwrap();
            let report = sync_notes(&mut store, STORE_JOURNAL, &vault_path, &state_dir)
                .await
                .unwrap();

            assert_eq!(report.deleted, vec!["2026-01-01.md".to_string()]);
            assert!(!store.notes.contains_key("2026-01-01.md"));
            assert!(!store.manifest.contains_key("2026-01-01.md"));
        })
    }

    #[test]
    fn a_note_that_was_removed_there_is_removed_here() {
        block_on(async {
            let (_vault, _config, vault_path, state_dir, _guard) = setup();
            vault::write_text("2026-01-01.md", "# Day One", STORE_JOURNAL).unwrap();

            let mut store = MemoryStore::new();
            sync_notes(&mut store, STORE_JOURNAL, &vault_path, &state_dir)
                .await
                .unwrap();

            // The other side removed it.
            store.notes.remove("2026-01-01.md");
            store.manifest.remove("2026-01-01.md");

            let report = sync_notes(&mut store, STORE_JOURNAL, &vault_path, &state_dir)
                .await
                .unwrap();

            assert_eq!(report.deleted, vec!["2026-01-01.md".to_string()]);
            assert!(vault::read_text("2026-01-01.md", STORE_JOURNAL).is_err());
        })
    }

    #[test]
    fn a_note_that_does_not_match_its_hash_is_not_written() {
        block_on(async {
            let (_vault, _config, vault_path, state_dir, _guard) = setup();

            let mut store = MemoryStore::new();
            // The manifest says one thing, the note is another.
            store.manifest.insert(
                "2026-01-01.md".to_string(),
                crate::sync::hash_bytes(b"something else"),
            );
            store.notes.insert(
                "2026-01-01.md".to_string(),
                b"not a note of this vault".to_vec(),
            );

            let report = sync_notes(&mut store, STORE_JOURNAL, &vault_path, &state_dir)
                .await
                .unwrap();

            assert_eq!(report.errors.len(), 1);
            assert!(report.downloaded.is_empty());
            assert!(vault::read_text("2026-01-01.md", STORE_JOURNAL).is_err());
        })
    }
}
