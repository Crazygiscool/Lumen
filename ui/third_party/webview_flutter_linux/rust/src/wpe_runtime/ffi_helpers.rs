// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Small ownership-safe conversions used at the native ABI boundary.

use super::prelude::*;

/// Copies a caller-owned NUL-terminated UTF-8 string into Rust storage.
///
/// The returned `String` does not borrow the FFI pointer. `-1` denotes null and
/// `-2` invalid UTF-8.
pub(super) fn required_c_string(pointer: *const c_char) -> Result<String, i32> {
    if pointer.is_null() {
        return Err(-1);
    }
    // SAFETY: FFI callers must provide a NUL-terminated string for this call.
    unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .map(str::to_owned)
        .map_err(|_| -2)
}

/// Copies a nullable foreign string while its owner remains alive.
pub(super) fn foreign_bytes(pointer: *const c_char) -> Vec<u8> {
    if pointer.is_null() {
        Vec::new()
    } else {
        // SAFETY: Non-null pointers passed here are borrowed NUL-terminated
        // strings supplied by WebKit for the duration of the enclosing call.
        unsafe { CStr::from_ptr(pointer) }.to_bytes().to_vec()
    }
}

/// Copies a WebKit-owned null-terminated UTF-8 string array.
///
/// The defensive value cap prevents an invalid foreign array from causing an
/// unbounded scan. WebKit's file chooser uses this shape for both accepted MIME
/// types and currently selected filesystem paths.
pub(super) unsafe fn foreign_string_array(values: *const *const c_char) -> Vec<Vec<u8>> {
    if values.is_null() {
        return Vec::new();
    }
    let mut copied = Vec::new();
    for index in 0..MAX_FILE_CHOOSER_VALUES {
        // SAFETY: The caller guarantees a readable, null-terminated pointer
        // array. The explicit cap bounds the scan if native data is malformed.
        let value = unsafe { values.add(index).read() };
        if value.is_null() {
            break;
        }
        copied.push(foreign_bytes(value));
    }
    copied
}

/// Converts WPE's stable web-process termination enum into an owned message.
///
/// The integer reason is preserved separately in the event's `code` field so
/// Dart can expose the native diagnostic while mapping every reason to the
/// federated `webContentProcessTerminated` category. Keeping the text here
/// also avoids making Dart duplicate WPE-specific enum knowledge.
pub(super) fn web_process_termination_description(reason: i32) -> &'static [u8] {
    match reason {
        0 => b"WPE WebKit web process crashed.",
        1 => b"WPE WebKit web process exceeded its memory limit.",
        2 => b"WPE WebKit web process was terminated by an API request.",
        _ => b"WPE WebKit web process terminated for an unknown reason.",
    }
}
