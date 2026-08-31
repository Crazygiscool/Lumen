// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! JavaScript evaluation, channels, user scripts, and presentation injection.
//!
//! Asynchronous results and page-originated messages are copied into per-view
//! queues before callback-scoped WebKit values expire. Installed channel and
//! stylesheet objects remain owned by the view's user-content manager.

use super::{navigation, prelude::*};

pub(super) const JAVASCRIPT_RESULT_SUCCESS: i32 = 0;
const JAVASCRIPT_RESULT_NULL: i32 = 1;
const JAVASCRIPT_RESULT_UNDEFINED: i32 = 2;
const JAVASCRIPT_RESULT_UNSUPPORTED: i32 = 3;
pub(super) const JAVASCRIPT_RESULT_ERROR: i32 = -1;
const JAVASCRIPT_RESULT_SERIALIZATION_ERROR: i32 = -2;

/// Native objects retained for one installed JavaScript channel.
///
/// The user-content manager owns a reference to `script` while it is
/// installed. The pointer is therefore valid until `remove_script` is called.
/// GLib owns the signal closure and releases it when the handler is
/// disconnected or the manager is destroyed.
pub(super) struct JavaScriptChannelRegistration {
    script: *mut WebKitUserScript,
    signal_handler_id: glib::SignalHandlerId,
}

/// Completed JavaScript request waiting for its Dart `Future` to be resolved.
///
/// Successful non-null values are encoded as UTF-8 JSON so the C ABI remains
/// independent of JavaScriptCore object layouts. Error payloads contain a
/// human-readable WebKit message. Results are never coalesced or dropped:
/// every accepted request ID must eventually resolve exactly one Dart future.
pub(super) struct JavaScriptResultSnapshot {
    pub(super) request_id: u64,
    pub(super) status: i32,
    pub(super) payload: Vec<u8>,
}

/// Browser-originated message waiting for the Dart channel callback.
///
/// Both fields are copied while WebKit's signal arguments are alive. Messages
/// are never coalesced or evicted because every `postMessage` call is an
/// application-visible event.
pub(super) struct JavaScriptMessageSnapshot {
    pub(super) channel: Vec<u8>,
    pub(super) message: Vec<u8>,
}

/// Callback ownership passed through WebKit's asynchronous C API.
///
/// The callback reconstructs this box exactly once. Its weak view reference
/// prevents an outstanding JavaScript request from extending browser lifetime.
struct JavaScriptRequestContext {
    native_view: Weak<NativeView>,
    request_id: u64,
}

/// Appends a completed JavaScript result without coalescing or eviction.
pub(super) fn enqueue_javascript_result(
    results: &mut VecDeque<JavaScriptResultSnapshot>,
    result: JavaScriptResultSnapshot,
) {
    results.push_back(result);
}

/// Converts an arbitrary channel name into a JavaScript string literal.
///
/// Channel wrappers use bracket notation rather than interpolating names as
/// identifiers. This accepts every non-empty UTF-8 name supported by WebKit,
/// including punctuation, without permitting source injection.
pub(super) fn javascript_string_literal(value: &str) -> String {
    let mut literal = String::with_capacity(value.len() + 2);
    literal.push('"');
    for character in value.chars() {
        match character {
            '"' => literal.push_str("\\\""),
            '\\' => literal.push_str("\\\\"),
            '\u{08}' => literal.push_str("\\b"),
            '\u{0c}' => literal.push_str("\\f"),
            '\n' => literal.push_str("\\n"),
            '\r' => literal.push_str("\\r"),
            '\t' => literal.push_str("\\t"),
            '\u{2028}' => literal.push_str("\\u2028"),
            '\u{2029}' => literal.push_str("\\u2029"),
            character if character <= '\u{1f}' => {
                use std::fmt::Write;
                write!(literal, "\\u{:04x}", character as u32)
                    .expect("writing to a String cannot fail");
            }
            character => literal.push(character),
        }
    }
    literal.push('"');
    literal
}

/// Builds the document-start wrapper used by the federated WebView API.
pub(super) fn javascript_channel_wrapper(channel: &str) -> String {
    let name = javascript_string_literal(channel);
    format!(
        "Object.defineProperty(window,{name},{{configurable:true,value:window.webkit.messageHandlers[{name}]}});"
    )
}

/// Builds the best-effort cleanup script for the currently loaded document.
fn javascript_channel_cleanup(channel: &str) -> String {
    let name = javascript_string_literal(channel);
    format!("delete window[{name}];")
}

/// Copies one `postMessage` value using the cross-platform channel contract.
///
/// WebKit's Apple implementation historically reports both JavaScript `null`
/// and `undefined` as `(null)`. Other values use JavaScript's string
/// conversion, so string messages arrive without JSON quotes.
pub(super) fn javascript_channel_message(value: *mut JSCValue) -> Vec<u8> {
    if value.is_null()
        || unsafe { jsc_value_is_null(value) != 0 }
        || unsafe { jsc_value_is_undefined(value) != 0 }
    {
        return b"(null)".to_vec();
    }
    // SAFETY: the signal owns `value` for this callback. JavaScriptCore
    // returns a newly allocated UTF-8 string released with g_free.
    let message = unsafe { jsc_value_to_string(value) };
    if message.is_null() {
        return Vec::new();
    }
    let bytes = unsafe { CStr::from_ptr(message) }.to_bytes().to_vec();
    unsafe { glib::ffi::g_free(message.cast()) };
    bytes
}

/// Installs the internal frame-classification bridge on every document.
///
/// WPE's public `WebKitNavigationAction` exposes the destination request but
/// not its source or target `FrameInfo`. WebKit's standards-based Navigation
/// API does expose the destination before policy evaluation and runs in the
/// initiating frame. This private handler records `window === window.top`
/// without exposing a page-visible Flutter channel or changing the URL.
///
/// The bridge runs in a private content world so page code cannot replace its
/// handler or marker. WPE suppresses document-start user scripts when content
/// JavaScript markup is disabled. In that mode the web-process request gate,
/// response-policy gate, and extension-owned isolated world provide the same
/// authoritative frame evidence without depending on page script execution.
///
/// The message handler and user script are owned by `manager`. The signal
/// closure retains only a weak view, so manager or controller disposal cannot
/// keep native browser state alive. Returns a negative construction status if
/// WebKit cannot register either half of the bridge.
pub(super) fn install_navigation_frame_bridge(
    manager: *mut WebKitUserContentManager,
    native_view: Weak<NativeView>,
) -> i32 {
    const CHANNEL: &CStr = c"__webviewFlutterLinuxNavigationFrame_0_1";
    const WORLD: &CStr = c"webview-flutter-linux-navigation-frame-0-1";
    const SOURCE: &str = r#"
(() => {
  const marker = '__webviewFlutterLinuxNavigationFrameInstalled_0_1';
  if (window[marker]) return;
  const handler =
    window.webkit?.messageHandlers?.__webviewFlutterLinuxNavigationFrame_0_1;
  if (!handler) return;
  Object.defineProperty(window, marker, {value: true});

  const announce = (main, url) => {
    if (typeof url === 'string' && url.length !== 0) {
      handler.postMessage((main ? 'M\n' : 'S\n') + url);
    }
  };
  window.navigation?.addEventListener('navigate', event => {
    announce(window === window.top, event.destination?.url);
  });

  const announceFrame = frame => {
    if (frame?.matches?.('iframe,frame')) announce(false, frame.src);
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

    if manager.is_null() {
        return -1;
    }
    let manager_object: glib::Object = unsafe { from_glib_none(manager.cast()) };
    let callback_view = native_view;
    let signal_handler_id = manager_object.connect_local(
        "script-message-received::__webviewFlutterLinuxNavigationFrame_0_1",
        false,
        move |values| {
            let value = values.get(1)?;
            let value = unsafe {
                glib::gobject_ffi::g_value_get_object(
                    ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(value).0,
                )
            }
            .cast::<JSCValue>();
            let native_view = callback_view.upgrade()?;
            let message = javascript_channel_message(value);
            let hint = navigation::navigation_frame_hint(&message)?;
            navigation::enqueue_navigation_frame_hint(
                &mut native_view.navigation_frame_hints.borrow_mut(),
                hint,
            );
            None
        },
    );

    let registered = unsafe {
        webkit_user_content_manager_register_script_message_handler(
            manager,
            CHANNEL.as_ptr(),
            WORLD.as_ptr(),
        )
    };
    if registered == 0 {
        manager_object.disconnect(signal_handler_id);
        return -2;
    }
    let source = std::ffi::CString::new(SOURCE).expect("navigation bridge cannot contain NUL");
    let script = unsafe {
        webkit_user_script_new_for_world(
            source.as_ptr(),
            0,
            0,
            WORLD.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
        )
    };
    if script.is_null() {
        unsafe {
            webkit_user_content_manager_unregister_script_message_handler(
                manager,
                CHANNEL.as_ptr(),
                WORLD.as_ptr(),
            )
        };
        manager_object.disconnect(signal_handler_id);
        return -3;
    }
    unsafe {
        webkit_user_content_manager_add_script(manager, script);
        webkit_user_script_unref(script);
    }
    0
}

/// Injects a script into the current main world without awaiting a result.
fn evaluate_javascript_without_result(webview: *mut WebKitWebView, source: &CStr) {
    // SAFETY: WebKit copies the source during submission. A null callback is
    // explicitly supported when the caller does not need the result.
    unsafe {
        webkit_web_view_evaluate_javascript(
            webview,
            source.as_ptr(),
            -1,
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null_mut(),
            None,
            std::ptr::null_mut(),
        )
    };
}

/// Completes one asynchronous JavaScript evaluation and queues an owned result.
///
/// WebKit owns `source_object` and `result` for the duration of this callback.
/// `user_data` is the unique box allocated when the request was submitted. The
/// returned JavaScriptCore value and any `GError` are transfer-full and are
/// released after their contents have been copied into Rust storage.
unsafe extern "C" fn javascript_evaluation_finished(
    source_object: *mut glib::gobject_ffi::GObject,
    result: *mut GAsyncResult,
    user_data: *mut c_void,
) {
    if user_data.is_null() {
        return;
    }
    // SAFETY: evaluate_javascript received this pointer from Box::into_raw and
    // WebKit invokes its completion callback at most once.
    let request = unsafe { Box::from_raw(user_data.cast::<JavaScriptRequestContext>()) };
    let mut error = std::ptr::null_mut::<glib::ffi::GError>();
    // SAFETY: WebKit supplies its originating WebView and GAsyncResult.
    let value = unsafe {
        webkit_web_view_evaluate_javascript_finish(
            source_object.cast::<WebKitWebView>(),
            result,
            &mut error,
        )
    };

    let snapshot = if !error.is_null() {
        let status = if unsafe {
            (*error).domain == webkit_javascript_error_quark() && (*error).code == 601
        } {
            JAVASCRIPT_RESULT_UNSUPPORTED
        } else {
            JAVASCRIPT_RESULT_ERROR
        };
        let message = unsafe {
            if (*error).message.is_null() {
                b"JavaScript evaluation failed".to_vec()
            } else {
                CStr::from_ptr((*error).message).to_bytes().to_vec()
            }
        };
        // SAFETY: evaluate_javascript_finish returned this transfer-full error.
        unsafe { glib::ffi::g_error_free(error) };
        JavaScriptResultSnapshot {
            request_id: request.request_id,
            status,
            payload: message,
        }
    } else if value.is_null() {
        JavaScriptResultSnapshot {
            request_id: request.request_id,
            status: JAVASCRIPT_RESULT_ERROR,
            payload: b"JavaScript evaluation returned no result".to_vec(),
        }
    } else if unsafe { jsc_value_is_null(value) != 0 } {
        JavaScriptResultSnapshot {
            request_id: request.request_id,
            status: JAVASCRIPT_RESULT_NULL,
            payload: Vec::new(),
        }
    } else if unsafe { jsc_value_is_undefined(value) != 0 } {
        JavaScriptResultSnapshot {
            request_id: request.request_id,
            status: JAVASCRIPT_RESULT_UNDEFINED,
            payload: Vec::new(),
        }
    } else {
        // SAFETY: value is a live JSCValue and the returned UTF-8 allocation is
        // owned by the caller and must be released with g_free.
        let json = unsafe { jsc_value_to_json(value, 0) };
        if json.is_null() {
            JavaScriptResultSnapshot {
                request_id: request.request_id,
                status: JAVASCRIPT_RESULT_SERIALIZATION_ERROR,
                payload: b"JavaScript result cannot be represented as JSON".to_vec(),
            }
        } else {
            let payload = unsafe { CStr::from_ptr(json).to_bytes().to_vec() };
            unsafe { glib::ffi::g_free(json.cast()) };
            JavaScriptResultSnapshot {
                request_id: request.request_id,
                status: JAVASCRIPT_RESULT_SUCCESS,
                payload,
            }
        }
    };

    if !value.is_null() {
        // SAFETY: evaluate_javascript_finish returns a transfer-full JSCValue.
        unsafe { glib::gobject_ffi::g_object_unref(value.cast()) };
    }
    if let Some(native_view) = request.native_view.upgrade() {
        enqueue_javascript_result(&mut native_view.javascript_results.borrow_mut(), snapshot);
    }
}

#[unsafe(no_mangle)]
/// Starts an asynchronous JavaScript evaluation in the current page.
///
/// Completion is appended to the view's result queue and retrieved through the
/// `javascript_result_*` accessors. `request_id` must be non-zero and unique
/// among Dart's outstanding requests. Returns `-1`/`-2` for an invalid script,
/// `-3` for an invalid view, and `-4` for a zero request ID.
pub extern "C" fn webview_flutter_linux_wpe_evaluate_javascript(
    handle: u64,
    request_id: u64,
    script: *const c_char,
) -> i32 {
    if request_id == 0 {
        return -4;
    }
    let script = match required_c_string(script)
        .and_then(|script| std::ffi::CString::new(script).map_err(|_| -2))
    {
        Ok(script) => script,
        Err(status) => return status,
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
    let context = Box::new(JavaScriptRequestContext {
        native_view: Rc::downgrade(&native_view),
        request_id,
    });
    // SAFETY: WebKit copies the script during submission and consumes the
    // callback context exactly once when the asynchronous result is ready.
    unsafe {
        webkit_web_view_evaluate_javascript(
            webview,
            script.as_ptr(),
            -1,
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null_mut(),
            Some(javascript_evaluation_finished),
            Box::into_raw(context).cast(),
        )
    };
    0
}

/// Applies an operation to the oldest queued JavaScript result.
fn with_javascript_result<T: Copy>(
    handle: u64,
    fallback: T,
    operation: impl FnOnce(&JavaScriptResultSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    native_view
        .javascript_results
        .borrow()
        .front()
        .map_or(fallback, operation)
}

#[unsafe(no_mangle)]
/// Returns the number of completed JavaScript requests waiting for Dart.
pub extern "C" fn webview_flutter_linux_wpe_javascript_result_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.javascript_results
            .borrow()
            .len()
            .min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Returns the request ID of the oldest completed JavaScript request.
pub extern "C" fn webview_flutter_linux_wpe_javascript_result_request_id(handle: u64) -> u64 {
    with_javascript_result(handle, 0, |result| result.request_id)
}

#[unsafe(no_mangle)]
/// Returns the status of the oldest completed JavaScript request.
pub extern "C" fn webview_flutter_linux_wpe_javascript_result_status(handle: u64) -> i32 {
    with_javascript_result(handle, JAVASCRIPT_RESULT_ERROR, |result| result.status)
}

#[unsafe(no_mangle)]
/// Returns the UTF-8 payload length of the oldest JavaScript result.
pub extern "C" fn webview_flutter_linux_wpe_javascript_result_payload_length(handle: u64) -> usize {
    with_javascript_result(handle, 0, |result| result.payload.len())
}

#[unsafe(no_mangle)]
/// Copies the oldest JavaScript result payload into caller-owned storage.
///
/// Returns the byte count, `-1` for a null destination, `-2` when no result is
/// available, and `-3` for insufficient capacity.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes and remain
/// valid for this call. Rust never stores the pointer.
pub unsafe extern "C" fn webview_flutter_linux_wpe_javascript_result_copy_payload(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_javascript_result(handle, -2, |result| {
        if destination_length < result.payload.len() || result.payload.len() > i32::MAX as usize {
            return -3;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(
                result.payload.as_ptr(),
                destination,
                result.payload.len(),
            )
        };
        result.payload.len() as i32
    })
}

#[unsafe(no_mangle)]
/// Removes the oldest JavaScript result after Dart has copied it.
pub extern "C" fn webview_flutter_linux_wpe_javascript_result_pop(handle: u64) -> i32 {
    native_view(handle).map_or(-1, |view| {
        i32::from(view.javascript_results.borrow_mut().pop_front().is_none())
    })
}

#[unsafe(no_mangle)]
/// Installs one document-start JavaScript channel and current-page wrapper.
///
/// The wrapper exposes `window[name].postMessage(value)`, matching the public
/// federated WebView contract. Returns `-1`/`-2` for an invalid name, `-3` for
/// an unavailable view, `-4` when WebKit cannot create the user script, `-5`
/// when WebKit rejects the message handler, and `-6` for a duplicate name.
pub extern "C" fn webview_flutter_linux_wpe_add_javascript_channel(
    handle: u64,
    channel: *const c_char,
) -> i32 {
    let channel = match required_c_string(channel) {
        Ok(channel) if !channel.is_empty() => channel,
        Ok(_) => return -2,
        Err(status) => return status,
    };
    let native_channel = match std::ffi::CString::new(channel.as_str()) {
        Ok(channel) => channel,
        Err(_) => return -2,
    };
    let wrapper = std::ffi::CString::new(javascript_channel_wrapper(&channel))
        .expect("escaped JavaScript wrapper cannot contain NUL");
    let Some(native_view) = native_view(handle) else {
        return -3;
    };
    let mut runtime = native_view.runtime.borrow_mut();
    let Some(runtime) = runtime.as_mut() else {
        return -3;
    };
    if runtime.javascript_channels.contains_key(&channel) {
        return -6;
    }
    let manager =
        ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.user_content_manager).0
            as *mut WebKitUserContentManager;
    // Inject into all frames at document start, which matches the Apple
    // implementation and makes a channel available to early page scripts.
    let script = unsafe {
        webkit_user_script_new(wrapper.as_ptr(), 0, 0, std::ptr::null(), std::ptr::null())
    };
    if script.is_null() {
        return -4;
    }

    let callback_view = Rc::downgrade(&native_view);
    let callback_channel = channel.as_bytes().to_vec();
    let detailed_signal = format!("script-message-received::{channel}");
    let signal_handler_id =
        runtime
            .user_content_manager
            .connect_local(&detailed_signal, false, move |values| {
                let value = values.get(1)?;
                let value = unsafe {
                    glib::gobject_ffi::g_value_get_object(
                        ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(value).0,
                    )
                }
                .cast::<JSCValue>();
                let native_view = callback_view.upgrade()?;
                native_view
                    .javascript_messages
                    .borrow_mut()
                    .push_back(JavaScriptMessageSnapshot {
                        channel: callback_channel.clone(),
                        message: javascript_channel_message(value),
                    });
                None
            });

    // Connect first to avoid the registration race documented by WebKit.
    let registered = unsafe {
        webkit_user_content_manager_register_script_message_handler(
            manager,
            native_channel.as_ptr(),
            std::ptr::null(),
        )
    };
    if registered == 0 {
        runtime.user_content_manager.disconnect(signal_handler_id);
        unsafe { webkit_user_script_unref(script) };
        return -5;
    }
    unsafe {
        webkit_user_content_manager_add_script(manager, script);
        // The manager retained the script. The registration stores a borrowed
        // pointer used only while that manager reference remains installed.
        webkit_user_script_unref(script);
    }
    runtime.javascript_channels.insert(
        channel,
        JavaScriptChannelRegistration {
            script,
            signal_handler_id,
        },
    );
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    evaluate_javascript_without_result(webview, &wrapper);
    0
}

#[unsafe(no_mangle)]
/// Removes a JavaScript channel from future and current documents.
///
/// Removing a name that is not installed is idempotent. Returns `-1`/`-2` for
/// an invalid name and `-3` for an unavailable view.
pub extern "C" fn webview_flutter_linux_wpe_remove_javascript_channel(
    handle: u64,
    channel: *const c_char,
) -> i32 {
    let channel = match required_c_string(channel) {
        Ok(channel) if !channel.is_empty() => channel,
        Ok(_) => return -2,
        Err(status) => return status,
    };
    let native_channel = match std::ffi::CString::new(channel.as_str()) {
        Ok(channel) => channel,
        Err(_) => return -2,
    };
    let Some(native_view) = native_view(handle) else {
        return -3;
    };
    let mut runtime = native_view.runtime.borrow_mut();
    let Some(runtime) = runtime.as_mut() else {
        return -3;
    };
    let Some(registration) = runtime.javascript_channels.remove(&channel) else {
        return 0;
    };
    let manager =
        ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.user_content_manager).0
            as *mut WebKitUserContentManager;
    runtime
        .user_content_manager
        .disconnect(registration.signal_handler_id);
    unsafe {
        webkit_user_content_manager_unregister_script_message_handler(
            manager,
            native_channel.as_ptr(),
            std::ptr::null(),
        );
        webkit_user_content_manager_remove_script(manager, registration.script);
    }
    let cleanup = std::ffi::CString::new(javascript_channel_cleanup(&channel))
        .expect("escaped JavaScript cleanup cannot contain NUL");
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    evaluate_javascript_without_result(webview, &cleanup);
    0
}

#[unsafe(no_mangle)]
/// Installs an application-owned script at document start and in the current page.
///
/// The user-content manager retains the script for future documents. The
/// source must be non-empty NUL-terminated UTF-8. Returns `-1`/`-2` for an
/// invalid source, `-3` for an unavailable view, and `-4` on allocation
/// failure.
pub extern "C" fn webview_flutter_linux_wpe_add_user_script(
    handle: u64,
    source: *const c_char,
) -> i32 {
    let source = match required_c_string(source) {
        Ok(source) if !source.is_empty() => source,
        Ok(_) => return -2,
        Err(status) => return status,
    };
    let source = match std::ffi::CString::new(source) {
        Ok(source) => source,
        Err(_) => return -2,
    };
    let Some(native_view) = native_view(handle) else {
        return -3;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -3;
    };
    let manager =
        ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.user_content_manager).0
            as *mut WebKitUserContentManager;
    let script = unsafe {
        webkit_user_script_new(source.as_ptr(), 0, 0, std::ptr::null(), std::ptr::null())
    };
    if script.is_null() {
        return -4;
    }
    unsafe {
        webkit_user_content_manager_add_script(manager, script);
        webkit_user_script_unref(script);
    }
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    evaluate_javascript_without_result(webview, &source);
    0
}

/// Builds the user-level CSS used for platform presentation controls.
pub(super) fn page_presentation_style(
    vertical_scrollbar_enabled: bool,
    horizontal_scrollbar_enabled: bool,
    overscroll_mode: i32,
) -> String {
    let mut style = String::new();
    if !vertical_scrollbar_enabled {
        style.push_str("::-webkit-scrollbar:vertical{width:0!important;}");
    }
    if !horizontal_scrollbar_enabled {
        style.push_str("::-webkit-scrollbar:horizontal{height:0!important;}");
    }
    if overscroll_mode == 2 {
        style.push_str("html,body{overscroll-behavior:none!important;}");
    }
    style
}

#[unsafe(no_mangle)]
/// Updates scrollbar visibility and overscroll behavior for all page frames.
///
/// The stylesheet is installed at WebKit's user level, so page-authored CSS
/// cannot override an application decision. Modes zero and one restore WPE's
/// native overscroll behavior; mode two disables overscroll through CSS.
pub extern "C" fn webview_flutter_linux_wpe_set_page_presentation(
    handle: u64,
    vertical_scrollbar_enabled: i32,
    horizontal_scrollbar_enabled: i32,
    overscroll_mode: i32,
) -> i32 {
    if !(0..=2).contains(&overscroll_mode) {
        return -1;
    }
    let source = page_presentation_style(
        vertical_scrollbar_enabled != 0,
        horizontal_scrollbar_enabled != 0,
        overscroll_mode,
    );
    let source =
        std::ffi::CString::new(source).expect("generated presentation CSS cannot contain NUL");
    let style_sheet = if source.as_bytes().is_empty() {
        std::ptr::null_mut()
    } else {
        let style_sheet = unsafe {
            webkit_user_style_sheet_new(source.as_ptr(), 0, 0, std::ptr::null(), std::ptr::null())
        };
        if style_sheet.is_null() {
            return -2;
        }
        style_sheet
    };
    let Some(native_view) = native_view(handle) else {
        if !style_sheet.is_null() {
            unsafe { webkit_user_style_sheet_unref(style_sheet) };
        }
        return -3;
    };
    let mut runtime = native_view.runtime.borrow_mut();
    let Some(runtime) = runtime.as_mut() else {
        if !style_sheet.is_null() {
            unsafe { webkit_user_style_sheet_unref(style_sheet) };
        }
        return -3;
    };
    let manager =
        ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.user_content_manager).0
            as *mut WebKitUserContentManager;
    unsafe {
        if !style_sheet.is_null() {
            webkit_user_content_manager_add_style_sheet(manager, style_sheet);
            // The manager retains the installed sheet. Keep only its borrowed
            // pointer so it can be removed during the next update.
            webkit_user_style_sheet_unref(style_sheet);
        }
        if !runtime.presentation_style_sheet.is_null() {
            webkit_user_content_manager_remove_style_sheet(
                manager,
                runtime.presentation_style_sheet,
            );
        }
    }
    runtime.presentation_style_sheet = style_sheet;
    0
}

/// Applies an operation to the oldest browser-originated channel message.
fn with_javascript_message<T: Copy>(
    handle: u64,
    fallback: T,
    operation: impl FnOnce(&JavaScriptMessageSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    native_view
        .javascript_messages
        .borrow()
        .front()
        .map_or(fallback, operation)
}

#[unsafe(no_mangle)]
/// Returns the number of browser-originated JavaScript messages waiting.
pub extern "C" fn webview_flutter_linux_wpe_javascript_message_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.javascript_messages
            .borrow()
            .len()
            .min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Returns the channel-name byte length of the oldest queued message.
pub extern "C" fn webview_flutter_linux_wpe_javascript_message_channel_length(
    handle: u64,
) -> usize {
    with_javascript_message(handle, 0, |message| message.channel.len())
}

#[unsafe(no_mangle)]
/// Returns the payload byte length of the oldest queued message.
pub extern "C" fn webview_flutter_linux_wpe_javascript_message_payload_length(
    handle: u64,
) -> usize {
    with_javascript_message(handle, 0, |message| message.message.len())
}

/// Copies one field from the oldest queued JavaScript message.
unsafe fn copy_javascript_message_field(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
    field: impl FnOnce(&JavaScriptMessageSnapshot) -> &[u8],
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_javascript_message(handle, -2, |message| {
        let bytes = field(message);
        if destination_length < bytes.len() || bytes.len() > i32::MAX as usize {
            return -3;
        }
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), destination, bytes.len()) };
        bytes.len() as i32
    })
}

#[unsafe(no_mangle)]
/// Copies the channel name of the oldest queued JavaScript message.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes.
pub unsafe extern "C" fn webview_flutter_linux_wpe_javascript_message_copy_channel(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    unsafe {
        copy_javascript_message_field(handle, destination, destination_length, |message| {
            &message.channel
        })
    }
}

#[unsafe(no_mangle)]
/// Copies the payload of the oldest queued JavaScript message.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes.
pub unsafe extern "C" fn webview_flutter_linux_wpe_javascript_message_copy_payload(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    unsafe {
        copy_javascript_message_field(handle, destination, destination_length, |message| {
            &message.message
        })
    }
}

#[unsafe(no_mangle)]
/// Removes the oldest JavaScript channel message after Dart copies it.
pub extern "C" fn webview_flutter_linux_wpe_javascript_message_pop(handle: u64) -> i32 {
    native_view(handle).map_or(-1, |view| {
        i32::from(view.javascript_messages.borrow_mut().pop_front().is_none())
    })
}
