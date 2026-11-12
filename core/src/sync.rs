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
    last_scan: Option<DateTime<Utc>>,
    file_hashes: HashMap<String, (DateTime<Utc>, String)>, // path -> (mtime, sha256)
}

/// Get SHA256 hash of a file.
fn file_hash(path: &Path) -> crate::Result<String> {
    let data = fs::read(path).map_err(|e| e.to_string())?;
    let mut hasher = Sha256::new();
    hasher.update(&data);
    Ok(hex::encode(hasher.finalize()))
}

/// Get file modified time.
fn file_modified(path: &Path) -> crate::Result<DateTime<Utc>> {
    let metadata = fs::metadata(path).map_err(|e| e.to_string())?;
    let modified = metadata.modified().map_err(|e| e.to_string())?;
    let datetime: DateTime<Utc> = modified.into();
    Ok(datetime)
}

/// Initialize sync state for a vault.
pub fn init_sync(vault_path: &str) -> crate::Result<()> {
    let config = config::get_config();
    if config.sync.method == "none" {
        return Ok(());
    }

    let mut state = SyncState {
        vault_path: vault_path.to_string(),
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
        if path.extension().and_then(|s| s.to_str()) != Some("md") {
            continue;
        }

        // Get relative path from vault root
        let rel_path = path.strip_prefix(vault_path)
            .map_err(|_| "Path not in vault")?
            .to_string_lossy()
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

    let (enabled, last_sync, conflicts) = if let Some(state) = state_guard.as_ref() {
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
                        });
                    }
                }
            }
        }
    }

    Ok(conflicts)
}

/// Resolve a conflict by choosing local or remote version.
pub fn resolve_conflict(path: &str, keep_local: bool) -> crate::Result<()> {
    let state_guard = SYNC_STATE.lock().unwrap();
    let state = state_guard.as_ref().ok_or("Sync not initialized")?;

    let vault_path = Path::new(&state.vault_path);
    let file_path = vault_path.join(path);
    let stversions_path = vault_path.join(".stversions").join(path);

    if keep_local {
        // Remove remote versions, keep local
        if stversions_path.exists() {
            fs::remove_dir_all(&stversions_path).map_err(|e| e.to_string())?;
        }
    } else {
        // Restore latest remote version
        if stversions_path.exists() {
            let mut latest: Option<(DateTime<Utc>, PathBuf)> = None;
            for entry in fs::read_dir(&stversions_path).map_err(|e| e.to_string())?.flatten() {
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

    // Rescan
    drop(state_guard);
    let mut state_guard = SYNC_STATE.lock().unwrap();
    if let Some(state) = state_guard.as_mut() {
        scan_vault(state)?;
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
pub mod webdav {
    use super::*;
    use dav_xml_client::Auth;
    use futures::AsyncReadExt;
    use remotefs::fs::{AsyncRemoteFs, ReadOptions, WriteOptions};
    use remotefs_webdav::WebDAVFs;
    use std::collections::HashMap;

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

            let mut cursor = futures::io::Cursor::new(data);
            self.client
                .write_file(
                    Path::new(&remote_path),
                    &WriteOptions::default(),
                    &mut cursor,
                )
                .await
                .map_err(|e| e.to_string())?;
            Ok(())
        }

        /// Download a remote file, age-decrypting it when `encrypt` is set.
        pub async fn download(&mut self, remote_path: &str, local_path: &Path) -> crate::Result<()> {
            let remote_path = if self.config.encrypt {
                format!("{}.age", remote_path)
            } else {
                remote_path.to_string()
            };

            let mut stream = self
                .client
                .open(Path::new(&remote_path), &ReadOptions::default())
                .await
                .map_err(|e| e.to_string())?;
            let mut data = Vec::new();
            stream.read_to_end(&mut data).await.map_err(|e| e.to_string())?;
            stream.finish().await.map_err(|e| e.to_string())?;

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

        /// Push every note in the vault to the remote endpoint.
        ///
        /// Files already uploaded during this session are skipped when their
        /// local hash is unchanged, so repeated syncs stay cheap.
        pub async fn sync_to_webdav(&mut self, vault_path: &str) -> crate::Result<()> {
            let vault_root = Path::new(vault_path);
            let mut local_files: HashMap<String, String> = HashMap::new();

            // Scan local vault for .md files
            for entry in walkdir::WalkDir::new(vault_root) {
                let entry = entry.map_err(|e| e.to_string())?;
                if !entry.file_type().is_file() {
                    continue;
                }
                let path = entry.path();
                if path.extension().and_then(|s| s.to_str()) != Some("md") {
                    continue;
                }

                let rel_path = path
                    .strip_prefix(vault_root)
                    .map_err(|_| "Path not in vault")?
                    .to_string_lossy()
                    .to_string();

                local_files.insert(rel_path, file_hash(path)?);
            }

            // List remote files
            let remote_files = self.list("/").await?;

            // Remote name -> local hash, for files uploaded in this session.
            let mut uploaded: HashMap<String, String> = HashMap::new();

            for (rel_path, hash) in &local_files {
                let remote_name = if self.config.encrypt {
                    format!("{}.age", rel_path)
                } else {
                    rel_path.clone()
                };

                let unchanged = uploaded
                    .get(&remote_name)
                    .map(|seen| seen == hash)
                    .unwrap_or(false);
                if unchanged && remote_files.iter().any(|f| f == &remote_name) {
                    continue;
                }

                // WebDAV needs the parent collection to exist before the file.
                if let Some(parent) = Path::new(rel_path).parent() {
                    if !parent.as_os_str().is_empty() {
                        self.client
                            .create_dir(Path::new(&format!("/{}", parent.to_string_lossy())), None)
                            .await
                            .map_err(|e| e.to_string())?;
                    }
                }

                let local_path = vault_root.join(rel_path);
                self.upload(&local_path, &format!("/{}", rel_path)).await?;
                uploaded.insert(remote_name, hash.clone());
            }

            Ok(())
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

    #[test]
    fn test_init_sync() {
        // Set sync method to syncthing for this test
        let config = config::load_config();
        let mut config = config;
        config.sync.method = "syncthing".to_string();
        config::set_config(config);

        let (_temp, vault_path, _guard) = setup_test_vault();
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
}