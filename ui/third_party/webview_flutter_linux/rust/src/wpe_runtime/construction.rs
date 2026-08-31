// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Transactional construction of independent and opener-related WebViews.

use super::prelude::*;

thread_local! {
    /// Application-scoped WPE display shared by every independent WebView.
    ///
    /// WebKit may reuse a content process after a related-window lifecycle.
    /// Keeping one display ensures that process always addresses the same WPE
    /// clipboard and input-device registry instead of a display owned by an
    /// already-disposed opener. The cell is thread-local because WPE/GLib
    /// objects must never cross Flutter's Linux platform thread.
    static SHARED_DISPLAY: std::cell::OnceCell<glib::Object> = const {
        std::cell::OnceCell::new()
    };
}

/// Returns the platform-thread-owned headless display for this application.
fn shared_display() -> Result<glib::Object, i32> {
    SHARED_DISPLAY.with(|cell| {
        if let Some(display) = cell.get() {
            return Ok(display.clone());
        }
        let raw_display = unsafe { wpe_display_headless_new() };
        if raw_display.is_null() {
            return Err(-3);
        }
        // The headless display cannot discover host devices itself. Advertise
        // every input class Flutter forwards before any WebView observes it.
        unsafe {
            wpe_display_set_available_input_devices(
                raw_display,
                WPE_AVAILABLE_INPUT_DEVICE_MOUSE
                    | WPE_AVAILABLE_INPUT_DEVICE_KEYBOARD
                    | WPE_AVAILABLE_INPUT_DEVICE_TOUCHSCREEN,
            )
        };
        // SAFETY: wpe_display_headless_new returns one transfer-full GObject.
        let display: glib::Object =
            unsafe { from_glib_full(raw_display.cast::<glib::gobject_ffi::GObject>()) };
        // The cell is empty on this platform thread; retaining a clone lets the
        // caller use ordinary RAII while the application owner stays alive.
        cell.set(display.clone()).map_err(|_| -3)?;
        Ok(display)
    })
}

/// Fully constructed native objects returned before public-handle insertion.
///
/// Naming the aggregate keeps construction transactional without exposing a
/// fragile positional tuple at the call site.
pub(super) struct BuiltWebView {
    pub(super) webview: glib::Object,
    pub(super) network_session: glib::Object,
    pub(super) download_started_handler_id: glib::SignalHandlerId,
    pub(super) input_method_context: glib::Object,
    pub(super) user_content_manager: glib::Object,
    pub(super) view: *mut WpeView,
    pub(super) toplevel: *mut WpeToplevel,
}

/// Constructs either an independent or opener-related headless WebView.
///
/// A null `related_view` uses the application-scoped headless display and
/// shared network session. A non-null value is used while handling WebKit's
/// synchronous `create` signal; the `related-view` construct property makes
/// the child inherit both from its opener. Every view still receives a distinct
/// user-content manager so scripts and message handlers configured through one
/// Flutter controller cannot leak into another.
///
/// The returned `glib::Object` is the strong browser owner. `WpeView` and
/// `WpeToplevel` are transfer-none children. Signal handlers receive only a
/// weak [`NativeView`] so they stop operating after public-handle disposal.
pub(super) fn build_webview(
    native_view: Weak<NativeView>,
    javascript_enabled: bool,
    javascript_can_open_windows_automatically: bool,
    javascript_can_access_clipboard: bool,
    user_agent: Option<&CStr>,
    related_view: *mut WebKitWebView,
) -> Result<BuiltWebView, i32> {
    install_headless_cursor_callbacks()?;
    configure_web_process_extension()?;
    // A dedicated manager isolates scripts and message handlers between the
    // Flutter controllers hosted by one process, including popup controllers.
    let user_content_manager = unsafe { webkit_user_content_manager_new() };
    if user_content_manager.is_null() {
        return Err(-5);
    }
    let navigation_bridge_status =
        install_navigation_frame_bridge(user_content_manager, native_view.clone());
    if navigation_bridge_status < 0 {
        unsafe { glib::gobject_ffi::g_object_unref(user_content_manager.cast()) };
        return Err(-13);
    }

    // WebKit preferences must be present when the WebView is constructed.
    // Applying them only through `webkit_web_view_get_settings()` afterward
    // is too late when WebKit reuses a content process after a related-window
    // lifecycle: the UI-process object reports the new value, while the reused
    // content process can retain its creation-time preference. A dedicated
    // settings object also prevents a popup and opener from mutating one
    // another after construction.
    let raw_settings = unsafe { webkit_settings_new() };
    if raw_settings.is_null() {
        unsafe { glib::gobject_ffi::g_object_unref(user_content_manager.cast()) };
        return Err(-11);
    }
    // SAFETY: webkit_settings_new returns one transfer-full GObject reference.
    // The WebView construct property retains its own reference below.
    let settings: glib::Object =
        unsafe { from_glib_full(raw_settings.cast::<glib::gobject_ffi::GObject>()) };
    unsafe {
        if related_view.is_null() {
            // Keep the JavaScript engine available for explicit host
            // evaluation while suppressing page-authored script elements and
            // event-handler attributes during parsing. WebKit's
            // `enable-javascript-markup` setting provides exactly that split;
            // the web-process extension's isolated frame bridge also remains
            // available when UI-process user scripts are suppressed.
            webkit_settings_set_enable_javascript(raw_settings, 1);
            webkit_settings_set_enable_javascript_markup(
                raw_settings,
                i32::from(javascript_enabled),
            );
            webkit_settings_set_javascript_can_open_windows_automatically(
                raw_settings,
                i32::from(javascript_can_open_windows_automatically),
            );
            webkit_settings_set_javascript_can_access_clipboard(
                raw_settings,
                i32::from(javascript_can_access_clipboard),
            );
            if let Some(user_agent) = user_agent {
                webkit_settings_set_user_agent(raw_settings, user_agent.as_ptr());
            }
            webkit_settings_set_enable_media(raw_settings, 1);
            webkit_settings_set_enable_fullscreen(raw_settings, 1);
            webkit_settings_set_enable_webaudio(raw_settings, 1);
            webkit_settings_set_enable_developer_extras(raw_settings, 0);
            webkit_settings_set_media_playback_requires_user_gesture(raw_settings, 1);
        } else {
            // Clone every setting currently controlled by the Dart API. The
            // related-view property still supplies the shared process and
            // network session; settings remain independently owned.
            let opener_settings = webkit_web_view_get_settings(related_view);
            if !opener_settings.is_null() {
                webkit_settings_set_enable_javascript(
                    raw_settings,
                    webkit_settings_get_enable_javascript(opener_settings),
                );
                webkit_settings_set_enable_javascript_markup(
                    raw_settings,
                    webkit_settings_get_enable_javascript_markup(opener_settings),
                );
                webkit_settings_set_javascript_can_open_windows_automatically(
                    raw_settings,
                    webkit_settings_get_javascript_can_open_windows_automatically(opener_settings),
                );
                webkit_settings_set_javascript_can_access_clipboard(
                    raw_settings,
                    webkit_settings_get_javascript_can_access_clipboard(opener_settings),
                );
                webkit_settings_set_allow_file_access_from_file_urls(
                    raw_settings,
                    webkit_settings_get_allow_file_access_from_file_urls(opener_settings),
                );
                webkit_settings_set_user_agent(
                    raw_settings,
                    webkit_settings_get_user_agent(opener_settings),
                );
                webkit_settings_set_enable_media(
                    raw_settings,
                    webkit_settings_get_enable_media(opener_settings),
                );
                webkit_settings_set_enable_fullscreen(
                    raw_settings,
                    webkit_settings_get_enable_fullscreen(opener_settings),
                );
                webkit_settings_set_enable_webaudio(
                    raw_settings,
                    webkit_settings_get_enable_webaudio(opener_settings),
                );
                webkit_settings_set_enable_developer_extras(
                    raw_settings,
                    webkit_settings_get_enable_developer_extras(opener_settings),
                );
                webkit_settings_set_media_playback_requires_user_gesture(
                    raw_settings,
                    webkit_settings_get_media_playback_requires_user_gesture(opener_settings),
                );
                webkit_settings_set_media_playback_allows_inline(
                    raw_settings,
                    webkit_settings_get_media_playback_allows_inline(opener_settings),
                );
                webkit_settings_set_enable_webrtc(
                    raw_settings,
                    webkit_settings_get_enable_webrtc(opener_settings),
                );
                webkit_settings_set_enable_mock_capture_devices(
                    raw_settings,
                    webkit_settings_get_enable_mock_capture_devices(opener_settings),
                );
                webkit_settings_set_enable_encrypted_media(
                    raw_settings,
                    webkit_settings_get_enable_encrypted_media(opener_settings),
                );
                webkit_settings_set_allow_universal_access_from_file_urls(
                    raw_settings,
                    webkit_settings_get_allow_universal_access_from_file_urls(opener_settings),
                );
                webkit_settings_set_zoom_text_only(
                    raw_settings,
                    webkit_settings_get_zoom_text_only(opener_settings),
                );
            }
        }
    }

    // Related views inherit their opener's display through the construct-only
    // related-view property. Independent views keep a temporary strong
    // reference to the shared application display through construction.
    let display = if related_view.is_null() {
        Some(shared_display()?)
    } else {
        None
    };
    let raw_display = display.as_ref().map_or(std::ptr::null_mut(), |display| {
        ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(display)
            .0
            .cast::<WpeDisplay>()
    });
    let network_session = if related_view.is_null() {
        match shared_network_session() {
            Ok(session) => session,
            Err(status) => {
                unsafe { glib::gobject_ffi::g_object_unref(user_content_manager.cast()) };
                return Err(status);
            }
        }
    } else {
        std::ptr::null_mut()
    };

    // SAFETY: Both variadic property lists use public construct properties and
    // terminate with a null property name. Related views intentionally omit
    // display and network-session because WebKit inherits both from the opener.
    let object = unsafe {
        if related_view.is_null() {
            glib::gobject_ffi::g_object_new(
                webkit_web_view_get_type(),
                c"display".as_ptr(),
                raw_display,
                c"network-session".as_ptr(),
                network_session,
                c"user-content-manager".as_ptr(),
                user_content_manager,
                c"settings".as_ptr(),
                raw_settings,
                std::ptr::null::<c_char>(),
            )
        } else {
            glib::gobject_ffi::g_object_new(
                webkit_web_view_get_type(),
                c"related-view".as_ptr(),
                related_view,
                c"user-content-manager".as_ptr(),
                user_content_manager,
                c"settings".as_ptr(),
                raw_settings,
                std::ptr::null::<c_char>(),
            )
        }
    };
    if object.is_null() {
        unsafe { glib::gobject_ffi::g_object_unref(user_content_manager.cast()) };
        return Err(-6);
    }
    // SAFETY: g_object_new returned a transfer-full GObject.
    let webview: glib::Object = unsafe { from_glib_full(object) };
    // Keep one strong manager reference for dynamic channel operations. The
    // WebView independently retained the construct-property reference.
    let user_content_manager: glib::Object =
        unsafe { from_glib_full(user_content_manager.cast::<glib::gobject_ffi::GObject>()) };
    let raw_webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&webview).0
        as *mut WebKitWebView;
    if unsafe { webkit_web_view_get_settings(raw_webview) } != raw_settings {
        return Err(-12);
    }
    let expected_display = if related_view.is_null() {
        raw_display
    } else {
        unsafe { webkit_web_view_get_display(related_view) }
    };
    let display = unsafe { webkit_web_view_get_display(raw_webview) };
    let network_session = unsafe { webkit_web_view_get_network_session(raw_webview) };
    if display.is_null() || display != expected_display {
        return Err(-7);
    }
    if network_session.is_null() {
        return Err(-4);
    }
    // Audio is routed by WebKit/GStreamer and does not pass through the texture
    // transport.
    unsafe {
        webkit_web_view_set_is_muted(raw_webview, 0);
        if !related_view.is_null() {
            webkit_web_view_set_zoom_level(
                raw_webview,
                webkit_web_view_get_zoom_level(related_view),
            );
        }
    }
    let input_method_context = create_input_method_context(native_view.clone())?;
    let raw_input_method_context =
        ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&input_method_context).0
            as *mut WebKitInputMethodContext;
    // WebView retains the context. The runtime also keeps a strong reference
    // so Dart-driven commit/preedit calls can address the exact installed
    // adapter without querying an unrelated platform default.
    unsafe {
        webkit_web_view_set_input_method_context(raw_webview, raw_input_method_context);
    }
    connect_web_process_frame_hints(&webview, native_view.clone());
    connect_navigation_events(&webview, native_view.clone());
    connect_script_dialogs(&webview, native_view.clone());
    connect_file_chooser_requests(&webview, native_view.clone());
    connect_permission_requests(&webview, native_view.clone());
    connect_permission_state_queries(&webview, native_view.clone());
    connect_notifications(&webview, native_view.clone());
    connect_http_auth_requests(&webview, native_view.clone());
    connect_ssl_auth_errors(&webview, native_view.clone());
    connect_context_menu(&webview, native_view.clone());
    connect_option_menu(&webview, native_view.clone());
    connect_popup_creation(&webview, native_view.clone());
    connect_fullscreen_events(&webview, native_view.clone());
    let (network_session, download_started_handler_id) =
        connect_downloads(network_session, &webview, native_view.clone());
    if unsafe { webkit_web_view_get_user_content_manager(raw_webview) }
        != ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&user_content_manager).0
            as *mut WebKitUserContentManager
    {
        return Err(-8);
    }
    // SAFETY: raw_webview remains alive through webview.
    let view = unsafe { webkit_web_view_get_wpe_view(raw_webview) };
    if view.is_null() {
        return Err(-9);
    }
    // SAFETY: view is a valid transfer-none WPEView pointer.
    let toplevel = unsafe { wpe_view_get_toplevel(view) };
    if toplevel.is_null() {
        return Err(-10);
    }
    connect_buffer_rendered(view, native_view);
    drop(settings);
    Ok(BuiltWebView {
        webview,
        network_session,
        download_started_handler_id,
        input_method_context,
        user_content_manager,
        view,
        toplevel,
    })
}
