//! The "tank": encrypted off-site storage for *any* file on the filesystem.
//!
//! A file the user chooses to encrypt is split into fixed-size chunks, each
//! encrypted with the tank's AES-256-GCM key and stored as an identical-size
//! blob inside the tank folder (`<tank>/blobs/<random>.blob`). Because every
//! blob is exactly `12 + 8192 + 16` bytes the folder is a uniform pile of
//! ciphertext — no file contents or sizes leak at a glance.
//!
//! In the file's original location only a plaintext *marker* remains: the
//! original file is replaced by `<name>.lumen-tank`, a small JSON document
//! naming the blobs and the original filename/size. Decrypting restores the
//! original file; deleting removes marker + blobs.
//!
//! The tank has its own passphrase (Argon2id) and is stateful like a vault
//! store: it is set up once, unlocked per session, and locked on demand.

pub mod ffi;

use std::collections::HashMap;
use std::fs;
use std::io::{BufWriter, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use base64::Engine;
use lazy_static::lazy_static;
use serde::{Deserialize, Serialize};

use crate::entry::encryption::{decrypt, encrypt};
use crate::vault::hex_decode;

pub const MARKER_SUFFIX: &str = ".lumen-tank";
pub const META_DIR: &str = ".lumen-tank";
pub const CONFIG_FILE: &str = "config.json";
pub const BLOBS_DIR: &str = "blobs";

/// Plaintext bytes per chunk. Every blob is exactly this size + nonce + tag,
/// so all ciphertext in the tank is uniform regardless of source file.
pub const CHUNK_SIZE: usize = 8192;

/// Production KDF parameters (Argon2id).
const M_COST: u32 = 19 * 1024;
const T_COST: u32 = 2;
const P_COST: u32 = 1;

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct TankConfig {
    pub version: u32,
    pub cipher: String,
    pub kdf: String,
    pub salt: String,
    pub m_cost: u32,
    pub t_cost: u32,
    pub p_cost: u32,
    /// Passphrase-wrapped tank data key; AES-GCM auth rejects wrong
    /// passphrases at unlock time.
    pub data_key: String,
    pub data_key_nonce: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct TankMarker {
    pub fmt: String,
    /// Basename of the original file (marker = `<name>.lumen-tank`).
    pub name: String,
    /// Original file size in bytes (last chunk is trimmed to this).
    pub size: u64,
    /// Blob paths relative to the tank root (e.g. `blobs/ab12….blob`).
    pub chunks: Vec<String>,
}

#[derive(Default)]
struct TankState {
    root: Option<PathBuf>,
    config: Option<TankConfig>,
    data_key: Option<[u8; 32]>,
}

lazy_static! {
    static ref TANK: Mutex<TankState> = Mutex::new(TankState::default());
}

fn config_path(root: &Path) -> PathBuf {
    root.join(META_DIR).join(CONFIG_FILE)
}

/// Snapshot of the tank state (root, config, key) so callers never hold the
/// global lock across filesystem work.
fn tank_clone() -> Result<(PathBuf, TankConfig, [u8; 32]), String> {
    let tank = TANK.lock().unwrap();
    let root = tank
        .root
        .clone()
        .ok_or_else(|| "Tank is not set up. Choose a location first.".to_string())?;
    let config = tank
        .config
        .clone()
        .ok_or_else(|| "Tank is not configured".to_string())?;
    let data_key = tank.data_key.ok_or_else(|| "Tank is locked".to_string())?;
    Ok((root, config, data_key))
}

fn derive_master(pass: &str, salt: &[u8], m_cost: &u32, t_cost: &u32, p_cost: &u32) -> Result<[u8; 32], String> {
    let params = argon2::Params::new(*m_cost, *t_cost, *p_cost, Some(32))
        .map_err(|e| format!("bad argon2 params: {e}"))?;
    let argon2 = argon2::Argon2::new(argon2::Algorithm::Argon2id, argon2::Version::V0x13, params);
    let mut key = [0u8; 32];
    argon2
        .hash_password_into(pass.as_bytes(), salt, &mut key)
        .map_err(|e| format!("key derivation failed: {e}"))?;
    Ok(key)
}

fn blob_path(root: &Path, rel: &str) -> Result<PathBuf, String> {
    let full = root.join(rel);
    if full.components().any(|c| matches!(c, std::path::Component::ParentDir)) {
        return Err("Blob path escapes the tank".into());
    }
    let canonical_root = root.canonicalize().unwrap_or_else(|_| root.to_path_buf());
    let canonical_full = full.canonicalize().unwrap_or_else(|_| full.clone());
    if !canonical_full.starts_with(&canonical_root) {
        return Err("Blob path is outside the tank".into());
    }
    Ok(full)
}

/// Whether `path` names a tank marker file (encrypted).
pub fn is_marker(path: &Path) -> bool {
    path.extension().map_or(false, |e| e == "lumen-tank")
}

pub fn marker_sibling(path: &Path) -> PathBuf {
    let mut s = path.as_os_str().to_owned();
    s.push(MARKER_SUFFIX);
    PathBuf::from(s)
}

/// Whether a tank is currently set up (config on disk) and unlocked.
pub fn status() -> serde_json::Value {
    let tank = TANK.lock().unwrap();
    let root = tank.root.clone();
    let setup = root
        .as_ref()
        .map(|r| config_path(r).exists())
        .unwrap_or(false);
    serde_json::json!({
        "setup": setup,
        "unlocked": tank.data_key.is_some(),
        "root": root,
    })
}

/// Records the tank location if it was already set up on disk. Does not
/// require the passphrase — unlocking happens separately.
pub fn set_path(root: &str) -> Result<(), String> {
    let root_path = Path::new(root);
    if !config_path(root_path).exists() {
        return Err("No tank is set up at this path yet".into());
    }
    let raw = fs::read_to_string(config_path(root_path)).map_err(|e| e.to_string())?;
    let config: TankConfig = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    TANK.lock().unwrap().root = Some(root_path.to_path_buf());
    TANK.lock().unwrap().config = Some(config);
    Ok(())
}

/// Create a tank at `root` with `passphrase`, and leave it unlocked.
pub fn setup(root: &str, passphrase: &str) -> Result<(), String> {
    setup_with_params(root, passphrase, M_COST, T_COST, P_COST)
}

/// Setup with explicit KDF parameters (tests use cheap ones).
fn setup_with_params(
    root: &str,
    passphrase: &str,
    m_cost: u32,
    t_cost: u32,
    p_cost: u32,
) -> Result<(), String> {
    let root_path = Path::new(root);
    if config_path(root_path).exists() {
        return Err("A tank already exists at this path".into());
    }
    fs::create_dir_all(root_path.join(META_DIR)).map_err(|e| e.to_string())?;
    fs::create_dir_all(root_path.join(BLOBS_DIR)).map_err(|e| e.to_string())?;

    let salt: [u8; 16] = rand::random();
    let master = derive_master(passphrase, &salt, &m_cost, &t_cost, &p_cost)?;
    let data_key: [u8; 32] = rand::random();
    let (wrapped, nonce) = encrypt(&data_key, &master);
    let engine = base64::engine::general_purpose::STANDARD;
    let config = TankConfig {
        version: 1,
        cipher: "aes-256-gcm".into(),
        kdf: "argon2id".into(),
        salt: salt.iter().map(|b| format!("{b:02x}")).collect(),
        m_cost,
        t_cost,
        p_cost,
        data_key: engine.encode(&wrapped),
        data_key_nonce: engine.encode(&nonce),
    };

    let json = serde_json::to_string_pretty(&config).map_err(|e| e.to_string())?;
    fs::write(config_path(root_path), json).map_err(|e| e.to_string())?;

    let mut tank = TANK.lock().unwrap();
    tank.root = Some(root_path.to_path_buf());
    tank.config = Some(config);
    tank.data_key = Some(data_key);
    Ok(())
}

/// Unlock an existing tank at `root` with `passphrase`.
pub fn unlock(root: &str, passphrase: &str) -> Result<(), String> {
    let root_path = Path::new(root);
    if !config_path(root_path).exists() {
        return Err("No tank found at this path".into());
    }
    let raw = fs::read_to_string(config_path(root_path)).map_err(|e| e.to_string())?;
    let config: TankConfig = serde_json::from_str(&raw).map_err(|e| e.to_string())?;

    let salt = hex_decode(&config.salt)?;
    let master = derive_master(passphrase, &salt, &config.m_cost, &config.t_cost, &config.p_cost)?;

    let engine = base64::engine::general_purpose::STANDARD;
    let wrapped = engine
        .decode(&config.data_key)
        .map_err(|e| format!("bad data_key: {e}"))?;
    let nonce = engine
        .decode(&config.data_key_nonce)
        .map_err(|e| format!("bad data_key_nonce: {e}"))?;
    let data_key_bytes = decrypt(&wrapped, &nonce, &master)?;
    if data_key_bytes.len() != 32 {
        return Err("decrypted tank key has invalid length".into());
    }
    let mut data_key = [0u8; 32];
    data_key.copy_from_slice(&data_key_bytes);

    let mut tank = TANK.lock().unwrap();
    tank.root = Some(root_path.to_path_buf());
    tank.config = Some(config);
    tank.data_key = Some(data_key);
    Ok(())
}

pub fn lock() {
    let mut tank = TANK.lock().unwrap();
    tank.data_key = None;
}

/// Encrypt `path` (any file, anywhere): move its bytes into the tank as
/// uniform blobs and leave `<path>.lumen-tank` marker in its place.
pub fn encrypt_file(path: &str) -> Result<serde_json::Value, String> {
    let (root, _config, key) = tank_clone()?;
    let src = Path::new(path);
    if is_marker(src) {
        return Err("File is already encrypted".into());
    }
    if marker_sibling(src).exists() {
        return Err("A marker for this file already exists; decrypt it first".into());
    }
    if src.is_dir() {
        return Err("Only files can be tank-encrypted".into());
    }
    if !src.exists() {
        return Err("File does not exist".into());
    }

    let name = src
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .ok_or_else(|| "Path has no file name".to_string())?;
    let size = fs::metadata(src).map_err(|e| e.to_string())?.len();

    let blobs = src.parent().unwrap_or_else(|| Path::new("/")).join(BLOBS_DIR);
    fs::create_dir_all(&blobs).map_err(|e| e.to_string())?;

    let mut chunk_refs: Vec<String> = Vec::new();
    let written: Result<(), String> = (|| {
        let mut file = fs::File::open(src).map_err(|e| e.to_string())?;
        let mut remaining = size;
        loop {
            if remaining == 0 {
                break;
            }
            let take = remaining.min(CHUNK_SIZE as u64) as usize;
            let mut buf = vec![0u8; CHUNK_SIZE];
            file.read_exact(&mut buf[..take]).map_err(|e| e.to_string())?;
            remaining -= take as u64;

            let (ciphertext, nonce) = encrypt(&buf, &key);
            let mut blob = Vec::with_capacity(12 + ciphertext.len());
            blob.extend_from_slice(&nonce);
            blob.extend_from_slice(&ciphertext);

            let id: [u8; 16] = rand::random();
            let rel = format!("{}/{}", BLOBS_DIR, hex_encode(&id));
            let dest = root.join(&rel);
            fs::write(&dest, blob).map_err(|e| e.to_string())?;
            chunk_refs.push(rel);
        }
        Ok(())
    })();

    if let Err(e) = written {
        // Best effort: drop blobs we may have partially written.
        for rel in &chunk_refs {
            if let Ok(p) = blob_path(&root, rel) {
                let _ = fs::remove_file(p);
            }
        }
        return Err(e);
    }

    let marker = TankMarker {
        fmt: "lumen-tank-v1".into(),
        name,
        size,
        chunks: chunk_refs,
    };
    let json = serde_json::to_string(&marker).map_err(|e| e.to_string())?;
    if let Err(e) = fs::write(marker_sibling(src), json) {
        for rel in &marker.chunks {
            if let Ok(p) = blob_path(&root, rel) {
                let _ = fs::remove_file(p);
            }
        }
        return Err(e.to_string());
    }

    fs::remove_file(src).map_err(|e| e.to_string())?;

    Ok(serde_json::json!({
        "encrypted": marker.name,
        "size": marker.size,
        "chunks": marker.chunks.len(),
    }))
}

fn load_marker(path: &Path) -> Result<TankMarker, String> {
    let raw = fs::read_to_string(path).map_err(|e| e.to_string())?;
    let marker: TankMarker = serde_json::from_str(&raw).map_err(|e| format!("bad marker: {e}"))?;
    if marker.fmt != "lumen-tank-v1" {
        return Err("Unknown marker format".into());
    }
    Ok(marker)
}

/// Restore the original file from its tank blobs; removes the marker.
pub fn decrypt_file(path: &str) -> Result<serde_json::Value, String> {
    let (root, _config, key) = tank_clone()?;
    let marker_path = Path::new(path);
    if !is_marker(marker_path) {
        return Err("Not a tank-encrypted file".into());
    }
    let marker = load_marker(marker_path)?;

    let original = marker_path.with_extension(""); // strip `.lumen-tank`
    let tmp = original.with_extension("lumen-tmp");
    let out: Result<(), String> = (|| {
        if let Some(parent) = tmp.parent() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let mut writer = BufWriter::new(fs::File::create(&tmp).map_err(|e| e.to_string())?);
        let mut written_total = 0u64;
        let num_chunks = marker.chunks.len();
        for (i, rel) in marker.chunks.iter().enumerate() {
            let blob_file = blob_path(&root, rel)?;
            if !blob_file.exists() {
                return Err(format!("Missing blob for chunk {}", i + 1));
            }
            let bytes = fs::read(&blob_file).map_err(|e| e.to_string())?;
            if bytes.len() != 12 + CHUNK_SIZE + 16 {
                return Err(format!("Blob {} has an unexpected size", i + 1));
            }
            let plaintext = decrypt(&bytes[12..], &bytes[..12], &key)?;
            let is_last = i == num_chunks - 1;
            let keep = if is_last {
                let rem = marker.size - written_total;
                rem.min(CHUNK_SIZE as u64) as usize
            } else {
                CHUNK_SIZE
            };
            writer.write_all(&plaintext[..keep]).map_err(|e| e.to_string())?;
            written_total += keep as u64;
        }
        Ok(())
    })();

    if let Err(e) = out {
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    if fs::metadata(&tmp).map(|m| m.len()).unwrap_or(0) != marker.size {
        let _ = fs::remove_file(&tmp);
        return Err("Decrypted size mismatch".into());
    }

    fs::rename(&tmp, &original).map_err(|e| e.to_string())?;
    fs::remove_file(marker_path).map_err(|e| e.to_string())?;

    Ok(serde_json::json!({
        "decrypted": marker.name,
        "size": marker.size,
    }))
}

/// Delete a file. Encrypted markers also remove their tank blobs.
pub fn delete_file(path: &str) -> Result<serde_json::Value, String> {
    let p = Path::new(path);
    if is_marker(p) {
        let marker = load_marker(p)?;
        if let Ok((root, _config, _key)) = tank_clone() {
            for rel in &marker.chunks {
                if let Ok(blob) = blob_path(&root, rel) {
                    let _ = fs::remove_file(blob);
                }
            }
        }
        fs::remove_file(p).map_err(|e| e.to_string())?;
        return Ok(serde_json::json!({ "deleted": path, "mode": "tank" }));
    }
    if p.is_dir() {
        fs::remove_dir_all(p).map_err(|e| e.to_string())?;
    } else {
        fs::remove_file(p).map_err(|e| e.to_string())?;
    }
    Ok(serde_json::json!({ "deleted": path, "mode": "plain" }))
}

/// Describe a path: encrypted (marker) or plain.
pub fn info_file(path: &str) -> Result<serde_json::Value, String> {
    let p = Path::new(path);
    if !p.exists() {
        return Err("Path does not exist".into());
    }
    if !is_marker(p) {
        return Ok(serde_json::json!({ "encrypted": false, "path": path, "is_dir": p.is_dir() }));
    }
    let marker = load_marker(p)?;
    Ok(serde_json::json!({
        "encrypted": true,
        "path": path,
        "name": marker.name,
        "size": marker.size,
        "chunks": marker.chunks.len(),
    }))
}

/// All blob paths currently present in the tank (for reporting).
pub fn blob_inventory() -> Result<Vec<serde_json::Value>, String> {
    let tank = TANK.lock().unwrap();
    let root = tank.root.clone().ok_or_else(|| "Tank is not set up".to_string())?;
    let blobs_dir = root.join(BLOBS_DIR);
    let mut out = Vec::new();
    if let Ok(read) = fs::read_dir(blobs_dir) {
        let mut entries: Vec<_> = read.flatten().collect();
        entries.sort_by_key(|e| e.file_name());
        for de in entries {
            let len = de.metadata().map(|m| m.len()).unwrap_or(0);
            out.push(serde_json::json!({
                "name": de.file_name().to_string_lossy().into_owned(),
                "size": len,
            }));
        }
    }
    Ok(out)
}

/// Orphan blobs — present in the tank but referenced by no marker anywhere.
pub fn orphaned_blobs(root: &str) -> Result<Vec<String>, String> {
    let root = Path::new(root);
    let mut referenced: HashMap<String, ()> = HashMap::new();
    collect_markers(root, &mut referenced)?;
    let mut orphans = Vec::new();
    if let Ok(read) = fs::read_dir(root.join(BLOBS_DIR)) {
        for de in read.flatten() {
            let file_name = de.file_name().to_string_lossy().into_owned();
            let rel = format!("{BLOBS_DIR}/{file_name}");
            if !referenced.contains_key(&rel) {
                orphans.push(rel);
            }
        }
    }
    Ok(orphans)
}

fn collect_markers(dir: &Path, referenced: &mut HashMap<String, ()>) -> Result<(), String> {
    let read = match fs::read_dir(dir) {
        Ok(r) => r,
        Err(_) => return Ok(()),
    };
    for de in read.flatten() {
        let path = de.path();
        if path.is_dir() {
            let name = de.file_name().to_string_lossy().into_owned();
            if name == META_DIR || name == BLOBS_DIR {
                continue;
            }
            collect_markers(&path, referenced)?;
        } else if is_marker(&path) {
            if let Ok(marker) = load_marker(&path) {
                for chunk in marker.chunks {
                    referenced.insert(chunk, ());
                }
            }
        }
    }
    Ok(())
}

pub fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    static TEST_LOCK: Mutex<()> = Mutex::new(());
    const M: u32 = 8 * 1024;
    const T: u32 = 1;
    const P: u32 = 1;

    fn test_lock() -> std::sync::MutexGuard<'static, ()> {
        let g = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        lock();
        g
    }

    fn temp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("lumen_tank_{name}_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    fn setup_test(root: &Path) {
        setup_with_params(root.to_str().unwrap(), "tank-pass", M, T, P).unwrap();
    }

    #[test]
    fn setup_unlock_status_roundtrip() {
        let _g = test_lock();
        let dir = temp_dir("setup");
        setup_test(&dir);
        assert!(status()["setup"].as_bool().unwrap());
        assert!(status()["unlocked"].as_bool().unwrap());

        lock();
        assert!(!status()["unlocked"].as_bool().unwrap());
        assert!(encrypt_file("/does/not/exist").is_err());

        unlock(dir.to_str().unwrap(), "wrong-pass").unwrap_err();
        unlock(dir.to_str().unwrap(), "tank-pass").unwrap();
        assert!(status()["unlocked"].as_bool().unwrap());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn encrypt_decrypt_roundtrip_preserves_bytes() {
        let _g = test_lock();
        let tank = temp_dir("roundtrip_tank");
        let src_dir = temp_dir("roundtrip_src").join("sub");
        fs::create_dir_all(&src_dir).unwrap();
        setup_test(&tank);

        const TEXT: &str = "Dear diary, the tank swallowed my secrets whole. 🐟";
        let src = src_dir.join("diary.txt");
        fs::write(&src, TEXT).unwrap();

        let marker_path = marker_sibling(&src);
        let info = encrypt_file(src.to_str().unwrap()).unwrap();
        assert_eq!(info["encrypted"].as_str().unwrap(), "diary.txt");
        assert!(!src.exists(), "original must be removed");
        assert!(marker_path.exists(), "marker must remain");

        // Uniform blobs: every blob in the tank is identical in size.
        let sizes: Vec<u64> = blob_inventory().unwrap().iter().map(|b| b["size"].as_u64().unwrap()).collect();
        assert!(!sizes.is_empty());
        let expected = (12 + CHUNK_SIZE + 16) as u64;
        assert!(sizes.iter().all(|s| *s == expected), "blobs must be uniform: {sizes:?}");

        // Chunk count matches the byte size.
        let expected_chunks = (TEXT.len() as u64).div_ceil(CHUNK_SIZE as u64);
        assert_eq!(info["chunks"].as_u64().unwrap(), expected_chunks);

        let dec = decrypt_file(marker_path.to_str().unwrap()).unwrap();
        assert_eq!(dec["decrypted"].as_str().unwrap(), "diary.txt");
        assert!(src.exists());
        assert_eq!(fs::read_to_string(&src).unwrap(), TEXT);
        assert!(!marker_path.exists());
        // Decrypt preserves blobs (reversible); they become orphans the
        // cleanup path can reclaim once the marker is gone.
        let orphans = orphaned_blobs(tank.to_str().unwrap()).unwrap();
        assert_eq!(orphans.len(), blob_inventory().unwrap().len());

        fs::remove_dir_all(&tank).unwrap();
        fs::remove_dir_all(src_dir).unwrap();
    }

    #[test]
    fn multiline_chunks_roundtrip() {
        let _g = test_lock();
        let tank = temp_dir("multi_tank");
        let src_dir = temp_dir("multi_src");
        fs::create_dir_all(&src_dir).unwrap();
        setup_test(&tank);

        // Slightly more than two full chunks.
        let data: Vec<u8> = (0u8..(CHUNK_SIZE * 2 + 37) as u8).cycle().take(CHUNK_SIZE * 2 + 37).collect();
        let src = src_dir.join("blob.bin");
        fs::write(&src, &data).unwrap();

        encrypt_file(src.to_str().unwrap()).unwrap();
        let decrypted = decrypt_file(marker_sibling(&src).to_str().unwrap()).unwrap();
        assert_eq!(decrypted["size"].as_u64().unwrap(), data.len() as u64);
        assert_eq!(fs::read(&src).unwrap(), data);
        assert_eq!(blob_inventory().unwrap().len(), 3, "2 full + 1 partial chunk");

        fs::remove_dir_all(&tank).unwrap();
        fs::remove_dir_all(src_dir).unwrap();
    }

    #[test]
    fn delete_removes_marker_and_blobs() {
        let _g = test_lock();
        let tank = temp_dir("del_tank");
        let src_dir = temp_dir("del_src");
        fs::create_dir_all(&src_dir).unwrap();
        setup_test(&tank);

        let a = src_dir.join("keep.txt");
        let b = src_dir.join("drop.md");
        fs::write(&a, "keep me").unwrap();
        fs::write(&b, "drop me").unwrap();

        encrypt_file(a.to_str().unwrap()).unwrap();
        encrypt_file(b.to_str().unwrap()).unwrap();

        let before = blob_inventory().unwrap().len();
        assert!(before >= 2);

        let res = delete_file(marker_sibling(&b).to_str().unwrap()).unwrap();
        assert_eq!(res["mode"].as_str().unwrap(), "tank");
        assert!(!marker_sibling(&b).exists());
        assert_eq!(blob_inventory().unwrap().len(), before - 1);

        fs::remove_dir_all(&tank).unwrap();
        fs::remove_dir_all(src_dir).unwrap();
    }

    #[test]
    fn wrong_double_and_missing_errors() {
        let _g = test_lock();
        let tank = temp_dir("err_tank");
        let src_dir = temp_dir("err_src");
        fs::create_dir_all(&src_dir).unwrap();
        setup_test(&tank);

        let src = src_dir.join("x.txt");
        fs::write(&src, "hello").unwrap();

        // Encrypting twice errors out.
        encrypt_file(src.to_str().unwrap()).unwrap();
        assert!(encrypt_file(marker_sibling(&src).to_str().unwrap()).is_err());
        assert!(encrypt_file(src.to_str().unwrap()).is_err(), "original is gone");

        // info() reports encrypted.
        let info = info_file(marker_sibling(&src).to_str().unwrap()).unwrap();
        assert!(info["encrypted"].as_bool().unwrap());
        assert_eq!(info["name"].as_str().unwrap(), "x.txt");

        // decrypt of a plain file errors.
        let plain = src_dir.join("plain.txt");
        fs::write(&plain, "plain").unwrap();
        assert!(decrypt_file(plain.to_str().unwrap()).is_err());

        // info() reports not-encrypted.
        let info2 = info_file(plain.to_str().unwrap()).unwrap();
        assert!(!info2["encrypted"].as_bool().unwrap());

        fs::remove_dir_all(&tank).unwrap();
        fs::remove_dir_all(src_dir).unwrap();
    }

    #[test]
    fn zero_byte_file_roundtrip() {
        let _g = test_lock();
        let tank = temp_dir("empty_tank");
        let src_dir = temp_dir("empty_src");
        fs::create_dir_all(&src_dir).unwrap();
        setup_test(&tank);

        let src = src_dir.join("empty.bin");
        fs::write(&src, b"").unwrap();
        encrypt_file(src.to_str().unwrap()).unwrap();
        assert_eq!(blob_inventory().unwrap().len(), 0);
        decrypt_file(marker_sibling(&src).to_str().unwrap()).unwrap();
        assert!(src.exists());
        assert_eq!(fs::metadata(&src).unwrap().len(), 0);

        fs::remove_dir_all(&tank).unwrap();
        fs::remove_dir_all(src_dir).unwrap();
    }
}