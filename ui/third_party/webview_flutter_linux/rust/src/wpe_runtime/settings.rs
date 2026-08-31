// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Per-view WebKit settings, presentation properties, and text metadata.
//!
//! These synchronous C ABI functions borrow settings or view properties only
//! for the duration of each call. No transfer-none native pointer crosses into
//! Dart or survives view disposal.

use super::{prelude::*, requests};

/// Maximum time allowed for WebKit's scrolling thread to retire a terminal
/// touch or precise-scroll event before the view is hidden or destroyed.
///
/// This is deliberately shorter than a user-visible animation frame sequence
/// and is applied only when lifecycle teardown immediately follows scrolling.
const SCROLL_LIFECYCLE_SETTLE_MICROS: i64 = 250_000;

/// Returns the remaining scrolling-thread grace period at `now`.
///
/// Keeping this arithmetic pure makes the lifecycle boundary testable without
/// clocks or GLib. A backwards clock observation is treated conservatively as
/// a fresh event even though GLib's monotonic clock should never move backwards.
pub(super) const fn scroll_lifecycle_settle_delay_micros(
    last_scroll_input_micros: i64,
    now_micros: i64,
) -> u64 {
    if last_scroll_input_micros <= 0 {
        return 0;
    }
    let elapsed = if now_micros <= last_scroll_input_micros {
        0
    } else {
        now_micros.saturating_sub(last_scroll_input_micros)
    };
    if elapsed >= SCROLL_LIFECYCLE_SETTLE_MICROS {
        0
    } else {
        (SCROLL_LIFECYCLE_SETTLE_MICROS - elapsed) as u64
    }
}

/// Records input that may leave work on WebKit's asynchronous scrolling tree.
pub(super) fn record_scroll_lifecycle_input(handle: u64) {
    let Some(native_view) = native_view(handle) else {
        return;
    };
    // SAFETY: `g_get_monotonic_time` has no preconditions or owned result.
    native_view
        .last_scroll_input_micros
        .set(unsafe { glib::ffi::g_get_monotonic_time() });
}

/// Calculates the view's remaining scrolling settle interval from GLib time.
pub(super) fn current_scroll_lifecycle_settle_delay_micros(native_view: &NativeView) -> u64 {
    // SAFETY: `g_get_monotonic_time` has no preconditions or owned result.
    let now_micros = unsafe { glib::ffi::g_get_monotonic_time() };
    scroll_lifecycle_settle_delay_micros(native_view.last_scroll_input_micros.get(), now_micros)
}

/// Applies visibility to a live runtime without repeating registry lookup.
fn apply_visibility(native_view: &NativeView, visible: bool) -> i32 {
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -1;
    };
    // SAFETY: `runtime` strongly owns the WPE view for this borrow.
    unsafe { wpe_view_set_visible(runtime.view, i32::from(visible)) };
    0
}

/// Sets whether WPE should consider this view visible.
///
/// Flutter lifecycle changes use this to let WebKit throttle hidden pages.
#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_set_visibility(handle: u64, visible: i32) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let generation = native_view.visibility_generation.get().wrapping_add(1);
    native_view.visibility_generation.set(generation);
    if visible != 0 {
        return apply_visibility(&native_view, true);
    }

    let delay_micros = current_scroll_lifecycle_settle_delay_micros(&native_view);
    if delay_micros == 0 {
        return apply_visibility(&native_view, false);
    }

    // A later show/hide request advances the generation, making this timeout a
    // no-op. The weak reference also prevents a delayed hide from extending the
    // public native view's lifetime after controller disposal.
    let weak_view = Rc::downgrade(&native_view);
    let _source_id =
        glib::timeout_add_local_once(std::time::Duration::from_micros(delay_micros), move || {
            let Some(native_view) = weak_view.upgrade() else {
                return;
            };
            if native_view.visibility_generation.get() != generation {
                return;
            }
            let _ = apply_visibility(&native_view, false);
        });
    0
}

#[unsafe(no_mangle)]
/// Enables or disables JavaScript authored by subsequent page markup.
///
/// WPE's global JavaScript switch also suppresses isolated embedder scripts,
/// including the private navigation-frame bridge. WebKit's documented
/// `enable-javascript-markup` policy instead removes script elements and
/// JavaScript attributes while leaving host evaluations available, matching
/// WKWebView's content-JavaScript split. The global engine switch therefore
/// remains enabled. Returns `-1` when the handle, runtime, or WebKit settings
/// object is unavailable.
pub extern "C" fn webview_flutter_linux_wpe_set_javascript_enabled(
    handle: u64,
    enabled: i32,
) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -1;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    // SAFETY: webview is borrowed from the live runtime and settings is a
    // transfer-none child retained by WebKit.
    let settings = unsafe { webkit_web_view_get_settings(webview) };
    if settings.is_null() {
        return -1;
    }
    unsafe {
        webkit_settings_set_enable_javascript(settings, 1);
        webkit_settings_set_enable_javascript_markup(settings, i32::from(enabled != 0));
    }
    0
}

#[unsafe(no_mangle)]
/// Controls whether JavaScript may create a related window without a gesture.
///
/// The Linux implementation owns real related WPE views, so enabling this
/// setting has the same role as the Android plugin's initialization policy:
/// programmatic `window.open()` reaches the existing Flutter popup callback.
pub extern "C" fn webview_flutter_linux_wpe_set_javascript_can_open_windows_automatically(
    handle: u64,
    enabled: i32,
) -> i32 {
    with_webview_settings(handle, |settings| unsafe {
        webkit_settings_set_javascript_can_open_windows_automatically(
            settings,
            i32::from(enabled != 0),
        )
    })
}

#[unsafe(no_mangle)]
/// Returns the effective automatic JavaScript-window preference, or `-1` for
/// an invalid or disposed view.
pub extern "C" fn webview_flutter_linux_wpe_javascript_can_open_windows_automatically(
    handle: u64,
) -> i32 {
    let mut enabled = -1;
    let status = with_webview_settings(handle, |settings| {
        enabled =
            unsafe { webkit_settings_get_javascript_can_open_windows_automatically(settings) };
    });
    if status < 0 { status } else { enabled }
}

#[unsafe(no_mangle)]
/// Controls whether page JavaScript may execute clipboard editing commands.
///
/// WPE keeps `document.execCommand("cut" | "copy" | "paste")` disabled by
/// default even when the embedding application has supplied a working native
/// clipboard. Flutter already synchronizes the WPE clipboard with the desktop;
/// this opt-in only changes WebKit's script policy and does not bypass that
/// bounded clipboard transport or grant filesystem access.
pub extern "C" fn webview_flutter_linux_wpe_set_javascript_can_access_clipboard(
    handle: u64,
    enabled: i32,
) -> i32 {
    with_webview_settings(handle, |settings| unsafe {
        webkit_settings_set_javascript_can_access_clipboard(settings, i32::from(enabled != 0))
    })
}

#[unsafe(no_mangle)]
/// Returns WebKit's effective JavaScript clipboard-command policy.
///
/// One means enabled, zero means disabled, and a negative value means the view
/// or its settings object is no longer available.
pub extern "C" fn webview_flutter_linux_wpe_javascript_can_access_clipboard(handle: u64) -> i32 {
    let mut enabled = -1;
    let status = with_webview_settings(handle, |settings| {
        enabled = unsafe { webkit_settings_get_javascript_can_access_clipboard(settings) };
    });
    if status < 0 { status } else { enabled }
}

#[unsafe(no_mangle)]
/// Sets whether WebKit requires a user gesture before loading or playing media.
///
/// This maps directly to the per-view public `WebKitSettings` property used by
/// WPE's media policy. The value takes effect for subsequent media decisions
/// without recreating the browser or its Flutter texture.
pub extern "C" fn webview_flutter_linux_wpe_set_media_playback_requires_user_gesture(
    handle: u64,
    required: i32,
) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -1;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    let settings = unsafe { webkit_web_view_get_settings(webview) };
    if settings.is_null() {
        return -1;
    }
    unsafe {
        webkit_settings_set_media_playback_requires_user_gesture(settings, i32::from(required != 0))
    };
    0
}

/// Borrows the settings object owned by a live WebView for one synchronous
/// update.
///
/// `WebKitSettings` is transfer-none and thread-affine. Keeping this lookup in
/// one helper prevents capability setters from accidentally retaining the
/// pointer or applying settings to an already disposed runtime.
fn with_webview_settings(handle: u64, operation: impl FnOnce(*mut WebKitSettings)) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -1;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    // SAFETY: `webview` is borrowed from the live runtime and WebKit owns the
    // transfer-none settings object for at least the duration of this call.
    let settings = unsafe { webkit_web_view_get_settings(webview) };
    if settings.is_null() {
        return -1;
    }
    operation(settings);
    0
}

#[unsafe(no_mangle)]
/// Enables or disables Geolocation API permission requests for one WebView.
///
/// WPE exposes geolocation through a concrete permission-request type rather
/// than a `WebKitSettings` property. The per-view gate is checked synchronously
/// before a request can cross into Dart. Disabling also denies requests already
/// queued or awaiting an asynchronous Flutter decision. WPE does not expose a
/// per-view API for revoking an origin permission after WebKit has already
/// granted it, so this gate intentionally makes no stronger claim about an
/// active page watch whose permission request has already been resolved.
pub extern "C" fn webview_flutter_linux_wpe_set_geolocation_enabled(
    handle: u64,
    enabled: i32,
) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let enabled = enabled != 0;
    native_view.geolocation_enabled.set(enabled);
    if !enabled {
        requests::deny_geolocation_permission_requests(&native_view);
    }
    0
}

#[unsafe(no_mangle)]
/// Returns one for an enabled geolocation gate, zero when disabled, and `-1`
/// for an invalid or disposed view handle.
pub extern "C" fn webview_flutter_linux_wpe_geolocation_enabled(handle: u64) -> i32 {
    native_view(handle).map_or(-1, |view| i32::from(view.geolocation_enabled.get()))
}

#[unsafe(no_mangle)]
/// Sets whether media elements may remain inside the page while playing.
///
/// Disabling this uses WPE's native fullscreen-only media policy; it does not
/// emulate fullscreen in Dart or alter the separate autoplay gesture policy.
pub extern "C" fn webview_flutter_linux_wpe_set_media_playback_allows_inline(
    handle: u64,
    allowed: i32,
) -> i32 {
    with_webview_settings(handle, |settings| unsafe {
        webkit_settings_set_media_playback_allows_inline(settings, i32::from(allowed != 0))
    })
}

#[unsafe(no_mangle)]
/// Enables or disables WPE's WebRTC and peer-connection implementation.
///
/// WPE also enables MediaStream when WebRTC is enabled, matching the public
/// `WebKitSettings` contract. Permission decisions still flow through the
/// existing retained permission-request bridge.
pub extern "C" fn webview_flutter_linux_wpe_set_webrtc_enabled(handle: u64, enabled: i32) -> i32 {
    with_webview_settings(handle, |settings| unsafe {
        webkit_settings_set_enable_webrtc(settings, i32::from(enabled != 0))
    })
}

#[unsafe(no_mangle)]
/// Enables deterministic WebKit camera and microphone devices for automation.
///
/// This is deliberately separate from WebRTC and permission policy. Pages
/// still require an application grant, but tests and headless CI can exercise
/// that real permission path without depending on host capture hardware.
pub extern "C" fn webview_flutter_linux_wpe_set_mock_capture_devices_enabled(
    handle: u64,
    enabled: i32,
) -> i32 {
    with_webview_settings(handle, |settings| unsafe {
        webkit_settings_set_enable_mock_capture_devices(settings, i32::from(enabled != 0))
    })
}

#[unsafe(no_mangle)]
/// Returns whether deterministic WebKit capture devices are enabled.
pub extern "C" fn webview_flutter_linux_wpe_mock_capture_devices_enabled(handle: u64) -> i32 {
    let mut enabled = -1;
    let status = with_webview_settings(handle, |settings| {
        enabled = unsafe { webkit_settings_get_enable_mock_capture_devices(settings) };
    });
    if status < 0 { status } else { enabled }
}

#[unsafe(no_mangle)]
/// Enables or disables WPE's Encrypted Media Extensions implementation.
///
/// Enabling the API cannot add a DRM backend that the host WPE/GStreamer build
/// does not provide; it only controls the per-view WebKit capability switch.
pub extern "C" fn webview_flutter_linux_wpe_set_encrypted_media_enabled(
    handle: u64,
    enabled: i32,
) -> i32 {
    with_webview_settings(handle, |settings| unsafe {
        webkit_settings_set_enable_encrypted_media(settings, i32::from(enabled != 0))
    })
}

#[unsafe(no_mangle)]
/// Enables or disables WebKit developer extras for one view.
///
/// Developer extras are WPE's public per-view switch for inspection tooling
/// and related developer features. Keeping the default disabled avoids
/// exposing those facilities in release applications unless the Dart owner
/// opts in explicitly.
pub extern "C" fn webview_flutter_linux_wpe_set_inspectable(handle: u64, inspectable: i32) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -1;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    let settings = unsafe { webkit_web_view_get_settings(webview) };
    if settings.is_null() {
        return -1;
    }
    unsafe { webkit_settings_set_enable_developer_extras(settings, i32::from(inspectable != 0)) };
    0
}

#[unsafe(no_mangle)]
/// Allows or denies local-file requests initiated by a document loaded from a
/// `file:` URI.
///
/// WebKit keeps this disabled by default. Flutter's `loadFile` and
/// `loadFlutterAsset` contracts require an HTML document to resolve its
/// adjacent CSS, images, scripts, and other packaged resources, so Dart
/// enables this setting before the first local-file navigation. The setting is
/// scoped to this WebView and does not grant HTTP documents access to local
/// files because WebKit still applies the requesting document's origin.
/// Returns `-1` when the handle, runtime, or settings object is unavailable.
pub extern "C" fn webview_flutter_linux_wpe_set_file_access_enabled(
    handle: u64,
    enabled: i32,
) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -1;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    // SAFETY: webview is borrowed from the live runtime and settings is a
    // transfer-none child retained by WebKit for at least this call.
    let settings = unsafe { webkit_web_view_get_settings(webview) };
    if settings.is_null() {
        return -1;
    }
    unsafe {
        webkit_settings_set_allow_file_access_from_file_urls(settings, i32::from(enabled != 0))
    };
    0
}

#[unsafe(no_mangle)]
/// Allows or denies file-origin documents access to resources from any origin.
///
/// This is intentionally separate from adjacent-file access because universal
/// access relaxes the same-origin boundary for local documents. It remains off
/// unless the Dart application explicitly opts in.
pub extern "C" fn webview_flutter_linux_wpe_set_universal_file_access_enabled(
    handle: u64,
    enabled: i32,
) -> i32 {
    with_webview_settings(handle, |settings| unsafe {
        webkit_settings_set_allow_universal_access_from_file_urls(settings, i32::from(enabled != 0))
    })
}

#[unsafe(no_mangle)]
/// Returns the effective WPE capability switches for one live view.
///
/// Bits zero through five represent enabled inline media, WebRTC, encrypted
/// media, adjacent-file access, universal file-origin access, and JavaScript
/// clipboard commands. Bits eight and nine report whether the host build
/// contains the WebRTC and encrypted-media feature definitions at all. Support
/// bits prevent callers confusing a writable preference with a browser
/// capability compiled out of system WPE.
pub extern "C" fn webview_flutter_linux_wpe_capability_flags(handle: u64) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -1;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    let settings = unsafe { webkit_web_view_get_settings(webview) };
    if settings.is_null() {
        return -1;
    }
    let mut flags = 0;
    unsafe {
        if webkit_settings_get_media_playback_allows_inline(settings) != 0 {
            flags |= 1 << 0;
        }
        if webkit_settings_get_enable_webrtc(settings) != 0 {
            flags |= 1 << 1;
        }
        if webkit_settings_get_enable_encrypted_media(settings) != 0 {
            flags |= 1 << 2;
        }
        if webkit_settings_get_allow_file_access_from_file_urls(settings) != 0 {
            flags |= 1 << 3;
        }
        if webkit_settings_get_allow_universal_access_from_file_urls(settings) != 0 {
            flags |= 1 << 4;
        }
        if webkit_settings_get_javascript_can_access_clipboard(settings) != 0 {
            flags |= 1 << 5;
        }
    }
    // The feature list is transfer-full. Its items remain transfer-none and
    // valid until this bounded scan releases the list.
    let features = unsafe { webkit_settings_get_all_features() };
    if !features.is_null() {
        let length = unsafe { webkit_feature_list_get_length(features) };
        for index in 0..length {
            let feature = unsafe { webkit_feature_list_get(features, index) };
            if feature.is_null() {
                continue;
            }
            let identifier = unsafe { webkit_feature_get_identifier(feature) };
            if identifier.is_null() {
                continue;
            }
            match unsafe { CStr::from_ptr(identifier) }.to_bytes() {
                b"PeerConnection" | b"PeerConnectionEnabled" => flags |= 1 << 8,
                b"EncryptedMediaAPI" | b"EncryptedMediaAPIEnabled" => flags |= 1 << 9,
                _ => {}
            }
        }
        unsafe { webkit_feature_list_unref(features) };
    }
    flags
}

#[unsafe(no_mangle)]
/// Replaces the WebKit user agent for subsequent requests.
///
/// A null pointer restores WebKit's default user agent. Non-null values must be
/// valid NUL-terminated UTF-8. Returns `-1` for invalid UTF-8 and `-2` when the
/// view or settings object is unavailable.
pub extern "C" fn webview_flutter_linux_wpe_set_user_agent(
    handle: u64,
    user_agent: *const c_char,
) -> i32 {
    let user_agent = if user_agent.is_null() {
        None
    } else {
        match required_c_string(user_agent)
            .and_then(|value| std::ffi::CString::new(value).map_err(|_| -1))
        {
            Ok(value) => Some(value),
            Err(status) => return status,
        }
    };
    let Some(native_view) = native_view(handle) else {
        return -2;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -2;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    // SAFETY: webview is borrowed from the live runtime and settings is a
    // transfer-none child. WebKit copies the optional user-agent string.
    let settings = unsafe { webkit_web_view_get_settings(webview) };
    if settings.is_null() {
        return -2;
    }
    unsafe {
        webkit_settings_set_user_agent(
            settings,
            user_agent
                .as_ref()
                .map_or(std::ptr::null(), |value| value.as_ptr()),
        )
    };
    0
}

/// Copies the current WebKit user-agent bytes for a live view.
fn webview_user_agent(handle: u64) -> Option<Vec<u8>> {
    let native_view = native_view(handle)?;
    let runtime = native_view.runtime.borrow();
    let runtime = runtime.as_ref()?;
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    let settings = unsafe { webkit_web_view_get_settings(webview) };
    if settings.is_null() {
        return None;
    }
    let user_agent = unsafe { webkit_settings_get_user_agent(settings) };
    if user_agent.is_null() {
        None
    } else {
        Some(unsafe { CStr::from_ptr(user_agent) }.to_bytes().to_vec())
    }
}

/// Copies one transfer-none UTF-8 property from a live WebKit view.
fn webview_text_property(
    handle: u64,
    getter: unsafe extern "C" fn(*mut WebKitWebView) -> *const c_char,
) -> Option<Vec<u8>> {
    let native_view = native_view(handle)?;
    let runtime = native_view.runtime.borrow();
    let runtime = runtime.as_ref()?;
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    let value = unsafe { getter(webview) };
    (!value.is_null()).then(|| unsafe { CStr::from_ptr(value) }.to_bytes().to_vec())
}

/// Copies optional view-property bytes into caller-owned storage.
unsafe fn copy_webview_text_property(
    handle: u64,
    getter: unsafe extern "C" fn(*mut WebKitWebView) -> *const c_char,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    let Some(value) = webview_text_property(handle, getter) else {
        return -2;
    };
    if destination_length < value.len() || value.len() > i32::MAX as usize {
        return -3;
    }
    unsafe { std::ptr::copy_nonoverlapping(value.as_ptr(), destination, value.len()) };
    value.len() as i32
}

#[unsafe(no_mangle)]
/// Returns the UTF-8 byte length of WebKit's current main-frame URI.
pub extern "C" fn webview_flutter_linux_wpe_uri_length(handle: u64) -> isize {
    webview_text_property(handle, webkit_web_view_get_uri).map_or(-1, |value| value.len() as isize)
}

#[unsafe(no_mangle)]
/// Copies WebKit's current main-frame URI into caller-owned storage.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes and remain
/// valid for this call. Rust never stores the pointer.
pub unsafe extern "C" fn webview_flutter_linux_wpe_copy_uri(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    unsafe {
        copy_webview_text_property(
            handle,
            webkit_web_view_get_uri,
            destination,
            destination_length,
        )
    }
}

#[unsafe(no_mangle)]
/// Returns the UTF-8 byte length of WebKit's current document title.
pub extern "C" fn webview_flutter_linux_wpe_title_length(handle: u64) -> isize {
    webview_text_property(handle, webkit_web_view_get_title)
        .map_or(-1, |value| value.len() as isize)
}

#[unsafe(no_mangle)]
/// Copies WebKit's current document title into caller-owned storage.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes and remain
/// valid for this call. Rust never stores the pointer.
pub unsafe extern "C" fn webview_flutter_linux_wpe_copy_title(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    unsafe {
        copy_webview_text_property(
            handle,
            webkit_web_view_get_title,
            destination,
            destination_length,
        )
    }
}

#[unsafe(no_mangle)]
/// Returns the UTF-8 length of the current WebKit user agent.
pub extern "C" fn webview_flutter_linux_wpe_user_agent_length(handle: u64) -> isize {
    webview_user_agent(handle).map_or(-1, |value| value.len() as isize)
}

#[unsafe(no_mangle)]
/// Copies the current WebKit user agent into caller-owned storage.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes and remain
/// valid for this call. Rust never stores the pointer.
pub unsafe extern "C" fn webview_flutter_linux_wpe_copy_user_agent(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    let Some(user_agent) = webview_user_agent(handle) else {
        return -2;
    };
    if destination_length < user_agent.len() || user_agent.len() > i32::MAX as usize {
        return -3;
    }
    unsafe { std::ptr::copy_nonoverlapping(user_agent.as_ptr(), destination, user_agent.len()) };
    user_agent.len() as i32
}

/// Converts an Android-compatible text-zoom percentage into WPE's factor.
///
/// WPE accepts a floating-point zoom factor. Keeping validation separate from
/// the live WebView lookup makes the public ABI reject NaN-equivalent or
/// unreasonable scale requests before any browser state is changed.
pub(super) fn text_zoom_factor(text_zoom: i32) -> Option<f64> {
    (10..=1_000)
        .contains(&text_zoom)
        .then_some(f64::from(text_zoom) / 100.0)
}

#[unsafe(no_mangle)]
/// Sets text-only zoom using the percentage contract exposed by Android.
///
/// WPE routes its WebView zoom factor either to the complete page or only to
/// text and text-bearing form controls. A non-default percentage selects the
/// latter mode before applying the factor. Setting 100 first restores the
/// neutral factor and then returns the view to ordinary full-page zoom mode,
/// so later Flutter touchpad pinch gestures continue to zoom the whole page.
///
/// Percentages below 10 or above 1000 are rejected with `-1`. Invalid or
/// disposed handles return `-2` without changing browser state.
pub extern "C" fn webview_flutter_linux_wpe_set_text_zoom(handle: u64, text_zoom: i32) -> i32 {
    let Some(zoom_factor) = text_zoom_factor(text_zoom) else {
        return -1;
    };
    let Some(native_view) = native_view(handle) else {
        return -2;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -2;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    // SAFETY: `webview` and its transfer-none settings object are borrowed
    // from the live runtime for this synchronous operation only.
    let settings = unsafe { webkit_web_view_get_settings(webview) };
    if settings.is_null() {
        return -2;
    }
    unsafe {
        if text_zoom == 100 {
            // Reset while text-only mode is still active. Disabling the mode
            // afterward migrates a neutral factor back to full-page zoom.
            webkit_web_view_set_zoom_level(webview, 1.0);
            webkit_settings_set_zoom_text_only(settings, 0);
        } else {
            webkit_settings_set_zoom_text_only(settings, 1);
            webkit_web_view_set_zoom_level(webview, zoom_factor);
        }
    }
    0
}

#[unsafe(no_mangle)]
/// Returns the effective text-only zoom percentage for one live view.
///
/// Ordinary full-page zoom mode reports 100 even when the page itself is
/// zoomed. Text-only mode reports WPE's current factor rounded to the nearest
/// percentage. Zero identifies an invalid or disposed handle.
pub extern "C" fn webview_flutter_linux_wpe_text_zoom(handle: u64) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return 0;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return 0;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    let settings = unsafe { webkit_web_view_get_settings(webview) };
    if settings.is_null() {
        return 0;
    }
    if unsafe { webkit_settings_get_zoom_text_only(settings) } == 0 {
        return 100;
    }
    let percentage = unsafe { webkit_web_view_get_zoom_level(webview) } * 100.0;
    if !percentage.is_finite() || !(10.0..=1_000.0).contains(&percentage) {
        return 0;
    }
    percentage.round() as i32
}

#[unsafe(no_mangle)]
/// Sets WebKit's page zoom factor for one view.
///
/// Values outside `0.1..=10.0`, NaN, and infinity are rejected. Dart applies a
/// narrower user-facing clamp for touchpad gestures.
pub extern "C" fn webview_flutter_linux_wpe_set_zoom_level(handle: u64, zoom_level: f64) -> i32 {
    if !zoom_level.is_finite() || !(0.1..=10.0).contains(&zoom_level) {
        return -1;
    }
    let Some(native_view) = native_view(handle) else {
        return -2;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -2;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    unsafe { webkit_web_view_set_zoom_level(webview, zoom_level) };
    0
}

#[unsafe(no_mangle)]
/// Returns WebKit's current page zoom factor, or zero for an invalid handle.
pub extern "C" fn webview_flutter_linux_wpe_zoom_level(handle: u64) -> f64 {
    let Some(native_view) = native_view(handle) else {
        return 0.0;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return 0.0;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    unsafe { webkit_web_view_get_zoom_level(webview) }
}

#[unsafe(no_mangle)]
/// Applies an ARGB Flutter color behind transparent page content.
pub extern "C" fn webview_flutter_linux_wpe_set_background_color(handle: u64, argb: u32) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -1;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    let component = |shift| f64::from(((argb >> shift) & 0xff_u32) as u8) / 255.0;
    let color = WebKitColor {
        red: component(16),
        green: component(8),
        blue: component(0),
        alpha: component(24),
    };
    unsafe { webkit_web_view_set_background_color(webview, &color) };
    0
}
