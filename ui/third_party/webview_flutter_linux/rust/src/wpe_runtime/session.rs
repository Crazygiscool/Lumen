// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Application-scoped persistent network-session configuration.
//!
//! Flutter's Linux runner sets GLib's program name to the application ID before
//! the native asset is used. WPE therefore places the default session's website
//! data and cache beneath that application's XDG directories. The session is
//! persistent, but `WebKitCookieManager` deliberately does not store
//! non-session cookies until the embedder assigns a persistence file. This
//! module configures a SQLite jar inside WPE's existing application data
//! directory before any WebView or handle-free cookie operation can use it.

use std::{ffi::OsStr, os::unix::ffi::OsStrExt, path::Path};

use super::prelude::*;

const SQLITE_COOKIE_STORAGE: i32 = 1;
const COOKIE_DATABASE_NAME: &str = "cookies.sqlite";

thread_local! {
    // WPE/GLib objects are platform-thread affine. A thread-local flag both
    // preserves that rule and prevents the persistence API from being applied
    // after every cookie or website-data operation.
    static COOKIE_STORAGE_CONFIGURED: Cell<bool> = const { Cell::new(false) };
}

/// Returns WPE's application-scoped default session after cookie setup.
///
/// The returned pointer is transfer-none and remains owned by WebKit's
/// process-lifetime singleton. Initialization is lazy so the federated cookie
/// manager can be used before a WebView attaches, while still ensuring the
/// cookie database is selected before the network process observes the jar.
pub(super) fn shared_network_session() -> Result<*mut WebKitNetworkSession, i32> {
    let session = unsafe { webkit_network_session_get_default() };
    if session.is_null() {
        return Err(-20);
    }
    if COOKIE_STORAGE_CONFIGURED.get() {
        return Ok(session);
    }
    if unsafe { webkit_network_session_is_ephemeral(session) } != 0 {
        return Err(-21);
    }
    let data_manager = unsafe { webkit_network_session_get_website_data_manager(session) };
    if data_manager.is_null() {
        return Err(-22);
    }
    let data_directory =
        unsafe { webkit_website_data_manager_get_base_data_directory(data_manager) };
    if data_directory.is_null() {
        return Err(-23);
    }
    let data_directory = Path::new(OsStr::from_bytes(
        unsafe { CStr::from_ptr(data_directory) }.to_bytes(),
    ));
    std::fs::create_dir_all(data_directory).map_err(|_| -24)?;
    let cookie_database = cookie_database_path(data_directory);
    let cookie_database = CString::new(cookie_database.as_os_str().as_bytes()).map_err(|_| -25)?;
    let cookie_manager = unsafe { webkit_network_session_get_cookie_manager(session) };
    if cookie_manager.is_null() {
        return Err(-26);
    }
    // SAFETY: The manager is a transfer-none child of the process-lifetime
    // session and WebKit copies the SQLite filename during this synchronous
    // configuration call.
    unsafe {
        webkit_cookie_manager_set_persistent_storage(
            cookie_manager,
            cookie_database.as_ptr(),
            SQLITE_COOKIE_STORAGE,
        )
    };
    COOKIE_STORAGE_CONFIGURED.set(true);
    Ok(session)
}

fn cookie_database_path(data_directory: &Path) -> std::path::PathBuf {
    data_directory.join(COOKIE_DATABASE_NAME)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_the_cookie_database_inside_wpes_application_profile() {
        assert_eq!(
            cookie_database_path(Path::new("/xdg/data/com.example.browser")),
            Path::new("/xdg/data/com.example.browser/cookies.sqlite"),
        );
    }
}
