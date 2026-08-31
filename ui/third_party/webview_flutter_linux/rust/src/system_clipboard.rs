// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! GTK-free system clipboard transport for the headless WPE runtime.
//!
//! WPE's headless display owns an in-process clipboard. Flutter owns the real
//! desktop window, so WPE cannot use the window system's clipboard directly.
//! This module bridges the two clipboards with `clipboard-rs`, whose Linux
//! implementations use the Wayland data-control protocols and X11 through
//! `x11rb`; no GTK object or Flutter C++ plugin participates.
//!
//! Desktop clipboard reads can wait for another process to answer a selection
//! request, while Wayland ownership has to keep serving MIME data after the
//! initiating call returns. Both jobs therefore live on one dedicated worker.
//! The platform thread only copies already-owned WPE bytes into a command or
//! applies an already-owned result back to WPE. This preserves WPE's strict
//! thread affinity and prevents a slow clipboard owner from stalling frames.

use std::{
    collections::{HashMap, HashSet},
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
        mpsc::{self, Receiver, Sender},
    },
    thread,
    time::{Duration, Instant},
};

use clipboard_rs::{Clipboard, ClipboardContent, ClipboardContext};

/// Maximum number of desktop formats copied for one clipboard item.
///
/// Clipboard owners routinely advertise aliases and conversion targets. A
/// fixed count prevents an untrusted owner from forcing an unbounded number of
/// synchronous selection requests while leaving ample room for browser data.
pub(crate) const MAX_CLIPBOARD_FORMATS: usize = 32;

/// Maximum byte length accepted for an individual clipboard representation.
pub(crate) const MAX_CLIPBOARD_FORMAT_BYTES: usize = 16 * 1024 * 1024;

/// Maximum aggregate byte length retained for one clipboard item.
pub(crate) const MAX_CLIPBOARD_TOTAL_BYTES: usize = 32 * 1024 * 1024;

/// Maximum number of bytes accepted in a MIME/selection target name.
const MAX_FORMAT_NAME_BYTES: usize = 255;

/// Completed requests are retained briefly so a paused Dart isolate can still
/// collect them. New commands opportunistically remove older results.
const REQUEST_RETENTION: Duration = Duration::from_secs(30);

pub(crate) const REQUEST_PENDING: i32 = 0;
pub(crate) const REQUEST_SUCCEEDED: i32 = 1;
pub(crate) const REQUEST_FAILED: i32 = -1;
pub(crate) const REQUEST_UNKNOWN: i32 = -2;

const MIME_TEXT_UTF8: &str = "text/plain;charset=utf-8";
const MIME_TEXT: &str = "text/plain";
const MIME_HTML: &str = "text/html";
const MIME_RTF: &str = "text/rtf";

/// One owned MIME representation in a clipboard snapshot.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct ClipboardFormat {
    pub(crate) name: String,
    pub(crate) bytes: Vec<u8>,
}

/// A bounded, thread-safe copy of one logical clipboard item.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub(crate) struct ClipboardSnapshot {
    pub(crate) formats: Vec<ClipboardFormat>,
    total_bytes: usize,
}

impl ClipboardSnapshot {
    /// Adds a representation if its name, size, and the aggregate size satisfy
    /// the bridge limits. Duplicate format names retain the first value.
    pub(crate) fn try_push(&mut self, name: String, bytes: Vec<u8>) -> bool {
        if !is_transferable_format(&name)
            || bytes.len() > MAX_CLIPBOARD_FORMAT_BYTES
            || self.formats.len() >= MAX_CLIPBOARD_FORMATS
            || self
                .total_bytes
                .checked_add(bytes.len())
                .is_none_or(|length| length > MAX_CLIPBOARD_TOTAL_BYTES)
            || self.formats.iter().any(|format| format.name == name)
        {
            return false;
        }
        self.total_bytes += bytes.len();
        self.formats.push(ClipboardFormat { name, bytes });
        true
    }

    /// Returns the best UTF-8 plain-text representation, if one exists.
    pub(crate) fn plain_text(&self) -> Option<&str> {
        self.formats
            .iter()
            .filter(|format| is_plain_text_format(&format.name))
            .min_by_key(|format| format_priority(&format.name))
            .and_then(|format| std::str::from_utf8(&format.bytes).ok())
    }

    /// Replaces every plain-text alias while preserving richer representations.
    pub(crate) fn replace_plain_text(&mut self, text: String) -> bool {
        self.formats
            .retain(|format| !is_plain_text_format(&format.name));
        self.total_bytes = self.formats.iter().map(|format| format.bytes.len()).sum();
        self.try_push(MIME_TEXT_UTF8.to_owned(), text.into_bytes())
    }

    fn into_clipboard_contents(self) -> Vec<ClipboardContent> {
        let plain_text = self.plain_text().map(ToOwned::to_owned);
        let mut contents = Vec::with_capacity(self.formats.len() + 1);
        if let Some(text) = plain_text {
            // `Text` makes clipboard-rs advertise the conventional Wayland
            // text aliases and X11 UTF8_STRING target in addition to richer
            // representations below.
            contents.push(ClipboardContent::Text(text));
        }

        for format in self.formats {
            if is_plain_text_format(&format.name) {
                // Preserve explicit MIME aliases as well. They matter to WPE
                // and to applications that request MIME targets rather than
                // the X11 UTF8_STRING convention.
                contents.push(ClipboardContent::Other(format.name, format.bytes));
            } else if format.name.eq_ignore_ascii_case(MIME_HTML) {
                match String::from_utf8(format.bytes) {
                    Ok(html) => contents.push(ClipboardContent::Html(html)),
                    Err(error) => {
                        contents.push(ClipboardContent::Other(format.name, error.into_bytes()))
                    }
                }
            } else if format.name.eq_ignore_ascii_case(MIME_RTF) {
                match String::from_utf8(format.bytes) {
                    Ok(rtf) => contents.push(ClipboardContent::Rtf(rtf)),
                    Err(error) => {
                        contents.push(ClipboardContent::Other(format.name, error.into_bytes()))
                    }
                }
            } else {
                contents.push(ClipboardContent::Other(format.name, format.bytes));
            }
        }
        contents
    }
}

/// Returns whether a target is safe to carry through the bridge.
///
/// MIME names are ASCII tokens. X11 also exposes legacy text target names, so
/// those are accepted explicitly. Protocol/control targets such as `TARGETS`
/// are intentionally not copied as data representations.
pub(crate) fn is_transferable_format(name: &str) -> bool {
    if name.is_empty() || name.len() > MAX_FORMAT_NAME_BYTES || name.contains('\0') {
        return false;
    }
    if is_plain_text_format(name) {
        return true;
    }
    name.contains('/') && name.bytes().all(|byte| byte.is_ascii_graphic())
}

pub(crate) fn is_plain_text_format(name: &str) -> bool {
    name.eq_ignore_ascii_case(MIME_TEXT_UTF8)
        || name.eq_ignore_ascii_case(MIME_TEXT)
        || name.eq_ignore_ascii_case("UTF8_STRING")
        || name.eq_ignore_ascii_case("TEXT")
        || name.eq_ignore_ascii_case("STRING")
}

/// Sorts and deduplicates advertised formats before any content is requested.
/// Important browser formats are read first so aggregate limits cannot crowd
/// out text or HTML with a long tail of conversion targets.
pub(crate) fn prioritized_formats(formats: impl IntoIterator<Item = String>) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut formats = formats
        .into_iter()
        .filter(|format| is_transferable_format(format))
        .filter(|format| seen.insert(format.to_ascii_lowercase()))
        .collect::<Vec<_>>();
    formats.sort_by_key(|format| (format_priority(format), format.to_ascii_lowercase()));
    formats.truncate(MAX_CLIPBOARD_FORMATS);
    formats
}

fn format_priority(format: &str) -> u8 {
    if format.eq_ignore_ascii_case(MIME_TEXT_UTF8) {
        0
    } else if format.eq_ignore_ascii_case("UTF8_STRING") {
        1
    } else if is_plain_text_format(format) {
        2
    } else if format.eq_ignore_ascii_case(MIME_HTML) {
        3
    } else if format.eq_ignore_ascii_case("text/uri-list") {
        4
    } else if format.eq_ignore_ascii_case("image/png") {
        5
    } else if format.eq_ignore_ascii_case(MIME_RTF) || format.eq_ignore_ascii_case("text/richtext")
    {
        6
    } else if format.starts_with("image/") {
        7
    } else if format.starts_with("text/") {
        8
    } else {
        9
    }
}

enum ClipboardCommand {
    Export {
        request_id: u64,
        snapshot: ClipboardSnapshot,
    },
    Import {
        request_id: u64,
    },
}

enum RequestValue {
    Pending,
    Exported(Result<(), String>),
    Imported(Result<ClipboardSnapshot, String>),
}

struct RequestEntry {
    updated_at: Instant,
    value: RequestValue,
}

struct ClipboardService {
    next_request_id: AtomicU64,
    sender: Sender<ClipboardCommand>,
    requests: Arc<Mutex<HashMap<u64, RequestEntry>>>,
}

impl ClipboardService {
    fn new() -> Self {
        let (sender, receiver) = mpsc::channel();
        let requests = Arc::new(Mutex::new(HashMap::new()));
        let worker_requests = Arc::clone(&requests);
        thread::Builder::new()
            .name("webview-linux-clipboard".to_owned())
            .spawn(move || clipboard_worker(receiver, worker_requests))
            .expect("failed to create the system clipboard worker");
        Self {
            next_request_id: AtomicU64::new(1),
            sender,
            requests,
        }
    }

    fn allocate_request(&self) -> u64 {
        loop {
            let request_id = self.next_request_id.fetch_add(1, Ordering::Relaxed);
            if request_id != 0 {
                return request_id;
            }
        }
    }

    fn insert_pending(&self, request_id: u64) {
        let mut requests = self
            .requests
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        requests.insert(
            request_id,
            RequestEntry {
                updated_at: Instant::now(),
                value: RequestValue::Pending,
            },
        );
    }

    fn mark_send_failure(&self, request_id: u64) {
        set_request_value(
            &self.requests,
            request_id,
            RequestValue::Exported(Err("clipboard worker stopped".to_owned())),
        );
    }
}

fn service() -> &'static ClipboardService {
    static SERVICE: OnceLock<ClipboardService> = OnceLock::new();
    SERVICE.get_or_init(ClipboardService::new)
}

/// Queues a browser-to-desktop clipboard snapshot and returns its request ID.
pub(crate) fn request_export(snapshot: ClipboardSnapshot) -> u64 {
    let service = service();
    let request_id = service.allocate_request();
    service.insert_pending(request_id);
    if service
        .sender
        .send(ClipboardCommand::Export {
            request_id,
            snapshot,
        })
        .is_err()
    {
        service.mark_send_failure(request_id);
    }
    request_id
}

/// Queues a desktop-to-browser clipboard read and returns its request ID.
pub(crate) fn request_import() -> u64 {
    let service = service();
    let request_id = service.allocate_request();
    service.insert_pending(request_id);
    if service
        .sender
        .send(ClipboardCommand::Import { request_id })
        .is_err()
    {
        set_request_value(
            &service.requests,
            request_id,
            RequestValue::Imported(Err("clipboard worker stopped".to_owned())),
        );
    }
    request_id
}

/// Returns the current state of a request without consuming its payload.
pub(crate) fn request_status(request_id: u64) -> i32 {
    if request_id == 0 {
        return REQUEST_UNKNOWN;
    }
    let requests = service()
        .requests
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    match requests.get(&request_id).map(|entry| &entry.value) {
        Some(RequestValue::Pending) => REQUEST_PENDING,
        Some(RequestValue::Exported(Ok(())) | RequestValue::Imported(Ok(_))) => REQUEST_SUCCEEDED,
        Some(RequestValue::Exported(Err(_)) | RequestValue::Imported(Err(_))) => REQUEST_FAILED,
        None => REQUEST_UNKNOWN,
    }
}

/// Removes and returns a successful imported snapshot.
pub(crate) fn take_import(request_id: u64) -> Result<ClipboardSnapshot, i32> {
    let mut requests = service()
        .requests
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let Some(entry) = requests.remove(&request_id) else {
        return Err(REQUEST_UNKNOWN);
    };
    match entry.value {
        RequestValue::Imported(Ok(snapshot)) => Ok(snapshot),
        RequestValue::Pending => {
            requests.insert(request_id, entry);
            Err(REQUEST_PENDING)
        }
        RequestValue::Imported(Err(_)) | RequestValue::Exported(_) => Err(REQUEST_FAILED),
    }
}

/// Drops a terminal request or abandons a result Dart no longer needs.
pub(crate) fn discard_request(request_id: u64) {
    if request_id == 0 {
        return;
    }
    service()
        .requests
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .remove(&request_id);
}

fn clipboard_worker(
    receiver: Receiver<ClipboardCommand>,
    requests: Arc<Mutex<HashMap<u64, RequestEntry>>>,
) {
    let mut clipboard = None;
    while let Ok(command) = receiver.recv() {
        remove_expired_requests(&requests);
        match command {
            ClipboardCommand::Export {
                request_id,
                snapshot,
            } => {
                // A fresh headless WPE display can advance its clipboard
                // revision before it advertises any formats. Treat that
                // initialization snapshot as no new browser ownership: if it
                // cleared the desktop selection, it could erase a Flutter
                // value immediately before the first paste gesture.
                let result = if snapshot.formats.is_empty() {
                    Ok(())
                } else {
                    clipboard_context(&mut clipboard)
                        .and_then(|context| export_snapshot(context, snapshot))
                };
                set_request_value(&requests, request_id, RequestValue::Exported(result));
            }
            ClipboardCommand::Import { request_id } => {
                let result = clipboard_context(&mut clipboard).and_then(import_snapshot);
                set_request_value(&requests, request_id, RequestValue::Imported(result));
            }
        }
    }
}

fn clipboard_context(
    clipboard: &mut Option<ClipboardContext>,
) -> Result<&ClipboardContext, String> {
    if clipboard.is_none() {
        *clipboard = Some(ClipboardContext::new().map_err(|error| error.to_string())?);
    }
    Ok(clipboard.as_ref().expect("clipboard was initialized"))
}

fn export_snapshot(
    clipboard: &ClipboardContext,
    snapshot: ClipboardSnapshot,
) -> Result<(), String> {
    if snapshot.formats.is_empty() {
        return Ok(());
    }
    clipboard
        .set(snapshot.into_clipboard_contents())
        .map_err(|error| error.to_string())
}

fn import_snapshot(clipboard: &ClipboardContext) -> Result<ClipboardSnapshot, String> {
    let formats = clipboard
        .available_formats()
        .map_err(|error| error.to_string())?;
    let mut snapshot = ClipboardSnapshot::default();
    let mut last_error = None;
    for format in prioritized_formats(formats) {
        let bytes = match clipboard.get_buffer(&format) {
            Ok(bytes) => bytes,
            Err(error) => {
                // Clipboard owners may advertise lazy conversions they cannot
                // ultimately produce. Keep the other representations instead
                // of degrading a valid rich item to the Dart text fallback.
                last_error = Some(format!("failed to read clipboard format {format}: {error}"));
                continue;
            }
        };
        let canonical_name = if is_plain_text_format(&format) {
            MIME_TEXT_UTF8.to_owned()
        } else {
            format
        };
        snapshot.try_push(canonical_name, bytes);
    }
    if snapshot.formats.is_empty() {
        Err(last_error.unwrap_or_else(|| "clipboard contains no transferable formats".to_owned()))
    } else {
        Ok(snapshot)
    }
}

fn set_request_value(
    requests: &Mutex<HashMap<u64, RequestEntry>>,
    request_id: u64,
    value: RequestValue,
) {
    let mut requests = requests.lock().unwrap_or_else(|error| error.into_inner());
    if let Some(entry) = requests.get_mut(&request_id) {
        entry.updated_at = Instant::now();
        entry.value = value;
    }
}

fn remove_expired_requests(requests: &Mutex<HashMap<u64, RequestEntry>>) {
    let now = Instant::now();
    requests
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .retain(|_, entry| now.duration_since(entry.updated_at) < REQUEST_RETENTION);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snapshot_enforces_duplicates_and_byte_limits() {
        let mut snapshot = ClipboardSnapshot::default();
        assert!(snapshot.try_push(MIME_TEXT.to_owned(), b"hello".to_vec()));
        assert!(!snapshot.try_push(MIME_TEXT.to_owned(), b"second".to_vec()));
        assert!(!snapshot.try_push("TARGETS".to_owned(), Vec::new()));
        assert!(!snapshot.try_push(
            "image/png".to_owned(),
            vec![0; MAX_CLIPBOARD_FORMAT_BYTES + 1],
        ));
        assert_eq!(snapshot.formats.len(), 1);
        assert_eq!(snapshot.plain_text(), Some("hello"));
    }

    #[test]
    fn important_formats_are_prioritized_and_aliases_are_deduplicated() {
        let formats = prioritized_formats([
            "application/example".to_owned(),
            "image/webp".to_owned(),
            "text/html".to_owned(),
            "UTF8_STRING".to_owned(),
            "text/plain;charset=utf-8".to_owned(),
            "TEXT/HTML".to_owned(),
            "TARGETS".to_owned(),
        ]);
        assert_eq!(
            formats,
            [
                "text/plain;charset=utf-8",
                "UTF8_STRING",
                "text/html",
                "image/webp",
                "application/example",
            ]
        );
    }

    #[test]
    fn clipboard_contents_preserve_plain_and_rich_representations() {
        let mut snapshot = ClipboardSnapshot::default();
        assert!(snapshot.try_push(MIME_TEXT_UTF8.to_owned(), b"hello".to_vec()));
        assert!(snapshot.try_push(MIME_HTML.to_owned(), b"<b>hello</b>".to_vec()));
        assert!(snapshot.try_push("image/png".to_owned(), vec![1, 2, 3]));

        let contents = snapshot.into_clipboard_contents();
        assert!(matches!(&contents[0], ClipboardContent::Text(text) if text == "hello"));
        assert!(matches!(&contents[1], ClipboardContent::Other(name, _) if name == MIME_TEXT_UTF8));
        assert!(matches!(&contents[2], ClipboardContent::Html(html) if html == "<b>hello</b>"));
        assert!(
            matches!(&contents[3], ClipboardContent::Other(name, bytes) if name == "image/png" && bytes == &[1, 2, 3])
        );
    }

    #[test]
    fn plain_text_replacement_preserves_rich_representations() {
        let mut snapshot = ClipboardSnapshot::default();
        assert!(snapshot.try_push(MIME_TEXT.to_owned(), b"stale".to_vec()));
        assert!(snapshot.try_push(MIME_HTML.to_owned(), b"<b>fresh</b>".to_vec()));

        assert!(snapshot.replace_plain_text("fresh".to_owned()));
        assert_eq!(snapshot.plain_text(), Some("fresh"));
        assert!(
            snapshot
                .formats
                .iter()
                .any(|format| format.name == MIME_HTML && format.bytes == b"<b>fresh</b>")
        );
    }
}
