//! Shared helpers for unit tests.
//!
//! The vault registry is process-global and keyed by store name, so every test
//! that unlocks a vault has to hold this lock. The guard also clears the
//! in-memory indexes on the way out, so a test never observes state — or a
//! Tantivy writer — left over from the one before it.

use std::sync::{Mutex, MutexGuard};

use crate::vault;

static TEST_LOCK: Mutex<()> = Mutex::new(());

/// Serializes vault-touching tests and starts each from a clean store map.
///
/// Hold the guard for the whole test; dropping it releases the lock and
/// discards the search and backlink indexes.
pub struct TestGuard {
    _lock: MutexGuard<'static, ()>,
}

impl TestGuard {
    /// Acquires the lock and resets the global store map.
    pub fn new() -> Self {
        let lock = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        vault::lock_all();
        Self { _lock: lock }
    }
}

impl Drop for TestGuard {
    fn drop(&mut self) {
        // Runs while the test's temporary vault is still on disk, so the
        // Tantivy writer can commit before the directory disappears.
        crate::search::clear_search_indexes();
        crate::wikilinks::clear_backlink_index();
    }
}
