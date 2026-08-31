// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Host-mediated WebKit requests and their C ABI.
//!
//! Headless WPE cannot present dialogs, pick files, request permissions, or
//! collect credentials itself. Each callback retains the minimum native object
//! needed for an asynchronous Dart decision and copies every borrowed value.

use super::prelude::*;

const MAX_FILE_CHOOSER_REQUESTS: usize = 32;
pub(super) const MAX_FILE_CHOOSER_VALUES: usize = 1024;

const PERMISSION_RESOURCE_CAMERA: u32 = 1 << 0;
const PERMISSION_RESOURCE_MICROPHONE: u32 = 1 << 1;
const PERMISSION_RESOURCE_DISPLAY_CAPTURE: u32 = 1 << 2;
const PERMISSION_RESOURCE_GEOLOCATION: u32 = 1 << 3;
const PERMISSION_RESOURCE_NOTIFICATIONS: u32 = 1 << 4;
const PERMISSION_RESOURCE_DEVICE_INFO: u32 = 1 << 5;
const PERMISSION_RESOURCE_PROTECTED_MEDIA: u32 = 1 << 6;
const PERMISSION_RESOURCE_WEBSITE_DATA_ACCESS: u32 = 1 << 7;
const PERMISSION_RESOURCE_XR: u32 = 1 << 8;
const PERMISSION_RESOURCE_UNKNOWN: u32 = 1 << 31;

const WEBKIT_PERMISSION_STATE_GRANTED: i32 = 0;
const WEBKIT_PERMISSION_STATE_DENIED: i32 = 1;
const WEBKIT_PERMISSION_STATE_PROMPT: i32 = 2;

const QUERYABLE_PERMISSION_RESOURCES: [u32; 5] = [
    PERMISSION_RESOURCE_CAMERA,
    PERMISSION_RESOURCE_MICROPHONE,
    PERMISSION_RESOURCE_DISPLAY_CAPTURE,
    PERMISSION_RESOURCE_GEOLOCATION,
    PERMISSION_RESOURCE_NOTIFICATIONS,
];

/// Returns whether the per-view setting must reject this request before Dart.
pub(super) fn geolocation_permission_blocked(resource_types: u32, enabled: bool) -> bool {
    !enabled && resource_types & PERMISSION_RESOURCE_GEOLOCATION != 0
}

/// Native gate retained while one navigation decision waits for Dart.
///
/// Most requests retain the UI-process `WebKitPolicyDecision` before WebKit
/// starts loading. Requests whose frame identity is available only from the
/// web process provisionally pass that gate, then retain the page-scoped
/// `WebKitUserMessage` that is synchronously holding `send-request`. Response
/// policy decisions stop local resources before document commit; web-process
/// decisions stop marked network requests before dispatch.
pub(super) enum NavigationPolicyBackend {
    UiNavigation(glib::Object),
    UiResponse(glib::Object),
    WebProcess(glib::Object),
}

pub(super) struct NavigationPolicyRequestSnapshot {
    pub(super) id: u64,
    pub(super) url: Vec<u8>,
    pub(super) is_main_frame: bool,
    pub(super) backend: NavigationPolicyBackend,
}

/// Replies to a page-scoped web-process decision message exactly once.
pub(super) fn reply_web_process_navigation(message: &glib::Object, allow: bool) {
    let parameters = allow.to_variant();
    let reply = unsafe {
        webkit_user_message_new(
            c"webview-flutter-linux-frame-decision-0-1".as_ptr(),
            ToGlibPtr::<*mut glib::ffi::GVariant>::to_glib_none(&parameters).0,
        )
    };
    if reply.is_null() {
        return;
    }
    let message = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(message)
        .0
        .cast::<WebKitUserMessage>();
    unsafe { webkit_user_message_send_reply(message, reply) };
}

/// Applies the safe cancellation default for either native policy backend.
pub(super) fn cancel_navigation_policy_backend(backend: &NavigationPolicyBackend) {
    match backend {
        NavigationPolicyBackend::UiNavigation(decision)
        | NavigationPolicyBackend::UiResponse(decision) => {
            let decision = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(decision)
                .0
                .cast::<WebKitPolicyDecision>();
            unsafe { webkit_policy_decision_ignore(decision) };
        }
        NavigationPolicyBackend::WebProcess(message) => {
            reply_web_process_navigation(message, false);
        }
    }
}

/// Retained JavaScript dialog waiting for an asynchronous Dart response.
///
/// WebKit explicitly permits retaining `WebKitScriptDialog` past the signal.
/// Dropping this snapshot always closes and unreferences the dialog, which also
/// gives view disposal a deterministic cancellation path.
pub(super) struct ScriptDialogRequestSnapshot {
    id: u64,
    kind: i32,
    message: Vec<u8>,
    url: Vec<u8>,
    default_text: Vec<u8>,
    has_default_text: bool,
    dialog: *mut WebKitScriptDialog,
}

/// Retained WebKit permission request awaiting a host grant or denial.
///
/// The generic GObject reference keeps every concrete request type alive after
/// the signal returns. [PermissionRequestSnapshot::resource_types] is copied
/// from the concrete WPE type while the borrowed signal argument is valid.
pub(super) struct PermissionRequestSnapshot {
    id: u64,
    resource_types: u32,
    url: Vec<u8>,
    origin: Vec<u8>,
    pub(super) request: glib::Object,
}

/// Maps Permissions API descriptors to the resource bits used by Dart.
///
/// WPE can ask about permission names for which it has no corresponding
/// `WebKitPermissionRequest` type. Those remain `prompt` instead of borrowing
/// an unrelated decision or treating an unknown capability as granted.
pub(super) fn permission_query_resource_type(name: &[u8]) -> Option<u32> {
    match name {
        b"camera" => Some(PERMISSION_RESOURCE_CAMERA),
        b"microphone" => Some(PERMISSION_RESOURCE_MICROPHONE),
        b"display-capture" => Some(PERMISSION_RESOURCE_DISPLAY_CAPTURE),
        b"geolocation" => Some(PERMISSION_RESOURCE_GEOLOCATION),
        b"notifications" => Some(PERMISSION_RESOURCE_NOTIFICATIONS),
        _ => None,
    }
}

/// Records one Flutter decision for each concrete permission in a request.
pub(super) fn remember_permission_decision(
    states: &mut HashMap<(Vec<u8>, u32), i32>,
    origin: &[u8],
    resource_types: u32,
    allow: bool,
) {
    if origin.is_empty() {
        return;
    }
    let state = if allow {
        WEBKIT_PERMISSION_STATE_GRANTED
    } else {
        WEBKIT_PERMISSION_STATE_DENIED
    };
    for resource in QUERYABLE_PERMISSION_RESOURCES {
        if resource_types & resource != 0 {
            states.insert((origin.to_vec(), resource), state);
        }
    }
}

/// Resolves one permission query without leaking decisions across origins.
pub(super) fn remembered_permission_state(
    states: &HashMap<(Vec<u8>, u32), i32>,
    origin: &[u8],
    resource: Option<u32>,
) -> i32 {
    let Some(resource) = resource else {
        return WEBKIT_PERMISSION_STATE_PROMPT;
    };
    states
        .get(&(origin.to_vec(), resource))
        .copied()
        .unwrap_or(WEBKIT_PERMISSION_STATE_PROMPT)
}

/// Copies WebKit's canonical serialization of a borrowed security origin.
unsafe fn serialized_security_origin(origin: *mut WebKitSecurityOrigin) -> Vec<u8> {
    if origin.is_null() {
        return Vec::new();
    }
    let serialized = unsafe { webkit_security_origin_to_string(origin) };
    if serialized.is_null() {
        return Vec::new();
    }
    let bytes = foreign_bytes(serialized);
    unsafe { glib::ffi::g_free(serialized.cast()) };
    bytes
}

/// Creates the same canonical origin key from the WebView's current URI.
unsafe fn webview_security_origin(webview: *mut WebKitWebView) -> Vec<u8> {
    let uri = unsafe { webkit_web_view_get_uri(webview) };
    if uri.is_null() {
        return Vec::new();
    }
    let origin = unsafe { webkit_security_origin_new_for_uri(uri) };
    if origin.is_null() {
        return Vec::new();
    }
    let serialized = unsafe { serialized_security_origin(origin) };
    unsafe { webkit_security_origin_unref(origin) };
    serialized
}

/// Retained HTTP authentication challenge waiting for host credentials.
///
/// The WebKit signal lends its request only for the callback. A strong GObject
/// reference makes the documented asynchronous authentication flow possible,
/// while copying host and realm avoids exposing borrowed native strings across
/// the ABI. The request moves from the delivery FIFO to the pending map before
/// Dart receives it, so each ID can be completed at most once.
pub(super) struct HttpAuthRequestSnapshot {
    id: u64,
    host: Vec<u8>,
    realm: Vec<u8>,
    has_realm: bool,
    pub(super) request: glib::Object,
}

/// Retained TLS certificate failure waiting for the application's decision.
///
/// WPE has already stopped the failed load when this snapshot is created.
/// Proceeding adds an exception for this exact certificate and host to the
/// view's network session, then explicitly reloads the copied URI. Cancelling
/// only drops the retained certificate because there is no in-flight load left
/// to abort. DER bytes are copied for the federated certificate value.
pub(super) struct SslAuthErrorSnapshot {
    id: u64,
    url: Vec<u8>,
    host: Vec<u8>,
    certificate_der: Vec<u8>,
    error_flags: u32,
    certificate: glib::Object,
}

/// Retained HTML file-input request awaiting Flutter's selection.
///
/// WPE lends the request only while emitting `run-file-chooser`. A strong
/// GObject reference keeps it valid for an asynchronous Flutter file picker;
/// MIME types and existing selections are copied immediately because their
/// null-terminated arrays remain WebKit-owned.
pub(super) struct FileChooserRequestSnapshot {
    id: u64,
    allows_multiple: bool,
    mime_types: Vec<Vec<u8>>,
    selected_files: Vec<Vec<u8>>,
    pub(super) request: glib::Object,
}

impl Drop for ScriptDialogRequestSnapshot {
    fn drop(&mut self) {
        if self.dialog.is_null() {
            return;
        }
        unsafe {
            webkit_script_dialog_close(self.dialog);
            webkit_script_dialog_unref(self.dialog);
        }
    }
}

/// Retains JavaScript dialogs for asynchronous resolution by Dart.
///
/// WPE is headless and cannot present its fallback dialog UI. Returning `true`
/// suppresses that fallback after taking the explicit reference required by
/// WebKit's asynchronous-dialog contract. Flutter later supplies alert,
/// confirm, or prompt results through handle-scoped FFI calls.
pub(super) fn connect_script_dialogs(webview: &glib::Object, native_view: Weak<NativeView>) {
    let raw_webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(webview).0
        as *mut WebKitWebView as usize;
    webview.connect_local("script-dialog", false, move |values| {
        let dialog = unsafe {
            glib::gobject_ffi::g_value_get_boxed(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        }
        .cast::<WebKitScriptDialog>();
        if dialog.is_null() {
            return Some(false.to_value());
        }
        let Some(native_view) = native_view.upgrade() else {
            return Some(false.to_value());
        };
        let kind = unsafe { webkit_script_dialog_get_dialog_type(dialog) };
        if !(0..=3).contains(&kind) {
            return Some(false.to_value());
        }
        let retained = unsafe { webkit_script_dialog_ref(dialog) };
        if retained.is_null() {
            return Some(false.to_value());
        }
        let id = {
            let mut next = native_view.next_script_dialog_id.borrow_mut();
            let id = (*next).max(1);
            *next = id.wrapping_add(1).max(1);
            id
        };
        let default_text = if kind == 2 {
            unsafe { webkit_script_dialog_prompt_get_default_text(dialog) }
        } else {
            std::ptr::null()
        };
        native_view
            .script_dialog_requests
            .borrow_mut()
            .push_back(ScriptDialogRequestSnapshot {
                id,
                kind,
                message: foreign_bytes(unsafe { webkit_script_dialog_get_message(dialog) }),
                url: webview_uri(raw_webview as *mut WebKitWebView),
                default_text: foreign_bytes(default_text),
                has_default_text: !default_text.is_null(),
                dialog: retained,
            });
        Some(true.to_value())
    });
}

/// Retains HTML file-input requests for an asynchronous Flutter picker.
///
/// Returning `true` is essential for this headless backend: it suppresses
/// WebKit's fallback GTK dialog after the request has been retained. If the
/// bounded queue is full, the new request is cancelled immediately so browser
/// form state cannot remain suspended indefinitely.
pub(super) fn connect_file_chooser_requests(webview: &glib::Object, native_view: Weak<NativeView>) {
    webview.connect_local("run-file-chooser", false, move |values| {
        let request = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        };
        if request.is_null() {
            return Some(false.to_value());
        }
        let request_pointer = request.cast::<WebKitFileChooserRequest>();
        let Some(native_view) = native_view.upgrade() else {
            unsafe { webkit_file_chooser_request_cancel(request_pointer) };
            return Some(true.to_value());
        };
        let retained_request_count = native_view.file_chooser_requests.borrow().len()
            + native_view.pending_file_chooser_requests.borrow().len();
        if retained_request_count >= MAX_FILE_CHOOSER_REQUESTS {
            unsafe { webkit_file_chooser_request_cancel(request_pointer) };
            return Some(true.to_value());
        }
        let id = {
            let mut next = native_view.next_file_chooser_request_id.borrow_mut();
            let id = (*next).max(1);
            *next = id.wrapping_add(1).max(1);
            id
        };
        // SAFETY: request is a live transfer-none signal argument. Acquiring a
        // GObject reference permits resolution after this callback returns.
        let retained: glib::Object = unsafe { from_glib_none(request) };
        let mime_types = unsafe {
            foreign_string_array(webkit_file_chooser_request_get_mime_types(request_pointer))
        };
        let selected_files = unsafe {
            foreign_string_array(webkit_file_chooser_request_get_selected_files(
                request_pointer,
            ))
        };
        let allows_multiple =
            unsafe { webkit_file_chooser_request_get_select_multiple(request_pointer) } != 0;
        native_view
            .file_chooser_requests
            .borrow_mut()
            .push_back(FileChooserRequestSnapshot {
                id,
                allows_multiple,
                mime_types,
                selected_files,
                request: retained,
            });
        Some(true.to_value())
    });
}

/// Retains permission requests until Dart calls `grant()` or `deny()`.
///
/// WPE's default is generally denial, which is safe but makes the federated
/// permission callback ineffective. A strong GObject reference allows Flutter
/// UI to ask the user asynchronously while this signal returns immediately.
pub(super) fn connect_permission_requests(webview: &glib::Object, native_view: Weak<NativeView>) {
    let raw_webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(webview).0
        as *mut WebKitWebView as usize;
    webview.connect_local("permission-request", false, move |values| {
        let request = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        };
        if request.is_null() {
            return Some(false.to_value());
        }
        let Some(native_view) = native_view.upgrade() else {
            return Some(false.to_value());
        };
        let resource_types = unsafe { permission_resource_types(request) };
        if geolocation_permission_blocked(resource_types, native_view.geolocation_enabled.get()) {
            // The embedding-level setting takes precedence over the Dart
            // permission callback, just as disabling geolocation in Android's
            // WebSettings prevents a later WebChromeClient prompt from
            // enabling it for a page.
            unsafe { webkit_permission_request_deny(request.cast()) };
            return Some(true.to_value());
        }
        let id = {
            let mut next = native_view.next_permission_request_id.borrow_mut();
            let id = (*next).max(1);
            *next = id.wrapping_add(1).max(1);
            id
        };
        // SAFETY: the signal argument is a live transfer-none GObject. Taking
        // one reference is the asynchronous ownership protocol documented by
        // WebKit for permission requests.
        let request: glib::Object = unsafe { from_glib_none(request) };
        native_view
            .permission_requests
            .borrow_mut()
            .push_back(PermissionRequestSnapshot {
                id,
                resource_types,
                url: webview_uri(raw_webview as *mut WebKitWebView),
                origin: unsafe { webview_security_origin(raw_webview as *mut WebKitWebView) },
                request,
            });
        Some(true.to_value())
    });
}

/// Answers `navigator.permissions.query()` from prior Flutter decisions.
///
/// WPE deliberately separates permission-state queries from permission
/// requests. A grant or denial delivered through `permission-request` does not
/// answer later query signals for the embedder. Finishing every known query
/// synchronously gives pages a stable origin-scoped result while leaving new
/// and unsupported permission names in the standards-defined `prompt` state.
pub(super) fn connect_permission_state_queries(
    webview: &glib::Object,
    native_view: Weak<NativeView>,
) {
    webview.connect_local("query-permission-state", false, move |values| {
        let query = unsafe {
            glib::gobject_ffi::g_value_get_boxed(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        }
        .cast::<WebKitPermissionStateQuery>();
        if query.is_null() {
            return Some(false.to_value());
        }
        let Some(native_view) = native_view.upgrade() else {
            return Some(false.to_value());
        };
        let name = foreign_bytes(unsafe { webkit_permission_state_query_get_name(query) });
        let resource = permission_query_resource_type(&name);
        let origin = unsafe {
            serialized_security_origin(webkit_permission_state_query_get_security_origin(query))
        };
        let state = if resource == Some(PERMISSION_RESOURCE_GEOLOCATION)
            && !native_view.geolocation_enabled.get()
        {
            WEBKIT_PERMISSION_STATE_DENIED
        } else {
            remembered_permission_state(&native_view.permission_states.borrow(), &origin, resource)
        };
        unsafe { webkit_permission_state_query_finish(query, state) };
        Some(true.to_value())
    });
}

/// Denies and removes every retained geolocation permission request.
///
/// A setting update may arrive while a request is still queued for Dart or
/// after Dart has taken ownership of its request ID. Both collections retain
/// strong GObject references, so disabling geolocation must resolve them
/// before removal rather than merely dropping the references and depending on
/// WebKit's default action.
pub(super) fn deny_geolocation_permission_requests(native_view: &NativeView) {
    native_view
        .permission_requests
        .borrow_mut()
        .retain(|request| {
            if request.resource_types & PERMISSION_RESOURCE_GEOLOCATION == 0 {
                return true;
            }
            let request =
                ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&request.request)
                    .0
                    .cast::<WebKitPermissionRequest>();
            unsafe { webkit_permission_request_deny(request) };
            false
        });
    native_view
        .pending_permission_requests
        .borrow_mut()
        .retain(|_, request| {
            let request_pointer =
                ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&request.request).0;
            let is_geolocation = request.resource_types & PERMISSION_RESOURCE_GEOLOCATION != 0;
            if is_geolocation {
                unsafe { webkit_permission_request_deny(request_pointer.cast()) };
            }
            !is_geolocation
        });
}

/// Retains username/password HTTP challenges for asynchronous Flutter UI.
///
/// Returning `true` suppresses WPE's unavailable headless fallback dialog.
/// Certificate, certificate-PIN, and server-trust schemes are deliberately
/// left to their dedicated platform paths because `HttpAuthRequest` can only
/// supply a username and password. Unknown schemes are retained because the
/// signal itself is documented as an HTTP authentication challenge and newer
/// WPE versions may add another credential-compatible scheme.
pub(super) fn connect_http_auth_requests(webview: &glib::Object, native_view: Weak<NativeView>) {
    webview.connect_local("authenticate", false, move |values| {
        let request = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        };
        if request.is_null() {
            return Some(false.to_value());
        }
        let request_ptr = request.cast::<WebKitAuthenticationRequest>();
        let scheme = unsafe { webkit_authentication_request_get_scheme(request_ptr) };
        if !supports_username_password_authentication(scheme) {
            return Some(false.to_value());
        }
        let Some(native_view) = native_view.upgrade() else {
            return Some(false.to_value());
        };
        let id = {
            let mut next = native_view.next_http_auth_request_id.borrow_mut();
            let id = (*next).max(1);
            *next = id.wrapping_add(1).max(1);
            id
        };
        let realm = unsafe { webkit_authentication_request_get_realm(request_ptr) };
        // SAFETY: `request` is a live transfer-none signal argument. WebKit's
        // asynchronous-authentication contract explicitly requires taking a
        // strong reference before returning true from this callback.
        let request: glib::Object = unsafe { from_glib_none(request) };
        native_view
            .http_auth_requests
            .borrow_mut()
            .push_back(HttpAuthRequestSnapshot {
                id,
                host: foreign_bytes(unsafe { webkit_authentication_request_get_host(request_ptr) }),
                realm: foreign_bytes(realm),
                has_realm: !realm.is_null(),
                request,
            });
        Some(true.to_value())
    });
}

/// Identifies challenges representable by the federated username/password API.
pub(super) fn supports_username_password_authentication(scheme: i32) -> bool {
    // WebKit reserves 7 through 9 for client certificates, server trust, and
    // certificate PINs. All other values emitted by the HTTP-auth signal are
    // credential-compatible, including future/unknown HTTP schemes.
    !matches!(scheme, 7..=9)
}

/// Retains main-load TLS failures for `PlatformSslAuthError` decisions.
///
/// Returning true prevents WPE from emitting the generic `load-failed` signal,
/// which would otherwise duplicate the dedicated certificate callback as a
/// `WebResourceError`. The failed load has already ended; the resolver must
/// install an exact host/certificate exception and start a new load to model
/// the federated `proceed()` operation.
pub(super) fn connect_ssl_auth_errors(webview: &glib::Object, native_view: Weak<NativeView>) {
    webview.connect_local("load-failed-with-tls-errors", false, move |values| {
        let failing_uri = unsafe {
            glib::gobject_ffi::g_value_get_string(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        };
        let certificate = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[2]).0,
            )
        };
        if failing_uri.is_null() || certificate.is_null() {
            return Some(false.to_value());
        }
        let Ok(url) = unsafe { CStr::from_ptr(failing_uri) }.to_str() else {
            return Some(false.to_value());
        };
        let Some(host) = host_from_https_uri(url) else {
            return Some(false.to_value());
        };
        let Some(native_view) = native_view.upgrade() else {
            return Some(false.to_value());
        };
        native_view.main_frame_load_failed.set(true);
        let error_flags = unsafe {
            glib::gobject_ffi::g_value_get_flags(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[3]).0,
            )
        };
        // SAFETY: the certificate is a live transfer-none GObject signal
        // argument. WPE explicitly documents retaining it for asynchronous
        // handling when this callback returns true.
        let certificate: glib::Object = unsafe { from_glib_none(certificate) };
        let certificate_der = certificate
            .property::<Option<glib::ByteArray>>("certificate")
            .map_or_else(Vec::new, |bytes| bytes.as_ref().to_vec());
        let id = {
            let mut next = native_view.next_ssl_auth_error_id.borrow_mut();
            let id = (*next).max(1);
            *next = id.wrapping_add(1).max(1);
            id
        };
        native_view
            .ssl_auth_errors
            .borrow_mut()
            .push_back(SslAuthErrorSnapshot {
                id,
                url: url.as_bytes().to_vec(),
                host,
                certificate_der,
                error_flags,
                certificate,
            });
        Some(true.to_value())
    });
}

/// Extracts the host spelling expected by WebKit's TLS-exception API.
///
/// The signal is only emitted for HTTPS loads, so a small strict authority
/// parser avoids adding a URL dependency or raising the crate's GLib feature
/// floor solely for `GUri`. IPv6 brackets are removed as required by
/// `webkit_network_session_allow_tls_certificate_for_host`.
pub(super) fn host_from_https_uri(url: &str) -> Option<Vec<u8>> {
    let authority_and_rest = url.strip_prefix("https://")?;
    let authority_end = authority_and_rest
        .find(['/', '?', '#'])
        .unwrap_or(authority_and_rest.len());
    let authority = &authority_and_rest[..authority_end];
    let host_and_port = authority
        .rsplit_once('@')
        .map_or(authority, |(_, host)| host);
    let host = if let Some(bracketed) = host_and_port.strip_prefix('[') {
        let closing_bracket = bracketed.find(']')?;
        let suffix = &bracketed[closing_bracket + 1..];
        if !suffix.is_empty() && !suffix.starts_with(':') {
            return None;
        }
        &bracketed[..closing_bracket]
    } else {
        host_and_port
            .split_once(':')
            .map_or(host_and_port, |(host, _)| host)
    };
    (!host.is_empty()).then(|| host.as_bytes().to_vec())
}

/// Converts WPE's concrete permission-request GType into stable ABI bits.
///
/// # Safety
///
/// `request` must point to a live GObject implementing WebKitPermissionRequest.
unsafe fn permission_resource_types(request: *mut glib::gobject_ffi::GObject) -> u32 {
    let is_a = |type_: glib::ffi::GType| unsafe {
        glib::gobject_ffi::g_type_check_instance_is_a(request.cast(), type_) != 0
    };
    if is_a(unsafe { webkit_user_media_permission_request_get_type() }) {
        let request = request.cast::<WebKitUserMediaPermissionRequest>();
        let mut types = 0;
        if unsafe { webkit_user_media_permission_is_for_video_device(request) } != 0 {
            types |= PERMISSION_RESOURCE_CAMERA;
        }
        if unsafe { webkit_user_media_permission_is_for_audio_device(request) } != 0 {
            types |= PERMISSION_RESOURCE_MICROPHONE;
        }
        if unsafe { webkit_user_media_permission_is_for_display_device(request) } != 0 {
            types |= PERMISSION_RESOURCE_DISPLAY_CAPTURE;
        }
        return if types == 0 {
            PERMISSION_RESOURCE_UNKNOWN
        } else {
            types
        };
    }
    if is_a(unsafe { webkit_geolocation_permission_request_get_type() }) {
        return PERMISSION_RESOURCE_GEOLOCATION;
    }
    if is_a(unsafe { webkit_notification_permission_request_get_type() }) {
        return PERMISSION_RESOURCE_NOTIFICATIONS;
    }
    if is_a(unsafe { webkit_device_info_permission_request_get_type() }) {
        return PERMISSION_RESOURCE_DEVICE_INFO;
    }
    if is_a(unsafe { webkit_media_key_system_permission_request_get_type() }) {
        return PERMISSION_RESOURCE_PROTECTED_MEDIA;
    }
    if is_a(unsafe { webkit_website_data_access_permission_request_get_type() }) {
        return PERMISSION_RESOURCE_WEBSITE_DATA_ACCESS;
    }
    if is_a(unsafe { webkit_xr_permission_request_get_type() }) {
        return PERMISSION_RESOURCE_XR;
    }
    PERMISSION_RESOURCE_UNKNOWN
}

/// Accepts a navigation with the media policy configured for its WebView.
///
/// `media-playback-requires-user-gesture` updates WebCore's media settings,
/// while WPE's default website policy still permits only muted autoplay. An
/// explicit per-navigation policy is therefore required for the Android-style
/// `false` value to allow audible autoplay. `DENY` still permits a later
/// user-initiated play action; it only blocks automatic playback.
pub(super) fn use_policy_decision_with_media_policy(
    webview: *mut WebKitWebView,
    decision: *mut WebKitPolicyDecision,
) {
    let settings = unsafe { webkit_web_view_get_settings(webview) };
    if settings.is_null() {
        unsafe { webkit_policy_decision_use(decision) };
        return;
    }
    let requires_gesture =
        unsafe { webkit_settings_get_media_playback_requires_user_gesture(settings) != 0 };
    // WebKitAutoplayPolicy: ALLOW = 0, ALLOW_WITHOUT_SOUND = 1, DENY = 2.
    let autoplay_policy: i32 = if requires_gesture { 2 } else { 0 };
    let policies = unsafe {
        webkit_website_policies_new_with_policies(
            c"autoplay".as_ptr(),
            autoplay_policy,
            std::ptr::null::<c_char>(),
        )
    };
    if policies.is_null() {
        unsafe { webkit_policy_decision_use(decision) };
        return;
    }
    unsafe {
        webkit_policy_decision_use_with_policies(decision, policies);
        glib::gobject_ffi::g_object_unref(policies.cast());
    }
}

/// Applies an operation to the oldest unresolved navigation policy request.
fn with_navigation_policy_request<T: Copy>(
    handle: u64,
    fallback: T,
    operation: impl FnOnce(&NavigationPolicyRequestSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    native_view
        .navigation_policy_requests
        .borrow()
        .front()
        .map_or(fallback, operation)
}

#[unsafe(no_mangle)]
/// Returns the number of WebKit navigation decisions waiting for Dart.
pub extern "C" fn webview_flutter_linux_wpe_navigation_policy_request_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.navigation_policy_requests
            .borrow()
            .len()
            .min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Returns the ID of the oldest waiting navigation policy request.
pub extern "C" fn webview_flutter_linux_wpe_navigation_policy_request_id(handle: u64) -> u64 {
    with_navigation_policy_request(handle, 0, |request| request.id)
}

#[unsafe(no_mangle)]
/// Returns whether the oldest waiting request targets the main frame.
pub extern "C" fn webview_flutter_linux_wpe_navigation_policy_request_is_main_frame(
    handle: u64,
) -> i32 {
    with_navigation_policy_request(handle, -1, |request| i32::from(request.is_main_frame))
}

#[unsafe(no_mangle)]
/// Returns the URL byte length of the oldest waiting policy request.
pub extern "C" fn webview_flutter_linux_wpe_navigation_policy_request_url_length(
    handle: u64,
) -> usize {
    with_navigation_policy_request(handle, 0, |request| request.url.len())
}

#[unsafe(no_mangle)]
/// Copies the URL of the oldest waiting navigation policy request.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes.
pub unsafe extern "C" fn webview_flutter_linux_wpe_navigation_policy_request_copy_url(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_navigation_policy_request(handle, -2, |request| {
        if destination_length < request.url.len() || request.url.len() > i32::MAX as usize {
            return -3;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(request.url.as_ptr(), destination, request.url.len())
        };
        request.url.len() as i32
    })
}

#[unsafe(no_mangle)]
/// Marks the oldest request as delivered while retaining its native gate.
pub extern "C" fn webview_flutter_linux_wpe_navigation_policy_request_take(handle: u64) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let Some(request) = native_view
        .navigation_policy_requests
        .borrow_mut()
        .pop_front()
    else {
        return 1;
    };
    native_view
        .pending_policy_decisions
        .borrow_mut()
        .insert(request.id, request.backend);
    0
}

#[unsafe(no_mangle)]
/// Resolves one delivered WebKit policy request exactly once.
///
/// A non-zero `allow` value continues navigation; zero prevents it. Returns
/// `-1` for an invalid handle, `-2` for an unknown or already resolved ID, and
/// `-3` if the owning WebView was torn down before an allow decision.
pub extern "C" fn webview_flutter_linux_wpe_navigation_policy_resolve(
    handle: u64,
    request_id: u64,
    allow: i32,
) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let Some(backend) = native_view
        .pending_policy_decisions
        .borrow_mut()
        .remove(&request_id)
    else {
        return -2;
    };
    if let NavigationPolicyBackend::WebProcess(message) = backend {
        reply_web_process_navigation(&message, allow != 0);
        return 0;
    }
    let (decision, with_media_policy) = match backend {
        NavigationPolicyBackend::UiNavigation(decision) => (decision, true),
        NavigationPolicyBackend::UiResponse(decision) => (decision, false),
        NavigationPolicyBackend::WebProcess(_) => {
            unreachable!("web-process navigation backend returned above")
        }
    };
    let decision = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&decision)
        .0
        .cast::<WebKitPolicyDecision>();
    if allow == 0 {
        unsafe { webkit_policy_decision_ignore(decision) };
        return 0;
    }
    let webview = {
        let runtime = native_view.runtime.borrow();
        let Some(runtime) = runtime.as_ref() else {
            unsafe { webkit_policy_decision_ignore(decision) };
            return -3;
        };
        ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
            as *mut WebKitWebView
    };
    if with_media_policy {
        use_policy_decision_with_media_policy(webview, decision);
    } else {
        unsafe { webkit_policy_decision_use(decision) };
    }
    0
}

/// Applies an operation to the oldest queued JavaScript dialog.
fn with_script_dialog_request<T: Copy>(
    handle: u64,
    fallback: T,
    operation: impl FnOnce(&ScriptDialogRequestSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    native_view
        .script_dialog_requests
        .borrow()
        .front()
        .map_or(fallback, operation)
}

#[unsafe(no_mangle)]
/// Returns the number of retained JavaScript dialogs waiting for Dart.
pub extern "C" fn webview_flutter_linux_wpe_script_dialog_request_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.script_dialog_requests
            .borrow()
            .len()
            .min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Returns the ID of the oldest waiting JavaScript dialog.
pub extern "C" fn webview_flutter_linux_wpe_script_dialog_request_id(handle: u64) -> u64 {
    with_script_dialog_request(handle, 0, |request| request.id)
}

#[unsafe(no_mangle)]
/// Returns WebKit's dialog kind for the oldest waiting request.
pub extern "C" fn webview_flutter_linux_wpe_script_dialog_request_kind(handle: u64) -> i32 {
    with_script_dialog_request(handle, -1, |request| request.kind)
}

#[unsafe(no_mangle)]
/// Returns whether the oldest prompt supplied default text.
pub extern "C" fn webview_flutter_linux_wpe_script_dialog_request_has_default_text(
    handle: u64,
) -> i32 {
    with_script_dialog_request(handle, 0, |request| i32::from(request.has_default_text))
}

/// Resolves a string field from the oldest JavaScript dialog.
fn with_script_dialog_field<T: Copy>(
    handle: u64,
    field: u32,
    fallback: T,
    operation: impl FnOnce(&[u8]) -> T,
) -> T {
    with_script_dialog_request(handle, fallback, |request| {
        let bytes = match field {
            0 => &request.message,
            1 => &request.url,
            2 => &request.default_text,
            _ => return fallback,
        };
        operation(bytes)
    })
}

#[unsafe(no_mangle)]
/// Returns the byte length of a JavaScript-dialog string field.
///
/// Field `0` is the message, `1` the source URL, and `2` prompt default text.
pub extern "C" fn webview_flutter_linux_wpe_script_dialog_request_field_length(
    handle: u64,
    field: u32,
) -> usize {
    with_script_dialog_field(handle, field, 0, <[u8]>::len)
}

#[unsafe(no_mangle)]
/// Copies a JavaScript-dialog string field into Dart-owned memory.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes.
pub unsafe extern "C" fn webview_flutter_linux_wpe_script_dialog_request_copy_field(
    handle: u64,
    field: u32,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_script_dialog_field(handle, field, -2, |bytes| {
        if destination_length < bytes.len() || bytes.len() > i32::MAX as usize {
            return -3;
        }
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), destination, bytes.len()) };
        bytes.len() as i32
    })
}

#[unsafe(no_mangle)]
/// Marks the oldest JavaScript dialog as delivered to Dart.
pub extern "C" fn webview_flutter_linux_wpe_script_dialog_request_take(handle: u64) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let Some(request) = native_view.script_dialog_requests.borrow_mut().pop_front() else {
        return 1;
    };
    native_view
        .pending_script_dialogs
        .borrow_mut()
        .insert(request.id, request);
    0
}

#[unsafe(no_mangle)]
/// Resolves one delivered JavaScript dialog exactly once.
///
/// `confirmed` controls confirm and before-unload requests. `prompt_text` is
/// used only for prompts and may be null to cancel. Alert responses ignore
/// both values. Returns `-1` for an invalid handle, `-2` for an unknown ID, and
/// `-3` for invalid prompt UTF-8.
///
/// # Safety
///
/// A non-null `prompt_text` must point to readable NUL-terminated UTF-8 for
/// the duration of this call.
pub unsafe extern "C" fn webview_flutter_linux_wpe_script_dialog_resolve(
    handle: u64,
    request_id: u64,
    confirmed: i32,
    prompt_text: *const c_char,
) -> i32 {
    if !prompt_text.is_null() && unsafe { CStr::from_ptr(prompt_text) }.to_str().is_err() {
        return -3;
    }
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let Some(request) = native_view
        .pending_script_dialogs
        .borrow_mut()
        .remove(&request_id)
    else {
        return -2;
    };
    unsafe {
        match request.kind {
            1 | 3 => webkit_script_dialog_confirm_set_confirmed(
                request.dialog,
                i32::from(confirmed != 0),
            ),
            2 => webkit_script_dialog_prompt_set_text(request.dialog, prompt_text),
            _ => {}
        }
    }
    // Drop closes and unreferences the retained WebKit dialog.
    drop(request);
    0
}

/// Applies an operation to the oldest queued HTML file-input request.
fn with_file_chooser_request<T: Copy>(
    handle: u64,
    fallback: T,
    operation: impl FnOnce(&FileChooserRequestSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    native_view
        .file_chooser_requests
        .borrow()
        .front()
        .map_or(fallback, operation)
}

#[unsafe(no_mangle)]
/// Returns the number of retained HTML file-input requests waiting for Dart.
pub extern "C" fn webview_flutter_linux_wpe_file_chooser_request_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.file_chooser_requests
            .borrow()
            .len()
            .min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Returns the stable ID of the oldest waiting file-input request.
pub extern "C" fn webview_flutter_linux_wpe_file_chooser_request_id(handle: u64) -> u64 {
    with_file_chooser_request(handle, 0, |request| request.id)
}

#[unsafe(no_mangle)]
/// Returns one when the oldest file-input request accepts multiple files.
pub extern "C" fn webview_flutter_linux_wpe_file_chooser_request_allows_multiple(
    handle: u64,
) -> i32 {
    with_file_chooser_request(handle, 0, |request| i32::from(request.allows_multiple))
}

#[unsafe(no_mangle)]
/// Returns the number of copied values in a file-input request collection.
///
/// Collection zero contains accepted MIME types and collection one contains
/// files selected by a previous chooser invocation. Unknown collections return
/// zero.
pub extern "C" fn webview_flutter_linux_wpe_file_chooser_request_value_count(
    handle: u64,
    collection: u32,
) -> u32 {
    with_file_chooser_request(handle, 0, |request| {
        let count = match collection {
            0 => request.mime_types.len(),
            1 => request.selected_files.len(),
            _ => 0,
        };
        count.min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Returns one copied file-input value's byte length.
pub extern "C" fn webview_flutter_linux_wpe_file_chooser_request_value_length(
    handle: u64,
    collection: u32,
    index: u32,
) -> usize {
    with_file_chooser_request(handle, 0, |request| {
        let values = match collection {
            0 => request.mime_types.as_slice(),
            1 => request.selected_files.as_slice(),
            _ => return 0,
        };
        values.get(index as usize).map_or(0, Vec::len)
    })
}

#[unsafe(no_mangle)]
/// Copies one accepted MIME type or previously selected file path.
///
/// Returns the copied byte count, `-1` for a null destination, `-2` for an
/// invalid handle, collection, or index, and `-3` when the destination is too
/// small.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes.
pub unsafe extern "C" fn webview_flutter_linux_wpe_file_chooser_request_copy_value(
    handle: u64,
    collection: u32,
    index: u32,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_file_chooser_request(handle, -2, |request| {
        let values = match collection {
            0 => request.mime_types.as_slice(),
            1 => request.selected_files.as_slice(),
            _ => return -2,
        };
        let Some(bytes) = values.get(index as usize) else {
            return -2;
        };
        if destination_length < bytes.len() || bytes.len() > i32::MAX as usize {
            return -3;
        }
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), destination, bytes.len()) };
        bytes.len() as i32
    })
}

#[unsafe(no_mangle)]
/// Moves the oldest file-input request into the pending-response map.
pub extern "C" fn webview_flutter_linux_wpe_file_chooser_request_take(handle: u64) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let Some(request) = native_view.file_chooser_requests.borrow_mut().pop_front() else {
        return 1;
    };
    native_view
        .pending_file_chooser_requests
        .borrow_mut()
        .insert(request.id, request.request);
    0
}

#[unsafe(no_mangle)]
/// Supplies filesystem paths for one delivered file-input request exactly once.
///
/// The path array is copied and validated before the retained WebKit request is
/// removed, so invalid Dart input remains recoverable through a later cancel.
/// Returns `-1` for an invalid handle, `-2` for an unknown request, `-3` for an
/// invalid pointer or UTF-8 path, `-4` for too many paths, and `-5` when multiple
/// paths are supplied to a single-selection input.
///
/// # Safety
///
/// When `file_count` is non-zero, `files` must point to `file_count` readable
/// pointers and every entry must address a NUL-terminated UTF-8 string for the
/// duration of this call.
pub unsafe extern "C" fn webview_flutter_linux_wpe_file_chooser_request_select(
    handle: u64,
    request_id: u64,
    files: *const *const c_char,
    file_count: usize,
) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    if file_count > MAX_FILE_CHOOSER_VALUES {
        return -4;
    }
    if file_count == 0 || files.is_null() {
        return -3;
    }

    let mut owned_files = Vec::with_capacity(file_count);
    for index in 0..file_count {
        let pointer = unsafe { *files.add(index) };
        if pointer.is_null() {
            return -3;
        }
        let bytes = unsafe { CStr::from_ptr(pointer) }.to_bytes();
        if std::str::from_utf8(bytes).is_err() {
            return -3;
        }
        let Ok(path) = std::ffi::CString::new(bytes) else {
            return -3;
        };
        owned_files.push(path);
    }

    let mut pending = native_view.pending_file_chooser_requests.borrow_mut();
    let Some(request) = pending.get(&request_id) else {
        return -2;
    };
    let request_pointer = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(request)
        .0
        .cast::<WebKitFileChooserRequest>();
    if file_count > 1
        && unsafe { webkit_file_chooser_request_get_select_multiple(request_pointer) } == 0
    {
        return -5;
    }
    let request = pending
        .remove(&request_id)
        .expect("request was checked above");
    drop(pending);

    let mut pointers: Vec<*const c_char> = owned_files.iter().map(|path| path.as_ptr()).collect();
    pointers.push(std::ptr::null());
    let request_pointer = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&request)
        .0
        .cast::<WebKitFileChooserRequest>();
    unsafe { webkit_file_chooser_request_select_files(request_pointer, pointers.as_ptr()) };
    0
}

#[unsafe(no_mangle)]
/// Cancels one delivered file-input request exactly once.
pub extern "C" fn webview_flutter_linux_wpe_file_chooser_request_cancel(
    handle: u64,
    request_id: u64,
) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let Some(request) = native_view
        .pending_file_chooser_requests
        .borrow_mut()
        .remove(&request_id)
    else {
        return -2;
    };
    let request = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&request)
        .0
        .cast::<WebKitFileChooserRequest>();
    unsafe { webkit_file_chooser_request_cancel(request) };
    0
}

/// Applies an operation to the oldest queued permission request.
fn with_permission_request<T: Copy>(
    handle: u64,
    fallback: T,
    operation: impl FnOnce(&PermissionRequestSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    native_view
        .permission_requests
        .borrow()
        .front()
        .map_or(fallback, operation)
}

#[unsafe(no_mangle)]
/// Returns the number of retained permission requests waiting for Dart.
pub extern "C" fn webview_flutter_linux_wpe_permission_request_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.permission_requests
            .borrow()
            .len()
            .min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Returns the ID of the oldest waiting permission request.
pub extern "C" fn webview_flutter_linux_wpe_permission_request_id(handle: u64) -> u64 {
    with_permission_request(handle, 0, |request| request.id)
}

#[unsafe(no_mangle)]
/// Returns the resource bitmask of the oldest waiting permission request.
pub extern "C" fn webview_flutter_linux_wpe_permission_request_resource_types(handle: u64) -> u32 {
    with_permission_request(handle, 0, |request| request.resource_types)
}

#[unsafe(no_mangle)]
/// Returns the source URL byte length of the oldest permission request.
pub extern "C" fn webview_flutter_linux_wpe_permission_request_url_length(handle: u64) -> usize {
    with_permission_request(handle, 0, |request| request.url.len())
}

#[unsafe(no_mangle)]
/// Copies the oldest permission request's source URL into Dart-owned memory.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes.
pub unsafe extern "C" fn webview_flutter_linux_wpe_permission_request_copy_url(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_permission_request(handle, -2, |request| {
        if destination_length < request.url.len() || request.url.len() > i32::MAX as usize {
            return -3;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(request.url.as_ptr(), destination, request.url.len())
        };
        request.url.len() as i32
    })
}

#[unsafe(no_mangle)]
/// Marks the oldest permission request as delivered to Dart.
pub extern "C" fn webview_flutter_linux_wpe_permission_request_take(handle: u64) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let Some(request) = native_view.permission_requests.borrow_mut().pop_front() else {
        return 1;
    };
    native_view
        .pending_permission_requests
        .borrow_mut()
        .insert(request.id, request);
    0
}

#[unsafe(no_mangle)]
/// Grants or denies one delivered WebKit permission request exactly once.
pub extern "C" fn webview_flutter_linux_wpe_permission_request_resolve(
    handle: u64,
    request_id: u64,
    allow: i32,
) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let Some(request) = native_view
        .pending_permission_requests
        .borrow_mut()
        .remove(&request_id)
    else {
        return -2;
    };
    remember_permission_decision(
        &mut native_view.permission_states.borrow_mut(),
        &request.origin,
        request.resource_types,
        allow != 0,
    );
    let request = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&request.request)
        .0
        .cast::<WebKitPermissionRequest>();
    unsafe {
        if allow != 0 {
            webkit_permission_request_allow(request);
        } else {
            webkit_permission_request_deny(request);
        }
    }
    0
}

/// Applies an operation to the oldest queued HTTP-authentication request.
fn with_http_auth_request<T: Copy>(
    handle: u64,
    fallback: T,
    operation: impl FnOnce(&HttpAuthRequestSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    native_view
        .http_auth_requests
        .borrow()
        .front()
        .map_or(fallback, operation)
}

#[unsafe(no_mangle)]
/// Returns the number of retained HTTP-authentication requests awaiting Dart.
pub extern "C" fn webview_flutter_linux_wpe_http_auth_request_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.http_auth_requests
            .borrow()
            .len()
            .min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Returns the stable ID of the oldest HTTP-authentication request.
pub extern "C" fn webview_flutter_linux_wpe_http_auth_request_id(handle: u64) -> u64 {
    with_http_auth_request(handle, 0, |request| request.id)
}

#[unsafe(no_mangle)]
/// Returns whether the oldest HTTP-authentication request supplied a realm.
pub extern "C" fn webview_flutter_linux_wpe_http_auth_request_has_realm(handle: u64) -> i32 {
    with_http_auth_request(handle, 0, |request| i32::from(request.has_realm))
}

#[unsafe(no_mangle)]
/// Returns a copied-field length for the oldest HTTP-authentication request.
///
/// Field zero is the host and field one is the realm. Unknown fields return
/// zero, as do valid empty strings; callers use `has_realm` to distinguish a
/// missing realm from an explicitly empty one.
pub extern "C" fn webview_flutter_linux_wpe_http_auth_request_field_length(
    handle: u64,
    field: u32,
) -> usize {
    with_http_auth_request(handle, 0, |request| match field {
        0 => request.host.len(),
        1 => request.realm.len(),
        _ => 0,
    })
}

#[unsafe(no_mangle)]
/// Copies a host or realm from the oldest HTTP-authentication request.
///
/// Returns the copied byte count, `-1` for a null destination, `-2` for an
/// invalid handle or field, and `-3` when the destination is too small.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes.
pub unsafe extern "C" fn webview_flutter_linux_wpe_http_auth_request_copy_field(
    handle: u64,
    field: u32,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_http_auth_request(handle, -2, |request| {
        let bytes = match field {
            0 => request.host.as_slice(),
            1 => request.realm.as_slice(),
            _ => return -2,
        };
        if destination_length < bytes.len() || bytes.len() > i32::MAX as usize {
            return -3;
        }
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), destination, bytes.len()) };
        bytes.len() as i32
    })
}

#[unsafe(no_mangle)]
/// Moves the oldest HTTP-authentication request into the pending-response map.
pub extern "C" fn webview_flutter_linux_wpe_http_auth_request_take(handle: u64) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let Some(request) = native_view.http_auth_requests.borrow_mut().pop_front() else {
        return 1;
    };
    native_view
        .pending_http_auth_requests
        .borrow_mut()
        .insert(request.id, request.request);
    0
}

#[unsafe(no_mangle)]
/// Supplies session-only username/password credentials exactly once.
///
/// Credential persistence is deliberately `NONE`: applications can retain or
/// retrieve secrets in their own credential store without silently causing
/// WebKit to write them to host storage. Returns `-1` for an invalid handle,
/// `-2` for an unknown/already-resolved request ID, `-3` for null or invalid
/// UTF-8 credential strings, and `-4` if WebKit cannot allocate a credential.
///
/// # Safety
///
/// `username` and `password` must point to readable NUL-terminated UTF-8 for
/// the duration of this call.
pub unsafe extern "C" fn webview_flutter_linux_wpe_http_auth_request_proceed(
    handle: u64,
    request_id: u64,
    username: *const c_char,
    password: *const c_char,
) -> i32 {
    if username.is_null() || password.is_null() {
        return -3;
    }
    if unsafe { CStr::from_ptr(username) }.to_str().is_err()
        || unsafe { CStr::from_ptr(password) }.to_str().is_err()
    {
        return -3;
    }
    // WEBKIT_CREDENTIAL_PERSISTENCE_NONE is zero in WebKit's public ABI.
    let credential = unsafe { webkit_credential_new(username, password, 0) };
    if credential.is_null() {
        return -4;
    }
    let status = if let Some(native_view) = native_view(handle) {
        if let Some(request) = native_view
            .pending_http_auth_requests
            .borrow_mut()
            .remove(&request_id)
        {
            let request = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&request).0
                as *mut WebKitAuthenticationRequest;
            unsafe { webkit_authentication_request_authenticate(request, credential) };
            0
        } else {
            -2
        }
    } else {
        -1
    };
    unsafe { webkit_credential_free(credential) };
    status
}

#[unsafe(no_mangle)]
/// Cancels one delivered HTTP-authentication request exactly once.
pub extern "C" fn webview_flutter_linux_wpe_http_auth_request_cancel(
    handle: u64,
    request_id: u64,
) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let Some(request) = native_view
        .pending_http_auth_requests
        .borrow_mut()
        .remove(&request_id)
    else {
        return -2;
    };
    let request = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&request)
        .0
        .cast::<WebKitAuthenticationRequest>();
    unsafe { webkit_authentication_request_cancel(request) };
    0
}

/// Applies an operation to the oldest queued TLS-authentication error.
fn with_ssl_auth_error<T: Copy>(
    handle: u64,
    fallback: T,
    operation: impl FnOnce(&SslAuthErrorSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    native_view
        .ssl_auth_errors
        .borrow()
        .front()
        .map_or(fallback, operation)
}

#[unsafe(no_mangle)]
/// Returns the number of retained TLS certificate failures awaiting Dart.
pub extern "C" fn webview_flutter_linux_wpe_ssl_auth_error_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.ssl_auth_errors.borrow().len().min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Returns the stable ID of the oldest TLS certificate failure.
pub extern "C" fn webview_flutter_linux_wpe_ssl_auth_error_id(handle: u64) -> u64 {
    with_ssl_auth_error(handle, 0, |error| error.id)
}

#[unsafe(no_mangle)]
/// Returns GLib's certificate-verification flag bitmask for the oldest error.
pub extern "C" fn webview_flutter_linux_wpe_ssl_auth_error_flags(handle: u64) -> u32 {
    with_ssl_auth_error(handle, 0, |error| error.error_flags)
}

#[unsafe(no_mangle)]
/// Returns the failing URL byte length for the oldest TLS error.
pub extern "C" fn webview_flutter_linux_wpe_ssl_auth_error_url_length(handle: u64) -> usize {
    with_ssl_auth_error(handle, 0, |error| error.url.len())
}

#[unsafe(no_mangle)]
/// Copies the failing URL for the oldest TLS error into Dart-owned memory.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes.
pub unsafe extern "C" fn webview_flutter_linux_wpe_ssl_auth_error_copy_url(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_ssl_auth_error(handle, -2, |error| {
        if destination_length < error.url.len() || error.url.len() > i32::MAX as usize {
            return -3;
        }
        unsafe { std::ptr::copy_nonoverlapping(error.url.as_ptr(), destination, error.url.len()) };
        error.url.len() as i32
    })
}

#[unsafe(no_mangle)]
/// Returns the DER certificate byte length for the oldest TLS error.
pub extern "C" fn webview_flutter_linux_wpe_ssl_auth_error_certificate_length(
    handle: u64,
) -> usize {
    with_ssl_auth_error(handle, 0, |error| error.certificate_der.len())
}

#[unsafe(no_mangle)]
/// Copies the DER certificate for the oldest TLS error into Dart-owned memory.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes.
pub unsafe extern "C" fn webview_flutter_linux_wpe_ssl_auth_error_copy_certificate(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_ssl_auth_error(handle, -2, |error| {
        if destination_length < error.certificate_der.len()
            || error.certificate_der.len() > i32::MAX as usize
        {
            return -3;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(
                error.certificate_der.as_ptr(),
                destination,
                error.certificate_der.len(),
            )
        };
        error.certificate_der.len() as i32
    })
}

#[unsafe(no_mangle)]
/// Moves the oldest TLS error into the pending-response map.
pub extern "C" fn webview_flutter_linux_wpe_ssl_auth_error_take(handle: u64) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let Some(error) = native_view.ssl_auth_errors.borrow_mut().pop_front() else {
        return 1;
    };
    native_view
        .pending_ssl_auth_errors
        .borrow_mut()
        .insert(error.id, error);
    0
}

#[unsafe(no_mangle)]
/// Cancels or proceeds past one delivered TLS certificate failure.
///
/// Cancellation only releases retained state because WPE already terminated
/// the failing load. Proceeding installs a session exception for the exact
/// certificate/host pair and reloads the copied URL. Returns `-1` for an
/// invalid handle, `-2` for an unknown/already-resolved ID, `-3` for invalid
/// retained strings, and `-4` if the view's network session is unavailable.
pub extern "C" fn webview_flutter_linux_wpe_ssl_auth_error_resolve(
    handle: u64,
    request_id: u64,
    proceed: i32,
) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let Some(error) = native_view
        .pending_ssl_auth_errors
        .borrow_mut()
        .remove(&request_id)
    else {
        return -2;
    };
    if proceed == 0 {
        return 0;
    }
    let host = match std::ffi::CString::new(error.host) {
        Ok(host) => host,
        Err(_) => return -3,
    };
    let url = match std::ffi::CString::new(error.url) {
        Ok(url) => url,
        Err(_) => return -3,
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -4;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    let session = unsafe { webkit_web_view_get_network_session(webview) };
    if session.is_null() {
        return -4;
    }
    let certificate = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&error.certificate)
        .0 as *mut GTlsCertificate;
    unsafe {
        webkit_network_session_allow_tls_certificate_for_host(session, certificate, host.as_ptr());
    }
    {
        let mut count = native_view.approved_navigation_count.borrow_mut();
        *count = count.saturating_add(1);
    }
    unsafe { webkit_web_view_load_uri(webview, url.as_ptr()) };
    0
}
