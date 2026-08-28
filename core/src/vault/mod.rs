//! Whole-vault encryption for Lumen.
//!
//! A vault is a folder protected by a passphrase:
//!   - `.lumen/config.json` holds KDF salt/params and a passphrase-wrapped data key.
//!   - File *contents* are stored as `nonce(12) || AES-256-GCM ciphertext`.
//!   - Unlocking derives a master key via Argon2id and unwraps the per-vault data key.
//!   - While unlocked, reads/writes transparently encrypt/decrypt with the data key.

pub mod ffi;

use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use base64::Engine;
use lazy_static::lazy_static;
use serde::{Deserialize, Serialize};

use crate::entry::encryption::{decrypt, encrypt};

pub const META_DIR: &str = ".lumen";
pub const CONFIG_FILE: &str = "config.json";

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct VaultConfig {
    pub version: u32,
    pub cipher: String,
    pub kdf: String,
    pub salt: String,
    pub m_cost: u32,
    pub t_cost: u32,
    pub p_cost: u32,
    pub data_key: String,
    pub data_key_nonce: String,
    #[serde(default)]
    pub obfuscate_names: bool,
}

pub struct VaultState {
    pub root: PathBuf,
    pub config: VaultConfig,
    pub data_key: [u8; 32],
}

#[derive(Clone, Debug, Serialize)]
pub struct VaultEntry {
    pub name: String,
    pub rel_path: String,
    pub is_dir: bool,
    pub size: u64,
    pub modified_ms: i64,
}

lazy_static! {
    static ref VAULT: Mutex<Option<VaultState>> = Mutex::new(None);
}

fn config_path(root: &Path) -> PathBuf {
    root.join(META_DIR).join(CONFIG_FILE)
}

fn derive_master(pass: &str, salt: &[u8], cfg: &VaultConfig) -> Result<[u8; 32], String> {
    let params = argon2::Params::new(cfg.m_cost, cfg.t_cost, cfg.p_cost, Some(32))
        .map_err(|e| format!("bad argon2 params: {e}"))?;
    let argon2 = argon2::Argon2::new(argon2::Algorithm::Argon2id, argon2::Version::V0x13, params);
    let mut key = [0u8; 32];
    argon2
        .hash_password_into(pass.as_bytes(), salt, &mut key)
        .map_err(|e| format!("key derivation failed: {e}"))?;
    Ok(key)
}

fn config_validate(cfg: &VaultConfig) -> Result<(), String> {
    if !cfg.obfuscate_names {
        return Ok(());
    }
    Err("obfuscate_names is not yet supported by this build".into())
}

pub fn exists(root: &Path) -> bool {
    config_path(root).exists()
}

pub fn create_with_passphrase(root: &str, passphrase: &str) -> Result<(), String> {
    let salt: [u8; 16] = rand::random();
    create(root, passphrase, &salt)
}

pub fn create(root: &str, passphrase: &str, salt: &[u8]) -> Result<(), String> {
    let root_path = Path::new(root);
    if exists(root_path) {
        return Err("A vault already exists at this path".into());
    }

    let meta_dir = root_path.join(META_DIR);
    fs::create_dir_all(&meta_dir).map_err(|e| e.to_string())?;

    let cfg = VaultConfig {
        version: 1,
        cipher: "aes-256-gcm".into(),
        kdf: "argon2id".into(),
        salt: hex_encode(salt),
        m_cost: 19 * 1024,
        t_cost: 2,
        p_cost: 1,
        data_key: String::new(),
        data_key_nonce: String::new(),
        obfuscate_names: false,
    };

    let master = derive_master(passphrase, salt, &cfg)?;
    let data_key: [u8; 32] = rand::random();

    let (wrapped, nonce) = encrypt(&data_key, &master);
    let cfg = VaultConfig {
        data_key: base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &wrapped),
        data_key_nonce: base64::Engine::encode(
            &base64::engine::general_purpose::STANDARD,
            &nonce,
        ),
        ..cfg
    };

    let json = serde_json::to_string_pretty(&cfg).map_err(|e| e.to_string())?;
    fs::write(config_path(root_path), json).map_err(|e| e.to_string())?;

    Ok(())
}

pub fn unlock(root: &str, passphrase: &str) -> Result<(), String> {
    let root_path = Path::new(root);
    if !exists(root_path) {
        return Err("No vault found at this path".into());
    }

    let raw = fs::read_to_string(config_path(root_path)).map_err(|e| e.to_string())?;
    let cfg: VaultConfig = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    config_validate(&cfg)?;

    let salt = hex_decode(&cfg.salt)?;
    let master = derive_master(passphrase, &salt, &cfg)?;

    let engine = base64::engine::general_purpose::STANDARD;
    let wrapped = engine
        .decode(&cfg.data_key)
        .map_err(|e| format!("bad data_key: {e}"))?;
    let nonce = engine
        .decode(&cfg.data_key_nonce)
        .map_err(|e| format!("bad data_key_nonce: {e}"))?;

    let data_key_bytes = decrypt(&wrapped, &nonce, &master)?;
    if data_key_bytes.len() != 32 {
        return Err("decrypted data key has invalid length".into());
    }
    let mut data_key = [0u8; 32];
    data_key.copy_from_slice(&data_key_bytes);

    let mut guard = VAULT.lock().unwrap();
    *guard = Some(VaultState {
        root: root_path.to_path_buf(),
        config: cfg,
        data_key,
    });
    Ok(())
}

pub fn lock() {
    let mut guard = VAULT.lock().unwrap();
    *guard = None;
}

pub fn is_unlocked() -> bool {
    VAULT.lock().unwrap().is_some()
}

fn state() -> Result<std::sync::MutexGuard<'static, Option<VaultState>>, String> {
    let guard = VAULT.lock().unwrap();
    if guard.is_none() {
        return Err("Vault is locked".into());
    }
    Ok(guard)
}

/// Resolve a user-supplied path (absolute or vault-relative) to a path under the vault root.
fn resolve_under_root(root: &Path, input: &str) -> Result<PathBuf, String> {
    let p = Path::new(input);
    let full = if p.is_absolute() {
        p.to_path_buf()
    } else {
        root.join(p)
    };

    if full.components().any(|c| matches!(c, std::path::Component::ParentDir)) {
        return Err("Path escapes the vault".into());
    }

    let canonical_root = root.canonicalize().unwrap_or_else(|_| root.to_path_buf());
    let canonical_full = full.canonicalize().unwrap_or_else(|_| full.clone());
    if !canonical_full.starts_with(&canonical_root) {
        return Err("Path is outside the vault".into());
    }
    Ok(full)
}

pub fn info() -> Result<serde_json::Value, String> {
    let guard = state()?;
    let st = guard.as_ref().unwrap();
    Ok(serde_json::json!({
        "root": st.root,
        "cipher": st.config.cipher,
        "kdf": st.config.kdf,
        "version": st.config.version,
    }))
}

pub fn read_bytes(input: &str) -> Result<Vec<u8>, String> {
    let guard = state()?;
    let st = guard.as_ref().unwrap();
    let full = resolve_under_root(&st.root, input)?;

    let mut file = fs::File::open(&full).map_err(|e| e.to_string())?;
    let mut bytes = Vec::new();
    file.read_to_end(&mut bytes).map_err(|e| e.to_string())?;

    if bytes.len() < 12 {
        return Err("Vault file is corrupt (missing nonce)".into());
    }
    let nonce = &bytes[..12];
    let ciphertext = &bytes[12..];
    decrypt(ciphertext, nonce, &st.data_key)
}

pub fn read_text(input: &str) -> Result<String, String> {
    let bytes = read_bytes(input)?;
    String::from_utf8(bytes).map_err(|e| format!("not valid UTF-8: {e}"))
}

pub fn write_bytes(input: &str, data: &[u8]) -> Result<(), String> {
    let guard = state()?;
    let st = guard.as_ref().unwrap();
    let full = resolve_under_root(&st.root, input)?;

    if let Some(parent) = full.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }

    let (ciphertext, nonce) = encrypt(data, &st.data_key);
    let mut blob = Vec::with_capacity(12 + ciphertext.len());
    blob.extend_from_slice(&nonce);
    blob.extend_from_slice(&ciphertext);

    let mut file = fs::File::create(&full).map_err(|e| e.to_string())?;
    file.write_all(&blob).map_err(|e| e.to_string())
}

pub fn write_text(input: &str, text: &str) -> Result<(), String> {
    write_bytes(input, text.as_bytes())
}

pub fn mkdir(input: &str) -> Result<(), String> {
    let guard = state()?;
    let st = guard.as_ref().unwrap();
    let full = resolve_under_root(&st.root, input)?;
    fs::create_dir_all(&full).map_err(|e| e.to_string())
}

pub fn delete(input: &str) -> Result<(), String> {
    let guard = state()?;
    let st = guard.as_ref().unwrap();
    let full = resolve_under_root(&st.root, input)?;

    if full.is_dir() {
        fs::remove_dir_all(&full).map_err(|e| e.to_string())
    } else {
        fs::remove_file(&full).map_err(|e| e.to_string())
    }
}

pub fn rename(from: &str, to: &str) -> Result<(), String> {
    let guard = state()?;
    let st = guard.as_ref().unwrap();
    let src = resolve_under_root(&st.root, from)?;
    let dst = resolve_under_root(&st.root, to)?;
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    fs::rename(&src, &dst).map_err(|e| e.to_string())
}

fn walk_entries(root: &Path, dir: &Path, rel_prefix: &str, out: &mut Vec<VaultEntry>) {
    let read = match fs::read_dir(dir) {
        Ok(r) => r,
        Err(_) => return,
    };
    let mut entries: Vec<std::fs::DirEntry> = read.flatten().collect();
    entries.sort_by_key(|e| e.file_name());

    for de in entries {
        let disk_name = de.file_name().to_string_lossy().into_owned();
        if de.path().is_dir() && disk_name == META_DIR {
            continue;
        }
        let rel_path = if rel_prefix.is_empty() {
            disk_name.clone()
        } else {
            format!("{rel_prefix}/{disk_name}")
        };
        let meta = match de.metadata() {
            Ok(m) => m,
            Err(_) => continue,
        };
        let modified_ms = meta
            .modified()
            .ok()
            .map(|t| {
                t.duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_millis() as i64)
                    .unwrap_or(0)
            })
            .unwrap_or(0);

        out.push(VaultEntry {
            name: disk_name.clone(),
            is_dir: meta.is_dir(),
            size: meta.len(),
            modified_ms,
            rel_path: rel_path.clone(),
        });

        if meta.is_dir() {
            walk_entries(root, &de.path(), &rel_path, out);
        }
    }
}

pub fn list(input: &str) -> Result<Vec<VaultEntry>, String> {
    let guard = state()?;
    let st = guard.as_ref().unwrap();
    let start = if input.trim().is_empty() {
        st.root.clone()
    } else {
        resolve_under_root(&st.root, input)?
    };
    if start.is_dir() {
        let mut out = Vec::new();
        walk_entries(&st.root, &start, "", &mut out);
        Ok(out)
    } else {
        Err("Not a directory".into())
    }
}

pub fn search(query: &str, max_results: usize) -> Result<Vec<serde_json::Value>, String> {
    let guard = state()?;
    let st = guard.as_ref().unwrap();

    let mut results = Vec::new();
    walk_entries(&st.root, &st.root, "", &mut Vec::new());
    let entries = list("")?;

    for e in entries {
        if results.len() >= max_results {
            break;
        }
        if e.is_dir {
            if e.name.to_lowercase().contains(&query.to_lowercase()) {
                results.push(serde_json::json!({
                    "rel_path": e.rel_path, "name": e.name, "is_dir": true
                }));
            }
            continue;
        }
        let hit = if e.name.to_lowercase().contains(&query.to_lowercase()) {
            true
        } else if let Ok(text) = read_bytes(&e.rel_path) {
            String::from_utf8_lossy(&text).to_lowercase().contains(&query.to_lowercase())
        } else {
            false
        };
        if hit {
            results.push(serde_json::json!({
                "rel_path": e.rel_path, "name": e.name, "is_dir": false, "size": e.size
            }));
        }
    }
    Ok(results)
}

/// Decrypt the entire vault into a plain folder at `dest`.
pub fn export(dest: &str) -> Result<usize, String> {
    let _guard = state()?;
    let dest_path = Path::new(dest);
    fs::create_dir_all(dest_path).map_err(|e| e.to_string())?;

    let entries = list("")?;
    let mut count = 0usize;
    for e in &entries {
        let target = dest_path.join(&e.rel_path);
        if e.is_dir {
            fs::create_dir_all(&target).map_err(|e| e.to_string())?;
        } else {
            let bytes = read_bytes(&e.rel_path)?;
            if let Some(parent) = target.parent() {
                fs::create_dir_all(parent).map_err(|e| e.to_string())?;
            }
            fs::write(&target, bytes).map_err(|e| e.to_string())?;
            count += 1;
        }
    }
    Ok(count)
}

pub fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub fn hex_decode(hex: &str) -> Result<Vec<u8>, String> {
    if hex.len() % 2 != 0 {
        return Err("odd hex length".into());
    }
    (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).map_err(|e| e.to_string()))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_vault(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("lumen_vault_{name}_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn create_unlock_roundtrip() {
        let dir = temp_vault("roundtrip");
        let salt: [u8; 16] = rand::random();
        create(dir.to_str().unwrap(), "hunter2", &salt).unwrap();
        assert!(!is_unlocked());

        unlock(dir.to_str().unwrap(), "hunter2").unwrap();
        assert!(is_unlocked());

        let info = info().unwrap();
        assert_eq!(info["root"].as_str().unwrap().to_lowercase(), dir.to_str().unwrap().to_lowercase());

        lock();
        assert!(!is_unlocked());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn fails_with_wrong_passphrase() {
        let dir = temp_vault("wrongpass");
        let salt: [u8; 16] = rand::random();
        create(dir.to_str().unwrap(), "right", &salt).unwrap();
        assert!(unlock(dir.to_str().unwrap(), "wrong").is_err());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn write_read_delete_list() {
        let dir = temp_vault("crud");
        let salt: [u8; 16] = rand::random();
        create(dir.to_str().unwrap(), "pw", &salt).unwrap();
        unlock(dir.to_str().unwrap(), "pw").unwrap();

        write_text("welcome.md", "# Hello\n\nEncrypted note.").unwrap();
        write_text("sub/other.md", "second").unwrap();

        let text = read_text("welcome.md").unwrap();
        assert!(text.contains("Encrypted note"));

        let entries = list("").unwrap();
        assert_eq!(entries.len(), 2);

        // Plain file must not contain plaintext on disk
        let on_disk = fs::read(dir.join("welcome.md")).unwrap();
        let disk_str = String::from_utf8_lossy(&on_disk);
        assert!(!disk_str.contains("Encrypted note"), "plaintext leaked to disk");

        delete("sub/other.md").unwrap();
        let entries = list("").unwrap();
        assert_eq!(entries.len(), 1);

        rename("welcome.md", "renamed.md").unwrap();
        assert!(read_text("renamed.md").unwrap().contains("Hello"));

        lock();
        assert!(read_text("welcome.md").is_err());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn rejects_escape_paths() {
        let dir = temp_vault("escape");
        let salt: [u8; 16] = rand::random();
        create(dir.to_str().unwrap(), "pw", &salt).unwrap();
        unlock(dir.to_str().unwrap(), "pw").unwrap();

        assert!(read_bytes("/etc/passwd").is_err());
        assert!(read_bytes("../outside").is_err());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn export_decrypts_whole_vault() {
        let dir = temp_vault("export");
        let out = temp_vault("export_out");
        let salt: [u8; 16] = rand::random();
        create(dir.to_str().unwrap(), "pw", &salt).unwrap();
        unlock(dir.to_str().unwrap(), "pw").unwrap();
        write_text("a.md", "alpha").unwrap();
        write_text("n/b.md", "beta").unwrap();

        let count = export(out.to_str().unwrap()).unwrap();
        assert_eq!(count, 2);
        assert_eq!(
            fs::read_to_string(out.join("a.md")).unwrap(),
            "alpha"
        );
        assert_eq!(
            fs::read_to_string(out.join("n/b.md")).unwrap(),
            "beta"
        );
        fs::remove_dir_all(&dir).unwrap();
        fs::remove_dir_all(&out).unwrap();
    }
}