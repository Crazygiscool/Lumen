// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Per-view ownership state and the platform-thread handle registry.

use super::{prelude::*, storage};

/// Strong owner for the WebKit object and its transfer-none WPE children.
///
/// `webview` keeps `view` and `toplevel` alive. The raw child pointers must
/// never be used after the owning `glib::Object` is dropped.
pub(super) struct WpeRuntime {
    pub(super) webview: glib::Object,
    pub(super) network_session: glib::Object,
    pub(super) download_started_handler_id: Option<glib::SignalHandlerId>,
    pub(super) input_method_context: glib::Object,
    pub(super) user_content_manager: glib::Object,
    pub(super) javascript_channels: HashMap<String, JavaScriptChannelRegistration>,
    pub(super) presentation_style_sheet: *mut WebKitUserStyleSheet,
    pub(super) view: *mut WpeView,
    pub(super) toplevel: *mut WpeToplevel,
}

impl Drop for WpeRuntime {
    fn drop(&mut self) {
        unregister_cursor_view(self.view);
        if let Some(handler_id) = self.download_started_handler_id.take() {
            self.network_session.disconnect(handler_id);
        }
    }
}

/// Ownership root for one public native handle.
///
/// Browser/menu state uses `RefCell` because it remains platform-thread local.
/// Texture state uses `Arc` because Irondash also retains it for raster-thread
/// callbacks. The registry and signal closures share this object via `Rc` and
/// `Weak`; the browser object itself never crosses threads.
pub(super) struct NativeView {
    pub(super) runtime: RefCell<Option<WpeRuntime>>,
    /// Monotonic microsecond time of the newest touch or scroll event.
    ///
    /// WPE WebKit 2.52 can retire continuous scrolling on its dedicated
    /// scrolling thread slightly after the UI process accepts the terminal
    /// event. Visibility and disposal use this value to avoid tearing down the
    /// scrolling tree during that bounded handoff.
    pub(super) last_scroll_input_micros: Cell<i64>,
    /// Invalidates a previously scheduled visibility transition.
    pub(super) visibility_generation: Cell<u64>,
    /// Last POST-header handoff created for this view.
    ///
    /// The web process removes a claimed file. Keeping its path here lets the
    /// next navigation or disposal clean up a suppressed, unclaimed request.
    pub(super) pending_request_header_handoff: RefCell<Option<std::path::PathBuf>>,
    pub(super) geolocation_enabled: Cell<bool>,
    pub(super) cursor: RefCell<CursorSnapshot>,
    pub(super) context_menu: RefCell<Option<ContextMenuSnapshot>>,
    pub(super) option_menu: RefCell<Option<OptionMenuSnapshot>>,
    pub(super) input_method: RefCell<InputMethodSnapshot>,
    pub(super) navigation_events: RefCell<VecDeque<NavigationEventSnapshot>>,
    /// Frame identities announced before or just after UI policy creation.
    ///
    /// WPE's public UI-process navigation action omits target `FrameInfo`.
    /// UI-process user scripts cover ordinary JavaScript-enabled documents;
    /// the web-process extension covers disabled-script custom schemes, while
    /// request and response gates classify network and local-resource loads.
    pub(super) navigation_frame_hints: RefCell<VecDeque<NavigationFrameHint>>,
    pub(super) javascript_results: RefCell<VecDeque<JavaScriptResultSnapshot>>,
    pub(super) javascript_messages: RefCell<VecDeque<JavaScriptMessageSnapshot>>,
    pub(super) navigation_policy_requests: RefCell<VecDeque<NavigationPolicyRequestSnapshot>>,
    pub(super) pending_policy_decisions: RefCell<HashMap<u64, NavigationPolicyBackend>>,
    /// Unsupported-scheme policies awaiting isolated-world frame evidence.
    pub(super) deferred_navigation_policies: RefCell<VecDeque<DeferredNavigationPolicy>>,
    /// UI policies and one-shot files awaiting the web-process request gate.
    pub(super) web_process_policy_gates: RefCell<VecDeque<PreparedNavigationPolicyGate>>,
    /// Local-resource URLs waiting for authoritative response-frame metadata.
    pub(super) response_policy_gates: RefCell<VecDeque<Vec<u8>>>,
    pub(super) script_dialog_requests: RefCell<VecDeque<ScriptDialogRequestSnapshot>>,
    pub(super) pending_script_dialogs: RefCell<HashMap<u64, ScriptDialogRequestSnapshot>>,
    pub(super) permission_requests: RefCell<VecDeque<PermissionRequestSnapshot>>,
    pub(super) pending_permission_requests: RefCell<HashMap<u64, PermissionRequestSnapshot>>,
    /// Decisions keyed by serialized security origin and one permission bit.
    ///
    /// WebKit asks the embedder to answer `navigator.permissions.query()`
    /// independently from the request that originally reached Flutter. The
    /// cache remains view-scoped so one controller cannot silently grant a
    /// capability to another controller displaying the same origin.
    pub(super) permission_states: RefCell<HashMap<(Vec<u8>, u32), i32>>,
    pub(super) notification_requests: RefCell<VecDeque<NotificationSnapshot>>,
    pub(super) pending_notifications: RefCell<HashMap<u64, NotificationSnapshot>>,
    pub(super) notification_closed_events: RefCell<VecDeque<u64>>,
    pub(super) http_auth_requests: RefCell<VecDeque<HttpAuthRequestSnapshot>>,
    pub(super) pending_http_auth_requests: RefCell<HashMap<u64, glib::Object>>,
    pub(super) ssl_auth_errors: RefCell<VecDeque<SslAuthErrorSnapshot>>,
    pub(super) pending_ssl_auth_errors: RefCell<HashMap<u64, SslAuthErrorSnapshot>>,
    pub(super) file_chooser_requests: RefCell<VecDeque<FileChooserRequestSnapshot>>,
    pub(super) pending_file_chooser_requests: RefCell<HashMap<u64, glib::Object>>,
    pub(super) download_requests: RefCell<VecDeque<DownloadRequestSnapshot>>,
    pub(super) pending_download_request_ids: RefCell<HashSet<u64>>,
    pub(super) active_downloads: RefCell<HashMap<u64, glib::Object>>,
    pub(super) download_events: RefCell<VecDeque<DownloadEventSnapshot>>,
    pub(super) popup_requests: RefCell<VecDeque<PopupRequestSnapshot>>,
    pub(super) owned_popup_handles: RefCell<HashSet<u64>>,
    pub(super) close_requested: AtomicBool,
    pub(super) fullscreen_events: RefCell<VecDeque<bool>>,
    pub(super) fullscreen: AtomicBool,
    /// Number of ad-blocked subrequests reported by the web process since the
    /// view was created. Read through `take_blocked_count`.
    pub(super) blocked_count: Cell<u64>,
    /// Whether the active main-frame load ended in a native failure.
    ///
    /// WebKit follows a failed-load signal with `WEBKIT_LOAD_FINISHED`; this
    /// flag suppresses that terminal lifecycle notification so Dart does not
    /// report a failed navigation as `onPageFinished`.
    pub(super) main_frame_load_failed: Cell<bool>,
    /// Whether WebKit is fetching a main-frame document before commit.
    ///
    /// Server redirects emitted during this interval remain main-frame
    /// navigations. Remembering the provisional interval lets the UI process
    /// classify those redirects without synchronously consulting the content
    /// process that WebKit may replace for a cross-site destination.
    pub(super) main_frame_load_provisional: Cell<bool>,
    pub(super) accessibility: RefCell<AccessibilitySnapshot>,
    pub(super) approved_navigation_count: RefCell<u32>,
    pub(super) next_policy_request_id: RefCell<u64>,
    pub(super) next_script_dialog_id: RefCell<u64>,
    pub(super) next_permission_request_id: RefCell<u64>,
    pub(super) next_notification_id: RefCell<u64>,
    pub(super) next_http_auth_request_id: RefCell<u64>,
    pub(super) next_ssl_auth_error_id: RefCell<u64>,
    pub(super) next_file_chooser_request_id: RefCell<u64>,
    pub(super) next_download_id: RefCell<u64>,
    pub(super) engine_handle: i64,
    pub(super) metrics: WpeMetrics,
    pub(super) texture: std::sync::Arc<crate::linux_texture::TextureState>,
}

thread_local! {
    // WPE/GLib objects may only be accessed on their creation thread. Calls
    // from another thread see a distinct empty registry instead of unsafely
    // treating NativeView as Send.
    pub(super) static VIEWS: RefCell<HashMap<u64, Rc<NativeView>>> = RefCell::new(HashMap::new());
    // A disposed public handle can briefly retain its native runtime while the
    // AT-SPI worker discards already-queued state. Keeping this ownership on
    // the platform thread gives browser teardown deterministic queue ordering.
    // Entries are invisible to every public FFI lookup and are removed only
    // after the worker acknowledges `DropView`.
    pub(super) static PENDING_ACCESSIBILITY_DISPOSALS: RefCell<HashMap<u64, Rc<NativeView>>> =
        RefCell::new(HashMap::new());
    // Handles are identifiers, not pointers. Zero is permanently reserved for
    // “no view” and is also the fallback returned by read-only accessors.
    static NEXT_HANDLE: RefCell<u64> = const { RefCell::new(1) };
    // Cookie APIs are application-wide and may run before a WebView exists.
    // The platform thread drains this queue through handle-free FFI accessors.
    pub(super) static COOKIE_RESULTS: RefCell<VecDeque<storage::CookieResultSnapshot>> = const {
        RefCell::new(VecDeque::new())
    };
    // Website-data operations share the application network session and must
    // survive without an attached view.
    pub(super) static WEBSITE_DATA_RESULTS: RefCell<VecDeque<storage::WebsiteDataResultSnapshot>> = const {
        RefCell::new(VecDeque::new())
    };
}

/// Resolves a public handle and clones its platform-thread `Rc`.
///
/// The registry borrow ends before the returned object is used, which permits
/// GLib signal re-entrancy without a nested `RefCell` borrow of `VIEWS`.
pub(super) fn native_view(handle: u64) -> Option<Rc<NativeView>> {
    if handle == 0 {
        return None;
    }
    VIEWS.with_borrow(|views| views.get(&handle).cloned())
}

/// Allocates the next non-zero process-local handle.
///
/// Wrapping is handled defensively. Exhausting the complete `u64` space in one
/// process is not realistic, and zero remains reserved after wraparound.
pub(super) fn next_handle() -> u64 {
    NEXT_HANDLE.with_borrow_mut(|next| {
        let handle = (*next).max(1);
        *next = handle.wrapping_add(1).max(1);
        handle
    })
}

/// Allocates the handle-scoped state and Flutter texture shared by ordinary
/// views and WebKit-created popup children.
///
/// Keeping this initializer in one place is important for popup parity: a
/// related view must expose the same dialogs, permissions, IME, downloads,
/// navigation, and diagnostics as a controller-created view. The browser
/// object itself is installed transactionally by the caller only after WPE
/// construction succeeds.
pub(super) fn new_native_view(engine_handle: i64) -> Result<Rc<NativeView>, i32> {
    let texture = crate::linux_texture::TextureState::new(engine_handle)?;
    Ok(Rc::new(NativeView {
        runtime: RefCell::new(None),
        last_scroll_input_micros: Cell::new(0),
        visibility_generation: Cell::new(0),
        pending_request_header_handoff: RefCell::new(None),
        geolocation_enabled: Cell::new(true),
        cursor: RefCell::new(CursorSnapshot::default()),
        context_menu: RefCell::new(None),
        option_menu: RefCell::new(None),
        input_method: RefCell::new(InputMethodSnapshot::default()),
        navigation_events: RefCell::new(VecDeque::new()),
        navigation_frame_hints: RefCell::new(VecDeque::new()),
        javascript_results: RefCell::new(VecDeque::new()),
        javascript_messages: RefCell::new(VecDeque::new()),
        navigation_policy_requests: RefCell::new(VecDeque::new()),
        pending_policy_decisions: RefCell::new(HashMap::new()),
        deferred_navigation_policies: RefCell::new(VecDeque::new()),
        web_process_policy_gates: RefCell::new(VecDeque::new()),
        response_policy_gates: RefCell::new(VecDeque::new()),
        script_dialog_requests: RefCell::new(VecDeque::new()),
        pending_script_dialogs: RefCell::new(HashMap::new()),
        permission_requests: RefCell::new(VecDeque::new()),
        pending_permission_requests: RefCell::new(HashMap::new()),
        permission_states: RefCell::new(HashMap::new()),
        notification_requests: RefCell::new(VecDeque::new()),
        pending_notifications: RefCell::new(HashMap::new()),
        notification_closed_events: RefCell::new(VecDeque::new()),
        http_auth_requests: RefCell::new(VecDeque::new()),
        pending_http_auth_requests: RefCell::new(HashMap::new()),
        ssl_auth_errors: RefCell::new(VecDeque::new()),
        pending_ssl_auth_errors: RefCell::new(HashMap::new()),
        file_chooser_requests: RefCell::new(VecDeque::new()),
        pending_file_chooser_requests: RefCell::new(HashMap::new()),
        download_requests: RefCell::new(VecDeque::new()),
        pending_download_request_ids: RefCell::new(HashSet::new()),
        active_downloads: RefCell::new(HashMap::new()),
        download_events: RefCell::new(VecDeque::new()),
        popup_requests: RefCell::new(VecDeque::new()),
        owned_popup_handles: RefCell::new(HashSet::new()),
        close_requested: AtomicBool::new(false),
        fullscreen_events: RefCell::new(VecDeque::new()),
        fullscreen: AtomicBool::new(false),
        blocked_count: Cell::new(0),
        main_frame_load_failed: Cell::new(false),
        main_frame_load_provisional: Cell::new(false),
        accessibility: RefCell::new(AccessibilitySnapshot::default()),
        // WebKit may emit one policy action for its implicit about:blank before
        // the first real URI. The first non-blank load-start removes any unused
        // allowance so subsequent page actions are still delegated to Dart.
        approved_navigation_count: RefCell::new(2),
        next_policy_request_id: RefCell::new(1),
        next_script_dialog_id: RefCell::new(1),
        next_permission_request_id: RefCell::new(1),
        next_notification_id: RefCell::new(1),
        next_http_auth_request_id: RefCell::new(1),
        next_ssl_auth_error_id: RefCell::new(1),
        next_file_chooser_request_id: RefCell::new(1),
        next_download_id: RefCell::new(1),
        engine_handle,
        metrics: WpeMetrics::default(),
        texture,
    }))
}
