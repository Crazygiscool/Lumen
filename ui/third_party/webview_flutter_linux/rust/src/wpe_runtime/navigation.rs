// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Main-frame navigation commands, lifecycle signals, history, and events.
//!
//! WebKit remains the source of truth for history and network loading. This
//! module connects its lifecycle signals, stores bounded owned snapshots, and
//! exposes navigation operations and event polling through the C ABI.

use super::prelude::*;

const MAX_NAVIGATION_FRAME_HINTS: usize = 64;
const MAX_WEB_PROCESS_POLICY_GATES: usize = 64;
const MAX_RESPONSE_POLICY_GATES: usize = 64;
const MAX_DEFERRED_FRAME_POLICIES: usize = 64;
const DEFERRED_FRAME_POLICY_TIMEOUT: std::time::Duration = std::time::Duration::from_millis(250);

/// Immutable browser lifecycle event waiting for Dart to poll it.
///
/// WebKit signal arguments are borrowed for the duration of the callback, so
/// the URI is copied immediately. A bounded FIFO preserves short redirect and
/// lifecycle sequences even when several signals arrive during one GLib pump.
pub(super) struct NavigationEventSnapshot {
    pub(super) kind: u32,
    pub(super) url: Vec<u8>,
    pub(super) progress: u32,
    pub(super) code: i32,
    pub(super) detail: Vec<u8>,
    pub(super) is_main_frame: i32,
}

/// One page-announced navigation destination and its target frame class.
///
/// The Navigation API event runs in the frame initiating the navigation, so
/// `window === window.top` is an authoritative frame answer unavailable from
/// WPE's public UI-process `WebKitNavigationAction` wrapper. Hints are copied
/// across the process boundary before the corresponding policy decision.
pub(super) struct NavigationFrameHint {
    pub(super) url: Vec<u8>,
    pub(super) is_main_frame: bool,
}

/// One UI policy decision waiting for a late isolated-world frame hint.
///
/// WPE emits unsupported-scheme policy actions just before delivering the
/// web-process extension message that identifies a statically parsed iframe.
/// Retaining the decision for that short IPC handoff preserves both accurate
/// frame classification and the ability for Dart to prevent the navigation.
pub(super) struct DeferredNavigationPolicy {
    pub(super) id: u64,
    pub(super) url: Vec<u8>,
    pub(super) backend: NavigationPolicyBackend,
}

/// Decodes the bounded wire message emitted by the Navigation API bridge.
///
/// `M\n<url>` identifies the main frame and `S\n<url>` a subframe. URLs may
/// contain newlines, so only the fixed two-byte prefix is interpreted.
pub(super) fn navigation_frame_hint(message: &[u8]) -> Option<NavigationFrameHint> {
    if message.len() < 3 || message.len() > 64 * 1024 || message[1] != b'\n' {
        return None;
    }
    let is_main_frame = match message[0] {
        b'M' => true,
        b'S' => false,
        _ => return None,
    };
    Some(NavigationFrameHint {
        url: message[2..].to_vec(),
        is_main_frame,
    })
}

/// Adds one frame hint while bounding pages that issue abandoned navigations.
pub(super) fn enqueue_navigation_frame_hint(
    hints: &mut VecDeque<NavigationFrameHint>,
    hint: NavigationFrameHint,
) {
    if hints
        .iter()
        .any(|existing| existing.url == hint.url && existing.is_main_frame == hint.is_main_frame)
    {
        return;
    }
    if hints.len() == MAX_NAVIGATION_FRAME_HINTS {
        hints.pop_front();
    }
    hints.push_back(hint);
}

/// Consumes the oldest exact destination match for a policy decision.
///
/// Exact URL matching prevents an unrelated frame event from changing a
/// decision. The FIFO position preserves repeated same-URL navigations in the
/// order WebKit delivered their bridge and policy messages.
fn take_navigation_frame_hint(native_view: &NativeView, url: &[u8]) -> Option<bool> {
    let mut hints = native_view.navigation_frame_hints.borrow_mut();
    let index = hints.iter().position(|hint| hint.url == url)?;
    hints.remove(index).map(|hint| hint.is_main_frame)
}

/// Publishes a retained policy to Dart after its frame class is known.
fn publish_navigation_policy(
    native_view: &NativeView,
    deferred: DeferredNavigationPolicy,
    is_main_frame: bool,
) {
    native_view
        .navigation_policy_requests
        .borrow_mut()
        .push_back(NavigationPolicyRequestSnapshot {
            id: deferred.id,
            url: deferred.url,
            is_main_frame,
            backend: deferred.backend,
        });
}

/// Resolves the oldest exact deferred URL from an extension announcement.
pub(super) fn resolve_deferred_navigation_policy(
    native_view: &NativeView,
    url: &[u8],
    is_main_frame: bool,
) -> bool {
    let deferred = {
        let mut policies = native_view.deferred_navigation_policies.borrow_mut();
        let Some(index) = policies.iter().position(|policy| policy.url == url) else {
            return false;
        };
        policies.remove(index)
    };
    let Some(deferred) = deferred else {
        return false;
    };
    publish_navigation_policy(native_view, deferred, is_main_frame);
    true
}

/// Falls back conservatively if an expected extension hint never arrives.
fn resolve_deferred_navigation_policy_timeout(native_view: &NativeView, id: u64) {
    let deferred = {
        let mut policies = native_view.deferred_navigation_policies.borrow_mut();
        let Some(index) = policies.iter().position(|policy| policy.id == id) else {
            return;
        };
        policies.remove(index)
    };
    if let Some(deferred) = deferred {
        publish_navigation_policy(native_view, deferred, true);
    }
}

/// Retains an unsupported-scheme action across the short extension IPC race.
fn defer_navigation_policy(
    native_view: &Rc<NativeView>,
    url: Vec<u8>,
    backend: NavigationPolicyBackend,
) {
    let id = next_navigation_policy_request_id(native_view);
    let evicted = {
        let mut policies = native_view.deferred_navigation_policies.borrow_mut();
        let evicted = (policies.len() == MAX_DEFERRED_FRAME_POLICIES)
            .then(|| policies.pop_front())
            .flatten();
        policies.push_back(DeferredNavigationPolicy { id, url, backend });
        evicted
    };
    if let Some(evicted) = evicted {
        publish_navigation_policy(native_view, evicted, true);
    }
    let deferred_view = Rc::downgrade(native_view);
    glib::timeout_add_local_once(DEFERRED_FRAME_POLICY_TIMEOUT, move || {
        if let Some(native_view) = deferred_view.upgrade() {
            resolve_deferred_navigation_policy_timeout(&native_view, id);
        }
    });
}

/// Allocates one non-zero identifier shared by both native policy backends.
pub(super) fn next_navigation_policy_request_id(native_view: &NativeView) -> u64 {
    let mut next = native_view.next_policy_request_id.borrow_mut();
    let current = (*next).max(1);
    *next = current.wrapping_add(1).max(1);
    current
}

/// Records a UI policy action provisionally advanced to `send-request`.
fn enqueue_web_process_policy_gate(native_view: &NativeView, url: &[u8]) -> bool {
    let Ok(gate) = prepare_navigation_policy_gate(url) else {
        return false;
    };
    let mut gates = native_view.web_process_policy_gates.borrow_mut();
    if gates.len() == MAX_WEB_PROCESS_POLICY_GATES
        && let Some(evicted) = gates.pop_front()
    {
        discard_navigation_policy_gate(&evicted);
    }
    gates.push_back(gate);
    true
}

/// Claims the oldest exact URL expected at the web-process request gate.
pub(super) fn take_web_process_policy_gate(native_view: &NativeView, url: &[u8]) -> bool {
    let mut gates = native_view.web_process_policy_gates.borrow_mut();
    let Some(index) = gates.iter().position(|pending| pending.url == url) else {
        return false;
    };
    let Some(gate) = gates.remove(index) else {
        return false;
    };
    discard_navigation_policy_gate(&gate);
    true
}

fn enqueue_response_policy_gate(native_view: &NativeView, url: Vec<u8>) {
    let mut gates = native_view.response_policy_gates.borrow_mut();
    if gates.len() == MAX_RESPONSE_POLICY_GATES {
        gates.pop_front();
    }
    gates.push_back(url);
}

fn take_response_policy_gate(native_view: &NativeView, url: &[u8]) -> bool {
    let mut gates = native_view.response_policy_gates.borrow_mut();
    let Some(index) = gates.iter().position(|pending| pending == url) else {
        return false;
    };
    gates.remove(index);
    true
}

fn uses_web_process_policy_gate(url: &[u8]) -> bool {
    url.starts_with(b"http://") || url.starts_with(b"https://")
}

fn uses_response_policy_gate(url: &[u8]) -> bool {
    url.starts_with(b"data:") || url.starts_with(b"file:") || url.starts_with(b"about:")
}

/// Copies the current main-frame URI from a live WebKit view.
pub(super) fn webview_uri(webview: *mut WebKitWebView) -> Vec<u8> {
    let uri = unsafe { webkit_web_view_get_uri(webview) };
    if uri.is_null() {
        Vec::new()
    } else {
        unsafe { CStr::from_ptr(uri) }.to_bytes().to_vec()
    }
}

/// Copies one WebKit network error into the existing federated event shape.
///
/// `GError` and URI pointers received from WebKit signals are transfer-none;
/// this helper never stores either pointer and owns every byte in the returned
/// snapshot.
fn resource_error_snapshot(
    url: Vec<u8>,
    error: *mut glib::ffi::GError,
    is_main_frame: bool,
) -> NavigationEventSnapshot {
    let (code, detail) = if error.is_null() {
        (-1, b"WebKit resource load failed".to_vec())
    } else {
        let detail = if unsafe { (*error).message.is_null() } {
            b"WebKit resource load failed".to_vec()
        } else {
            unsafe { CStr::from_ptr((*error).message) }
                .to_bytes()
                .to_vec()
        };
        (unsafe { (*error).code }, detail)
    };
    NavigationEventSnapshot {
        kind: NAVIGATION_EVENT_RESOURCE_ERROR,
        url,
        progress: 0,
        code,
        detail,
        is_main_frame: i32::from(is_main_frame),
    }
}

/// Appends one event to the Dart-facing queue without allowing unbounded growth.
///
/// Consecutive progress notifications are coalesced because WebKit may emit
/// many of them between Flutter's 16 ms polling ticks. Structural lifecycle
/// events are never coalesced, so started/redirected/committed/finished ordering
/// remains observable.
fn push_navigation_event(
    native_view: &Weak<NativeView>,
    kind: u32,
    webview: *mut WebKitWebView,
    progress: u32,
) {
    let Some(native_view) = native_view.upgrade() else {
        return;
    };
    let event = NavigationEventSnapshot {
        kind,
        url: webview_uri(webview),
        progress: progress.min(100),
        code: 0,
        detail: Vec::new(),
        is_main_frame: 1,
    };
    let mut events = native_view.navigation_events.borrow_mut();
    enqueue_navigation_event(&mut events, event);
}

/// Inserts a lifecycle snapshot while enforcing queue and coalescing policy.
pub(super) fn enqueue_navigation_event(
    events: &mut VecDeque<NavigationEventSnapshot>,
    event: NavigationEventSnapshot,
) {
    let kind = event.kind;
    if kind == NAVIGATION_EVENT_PROGRESS
        && let Some(previous) = events.back_mut()
        && previous.kind == NAVIGATION_EVENT_PROGRESS
    {
        *previous = event;
        return;
    }
    if events.len() == MAX_NAVIGATION_EVENTS {
        events.pop_front();
    }
    events.push_back(event);
}

/// Filters WebKit's misleading terminal event after a main-frame failure.
///
/// WPE emits `WEBKIT_LOAD_FINISHED` after `load-failed` and
/// `load-failed-with-tls-errors`. The federated API treats `onPageFinished` as
/// successful completion, so the terminal event must be consumed exactly once
/// after a failure. A new start always resets the state for the next load.
pub(super) fn should_enqueue_main_frame_lifecycle(
    kind: u32,
    main_frame_load_failed: &Cell<bool>,
) -> bool {
    match kind {
        NAVIGATION_EVENT_STARTED => {
            main_frame_load_failed.set(false);
            true
        }
        NAVIGATION_EVENT_FINISHED => !main_frame_load_failed.replace(false),
        _ => true,
    }
}

/// Identifies a server redirect belonging to the provisional main-frame load.
///
/// A redirect stays in the frame that initiated its request. Before the main
/// document commits, subordinate documents cannot yet be created by that new
/// document, so a redirect reported in this interval belongs to the main
/// frame. Resolving it from the UI-process policy object avoids a synchronous
/// message to a content process that WebKit may be replacing for a cross-site
/// destination.
pub(super) fn is_provisional_main_frame_redirect(
    is_redirect: bool,
    main_frame_load_provisional: bool,
) -> bool {
    is_redirect && main_frame_load_provisional
}

/// Connects WebKit's real main-frame lifecycle and progress signals.
///
/// The `load-changed` argument is a foreign GEnum, so the callback reads it
/// through GLib's enum accessor instead of pretending it is a G_TYPE_INT.
/// Signal callbacks only enqueue owned snapshots; Dart invokes application
/// callbacks later while polling on Flutter's platform thread.
pub(super) fn connect_navigation_events(webview: &glib::Object, native_view: Weak<NativeView>) {
    let raw_webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(webview).0
        as *mut WebKitWebView as usize;
    let load_view = native_view.clone();
    webview.connect_local("load-changed", false, move |values| {
        let load_event = unsafe {
            glib::gobject_ffi::g_value_get_enum(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        };
        let (kind, progress) = match load_event {
            0 => (NAVIGATION_EVENT_STARTED, 0),
            1 => (NAVIGATION_EVENT_REDIRECTED, 0),
            2 => (NAVIGATION_EVENT_COMMITTED, 0),
            3 => (NAVIGATION_EVENT_FINISHED, 100),
            _ => return None,
        };
        if let Some(native_view) = load_view.upgrade() {
            match kind {
                NAVIGATION_EVENT_STARTED => native_view.main_frame_load_provisional.set(true),
                NAVIGATION_EVENT_COMMITTED | NAVIGATION_EVENT_FINISHED => {
                    native_view.main_frame_load_provisional.set(false);
                }
                _ => {}
            }
            if !should_enqueue_main_frame_lifecycle(kind, &native_view.main_frame_load_failed) {
                return None;
            }
        }
        if kind == NAVIGATION_EVENT_STARTED {
            let webview = raw_webview as *mut WebKitWebView;
            if webview_uri(webview) != b"about:blank"
                && let Some(native_view) = load_view.upgrade()
            {
                *native_view.approved_navigation_count.borrow_mut() = 0;
            }
        }
        push_navigation_event(
            &load_view,
            kind,
            raw_webview as *mut WebKitWebView,
            progress,
        );
        None
    });

    // `history.pushState`, `history.replaceState`, and fragment navigation can
    // change the main-frame URI without emitting the load lifecycle above.
    // Reuse the committed snapshot shape because Dart treats it as a URL-state
    // update without synthesizing page-started or page-finished callbacks.
    let uri_view = native_view.clone();
    webview.connect_local("notify::uri", false, move |_| {
        push_navigation_event(
            &uri_view,
            NAVIGATION_EVENT_COMMITTED,
            raw_webview as *mut WebKitWebView,
            0,
        );
        None
    });

    let resource_view = native_view.clone();
    let resource_webview = raw_webview;
    webview.connect_local("resource-load-started", false, move |values| {
        let resource_pointer = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        }
        .cast::<WebKitWebResource>();
        if resource_pointer.is_null() {
            return None;
        }
        let webview_pointer = resource_webview as *mut WebKitWebView;
        let was_main_resource =
            unsafe { webkit_web_view_get_main_resource(webview_pointer) } == resource_pointer;
        // SAFETY: the signal lends a GObject. `from_glib_none` takes a strong
        // reference while the handler is installed and releases only that
        // reference afterward; WebKit retains the resource for its load.
        let resource = unsafe {
            from_glib_none::<*mut glib::gobject_ffi::GObject, glib::Object>(resource_pointer.cast())
        };
        let failed_view = resource_view.clone();
        resource.connect_local("failed", false, move |values| {
            let native_view = failed_view.upgrade()?;
            let resource_pointer = unsafe {
                glib::gobject_ffi::g_value_get_object(
                    ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[0]).0,
                )
            }
            .cast::<WebKitWebResource>();
            if resource_pointer.is_null() {
                return None;
            }
            // Main-resource failures already arrive through `load-failed`.
            // Skipping them here avoids delivering the federated callback
            // twice while retaining every subordinate resource failure.
            let is_main_resource = was_main_resource
                || unsafe { webkit_web_view_get_main_resource(webview_pointer) }
                    == resource_pointer;
            if is_main_resource {
                return None;
            }
            let uri = unsafe { webkit_web_resource_get_uri(resource_pointer) };
            let url = if uri.is_null() {
                Vec::new()
            } else {
                unsafe { CStr::from_ptr(uri) }.to_bytes().to_vec()
            };
            let error = unsafe {
                glib::gobject_ffi::g_value_get_boxed(
                    ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
                )
            }
            .cast::<glib::ffi::GError>();
            enqueue_navigation_event(
                &mut native_view.navigation_events.borrow_mut(),
                resource_error_snapshot(url, error, false),
            );
            None
        });
        None
    });

    let failed_view = native_view.clone();
    webview.connect_local("load-failed", false, move |values| {
        let Some(native_view) = failed_view.upgrade() else {
            return Some(false.to_value());
        };
        native_view.main_frame_load_provisional.set(false);
        native_view.main_frame_load_failed.set(true);
        let failing_uri = unsafe {
            glib::gobject_ffi::g_value_get_string(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[2]).0,
            )
        };
        let error = unsafe {
            glib::gobject_ffi::g_value_get_boxed(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[3]).0,
            )
        }
        .cast::<glib::ffi::GError>();
        let url = if failing_uri.is_null() {
            Vec::new()
        } else {
            unsafe { CStr::from_ptr(failing_uri) }.to_bytes().to_vec()
        };
        enqueue_navigation_event(
            &mut native_view.navigation_events.borrow_mut(),
            resource_error_snapshot(url, error, true),
        );
        // Returning false preserves WebKit's default failed-load behavior.
        Some(false.to_value())
    });

    let terminated_view = native_view.clone();
    webview.connect_local("web-process-terminated", false, move |values| {
        let reason = unsafe {
            glib::gobject_ffi::g_value_get_enum(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        };
        let native_view = terminated_view.upgrade()?;
        native_view.main_frame_load_provisional.set(false);
        native_view.main_frame_load_failed.set(true);
        // Nothing retained from the exited content process may be resolved by
        // Dart after this point. The WebView itself remains alive and can
        // create a replacement process on the application's next navigation.
        cancel_process_bound_requests(&native_view, true);
        enqueue_fullscreen_event(&native_view, false);
        enqueue_navigation_event(
            &mut native_view.navigation_events.borrow_mut(),
            NavigationEventSnapshot {
                kind: NAVIGATION_EVENT_WEB_PROCESS_TERMINATED,
                url: webview_uri(raw_webview as *mut WebKitWebView),
                progress: 0,
                code: reason,
                detail: web_process_termination_description(reason).to_vec(),
                is_main_frame: 1,
            },
        );
        None
    });

    let response_view = native_view.clone();
    webview.connect_local("decide-policy", false, move |values| {
        let decision_type = unsafe {
            glib::gobject_ffi::g_value_get_enum(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[2]).0,
            )
        };
        if decision_type != 2 {
            return Some(false.to_value());
        }
        let decision = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        }
        .cast::<WebKitResponsePolicyDecision>();
        if decision.is_null() {
            return Some(false.to_value());
        }
        let response = unsafe { webkit_response_policy_decision_get_response(decision) };
        if response.is_null() {
            return Some(false.to_value());
        }
        let status = unsafe { webkit_uri_response_get_status_code(response) };
        if !(400..=599).contains(&status) {
            return Some(false.to_value());
        }
        let Some(native_view) = response_view.upgrade() else {
            return Some(false.to_value());
        };
        let uri = unsafe { webkit_uri_response_get_uri(response) };
        let url = if uri.is_null() {
            Vec::new()
        } else {
            unsafe { CStr::from_ptr(uri) }.to_bytes().to_vec()
        };
        enqueue_navigation_event(
            &mut native_view.navigation_events.borrow_mut(),
            NavigationEventSnapshot {
                kind: NAVIGATION_EVENT_HTTP_ERROR,
                url,
                progress: 0,
                code: status.min(i32::MAX as u32) as i32,
                detail: Vec::new(),
                is_main_frame: i32::from(unsafe {
                    webkit_response_policy_decision_is_main_frame_main_resource(decision) != 0
                }),
            },
        );
        // Let WebKit's default handler continue loading the error response.
        Some(false.to_value())
    });

    let policy_view = native_view.clone();
    webview.connect_local("decide-policy", false, move |values| {
        let decision_type = unsafe {
            glib::gobject_ffi::g_value_get_enum(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[2]).0,
            )
        };
        let Some(native_view) = policy_view.upgrade() else {
            return Some(false.to_value());
        };
        let decision = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        };
        if decision.is_null() {
            return Some(false.to_value());
        }
        if decision_type == 2 {
            let response_decision = decision.cast::<WebKitResponsePolicyDecision>();
            let request = unsafe { webkit_response_policy_decision_get_request(response_decision) };
            if request.is_null() {
                return Some(false.to_value());
            }
            let uri = unsafe { webkit_uri_request_get_uri(request) };
            let url = if uri.is_null() {
                Vec::new()
            } else {
                unsafe { CStr::from_ptr(uri) }.to_bytes().to_vec()
            };
            if !take_response_policy_gate(&native_view, &url) {
                return Some(false.to_value());
            }
            let decision: glib::Object = unsafe { glib::translate::from_glib_none(decision) };
            native_view
                .navigation_policy_requests
                .borrow_mut()
                .push_back(NavigationPolicyRequestSnapshot {
                    id: next_navigation_policy_request_id(&native_view),
                    url,
                    is_main_frame: unsafe {
                        webkit_response_policy_decision_is_main_frame_main_resource(
                            response_decision,
                        ) != 0
                    },
                    backend: NavigationPolicyBackend::UiResponse(decision),
                });
            return Some(true.to_value());
        }
        if decision_type != 0 {
            return Some(false.to_value());
        }
        let mut approved = native_view.approved_navigation_count.borrow_mut();
        if *approved > 0 {
            *approved -= 1;
            drop(approved);
            use_policy_decision_with_media_policy(
                raw_webview as *mut WebKitWebView,
                decision.cast::<WebKitPolicyDecision>(),
            );
            return Some(true.to_value());
        }
        drop(approved);
        let navigation_action = unsafe {
            webkit_navigation_policy_decision_get_navigation_action(
                decision.cast::<WebKitNavigationPolicyDecision>(),
            )
        };
        if navigation_action.is_null() {
            return Some(false.to_value());
        }
        let request = unsafe { webkit_navigation_action_get_request(navigation_action) };
        if request.is_null() {
            return Some(false.to_value());
        }
        let uri = unsafe { webkit_uri_request_get_uri(request) };
        let url = if uri.is_null() {
            Vec::new()
        } else {
            unsafe { CStr::from_ptr(uri) }.to_bytes().to_vec()
        };
        if is_provisional_main_frame_redirect(
            unsafe { webkit_navigation_action_is_redirect(navigation_action) } != 0,
            native_view.main_frame_load_provisional.get(),
        ) {
            let decision: glib::Object = unsafe { glib::translate::from_glib_none(decision) };
            native_view
                .navigation_policy_requests
                .borrow_mut()
                .push_back(NavigationPolicyRequestSnapshot {
                    id: next_navigation_policy_request_id(&native_view),
                    url,
                    is_main_frame: true,
                    backend: NavigationPolicyBackend::UiNavigation(decision),
                });
            return Some(true.to_value());
        }
        let Some(is_main_frame) = take_navigation_frame_hint(&native_view, &url) else {
            // WPE's UI action omits target FrameInfo. Network requests use a
            // one-shot web-process gate before dispatch; local resources use
            // response-policy metadata before commit; unsupported schemes wait
            // briefly for the extension-owned isolated-world announcement.
            if uses_web_process_policy_gate(&url) {
                if enqueue_web_process_policy_gate(&native_view, &url) {
                    use_policy_decision_with_media_policy(
                        raw_webview as *mut WebKitWebView,
                        decision.cast::<WebKitPolicyDecision>(),
                    );
                    return Some(true.to_value());
                }
                // A private marker creation failure must not advance a load
                // that Dart can no longer prevent. Retain the original UI
                // decision with the conservative main-frame classification.
                let decision: glib::Object = unsafe { glib::translate::from_glib_none(decision) };
                native_view
                    .navigation_policy_requests
                    .borrow_mut()
                    .push_back(NavigationPolicyRequestSnapshot {
                        id: next_navigation_policy_request_id(&native_view),
                        url,
                        is_main_frame: true,
                        backend: NavigationPolicyBackend::UiNavigation(decision),
                    });
                return Some(true.to_value());
            }
            if uses_response_policy_gate(&url) {
                enqueue_response_policy_gate(&native_view, url);
                use_policy_decision_with_media_policy(
                    raw_webview as *mut WebKitWebView,
                    decision.cast::<WebKitPolicyDecision>(),
                );
                return Some(true.to_value());
            }
            // Unsupported/custom schemes never reach either public WPE gate.
            // The isolated web-process world announces statically parsed
            // iframe destinations just after this callback, so retain the UI
            // decision across that bounded IPC race before publishing it to
            // Dart.
            let decision: glib::Object = unsafe { glib::translate::from_glib_none(decision) };
            defer_navigation_policy(
                &native_view,
                url,
                NavigationPolicyBackend::UiNavigation(decision),
            );
            return Some(true.to_value());
        };
        let id = next_navigation_policy_request_id(&native_view);
        // SAFETY: the signal lends a live GObject. `from_glib_none` acquires a
        // strong reference that remains valid until Dart resolves the request.
        let decision: glib::Object = unsafe { glib::translate::from_glib_none(decision) };
        native_view
            .navigation_policy_requests
            .borrow_mut()
            .push_back(NavigationPolicyRequestSnapshot {
                id,
                url,
                // Native WPE omits target FrameInfo; one of the host-owned
                // frame bridges supplied it before this object reached Dart.
                is_main_frame,
                backend: NavigationPolicyBackend::UiNavigation(decision),
            });
        // The retained decision will be completed asynchronously by Dart.
        Some(true.to_value())
    });

    webview.connect_local("notify::estimated-load-progress", false, move |_| {
        let webview = raw_webview as *mut WebKitWebView;
        let progress = unsafe { webkit_web_view_get_estimated_load_progress(webview) };
        let percent = (progress.clamp(0.0, 1.0) * 100.0).round() as u32;
        push_navigation_event(&native_view, NAVIGATION_EVENT_PROGRESS, webview, percent);
        None
    });
}

#[unsafe(no_mangle)]
/// Validates that a live WPE view can participate in the current pump tick.
///
/// Flutter's Linux runner already owns and advances GLib's process-wide default
/// main context. WPE sources created on the platform thread are dispatched by
/// that outer runner loop. Iterating the same context here would be a nested
/// main loop entered from a Dart FFI call: it can dispatch Flutter engine work,
/// including hot-restart isolate transitions, before the current Dart call has
/// exited. The Dart timer still calls this function as a cheap liveness check
/// before draining native snapshots, but it must never advance GLib itself.
pub extern "C" fn webview_flutter_linux_wpe_pump(handle: u64) -> i32 {
    if native_view(handle).is_none() {
        return -1;
    }
    0
}

/// Reads one WebKit session-history capability for a live view.
///
/// The result is one or zero. `-1` identifies a missing handle or runtime so
/// Dart can distinguish an unavailable view from a valid empty history list.
fn webview_history_capability(
    handle: u64,
    operation: unsafe extern "C" fn(*mut WebKitWebView) -> i32,
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
    i32::from(unsafe { operation(webview) } != 0)
}

#[unsafe(no_mangle)]
/// Returns one when WebKit's native back-forward list has a previous item.
pub extern "C" fn webview_flutter_linux_wpe_can_go_back(handle: u64) -> i32 {
    webview_history_capability(handle, webkit_web_view_can_go_back)
}

#[unsafe(no_mangle)]
/// Returns one when WebKit's native back-forward list has a following item.
pub extern "C" fn webview_flutter_linux_wpe_can_go_forward(handle: u64) -> i32 {
    webview_history_capability(handle, webkit_web_view_can_go_forward)
}

#[unsafe(no_mangle)]
/// Traverses to the previous item in WebKit's native session history.
///
/// Returns `-3` for an invalid or torn-down view. Callers should first inspect
/// [`webview_flutter_linux_wpe_can_go_back`]; WebKit otherwise treats this as a
/// no-op.
pub extern "C" fn webview_flutter_linux_wpe_go_back(handle: u64) -> i32 {
    with_webview(handle, |webview| unsafe {
        webkit_web_view_go_back(webview)
    })
}

#[unsafe(no_mangle)]
/// Traverses to the following item in WebKit's native session history.
pub extern "C" fn webview_flutter_linux_wpe_go_forward(handle: u64) -> i32 {
    with_webview(handle, |webview| unsafe {
        webkit_web_view_go_forward(webview)
    })
}

#[unsafe(no_mangle)]
/// Reloads WebKit's current history item without reconstructing its request.
///
/// Using the engine operation preserves POST bodies, referrer information,
/// cache semantics, scroll restoration, and other state unavailable to Dart's
/// URL-only history model.
pub extern "C" fn webview_flutter_linux_wpe_reload(handle: u64) -> i32 {
    with_webview(handle, |webview| unsafe { webkit_web_view_reload(webview) })
}

#[unsafe(no_mangle)]
/// Starts a main-frame navigation for one WebView.
///
/// WebKit copies the URI before this function returns. Returns `-1`/`-2` for
/// invalid caller strings and `-3` for an invalid or torn-down handle.
pub extern "C" fn webview_flutter_linux_wpe_navigate(handle: u64, url: *const c_char) -> i32 {
    let url =
        match required_c_string(url).and_then(|url| std::ffi::CString::new(url).map_err(|_| -2)) {
            Ok(url) => url,
            Err(status) => return status,
        };
    let Some(native_view) = native_view(handle) else {
        return -3;
    };
    {
        let mut count = native_view.approved_navigation_count.borrow_mut();
        *count = count.saturating_add(1);
    }
    {
        let runtime = native_view.runtime.borrow();
        let Some(runtime) = runtime.as_ref() else {
            return -3;
        };
        let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
            as *mut WebKitWebView;
        // SAFETY: webview is borrowed from the live runtime; WebKit copies URI.
        unsafe { webkit_web_view_load_uri(webview, url.as_ptr()) };
        0
    }
}

#[unsafe(no_mangle)]
/// Loads an HTML document with WebKit's native base-URI semantics.
///
/// Unlike a `data:` URL or an injected `<base>` element, this operation keeps
/// the document-loading contract inside WebKit. Relative resources resolve
/// against `base_uri`, while a null base defaults to `about:blank`. WebKit
/// copies both strings before returning. Returns `-1`/`-2` for invalid HTML or
/// base strings and `-3` for an invalid or torn-down view.
///
/// # Safety
///
/// `content` must point to readable NUL-terminated UTF-8. A non-null
/// `base_uri` must satisfy the same requirement. Neither pointer is retained.
pub unsafe extern "C" fn webview_flutter_linux_wpe_load_html(
    handle: u64,
    content: *const c_char,
    base_uri: *const c_char,
) -> i32 {
    let content = match required_c_string(content)
        .and_then(|value| std::ffi::CString::new(value).map_err(|_| -2))
    {
        Ok(content) => content,
        Err(status) => return status,
    };
    let base_uri = if base_uri.is_null() {
        None
    } else {
        match required_c_string(base_uri)
            .and_then(|value| std::ffi::CString::new(value).map_err(|_| -2))
        {
            Ok(base_uri) => Some(base_uri),
            Err(status) => return status,
        }
    };
    let Some(native_view) = native_view(handle) else {
        return -3;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -3;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    unsafe {
        webkit_web_view_load_html(
            webview,
            content.as_ptr(),
            base_uri
                .as_ref()
                .map_or(std::ptr::null(), |value| value.as_ptr()),
        )
    };
    0
}

/// Builds the WebKit session-history item used to start a native POST load.
///
/// WPE's public `WebKitURIRequest` API intentionally has no method or body
/// setter. Its equally public session-state format does preserve a history
/// item's form body, and WebKit turns that body back into a POST request inside
/// the web process. Constructing the documented version-2 GVariant keeps this
/// bridge on public ABI while retaining WebKit networking, cookies, redirects,
/// cache behavior, origin handling, and native history.
pub(super) fn post_history_item_variant(
    url: &str,
    body: &[u8],
    content_type: &str,
) -> glib::Variant {
    let empty_i64 = glib::Variant::from_none(
        glib::VariantTy::new("x").expect("the static int64 GVariant type is valid"),
    );
    let empty_f64 = glib::Variant::from_none(
        glib::VariantTy::new("d").expect("the static double GVariant type is valid"),
    );
    let body_element = glib::Variant::tuple_from_iter([
        0_u32.to_variant(),
        body.to_vec().to_variant(),
        String::new().to_variant(),
        0_i64.to_variant(),
        empty_i64,
        empty_f64,
        String::new().to_variant(),
    ]);
    let body_element_type = glib::VariantTy::new("(uaysxmxmds)")
        .expect("the static HTTP-body element GVariant type is valid");
    let body_elements = glib::Variant::array_from_iter_with_type(body_element_type, [body_element]);
    let http_body =
        glib::Variant::tuple_from_iter([content_type.to_string().to_variant(), body_elements]);
    let optional_http_body = glib::Variant::from_some(&http_body);
    let no_state_object = glib::Variant::from_none(
        glib::VariantTy::new("ay").expect("the static byte-array GVariant type is valid"),
    );
    let no_children = glib::Variant::array_from_iter_with_type(
        glib::VariantTy::VARIANT,
        std::iter::empty::<glib::Variant>(),
    );
    let frame_state = glib::Variant::tuple_from_iter([
        url.to_string().to_variant(),
        url.to_string().to_variant(),
        String::new().to_variant(),
        String::new().to_variant(),
        Vec::<String>::new().to_variant(),
        no_state_object,
        0_i64.to_variant(),
        0_i64.to_variant(),
        (0_i32, 0_i32).to_variant(),
        1_f64.to_variant(),
        optional_http_body,
        no_children,
    ]);

    glib::Variant::tuple_from_iter([String::new().to_variant(), frame_state, 2_u32.to_variant()])
}

/// Appends a POST item after the current native history entry.
///
/// Forward entries are discarded just as they are for an ordinary new
/// navigation. Existing back entries are copied verbatim from WebKit's own
/// serialized state, so request bodies and engine-only history metadata are
/// not reconstructed by Dart.
fn session_state_with_post(
    webview: *mut WebKitWebView,
    url: &str,
    body: &[u8],
    content_type: &str,
) -> Result<glib::Variant, i32> {
    let session_type = glib::VariantTy::new(SESSION_STATE_TYPE_V2).map_err(|_| -8)?;
    let item_type = glib::VariantTy::new(BACK_FORWARD_LIST_ITEM_TYPE_V2).map_err(|_| -8)?;
    let current_state = unsafe { webkit_web_view_get_session_state(webview) };
    if current_state.is_null() {
        return Err(-9);
    }
    let serialized = unsafe { webkit_web_view_session_state_serialize(current_state) };
    unsafe { webkit_web_view_session_state_unref(current_state) };
    if serialized.is_null() {
        return Err(-10);
    }
    let serialized: glib::Bytes = unsafe { from_glib_full(serialized) };
    let current = glib::Variant::from_bytes_with_type(&serialized, session_type);
    if !current.is_normal_form() || current.type_() != session_type {
        return Err(-11);
    }
    if current.try_child_get::<u16>(0).ok().flatten() != Some(2) {
        return Err(-12);
    }
    let current_items = current.try_child_value(1).ok_or(-11)?;
    let current_index = current
        .try_child_get::<Option<u32>>(2)
        .map_err(|_| -11)?
        .flatten();
    let retained_count = current_index
        .map(|index| (index as usize + 1).min(current_items.n_children()))
        .unwrap_or(0);
    let mut items = Vec::with_capacity(retained_count + 1);
    for index in 0..retained_count {
        let item = current_items.child_value(index);
        if item.type_() != item_type {
            return Err(-11);
        }
        items.push(item);
    }
    items.push(post_history_item_variant(url, body, content_type));
    let current_index = u32::try_from(items.len() - 1).map_err(|_| -13)?;
    let items = glib::Variant::array_from_iter_with_type(item_type, items);

    Ok(glib::Variant::tuple_from_iter([
        2_u16.to_variant(),
        items,
        glib::Variant::from_some(&current_index.to_variant()),
    ]))
}

#[unsafe(no_mangle)]
/// Starts a GET navigation with application-supplied HTTP headers.
///
/// WebKit owns the HTTP method for a newly constructed URI request and exposes
/// only read access to it, so this entry point intentionally represents GET.
/// Header arrays are parallel and borrowed only for this call. Returns `-1` or
/// `-2` for invalid UTF-8/string pointers, `-3` for an invalid view, `-4` for
/// an excessive header count, `-5` for an empty name, `-6` when WebKit cannot
/// create a request, and `-7` when its HTTP header collection is unavailable.
///
/// # Safety
///
/// `url` and every element in `header_names` and `header_values` must point to
/// readable NUL-terminated UTF-8. When `header_count` is non-zero, both arrays
/// must be readable for that many pointer elements.
pub unsafe extern "C" fn webview_flutter_linux_wpe_navigate_with_headers(
    handle: u64,
    url: *const c_char,
    header_names: *const *const c_char,
    header_values: *const *const c_char,
    header_count: usize,
) -> i32 {
    if header_count > 1024 {
        return -4;
    }
    if header_count > 0 && (header_names.is_null() || header_values.is_null()) {
        return -1;
    }
    if required_c_string(url).is_err() {
        return -2;
    }
    for index in 0..header_count {
        let name = unsafe { header_names.add(index).read() };
        let value = unsafe { header_values.add(index).read() };
        let Ok(name_text) = required_c_string(name) else {
            return -2;
        };
        if name_text.is_empty() {
            return -5;
        }
        if required_c_string(value).is_err() {
            return -2;
        }
    }
    let Some(native_view) = native_view(handle) else {
        return -3;
    };
    let request = unsafe { webkit_uri_request_new(url) };
    if request.is_null() {
        return -6;
    }
    let headers = unsafe { webkit_uri_request_get_http_headers(request) };
    if headers.is_null() && header_count > 0 {
        unsafe { glib::gobject_ffi::g_object_unref(request.cast()) };
        return -7;
    }
    for index in 0..header_count {
        let name = unsafe { header_names.add(index).read() };
        let value = unsafe { header_values.add(index).read() };
        unsafe { soup_message_headers_replace(headers, name, value) };
    }
    {
        let mut count = native_view.approved_navigation_count.borrow_mut();
        *count = count.saturating_add(1);
    }
    let status = {
        let runtime = native_view.runtime.borrow();
        let Some(runtime) = runtime.as_ref() else {
            unsafe { glib::gobject_ffi::g_object_unref(request.cast()) };
            return -3;
        };
        let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
            as *mut WebKitWebView;
        unsafe { webkit_web_view_load_request(webview, request) };
        0
    };
    unsafe { glib::gobject_ffi::g_object_unref(request.cast()) };
    status
}

#[unsafe(no_mangle)]
/// Starts a native POST navigation with an arbitrary binary request body.
///
/// The request is represented as a WebKit session-history form submission,
/// then loaded through the public back/forward-list API. This deliberately
/// avoids JavaScript forms, a second HTTP client, and private WebCore symbols:
/// cookies, redirects, cache policy, security origin, response rendering, and
/// subsequent reload/back/forward behavior all remain owned by WebKit. The
/// UI process places a bounded, nonce-keyed header handoff beside the private
/// web-process extension. That extension applies the complete caller-supplied
/// header set at WebKit's supported `send-request` interception point.
///
/// Returns negative status codes for invalid strings/arrays (`-1` through
/// `-5`), invalid view/runtime state (`-3`, `-9`, `-10`), unsupported or
/// malformed session data (`-8`, `-11`, `-12`), history overflow (`-13`),
/// rejected serialized state (`-15`), a missing restored history item (`-16`),
/// an unavailable native library path (`-17`), extension-directory I/O
/// (`-18`), an unavailable WebKit context (`-19`), or an oversized header
/// handoff (`-20`).
///
/// # Safety
///
/// `url` and every header pointer must identify readable NUL-terminated UTF-8
/// for this call. When `body_length` is non-zero, `body` must identify that
/// many readable bytes. Header arrays must contain `header_count` pointers.
pub unsafe extern "C" fn webview_flutter_linux_wpe_navigate_post(
    handle: u64,
    url: *const c_char,
    header_names: *const *const c_char,
    header_values: *const *const c_char,
    header_count: usize,
    body: *const u8,
    body_length: usize,
) -> i32 {
    if header_count > 1024 {
        return -4;
    }
    if header_count > 0 && (header_names.is_null() || header_values.is_null()) {
        return -1;
    }
    if body_length > 0 && body.is_null() {
        return -1;
    }
    let url = match required_c_string(url) {
        Ok(url) => url,
        Err(status) => return status,
    };
    let mut content_type = String::new();
    let mut request_headers = Vec::with_capacity(header_count);
    for index in 0..header_count {
        let name = unsafe { header_names.add(index).read() };
        let value = unsafe { header_values.add(index).read() };
        let name = match required_c_string(name) {
            Ok(name) if !name.is_empty() => name,
            Ok(_) => return -5,
            Err(status) => return status,
        };
        let value = match required_c_string(value) {
            Ok(value) => value,
            Err(status) => return status,
        };
        if name.eq_ignore_ascii_case("content-type") {
            content_type.clone_from(&value);
        }
        request_headers.push((name, value));
    }
    let body = if body_length == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(body, body_length) }
    };
    let Some(native_view) = native_view(handle) else {
        return -3;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -3;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    discard_request_header_handoff(&native_view);
    let history_content_type = if request_headers.is_empty() {
        content_type
    } else {
        match prepare_request_header_handoff(&url, &request_headers) {
            Ok(handoff) => {
                *native_view.pending_request_header_handoff.borrow_mut() = Some(handoff.path);
                handoff.marker
            }
            Err(status) => return status,
        }
    };
    let session = match session_state_with_post(webview, &url, body, &history_content_type) {
        Ok(session) => session,
        Err(status) => return status,
    };
    let bytes = session.data_as_bytes();
    let state = unsafe {
        webkit_web_view_session_state_new(
            ToGlibPtr::<*mut glib::ffi::GBytes>::to_glib_none(&bytes).0,
        )
    };
    if state.is_null() {
        return -15;
    }
    unsafe { webkit_web_view_restore_session_state(webview, state) };
    unsafe { webkit_web_view_session_state_unref(state) };
    let list = unsafe { webkit_web_view_get_back_forward_list(webview) };
    let item = if list.is_null() {
        std::ptr::null_mut()
    } else {
        unsafe { webkit_back_forward_list_get_current_item(list) }
    };
    if item.is_null() {
        return -16;
    }
    {
        let mut count = native_view.approved_navigation_count.borrow_mut();
        *count = count.saturating_add(1);
    }
    unsafe { webkit_web_view_go_to_back_forward_list_item(webview, item) };
    0
}

/// Applies an operation to the oldest queued navigation event.
fn with_navigation_event<T: Copy>(
    handle: u64,
    fallback: T,
    operation: impl FnOnce(&NavigationEventSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    native_view
        .navigation_events
        .borrow()
        .front()
        .map_or(fallback, operation)
}

#[unsafe(no_mangle)]
/// Returns the number of lifecycle events waiting for Dart.
pub extern "C" fn webview_flutter_linux_wpe_navigation_event_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.navigation_events.borrow().len().min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Returns the kind identifier of the oldest queued lifecycle event.
pub extern "C" fn webview_flutter_linux_wpe_navigation_event_kind(handle: u64) -> u32 {
    with_navigation_event(handle, 0, |event| event.kind)
}

#[unsafe(no_mangle)]
/// Returns the progress percentage carried by the oldest queued event.
pub extern "C" fn webview_flutter_linux_wpe_navigation_event_progress(handle: u64) -> u32 {
    with_navigation_event(handle, 0, |event| event.progress)
}

#[unsafe(no_mangle)]
/// Returns the error or HTTP status code carried by the oldest event.
pub extern "C" fn webview_flutter_linux_wpe_navigation_event_code(handle: u64) -> i32 {
    with_navigation_event(handle, 0, |event| event.code)
}

#[unsafe(no_mangle)]
/// Returns one for main-frame events, zero for subresources, and `-1` unknown.
pub extern "C" fn webview_flutter_linux_wpe_navigation_event_is_main_frame(handle: u64) -> i32 {
    with_navigation_event(handle, -1, |event| event.is_main_frame)
}

#[unsafe(no_mangle)]
/// Returns the UTF-8 detail length of the oldest queued event.
pub extern "C" fn webview_flutter_linux_wpe_navigation_event_detail_length(handle: u64) -> usize {
    with_navigation_event(handle, 0, |event| event.detail.len())
}

#[unsafe(no_mangle)]
/// Copies the detail string carried by the oldest queued event.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes.
pub unsafe extern "C" fn webview_flutter_linux_wpe_navigation_event_copy_detail(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_navigation_event(handle, -2, |event| {
        if destination_length < event.detail.len() || event.detail.len() > i32::MAX as usize {
            return -3;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(event.detail.as_ptr(), destination, event.detail.len())
        };
        event.detail.len() as i32
    })
}

#[unsafe(no_mangle)]
/// Returns the UTF-8 URI length of the oldest queued lifecycle event.
pub extern "C" fn webview_flutter_linux_wpe_navigation_event_url_length(handle: u64) -> usize {
    with_navigation_event(handle, 0, |event| event.url.len())
}

#[unsafe(no_mangle)]
/// Copies the oldest queued lifecycle event URI into caller-owned storage.
///
/// Returns the byte count, `-1` for a null destination, `-2` when the queue is
/// empty or the handle is invalid, and `-3` for insufficient capacity.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes and remain
/// valid for this call. Rust never stores the pointer.
pub unsafe extern "C" fn webview_flutter_linux_wpe_navigation_event_copy_url(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_navigation_event(handle, -2, |event| {
        if destination_length < event.url.len() || event.url.len() > i32::MAX as usize {
            return -3;
        }
        unsafe { std::ptr::copy_nonoverlapping(event.url.as_ptr(), destination, event.url.len()) };
        event.url.len() as i32
    })
}

#[unsafe(no_mangle)]
/// Removes the oldest queued lifecycle event after Dart has copied it.
///
/// Returns zero when an event was removed, one for an empty queue, and `-1`
/// for an invalid handle.
pub extern "C" fn webview_flutter_linux_wpe_navigation_event_pop(handle: u64) -> i32 {
    native_view(handle).map_or(-1, |view| {
        i32::from(view.navigation_events.borrow_mut().pop_front().is_none())
    })
}

#[unsafe(no_mangle)]
/// Intentionally terminates this view's current WebKit web process.
///
/// This is a deterministic testing hook for exercising the same
/// `web-process-terminated` signal used for real crashes and memory-limit
/// exits. Production applications should never call it. The `WebKitWebView`
/// remains alive after the call, and a later navigation or reload asks WebKit
/// to launch a replacement content process. Returns `-1` when the handle or
/// runtime is unavailable.
pub extern "C" fn webview_flutter_linux_wpe_terminate_web_process_for_testing(handle: u64) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -1;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    // SAFETY: the pointer is borrowed from the runtime retained for this call.
    unsafe { webkit_web_view_terminate_web_process(webview) };
    0
}
