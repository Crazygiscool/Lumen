// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! WebKit download ownership, destination requests, and lifecycle events.
//!
//! A download remains retained from download-started until finished while Dart
//! asynchronously chooses its destination. This module keeps that native
//! lifetime together with bounded progress queues and the exactly-once ABI.

use super::prelude::*;

/// A native download paused while Flutter chooses its destination.
///
/// The `WebKitDownload` itself is owned by [`NativeView::active_downloads`]
/// from `download-started` through `finished`. This snapshot therefore copies
/// only callback-scoped response metadata and the stable per-view identifier.
pub(super) struct DownloadRequestSnapshot {
    id: u64,
    uri: Vec<u8>,
    suggested_filename: Vec<u8>,
    mime_type: Vec<u8>,
    content_length: i64,
}

/// One observable transition from a WebKit download.
///
/// Progress entries are coalesced per download between Flutter pump ticks.
/// Created, failed, and finished transitions remain ordered and are never
/// replaced by later progress notifications.
pub(super) struct DownloadEventSnapshot {
    pub(super) id: u64,
    pub(super) kind: u32,
    pub(super) received_bytes: u64,
    pub(super) content_length: i64,
    pub(super) error_code: i32,
    pub(super) destination: Vec<u8>,
    pub(super) detail: Vec<u8>,
}

/// Appends a download transition while bounding high-frequency progress data.
///
/// Only adjacent progress updates for the same download are coalesced. When
/// the queue reaches its cap, an older progress entry is discarded before a
/// structural event so created/failed/finished transitions are preserved for
/// as long as possible.
pub(super) fn enqueue_download_event(
    events: &mut VecDeque<DownloadEventSnapshot>,
    event: DownloadEventSnapshot,
) {
    if event.kind == DOWNLOAD_EVENT_PROGRESS
        && let Some(previous) = events.back_mut()
        && previous.kind == DOWNLOAD_EVENT_PROGRESS
        && previous.id == event.id
    {
        *previous = event;
        return;
    }
    if events.len() == MAX_DOWNLOAD_EVENTS {
        if let Some(index) = events
            .iter()
            .position(|candidate| candidate.kind == DOWNLOAD_EVENT_PROGRESS)
        {
            events.remove(index);
        } else {
            events.pop_front();
        }
    }
    events.push_back(event);
}

/// Returns the response size, or `-1` while WebKit has no response/size.
fn download_content_length(download: *mut WebKitDownload) -> i64 {
    if download.is_null() {
        return -1;
    }
    let response = unsafe { webkit_download_get_response(download) };
    if response.is_null() {
        -1
    } else {
        unsafe { webkit_uri_response_get_content_length(response) }
    }
}

/// Copies the current destination of a live download, if one was selected.
fn download_destination(download: *mut WebKitDownload) -> Vec<u8> {
    if download.is_null() {
        return Vec::new();
    }
    foreign_bytes(unsafe { webkit_download_get_destination(download) })
}

/// Attaches lifecycle signals to a download belonging to one native view.
///
/// WebKit pauses after `decide-destination` because the callback returns true.
/// Dart must later call the resolve ABI with either an absolute path or null to
/// cancel. Signal closures capture only the numeric ID and a weak owner; the
/// strong download reference lives in `active_downloads` until `finished`.
fn connect_download_signals(download: &glib::Object, id: u64, native_view: Weak<NativeView>) {
    let decide_view = native_view.clone();
    download.connect_local("decide-destination", false, move |values| {
        let Some(native_view) = decide_view.upgrade() else {
            return Some(true.to_value());
        };
        let raw_download = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[0]).0,
            )
        }
        .cast::<WebKitDownload>();
        if raw_download.is_null() {
            return Some(true.to_value());
        }
        let suggested_filename = unsafe {
            glib::gobject_ffi::g_value_get_string(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        };
        let request = unsafe { webkit_download_get_request(raw_download) };
        let response = unsafe { webkit_download_get_response(raw_download) };
        let mut requests = native_view.download_requests.borrow_mut();
        if requests.len() == MAX_DOWNLOAD_REQUESTS {
            drop(requests);
            unsafe { webkit_download_cancel(raw_download) };
            return Some(true.to_value());
        }
        requests.push_back(DownloadRequestSnapshot {
            id,
            uri: if request.is_null() {
                Vec::new()
            } else {
                foreign_bytes(unsafe { webkit_uri_request_get_uri(request) })
            },
            suggested_filename: foreign_bytes(suggested_filename),
            mime_type: if response.is_null() {
                Vec::new()
            } else {
                foreign_bytes(unsafe { webkit_uri_response_get_mime_type(response) })
            },
            content_length: download_content_length(raw_download),
        });
        Some(true.to_value())
    });

    let created_view = native_view.clone();
    download.connect_local("created-destination", false, move |values| {
        let native_view = created_view.upgrade()?;
        let destination = unsafe {
            glib::gobject_ffi::g_value_get_string(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        };
        let raw_download = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[0]).0,
            )
        }
        .cast::<WebKitDownload>();
        enqueue_download_event(
            &mut native_view.download_events.borrow_mut(),
            DownloadEventSnapshot {
                id,
                kind: DOWNLOAD_EVENT_CREATED_DESTINATION,
                received_bytes: 0,
                content_length: download_content_length(raw_download),
                error_code: 0,
                destination: foreign_bytes(destination),
                detail: Vec::new(),
            },
        );
        None
    });

    let progress_view = native_view.clone();
    download.connect_local("received-data", false, move |values| {
        let native_view = progress_view.upgrade()?;
        let raw_download = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[0]).0,
            )
        }
        .cast::<WebKitDownload>();
        if raw_download.is_null() {
            return None;
        }
        enqueue_download_event(
            &mut native_view.download_events.borrow_mut(),
            DownloadEventSnapshot {
                id,
                kind: DOWNLOAD_EVENT_PROGRESS,
                received_bytes: unsafe { webkit_download_get_received_data_length(raw_download) },
                content_length: download_content_length(raw_download),
                error_code: 0,
                destination: download_destination(raw_download),
                detail: Vec::new(),
            },
        );
        None
    });

    let failed_view = native_view.clone();
    download.connect_local("failed", false, move |values| {
        let native_view = failed_view.upgrade()?;
        let raw_download = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[0]).0,
            )
        }
        .cast::<WebKitDownload>();
        let error = unsafe {
            glib::gobject_ffi::g_value_get_boxed(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        }
        .cast::<glib::ffi::GError>();
        let (error_code, detail) = if error.is_null() {
            (-1, b"WebKit download failed".to_vec())
        } else {
            (
                unsafe { (*error).code },
                foreign_bytes(unsafe { (*error).message }),
            )
        };
        enqueue_download_event(
            &mut native_view.download_events.borrow_mut(),
            DownloadEventSnapshot {
                id,
                kind: DOWNLOAD_EVENT_FAILED,
                received_bytes: if raw_download.is_null() {
                    0
                } else {
                    unsafe { webkit_download_get_received_data_length(raw_download) }
                },
                content_length: if raw_download.is_null() {
                    -1
                } else {
                    download_content_length(raw_download)
                },
                error_code,
                destination: if raw_download.is_null() {
                    Vec::new()
                } else {
                    download_destination(raw_download)
                },
                detail,
            },
        );
        None
    });

    download.connect_local("finished", false, move |values| {
        let native_view = native_view.upgrade()?;
        let raw_download = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[0]).0,
            )
        }
        .cast::<WebKitDownload>();
        enqueue_download_event(
            &mut native_view.download_events.borrow_mut(),
            DownloadEventSnapshot {
                id,
                kind: DOWNLOAD_EVENT_FINISHED,
                received_bytes: if raw_download.is_null() {
                    0
                } else {
                    unsafe { webkit_download_get_received_data_length(raw_download) }
                },
                content_length: if raw_download.is_null() {
                    -1
                } else {
                    download_content_length(raw_download)
                },
                error_code: 0,
                destination: if raw_download.is_null() {
                    Vec::new()
                } else {
                    download_destination(raw_download)
                },
                detail: Vec::new(),
            },
        );
        native_view
            .download_requests
            .borrow_mut()
            .retain(|request| request.id != id);
        native_view
            .pending_download_request_ids
            .borrow_mut()
            .remove(&id);
        native_view.active_downloads.borrow_mut().remove(&id);
        None
    });
}

/// Watches the shared network session and claims downloads created by a view.
///
/// Every WebView uses the application-scoped session so downloads inherit the page's
/// cookies, authentication, proxy, and TLS state. Each view installs a filtered
/// session handler and disconnects it from [`WpeRuntime::drop`].
pub(super) fn connect_downloads(
    network_session: *mut WebKitNetworkSession,
    webview: &glib::Object,
    native_view: Weak<NativeView>,
) -> (glib::Object, glib::SignalHandlerId) {
    let session: glib::Object = unsafe { from_glib_none(network_session.cast()) };
    let webview_identity =
        ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(webview).0 as usize;
    let handler_id = session.connect_local("download-started", false, move |values| {
        let raw_download = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        }
        .cast::<WebKitDownload>();
        if raw_download.is_null()
            || unsafe { webkit_download_get_web_view(raw_download) } as usize != webview_identity
        {
            return None;
        }
        let Some(native_view) = native_view.upgrade() else {
            unsafe { webkit_download_cancel(raw_download) };
            return None;
        };
        let id = {
            let mut next = native_view.next_download_id.borrow_mut();
            let id = (*next).max(1);
            *next = id.wrapping_add(1).max(1);
            id
        };
        let download: glib::Object = unsafe { from_glib_none(raw_download.cast()) };
        connect_download_signals(&download, id, Rc::downgrade(&native_view));
        native_view
            .active_downloads
            .borrow_mut()
            .insert(id, download);
        None
    });
    (session, handler_id)
}

/// Applies an operation to the oldest download awaiting a Flutter destination.
fn with_download_request<T: Copy>(
    handle: u64,
    fallback: T,
    operation: impl FnOnce(&DownloadRequestSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    native_view
        .download_requests
        .borrow()
        .front()
        .map_or(fallback, operation)
}

#[unsafe(no_mangle)]
/// Returns the number of downloads paused for a Flutter destination.
pub extern "C" fn webview_flutter_linux_wpe_download_request_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.download_requests.borrow().len().min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Returns the stable ID of the oldest paused download.
pub extern "C" fn webview_flutter_linux_wpe_download_request_id(handle: u64) -> u64 {
    with_download_request(handle, 0, |request| request.id)
}

#[unsafe(no_mangle)]
/// Returns the response content length, or `-1` when it is unknown.
pub extern "C" fn webview_flutter_linux_wpe_download_request_content_length(handle: u64) -> i64 {
    with_download_request(handle, -1, |request| request.content_length)
}

fn download_request_field(request: &DownloadRequestSnapshot, field: u32) -> Option<&[u8]> {
    match field {
        0 => Some(&request.uri),
        1 => Some(&request.suggested_filename),
        2 => Some(&request.mime_type),
        _ => None,
    }
}

#[unsafe(no_mangle)]
/// Returns a queued download URI, filename, or MIME field length.
pub extern "C" fn webview_flutter_linux_wpe_download_request_field_length(
    handle: u64,
    field: u32,
) -> usize {
    with_download_request(handle, 0, |request| {
        download_request_field(request, field).map_or(0, <[u8]>::len)
    })
}

#[unsafe(no_mangle)]
/// Copies a queued download URI, filename, or MIME field.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes.
pub unsafe extern "C" fn webview_flutter_linux_wpe_download_request_copy_field(
    handle: u64,
    field: u32,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    with_download_request(handle, -1, |request| {
        let Some(bytes) = download_request_field(request, field) else {
            return -2;
        };
        if destination.is_null()
            || destination_length < bytes.len()
            || bytes.len() > i32::MAX as usize
        {
            return -3;
        }
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), destination, bytes.len()) };
        bytes.len() as i32
    })
}

#[unsafe(no_mangle)]
/// Moves the oldest paused download into the exactly-once resolution set.
pub extern "C" fn webview_flutter_linux_wpe_download_request_take(handle: u64) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let Some(request) = native_view.download_requests.borrow_mut().pop_front() else {
        return 1;
    };
    native_view
        .pending_download_request_ids
        .borrow_mut()
        .insert(request.id);
    0
}

#[unsafe(no_mangle)]
/// Sets a destination for, or cancels, one delivered download request.
///
/// A null destination cancels. A non-null destination must be non-empty UTF-8;
/// Dart validates that it is an absolute filesystem path before this call.
/// Invalid input leaves the request pending so callers can still cancel it.
///
/// # Safety
///
/// A non-null `destination` must address a readable NUL-terminated byte string
/// for the duration of this call.
pub unsafe extern "C" fn webview_flutter_linux_wpe_download_request_resolve(
    handle: u64,
    request_id: u64,
    destination: *const c_char,
    allow_overwrite: i32,
) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    if !native_view
        .pending_download_request_ids
        .borrow()
        .contains(&request_id)
    {
        return -2;
    }
    let owned_destination = if destination.is_null() {
        None
    } else {
        let value = match required_c_string(destination) {
            Ok(value) if !value.is_empty() => value,
            _ => return -3,
        };
        match std::ffi::CString::new(value) {
            Ok(value) => Some(value),
            Err(_) => return -3,
        }
    };
    let Some(download) = native_view
        .active_downloads
        .borrow()
        .get(&request_id)
        .cloned()
    else {
        return -4;
    };
    native_view
        .pending_download_request_ids
        .borrow_mut()
        .remove(&request_id);
    let download = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&download)
        .0
        .cast::<WebKitDownload>();
    if let Some(destination) = owned_destination {
        unsafe {
            webkit_download_set_allow_overwrite(download, i32::from(allow_overwrite != 0));
            webkit_download_set_destination(download, destination.as_ptr());
        }
    } else {
        unsafe { webkit_download_cancel(download) };
    }
    0
}

/// Applies an operation to the oldest queued download transition.
fn with_download_event<T: Copy>(
    handle: u64,
    fallback: T,
    operation: impl FnOnce(&DownloadEventSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    native_view
        .download_events
        .borrow()
        .front()
        .map_or(fallback, operation)
}

#[unsafe(no_mangle)]
/// Returns the number of queued download lifecycle transitions.
pub extern "C" fn webview_flutter_linux_wpe_download_event_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.download_events.borrow().len().min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Returns the download ID associated with the oldest transition.
pub extern "C" fn webview_flutter_linux_wpe_download_event_id(handle: u64) -> u64 {
    with_download_event(handle, 0, |event| event.id)
}

#[unsafe(no_mangle)]
/// Returns the stable kind of the oldest download transition.
pub extern "C" fn webview_flutter_linux_wpe_download_event_kind(handle: u64) -> u32 {
    with_download_event(handle, 0, |event| event.kind)
}

#[unsafe(no_mangle)]
/// Returns total bytes received for the oldest download transition.
pub extern "C" fn webview_flutter_linux_wpe_download_event_received_bytes(handle: u64) -> u64 {
    with_download_event(handle, 0, |event| event.received_bytes)
}

#[unsafe(no_mangle)]
/// Returns expected total bytes, or `-1` when the server omitted a size.
pub extern "C" fn webview_flutter_linux_wpe_download_event_content_length(handle: u64) -> i64 {
    with_download_event(handle, -1, |event| event.content_length)
}

#[unsafe(no_mangle)]
/// Returns WebKit's error code for a failed download transition.
pub extern "C" fn webview_flutter_linux_wpe_download_event_error_code(handle: u64) -> i32 {
    with_download_event(handle, 0, |event| event.error_code)
}

fn download_event_field(event: &DownloadEventSnapshot, field: u32) -> Option<&[u8]> {
    match field {
        0 => Some(&event.destination),
        1 => Some(&event.detail),
        _ => None,
    }
}

#[unsafe(no_mangle)]
/// Returns a download transition's destination or detail field length.
pub extern "C" fn webview_flutter_linux_wpe_download_event_field_length(
    handle: u64,
    field: u32,
) -> usize {
    with_download_event(handle, 0, |event| {
        download_event_field(event, field).map_or(0, <[u8]>::len)
    })
}

#[unsafe(no_mangle)]
/// Copies a download transition's destination or detail field.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes.
pub unsafe extern "C" fn webview_flutter_linux_wpe_download_event_copy_field(
    handle: u64,
    field: u32,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    with_download_event(handle, -1, |event| {
        let Some(bytes) = download_event_field(event, field) else {
            return -2;
        };
        if destination.is_null()
            || destination_length < bytes.len()
            || bytes.len() > i32::MAX as usize
        {
            return -3;
        }
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), destination, bytes.len()) };
        bytes.len() as i32
    })
}

#[unsafe(no_mangle)]
/// Removes the oldest download transition after Dart copies it.
pub extern "C" fn webview_flutter_linux_wpe_download_event_pop(handle: u64) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    i32::from(
        native_view
            .download_events
            .borrow_mut()
            .pop_front()
            .is_none(),
    )
}
