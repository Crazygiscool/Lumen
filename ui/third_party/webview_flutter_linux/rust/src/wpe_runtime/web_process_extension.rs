// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Web-process request interception and authoritative frame classification.
//!
//! WPE's UI-process `WebKitURIRequest` values are monitoring snapshots:
//! changing their header collection does not affect the network request. The
//! public `WebKitWebPage::send-request` signal is the supported interception
//! point, but it runs in WebKit's separately sandboxed web process. This module
//! makes the package's Rust library serve both roles:
//!
//! 1. The Flutter process copies the currently loaded library into a private,
//!    process-scoped extension directory before creating the first WebView.
//! 2. A POST navigation atomically writes its exact URL and headers to a
//!    nonce-keyed file in that directory. The nonce is carried in a temporary
//!    internal `Content-Type` value inside WebKit's native history item.
//! 3. WPE loads the same library into its web process and calls the exported
//!    initialization symbol below. The extension claims the matching nonce,
//!    verifies the exact POST URL, replaces the temporary content type with
//!    the caller's real headers, then removes the handoff.
//!
//! The handoff is deliberately bounded and contains no body or cookies. WebKit
//! continues to own the native form body, redirect policy, credential store,
//! cache, and history. Nonces and a unique application-process directory
//! isolate simultaneous identical requests without requiring a C shim or a
//! socket.
//!
//! The same public extension APIs close WPE's UI-process frame-information
//! gap. A private one-shot gate file marks only HTTP requests whose policy is
//! waiting for Dart; `send-request` claims that marker, reads
//! `Sec-Fetch-Dest`, and synchronously asks the exact owning view to allow or
//! cancel before network dispatch. An isolated extension script handles
//! custom schemes that never reach request or response policy, including when
//! page-authored JavaScript is disabled. Approved loads never enter the
//! synchronous message roundtrip.

use std::{
    ffi::{CStr, CString, c_void},
    fs::{self, OpenOptions},
    io::Write,
    os::{unix::ffi::OsStrExt, unix::fs::OpenOptionsExt},
    path::{Path, PathBuf},
    sync::{
        OnceLock,
        atomic::{AtomicU64, Ordering},
    },
};

use super::{navigation, prelude::*};

const HANDOFF_MAGIC: &[u8; 8] = b"WFLHDR1\0";
const MAX_HANDOFF_BYTES: usize = 16 * 1024 * 1024;
const MAX_HANDOFF_HEADERS: usize = 1024;
const EXTENSION_FILE_NAME: &str = "libwebview_flutter_linux_web_process_extension.so";
const MARKER_CONTENT_TYPE_PREFIX: &str = "application/x-webview-flutter-linux-request; id=";
const POLICY_GATE_FILE_PREFIX: &str = "navigation-policy-";
const POLICY_GATE_FILE_SUFFIX: &str = ".gate";
const FRAME_HINT_MESSAGE_NAME: &CStr = c"webview-flutter-linux-frame-hint-0-1";
const FRAME_DECISION_MESSAGE_NAME: &CStr = c"webview-flutter-linux-frame-decision-0-1";
const FRAME_ANNOUNCEMENT_MESSAGE_NAME: &CStr = c"webview-flutter-linux-frame-announcement-0-1";
const FRAME_ANNOUNCEMENT_WORLD_NAME: &CStr = c"webview-flutter-linux-frame-announcement-0-1";
const FRAME_ANNOUNCEMENT_FUNCTION_NAME: &CStr = c"__webviewFlutterLinuxAnnounceNavigation_0_1";
const FRAME_ANNOUNCEMENT_SOURCE: &str = r#"
(() => {
  const announce = globalThis.__webviewFlutterLinuxAnnounceNavigation_0_1;
  if (typeof announce !== 'function') return;
  const pending = new Set();
  const emit = (targetsChild, url) => {
    if (typeof url !== 'string' || url.length === 0) return;
    let scheme;
    try {
      scheme = new URL(url, document.baseURI).protocol;
    } catch (_) {
      return;
    }
    if (['http:', 'https:', 'data:', 'file:', 'about:'].includes(scheme)) {
      return;
    }
    const key = `${targetsChild ? 'S' : 'C'}\n${url}`;
    if (pending.has(key)) return;
    pending.add(key);
    queueMicrotask(() => pending.delete(key));
    announce(targetsChild, url);
  };
  window.navigation?.addEventListener('navigate', event => {
    emit(false, event.destination?.url);
  });
  const announceFrame = frame => {
    if (frame?.matches?.('iframe,frame')) emit(true, frame.src);
  };
  const scan = node => {
    if (node?.nodeType !== Node.ELEMENT_NODE) return;
    announceFrame(node);
    node.querySelectorAll?.('iframe,frame').forEach(announceFrame);
  };
  new MutationObserver(records => {
    for (const record of records) {
      if (record.type === 'attributes') announceFrame(record.target);
      for (const node of record.addedNodes) scan(node);
    }
  }).observe(document, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ['src']
  });
  document.querySelectorAll('iframe,frame').forEach(announceFrame);
})();
"#;

static EXTENSION_DIRECTORY: OnceLock<PathBuf> = OnceLock::new();
static NEXT_HANDOFF_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Debug, PartialEq, Eq)]
struct PendingRequestHeaders {
    url: Vec<u8>,
    headers: Vec<(Vec<u8>, Vec<u8>)>,
}

/// One header handoff prepared by the UI process but not yet claimed by WPE.
///
/// The path is retained by its originating view so a later navigation or view
/// disposal can remove a handoff when WebKit suppresses the corresponding
/// network load (for example, an identical current-history navigation).
pub(super) struct PreparedRequestHeaderHandoff {
    pub(super) marker: String,
    pub(super) path: PathBuf,
}

/// One exact URL marker authorizing the web process to wait for Dart.
///
/// UI-process request objects are immutable monitoring snapshots, so the
/// process-private extension directory carries this one-shot intent across the
/// process boundary. Keeping the path in the owning view permits deterministic
/// cleanup when WebKit abandons the corresponding navigation.
pub(super) struct PreparedNavigationPolicyGate {
    pub(super) url: Vec<u8>,
    pub(super) path: PathBuf,
}

/// Finds the filesystem image containing this function through the loader.
///
/// This works in both processes: the Flutter process resolves the native asset
/// selected by Dart, while the WebKit process resolves the private extension
/// copy that it loaded.
fn current_library_path() -> Result<PathBuf, i32> {
    let mut info = std::mem::MaybeUninit::<libc::Dl_info>::zeroed();
    let address = crate::webview_flutter_linux_api_version as *const () as *const c_void;
    // SAFETY: `address` is a function in the currently loaded library and
    // `info` points to writable storage for the duration of `dladdr`.
    if unsafe { libc::dladdr(address, info.as_mut_ptr()) } == 0 {
        return Err(-17);
    }
    // SAFETY: a successful `dladdr` initializes `Dl_info`; `dli_fname` is a
    // loader-owned NUL-terminated path valid while this library is loaded.
    let info = unsafe { info.assume_init() };
    if info.dli_fname.is_null() {
        return Err(-17);
    }
    let path = PathBuf::from(std::ffi::OsStr::from_bytes(
        unsafe { CStr::from_ptr(info.dli_fname) }.to_bytes(),
    ));
    path.canonicalize().map_err(|_| -17)
}

/// Creates and registers the directory WPE scans for web-process extensions.
///
/// Configuration must happen before the first page load. The copied library is
/// process-scoped so a development rebuild or a second application instance
/// cannot replace code beneath an already running WebKit process.
pub(super) fn configure_web_process_extension() -> Result<(), i32> {
    if EXTENSION_DIRECTORY.get().is_some() {
        return Ok(());
    }
    let source = current_library_path()?;
    let directory = std::env::temp_dir().join(format!(
        "webview-flutter-linux-{}-{}",
        unsafe { libc::geteuid() },
        std::process::id(),
    ));
    fs::create_dir_all(&directory).map_err(|_| -18)?;
    let destination = directory.join(EXTENSION_FILE_NAME);
    fs::copy(&source, &destination).map_err(|_| -18)?;

    let directory_bytes = directory.as_os_str().as_bytes();
    let directory_c = CString::new(directory_bytes).map_err(|_| -18)?;
    let context = unsafe { webkit_web_context_get_default() };
    if context.is_null() {
        return Err(-19);
    }
    // The extension reads and removes page-scoped handoff files, so the
    // sandbox grant must be writable. The directory itself remains private to
    // the application UID and unique process ID.
    unsafe {
        webkit_web_context_add_path_to_sandbox(context, directory_c.as_ptr(), 0);
        webkit_web_context_set_web_process_extensions_directory(context, directory_c.as_ptr());
    }
    EXTENSION_DIRECTORY.set(directory).map_err(|_| -18)
}

fn handoff_path(directory: &Path, token: &str) -> PathBuf {
    directory.join(format!("request-{token}.headers"))
}

fn policy_gate_path(directory: &Path, id: u64) -> PathBuf {
    directory.join(format!(
        "{POLICY_GATE_FILE_PREFIX}{id:016x}{POLICY_GATE_FILE_SUFFIX}"
    ))
}

/// Creates one atomic marker before the UI process advances an HTTP policy.
pub(super) fn prepare_navigation_policy_gate(
    url: &[u8],
) -> Result<PreparedNavigationPolicyGate, i32> {
    if url.is_empty() || url.len() > 64 * 1024 {
        return Err(-20);
    }
    let directory = EXTENSION_DIRECTORY.get().ok_or(-19)?;
    let id = NEXT_HANDOFF_ID.fetch_add(1, Ordering::Relaxed).max(1);
    let path = policy_gate_path(directory, id);
    let temporary = path.with_extension("gate.tmp");
    let mut file = OpenOptions::new()
        .create_new(true)
        .write(true)
        .mode(0o600)
        .open(&temporary)
        .map_err(|_| -18)?;
    if let Err(error) = file.write_all(url).and_then(|()| file.sync_all()) {
        drop(file);
        let _ = fs::remove_file(&temporary);
        let _ = error;
        return Err(-18);
    }
    drop(file);
    if fs::rename(&temporary, &path).is_err() {
        let _ = fs::remove_file(&temporary);
        return Err(-18);
    }
    Ok(PreparedNavigationPolicyGate {
        url: url.to_vec(),
        path,
    })
}

/// Removes a UI-owned marker that the web process no longer needs.
pub(super) fn discard_navigation_policy_gate(gate: &PreparedNavigationPolicyGate) {
    let _ = fs::remove_file(&gate.path);
}

/// Atomically claims the oldest exact URL marker in the web process.
///
/// Multiple web processes may inspect the same directory during a site
/// isolation transition. Renaming the matching file before removal guarantees
/// that exactly one request enters the synchronous Dart decision path.
fn claim_navigation_policy_gate(url: &[u8]) -> bool {
    let directory = if let Some(directory) = EXTENSION_DIRECTORY.get() {
        directory.clone()
    } else {
        let Ok(library) = current_library_path() else {
            return false;
        };
        let Some(directory) = library.parent() else {
            return false;
        };
        directory.to_path_buf()
    };
    claim_navigation_policy_gate_in(&directory, url)
}

fn claim_navigation_policy_gate_in(directory: &Path, url: &[u8]) -> bool {
    let Ok(entries) = fs::read_dir(directory) else {
        return false;
    };
    let mut paths = entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| {
                    name.starts_with(POLICY_GATE_FILE_PREFIX)
                        && name.ends_with(POLICY_GATE_FILE_SUFFIX)
                })
        })
        .collect::<Vec<_>>();
    paths.sort_unstable();
    for path in paths {
        let Ok(candidate) = fs::read(&path) else {
            continue;
        };
        if candidate != url {
            continue;
        }
        let claimed = path.with_extension("gate.claimed");
        if fs::rename(&path, &claimed).is_err() {
            continue;
        }
        let _ = fs::remove_file(claimed);
        return true;
    }
    false
}

fn push_field(output: &mut Vec<u8>, bytes: &[u8]) -> Result<(), i32> {
    let length = u32::try_from(bytes.len()).map_err(|_| -20)?;
    output.extend_from_slice(&length.to_le_bytes());
    output.extend_from_slice(bytes);
    (output.len() <= MAX_HANDOFF_BYTES).then_some(()).ok_or(-20)
}

fn encode_handoff(url: &str, headers: &[(String, String)]) -> Result<Vec<u8>, i32> {
    if headers.len() > MAX_HANDOFF_HEADERS {
        return Err(-20);
    }
    let mut output = Vec::with_capacity(
        HANDOFF_MAGIC.len()
            + url.len()
            + headers
                .iter()
                .map(|(name, value)| name.len() + value.len() + 8)
                .sum::<usize>(),
    );
    output.extend_from_slice(HANDOFF_MAGIC);
    push_field(&mut output, url.as_bytes())?;
    output.extend_from_slice(&u32::try_from(headers.len()).map_err(|_| -20)?.to_le_bytes());
    for (name, value) in headers {
        push_field(&mut output, name.as_bytes())?;
        push_field(&mut output, value.as_bytes())?;
    }
    Ok(output)
}

fn read_u32(input: &[u8], cursor: &mut usize) -> Option<u32> {
    let end = cursor.checked_add(4)?;
    let bytes: [u8; 4] = input.get(*cursor..end)?.try_into().ok()?;
    *cursor = end;
    Some(u32::from_le_bytes(bytes))
}

fn read_field(input: &[u8], cursor: &mut usize) -> Option<Vec<u8>> {
    let length = usize::try_from(read_u32(input, cursor)?).ok()?;
    let end = cursor.checked_add(length)?;
    let field = input.get(*cursor..end)?.to_vec();
    *cursor = end;
    Some(field)
}

fn decode_handoff(input: &[u8]) -> Option<PendingRequestHeaders> {
    if input.len() > MAX_HANDOFF_BYTES || !input.starts_with(HANDOFF_MAGIC) {
        return None;
    }
    let mut cursor = HANDOFF_MAGIC.len();
    let url = read_field(input, &mut cursor)?;
    let header_count = usize::try_from(read_u32(input, &mut cursor)?).ok()?;
    if header_count > MAX_HANDOFF_HEADERS {
        return None;
    }
    let mut headers = Vec::with_capacity(header_count);
    for _ in 0..header_count {
        headers.push((
            read_field(input, &mut cursor)?,
            read_field(input, &mut cursor)?,
        ));
    }
    (cursor == input.len()).then_some(PendingRequestHeaders { url, headers })
}

/// Writes one nonce-scoped header handoff and returns its marker content type.
pub(super) fn prepare_request_header_handoff(
    url: &str,
    headers: &[(String, String)],
) -> Result<PreparedRequestHeaderHandoff, i32> {
    let directory = EXTENSION_DIRECTORY.get().ok_or(-19)?;
    if headers.is_empty() {
        return Err(-20);
    }
    let id = NEXT_HANDOFF_ID.fetch_add(1, Ordering::Relaxed).max(1);
    let token = format!("{id:016x}");
    let path = handoff_path(directory, &token);
    let encoded = encode_handoff(url, headers)?;
    let temporary = path.with_extension("headers.tmp");
    let mut file = OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .mode(0o600)
        .open(&temporary)
        .map_err(|_| -18)?;
    file.write_all(&encoded).map_err(|_| -18)?;
    file.sync_all().map_err(|_| -18)?;
    drop(file);
    fs::rename(temporary, &path).map_err(|_| -18)?;
    Ok(PreparedRequestHeaderHandoff {
        marker: format!("{MARKER_CONTENT_TYPE_PREFIX}{token}"),
        path,
    })
}

/// Removes the previous one-shot handoff still associated with a view.
///
/// A successfully dispatched request normally removes its own file from the
/// web process. Removing it again is harmless. Retaining only one path per view
/// also bounds disk usage when WebKit decides an identical navigation is a
/// no-op and consequently never emits `send-request`.
pub(super) fn discard_request_header_handoff(native_view: &NativeView) {
    let Some(path) = native_view
        .pending_request_header_handoff
        .borrow_mut()
        .take()
    else {
        return;
    };
    let _ = fs::remove_file(path);
}

fn marker_token(headers: *mut SoupMessageHeaders) -> Option<String> {
    if headers.is_null() {
        return None;
    }
    let content_type = unsafe { soup_message_headers_get_one(headers, c"Content-Type".as_ptr()) };
    let content_type = foreign_bytes(content_type);
    let token = content_type.strip_prefix(MARKER_CONTENT_TYPE_PREFIX.as_bytes())?;
    if token.len() != 16 || !token.iter().all(u8::is_ascii_hexdigit) {
        return None;
    }
    String::from_utf8(token.to_vec()).ok()
}

fn apply_request_headers(request: *mut WebKitURIRequest) {
    if request.is_null() {
        return;
    }
    let native_headers = unsafe { webkit_uri_request_get_http_headers(request) };
    let Some(token) = marker_token(native_headers) else {
        return;
    };
    let Ok(library) = current_library_path() else {
        return;
    };
    let Some(directory) = library.parent() else {
        return;
    };
    let path = handoff_path(directory, &token);
    let Ok(encoded) = fs::read(&path) else {
        return;
    };
    let Some(pending) = decode_handoff(&encoded) else {
        let _ = fs::remove_file(path);
        return;
    };
    let url = foreign_bytes(unsafe { webkit_uri_request_get_uri(request) });
    let method = foreign_bytes(unsafe { webkit_uri_request_get_http_method(request) });
    if !method.eq_ignore_ascii_case(b"POST") || pending.url != url {
        let _ = fs::remove_file(path);
        return;
    }
    let mut replaced_content_type = false;
    for (name, value) in pending.headers {
        replaced_content_type |= name.eq_ignore_ascii_case(b"Content-Type");
        let (Ok(name), Ok(value)) = (CString::new(name), CString::new(value)) else {
            let _ = fs::remove_file(path);
            return;
        };
        unsafe { soup_message_headers_replace(native_headers, name.as_ptr(), value.as_ptr()) };
    }
    if !replaced_content_type {
        unsafe { soup_message_headers_remove(native_headers, c"Content-Type".as_ptr()) };
    }
    let _ = fs::remove_file(path);
}

/// Maps Fetch Metadata's navigation destination to the federated frame flag.
///
/// WebKit adds this header in the web process after the UI-process navigation
/// action snapshot is created. Only navigation destinations are accepted;
/// images, scripts, media, and other subresources must never enter the policy
/// request queue.
fn frame_class_from_fetch_destination(destination: &[u8]) -> Option<bool> {
    if destination.eq_ignore_ascii_case(b"document") {
        Some(true)
    } else if destination.eq_ignore_ascii_case(b"iframe")
        || destination.eq_ignore_ascii_case(b"frame")
    {
        Some(false)
    } else {
        None
    }
}

struct FrameDecisionWait {
    main_loop: glib::MainLoop,
    completed: Rc<Cell<bool>>,
    allow: Rc<Cell<bool>>,
}

/// Strong page ownership retained by one isolated-world native function.
///
/// JavaScriptCore invokes the destroy notifier when its frame global is
/// cleared, releasing the page reference before the web process discards the
/// corresponding document.
struct FrameAnnouncementContext {
    page: glib::Object,
    is_main_frame: bool,
}

unsafe extern "C" fn destroy_frame_announcement_context(user_data: *mut c_void) {
    if !user_data.is_null() {
        drop(unsafe { Box::from_raw(user_data.cast::<FrameAnnouncementContext>()) });
    }
}

/// Copies one isolated-world navigation announcement to the owning view.
///
/// The callback signature follows the two GTypes passed to
/// `jsc_value_new_functionv`, followed by its opaque user data. The isolated
/// script distinguishes current-frame Navigation API events from child-frame
/// DOM observations. The former uses the authoritative `WebKitFrame` class
/// captured when its global object was created; the latter is always a
/// subordinate target regardless of the observing frame.
unsafe extern "C" fn announce_frame_navigation(
    targets_child: i32,
    url: *const c_char,
    user_data: *mut c_void,
) {
    if url.is_null() || user_data.is_null() {
        return;
    }
    let url = unsafe { CStr::from_ptr(url) }.to_bytes();
    if url.is_empty() || url.len() > 64 * 1024 {
        return;
    }
    let context = unsafe { &*user_data.cast::<FrameAnnouncementContext>() };
    let page = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&context.page)
        .0
        .cast::<WebKitWebPage>();
    if page.is_null() {
        return;
    }
    let Ok(url) = std::str::from_utf8(url) else {
        return;
    };
    let is_main_frame = targets_child == 0 && context.is_main_frame;
    let parameters = (url, is_main_frame).to_variant();
    let message = unsafe {
        webkit_user_message_new(
            FRAME_ANNOUNCEMENT_MESSAGE_NAME.as_ptr(),
            ToGlibPtr::<*mut glib::ffi::GVariant>::to_glib_none(&parameters).0,
        )
    };
    if message.is_null() {
        return;
    }
    // The newly created message is floating, so WebKit consumes it. No reply
    // is required for this best-effort hint sent before UI policy evaluation.
    unsafe {
        webkit_web_page_send_message_to_view(
            page,
            message,
            std::ptr::null_mut(),
            None,
            std::ptr::null_mut(),
        )
    };
}

/// Installs an isolated host script at global-object creation for every frame.
///
/// Unlike UI-process user scripts, web-process extension worlds continue to
/// run when `enable-javascript-markup` disables page-authored JavaScript. The
/// signal also supplies the exact `WebKitFrame`, while the injected observer
/// announces iframe destinations before the UI navigation-policy signal. This
/// fills the public WPE frame-information gap for schemes that never reach the
/// network or response policy gates.
fn install_extension_frame_bridge() {
    let world =
        unsafe { webkit_script_world_new_with_name(FRAME_ANNOUNCEMENT_WORLD_NAME.as_ptr()) };
    if world.is_null() {
        return;
    }
    let world_object: glib::Object = unsafe { from_glib_full(world.cast()) };
    let raw_world = world as usize;
    world_object.connect_local("window-object-cleared", false, move |values| {
        let page = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        }
        .cast::<WebKitWebPage>();
        let frame = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[2]).0,
            )
        }
        .cast::<WebKitFrame>();
        if page.is_null() || frame.is_null() {
            return None;
        }
        let context = unsafe {
            webkit_frame_get_js_context_for_script_world(frame, raw_world as *mut WebKitScriptWorld)
        };
        if context.is_null() {
            return None;
        }
        let context_object: glib::Object = unsafe { from_glib_full(context.cast()) };
        let context = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&context_object)
            .0
            .cast::<JSCContext>();
        let page: glib::Object = unsafe { from_glib_none(page.cast()) };
        let callback_context = Box::new(FrameAnnouncementContext {
            page,
            is_main_frame: unsafe { webkit_frame_is_main_frame(frame) != 0 },
        });
        let callback_context = Box::into_raw(callback_context).cast::<c_void>();
        let mut parameter_types = [
            glib::gobject_ffi::G_TYPE_BOOLEAN,
            glib::gobject_ffi::G_TYPE_STRING,
        ];
        let function = unsafe {
            jsc_value_new_functionv(
                context,
                FRAME_ANNOUNCEMENT_FUNCTION_NAME.as_ptr(),
                Some(announce_frame_navigation),
                callback_context,
                Some(destroy_frame_announcement_context),
                glib::gobject_ffi::G_TYPE_NONE,
                parameter_types.len() as u32,
                parameter_types.as_mut_ptr(),
            )
        };
        if function.is_null() {
            unsafe { destroy_frame_announcement_context(callback_context) };
            return None;
        }
        let function_object: glib::Object = unsafe { from_glib_full(function.cast()) };
        unsafe {
            jsc_context_set_value(
                context,
                FRAME_ANNOUNCEMENT_FUNCTION_NAME.as_ptr(),
                ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&function_object)
                    .0
                    .cast::<JSCValue>(),
            )
        };
        let source = CString::new(FRAME_ANNOUNCEMENT_SOURCE)
            .expect("frame announcement source cannot contain NUL");
        let result = unsafe { jsc_context_evaluate(context, source.as_ptr(), -1) };
        if !result.is_null() {
            let result: glib::Object = unsafe { from_glib_full(result.cast()) };
            drop(result);
        }
        None
    });
    // A web-process extension lives for the process lifetime. Retaining this
    // single world keeps its signal handler active for every subsequently
    // created page and frame; process exit reclaims the object and closure.
    std::mem::forget(world_object);
}

unsafe extern "C" fn frame_decision_finished(
    source: *mut glib::gobject_ffi::GObject,
    result: *mut GAsyncResult,
    user_data: *mut c_void,
) {
    let context = unsafe { Box::from_raw(user_data.cast::<FrameDecisionWait>()) };
    let mut error = std::ptr::null_mut();
    let reply = unsafe {
        webkit_web_page_send_message_to_view_finish(
            source.cast::<WebKitWebPage>(),
            result,
            &mut error,
        )
    };
    if !reply.is_null() {
        let reply: glib::Object = unsafe { from_glib_full(reply.cast()) };
        let reply_pointer = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&reply)
            .0
            .cast::<WebKitUserMessage>();
        if foreign_bytes(unsafe { webkit_user_message_get_name(reply_pointer) })
            == FRAME_DECISION_MESSAGE_NAME.to_bytes()
        {
            let parameters = unsafe { webkit_user_message_get_parameters(reply_pointer) };
            if !parameters.is_null() {
                let parameters: glib::Variant = unsafe { from_glib_none(parameters) };
                if let Some(allow) = parameters.get::<bool>() {
                    context.allow.set(allow);
                }
            }
        }
    }
    if !error.is_null() {
        unsafe { glib::ffi::g_error_free(error) };
    }
    context.completed.set(true);
    context.main_loop.quit();
}

/// Sends one finalized navigation destination to its owning UI-process view.
///
/// `WebKitWebPage::send-request` is the first public WPE hook where
/// `Sec-Fetch-Dest` is available. A page-scoped user message preserves WebView
/// ownership even when several views navigate to the same URL concurrently.
fn send_frame_hint(page: *mut WebKitWebPage, request: *mut WebKitURIRequest) -> Option<bool> {
    if page.is_null() || request.is_null() {
        return None;
    }
    let headers = unsafe { webkit_uri_request_get_http_headers(request) };
    if headers.is_null() {
        return None;
    }
    let destination =
        foreign_bytes(unsafe { soup_message_headers_get_one(headers, c"Sec-Fetch-Dest".as_ptr()) });
    let is_main_frame = frame_class_from_fetch_destination(&destination)?;
    let url = foreign_bytes(unsafe { webkit_uri_request_get_uri(request) });
    let Ok(url) = std::str::from_utf8(&url) else {
        return None;
    };
    if !claim_navigation_policy_gate(url.as_bytes()) {
        return None;
    }
    let parameters = (url, is_main_frame).to_variant();
    let message = unsafe {
        webkit_user_message_new(
            FRAME_HINT_MESSAGE_NAME.as_ptr(),
            ToGlibPtr::<*mut glib::ffi::GVariant>::to_glib_none(&parameters).0,
        )
    };
    if message.is_null() {
        return None;
    }
    let main_loop = glib::MainLoop::new(None, false);
    let completed = Rc::new(Cell::new(false));
    // Claiming a marker means Dart owns this decision. A missing, malformed,
    // or unhandled reply must therefore fail closed rather than bypassing an
    // application policy callback.
    let allow = Rc::new(Cell::new(false));
    let context = Box::new(FrameDecisionWait {
        main_loop: main_loop.clone(),
        completed: completed.clone(),
        allow: allow.clone(),
    });
    unsafe {
        webkit_web_page_send_message_to_view(
            page,
            message,
            std::ptr::null_mut(),
            Some(frame_decision_finished),
            Box::into_raw(context).cast(),
        )
    };
    if !completed.get() {
        main_loop.run();
    }
    Some(!allow.get())
}

/// Receives extension announcements and gated decisions on the owning view.
pub(super) fn connect_web_process_frame_hints(
    webview: &glib::Object,
    native_view: Weak<NativeView>,
) {
    webview.connect_local("user-message-received", false, move |values| {
        let message = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        }
        .cast::<WebKitUserMessage>();
        if message.is_null() {
            return Some(false.to_value());
        }
        let name = foreign_bytes(unsafe { webkit_user_message_get_name(message) });
        let parameters = unsafe { webkit_user_message_get_parameters(message) };
        if name == FRAME_ANNOUNCEMENT_MESSAGE_NAME.to_bytes() {
            if parameters.is_null() {
                return Some(true.to_value());
            }
            let parameters: glib::Variant = unsafe { from_glib_none(parameters) };
            let Some((url, is_main_frame)) = parameters.get::<(String, bool)>() else {
                return Some(true.to_value());
            };
            let Some(native_view) = native_view.upgrade() else {
                return Some(true.to_value());
            };
            let url = url.into_bytes();
            if !navigation::resolve_deferred_navigation_policy(&native_view, &url, is_main_frame) {
                navigation::enqueue_navigation_frame_hint(
                    &mut native_view.navigation_frame_hints.borrow_mut(),
                    NavigationFrameHint { url, is_main_frame },
                );
            }
            return Some(true.to_value());
        }
        if name != FRAME_HINT_MESSAGE_NAME.to_bytes() {
            return Some(false.to_value());
        }
        if parameters.is_null() {
            return Some(true.to_value());
        }
        let parameters: glib::Variant = unsafe { from_glib_none(parameters) };
        let Some((url, is_main_frame)) = parameters.get::<(String, bool)>() else {
            let message: glib::Object = unsafe { from_glib_none(message.cast()) };
            reply_web_process_navigation(&message, false);
            return Some(true.to_value());
        };
        let message: glib::Object = unsafe { from_glib_none(message.cast()) };
        let Some(native_view) = native_view.upgrade() else {
            reply_web_process_navigation(&message, false);
            return Some(true.to_value());
        };
        let url = url.into_bytes();
        let gated = navigation::take_web_process_policy_gate(&native_view, &url);
        if !gated {
            reply_web_process_navigation(&message, false);
            return Some(true.to_value());
        }
        native_view
            .navigation_policy_requests
            .borrow_mut()
            .push_back(NavigationPolicyRequestSnapshot {
                id: navigation::next_navigation_policy_request_id(&native_view),
                url,
                is_main_frame,
                backend: NavigationPolicyBackend::WebProcess(message),
            });
        Some(true.to_value())
    });
}

/// Entry point discovered by WPE after loading this library in a web process.
///
/// # Safety
///
/// WPE must pass a live, transfer-none `WebKitWebProcessExtension`. The pointer
/// and page/request signal values are borrowed only for their callback scope.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn webkit_web_process_extension_initialize(
    extension: *mut WebKitWebProcessExtension,
) {
    if extension.is_null() {
        return;
    }
    install_extension_frame_bridge();
    let extension: glib::Object = unsafe { from_glib_none(extension.cast()) };
    extension.connect_local("page-created", false, move |values| {
        let page_pointer = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        }
        .cast::<WebKitWebPage>();
        if page_pointer.is_null() {
            return None;
        }
        let page: glib::Object = unsafe { from_glib_none(page_pointer.cast()) };
        let raw_page = page_pointer as usize;
        page.connect_local("send-request", false, move |values| {
            let request = unsafe {
                glib::gobject_ffi::g_value_get_object(
                    ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
                )
            }
            .cast::<WebKitURIRequest>();
            let cancel = send_frame_hint(raw_page as *mut WebKitWebPage, request).unwrap_or(false);
            if cancel {
                return Some(true.to_value());
            }
            apply_request_headers(request);
            Some(false.to_value())
        });
        None
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn policy_gate_claims_only_the_oldest_exact_url_once() {
        let id = NEXT_HANDOFF_ID.fetch_add(3, Ordering::Relaxed).max(1);
        let directory = std::env::temp_dir().join(format!(
            "webview-flutter-linux-policy-gate-test-{}-{id}",
            std::process::id()
        ));
        fs::create_dir_all(&directory).expect("create policy-gate test directory");
        let unrelated = policy_gate_path(&directory, id);
        let first_match = policy_gate_path(&directory, id + 1);
        let second_match = policy_gate_path(&directory, id + 2);
        fs::write(&unrelated, b"https://example.test/unrelated").expect("write unrelated gate");
        fs::write(&first_match, b"https://example.test/frame").expect("write first gate");
        fs::write(&second_match, b"https://example.test/frame").expect("write second gate");

        assert!(claim_navigation_policy_gate_in(
            &directory,
            b"https://example.test/frame"
        ));
        assert!(unrelated.exists());
        assert!(!first_match.exists());
        assert!(second_match.exists());
        assert!(claim_navigation_policy_gate_in(
            &directory,
            b"https://example.test/frame"
        ));
        assert!(!claim_navigation_policy_gate_in(
            &directory,
            b"https://example.test/frame"
        ));

        fs::remove_dir_all(directory).expect("remove policy-gate test directory");
    }

    #[test]
    fn handoff_round_trip_preserves_binary_safe_utf8_headers() {
        let headers = vec![
            (
                "Content-Type".to_string(),
                "application/octet-stream".to_string(),
            ),
            ("X-Ünicode".to_string(), "välue".to_string()),
        ];
        let encoded = encode_handoff("https://example.com/post", &headers).unwrap();

        assert_eq!(
            decode_handoff(&encoded),
            Some(PendingRequestHeaders {
                url: b"https://example.com/post".to_vec(),
                headers: headers
                    .into_iter()
                    .map(|(name, value)| (name.into_bytes(), value.into_bytes()))
                    .collect(),
            }),
        );
    }

    #[test]
    fn handoff_decoder_rejects_truncation_and_trailing_data() {
        let encoded = encode_handoff(
            "https://example.com/post",
            &[("X-Probe".to_string(), "present".to_string())],
        )
        .unwrap();
        assert_eq!(decode_handoff(&encoded[..encoded.len() - 1]), None);

        let mut trailing = encoded;
        trailing.push(0);
        assert_eq!(decode_handoff(&trailing), None);
    }

    #[test]
    fn accepts_only_navigation_fetch_destinations_as_frame_evidence() {
        assert_eq!(frame_class_from_fetch_destination(b"document"), Some(true));
        assert_eq!(frame_class_from_fetch_destination(b"iframe"), Some(false));
        assert_eq!(frame_class_from_fetch_destination(b"frame"), Some(false));
        assert_eq!(frame_class_from_fetch_destination(b"DOCUMENT"), Some(true));
        assert_eq!(frame_class_from_fetch_destination(b"image"), None);
        assert_eq!(frame_class_from_fetch_destination(b""), None);
    }
}
