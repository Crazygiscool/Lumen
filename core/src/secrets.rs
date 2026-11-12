//! Secrets kept in the operating system's keyring.
//!
//! The password of a WebDAV account and the passphrase that encrypts the
//! uploads belong to the user, not to Lumen. They are kept in the keyring
//! rather than in the configuration file, which is copied from machine to
//! machine, and rather than in the vault, which is synced.
//!
//! The passphrase that encrypts the uploads is deliberately *not* the
//! password of the account: the account password is known to the server,
//! and a server that could decrypt the notes would know too much.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

/// The name Lumen files its secrets under.
const SERVICE: &str = "Lumen";

/// The accounts Lumen keeps secrets for.
pub mod account {
    /// The password of the WebDAV account.
    pub const WEBDAV_PASSWORD: &str = "webdav-password";

    /// The passphrase that encrypts the uploads.
    pub const WEBDAV_PASSPHRASE: &str = "webdav-passphrase";
}

/// A place secrets can be kept.
pub trait SecretStore: Send + Sync {
    /// Keep a secret, replacing any secret kept before.
    fn set(&self, account: &str, secret: &str) -> crate::Result<()>;

    /// The secret kept under an account, if there is one.
    fn get(&self, account: &str) -> crate::Result<Option<String>>;

    /// Forget a secret.
    fn delete(&self, account: &str) -> crate::Result<()>;
}

/// An in-memory store, put in place by [`set_store`].
static OVERRIDE: Mutex<Option<Arc<dyn SecretStore>>> = Mutex::new(None);

/// The operating system's keyring.
pub struct SystemKeyring;

impl SecretStore for SystemKeyring {
    fn set(&self, account: &str, secret: &str) -> crate::Result<()> {
        let entry = keyring::Entry::new(SERVICE, account).map_err(|e| e.to_string())?;
        entry.set_password(secret).map_err(|e| e.to_string())
    }

    fn get(&self, account: &str) -> crate::Result<Option<String>> {
        let entry = keyring::Entry::new(SERVICE, account).map_err(|e| e.to_string())?;
        match entry.get_password() {
            Ok(secret) => Ok(Some(secret)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(e) => Err(e.to_string()),
        }
    }

    fn delete(&self, account: &str) -> crate::Result<()> {
        let entry = keyring::Entry::new(SERVICE, account).map_err(|e| e.to_string())?;
        match entry.delete_credential() {
            Ok(()) => Ok(()),
            Err(keyring::Error::NoEntry) => Ok(()),
            Err(e) => Err(e.to_string()),
        }
    }
}

/// A store that keeps secrets in memory.
///
/// The secrets are gone when the process ends, which is better than writing
/// them to a file.
pub struct MemoryStore {
    secrets: Mutex<HashMap<String, String>>,
}

impl Default for MemoryStore {
    fn default() -> Self {
        Self::new()
    }
}

impl MemoryStore {
    /// An empty store.
    pub fn new() -> Self {
        MemoryStore {
            secrets: Mutex::new(HashMap::new()),
        }
    }
}

impl SecretStore for MemoryStore {
    fn set(&self, account: &str, secret: &str) -> crate::Result<()> {
        let mut secrets = self.secrets.lock().map_err(|e| e.to_string())?;
        secrets.insert(account.to_string(), secret.to_string());
        Ok(())
    }

    fn get(&self, account: &str) -> crate::Result<Option<String>> {
        let secrets = self.secrets.lock().map_err(|e| e.to_string())?;
        Ok(secrets.get(account).cloned())
    }

    fn delete(&self, account: &str) -> crate::Result<()> {
        let mut secrets = self.secrets.lock().map_err(|e| e.to_string())?;
        secrets.remove(account);
        Ok(())
    }
}

/// Whether the machine has a keyring Lumen can use.
pub fn keyring_available() -> bool {
    keyring::Entry::store_status().is_ok()
}

/// The store the secrets are kept in, unless another one was put in place.
fn current() -> Arc<dyn SecretStore> {
    let guard = OVERRIDE.lock().unwrap();
    match guard.as_ref() {
        Some(store) => store.clone(),
        None => Arc::new(SystemKeyring),
    }
}

/// Keep the secrets in another store, or put the keyring back.
///
/// This is how the tests keep their secrets to themselves.
pub fn set_store(store: Option<Arc<dyn SecretStore>>) {
    let mut guard = OVERRIDE.lock().unwrap();
    *guard = store;
}

/// Keep the password of the WebDAV account.
pub fn set_webdav_password(password: &str) -> crate::Result<()> {
    store_webdav_password(&*current(), password)
}

/// The password of the WebDAV account, if it has been kept.
pub fn webdav_password() -> crate::Result<Option<String>> {
    webdav_password_in(&*current())
}

/// Keep the passphrase that encrypts the uploads.
pub fn set_webdav_passphrase(passphrase: &str) -> crate::Result<()> {
    store_webdav_passphrase(&*current(), passphrase)
}

/// The passphrase that encrypts the uploads, if it has been kept.
pub fn webdav_passphrase() -> crate::Result<Option<String>> {
    webdav_passphrase_in(&*current())
}

/// Forget the WebDAV secrets.
pub fn clear_webdav_secrets() -> crate::Result<()> {
    clear_webdav_secrets_in(&*current())
}

/// Keep the password of the WebDAV account in a store.
pub fn store_webdav_password(store: &dyn SecretStore, password: &str) -> crate::Result<()> {
    store.set(account::WEBDAV_PASSWORD, password)
}

/// The password of the WebDAV account in a store.
pub fn webdav_password_in(store: &dyn SecretStore) -> crate::Result<Option<String>> {
    store.get(account::WEBDAV_PASSWORD)
}

/// Keep the passphrase that encrypts the uploads in a store.
pub fn store_webdav_passphrase(store: &dyn SecretStore, passphrase: &str) -> crate::Result<()> {
    store.set(account::WEBDAV_PASSPHRASE, passphrase)
}

/// The passphrase that encrypts the uploads in a store.
pub fn webdav_passphrase_in(store: &dyn SecretStore) -> crate::Result<Option<String>> {
    store.get(account::WEBDAV_PASSPHRASE)
}

/// Forget the WebDAV secrets in a store.
pub fn clear_webdav_secrets_in(store: &dyn SecretStore) -> crate::Result<()> {
    store.delete(account::WEBDAV_PASSWORD)?;
    store.delete(account::WEBDAV_PASSPHRASE)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_a_secret_is_kept_and_read_back() {
        let store = MemoryStore::new();

        store_webdav_password(&store, "hunter2").unwrap();

        assert_eq!(
            webdav_password_in(&store).unwrap().as_deref(),
            Some("hunter2")
        );
    }

    #[test]
    fn test_a_secret_that_was_never_kept_is_none() {
        let store = MemoryStore::new();

        assert!(webdav_password_in(&store).unwrap().is_none());
        assert!(webdav_passphrase_in(&store).unwrap().is_none());
    }

    #[test]
    fn test_the_password_and_the_passphrase_are_kept_apart() {
        let store = MemoryStore::new();

        store_webdav_password(&store, "hunter2").unwrap();
        store_webdav_passphrase(&store, "a different secret").unwrap();

        assert_eq!(
            webdav_password_in(&store).unwrap().as_deref(),
            Some("hunter2")
        );
        assert_eq!(
            webdav_passphrase_in(&store).unwrap().as_deref(),
            Some("a different secret")
        );
    }

    #[test]
    fn test_the_secrets_can_be_forgotten() {
        let store = MemoryStore::new();
        store_webdav_password(&store, "hunter2").unwrap();
        store_webdav_passphrase(&store, "a different secret").unwrap();

        clear_webdav_secrets_in(&store).unwrap();

        assert!(webdav_password_in(&store).unwrap().is_none());
        assert!(webdav_passphrase_in(&store).unwrap().is_none());
    }

    #[test]
    fn test_a_secret_can_be_replaced() {
        let store = MemoryStore::new();

        store_webdav_password(&store, "old").unwrap();
        store_webdav_password(&store, "new").unwrap();

        assert_eq!(webdav_password_in(&store).unwrap().as_deref(), Some("new"));
    }

    /// The store in place can be replaced, so the tests keep their secrets
    /// to themselves.
    #[test]
    fn test_the_store_can_be_replaced() {
        // The store is process-global, so the test takes the same lock the
        // other tests that touch a vault take.
        let _guard = crate::testutil::TestGuard::new();

        let store = std::sync::Arc::new(MemoryStore::new());
        set_store(Some(store.clone()));

        set_webdav_password("hunter2").unwrap();
        assert_eq!(webdav_password().unwrap().as_deref(), Some("hunter2"));

        set_store(None);
    }
}
