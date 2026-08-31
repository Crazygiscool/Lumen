// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Public view creation/disposal ABI and exactly-once teardown policy.

use super::{prelude::*, settings::current_scroll_lifecycle_settle_delay_micros};

/// Resolves or releases browser-process-owned requests that cannot survive a
/// process exit.
///
/// A `WebKitWebView` remains reusable after `web-process-terminated`, but
/// policy decisions, dialogs, file choosers, permission prompts,
/// authentication challenges, TLS failures, and context-menu actions belong to
/// the exited content process. Retaining them would let a later Dart callback
/// address stale native objects after WebKit has launched a replacement
/// process. This helper is shared by crash handling and ordinary view disposal
/// so both teardown paths apply the same exactly-once defaults.
pub(super) fn cancel_process_bound_requests(
    native_view: &NativeView,
    report_notification_closures: bool,
) {
    cancel_notifications(native_view, report_notification_closures);
    native_view.context_menu.take();
    if let Some(menu) = native_view.option_menu.take() {
        let menu = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&menu.menu)
            .0
            .cast::<WebKitOptionMenu>();
        unsafe { webkit_option_menu_close(menu) };
    }
    for request in native_view
        .navigation_policy_requests
        .borrow_mut()
        .drain(..)
    {
        cancel_navigation_policy_backend(&request.backend);
    }
    for (_, backend) in native_view.pending_policy_decisions.borrow_mut().drain() {
        cancel_navigation_policy_backend(&backend);
    }
    for policy in native_view
        .deferred_navigation_policies
        .borrow_mut()
        .drain(..)
    {
        cancel_navigation_policy_backend(&policy.backend);
    }
    for gate in native_view.web_process_policy_gates.borrow_mut().drain(..) {
        discard_navigation_policy_gate(&gate);
    }
    native_view.response_policy_gates.borrow_mut().clear();
    // Dropping retained dialog snapshots closes and unreferences them.
    native_view.script_dialog_requests.borrow_mut().clear();
    native_view.pending_script_dialogs.borrow_mut().clear();
    for request in native_view.permission_requests.borrow_mut().drain(..) {
        let request = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&request.request)
            .0
            .cast::<WebKitPermissionRequest>();
        unsafe { webkit_permission_request_deny(request) };
    }
    for (_, request) in native_view.pending_permission_requests.borrow_mut().drain() {
        let request = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&request.request)
            .0
            .cast::<WebKitPermissionRequest>();
        unsafe { webkit_permission_request_deny(request) };
    }
    for request in native_view.http_auth_requests.borrow_mut().drain(..) {
        let request = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&request.request)
            .0
            .cast::<WebKitAuthenticationRequest>();
        unsafe { webkit_authentication_request_cancel(request) };
    }
    for (_, request) in native_view.pending_http_auth_requests.borrow_mut().drain() {
        let request = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&request)
            .0
            .cast::<WebKitAuthenticationRequest>();
        unsafe { webkit_authentication_request_cancel(request) };
    }
    // TLS failures have already stopped their loads; dropping their retained
    // certificate snapshots is the complete cancellation operation.
    native_view.ssl_auth_errors.borrow_mut().clear();
    native_view.pending_ssl_auth_errors.borrow_mut().clear();
    for request in native_view.file_chooser_requests.borrow_mut().drain(..) {
        let request = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&request.request)
            .0
            .cast::<WebKitFileChooserRequest>();
        unsafe { webkit_file_chooser_request_cancel(request) };
    }
    for (_, request) in native_view
        .pending_file_chooser_requests
        .borrow_mut()
        .drain()
    {
        let request = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&request)
            .0
            .cast::<WebKitFileChooserRequest>();
        unsafe { webkit_file_chooser_request_cancel(request) };
    }
}

/// Cancels network-process downloads owned by a view during final disposal.
///
/// Downloads deliberately survive a WebContent process crash, matching normal
/// browser behavior. They are cancelled only when the Flutter view itself is
/// disposed and no longer has a destination or progress observer.
fn cancel_view_downloads(native_view: &NativeView) {
    native_view.download_requests.borrow_mut().clear();
    native_view
        .pending_download_request_ids
        .borrow_mut()
        .clear();
    let active_downloads = mem::take(&mut *native_view.active_downloads.borrow_mut());
    for (_, download) in active_downloads {
        let download = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&download)
            .0
            .cast::<WebKitDownload>();
        unsafe { webkit_download_cancel(download) };
    }
    native_view.download_events.borrow_mut().clear();
}

#[unsafe(no_mangle)]
/// Creates one independently owned browser and Flutter texture.
///
/// Creation is transactional: the handle is inserted only after texture
/// registration, WPE construction, signal connection, and initial navigation
/// all succeed. On success `output_handle` receives a non-zero identifier and
/// the function returns `0`. Negative values report invalid pointers/strings or
/// the propagated texture/WPE construction failure.
///
/// # Safety
///
/// `initial_url` must point to a readable NUL-terminated byte sequence for the
/// duration of this call. `output_handle` must point to writable, properly
/// aligned storage for one `u64`. The call must run on Flutter's Linux platform
/// thread and `engine_handle` must identify the live engine supplied by
/// Irondash.
pub unsafe extern "C" fn webview_flutter_linux_view_create(
    engine_handle: i64,
    initial_url: *const c_char,
    javascript_enabled: i32,
    javascript_can_open_windows_automatically: i32,
    javascript_can_access_clipboard: i32,
    user_agent: *const c_char,
    output_handle: *mut u64,
) -> i32 {
    if output_handle.is_null() {
        return -1;
    }
    let initial_url = match required_c_string(initial_url) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let user_agent = if user_agent.is_null() {
        None
    } else {
        match required_c_string(user_agent).and_then(|value| CString::new(value).map_err(|_| -2)) {
            Ok(value) => Some(value),
            Err(status) => return status,
        }
    };
    let native_view = match new_native_view(engine_handle) {
        Ok(native_view) => native_view,
        Err(status) => return status,
    };
    let BuiltWebView {
        webview,
        network_session,
        download_started_handler_id,
        input_method_context,
        user_content_manager,
        view,
        toplevel,
    } = match build_webview(
        Rc::downgrade(&native_view),
        javascript_enabled != 0,
        javascript_can_open_windows_automatically != 0,
        javascript_can_access_clipboard != 0,
        user_agent.as_deref(),
        std::ptr::null_mut(),
    ) {
        Ok(parts) => parts,
        Err(status) => return status,
    };
    let raw_webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&webview).0
        as *mut WebKitWebView;
    let url = match CString::new(initial_url) {
        Ok(url) => url,
        Err(_) => return -2,
    };
    // SAFETY: raw_webview is borrowed from webview; WebKit copies the URI.
    unsafe { webkit_web_view_load_uri(raw_webview, url.as_ptr()) };
    native_view.runtime.replace(Some(WpeRuntime {
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
    register_cursor_view(view, &native_view);
    let handle = next_handle();
    VIEWS.with_borrow_mut(|views| {
        views.insert(handle, native_view);
    });
    // SAFETY: The caller provided writable, aligned storage for one `u64`.
    unsafe { output_handle.write(handle) };
    0
}

#[unsafe(no_mangle)]
/// Removes a handle from the registry and tears down its browser and texture.
///
/// Registry removal happens first so re-entrant or repeated calls cannot find
/// partially destroyed state. WPE/menu objects are dropped before the texture
/// is unregistered. Returns `-1` for zero, unknown, or already disposed handles.
pub extern "C" fn webview_flutter_linux_view_dispose(handle: u64) -> i32 {
    let native_view = VIEWS.with_borrow_mut(|views| views.remove(&handle));
    let Some(native_view) = native_view else {
        return -1;
    };
    // Removing the handle first preserves the exactly-once public contract.
    // If continuous input just ended, retain only the inaccessible native
    // ownership root until WebKit's scrolling thread has retired that stream.
    // Advancing the generation also cancels a pending delayed hide so teardown
    // cannot race a visibility transition at the same deadline.
    native_view
        .visibility_generation
        .set(native_view.visibility_generation.get().wrapping_add(1));
    let delay_micros = current_scroll_lifecycle_settle_delay_micros(&native_view);
    if delay_micros == 0 {
        return dispose_native_view(handle, native_view);
    }
    let _source_id =
        glib::timeout_add_local_once(std::time::Duration::from_micros(delay_micros), move || {
            let _ = dispose_native_view(handle, native_view);
        });
    0
}

#[unsafe(no_mangle)]
/// Schedules disposal requested by Dart's native finalizer.
///
/// Dart may invoke a native finalizer on an arbitrary helper thread. WPE and
/// the thread-local handle registry must only be touched by Flutter's platform
/// thread, so this callback creates an idle source and attaches it to the
/// process-default GLib context. Attaching a source is thread-safe and, unlike
/// `g_main_context_invoke`, never executes the teardown closure synchronously
/// on the calling finalizer thread.
///
/// The non-null pointer value is the opaque integer handle encoded by Dart.
/// Unknown or already-disposed handles are harmless when the source runs.
pub extern "C" fn webview_flutter_linux_view_dispose_finalizer(token: *mut c_void) {
    if token.is_null() {
        return;
    }
    let handle = token as usize as u64;
    let source = glib::source::idle_source_new(
        Some("webview-flutter-linux-finalizer"),
        glib::Priority::DEFAULT_IDLE,
        move || {
            let _ = webview_flutter_linux_view_dispose(handle);
            glib::ControlFlow::Break
        },
    );
    let _source_id = source.attach(Some(&glib::MainContext::default()));
}

/// Tears down one removed registry entry and every popup it still owns.
///
/// Child handles are removed before their browser objects are dropped, so
/// re-entrant WebKit signals cannot rediscover partially disposed state. A
/// popup transferred to Dart is absent from `owned_popup_handles` and therefore
/// remains alive when its opener goes away.
fn dispose_native_view(handle: u64, native_view: Rc<NativeView>) -> i32 {
    let accessibility_released = begin_accessibility_worker_view_discard(handle);
    native_view.popup_requests.borrow_mut().clear();
    let popup_handles = mem::take(&mut *native_view.owned_popup_handles.borrow_mut());
    for popup_handle in popup_handles {
        let popup = VIEWS.with_borrow_mut(|views| views.remove(&popup_handle));
        if let Some(popup) = popup {
            let _ = dispose_native_view(popup_handle, popup);
        }
    }
    cancel_process_bound_requests(&native_view, false);
    cancel_view_downloads(&native_view);
    discard_request_header_handoff(&native_view);
    if accessibility_released {
        native_view.runtime.take();
    } else {
        defer_runtime_disposal_until_accessibility_release(handle, native_view.clone());
    }
    native_view.texture.shutdown()
}

/// Retains a removed view until the AT-SPI worker has discarded queued state.
///
/// Public FFI lookup cannot find the handle after `VIEWS.remove`, and the
/// Flutter texture is shut down immediately. Only the WPE runtime remains
/// alive. A default-context timer performs the final drop back on the platform
/// thread after the worker publishes its acknowledgement. There is
/// intentionally no time-based fallback: an acknowledgement gives teardown a
/// deterministic ordering relative to already-queued accessibility commands.
fn defer_runtime_disposal_until_accessibility_release(handle: u64, native_view: Rc<NativeView>) {
    PENDING_ACCESSIBILITY_DISPOSALS.with_borrow_mut(|pending| {
        pending.insert(handle, native_view);
    });
    let source = glib::source::timeout_source_new(
        std::time::Duration::from_millis(10),
        Some("webview-flutter-linux-accessibility-disposal"),
        glib::Priority::DEFAULT_IDLE,
        move || {
            if !take_accessibility_worker_view_discarded(handle) {
                return glib::ControlFlow::Continue;
            }
            let native_view =
                PENDING_ACCESSIBILITY_DISPOSALS.with_borrow_mut(|pending| pending.remove(&handle));
            if let Some(native_view) = native_view {
                native_view.runtime.take();
            }
            glib::ControlFlow::Break
        },
    );
    let _source_id = source.attach(Some(&glib::MainContext::default()));
}
