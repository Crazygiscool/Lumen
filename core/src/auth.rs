use std::path::PathBuf;
use std::sync::Mutex;

use lazy_static::lazy_static;
use serde::{Deserialize, Serialize};

use crate::entry::encryption;
use crate::paths;

lazy_static! {
    static ref SESSION_KEY: Mutex<Option<[u8; 32]>> = Mutex::new(None);
}

#[derive(Serialize, Deserialize)]
struct AuthData {
    salt: Vec<u8>,
    key_hash: Vec<u8>,
}

fn auth_path() -> PathBuf {
    paths::auth_path()
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_session_lifecycle() {
        assert!(!is_unlocked());
        assert_eq!(session_key(), None);

        // Set password (should auto-unlock)
        set_password("test_password").unwrap();
        assert!(is_unlocked());
        assert!(session_key().is_some());

        // Lock
        lock();
        assert!(!is_unlocked());
        assert_eq!(session_key(), None);

        // Unlock with wrong password
        assert!(!unlock("wrong_password"));
        assert!(!is_unlocked());

        // Unlock with correct password
        assert!(unlock("test_password"));
        assert!(is_unlocked());
    }

    #[test]
    fn test_has_password() {
        // This writes to the real auth.json, so we test the logic indirectly
        // by verifying the auth_path() and has_password() are consistent
        let path = auth_path();
        if path.exists() {
            assert!(has_password());
        }
    }

    #[test]
    fn test_key_derivation_consistency() {
        let password = "consistent_test_password";
        let salt: [u8; 16] = rand::random();
        let key1 = encryption::derive_key(password, &salt);
        let key2 = encryption::derive_key(password, &salt);
        assert_eq!(key1, key2);
    }

    #[test]
    fn test_different_passwords_different_keys() {
        let salt: [u8; 16] = rand::random();
        let key1 = encryption::derive_key("password_a", &salt);
        let key2 = encryption::derive_key("password_b", &salt);
        assert_ne!(key1, key2);
    }
}
