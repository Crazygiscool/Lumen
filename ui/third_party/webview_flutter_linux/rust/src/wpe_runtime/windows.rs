// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Related-window ownership and fullscreen presentation.
//!
//! Popup children are real related WebKit views with independent Flutter
//! textures. This module keeps each child opener-owned until Dart takes it and
//! translates headless fullscreen transitions into a bounded event queue.

use super::prelude::*;

pub(super) const MAX_POPUP_REQUESTS: usize = 32;
pub(super) const MAX_FULLSCREEN_EVENTS: usize = 16;

/// A related WebView that is ready for Flutter to present as a new window.
///
/// The child already has its own registry handle and Irondash texture. Until
/// Dart calls the popup `take` ABI, that handle remains in the opener's
/// `owned_popup_handles` set so disposing the opener also disposes every
/// undelivered child. The URL is copied from the navigation action because the
/// borrowed `WebKitNavigationAction` does not outlive the `create` signal.
pub(super) struct PopupRequestSnapshot {
    pub(super) child_handle: u64,
    pub(super) url: Vec<u8>,
}

/// Copies the requested URI from a callback-scoped navigation action.
fn popup_action_url(action: *mut WebKitNavigationAction) -> Vec<u8> {
    if action.is_null() {
        return Vec::new();
    }
    let request = unsafe { webkit_navigation_action_get_request(action) };
    if request.is_null() {
        return Vec::new();
    }
    foreign_bytes(unsafe { webkit_uri_request_get_uri(request) })
}

/// Makes a child available to Dart at most once while it remains opener-owned.
fn enqueue_popup_request(opener: &NativeView, child_handle: u64, url: &[u8]) {
    let owned_handles = opener.owned_popup_handles.borrow();
    let mut requests = opener.popup_requests.borrow_mut();
    enqueue_popup_snapshot(&owned_handles, &mut requests, child_handle, url);
}

/// Enqueues one popup snapshot when ownership and queue bounds permit it.
///
/// This state-only helper keeps the exactly-once and bounded-queue rules
/// directly unit-testable without constructing a WPE display or Flutter engine.
pub(super) fn enqueue_popup_snapshot(
    owned_handles: &HashSet<u64>,
    requests: &mut VecDeque<PopupRequestSnapshot>,
    child_handle: u64,
    url: &[u8],
) -> bool {
    if !owned_handles.contains(&child_handle)
        || requests
            .iter()
            .any(|request| request.child_handle == child_handle)
    {
        return false;
    }
    // The same cap guards child construction, but retain a defensive queue
    // bound in case lifecycle callbacks are reordered by a future WebKit.
    if requests.len() >= MAX_POPUP_REQUESTS {
        return false;
    }
    requests.push_back(PopupRequestSnapshot {
        child_handle,
        url: url.to_vec(),
    });
    true
}

/// Connects the lifecycle signals that transfer a related view to Flutter.
///
/// `ready-to-show` is the normal delivery point required by WebKit. A close
/// request before readiness also delivers the child so Dart can observe the
/// close and release it rather than leaving it opener-owned until teardown.
fn connect_popup_lifecycle(
    webview: &glib::Object,
    opener: Weak<NativeView>,
    child: Weak<NativeView>,
    child_handle: u64,
    url: Vec<u8>,
) {
    let ready_opener = opener.clone();
    let ready_url = url.clone();
    webview.connect_local("ready-to-show", false, move |_| {
        if let Some(opener) = ready_opener.upgrade() {
            enqueue_popup_request(&opener, child_handle, &ready_url);
        }
        None
    });

    webview.connect_local("close", false, move |_| {
        if let Some(child) = child.upgrade() {
            child.close_requested.store(true, Ordering::Release);
        }
        if let Some(opener) = opener.upgrade() {
            enqueue_popup_request(&opener, child_handle, &url);
        }
        None
    });
}

/// Creates and registers one WebKit-related child during an opener's `create`
/// signal, returning the browser object that WebKit will navigate.
///
/// Texture registration and WPE construction complete before the handle enters
/// the registry. The opener owns the new handle until Dart takes the queued
/// request; that rule makes ignored popups deterministic and prevents native
/// resources from escaping when an opener is disposed.
fn create_related_webview(
    opener: Rc<NativeView>,
    opener_webview: *mut WebKitWebView,
    action: *mut WebKitNavigationAction,
) -> Option<glib::Object> {
    if opener_webview.is_null() || opener.owned_popup_handles.borrow().len() >= MAX_POPUP_REQUESTS {
        return None;
    }
    let child = new_native_view(opener.engine_handle).ok()?;
    // WebKitSettings are cloned by build_webview, but the geolocation gate is
    // owned by this embedding layer because WPE exposes geolocation as a
    // permission request rather than a WebKitSettings property.
    child
        .geolocation_enabled
        .set(opener.geolocation_enabled.get());
    let BuiltWebView {
        webview,
        network_session,
        download_started_handler_id,
        input_method_context,
        user_content_manager,
        view,
        toplevel,
    } = build_webview(
        Rc::downgrade(&child),
        true,
        true,
        false,
        None,
        opener_webview,
    )
    .ok()?;
    let child_webview = webview.clone();
    child.runtime.replace(Some(WpeRuntime {
        webview,
        network_session,
        download_started_handler_id: Some(download_started_handler_id),
        input_method_context,
        user_content_manager,
        javascript_channels: HashMap::new(),
        presentation_style_sheet: std::ptr::null_mut(),
        view,
        toplevel,
    }));
    register_cursor_view(view, &child);

    let handle = next_handle();
    VIEWS.with_borrow_mut(|views| {
        views.insert(handle, child.clone());
    });
    opener.owned_popup_handles.borrow_mut().insert(handle);
    connect_popup_lifecycle(
        &child_webview,
        Rc::downgrade(&opener),
        Rc::downgrade(&child),
        handle,
        popup_action_url(action),
    );
    Some(child_webview)
}

/// Handles `target=_blank` and `window.open` with a real related WebView.
pub(super) fn connect_popup_creation(webview: &glib::Object, opener: Weak<NativeView>) {
    let opener_webview =
        ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(webview).0 as usize;
    webview.connect_local("create", false, move |values| {
        let Some(opener) = opener.upgrade() else {
            return Some(Option::<glib::Object>::None.to_value());
        };
        let action = unsafe {
            glib::gobject_ffi::g_value_get_boxed(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        }
        .cast::<WebKitNavigationAction>();
        let child = create_related_webview(opener, opener_webview as *mut WebKitWebView, action);
        Some(child.to_value())
    });
}

/// Publishes an effective HTML fullscreen transition exactly once.
pub(super) fn enqueue_fullscreen_event(native_view: &NativeView, fullscreen: bool) {
    if native_view.fullscreen.swap(fullscreen, Ordering::AcqRel) == fullscreen {
        return;
    }
    enqueue_fullscreen_snapshot(&mut native_view.fullscreen_events.borrow_mut(), fullscreen);
}

/// Appends one effective fullscreen state while bounding unconsumed changes.
pub(super) fn enqueue_fullscreen_snapshot(events: &mut VecDeque<bool>, fullscreen: bool) {
    if events.back().copied() == Some(fullscreen) {
        return;
    }
    if events.len() >= MAX_FULLSCREEN_EVENTS {
        events.pop_front();
    }
    events.push_back(fullscreen);
}

/// Claims WPE's fullscreen lifecycle for Flutter's texture presentation.
///
/// Returning true prevents the headless WPE toplevel from attempting a native
/// window transition. Dart moves the existing texture into a root Flutter
/// overlay, so the browser object, playback state, focus, and input bridge all
/// remain continuous across enter and leave transitions.
pub(super) fn connect_fullscreen_events(webview: &glib::Object, native_view: Weak<NativeView>) {
    let enter_view = native_view.clone();
    webview.connect_local("enter-fullscreen", false, move |_| {
        if let Some(native_view) = enter_view.upgrade() {
            enqueue_fullscreen_event(&native_view, true);
        }
        Some(true.to_value())
    });
    webview.connect_local("leave-fullscreen", false, move |_| {
        if let Some(native_view) = native_view.upgrade() {
            enqueue_fullscreen_event(&native_view, false);
        }
        Some(true.to_value())
    });
}

/// Applies an operation to the oldest related view awaiting Dart ownership.
fn with_popup_request<T: Copy>(
    handle: u64,
    fallback: T,
    operation: impl FnOnce(&PopupRequestSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    native_view
        .popup_requests
        .borrow()
        .front()
        .map_or(fallback, operation)
}

#[unsafe(no_mangle)]
/// Returns the number of popup children ready for Flutter presentation.
pub extern "C" fn webview_flutter_linux_wpe_popup_request_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.popup_requests.borrow().len().min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Returns the child registry handle of the oldest popup request.
pub extern "C" fn webview_flutter_linux_wpe_popup_request_child_handle(handle: u64) -> u64 {
    with_popup_request(handle, 0, |request| request.child_handle)
}

#[unsafe(no_mangle)]
/// Returns the requested popup URI's UTF-8 byte length.
pub extern "C" fn webview_flutter_linux_wpe_popup_request_url_length(handle: u64) -> usize {
    with_popup_request(handle, 0, |request| request.url.len())
}

#[unsafe(no_mangle)]
/// Copies the oldest popup request URI into caller-owned storage.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes. Empty URLs
/// are valid, but the pointer must still be non-null to keep the ABI contract
/// uniform for Dart allocation code.
pub unsafe extern "C" fn webview_flutter_linux_wpe_popup_request_copy_url(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    with_popup_request(handle, -1, |request| {
        if destination.is_null()
            || destination_length < request.url.len()
            || request.url.len() > i32::MAX as usize
        {
            return -2;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(request.url.as_ptr(), destination, request.url.len())
        };
        request.url.len() as i32
    })
}

#[unsafe(no_mangle)]
/// Transfers the oldest popup child from its opener to Dart.
///
/// The request remains untouched unless its handle is still registered and
/// opener-owned. This prevents a consumer from receiving a stale handle and
/// ensures opener disposal no longer affects a successfully transferred child.
pub extern "C" fn webview_flutter_linux_wpe_popup_request_take(handle: u64) -> i32 {
    let Some(opener) = native_view(handle) else {
        return -1;
    };
    let child_handle = match opener.popup_requests.borrow().front() {
        Some(request) => request.child_handle,
        None => return 1,
    };
    if native_view(child_handle).is_none()
        || !opener
            .owned_popup_handles
            .borrow_mut()
            .remove(&child_handle)
    {
        return -2;
    }
    opener.popup_requests.borrow_mut().pop_front();
    0
}

#[unsafe(no_mangle)]
/// Atomically consumes a child view's pending JavaScript `window.close` signal.
///
/// Returns one when a close was pending, zero when no close was pending, and
/// `-1` for an invalid handle.
pub extern "C" fn webview_flutter_linux_wpe_close_requested_take(handle: u64) -> i32 {
    native_view(handle).map_or(-1, |view| {
        i32::from(view.close_requested.swap(false, Ordering::AcqRel))
    })
}

#[unsafe(no_mangle)]
/// Returns the number of pending HTML fullscreen transitions.
pub extern "C" fn webview_flutter_linux_wpe_fullscreen_event_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.fullscreen_events.borrow().len().min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Returns one for the oldest enter transition and zero for leave.
///
/// Invalid handles and empty queues also return zero; callers distinguish them
/// by reading the event count first.
pub extern "C" fn webview_flutter_linux_wpe_fullscreen_event_value(handle: u64) -> i32 {
    native_view(handle).map_or(0, |view| {
        view.fullscreen_events
            .borrow()
            .front()
            .copied()
            .map_or(0, i32::from)
    })
}

#[unsafe(no_mangle)]
/// Removes the oldest HTML fullscreen transition after Dart reads it.
pub extern "C" fn webview_flutter_linux_wpe_fullscreen_event_pop(handle: u64) -> i32 {
    let Some(view) = native_view(handle) else {
        return -1;
    };
    if view.fullscreen_events.borrow_mut().pop_front().is_some() {
        0
    } else {
        1
    }
}
