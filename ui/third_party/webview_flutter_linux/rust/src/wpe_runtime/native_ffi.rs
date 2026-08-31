// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Raw WPE WebKit, WPE Platform, GLib, GIO, ATK, and AT-SPI declarations.
//!
//! This module contains only the hand-written native ABI boundary. Runtime
//! ownership, callback policy, handle lookup, and exported Dart-facing
//! functions remain in the surrounding `wpe_runtime` module tree. Every item
//! is visible only within that tree so the unsafe surface cannot leak across
//! the crate.

use std::ffi::{c_char, c_void};

use super::prelude::{NativeView, Weak};

// Opaque declarations for the WPE/WebKit/GIO types used by the hand-written
// ABI. Rust never constructs or dereferences these zero-sized marker types; it
// only passes pointers back to the library that created them. Ownership and
// transfer annotations for individual calls are recorded at their call sites.
#[repr(C)]
pub(super) struct WpeDisplay {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WpeView {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WpeToplevel {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WpeBuffer {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WpeBufferDmaBuf {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WpeRectangle {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WpeEvent {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WpeClipboard {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WpeViewAccessible {
    pub(super) _opaque: [u8; 0],
}

/// Public prefix of `WPEViewClass` from WPE Platform 2.0.
///
/// WPE's headless final class deliberately leaves both cursor vfuncs unset,
/// because it has no native window on which to display a cursor. Flutter owns
/// that window in this embedding, so [`install_headless_cursor_callbacks`]
/// fills those two public subclass slots and leaves every other slot exactly as
/// WPE initialized it. Keeping the complete published prefix here is critical:
/// the callback fields cannot be addressed safely through a shortened layout.
#[repr(C)]
pub(super) struct WpeViewClass {
    pub(super) parent_class: glib::gobject_ffi::GObjectClass,
    pub(super) buffers_changed:
        Option<unsafe extern "C" fn(*mut WpeView, *mut *mut WpeBuffer, u32)>,
    pub(super) render_buffer: Option<
        unsafe extern "C" fn(
            *mut WpeView,
            *mut WpeBuffer,
            *const WpeRectangle,
            u32,
            *mut *mut glib::ffi::GError,
        ) -> i32,
    >,
    pub(super) lock_pointer: Option<unsafe extern "C" fn(*mut WpeView) -> i32>,
    pub(super) unlock_pointer: Option<unsafe extern "C" fn(*mut WpeView) -> i32>,
    pub(super) set_cursor_from_name: Option<unsafe extern "C" fn(*mut WpeView, *const c_char)>,
    pub(super) set_cursor_from_bytes:
        Option<unsafe extern "C" fn(*mut WpeView, *mut glib::ffi::GBytes, u32, u32, u32, u32, u32)>,
    pub(super) set_opaque_rectangles:
        Option<unsafe extern "C" fn(*mut WpeView, *mut WpeRectangle, u32)>,
    pub(super) can_be_mapped: Option<unsafe extern "C" fn(*mut WpeView) -> i32>,
    pub(super) get_accessible: Option<unsafe extern "C" fn(*mut WpeView) -> *mut WpeViewAccessible>,
    pub(super) padding: [*mut c_void; 32],
}

#[repr(C)]
pub(super) struct AtkObject {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct AtkSocket {
    pub(super) _opaque: [u8; 0],
}

// ATK deliberately publishes these instance layouts. Only the final
// `embedded_plug_id` field is read, after `atk_socket_is_occupied` confirms the
// object is an AtkSocket. Mirroring the public C prefix avoids relying on an
// undocumented symbol to discover the remote AT-SPI object.
#[repr(C)]
pub(super) struct GTypeInstanceLayout {
    pub(super) class: *mut c_void,
}

#[repr(C)]
pub(super) struct GObjectLayout {
    pub(super) type_instance: GTypeInstanceLayout,
    pub(super) reference_count: u32,
    pub(super) qdata: *mut c_void,
}

#[repr(C)]
pub(super) struct AtkObjectLayout {
    pub(super) parent: GObjectLayout,
    pub(super) description: *mut c_char,
    pub(super) name: *mut c_char,
    pub(super) accessible_parent: *mut AtkObject,
    pub(super) role: i32,
    pub(super) relation_set: *mut c_void,
    pub(super) layer: i32,
}

#[repr(C)]
pub(super) struct AtkSocketLayout {
    pub(super) parent: AtkObjectLayout,
    pub(super) embedded_plug_id: *mut c_char,
}

#[repr(C)]
pub(super) struct WpeClipboardContent {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitWebView {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitWebResource {
    pub(super) _opaque: [u8; 0],
}

/// Public instance prefix declared by `WebKitInputMethodContext.h`.
///
/// Unlike most WebKit types used here, this one is not opaque because the
/// Flutter adapter subclasses it. The two fields exactly match
/// `WEBKIT_DECLARE_DERIVABLE_TYPE`: a `GObject` followed by WebKit's private
/// pointer. Adapter-owned fields are appended in [`FlutterInputMethodContext`].
#[repr(C)]
pub(super) struct WebKitInputMethodContext {
    pub(super) parent_instance: glib::gobject_ffi::GObject,
    pub(super) priv_: *mut c_void,
}

/// Virtual-function table published for `WebKitInputMethodContext`.
///
/// GLib copies the parent portion into the subclass class allocation before
/// [`flutter_input_method_class_init`] runs. Keeping every reserved slot is
/// important: the registered class size must match the ABI used by WebKit.
#[repr(C)]
pub(super) struct WebKitInputMethodContextClass {
    pub(super) parent_class: glib::gobject_ffi::GObjectClass,
    pub(super) preedit_started: Option<unsafe extern "C" fn(*mut WebKitInputMethodContext)>,
    pub(super) preedit_changed: Option<unsafe extern "C" fn(*mut WebKitInputMethodContext)>,
    pub(super) preedit_finished: Option<unsafe extern "C" fn(*mut WebKitInputMethodContext)>,
    pub(super) committed:
        Option<unsafe extern "C" fn(*mut WebKitInputMethodContext, *const c_char)>,
    pub(super) delete_surrounding:
        Option<unsafe extern "C" fn(*mut WebKitInputMethodContext, i32, u32)>,
    pub(super) set_enable_preedit: Option<unsafe extern "C" fn(*mut WebKitInputMethodContext, i32)>,
    pub(super) get_preedit: Option<
        unsafe extern "C" fn(
            *mut WebKitInputMethodContext,
            *mut *mut c_char,
            *mut *mut glib::ffi::GList,
            *mut u32,
        ),
    >,
    pub(super) filter_key_event:
        Option<unsafe extern "C" fn(*mut WebKitInputMethodContext, *mut c_void) -> i32>,
    pub(super) notify_focus_in: Option<unsafe extern "C" fn(*mut WebKitInputMethodContext)>,
    pub(super) notify_focus_out: Option<unsafe extern "C" fn(*mut WebKitInputMethodContext)>,
    pub(super) notify_cursor_area:
        Option<unsafe extern "C" fn(*mut WebKitInputMethodContext, i32, i32, i32, i32)>,
    pub(super) notify_surrounding:
        Option<unsafe extern "C" fn(*mut WebKitInputMethodContext, *const c_char, u32, u32, u32)>,
    pub(super) reset: Option<unsafe extern "C" fn(*mut WebKitInputMethodContext)>,
    pub(super) reserved: [Option<unsafe extern "C" fn()>; 16],
}

/// Concrete, toolkit-free input-method context installed on one WebView.
///
/// WebKit invokes the parent virtual methods when an editable element gains
/// focus or changes its surrounding text. Dart drives the opposite direction
/// by replacing `preedit_text` and emitting the standard parent signals. The
/// boxed weak owner avoids a reference cycle and is released by the GObject
/// finalizer.
#[repr(C)]
pub(super) struct FlutterInputMethodContext {
    pub(super) parent_instance: WebKitInputMethodContext,
    pub(super) owner: *mut Weak<NativeView>,
    pub(super) preedit_text: *mut c_char,
    pub(super) preedit_cursor_offset: u32,
    pub(super) preedit_enabled: i32,
    pub(super) preedit_active: i32,
}

#[repr(C)]
pub(super) struct WebKitNetworkSession {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitWebContext {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitWebProcessExtension {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitWebPage {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitScriptWorld {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitFrame {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct JSCContext {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitUserMessage {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitGeolocationManager {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitGeolocationPosition {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitDownload {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitWebsiteDataManager {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitCookieManager {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitScriptDialog {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitPermissionRequest {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitNotification {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitPermissionStateQuery {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitSecurityOrigin {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitAuthenticationRequest {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitFileChooserRequest {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitOptionMenu {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitOptionMenuItem {
    pub(super) _opaque: [u8; 0],
}

/// Stable WPE rectangle ABI used by `show-option-menu`.
#[repr(C)]
pub(super) struct WebKitRectangle {
    pub(super) x: i32,
    pub(super) y: i32,
    pub(super) width: i32,
    pub(super) height: i32,
}

#[repr(C)]
pub(super) struct WebKitCredential {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct GTlsCertificate {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitUserMediaPermissionRequest {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct SoupCookie {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitSettings {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitFeature {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitFeatureList {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitUserContentManager {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitUserScript {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitUserStyleSheet {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitResponsePolicyDecision {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitURIResponse {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitPolicyDecision {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitWebsitePolicies {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitNavigationPolicyDecision {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitNavigationAction {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitURIRequest {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitWebViewSessionState {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitBackForwardList {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitBackForwardListItem {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct SoupMessageHeaders {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitColor {
    pub(super) red: f64,
    pub(super) green: f64,
    pub(super) blue: f64,
    pub(super) alpha: f64,
}

#[repr(C)]
pub(super) struct GAsyncResult {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct JSCValue {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitContextMenu {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct WebKitContextMenuItem {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct GAction {
    pub(super) _opaque: [u8; 0],
}

#[repr(C)]
pub(super) struct GVariant {
    pub(super) _opaque: [u8; 0],
}

unsafe extern "C" {
    // Constructors returning transfer-full GObjects are wrapped immediately in
    // glib ownership or explicitly unref'd on failure. All `get_*` functions
    // below return transfer-none pointers tied to their parent object.
    pub(super) fn wpe_display_headless_new() -> *mut WpeDisplay;
    pub(super) fn wpe_view_headless_get_type() -> glib::ffi::GType;
    pub(super) fn wpe_display_set_available_input_devices(display: *mut WpeDisplay, devices: u32);
    pub(super) fn wpe_toplevel_get_size(
        toplevel: *mut WpeToplevel,
        width: *mut i32,
        height: *mut i32,
    );
    pub(super) fn wpe_toplevel_get_scale(toplevel: *mut WpeToplevel) -> f64;
    pub(super) fn wpe_toplevel_scale_changed(toplevel: *mut WpeToplevel, scale: f64);
    pub(super) fn wpe_display_get_clipboard(display: *mut WpeDisplay) -> *mut WpeClipboard;
    pub(super) fn wpe_clipboard_get_change_count(clipboard: *mut WpeClipboard) -> i64;
    pub(super) fn wpe_clipboard_get_formats(clipboard: *mut WpeClipboard) -> *const *const c_char;
    pub(super) fn wpe_clipboard_set_content(
        clipboard: *mut WpeClipboard,
        content: *mut WpeClipboardContent,
    );
    pub(super) fn wpe_clipboard_read_bytes(
        clipboard: *mut WpeClipboard,
        format: *const c_char,
    ) -> *mut glib::ffi::GBytes;
    pub(super) fn wpe_clipboard_read_text(
        clipboard: *mut WpeClipboard,
        format: *const c_char,
        size: *mut usize,
    ) -> *mut c_char;
    pub(super) fn wpe_clipboard_content_new() -> *mut WpeClipboardContent;
    pub(super) fn wpe_clipboard_content_unref(content: *mut WpeClipboardContent);
    pub(super) fn wpe_clipboard_content_set_text(
        content: *mut WpeClipboardContent,
        text: *const c_char,
    );
    pub(super) fn wpe_clipboard_content_set_bytes(
        content: *mut WpeClipboardContent,
        format: *const c_char,
        bytes: *mut glib::ffi::GBytes,
    );
    pub(super) fn webkit_settings_new() -> *mut WebKitSettings;
    pub(super) fn webkit_network_session_get_default() -> *mut WebKitNetworkSession;
    pub(super) fn webkit_web_context_get_default() -> *mut WebKitWebContext;
    pub(super) fn webkit_web_context_add_path_to_sandbox(
        context: *mut WebKitWebContext,
        path: *const c_char,
        read_only: i32,
    );
    pub(super) fn webkit_web_context_set_web_process_extensions_directory(
        context: *mut WebKitWebContext,
        directory: *const c_char,
    );
    pub(super) fn webkit_user_message_new(
        name: *const c_char,
        parameters: *mut glib::ffi::GVariant,
    ) -> *mut WebKitUserMessage;
    pub(super) fn webkit_user_message_get_name(message: *mut WebKitUserMessage) -> *const c_char;
    pub(super) fn webkit_user_message_get_parameters(
        message: *mut WebKitUserMessage,
    ) -> *mut glib::ffi::GVariant;
    pub(super) fn webkit_user_message_send_reply(
        message: *mut WebKitUserMessage,
        reply: *mut WebKitUserMessage,
    );
    pub(super) fn webkit_web_page_send_message_to_view(
        page: *mut WebKitWebPage,
        message: *mut WebKitUserMessage,
        cancellable: *mut c_void,
        callback: Option<
            unsafe extern "C" fn(*mut glib::gobject_ffi::GObject, *mut GAsyncResult, *mut c_void),
        >,
        user_data: *mut c_void,
    );
    pub(super) fn webkit_web_page_send_message_to_view_finish(
        page: *mut WebKitWebPage,
        result: *mut GAsyncResult,
        error: *mut *mut glib::ffi::GError,
    ) -> *mut WebKitUserMessage;
    pub(super) fn webkit_script_world_new_with_name(name: *const c_char) -> *mut WebKitScriptWorld;
    pub(super) fn webkit_frame_is_main_frame(frame: *mut WebKitFrame) -> i32;
    pub(super) fn webkit_frame_get_js_context_for_script_world(
        frame: *mut WebKitFrame,
        world: *mut WebKitScriptWorld,
    ) -> *mut JSCContext;
    pub(super) fn jsc_value_new_functionv(
        context: *mut JSCContext,
        name: *const c_char,
        callback: Option<unsafe extern "C" fn(i32, *const c_char, *mut c_void)>,
        user_data: *mut c_void,
        destroy_notify: Option<unsafe extern "C" fn(*mut c_void)>,
        return_type: glib::ffi::GType,
        parameter_count: u32,
        parameter_types: *mut glib::ffi::GType,
    ) -> *mut JSCValue;
    pub(super) fn jsc_context_set_value(
        context: *mut JSCContext,
        name: *const c_char,
        value: *mut JSCValue,
    );
    pub(super) fn jsc_context_evaluate(
        context: *mut JSCContext,
        code: *const c_char,
        length: isize,
    ) -> *mut JSCValue;
    pub(super) fn webkit_web_context_get_geolocation_manager(
        context: *mut WebKitWebContext,
    ) -> *mut WebKitGeolocationManager;
    pub(super) fn webkit_geolocation_manager_update_position(
        manager: *mut WebKitGeolocationManager,
        position: *mut WebKitGeolocationPosition,
    );
    pub(super) fn webkit_geolocation_manager_failed(
        manager: *mut WebKitGeolocationManager,
        error_message: *const c_char,
    );
    pub(super) fn webkit_geolocation_manager_get_enable_high_accuracy(
        manager: *mut WebKitGeolocationManager,
    ) -> i32;
    pub(super) fn webkit_geolocation_position_new(
        latitude: f64,
        longitude: f64,
        accuracy: f64,
    ) -> *mut WebKitGeolocationPosition;
    pub(super) fn webkit_geolocation_position_free(position: *mut WebKitGeolocationPosition);
    pub(super) fn webkit_geolocation_position_set_timestamp(
        position: *mut WebKitGeolocationPosition,
        timestamp: u64,
    );
    pub(super) fn webkit_geolocation_position_set_altitude(
        position: *mut WebKitGeolocationPosition,
        altitude: f64,
    );
    pub(super) fn webkit_geolocation_position_set_altitude_accuracy(
        position: *mut WebKitGeolocationPosition,
        altitude_accuracy: f64,
    );
    pub(super) fn webkit_geolocation_position_set_heading(
        position: *mut WebKitGeolocationPosition,
        heading: f64,
    );
    pub(super) fn webkit_geolocation_position_set_speed(
        position: *mut WebKitGeolocationPosition,
        speed: f64,
    );
    pub(super) fn webkit_download_get_request(
        download: *mut WebKitDownload,
    ) -> *mut WebKitURIRequest;
    pub(super) fn webkit_download_get_response(
        download: *mut WebKitDownload,
    ) -> *mut WebKitURIResponse;
    pub(super) fn webkit_download_get_web_view(download: *mut WebKitDownload)
    -> *mut WebKitWebView;
    pub(super) fn webkit_download_get_destination(download: *mut WebKitDownload) -> *const c_char;
    pub(super) fn webkit_download_set_destination(
        download: *mut WebKitDownload,
        destination: *const c_char,
    );
    pub(super) fn webkit_download_set_allow_overwrite(download: *mut WebKitDownload, allowed: i32);
    pub(super) fn webkit_download_cancel(download: *mut WebKitDownload);
    pub(super) fn webkit_download_get_received_data_length(download: *mut WebKitDownload) -> u64;
    pub(super) fn webkit_web_view_get_type() -> glib::ffi::GType;
    pub(super) fn webkit_web_view_get_display(web_view: *mut WebKitWebView) -> *mut WpeDisplay;
    pub(super) fn webkit_web_view_get_wpe_view(web_view: *mut WebKitWebView) -> *mut WpeView;
    pub(super) fn webkit_web_view_get_settings(web_view: *mut WebKitWebView)
    -> *mut WebKitSettings;
    pub(super) fn webkit_web_view_get_network_session(
        web_view: *mut WebKitWebView,
    ) -> *mut WebKitNetworkSession;
    pub(super) fn webkit_web_view_get_user_content_manager(
        web_view: *mut WebKitWebView,
    ) -> *mut WebKitUserContentManager;
    pub(super) fn webkit_web_view_get_uri(web_view: *mut WebKitWebView) -> *const c_char;
    pub(super) fn webkit_web_view_get_title(web_view: *mut WebKitWebView) -> *const c_char;
    pub(super) fn webkit_web_view_get_main_resource(
        web_view: *mut WebKitWebView,
    ) -> *mut WebKitWebResource;
    pub(super) fn webkit_web_resource_get_uri(resource: *mut WebKitWebResource) -> *const c_char;
    pub(super) fn webkit_web_view_get_estimated_load_progress(web_view: *mut WebKitWebView) -> f64;
    pub(super) fn webkit_web_view_set_input_method_context(
        web_view: *mut WebKitWebView,
        context: *mut WebKitInputMethodContext,
    );
    pub(super) fn webkit_web_view_set_is_muted(web_view: *mut WebKitWebView, muted: i32);
    pub(super) fn webkit_web_view_load_uri(web_view: *mut WebKitWebView, uri: *const c_char);
    pub(super) fn webkit_web_view_load_html(
        web_view: *mut WebKitWebView,
        content: *const c_char,
        base_uri: *const c_char,
    );
    pub(super) fn webkit_web_view_load_request(
        web_view: *mut WebKitWebView,
        request: *mut WebKitURIRequest,
    );
    pub(super) fn webkit_web_view_terminate_web_process(web_view: *mut WebKitWebView);
    pub(super) fn webkit_web_view_can_go_back(web_view: *mut WebKitWebView) -> i32;
    pub(super) fn webkit_web_view_can_go_forward(web_view: *mut WebKitWebView) -> i32;
    pub(super) fn webkit_web_view_go_back(web_view: *mut WebKitWebView);
    pub(super) fn webkit_web_view_go_forward(web_view: *mut WebKitWebView);
    pub(super) fn webkit_web_view_reload(web_view: *mut WebKitWebView);
    pub(super) fn webkit_web_view_get_session_state(
        web_view: *mut WebKitWebView,
    ) -> *mut WebKitWebViewSessionState;
    pub(super) fn webkit_web_view_restore_session_state(
        web_view: *mut WebKitWebView,
        state: *mut WebKitWebViewSessionState,
    );
    pub(super) fn webkit_web_view_session_state_new(
        data: *mut glib::ffi::GBytes,
    ) -> *mut WebKitWebViewSessionState;
    pub(super) fn webkit_web_view_session_state_serialize(
        state: *mut WebKitWebViewSessionState,
    ) -> *mut glib::ffi::GBytes;
    pub(super) fn webkit_web_view_session_state_unref(state: *mut WebKitWebViewSessionState);
    pub(super) fn webkit_web_view_get_back_forward_list(
        web_view: *mut WebKitWebView,
    ) -> *mut WebKitBackForwardList;
    pub(super) fn webkit_back_forward_list_get_current_item(
        list: *mut WebKitBackForwardList,
    ) -> *mut WebKitBackForwardListItem;
    pub(super) fn webkit_web_view_go_to_back_forward_list_item(
        web_view: *mut WebKitWebView,
        item: *mut WebKitBackForwardListItem,
    );
    pub(super) fn webkit_input_method_context_get_type() -> glib::ffi::GType;
    pub(super) fn webkit_input_method_context_get_input_purpose(
        context: *mut WebKitInputMethodContext,
    ) -> i32;
    pub(super) fn webkit_input_method_context_get_input_hints(
        context: *mut WebKitInputMethodContext,
    ) -> u32;
    pub(super) fn webkit_input_method_context_notify_focus_in(
        context: *mut WebKitInputMethodContext,
    );
    pub(super) fn webkit_input_method_context_notify_focus_out(
        context: *mut WebKitInputMethodContext,
    );
    pub(super) fn webkit_uri_request_new(uri: *const c_char) -> *mut WebKitURIRequest;
    pub(super) fn webkit_uri_request_get_uri(request: *mut WebKitURIRequest) -> *const c_char;
    pub(super) fn webkit_uri_request_get_http_method(
        request: *mut WebKitURIRequest,
    ) -> *const c_char;
    pub(super) fn webkit_uri_request_get_http_headers(
        request: *mut WebKitURIRequest,
    ) -> *mut SoupMessageHeaders;
    pub(super) fn soup_message_headers_replace(
        headers: *mut SoupMessageHeaders,
        name: *const c_char,
        value: *const c_char,
    );
    pub(super) fn soup_message_headers_get_one(
        headers: *mut SoupMessageHeaders,
        name: *const c_char,
    ) -> *const c_char;
    pub(super) fn soup_message_headers_remove(
        headers: *mut SoupMessageHeaders,
        name: *const c_char,
    );
    pub(super) fn webkit_web_view_evaluate_javascript(
        web_view: *mut WebKitWebView,
        script: *const c_char,
        length: isize,
        world_name: *const c_char,
        source_uri: *const c_char,
        cancellable: *mut c_void,
        callback: Option<
            unsafe extern "C" fn(*mut glib::gobject_ffi::GObject, *mut GAsyncResult, *mut c_void),
        >,
        user_data: *mut c_void,
    );
    pub(super) fn webkit_web_view_evaluate_javascript_finish(
        web_view: *mut WebKitWebView,
        result: *mut GAsyncResult,
        error: *mut *mut glib::ffi::GError,
    ) -> *mut JSCValue;
    pub(super) fn webkit_javascript_error_quark() -> glib::ffi::GQuark;
    pub(super) fn jsc_value_is_undefined(value: *mut JSCValue) -> i32;
    pub(super) fn jsc_value_is_null(value: *mut JSCValue) -> i32;
    pub(super) fn jsc_value_to_string(value: *mut JSCValue) -> *mut c_char;
    pub(super) fn jsc_value_to_json(value: *mut JSCValue, indent: u32) -> *mut c_char;
    pub(super) fn webkit_user_content_manager_new() -> *mut WebKitUserContentManager;
    pub(super) fn webkit_user_content_manager_register_script_message_handler(
        manager: *mut WebKitUserContentManager,
        name: *const c_char,
        world_name: *const c_char,
    ) -> i32;
    pub(super) fn webkit_user_content_manager_unregister_script_message_handler(
        manager: *mut WebKitUserContentManager,
        name: *const c_char,
        world_name: *const c_char,
    );
    pub(super) fn webkit_user_content_manager_add_script(
        manager: *mut WebKitUserContentManager,
        script: *mut WebKitUserScript,
    );
    pub(super) fn webkit_user_content_manager_remove_script(
        manager: *mut WebKitUserContentManager,
        script: *mut WebKitUserScript,
    );
    pub(super) fn webkit_user_content_manager_add_style_sheet(
        manager: *mut WebKitUserContentManager,
        style_sheet: *mut WebKitUserStyleSheet,
    );
    pub(super) fn webkit_user_content_manager_remove_style_sheet(
        manager: *mut WebKitUserContentManager,
        style_sheet: *mut WebKitUserStyleSheet,
    );
    pub(super) fn webkit_user_script_new(
        source: *const c_char,
        injected_frames: i32,
        injection_time: i32,
        allow_list: *const *const c_char,
        block_list: *const *const c_char,
    ) -> *mut WebKitUserScript;
    pub(super) fn webkit_user_script_new_for_world(
        source: *const c_char,
        injected_frames: i32,
        injection_time: i32,
        world_name: *const c_char,
        allow_list: *const *const c_char,
        block_list: *const *const c_char,
    ) -> *mut WebKitUserScript;
    pub(super) fn webkit_user_script_unref(script: *mut WebKitUserScript);
    pub(super) fn webkit_user_style_sheet_new(
        source: *const c_char,
        injected_frames: i32,
        level: i32,
        allow_list: *const *const c_char,
        block_list: *const *const c_char,
    ) -> *mut WebKitUserStyleSheet;
    pub(super) fn webkit_user_style_sheet_unref(style_sheet: *mut WebKitUserStyleSheet);
    pub(super) fn webkit_response_policy_decision_get_response(
        decision: *mut WebKitResponsePolicyDecision,
    ) -> *mut WebKitURIResponse;
    pub(super) fn webkit_response_policy_decision_get_request(
        decision: *mut WebKitResponsePolicyDecision,
    ) -> *mut WebKitURIRequest;
    pub(super) fn webkit_response_policy_decision_is_main_frame_main_resource(
        decision: *mut WebKitResponsePolicyDecision,
    ) -> i32;
    pub(super) fn webkit_uri_response_get_uri(response: *mut WebKitURIResponse) -> *const c_char;
    pub(super) fn webkit_uri_response_get_status_code(response: *mut WebKitURIResponse) -> u32;
    pub(super) fn webkit_uri_response_get_content_length(response: *mut WebKitURIResponse) -> i64;
    pub(super) fn webkit_uri_response_get_mime_type(
        response: *mut WebKitURIResponse,
    ) -> *const c_char;
    pub(super) fn webkit_navigation_policy_decision_get_navigation_action(
        decision: *mut WebKitNavigationPolicyDecision,
    ) -> *mut WebKitNavigationAction;
    pub(super) fn webkit_navigation_action_get_request(
        action: *mut WebKitNavigationAction,
    ) -> *mut WebKitURIRequest;
    pub(super) fn webkit_navigation_action_is_redirect(action: *mut WebKitNavigationAction) -> i32;
    pub(super) fn webkit_policy_decision_use(decision: *mut WebKitPolicyDecision);
    pub(super) fn webkit_policy_decision_use_with_policies(
        decision: *mut WebKitPolicyDecision,
        policies: *mut WebKitWebsitePolicies,
    );
    pub(super) fn webkit_policy_decision_ignore(decision: *mut WebKitPolicyDecision);
    pub(super) fn webkit_website_policies_new_with_policies(
        first_policy_name: *const c_char,
        ...
    ) -> *mut WebKitWebsitePolicies;
    pub(super) fn webkit_web_view_set_zoom_level(web_view: *mut WebKitWebView, zoom_level: f64);
    pub(super) fn webkit_web_view_get_zoom_level(web_view: *mut WebKitWebView) -> f64;
    pub(super) fn webkit_settings_set_zoom_text_only(
        settings: *mut WebKitSettings,
        zoom_text_only: i32,
    );
    pub(super) fn webkit_settings_get_zoom_text_only(settings: *mut WebKitSettings) -> i32;
    pub(super) fn webkit_web_view_set_background_color(
        web_view: *mut WebKitWebView,
        color: *const WebKitColor,
    );
    pub(super) fn webkit_script_dialog_ref(
        dialog: *mut WebKitScriptDialog,
    ) -> *mut WebKitScriptDialog;
    pub(super) fn webkit_script_dialog_unref(dialog: *mut WebKitScriptDialog);
    pub(super) fn webkit_script_dialog_get_dialog_type(dialog: *mut WebKitScriptDialog) -> i32;
    pub(super) fn webkit_script_dialog_get_message(
        dialog: *mut WebKitScriptDialog,
    ) -> *const c_char;
    pub(super) fn webkit_script_dialog_confirm_set_confirmed(
        dialog: *mut WebKitScriptDialog,
        confirmed: i32,
    );
    pub(super) fn webkit_script_dialog_prompt_get_default_text(
        dialog: *mut WebKitScriptDialog,
    ) -> *const c_char;
    pub(super) fn webkit_script_dialog_prompt_set_text(
        dialog: *mut WebKitScriptDialog,
        text: *const c_char,
    );
    pub(super) fn webkit_script_dialog_close(dialog: *mut WebKitScriptDialog);
    pub(super) fn webkit_permission_request_allow(request: *mut WebKitPermissionRequest);
    pub(super) fn webkit_permission_request_deny(request: *mut WebKitPermissionRequest);
    pub(super) fn webkit_notification_get_title(
        notification: *mut WebKitNotification,
    ) -> *const c_char;
    pub(super) fn webkit_notification_get_body(
        notification: *mut WebKitNotification,
    ) -> *const c_char;
    pub(super) fn webkit_notification_get_tag(
        notification: *mut WebKitNotification,
    ) -> *const c_char;
    pub(super) fn webkit_notification_close(notification: *mut WebKitNotification);
    pub(super) fn webkit_notification_clicked(notification: *mut WebKitNotification);
    pub(super) fn webkit_permission_state_query_get_name(
        query: *mut WebKitPermissionStateQuery,
    ) -> *const c_char;
    pub(super) fn webkit_permission_state_query_get_security_origin(
        query: *mut WebKitPermissionStateQuery,
    ) -> *mut WebKitSecurityOrigin;
    pub(super) fn webkit_permission_state_query_finish(
        query: *mut WebKitPermissionStateQuery,
        state: i32,
    );
    pub(super) fn webkit_security_origin_new_for_uri(
        uri: *const c_char,
    ) -> *mut WebKitSecurityOrigin;
    pub(super) fn webkit_security_origin_to_string(
        origin: *mut WebKitSecurityOrigin,
    ) -> *mut c_char;
    pub(super) fn webkit_security_origin_unref(origin: *mut WebKitSecurityOrigin);
    pub(super) fn webkit_authentication_request_get_host(
        request: *mut WebKitAuthenticationRequest,
    ) -> *const c_char;
    pub(super) fn webkit_authentication_request_get_realm(
        request: *mut WebKitAuthenticationRequest,
    ) -> *const c_char;
    pub(super) fn webkit_authentication_request_get_scheme(
        request: *mut WebKitAuthenticationRequest,
    ) -> i32;
    pub(super) fn webkit_authentication_request_authenticate(
        request: *mut WebKitAuthenticationRequest,
        credential: *mut WebKitCredential,
    );
    pub(super) fn webkit_authentication_request_cancel(request: *mut WebKitAuthenticationRequest);
    pub(super) fn webkit_file_chooser_request_get_mime_types(
        request: *mut WebKitFileChooserRequest,
    ) -> *const *const c_char;
    pub(super) fn webkit_file_chooser_request_get_select_multiple(
        request: *mut WebKitFileChooserRequest,
    ) -> i32;
    pub(super) fn webkit_file_chooser_request_get_selected_files(
        request: *mut WebKitFileChooserRequest,
    ) -> *const *const c_char;
    pub(super) fn webkit_file_chooser_request_select_files(
        request: *mut WebKitFileChooserRequest,
        files: *const *const c_char,
    );
    pub(super) fn webkit_file_chooser_request_cancel(request: *mut WebKitFileChooserRequest);
    pub(super) fn webkit_option_menu_get_n_items(menu: *mut WebKitOptionMenu) -> u32;
    pub(super) fn webkit_option_menu_get_item(
        menu: *mut WebKitOptionMenu,
        index: u32,
    ) -> *mut WebKitOptionMenuItem;
    pub(super) fn webkit_option_menu_activate_item(menu: *mut WebKitOptionMenu, index: u32);
    pub(super) fn webkit_option_menu_close(menu: *mut WebKitOptionMenu);
    pub(super) fn webkit_option_menu_item_get_label(
        item: *mut WebKitOptionMenuItem,
    ) -> *const c_char;
    pub(super) fn webkit_option_menu_item_get_tooltip(
        item: *mut WebKitOptionMenuItem,
    ) -> *const c_char;
    pub(super) fn webkit_option_menu_item_is_group_label(item: *mut WebKitOptionMenuItem) -> i32;
    pub(super) fn webkit_option_menu_item_is_group_child(item: *mut WebKitOptionMenuItem) -> i32;
    pub(super) fn webkit_option_menu_item_is_enabled(item: *mut WebKitOptionMenuItem) -> i32;
    pub(super) fn webkit_option_menu_item_is_selected(item: *mut WebKitOptionMenuItem) -> i32;
    pub(super) fn webkit_credential_new(
        username: *const c_char,
        password: *const c_char,
        persistence: i32,
    ) -> *mut WebKitCredential;
    pub(super) fn webkit_credential_free(credential: *mut WebKitCredential);
    pub(super) fn webkit_user_media_permission_request_get_type() -> glib::ffi::GType;
    pub(super) fn webkit_geolocation_permission_request_get_type() -> glib::ffi::GType;
    pub(super) fn webkit_notification_permission_request_get_type() -> glib::ffi::GType;
    pub(super) fn webkit_device_info_permission_request_get_type() -> glib::ffi::GType;
    pub(super) fn webkit_media_key_system_permission_request_get_type() -> glib::ffi::GType;
    pub(super) fn webkit_website_data_access_permission_request_get_type() -> glib::ffi::GType;
    pub(super) fn webkit_xr_permission_request_get_type() -> glib::ffi::GType;
    pub(super) fn webkit_user_media_permission_is_for_audio_device(
        request: *mut WebKitUserMediaPermissionRequest,
    ) -> i32;
    pub(super) fn webkit_user_media_permission_is_for_video_device(
        request: *mut WebKitUserMediaPermissionRequest,
    ) -> i32;
    pub(super) fn webkit_user_media_permission_is_for_display_device(
        request: *mut WebKitUserMediaPermissionRequest,
    ) -> i32;
    pub(super) fn webkit_network_session_get_website_data_manager(
        session: *mut WebKitNetworkSession,
    ) -> *mut WebKitWebsiteDataManager;
    pub(super) fn webkit_network_session_is_ephemeral(session: *mut WebKitNetworkSession) -> i32;
    pub(super) fn webkit_network_session_get_cookie_manager(
        session: *mut WebKitNetworkSession,
    ) -> *mut WebKitCookieManager;
    pub(super) fn webkit_network_session_set_itp_enabled(
        session: *mut WebKitNetworkSession,
        enabled: i32,
    );
    pub(super) fn webkit_network_session_get_itp_enabled(session: *mut WebKitNetworkSession)
    -> i32;
    pub(super) fn webkit_network_session_allow_tls_certificate_for_host(
        session: *mut WebKitNetworkSession,
        certificate: *mut GTlsCertificate,
        host: *const c_char,
    );
    pub(super) fn webkit_website_data_manager_get_base_data_directory(
        manager: *mut WebKitWebsiteDataManager,
    ) -> *const c_char;
    pub(super) fn webkit_website_data_manager_clear(
        manager: *mut WebKitWebsiteDataManager,
        types: u32,
        timespan: i64,
        cancellable: *mut c_void,
        callback: Option<
            unsafe extern "C" fn(*mut glib::gobject_ffi::GObject, *mut GAsyncResult, *mut c_void),
        >,
        user_data: *mut c_void,
    );
    pub(super) fn webkit_website_data_manager_clear_finish(
        manager: *mut WebKitWebsiteDataManager,
        result: *mut GAsyncResult,
        error: *mut *mut glib::ffi::GError,
    ) -> i32;
    pub(super) fn webkit_cookie_manager_add_cookie(
        manager: *mut WebKitCookieManager,
        cookie: *mut SoupCookie,
        cancellable: *mut c_void,
        callback: Option<
            unsafe extern "C" fn(*mut glib::gobject_ffi::GObject, *mut GAsyncResult, *mut c_void),
        >,
        user_data: *mut c_void,
    );
    pub(super) fn webkit_cookie_manager_add_cookie_finish(
        manager: *mut WebKitCookieManager,
        result: *mut GAsyncResult,
        error: *mut *mut glib::ffi::GError,
    ) -> i32;
    pub(super) fn webkit_cookie_manager_get_cookies(
        manager: *mut WebKitCookieManager,
        uri: *const c_char,
        cancellable: *mut c_void,
        callback: Option<
            unsafe extern "C" fn(*mut glib::gobject_ffi::GObject, *mut GAsyncResult, *mut c_void),
        >,
        user_data: *mut c_void,
    );
    pub(super) fn webkit_cookie_manager_get_cookies_finish(
        manager: *mut WebKitCookieManager,
        result: *mut GAsyncResult,
        error: *mut *mut glib::ffi::GError,
    ) -> *mut glib::ffi::GList;
    pub(super) fn webkit_cookie_manager_get_all_cookies(
        manager: *mut WebKitCookieManager,
        cancellable: *mut c_void,
        callback: Option<
            unsafe extern "C" fn(*mut glib::gobject_ffi::GObject, *mut GAsyncResult, *mut c_void),
        >,
        user_data: *mut c_void,
    );
    pub(super) fn webkit_cookie_manager_get_all_cookies_finish(
        manager: *mut WebKitCookieManager,
        result: *mut GAsyncResult,
        error: *mut *mut glib::ffi::GError,
    ) -> *mut glib::ffi::GList;
    pub(super) fn webkit_cookie_manager_delete_cookie(
        manager: *mut WebKitCookieManager,
        cookie: *mut SoupCookie,
        cancellable: *mut c_void,
        callback: Option<
            unsafe extern "C" fn(*mut glib::gobject_ffi::GObject, *mut GAsyncResult, *mut c_void),
        >,
        user_data: *mut c_void,
    );
    pub(super) fn webkit_cookie_manager_delete_cookie_finish(
        manager: *mut WebKitCookieManager,
        result: *mut GAsyncResult,
        error: *mut *mut glib::ffi::GError,
    ) -> i32;
    pub(super) fn webkit_cookie_manager_set_persistent_storage(
        manager: *mut WebKitCookieManager,
        filename: *const c_char,
        storage: i32,
    );
    pub(super) fn webkit_cookie_manager_set_accept_policy(
        manager: *mut WebKitCookieManager,
        policy: i32,
    );
    pub(super) fn webkit_cookie_manager_get_accept_policy(
        manager: *mut WebKitCookieManager,
        cancellable: *mut c_void,
        callback: Option<
            unsafe extern "C" fn(*mut glib::gobject_ffi::GObject, *mut GAsyncResult, *mut c_void),
        >,
        user_data: *mut c_void,
    );
    pub(super) fn webkit_cookie_manager_get_accept_policy_finish(
        manager: *mut WebKitCookieManager,
        result: *mut GAsyncResult,
        error: *mut *mut glib::ffi::GError,
    ) -> i32;
    pub(super) fn soup_cookie_new(
        name: *const c_char,
        value: *const c_char,
        domain: *const c_char,
        path: *const c_char,
        max_age: i32,
    ) -> *mut SoupCookie;
    pub(super) fn soup_cookie_get_name(cookie: *mut SoupCookie) -> *const c_char;
    pub(super) fn soup_cookie_get_value(cookie: *mut SoupCookie) -> *const c_char;
    pub(super) fn soup_cookie_get_domain(cookie: *mut SoupCookie) -> *const c_char;
    pub(super) fn soup_cookie_get_path(cookie: *mut SoupCookie) -> *const c_char;
    pub(super) fn soup_cookie_free(cookie: *mut SoupCookie);
    pub(super) fn webkit_settings_get_enable_media(settings: *mut WebKitSettings) -> i32;
    pub(super) fn webkit_settings_set_enable_media(settings: *mut WebKitSettings, enabled: i32);
    pub(super) fn webkit_settings_get_enable_fullscreen(settings: *mut WebKitSettings) -> i32;
    pub(super) fn webkit_settings_set_enable_fullscreen(
        settings: *mut WebKitSettings,
        enabled: i32,
    );
    pub(super) fn webkit_settings_get_enable_javascript(settings: *mut WebKitSettings) -> i32;
    pub(super) fn webkit_settings_set_enable_javascript(
        settings: *mut WebKitSettings,
        enabled: i32,
    );
    pub(super) fn webkit_settings_get_enable_javascript_markup(
        settings: *mut WebKitSettings,
    ) -> i32;
    pub(super) fn webkit_settings_set_enable_javascript_markup(
        settings: *mut WebKitSettings,
        enabled: i32,
    );
    pub(super) fn webkit_settings_get_javascript_can_open_windows_automatically(
        settings: *mut WebKitSettings,
    ) -> i32;
    pub(super) fn webkit_settings_set_javascript_can_open_windows_automatically(
        settings: *mut WebKitSettings,
        enabled: i32,
    );
    pub(super) fn webkit_settings_get_javascript_can_access_clipboard(
        settings: *mut WebKitSettings,
    ) -> i32;
    pub(super) fn webkit_settings_set_javascript_can_access_clipboard(
        settings: *mut WebKitSettings,
        enabled: i32,
    );
    pub(super) fn webkit_settings_get_allow_file_access_from_file_urls(
        settings: *mut WebKitSettings,
    ) -> i32;
    pub(super) fn webkit_settings_set_allow_file_access_from_file_urls(
        settings: *mut WebKitSettings,
        allowed: i32,
    );
    pub(super) fn webkit_settings_get_user_agent(settings: *mut WebKitSettings) -> *const c_char;
    pub(super) fn webkit_settings_set_user_agent(
        settings: *mut WebKitSettings,
        user_agent: *const c_char,
    );
    pub(super) fn webkit_settings_get_enable_webaudio(settings: *mut WebKitSettings) -> i32;
    pub(super) fn webkit_settings_set_enable_webaudio(settings: *mut WebKitSettings, enabled: i32);
    pub(super) fn webkit_settings_get_enable_developer_extras(settings: *mut WebKitSettings)
    -> i32;
    pub(super) fn webkit_settings_set_enable_developer_extras(
        settings: *mut WebKitSettings,
        enabled: i32,
    );
    pub(super) fn webkit_settings_get_media_playback_requires_user_gesture(
        settings: *mut WebKitSettings,
    ) -> i32;
    pub(super) fn webkit_settings_set_media_playback_requires_user_gesture(
        settings: *mut WebKitSettings,
        enabled: i32,
    );
    pub(super) fn webkit_settings_get_media_playback_allows_inline(
        settings: *mut WebKitSettings,
    ) -> i32;
    pub(super) fn webkit_settings_set_media_playback_allows_inline(
        settings: *mut WebKitSettings,
        enabled: i32,
    );
    pub(super) fn webkit_settings_get_enable_webrtc(settings: *mut WebKitSettings) -> i32;
    pub(super) fn webkit_settings_set_enable_webrtc(settings: *mut WebKitSettings, enabled: i32);
    pub(super) fn webkit_settings_get_enable_mock_capture_devices(
        settings: *mut WebKitSettings,
    ) -> i32;
    pub(super) fn webkit_settings_set_enable_mock_capture_devices(
        settings: *mut WebKitSettings,
        enabled: i32,
    );
    pub(super) fn webkit_settings_get_enable_encrypted_media(settings: *mut WebKitSettings) -> i32;
    pub(super) fn webkit_settings_set_enable_encrypted_media(
        settings: *mut WebKitSettings,
        enabled: i32,
    );
    pub(super) fn webkit_settings_get_allow_universal_access_from_file_urls(
        settings: *mut WebKitSettings,
    ) -> i32;
    pub(super) fn webkit_settings_set_allow_universal_access_from_file_urls(
        settings: *mut WebKitSettings,
        allowed: i32,
    );
    pub(super) fn webkit_settings_get_all_features() -> *mut WebKitFeatureList;
    pub(super) fn webkit_feature_list_get_length(features: *mut WebKitFeatureList) -> usize;
    pub(super) fn webkit_feature_list_get(
        features: *mut WebKitFeatureList,
        index: usize,
    ) -> *mut WebKitFeature;
    pub(super) fn webkit_feature_list_unref(features: *mut WebKitFeatureList);
    pub(super) fn webkit_feature_get_identifier(feature: *mut WebKitFeature) -> *const c_char;
    pub(super) fn webkit_context_menu_get_n_items(menu: *mut WebKitContextMenu) -> u32;
    pub(super) fn webkit_context_menu_get_item_at_position(
        menu: *mut WebKitContextMenu,
        position: u32,
    ) -> *mut WebKitContextMenuItem;
    pub(super) fn webkit_context_menu_get_position(
        menu: *mut WebKitContextMenu,
        x: *mut i32,
        y: *mut i32,
    ) -> i32;
    pub(super) fn webkit_context_menu_item_get_title(
        item: *mut WebKitContextMenuItem,
    ) -> *const c_char;
    pub(super) fn webkit_context_menu_item_is_separator(item: *mut WebKitContextMenuItem) -> i32;
    pub(super) fn webkit_context_menu_item_get_gaction(
        item: *mut WebKitContextMenuItem,
    ) -> *mut GAction;
    pub(super) fn webkit_context_menu_item_get_gaction_target(
        item: *mut WebKitContextMenuItem,
    ) -> *mut GVariant;
    pub(super) fn webkit_context_menu_item_get_stock_action(
        item: *mut WebKitContextMenuItem,
    ) -> i32;
    pub(super) fn webkit_web_view_execute_editing_command(
        web_view: *mut WebKitWebView,
        command: *const c_char,
    );
    pub(super) fn g_action_get_enabled(action: *mut GAction) -> i32;
    pub(super) fn g_action_activate(action: *mut GAction, parameter: *mut GVariant);
    pub(super) fn g_variant_ref(value: *mut GVariant) -> *mut GVariant;
    pub(super) fn g_variant_unref(value: *mut GVariant);

    pub(super) fn wpe_view_get_toplevel(view: *mut WpeView) -> *mut WpeToplevel;
    pub(super) fn wpe_view_get_accessible(view: *mut WpeView) -> *mut WpeViewAccessible;
    pub(super) fn wpe_toplevel_resize(toplevel: *mut WpeToplevel, width: i32, height: i32) -> i32;
    pub(super) fn wpe_view_buffer_released(view: *mut WpeView, buffer: *mut WpeBuffer);
    pub(super) fn wpe_view_event(view: *mut WpeView, event: *mut WpeEvent);
    pub(super) fn wpe_view_focus_in(view: *mut WpeView);
    pub(super) fn wpe_view_focus_out(view: *mut WpeView);
    pub(super) fn wpe_view_set_visible(view: *mut WpeView, visible: i32);

    // WPE's UI-process object is an AtkSocket already bound to the web
    // process's AT-SPI plug. The socket itself has no local ATK children; its
    // public plug ID identifies the remote tree queried through GIO D-Bus.
    pub(super) fn atk_socket_is_occupied(socket: *mut AtkSocket) -> i32;

    pub(super) fn wpe_buffer_get_width(buffer: *mut WpeBuffer) -> i32;
    pub(super) fn wpe_buffer_get_height(buffer: *mut WpeBuffer) -> i32;
    pub(super) fn wpe_buffer_take_rendering_fence(buffer: *mut WpeBuffer) -> i32;
    pub(super) fn wpe_buffer_dma_buf_get_type() -> glib::ffi::GType;
    pub(super) fn wpe_buffer_dma_buf_get_format(buffer: *mut WpeBufferDmaBuf) -> u32;
    pub(super) fn wpe_buffer_dma_buf_get_n_planes(buffer: *mut WpeBufferDmaBuf) -> u32;
    pub(super) fn wpe_buffer_dma_buf_get_fd(buffer: *mut WpeBufferDmaBuf, plane: u32) -> i32;
    pub(super) fn wpe_buffer_dma_buf_get_offset(buffer: *mut WpeBufferDmaBuf, plane: u32) -> u32;
    pub(super) fn wpe_buffer_dma_buf_get_stride(buffer: *mut WpeBufferDmaBuf, plane: u32) -> u32;
    pub(super) fn wpe_buffer_dma_buf_get_modifier(buffer: *mut WpeBufferDmaBuf) -> u64;

    pub(super) fn wpe_event_keyboard_new(
        event_type: i32,
        view: *mut WpeView,
        source: i32,
        time: u32,
        modifiers: u32,
        keycode: u32,
        keyval: u32,
    ) -> *mut WpeEvent;
    pub(super) fn wpe_event_pointer_button_new(
        event_type: i32,
        view: *mut WpeView,
        source: i32,
        time: u32,
        modifiers: u32,
        button: u32,
        x: f64,
        y: f64,
        press_count: u32,
    ) -> *mut WpeEvent;
    pub(super) fn wpe_event_pointer_move_new(
        event_type: i32,
        view: *mut WpeView,
        source: i32,
        time: u32,
        modifiers: u32,
        x: f64,
        y: f64,
        delta_x: f64,
        delta_y: f64,
    ) -> *mut WpeEvent;
    pub(super) fn wpe_event_scroll_new(
        view: *mut WpeView,
        source: i32,
        time: u32,
        modifiers: u32,
        delta_x: f64,
        delta_y: f64,
        precise: i32,
        is_stop: i32,
        x: f64,
        y: f64,
    ) -> *mut WpeEvent;
    pub(super) fn wpe_event_touch_new(
        event_type: i32,
        view: *mut WpeView,
        source: i32,
        time: u32,
        modifiers: u32,
        sequence_id: u32,
        x: f64,
        y: f64,
    ) -> *mut WpeEvent;
    pub(super) fn wpe_event_unref(event: *mut WpeEvent);
}
