// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! WPE and desktop clipboard synchronization.
//!
//! WPE clipboard access is platform-thread-affine, while desktop Wayland/X11
//! transfers run through the thread-safe system clipboard worker. This module
//! owns the bounded snapshot conversion and the polling ABI joining both sides.

use super::prelude::*;

/// Resolves the clipboard belonging to a handle's WPE display.
///
/// WPE clipboard objects are transfer-none. `operation` must not retain the
/// pointer beyond the closure call.
fn with_clipboard<T>(
    handle: u64,
    fallback: T,
    operation: impl FnOnce(*mut WpeClipboard) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    {
        let runtime = native_view.runtime.borrow();
        let Some(runtime) = runtime.as_ref() else {
            return fallback;
        };
        let raw_webview =
            ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
                as *mut WebKitWebView;
        let display = unsafe { webkit_web_view_get_display(raw_webview) };
        if display.is_null() {
            return fallback;
        }
        let clipboard = unsafe { wpe_display_get_clipboard(display) };
        if clipboard.is_null() {
            fallback
        } else {
            operation(clipboard)
        }
    }
}

const UTF8_TEXT_MIME: &str = "text/plain;charset=utf-8";
const UTF8_TEXT_FORMAT: &[u8] = b"text/plain;charset=utf-8\0";

#[unsafe(no_mangle)]
/// Returns WPE's monotonically increasing clipboard change count.
///
/// Dart compares this value with the last observed count to avoid repeatedly
/// copying unchanged browser clipboard text. Returns `-1` when unavailable.
pub extern "C" fn webview_flutter_linux_wpe_clipboard_change_count(handle: u64) -> i64 {
    with_clipboard(handle, -1, |clipboard| unsafe {
        wpe_clipboard_get_change_count(clipboard)
    })
}

#[unsafe(no_mangle)]
/// Returns the UTF-8 byte length of the current plain-text clipboard value.
///
/// WPE allocates a temporary read buffer; this function frees it after reading
/// the length. Dart uses the result to allocate the exact destination buffer.
pub extern "C" fn webview_flutter_linux_wpe_clipboard_text_length(handle: u64) -> isize {
    with_clipboard(handle, -1, |clipboard| {
        let mut length = 0;
        let text = unsafe {
            wpe_clipboard_read_text(clipboard, UTF8_TEXT_FORMAT.as_ptr().cast(), &mut length)
        };
        if text.is_null() {
            -1
        } else {
            unsafe { glib::ffi::g_free(text.cast()) };
            length.min(isize::MAX as usize) as isize
        }
    })
}

#[unsafe(no_mangle)]
/// Copies the current plain-text clipboard value into caller-owned storage.
///
/// Returns the number of bytes copied. `-1` denotes a null destination, `-2`
/// an unavailable view/clipboard, `-3` insufficient destination capacity, and
/// `-4` a failed WPE text read.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes. It may not
/// alias memory managed by WPE. The pointer is used only during this call.
pub unsafe extern "C" fn webview_flutter_linux_wpe_clipboard_copy_text(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_clipboard(handle, -2, |clipboard| {
        let mut length = 0;
        let text = unsafe {
            wpe_clipboard_read_text(clipboard, UTF8_TEXT_FORMAT.as_ptr().cast(), &mut length)
        };
        if text.is_null() {
            return -4;
        }
        if destination_length < length || length > i32::MAX as usize {
            unsafe { glib::ffi::g_free(text.cast()) };
            return -3;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(text.cast(), destination, length);
            glib::ffi::g_free(text.cast());
        }
        length as i32
    })
}

#[unsafe(no_mangle)]
/// Replaces the browser clipboard with caller-provided UTF-8 plain text.
///
/// WPE copies the string into a new `WpeClipboardContent`; the caller retains
/// ownership of `text`. Returns `-1` for null/invalid UTF-8, `-2` when the
/// clipboard is unavailable, and `-3` if content allocation fails.
///
/// # Safety
///
/// `text` must point to a readable NUL-terminated byte sequence for the
/// duration of this call.
pub unsafe extern "C" fn webview_flutter_linux_wpe_clipboard_set_text(
    handle: u64,
    text: *const c_char,
) -> i32 {
    if text.is_null() || unsafe { CStr::from_ptr(text) }.to_str().is_err() {
        return -1;
    }
    with_clipboard(handle, -2, |clipboard| {
        let content = unsafe { wpe_clipboard_content_new() };
        if content.is_null() {
            return -3;
        }
        unsafe {
            wpe_clipboard_content_set_text(content, text);
            wpe_clipboard_set_content(clipboard, content);
            wpe_clipboard_content_unref(content);
        }
        0
    })
}

/// Copies the WPE clipboard into a bounded, thread-safe snapshot.
///
/// `wpe_clipboard_get_formats()` and `wpe_clipboard_read_bytes()` must run on
/// the WPE platform thread. Each returned `GBytes` is transfer-full, so its
/// payload is copied into Rust-owned memory and the native reference is
/// released before this function returns. No WPE pointer crosses to the
/// desktop clipboard worker.
fn snapshot_wpe_clipboard(handle: u64) -> Result<ClipboardSnapshot, i32> {
    with_clipboard(handle, Err(-2), |clipboard| unsafe {
        let raw_formats = wpe_clipboard_get_formats(clipboard);
        if raw_formats.is_null() {
            return Ok(ClipboardSnapshot::default());
        }

        // WPE promises a NULL-terminated array. The defensive upper bound
        // prevents a corrupted native array from causing an unbounded walk;
        // prioritized_formats() applies the smaller transfer limit afterward.
        let mut names = Vec::new();
        for index in 0..(MAX_CLIPBOARD_FORMATS * 4) {
            let raw_format = *raw_formats.add(index);
            if raw_format.is_null() {
                break;
            }
            if let Ok(format) = CStr::from_ptr(raw_format).to_str() {
                names.push(format.to_owned());
            }
        }

        let mut snapshot = ClipboardSnapshot::default();
        for name in prioritized_formats(names) {
            let Ok(native_name) = CString::new(name.as_bytes()) else {
                continue;
            };
            let bytes = wpe_clipboard_read_bytes(clipboard, native_name.as_ptr());
            if bytes.is_null() {
                continue;
            }
            let mut length = 0;
            let data = glib::ffi::g_bytes_get_data(bytes, &mut length);
            let owned = if length == 0 {
                Vec::new()
            } else if data.is_null() {
                glib::ffi::g_bytes_unref(bytes);
                continue;
            } else {
                std::slice::from_raw_parts(data.cast::<u8>(), length).to_vec()
            };
            glib::ffi::g_bytes_unref(bytes);
            snapshot.try_push(name, owned);
        }

        // Text copied by an editing command is exposed through WPE's
        // conversion API even when the clipboard has not advertised a byte
        // target yet. Relying only on `get_formats` can therefore observe the
        // new change count, export an empty/partial snapshot, and permanently
        // mark that revision as handled. Preserve all rich representations
        // above, then fill only a missing plain-text representation from the
        // canonical UTF-8 conversion before the snapshot leaves WPE's thread.
        if snapshot.plain_text().is_none() {
            let mut length = 0;
            let text =
                wpe_clipboard_read_text(clipboard, UTF8_TEXT_FORMAT.as_ptr().cast(), &mut length);
            if !text.is_null() {
                let owned = if length == 0 {
                    Vec::new()
                } else {
                    std::slice::from_raw_parts(text.cast(), length).to_vec()
                };
                glib::ffi::g_free(text.cast());
                snapshot.try_push(UTF8_TEXT_MIME.to_owned(), owned);
            }
        }
        Ok(snapshot)
    })
}

/// Applies an owned system clipboard snapshot to WPE on its platform thread.
fn apply_system_clipboard_snapshot(handle: u64, snapshot: ClipboardSnapshot) -> i32 {
    with_clipboard(handle, -2, |clipboard| {
        if snapshot.formats.is_empty() {
            unsafe { wpe_clipboard_set_content(clipboard, std::ptr::null_mut()) };
            return 0;
        }

        let content = unsafe { wpe_clipboard_content_new() };
        if content.is_null() {
            return -3;
        }

        let plain_text = snapshot
            .plain_text()
            .and_then(|text| CString::new(text).ok());
        if let Some(text) = &plain_text {
            unsafe { wpe_clipboard_content_set_text(content, text.as_ptr()) };
        }

        for format in snapshot.formats {
            if plain_text.is_some() && crate::system_clipboard::is_plain_text_format(&format.name) {
                continue;
            }
            let Ok(native_format) = CString::new(format.name) else {
                continue;
            };
            let data = if format.bytes.is_empty() {
                std::ptr::null()
            } else {
                format.bytes.as_ptr().cast()
            };
            let bytes = unsafe { glib::ffi::g_bytes_new(data, format.bytes.len()) };
            if bytes.is_null() {
                continue;
            }
            unsafe {
                wpe_clipboard_content_set_bytes(content, native_format.as_ptr(), bytes);
                glib::ffi::g_bytes_unref(bytes);
            }
        }

        unsafe {
            wpe_clipboard_set_content(clipboard, content);
            wpe_clipboard_content_unref(content);
        }
        0
    })
}

#[unsafe(no_mangle)]
/// Queues all transferable WPE clipboard formats for desktop ownership.
///
/// The returned non-zero identifier can be polled with
/// [`webview_flutter_linux_system_clipboard_request_status`]. Zero means the
/// view or WPE clipboard was unavailable and no request was created.
pub extern "C" fn webview_flutter_linux_system_clipboard_export(handle: u64) -> u64 {
    snapshot_wpe_clipboard(handle)
        .map(crate::system_clipboard::request_export)
        .unwrap_or(0)
}

#[unsafe(no_mangle)]
/// Starts an asynchronous read of every supported desktop clipboard format.
pub extern "C" fn webview_flutter_linux_system_clipboard_import() -> u64 {
    crate::system_clipboard::request_import()
}

#[unsafe(no_mangle)]
/// Returns zero while pending, one on success, or a negative failure status.
pub extern "C" fn webview_flutter_linux_system_clipboard_request_status(request_id: u64) -> i32 {
    crate::system_clipboard::request_status(request_id)
}

#[unsafe(no_mangle)]
/// Consumes a completed desktop read and installs it in the WPE clipboard.
///
/// When `plain_text_override` is non-null, its Flutter-provided UTF-8 value
/// replaces the snapshot's native plain-text aliases while retaining HTML,
/// images, and custom formats. This reconciles clipboard backends that report
/// stale text for a newly changed Wayland selection.
///
/// This call must execute on the WPE platform thread. A pending request returns
/// zero, a successful application returns one, and failures are negative.
///
/// # Safety
///
/// `plain_text_override`, when non-null, must point to a readable
/// NUL-terminated UTF-8 sequence for the duration of this call.
pub unsafe extern "C" fn webview_flutter_linux_system_clipboard_apply_import(
    handle: u64,
    request_id: u64,
    plain_text_override: *const c_char,
) -> i32 {
    match crate::system_clipboard::take_import(request_id) {
        Ok(mut snapshot) => {
            if !plain_text_override.is_null() {
                let Ok(text) = required_c_string(plain_text_override) else {
                    return -3;
                };
                if !snapshot.replace_plain_text(text) {
                    return -3;
                }
            }
            match apply_system_clipboard_snapshot(handle, snapshot) {
                0 => crate::system_clipboard::REQUEST_SUCCEEDED,
                status => status,
            }
        }
        Err(status) => status,
    }
}

#[unsafe(no_mangle)]
/// Releases a completed request or abandons a result that is no longer needed.
pub extern "C" fn webview_flutter_linux_system_clipboard_discard(request_id: u64) {
    crate::system_clipboard::discard_request(request_id);
}
