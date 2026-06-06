use std::path::PathBuf;
use std::sync::Mutex;

use lazy_static::lazy_static;
use serde::{Deserialize, Serialize};

use crate::entry::encryption;

lazy_static! {
    static ref SESSION_KEY: Mutex<Option<[u8; 32]>> = Mutex::new(None);
}

#[derive(Serialize, Deserialize)]
struct AuthData {
    salt: Vec<u8>,
    key_hash: Vec<u8>,
}

fn auth_path() -> PathBuf {
    let mut path = dirs::data_dir().unwrap_or_else(|| PathBuf::from("."));
    path.push("lumen");
    let _ = std::fs::create_dir_all(&path);
    path.push("auth.json");
    path
}

pub fn has_password() -> bool {
    auth_path().exists()
}

pub fn set_password(password: &str) -> Result<(), String> {
    let salt: [u8; 16] = rand::random();
    let key = encryption::derive_key(password, &salt);
    let data = AuthData {
        salt: salt.to_vec(),
        key_hash: key.to_vec(),
    };
    let json = serde_json::to_string(&data).map_err(|e| e.to_string())?;
    std::fs::write(auth_path(), &json).map_err(|e| e.to_string())?;

    // Also unlock immediately
    if let Ok(mut session) = SESSION_KEY.lock() {
        *session = Some(key);
    }
    Ok(())
}

pub fn unlock(password: &str) -> bool {
    let path = auth_path();
    if !path.exists() {
        return false;
    }
    let json = match std::fs::read_to_string(&path) {
        Ok(s) => s,
        Err(_) => return false,
    };
    let data: AuthData = match serde_json::from_str(&json) {
        Ok(d) => d,
        Err(_) => return false,
    };
    let key = encryption::derive_key(password, &data.salt);
    if key.as_slice() == data.key_hash.as_slice() {
        if let Ok(mut session) = SESSION_KEY.lock() {
            *session = Some(key);
        }
        true
    } else {
        false
    }
}

pub fn lock() {
    if let Ok(mut session) = SESSION_KEY.lock() {
        *session = None;
    }
}

pub fn session_key() -> Option<[u8; 32]> {
    if let Ok(guard) = SESSION_KEY.lock() {
        guard.as_ref().copied()
    } else {
        None
    }
}

pub fn is_unlocked() -> bool {
    SESSION_KEY.lock().map(|s| s.is_some()).unwrap_or(false)
}
