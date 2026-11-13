//! Sync module for Lumen - Syncthing, WebDAV, and backup support.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use age_core::secrecy::SecretString;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::config;

lazy_static::lazy_static! {
    static ref SYNC_STATE: Mutex<Option<SyncState>> = Mutex::new(None);
}

/// Sync method type.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type")]
pub enum SyncMethod {
    #[serde(rename = "syncthing")]
    Syncthing { config_path: String },
    #[serde(rename = "webdav")]
    WebDAV { url: String, username: String },
    #[serde(rename = "none")]
    None,
}

/// Sync status for UI display.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncStatus {
    pub enabled: bool,
    pub method: SyncMethod,
    pub last_sync: Option<DateTime<Utc>>,
    pub pending_changes: usize,
    pub conflicts: Vec<SyncConflict>,
    pub device_status: Vec<DeviceStatus>,
    /// Why the devices could not be asked about, if they could not.
    ///
    /// Syncthing may simply not be running, which is not an error: the
    /// journal works either way. The reason is here so the app can say so.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device_error: Option<String>,
}

/// A sync conflict between local and remote versions.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncConflict {
    pub path: String,
    pub local_modified: DateTime<Utc>,
    pub remote_modified: DateTime<Utc>,
    pub local_hash: String,
    pub remote_hash: String,
    /// Where the conflict came from: "syncthing" or "webdav".
    #[serde(default = "default_conflict_source")]
    pub source: String,
}

fn default_conflict_source() -> String {
    "syncthing".to_string()
}

/// Connected device status (from Syncthing).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceStatus {
    pub id: String,
    pub name: String,
    pub connected: bool,
    pub last_seen: Option<DateTime<Utc>>,
}

/// Internal sync state.
#[derive(Debug, Clone)]
struct SyncState {
    vault_path: String,
    /// The store the vault belongs to.
    store: String,
    last_scan: Option<DateTime<Utc>>,
    file_hashes: HashMap<String, (DateTime<Utc>, String)>, // path -> (mtime, sha256)
}

/// Get SHA256 hash of a file.
pub(crate) fn file_hash(path: &Path) -> crate::Result<String> {
    let data = fs::read(path).map_err(|e| e.to_string())?;
    Ok(hash_bytes(&data))
}

/// The hash of some bytes.
pub(crate) fn hash_bytes(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hex::encode(hasher.finalize())
}

/// Get file modified time.
pub(crate) fn file_modified(path: &Path) -> crate::Result<DateTime<Utc>> {
    let metadata = fs::metadata(path).map_err(|e| e.to_string())?;
    let modified = metadata.modified().map_err(|e| e.to_string())?;
    let datetime: DateTime<Utc> = modified.into();
    Ok(datetime)
}

/// Whether a file in the vault is a note that is synced.
///
/// The metadata folder holds the wrapped key, the search index and the
/// copies of the other side's version that a conflict leaves behind — none
/// of which are notes of the journal.
fn is_synced_note(path: &Path, vault_root: &Path) -> bool {
    let Ok(rel) = path.strip_prefix(vault_root) else {
        return false;
    };
    let mut components = rel.components();
    let Some(first) = components.next() else {
        return false;
    };
    if first.as_os_str() == crate::vault::META_DIR {
        return false;
    }
    path.extension().and_then(|s| s.to_str()) == Some("md")
}

/// The notes in the vault, with the hash of their encrypted bytes.
///
/// The hash is of the bytes on disk, which are encrypted: every device that
/// has the note has the same bytes, so the hashes can be compared across
/// devices.
pub(crate) fn local_manifest(vault_path: &str) -> crate::Result<crate::sync_plan::Manifest> {
    let root = Path::new(vault_path);
    let mut notes = crate::sync_plan::Manifest::new();

    for entry in walkdir::WalkDir::new(root) {
        let entry = entry.map_err(|e| e.to_string())?;
        if !entry.file_type().is_file() {
            continue;
        }
        let path = entry.path();
        if !is_synced_note(path, root) {
            continue;
        }
        let rel_path = path
            .strip_prefix(root)
            .map_err(|_| "Path not in vault")?
            .to_string_lossy()
            .replace('\\', "/");
        notes.insert(rel_path, file_hash(path)?);
    }

    Ok(notes)
}

/// Where the version the other side sent is kept, so the user can look at it.
///
/// The copy lives inside the vault, so it is encrypted like a note and the
/// app can read both versions without asking the server again.
pub fn conflict_copy_path(path: &str) -> String {
    format!("{}/conflicts/{}", crate::vault::META_DIR, path)
}

/// Initialize sync state for a vault.
pub fn init_sync(vault_path: &str) -> crate::Result<()> {
    init_sync_store(crate::vault::STORE_JOURNAL, vault_path)
}

/// Initialize sync state for a store of a vault.
pub fn init_sync_store(store: &str, vault_path: &str) -> crate::Result<()> {
    let config = config::get_config();
    if config.sync.method == "none" {
        return Ok(());
    }

    let mut state = SyncState {
        vault_path: vault_path.to_string(),
        store: store.to_string(),
        last_scan: None,
        file_hashes: HashMap::new(),
    };

    // Initial scan
    scan_vault(&mut state)?;

    let mut guard = SYNC_STATE.lock().unwrap();
    *guard = Some(state);
    Ok(())
}

/// Scan vault for files and compute hashes.
fn scan_vault(state: &mut SyncState) -> crate::Result<()> {
    state.file_hashes.clear();
    let vault_path = Path::new(&state.vault_path);

    // Walk all .md files in vault
    for entry in walkdir::WalkDir::new(vault_path) {
        let entry = entry.map_err(|e| e.to_string())?;
        if !entry.file_type().is_file() {
            continue;
        }
        let path = entry.path();
        if !is_synced_note(path, vault_path) {
            continue;
        }

        // Get relative path from vault root
        let rel_path = path
            .strip_prefix(vault_path)
            .map_err(|_| "Path not in vault")?
            .to_string_lossy()
            .replace('\\', "/")
            .to_string();

        let modified = file_modified(path)?;
        let hash = file_hash(path)?;

        state.file_hashes.insert(rel_path, (modified, hash));
    }

    state.last_scan = Some(Utc::now());
    Ok(())
}

/// Get current sync status.
pub fn get_sync_status() -> crate::Result<SyncStatus> {
    let config = config::get_config();
    let state_guard = SYNC_STATE.lock().unwrap();

    let method = parse_sync_method(&config.sync.method);

    let (enabled, last_sync, mut conflicts) = if let Some(state) = state_guard.as_ref() {
        let conflicts = detect_conflicts(state)?;
        (true, state.last_scan, conflicts)
    } else {
        (false, None, Vec::new())
    };

    // The devices and the pending changes come from Syncthing itself, when
    // it is there to be asked.
    let mut device_status = Vec::new();
    let mut pending_changes = 0;
    let mut device_error = None;

    if enabled && config.sync.method == "syncthing" {
        let vault_path = state_guard
            .as_ref()
            .map(|state| state.vault_path.clone())
            .unwrap_or_default();

        match crate::syncthing::status(&vault_path) {
            Ok(status) => {
                device_status = status
                    .devices
                    .into_iter()
                    .map(|device| DeviceStatus {
                        id: device.id,
                        name: device.name,
                        connected: device.connected,
                        last_seen: device.last_seen,
                    })
                    .collect();
                pending_changes = status.pending;
            }
            Err(e) => device_error = Some(e),
        }
    }

    // The conflicts of a WebDAV account are the ones the last sync found;
    // they are kept until the user has had a look at them.
    if enabled && config.sync.method == "webdav" {
        if let Some(state) = state_guard.as_ref() {
            let dir = webdav::state_dir(
                &config.sync.webdav.url,
                &config.sync.webdav.username,
                &state.store,
                &state.vault_path,
            );
            conflicts.extend(webdav::read_state(&dir).conflicts);
        }
    }

    Ok(SyncStatus {
        enabled,
        method,
        last_sync,
        pending_changes,
        conflicts,
        device_status,
        device_error,
    })
}

fn parse_sync_method(s: &str) -> SyncMethod {
    match s {
        "syncthing" => SyncMethod::Syncthing { config_path: String::new() },
        "webdav" => SyncMethod::WebDAV { url: String::new(), username: String::new() },
        _ => SyncMethod::None,
    }
}

/// Detect conflicts by comparing local hashes with remote (Syncthing .stversions).
fn detect_conflicts(state: &SyncState) -> crate::Result<Vec<SyncConflict>> {
    let mut conflicts = Vec::new();
    let vault_path = Path::new(&state.vault_path);

    for (rel_path, (local_mtime, local_hash)) in &state.file_hashes {
        // Check Syncthing versioning folder for conflicts
        let stversions_path = vault_path.join(".stversions").join(rel_path);
        if stversions_path.exists() {
            // Find the latest versioned file
            if let Ok(entries) = fs::read_dir(&stversions_path) {
                let mut latest_remote: Option<(DateTime<Utc>, String)> = None;
                for entry in entries.flatten() {
                    if entry.file_type().map(|t| t.is_file()).unwrap_or(false) {
                        let remote_mtime = file_modified(&entry.path())?;
                        let remote_hash = file_hash(&entry.path())?;
                        if latest_remote.is_none() || remote_mtime > latest_remote.as_ref().unwrap().0 {
                            latest_remote = Some((remote_mtime, remote_hash));
                        }
                    }
                }

                if let Some((remote_mtime, remote_hash)) = latest_remote {
                    if remote_hash != *local_hash && remote_mtime > *local_mtime {
                        conflicts.push(SyncConflict {
                            path: rel_path.clone(),
                            local_modified: *local_mtime,
                            remote_modified: remote_mtime,
                            local_hash: local_hash.clone(),
                            remote_hash,
                            source: "syncthing".to_string(),
                        });
                    }
                }
            }
        }
    }

    Ok(conflicts)
}

/// The two versions of a conflicted note, decrypted.
///
/// The note and the version the other side sent are both encrypted with the
/// vault's key, so both are read through the vault and come back as text.
/// The difference between them is what the user is asked to look at.
pub fn conflict_versions(
    store: &str,
    vault_path: &str,
    path: &str,
) -> crate::Result<(String, String)> {
    let local = crate::vault::read_text(path, store)?;

    // A WebDAV account leaves the version it had inside the vault, so the
    // difference can be shown without asking the server again.
    let copy = conflict_copy_path(path);
    let copy_full = Path::new(vault_path).join(&copy);
    if copy_full.exists() {
        let remote = crate::vault::read_text(&copy, store)?;
        return Ok((local, remote));
    }

    let stversions_path = Path::new(vault_path).join(".stversions").join(path);
    let mut latest: Option<(DateTime<Utc>, PathBuf)> = None;
    if stversions_path.exists() {
        for entry in fs::read_dir(&stversions_path)
            .map_err(|e| e.to_string())?
            .flatten()
        {
            if entry.file_type().map(|t| t.is_file()).unwrap_or(false) {
                let mtime = file_modified(&entry.path())?;
                if latest.is_none() || mtime > latest.as_ref().unwrap().0 {
                    latest = Some((mtime, entry.path()));
                }
            }
        }
    }

    let Some((_, latest_path)) = latest else {
        return Err("there is no remote version of this note".into());
    };

    // The version sits inside the vault, so it is read through the vault
    // and comes back decrypted.
    let relative = latest_path
        .strip_prefix(vault_path)
        .map_err(|_| "the remote version is not in the vault")?
        .to_string_lossy()
        .to_string();
    let remote = crate::vault::read_text(&relative, store)?;

    Ok((local, remote))
}

/// Resolve a conflict by choosing local or remote version.
pub fn resolve_conflict(path: &str, keep_local: bool) -> crate::Result<()> {
    let (store, vault_path) = {
        let state_guard = SYNC_STATE.lock().unwrap();
        let state = state_guard.as_ref().ok_or("Sync not initialized")?;
        (state.store.clone(), state.vault_path.clone())
    };

    // A WebDAV account keeps the version it had inside the vault, so it is
    // settled here rather than by Syncthing's folder of versions.
    let copy = conflict_copy_path(path);
    let copy_full = Path::new(&vault_path).join(&copy);
    if copy_full.exists() {
        resolve_webdav_conflict(&store, &vault_path, path, &copy, keep_local)?;
    } else {
        resolve_syncthing_conflict(&vault_path, path, keep_local)?;
    }

    // Rescan
    {
        let mut state_guard = SYNC_STATE.lock().unwrap();
        if let Some(state) = state_guard.as_mut() {
            scan_vault(state)?;
        }
    }

    Ok(())
}

/// Settle a conflict of a WebDAV account.
///
/// The version the other side had is the one the server still has, so the
/// base of the account becomes that version: the next sync then carries the
/// local choice over, or finds that both sides agree.
fn resolve_webdav_conflict(
    store: &str,
    vault_path: &str,
    path: &str,
    copy: &str,
    keep_local: bool,
) -> crate::Result<()> {
    let copy_full = Path::new(vault_path).join(copy);
    let remote_hash = file_hash(&copy_full)?;

    if !keep_local {
        // Take the version the other side had.
        crate::vault::copy_encrypted_note(copy, path, store)?;
    }
    fs::remove_file(&copy_full).map_err(|e| e.to_string())?;

    let config = config::get_config();
    let dir = webdav::state_dir(
        &config.sync.webdav.url,
        &config.sync.webdav.username,
        store,
        vault_path,
    );
    let mut state = webdav::read_state(&dir);
    state.base.insert(path.to_string(), remote_hash);
    state.conflicts.retain(|c| c.path != path);
    webdav::write_state(&dir, &state)
}

/// Settle a conflict Syncthing found.
fn resolve_syncthing_conflict(vault_path: &str, path: &str, keep_local: bool) -> crate::Result<()> {
    let file_path = Path::new(vault_path).join(path);
    let stversions_path = Path::new(vault_path).join(".stversions").join(path);

    if keep_local {
        // Remove remote versions, keep local
        if stversions_path.exists() {
            fs::remove_dir_all(&stversions_path).map_err(|e| e.to_string())?;
        }
    } else {
        // Restore latest remote version
        if stversions_path.exists() {
            let mut latest: Option<(DateTime<Utc>, PathBuf)> = None;
            for entry in fs::read_dir(&stversions_path)
                .map_err(|e| e.to_string())?
                .flatten()
            {
                if entry.file_type().map(|t| t.is_file()).unwrap_or(false) {
                    let mtime = file_modified(&entry.path())?;
                    if latest.is_none() || mtime > latest.as_ref().unwrap().0 {
                        latest = Some((mtime, entry.path()));
                    }
                }
            }
            if let Some((_, latest_path)) = latest {
                fs::copy(&latest_path, &file_path).map_err(|e| e.to_string())?;
            }
        }
    }

    Ok(())
}

/// Generate Syncthing folder configuration.
pub fn generate_syncthing_config(vault_path: &str) -> crate::Result<String> {
    let config = config::get_config();
    let folder_id = if config.sync.syncthing.folder_id.is_empty() {
        format!("lumen-journal-{}", uuid::Uuid::new_v4().simple())
    } else {
        config.sync.syncthing.folder_id.clone()
    };

    let ignore_patterns = config.sync.syncthing.ignore_patterns.join("\n      - ");

    let xml = format!(
        r#"<folder id="{}" label="Lumen Journal" path="{}" type="sendreceive" rescanIntervalS="300" fsWatcherEnabled="true" fsWatcherDelayS="10" ignorePerms="false" autoNormalize="true">
      <versioning>
        <type>staggered</type>
        <params>
          <param key="maxAge" value="{}"/>
          <param key="cleanupIntervalS" value="86400"/>
        </params>
      </versioning>
      <ignorePatterns>
        - {}
      </ignorePatterns>
      <devices>
      </devices>
    </folder>"#,
        folder_id,
        vault_path,
        config.sync.syncthing.versioning_days * 86400,
        ignore_patterns
    );

    Ok(xml)
}

/// Create encrypted backup bundle using age.
pub fn create_backup_bundle(vault_path: &str, passphrase: &str, output: &Path) -> crate::Result<()> {
    use std::io::Write;

    // Create tar.gz in memory
    let mut tar = tar::Builder::new(Vec::new());
    let vault_root = Path::new(vault_path);

    for entry in walkdir::WalkDir::new(vault_root) {
        let entry = entry.map_err(|e| e.to_string())?;
        let path = entry.path();
        if path == vault_root {
            continue;
        }
        let rel_path = path.strip_prefix(vault_root).map_err(|_| "Path not in vault")?;
        if entry.file_type().is_file() {
            tar.append_path_with_name(path, rel_path).map_err(|e| e.to_string())?;
        } else if entry.file_type().is_dir() {
            tar.append_dir(rel_path.to_string_lossy().as_ref(), path).map_err(|e| e.to_string())?;
        }
    }
    let tar_data = tar.into_inner().map_err(|e| e.to_string())?;

    // Compress with gzip
    let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
    gz.write_all(&tar_data).map_err(|e| e.to_string())?;
    let compressed = gz.finish().map_err(|e| e.to_string())?;

    // Encrypt with age (using passphrase-derived key)
    let encrypted = encrypt_with_age(&compressed, passphrase)?;

    // Write to output
    fs::write(output, encrypted).map_err(|e| e.to_string())?;
    Ok(())
}

/// Restore encrypted backup bundle.
pub fn restore_backup_bundle(bundle_path: &Path, passphrase: &str, target_dir: &Path) -> crate::Result<()> {
    // Read encrypted bundle
    let encrypted = fs::read(bundle_path).map_err(|e| e.to_string())?;

    // Decrypt with age
    let compressed = decrypt_with_age(&encrypted, passphrase)?;

    // Decompress gzip
    let mut gz = flate2::read::GzDecoder::new(&compressed[..]);
    let mut tar_data = Vec::new();
    std::io::Read::read_to_end(&mut gz, &mut tar_data).map_err(|e| e.to_string())?;

    // Extract tar
    let mut tar = tar::Archive::new(&tar_data[..]);
    tar.unpack(target_dir).map_err(|e| e.to_string())?;

    Ok(())
}

/// Encrypt data with age using passphrase.
fn encrypt_with_age(data: &[u8], passphrase: &str) -> crate::Result<Vec<u8>> {
    let secret = SecretString::new(passphrase.to_string().into());
    let encryptor = age::Encryptor::with_user_passphrase(secret);
    let mut encrypted = Vec::new();
    {
        let mut writer = encryptor.wrap_output(&mut encrypted).map_err(|e| e.to_string())?;
        std::io::Write::write_all(&mut writer, data).map_err(|e| e.to_string())?;
        writer.finish().map_err(|e| e.to_string())?;
    }
    Ok(encrypted)
}

/// Decrypt data with age.
fn decrypt_with_age(data: &[u8], passphrase: &str) -> crate::Result<Vec<u8>> {
    let secret = SecretString::new(passphrase.to_string().into());
    let identity = age::scrypt::Identity::new(secret);
    let decryptor = age::Decryptor::new_buffered(&data[..]).map_err(|e| e.to_string())?;
    let mut reader = decryptor.decrypt(std::iter::once(&identity as &dyn age::Identity)).map_err(|e| e.to_string())?;
    let mut decrypted = Vec::new();
    std::io::Read::read_to_end(&mut reader, &mut decrypted).map_err(|e| e.to_string())?;
    Ok(decrypted)
}

/// WebDAV sync implementation using remotefs-webdav.
///
/// The notes are synced both ways. Every device keeps a manifest of the
/// notes it has seen the other side agree on, and the server keeps a
/// manifest of the notes it has. Comparing the two tells Lumen what to
/// send, what to take and what the user has to decide.
pub mod webdav {
    use super::*;
    use crate::sync_plan::Manifest;
    use dav_xml_client::Auth;
    use futures::AsyncReadExt;
    use remotefs::fs::{AsyncRemoteFs, File, ReadOptions, WriteOptions};
    use remotefs_webdav::WebDAVFs;
    use serde::{Deserialize, Serialize};

    /// The name of the manifest that says what is on the server.
    pub const MANIFEST_FILE: &str = "lumen-manifest.json";

    /// WebDAV connection settings.
    #[derive(Debug, Clone, Serialize, Deserialize)]
    pub struct WebDAVConfig {
        pub url: String,
        pub username: String,
        /// Never serialized — the password lives in the OS keyring.
        #[serde(skip_serializing)]
        pub password: Option<String>,
        /// Never serialized — the passphrase lives in the OS keyring.
        ///
        /// It is not the password of the account: the server knows that one,
        /// and a server that could read the notes would know too much.
        #[serde(skip_serializing)]
        pub encryption_passphrase: Option<String>,
        pub encrypt: bool,
    }

    /// What the server says it has.
    #[derive(Debug, Clone, Default, Serialize, Deserialize)]
    struct RemoteManifest {
        /// The version of the manifest, so a later change can be told apart.
        #[serde(default)]
        version: u32,
        /// The notes on the server, with the hash of their encrypted bytes.
        #[serde(default)]
        notes: Manifest,
    }

    /// The folder holding what Lumen remembers about an account.
    ///
    /// Every account and every vault gets a folder of its own, so two
    /// journals never share a base.
    pub fn state_dir(url: &str, username: &str, store: &str, vault_path: &str) -> PathBuf {
        let mut hasher = Sha256::new();
        hasher.update(url.as_bytes());
        hasher.update([0]);
        hasher.update(username.as_bytes());
        hasher.update([0]);
        hasher.update(store.as_bytes());
        hasher.update([0]);
        hasher.update(vault_path.as_bytes());
        let fingerprint = hex::encode(&hasher.finalize()[..8]);
        config::config_dir().join("webdav").join(fingerprint)
    }

    /// Read what Lumen remembers about an account.
    pub fn read_state(dir: &Path) -> crate::sync_notes::LocalState {
        crate::sync_notes::read_local_state(dir)
    }

    /// Write down what Lumen remembers about an account.
    pub fn write_state(dir: &Path, state: &crate::sync_notes::LocalState) -> crate::Result<()> {
        crate::sync_notes::write_local_state(dir, state)
    }

    /// A connected WebDAV client.
    pub struct WebDAVSync {
        client: WebDAVFs,
        config: WebDAVConfig,
    }

    impl WebDAVSync {
        /// Connect to the endpoint and verify the credentials.
        pub async fn new(config: WebDAVConfig) -> crate::Result<Self> {
            let auth = Auth::Basic {
                username: config.username.clone(),
                password: config.password.clone().unwrap_or_default(),
            };
            let mut client = WebDAVFs::new(&config.url, auth).map_err(|e| e.to_string())?;
            client.connect().await.map_err(|e| e.to_string())?;

            Ok(Self { client, config })
        }

        /// The path a note has on the server.
        fn note_path(&self, rel_path: &str) -> String {
            if self.config.encrypt {
                format!("/{rel_path}.age")
            } else {
                format!("/{rel_path}")
            }
        }

        /// The path the manifest has on the server.
        fn manifest_path(&self) -> String {
            if self.config.encrypt {
                format!("/{MANIFEST_FILE}.age")
            } else {
                format!("/{MANIFEST_FILE}")
            }
        }

        /// Upload a local file, age-encrypting it when `encrypt` is set.
        pub async fn upload(&mut self, local_path: &Path, remote_path: &str) -> crate::Result<()> {
            let data = fs::read(local_path).map_err(|e| e.to_string())?;

            let (data, remote_path) = if self.config.encrypt {
                let passphrase = self.encryption_passphrase()?;
                (
                    encrypt_with_age(&data, passphrase)?,
                    format!("{}.age", remote_path),
                )
            } else {
                (data, remote_path.to_string())
            };

            self.write_file(&remote_path, data).await
        }

        /// Download a remote file, age-decrypting it when `encrypt` is set.
        pub async fn download(
            &mut self,
            remote_path: &str,
            local_path: &Path,
        ) -> crate::Result<()> {
            let remote_path = if self.config.encrypt {
                format!("{}.age", remote_path)
            } else {
                remote_path.to_string()
            };

            let data = self.read_file(&remote_path).await?;
            let data = if self.config.encrypt {
                let passphrase = self.encryption_passphrase()?;
                decrypt_with_age(&data, passphrase)?
            } else {
                data
            };

            fs::write(local_path, data).map_err(|e| e.to_string())?;
            Ok(())
        }

        /// The passphrase that encrypts the uploads.
        ///
        /// Without one the uploads cannot be encrypted, and saying so is
        /// better than sending the notes in the clear.
        fn encryption_passphrase(&self) -> crate::Result<&str> {
            self.config
                .encryption_passphrase
                .as_deref()
                .filter(|passphrase| !passphrase.is_empty())
                .ok_or_else(|| {
                    "the uploads are encrypted, so a passphrase is needed; \
                     keep one in the keyring"
                        .to_string()
                })
        }

        /// List the names of the files directly under `remote_path`.
        pub async fn list(&mut self, remote_path: &str) -> crate::Result<Vec<String>> {
            let entries = self
                .client
                .list_dir(Path::new(remote_path))
                .await
                .map_err(|e| e.to_string())?;

            Ok(entries
                .into_iter()
                .filter(|entry| entry.is_file())
                .map(|entry| entry.name())
                .collect())
        }

        /// Every file on the server, with the path it has there.
        ///
        /// A listing only holds the direct children of a folder, so the
        /// folders are walked as well: the notes of a journal live in
        /// folders of their own.
        pub async fn list_recursive(&mut self, remote_path: &str) -> crate::Result<Vec<File>> {
            let mut files = Vec::new();
            let mut folders = vec![remote_path.to_string()];

            while let Some(folder) = folders.pop() {
                let entries = self
                    .client
                    .list_dir(Path::new(&folder))
                    .await
                    .map_err(|e| e.to_string())?;
                for entry in entries {
                    if entry.is_dir() {
                        folders.push(entry.path().to_string_lossy().into_owned());
                    } else {
                        files.push(entry);
                    }
                }
            }

            Ok(files)
        }

        /// Read a file from the server.
        async fn read_file(&mut self, remote_path: &str) -> crate::Result<Vec<u8>> {
            let mut stream = self
                .client
                .open(Path::new(remote_path), &ReadOptions::default())
                .await
                .map_err(|e| e.to_string())?;
            let mut data = Vec::new();
            stream
                .read_to_end(&mut data)
                .await
                .map_err(|e| e.to_string())?;
            stream.finish().await.map_err(|e| e.to_string())?;
            Ok(data)
        }

        /// Write a file to the server.
        async fn write_file(&mut self, remote_path: &str, data: Vec<u8>) -> crate::Result<()> {
            self.ensure_parent(remote_path).await?;
            let mut cursor = futures::io::Cursor::new(data);
            self.client
                .write_file(
                    Path::new(remote_path),
                    &WriteOptions::default(),
                    &mut cursor,
                )
                .await
                .map_err(|e| e.to_string())?;
            Ok(())
        }

        /// Make sure the folders of a path are there.
        ///
        /// WebDAV needs the collection to exist before the file in it, and
        /// the server says so when it is not.
        async fn ensure_parent(&mut self, remote_path: &str) -> crate::Result<()> {
            let path = Path::new(remote_path);
            let Some(parent) = path.parent() else {
                return Ok(());
            };

            let mut current = PathBuf::from("/");
            for part in parent.components() {
                if !matches!(part, std::path::Component::Normal(_)) {
                    continue;
                }
                current.push(part);
                if self.client.exists(&current).await.unwrap_or(false) {
                    continue;
                }
                // The folder may have been made between the check and the
                // call, so a failure here is not the end of it: the write
                // that follows says what is really wrong.
                let _ = self.client.create_dir(&current, None).await;
            }
            Ok(())
        }

        /// Read what the server says it has.
        async fn read_manifest_file(&mut self) -> crate::Result<Manifest> {
            let path = self.manifest_path();
            if !self.client.exists(Path::new(&path)).await.unwrap_or(false) {
                // The server has no manifest: it has no notes as far as
                // Lumen is concerned.
                return Ok(Manifest::new());
            }

            let data = self.read_file(&path).await?;
            let data = if self.config.encrypt {
                let passphrase = self.encryption_passphrase()?;
                decrypt_with_age(&data, passphrase)?
            } else {
                data
            };

            let raw = String::from_utf8(data)
                .map_err(|e| format!("the manifest on the server is not text: {e}"))?;
            let manifest: RemoteManifest = serde_json::from_str(&raw)
                .map_err(|e| format!("the manifest on the server cannot be read: {e}"))?;
            Ok(manifest.notes)
        }

        /// Tell the server what it has.
        async fn write_manifest_file(&mut self, notes: &Manifest) -> crate::Result<()> {
            let manifest = RemoteManifest {
                version: 1,
                notes: notes.clone(),
            };
            let json = serde_json::to_string_pretty(&manifest).map_err(|e| e.to_string())?;
            let data = if self.config.encrypt {
                let passphrase = self.encryption_passphrase()?;
                encrypt_with_age(json.as_bytes(), passphrase)?
            } else {
                json.into_bytes()
            };
            let path = self.manifest_path();
            self.write_file(&path, data).await
        }

        /// Sync the notes of a vault with the server, both ways.
        ///
        /// The notes are compared with what the server has and with what the
        /// two sides last agreed on, so the sync knows what to send, what to
        /// take, and what the user has to decide.
        pub async fn sync_vault(
            &mut self,
            store: &str,
            vault_path: &str,
        ) -> crate::Result<crate::sync_notes::SyncReport> {
            let dir = state_dir(&self.config.url, &self.config.username, store, vault_path);
            crate::sync_notes::sync_notes(self, store, vault_path, &dir).await
        }
    }

    #[remotefs::async_trait]
    impl crate::sync_notes::NoteStore for WebDAVSync {
        async fn put(&mut self, rel_path: &str, data: Vec<u8>) -> crate::Result<()> {
            let data = if self.config.encrypt {
                let passphrase = self.encryption_passphrase()?;
                encrypt_with_age(&data, passphrase)?
            } else {
                data
            };
            let path = self.note_path(rel_path);
            self.write_file(&path, data).await
        }

        async fn get(&mut self, rel_path: &str) -> crate::Result<Vec<u8>> {
            let path = self.note_path(rel_path);
            let data = self.read_file(&path).await?;
            if self.config.encrypt {
                let passphrase = self.encryption_passphrase()?;
                decrypt_with_age(&data, passphrase)
            } else {
                Ok(data)
            }
        }

        async fn remove(&mut self, rel_path: &str) -> crate::Result<()> {
            let path = self.note_path(rel_path);
            self.client
                .remove_file(Path::new(&path))
                .await
                .map_err(|e| e.to_string())
        }

        async fn modified(&mut self, rel_path: &str) -> crate::Result<DateTime<Utc>> {
            let path = self.note_path(rel_path);
            let entry = self
                .client
                .stat(Path::new(&path))
                .await
                .map_err(|e| e.to_string())?;
            match entry.metadata.modified {
                Some(modified) => Ok(modified.into()),
                None => Ok(Utc::now()),
            }
        }

        async fn read_manifest(&mut self) -> crate::Result<Manifest> {
            self.read_manifest_file().await
        }

        async fn write_manifest(&mut self, notes: &Manifest) -> crate::Result<()> {
            self.write_manifest_file(notes).await
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vault::{self, STORE_JOURNAL};
    use tempfile::tempdir;

    fn setup_test_vault() -> (tempfile::TempDir, String, crate::testutil::TestGuard) {
        // The vault registry is process-global, so hold the shared lock for
        // the duration of the test.
        let guard = crate::testutil::TestGuard::new();

        let temp = tempdir().unwrap();
        let vault_path = temp.path().to_string_lossy().to_string();
        vault::create_with_passphrase(&vault_path, "testpass123", STORE_JOURNAL).unwrap();
        vault::unlock(&vault_path, "testpass123", STORE_JOURNAL).unwrap();
        (temp, vault_path, guard)
    }

    /// Turn the sync on, the way the configuration does.
    ///
    /// The configuration is process-global, so this is done while the test
    /// holds the lock.
    fn use_syncthing() {
        let mut config = config::load_config();
        config.sync.method = "syncthing".to_string();
        config::set_config(config);
    }

    #[test]
    fn test_init_sync() {
        let (_temp, vault_path, _guard) = setup_test_vault();

        // Set sync method to syncthing for this test
        use_syncthing();

        vault::write_text("2026-01-01.md", "# Day One", STORE_JOURNAL).unwrap();
        vault::write_text("2026-01-02.md", "# Day Two", STORE_JOURNAL).unwrap();

        init_sync(&vault_path).unwrap();

        let status = get_sync_status().unwrap();
        assert!(status.enabled);
        assert_eq!(status.conflicts.len(), 0);
    }

    #[test]
    fn test_backup_bundle() {
        let (_temp, vault_path, _guard) = setup_test_vault();
        vault::write_text("2026-01-01.md", "# Day One", STORE_JOURNAL).unwrap();

        let backup_path = Path::new(&vault_path).join("backup.lumen.bak.age");
        create_backup_bundle(&vault_path, "testpass123", &backup_path).unwrap();

        assert!(backup_path.exists());

        // Test restore
        let restore_dir = Path::new(&vault_path).join("restore");
        restore_backup_bundle(&backup_path, "testpass123", &restore_dir).unwrap();

        assert!(restore_dir.join("2026-01-01.md").exists());
    }

    /// The version Syncthing kept is encrypted like the note itself, so
    /// both versions come back as text.
    #[test]
    fn test_the_two_versions_of_a_conflict_are_read_decrypted() {
        let (_temp, vault_path, _guard) = setup_test_vault();

        // The version Syncthing would have kept.
        vault::write_text("2026-01-01.md", "# Remote version\n\nchanged", STORE_JOURNAL).unwrap();
        let versions = Path::new(&vault_path).join(".stversions").join("2026-01-01.md");
        fs::create_dir_all(&versions).unwrap();
        fs::copy(
            Path::new(&vault_path).join("2026-01-01.md"),
            versions.join("2026-01-01.md.20260101-120000.md"),
        )
        .unwrap();

        // The note as it stands now.
        vault::write_text("2026-01-01.md", "# Local version\n\noriginal", STORE_JOURNAL).unwrap();

        init_sync(&vault_path).unwrap();

        let (local, remote) =
            conflict_versions(STORE_JOURNAL, &vault_path, "2026-01-01.md").unwrap();

        assert_eq!(local, "# Local version\n\noriginal");
        assert_eq!(remote, "# Remote version\n\nchanged");
    }

    /// A note without a remote version has nothing to compare with.
    #[test]
    fn test_a_note_without_a_remote_version() {
        let (_temp, vault_path, _guard) = setup_test_vault();
        vault::write_text("2026-01-01.md", "# Day One", STORE_JOURNAL).unwrap();
        init_sync(&vault_path).unwrap();

        assert!(conflict_versions(STORE_JOURNAL, &vault_path, "2026-01-01.md").is_err());
    }
}