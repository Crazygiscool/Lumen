//! Whole-vault encryption for Lumen.
//!
//! A store is a folder protected by a passphrase:
//!   - `.lumen/<store>.json` (`config.json` for the vault/KB store, `journal.json`
//!     for the journal store) holds KDF salt/params and a passphrase-wrapped data key.
//!   - File *contents* are stored as `nonce(12) || AES-256-GCM ciphertext`.
//!   - Unlocking derives a master key via Argon2id and unwraps the per-store data key.
//!   - While unlocked, reads/writes transparently encrypt/decrypt with the data key.
//!
//! Multiple stores may be unlocked at the same time — even in the same folder —
//! each with its own passphrase.

pub mod ffi;

use std::collections::HashMap;
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
pub const JOURNAL_FILE: &str = "journal.json";

pub const STORE_VAULT: &str = "vault";
pub const STORE_JOURNAL: &str = "journal";

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

#[derive(Clone)]
pub struct VaultState {
    pub root: PathBuf,
    pub store: String,
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

/// Production KDF parameters (Argon2id).
const M_COST: u32 = 19 * 1024;
const T_COST: u32 = 2;
const P_COST: u32 = 1;

lazy_static! {
    static ref VAULTS: Mutex<HashMap<(PathBuf, String), VaultState>> = Mutex::new(HashMap::new());
    static ref ACTIVE: Mutex<HashMap<String, PathBuf>> = Mutex::new(HashMap::new());
}

/// Config file name (inside `.lumen/`) for a store.
pub fn config_file_for(store: &str) -> &'static str {
    if store == STORE_JOURNAL {
        JOURNAL_FILE
    } else {
        CONFIG_FILE
    }
}

fn config_path(root: &Path, store: &str) -> PathBuf {
    root.join(META_DIR).join(config_file_for(store))
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

/// Whether a store currently exists on disk at `root`.
pub fn exists_store(root: &str, store: &str) -> bool {
    config_path(Path::new(root), store).exists()
}

/// Whether a vault store currently exists on disk at `root` (back-compat helper).
pub fn exists(root: &Path) -> bool {
    exists_store(root.to_str().unwrap_or(""), STORE_VAULT)
}

pub fn create_with_passphrase(root: &str, passphrase: &str, store: &str) -> Result<(), String> {
    let salt: [u8; 16] = rand::random();
    create(root, passphrase, &salt, store)
}

pub fn create(root: &str, passphrase: &str, salt: &[u8], store: &str) -> Result<(), String> {
    create_with_params(root, passphrase, salt, store, M_COST, T_COST, P_COST)
}

/// Create a store with explicit KDF parameters (tests use cheap ones).
fn create_with_params(
    root: &str,
    passphrase: &str,
    salt: &[u8],
    store: &str,
    m_cost: u32,
    t_cost: u32,
    p_cost: u32,
) -> Result<(), String> {
    let root_path = Path::new(root);
    if exists_store(root, store) {
        return Err(format!("A {store} already exists at this path"));
    }

    let meta_dir = root_path.join(META_DIR);
    fs::create_dir_all(&meta_dir).map_err(|e| e.to_string())?;

    let cfg = VaultConfig {
        version: 1,
        cipher: "aes-256-gcm".into(),
        kdf: "argon2id".into(),
        salt: hex_encode(salt),
        m_cost,
        t_cost,
        p_cost,
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
    fs::write(config_path(root_path, store), json).map_err(|e| e.to_string())?;

    Ok(())
}

pub fn unlock(root: &str, passphrase: &str, store: &str) -> Result<(), String> {
    let root_path = Path::new(root);
    if !exists_store(root, store) {
        return Err(format!("No {store} found at this path"));
    }

    let cfg_path = config_path(root_path, store);
    let raw = fs::read_to_string(&cfg_path).map_err(|e| e.to_string())?;
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

    let state = VaultState {
        root: root_path.to_path_buf(),
        store: store.to_string(),
        config: cfg,
        data_key,
    };
    VAULTS.lock().unwrap().insert((state.root.clone(), store.to_string()), state);
    ACTIVE.lock().unwrap().insert(store.to_string(), root_path.to_path_buf());
    Ok(())
}

/// Lock a single store (all its roots).
pub fn lock(store: &str) {
    VAULTS.lock().unwrap().retain(|(_, s), _| s != store);
    ACTIVE.lock().unwrap().remove(store);
}

/// Lock every store.
pub fn lock_all() {
    VAULTS.lock().unwrap().clear();
    ACTIVE.lock().unwrap().clear();
}

pub fn is_unlocked(store: &str) -> bool {
    let root = ACTIVE.lock().unwrap().get(store).cloned();
    match root {
        Some(root) => VAULTS.lock().unwrap().contains_key(&(root, store.to_string())),
        None => false,
    }
}

/// Stores currently unlocked on disk, as `{root, store}` records.
pub fn open_stores() -> Vec<serde_json::Value> {
    let vaults = VAULTS.lock().unwrap();
    let mut out: Vec<serde_json::Value> = vaults
        .iter()
        .map(|((root, store), _)| serde_json::json!({ "root": root, "store": store }))
        .collect();
    out.sort_by_key(|j| j["root"].as_str().unwrap_or("").to_string());
    out
}

/// The currently-active root for a store, plus its decrypted state. Cloned so
/// callers never hold the global lock while performing filesystem work.
fn state_clone(store: &str) -> Result<VaultState, String> {
    let root = ACTIVE
        .lock()
        .unwrap()
        .get(store)
        .cloned()
        .ok_or_else(|| "Vault is locked".to_string())?;
    let vaults = VAULTS.lock().unwrap();
    let st = vaults
        .get(&(root.clone(), store.to_string()))
        .ok_or_else(|| "Vault is locked".to_string())?;
    Ok(st.clone())
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

pub fn info(store: &str) -> Result<serde_json::Value, String> {
    let st = state_clone(store)?;
    Ok(serde_json::json!({
        "root": st.root,
        "store": st.store,
        "cipher": st.config.cipher,
        "kdf": st.config.kdf,
        "version": st.config.version,
    }))
}

pub fn read_bytes(input: &str, store: &str) -> Result<Vec<u8>, String> {
    let st = state_clone(store)?;
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

pub fn read_text(input: &str, store: &str) -> Result<String, String> {
    let bytes = read_bytes(input, store)?;
    String::from_utf8(bytes).map_err(|e| format!("not valid UTF-8: {e}"))
}

pub fn write_bytes(input: &str, data: &[u8], store: &str) -> Result<(), String> {
    let st = state_clone(store)?;
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

pub fn write_text(input: &str, text: &str, store: &str) -> Result<(), String> {
    write_bytes(input, text.as_bytes(), store)
}

pub fn mkdir(input: &str, store: &str) -> Result<(), String> {
    let st = state_clone(store)?;
    let full = resolve_under_root(&st.root, input)?;
    fs::create_dir_all(&full).map_err(|e| e.to_string())
}

pub fn delete(input: &str, store: &str) -> Result<(), String> {
    let st = state_clone(store)?;
    let full = resolve_under_root(&st.root, input)?;

    if full.is_dir() {
        fs::remove_dir_all(&full).map_err(|e| e.to_string())
    } else {
        fs::remove_file(&full).map_err(|e| e.to_string())
    }
}

pub fn rename(from: &str, to: &str, store: &str) -> Result<(), String> {
    let st = state_clone(store)?;
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

pub fn list(input: &str, store: &str) -> Result<Vec<VaultEntry>, String> {
    let st = state_clone(store)?;
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

pub fn search(query: &str, max_results: usize, store: &str) -> Result<Vec<serde_json::Value>, String> {
    let st = state_clone(store)?;
    let root = st.root.clone();

    let mut results = Vec::new();
    walk_entries(&root, &root, "", &mut Vec::new());
    let entries = list("", store)?;

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
        } else if let Ok(text) = read_bytes(&e.rel_path, store) {
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

/// Decrypt an entire store into a plain folder at `dest`.
pub fn export(dest: &str, store: &str) -> Result<usize, String> {
    let dest_path = Path::new(dest);
    fs::create_dir_all(dest_path).map_err(|e| e.to_string())?;

    let entries = list("", store)?;
    let mut count = 0usize;
    for e in &entries {
        let target = dest_path.join(&e.rel_path);
        if e.is_dir {
            fs::create_dir_all(&target).map_err(|e| e.to_string())?;
        } else {
            let bytes = read_bytes(&e.rel_path, store)?;
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

    // The store map is process-global; serializing vault tests avoids
    // cross-test contamination while running cheap KDF parameters.
    static TEST_LOCK: Mutex<()> = Mutex::new(());
    const M: u32 = 8 * 1024;
    const T: u32 = 1;
    const P: u32 = 1;

    /// Serializes vault tests and starts each from a clean store map.
    fn test_lock() -> std::sync::MutexGuard<'static, ()> {
        let g = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        lock_all();
        g
    }

    fn temp_vault(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("lumen_vault_{name}_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    fn create_test(dir: &Path, pass: &str, salt: &[u8], store: &str) {
        create_with_params(dir.to_str().unwrap(), pass, salt, store, M, T, P).unwrap();
    }

    fn unlock_test(dir: &Path, pass: &str, store: &str) {
        unlock(dir.to_str().unwrap(), pass, store).unwrap();
    }

    #[test]
    fn create_unlock_roundtrip() {
        let _g = test_lock();
        let dir = temp_vault("roundtrip");
        let salt: [u8; 16] = rand::random();
        create_test(&dir, "hunter2", &salt, STORE_VAULT);
        assert!(!is_unlocked(STORE_VAULT));

        unlock_test(&dir, "hunter2", STORE_VAULT);
        assert!(is_unlocked(STORE_VAULT));

        let info = info(STORE_VAULT).unwrap();
        assert_eq!(info["root"].as_str().unwrap().to_lowercase(), dir.to_str().unwrap().to_lowercase());

        lock(STORE_VAULT);
        assert!(!is_unlocked(STORE_VAULT));
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn fails_with_wrong_passphrase() {
        let _g = test_lock();
        let dir = temp_vault("wrongpass");
        let salt: [u8; 16] = rand::random();
        create_test(&dir, "right", &salt, STORE_VAULT);
        assert!(unlock(dir.to_str().unwrap(), "wrong", STORE_VAULT).is_err());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn write_read_delete_list() {
        let _g = test_lock();
        let dir = temp_vault("crud");
        let salt: [u8; 16] = rand::random();
        create_test(&dir, "pw", &salt, STORE_VAULT);
        unlock_test(&dir, "pw", STORE_VAULT);

        write_text("welcome.md", "# Hello\n\nEncrypted note.", STORE_VAULT).unwrap();
        write_text("sub/other.md", "second", STORE_VAULT).unwrap();

        let text = read_text("welcome.md", STORE_VAULT).unwrap();
        assert!(text.contains("Encrypted note"));

        let names = names_of(list("", STORE_VAULT).unwrap());
        assert_eq!(names, vec!["sub", "sub/other.md", "welcome.md"]);

        // Plain file must not contain plaintext on disk
        let on_disk = fs::read(dir.join("welcome.md")).unwrap();
        let disk_str = String::from_utf8_lossy(&on_disk);
        assert!(!disk_str.contains("Encrypted note"), "plaintext leaked to disk");

        delete("sub/other.md", STORE_VAULT).unwrap();
        let names = names_of(list("", STORE_VAULT).unwrap());
        assert_eq!(names, vec!["sub", "welcome.md"]);

        rename("welcome.md", "renamed.md", STORE_VAULT).unwrap();
        assert!(read_text("renamed.md", STORE_VAULT).unwrap().contains("Hello"));

        lock(STORE_VAULT);
        assert!(read_text("welcome.md", STORE_VAULT).is_err());
        fs::remove_dir_all(&dir).unwrap();
    }

    fn names_of(entries: Vec<VaultEntry>) -> Vec<String> {
        let mut names: Vec<String> = entries.iter().map(|e| e.rel_path.clone()).collect();
        names.sort();
        names
    }

    #[test]
    fn rejects_escape_paths() {
        let _g = test_lock();
        let dir = temp_vault("escape");
        let salt: [u8; 16] = rand::random();
        create_test(&dir, "pw", &salt, STORE_VAULT);
        unlock_test(&dir, "pw", STORE_VAULT);

        assert!(read_bytes("/etc/passwd", STORE_VAULT).is_err());
        assert!(read_bytes("../outside", STORE_VAULT).is_err());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn export_decrypts_whole_vault() {
        let _g = test_lock();
        let dir = temp_vault("export");
        let out = temp_vault("export_out");
        let salt: [u8; 16] = rand::random();
        create_test(&dir, "pw", &salt, STORE_VAULT);
        unlock_test(&dir, "pw", STORE_VAULT);
        write_text("a.md", "alpha", STORE_VAULT).unwrap();
        write_text("n/b.md", "beta", STORE_VAULT).unwrap();

        let count = export(out.to_str().unwrap(), STORE_VAULT).unwrap();
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

    /// Two stores sharing one folder, unlocked simultaneously with different
    /// passphrases; locking one leaves the other usable.
    #[test]
    fn journal_and_vault_share_folder() {
        let _g = test_lock();
        let dir = temp_vault("shared");
        let salt: [u8; 16] = rand::random();

        create_test(&dir, "kb-pass", &salt, STORE_VAULT);
        create_test(&dir, "journal-pass", &salt, STORE_JOURNAL);

        unlock_test(&dir, "kb-pass", STORE_VAULT);
        unlock_test(&dir, "journal-pass", STORE_JOURNAL);

        assert!(is_unlocked(STORE_VAULT));
        assert!(is_unlocked(STORE_JOURNAL));
        assert_eq!(open_stores().len(), 2);

        write_text("note.md", "kb note", STORE_VAULT).unwrap();
        write_text("2026-08-29.md", "journal entry", STORE_JOURNAL).unwrap();

        assert_eq!(read_text("note.md", STORE_VAULT).unwrap(), "kb note");
        assert_eq!(read_text("2026-08-29.md", STORE_JOURNAL).unwrap(), "journal entry");

        // Configs are distinct files.
        assert!(dir.join(META_DIR).join(CONFIG_FILE).exists());
        assert!(dir.join(META_DIR).join(JOURNAL_FILE).exists());

        // Locking the vault leaves the journal store live.
        lock(STORE_VAULT);
        assert!(!is_unlocked(STORE_VAULT));
        assert!(is_unlocked(STORE_JOURNAL));
        assert_eq!(read_text("2026-08-29.md", STORE_JOURNAL).unwrap(), "journal entry");

        // Wrong passphrase for the journal store is rejected independently.
        lock(STORE_JOURNAL);
        assert!(unlock(dir.to_str().unwrap(), "kb-pass", STORE_JOURNAL).is_err());
        assert!(!is_unlocked(STORE_JOURNAL));

        fs::remove_dir_all(&dir).unwrap();
    }
}