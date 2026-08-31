// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Application-global cookies and website-data operations.
//!
//! WebKit owns these stores through the application-scoped shared network
//! session rather than an individual view. Their async completions therefore
//! use handle-free queues that remain valid before a texture exists and across
//! WebView disposal.

use super::prelude::*;

const COOKIE_POLICY_ACCEPT_ALWAYS: i32 = 0;
const COOKIE_POLICY_ACCEPT_NEVER: i32 = 1;
const COOKIE_POLICY_ACCEPT_NO_THIRD_PARTY: i32 = 2;

/// Callback ownership for an asynchronous website-data clear request.
struct WebsiteDataClearContext {
    request_id: u64,
}

/// Completed application-wide website-data operation waiting for Dart.
///
/// Cache and storage belong to WebKit's shared network session rather than a
/// rendered view. Keeping these results outside [`NativeView`] lets the
/// federated controller clear data before its widget creates a texture.
pub(super) struct WebsiteDataResultSnapshot {
    pub(super) request_id: u64,
    pub(super) status: i32,
    pub(super) error: Vec<u8>,
}

/// One cookie copied out of libsoup-owned storage for Dart.
///
/// The WebKit callback frees the source `SoupCookie` immediately after copying
/// these UTF-8 bytes. No cookie pointer crosses the callback or FFI boundary.
pub(super) struct CookieSnapshot {
    pub(super) name: Vec<u8>,
    pub(super) value: Vec<u8>,
    pub(super) domain: Vec<u8>,
    pub(super) path: Vec<u8>,
}

/// Completed global cookie operation waiting for its Dart `Future`.
///
/// Cookie-manager instances are application-global in `webview_flutter`, so
/// these results deliberately live outside any individual [`NativeView`]. A
/// request ID still makes concurrent operations lossless and order-independent.
pub(super) struct CookieResultSnapshot {
    pub(super) request_id: u64,
    pub(super) status: i32,
    pub(super) had_cookies: i32,
    pub(super) accept_policy: i32,
    pub(super) error: Vec<u8>,
    pub(super) cookies: Vec<CookieSnapshot>,
}

/// Ownership token passed through one asynchronous cookie operation.
struct CookieRequestContext {
    request_id: u64,
}

/// Shared state for the per-cookie deletions that implement `clearCookies`.
struct CookieClearBatch {
    request_id: u64,
    remaining: Cell<usize>,
    error: RefCell<Option<Vec<u8>>>,
}

/// Returns WPE's application-scoped cookie manager.
///
/// Both getters are transfer-none. [`shared_network_session`] retains the
/// session and configures its persistent cookie store before returning it.
/// Every independent WebView uses that same session as a construct property,
/// matching `webview_flutter`'s app-wide cookie model without sharing state
/// between unrelated executables.
fn default_cookie_manager() -> Option<*mut WebKitCookieManager> {
    let session = shared_network_session().ok()?;
    let manager = unsafe { webkit_network_session_get_cookie_manager(session) };
    (!manager.is_null()).then_some(manager)
}

/// Returns WPE's application-scoped website-data manager.
///
/// The returned pointer is transfer-none and remains owned by the shared
/// persistent network session.
fn default_website_data_manager() -> Option<*mut WebKitWebsiteDataManager> {
    let session = shared_network_session().ok()?;
    let manager = unsafe { webkit_network_session_get_website_data_manager(session) };
    (!manager.is_null()).then_some(manager)
}

/// Copies and releases a transfer-full `GList<SoupCookie*>`.
fn take_cookie_list(mut list: *mut glib::ffi::GList) -> Vec<CookieSnapshot> {
    let head = list;
    let mut cookies = Vec::new();
    while !list.is_null() {
        let cookie = unsafe { (*list).data.cast::<SoupCookie>() };
        if !cookie.is_null() {
            cookies.push(CookieSnapshot {
                name: foreign_bytes(unsafe { soup_cookie_get_name(cookie) }),
                value: foreign_bytes(unsafe { soup_cookie_get_value(cookie) }),
                domain: foreign_bytes(unsafe { soup_cookie_get_domain(cookie) }),
                path: foreign_bytes(unsafe { soup_cookie_get_path(cookie) }),
            });
            unsafe { soup_cookie_free(cookie) };
        }
        list = unsafe { (*list).next };
    }
    if !head.is_null() {
        unsafe { glib::ffi::g_list_free(head) };
    }
    cookies
}

/// Converts a transfer-full `GError` into owned bytes and releases it.
fn take_error(error: *mut glib::ffi::GError, fallback: &[u8]) -> Vec<u8> {
    if error.is_null() {
        return fallback.to_vec();
    }
    let bytes = if unsafe { (*error).message.is_null() } {
        fallback.to_vec()
    } else {
        foreign_bytes(unsafe { (*error).message })
    };
    unsafe { glib::ffi::g_error_free(error) };
    bytes
}

/// Enqueues exactly one completion for a cookie request.
fn enqueue_cookie_result(result: CookieResultSnapshot) {
    COOKIE_RESULTS.with_borrow_mut(|results| results.push_back(result));
}

/// Returns whether `policy` is one of WPE's public cookie-policy values.
pub(super) const fn cookie_accept_policy_is_valid(policy: i32) -> bool {
    matches!(
        policy,
        COOKIE_POLICY_ACCEPT_ALWAYS
            | COOKIE_POLICY_ACCEPT_NEVER
            | COOKIE_POLICY_ACCEPT_NO_THIRD_PARTY
    )
}

/// Completes an asynchronous WebKit website-data clear request.
unsafe extern "C" fn website_data_clear_finished(
    source_object: *mut glib::gobject_ffi::GObject,
    result: *mut GAsyncResult,
    user_data: *mut c_void,
) {
    if user_data.is_null() {
        return;
    }
    let request = unsafe { Box::from_raw(user_data.cast::<WebsiteDataClearContext>()) };
    let mut error = std::ptr::null_mut::<glib::ffi::GError>();
    let succeeded = unsafe {
        webkit_website_data_manager_clear_finish(
            source_object.cast::<WebKitWebsiteDataManager>(),
            result,
            &mut error,
        ) != 0
    };
    let snapshot = if succeeded && error.is_null() {
        WebsiteDataResultSnapshot {
            request_id: request.request_id,
            status: WEBSITE_DATA_RESULT_SUCCESS,
            error: Vec::new(),
        }
    } else {
        let message = if error.is_null() || unsafe { (*error).message.is_null() } {
            b"Website data clear failed".to_vec()
        } else {
            unsafe { CStr::from_ptr((*error).message) }
                .to_bytes()
                .to_vec()
        };
        WebsiteDataResultSnapshot {
            request_id: request.request_id,
            status: WEBSITE_DATA_RESULT_ERROR,
            error: message,
        }
    };
    if !error.is_null() {
        unsafe { glib::ffi::g_error_free(error) };
    }
    WEBSITE_DATA_RESULTS.with_borrow_mut(|results| results.push_back(snapshot));
}

/// Completes `setCookie` after WebKit has copied the supplied `SoupCookie`.
unsafe extern "C" fn cookie_add_finished(
    source_object: *mut glib::gobject_ffi::GObject,
    result: *mut GAsyncResult,
    user_data: *mut c_void,
) {
    if user_data.is_null() {
        return;
    }
    let request = unsafe { Box::from_raw(user_data.cast::<CookieRequestContext>()) };
    let mut error = std::ptr::null_mut::<glib::ffi::GError>();
    let succeeded = unsafe {
        webkit_cookie_manager_add_cookie_finish(
            source_object.cast::<WebKitCookieManager>(),
            result,
            &mut error,
        ) != 0
    };
    enqueue_cookie_result(if succeeded && error.is_null() {
        CookieResultSnapshot {
            request_id: request.request_id,
            status: COOKIE_RESULT_SUCCESS,
            had_cookies: -1,
            accept_policy: -1,
            error: Vec::new(),
            cookies: Vec::new(),
        }
    } else {
        CookieResultSnapshot {
            request_id: request.request_id,
            status: COOKIE_RESULT_ERROR,
            had_cookies: -1,
            accept_policy: -1,
            error: take_error(error, b"Cookie add failed"),
            cookies: Vec::new(),
        }
    });
}

/// Completes `getCookies` by copying and releasing WebKit's cookie list.
unsafe extern "C" fn cookie_get_finished(
    source_object: *mut glib::gobject_ffi::GObject,
    result: *mut GAsyncResult,
    user_data: *mut c_void,
) {
    if user_data.is_null() {
        return;
    }
    let request = unsafe { Box::from_raw(user_data.cast::<CookieRequestContext>()) };
    let mut error = std::ptr::null_mut::<glib::ffi::GError>();
    let list = unsafe {
        webkit_cookie_manager_get_cookies_finish(
            source_object.cast::<WebKitCookieManager>(),
            result,
            &mut error,
        )
    };
    if error.is_null() {
        enqueue_cookie_result(CookieResultSnapshot {
            request_id: request.request_id,
            status: COOKIE_RESULT_SUCCESS,
            had_cookies: -1,
            accept_policy: -1,
            error: Vec::new(),
            cookies: take_cookie_list(list),
        });
    } else {
        // Defensive cleanup if a newer WebKit ever returns both a list and an
        // error, even though the documented contract returns NULL on failure.
        drop(take_cookie_list(list));
        enqueue_cookie_result(CookieResultSnapshot {
            request_id: request.request_id,
            status: COOKIE_RESULT_ERROR,
            had_cookies: -1,
            accept_policy: -1,
            error: take_error(error, b"Cookie lookup failed"),
            cookies: Vec::new(),
        });
    }
}

/// Completes an asynchronous read of WPE's effective cookie policy.
unsafe extern "C" fn cookie_accept_policy_finished(
    source_object: *mut glib::gobject_ffi::GObject,
    result: *mut GAsyncResult,
    user_data: *mut c_void,
) {
    if user_data.is_null() {
        return;
    }
    let request = unsafe { Box::from_raw(user_data.cast::<CookieRequestContext>()) };
    let mut error = std::ptr::null_mut::<glib::ffi::GError>();
    let policy = unsafe {
        webkit_cookie_manager_get_accept_policy_finish(
            source_object.cast::<WebKitCookieManager>(),
            result,
            &mut error,
        )
    };
    if error.is_null() && cookie_accept_policy_is_valid(policy) {
        enqueue_cookie_result(CookieResultSnapshot {
            request_id: request.request_id,
            status: COOKIE_RESULT_SUCCESS,
            had_cookies: -1,
            accept_policy: policy,
            error: Vec::new(),
            cookies: Vec::new(),
        });
    } else {
        enqueue_cookie_result(CookieResultSnapshot {
            request_id: request.request_id,
            status: COOKIE_RESULT_ERROR,
            had_cookies: -1,
            accept_policy: -1,
            error: take_error(error, b"Cookie accept-policy lookup failed"),
            cookies: Vec::new(),
        });
    }
}

/// First phase of `clearCookies`: enumerate the jar and start every deletion.
unsafe extern "C" fn cookie_clear_enumerated(
    source_object: *mut glib::gobject_ffi::GObject,
    result: *mut GAsyncResult,
    user_data: *mut c_void,
) {
    if user_data.is_null() {
        return;
    }
    let request = unsafe { Box::from_raw(user_data.cast::<CookieRequestContext>()) };
    let manager = source_object.cast::<WebKitCookieManager>();
    let mut error = std::ptr::null_mut::<glib::ffi::GError>();
    let list = unsafe { webkit_cookie_manager_get_all_cookies_finish(manager, result, &mut error) };
    if !error.is_null() {
        drop(take_cookie_list(list));
        enqueue_cookie_result(CookieResultSnapshot {
            request_id: request.request_id,
            status: COOKIE_RESULT_ERROR,
            had_cookies: -1,
            accept_policy: -1,
            error: take_error(error, b"Cookie enumeration failed"),
            cookies: Vec::new(),
        });
        return;
    }
    let mut cookie_pointers = Vec::new();
    let mut node = list;
    while !node.is_null() {
        let cookie = unsafe { (*node).data.cast::<SoupCookie>() };
        if !cookie.is_null() {
            cookie_pointers.push(cookie);
        }
        node = unsafe { (*node).next };
    }
    if cookie_pointers.is_empty() {
        if !list.is_null() {
            unsafe { glib::ffi::g_list_free(list) };
        }
        enqueue_cookie_result(CookieResultSnapshot {
            request_id: request.request_id,
            status: COOKIE_RESULT_SUCCESS,
            had_cookies: 0,
            accept_policy: -1,
            error: Vec::new(),
            cookies: Vec::new(),
        });
        return;
    }
    let batch = Rc::new(CookieClearBatch {
        request_id: request.request_id,
        remaining: Cell::new(cookie_pointers.len()),
        error: RefCell::new(None),
    });
    for cookie in cookie_pointers {
        // Each callback owns one strong batch reference. WebKit copies the
        // transfer-none SoupCookie during this start call, allowing the
        // transfer-full enumeration result to be freed immediately afterward.
        let callback_batch = Box::new(Rc::clone(&batch));
        unsafe {
            webkit_cookie_manager_delete_cookie(
                manager,
                cookie,
                std::ptr::null_mut(),
                Some(cookie_clear_finished),
                Box::into_raw(callback_batch).cast(),
            );
            soup_cookie_free(cookie);
        }
    }
    unsafe { glib::ffi::g_list_free(list) };
}

/// Completes one deletion and publishes the batch after its final callback.
unsafe extern "C" fn cookie_clear_finished(
    source_object: *mut glib::gobject_ffi::GObject,
    result: *mut GAsyncResult,
    user_data: *mut c_void,
) {
    if user_data.is_null() {
        return;
    }
    let batch = unsafe { Box::from_raw(user_data.cast::<Rc<CookieClearBatch>>()) };
    let mut error = std::ptr::null_mut::<glib::ffi::GError>();
    let succeeded = unsafe {
        webkit_cookie_manager_delete_cookie_finish(
            source_object.cast::<WebKitCookieManager>(),
            result,
            &mut error,
        ) != 0
    };
    if !succeeded || !error.is_null() {
        let error = take_error(error, b"Cookie deletion failed");
        let mut first_error = batch.error.borrow_mut();
        if first_error.is_none() {
            *first_error = Some(error);
        }
    }
    let remaining = batch.remaining.get().saturating_sub(1);
    batch.remaining.set(remaining);
    if remaining != 0 {
        return;
    }
    let error = batch.error.borrow_mut().take();
    enqueue_cookie_result(CookieResultSnapshot {
        request_id: batch.request_id,
        status: if error.is_some() {
            COOKIE_RESULT_ERROR
        } else {
            COOKIE_RESULT_SUCCESS
        },
        had_cookies: if error.is_some() { -1 } else { 1 },
        accept_policy: -1,
        error: error.unwrap_or_default(),
        cookies: Vec::new(),
    });
}

#[unsafe(no_mangle)]
/// Clears selected WebKit website-data types asynchronously.
///
/// Completion is copied into a handle-free result queue because website data
/// belongs to the application-scoped shared network session. `types` is the
/// `WebKitWebsiteDataTypes` bitmask. Returns `-1` for an empty mask, `-2` for a
/// zero request ID, and `-3` when the shared data manager is unavailable.
pub extern "C" fn webview_flutter_linux_website_data_clear(request_id: u64, types: u32) -> i32 {
    if types == 0 {
        return -1;
    }
    if request_id == 0 {
        return -2;
    }
    let Some(manager) = default_website_data_manager() else {
        return -3;
    };
    let context = Box::new(WebsiteDataClearContext { request_id });
    unsafe {
        webkit_website_data_manager_clear(
            manager,
            types,
            i64::MAX,
            std::ptr::null_mut(),
            Some(website_data_clear_finished),
            Box::into_raw(context).cast(),
        )
    };
    0
}

/// Applies an operation to the oldest global website-data result.
fn with_website_data_result<T: Copy>(
    fallback: T,
    operation: impl FnOnce(&WebsiteDataResultSnapshot) -> T,
) -> T {
    WEBSITE_DATA_RESULTS.with_borrow(|results| results.front().map_or(fallback, operation))
}

#[unsafe(no_mangle)]
/// Returns the number of completed website-data operations waiting for Dart.
pub extern "C" fn webview_flutter_linux_website_data_result_count() -> u32 {
    WEBSITE_DATA_RESULTS.with_borrow(|results| results.len().min(u32::MAX as usize) as u32)
}

#[unsafe(no_mangle)]
/// Returns the request ID of the oldest website-data result.
pub extern "C" fn webview_flutter_linux_website_data_result_request_id() -> u64 {
    with_website_data_result(0, |result| result.request_id)
}

#[unsafe(no_mangle)]
/// Returns zero for success and a negative value for failure.
pub extern "C" fn webview_flutter_linux_website_data_result_status() -> i32 {
    with_website_data_result(WEBSITE_DATA_RESULT_ERROR, |result| result.status)
}

#[unsafe(no_mangle)]
/// Returns the UTF-8 error byte length of the oldest result.
pub extern "C" fn webview_flutter_linux_website_data_result_error_length() -> usize {
    with_website_data_result(0, |result| result.error.len())
}

#[unsafe(no_mangle)]
/// Copies the oldest website-data error into caller-owned storage.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes and remain
/// valid for this call. Rust never stores the pointer.
pub unsafe extern "C" fn webview_flutter_linux_website_data_result_copy_error(
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_website_data_result(-2, |result| {
        if destination_length < result.error.len() || result.error.len() > i32::MAX as usize {
            return -3;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(result.error.as_ptr(), destination, result.error.len())
        };
        result.error.len() as i32
    })
}

#[unsafe(no_mangle)]
/// Removes the oldest website-data result after Dart copies it.
pub extern "C" fn webview_flutter_linux_website_data_result_pop() -> i32 {
    WEBSITE_DATA_RESULTS
        .with_borrow_mut(|results| if results.pop_front().is_some() { 0 } else { -1 })
}

#[unsafe(no_mangle)]
/// Starts an asynchronous application-wide cookie insertion.
///
/// All string pointers remain caller-owned; libsoup copies their values into a
/// temporary `SoupCookie`, and WebKit copies that cookie during the start call.
/// Completion is exposed through the global cookie-result queue. Returns `-1`
/// for invalid strings, `-2` for a zero request ID, `-3` when the shared cookie
/// manager is unavailable, and `-4` when libsoup rejects the cookie.
///
/// # Safety
///
/// Every string argument must point to readable NUL-terminated UTF-8 for the
/// duration of this call.
pub unsafe extern "C" fn webview_flutter_linux_cookie_set(
    request_id: u64,
    name: *const c_char,
    value: *const c_char,
    domain: *const c_char,
    path: *const c_char,
) -> i32 {
    if [name, value, domain, path]
        .into_iter()
        .any(|pointer| required_c_string(pointer).is_err())
    {
        return -1;
    }
    if request_id == 0 {
        return -2;
    }
    let Some(manager) = default_cookie_manager() else {
        return -3;
    };
    let cookie = unsafe { soup_cookie_new(name, value, domain, path, -1) };
    if cookie.is_null() {
        return -4;
    }
    let context = Box::new(CookieRequestContext { request_id });
    unsafe {
        webkit_cookie_manager_add_cookie(
            manager,
            cookie,
            std::ptr::null_mut(),
            Some(cookie_add_finished),
            Box::into_raw(context).cast(),
        );
        // `add_cookie` takes transfer-none and copies the cookie before
        // returning, so this constructor reference remains ours to release.
        soup_cookie_free(cookie);
    }
    0
}

#[unsafe(no_mangle)]
/// Starts an asynchronous cookie lookup for one HTTP(S) URI.
///
/// WebKit applies domain, path, and secure matching before returning the list.
/// Completion is exposed through the global cookie-result queue.
///
/// # Safety
///
/// `uri` must point to readable NUL-terminated UTF-8 for this call.
pub unsafe extern "C" fn webview_flutter_linux_cookie_get(
    request_id: u64,
    uri: *const c_char,
) -> i32 {
    if required_c_string(uri).is_err() {
        return -1;
    }
    if request_id == 0 {
        return -2;
    }
    let Some(manager) = default_cookie_manager() else {
        return -3;
    };
    let context = Box::new(CookieRequestContext { request_id });
    unsafe {
        webkit_cookie_manager_get_cookies(
            manager,
            uri,
            std::ptr::null_mut(),
            Some(cookie_get_finished),
            Box::into_raw(context).cast(),
        )
    };
    0
}

#[unsafe(no_mangle)]
/// Starts an asynchronous clear of the shared cookie jar.
///
/// WebKit is first asked whether any cookies exist so the federated API can
/// return its required boolean, then deletes each cookie through WPE's
/// cookie-manager API. Completion is exposed through the global result queue.
pub extern "C" fn webview_flutter_linux_cookie_clear(request_id: u64) -> i32 {
    if request_id == 0 {
        return -2;
    }
    let Some(manager) = default_cookie_manager() else {
        return -3;
    };
    let context = Box::new(CookieRequestContext { request_id });
    unsafe {
        webkit_cookie_manager_get_all_cookies(
            manager,
            std::ptr::null_mut(),
            Some(cookie_clear_enumerated),
            Box::into_raw(context).cast(),
        )
    };
    0
}

#[unsafe(no_mangle)]
/// Sets WPE's application-wide cookie acceptance policy.
///
/// Policies are zero for accept-always, one for accept-never, and two for
/// accept-no-third-party. WPE temporarily applies accept-always when policy two
/// is selected while ITP is enabled, because ITP makes its own adaptive
/// third-party-cookie decisions. Returns `-1` for an invalid policy and `-3`
/// when the shared cookie manager is unavailable.
pub extern "C" fn webview_flutter_linux_cookie_set_accept_policy(policy: i32) -> i32 {
    if !cookie_accept_policy_is_valid(policy) {
        return -1;
    }
    let Some(manager) = default_cookie_manager() else {
        return -3;
    };
    unsafe { webkit_cookie_manager_set_accept_policy(manager, policy) };
    0
}

#[unsafe(no_mangle)]
/// Starts an asynchronous read of WPE's effective application cookie policy.
///
/// Completion uses the ordinary cookie-result queue. The returned policy is
/// WPE's effective value, so no-third-party reads as accept-always while ITP is
/// active. Returns `-2` for a zero request ID and `-3` when the shared manager
/// is unavailable.
pub extern "C" fn webview_flutter_linux_cookie_get_accept_policy(request_id: u64) -> i32 {
    if request_id == 0 {
        return -2;
    }
    let Some(manager) = default_cookie_manager() else {
        return -3;
    };
    let context = Box::new(CookieRequestContext { request_id });
    unsafe {
        webkit_cookie_manager_get_accept_policy(
            manager,
            std::ptr::null_mut(),
            Some(cookie_accept_policy_finished),
            Box::into_raw(context).cast(),
        )
    };
    0
}

#[unsafe(no_mangle)]
/// Enables or disables Intelligent Tracking Prevention for the shared session.
pub extern "C" fn webview_flutter_linux_cookie_set_itp_enabled(enabled: i32) -> i32 {
    let Ok(session) = shared_network_session() else {
        return -3;
    };
    unsafe { webkit_network_session_set_itp_enabled(session, i32::from(enabled != 0)) };
    0
}

#[unsafe(no_mangle)]
/// Returns one when ITP is enabled, zero when disabled, or `-3` when the shared
/// network session is unavailable.
pub extern "C" fn webview_flutter_linux_cookie_itp_enabled() -> i32 {
    let Ok(session) = shared_network_session() else {
        return -3;
    };
    i32::from(unsafe { webkit_network_session_get_itp_enabled(session) } != 0)
}

/// Applies an operation to the oldest global cookie result.
fn with_cookie_result<T: Copy>(
    fallback: T,
    operation: impl FnOnce(&CookieResultSnapshot) -> T,
) -> T {
    COOKIE_RESULTS.with_borrow(|results| results.front().map_or(fallback, operation))
}

/// Resolves a field from one cookie in the oldest result.
pub(super) fn with_cookie_field<T: Copy>(
    cookie_index: u32,
    field: u32,
    fallback: T,
    operation: impl FnOnce(&[u8]) -> T,
) -> T {
    with_cookie_result(fallback, |result| {
        let Some(cookie) = result.cookies.get(cookie_index as usize) else {
            return fallback;
        };
        let bytes = match field {
            0 => &cookie.name,
            1 => &cookie.value,
            2 => &cookie.domain,
            3 => &cookie.path,
            _ => return fallback,
        };
        operation(bytes)
    })
}

/// Copies bytes into a Dart-owned destination without appending a NUL byte.
unsafe fn copy_cookie_bytes(bytes: &[u8], destination: *mut u8, destination_length: usize) -> i32 {
    if destination.is_null() {
        return -1;
    }
    if destination_length < bytes.len() || bytes.len() > i32::MAX as usize {
        return -2;
    }
    unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), destination, bytes.len()) };
    bytes.len() as i32
}

#[unsafe(no_mangle)]
/// Returns the number of completed cookie operations waiting for Dart.
pub extern "C" fn webview_flutter_linux_cookie_result_count() -> u32 {
    COOKIE_RESULTS.with_borrow(|results| results.len().min(u32::MAX as usize) as u32)
}

#[unsafe(no_mangle)]
/// Returns the request ID of the oldest completed cookie operation.
pub extern "C" fn webview_flutter_linux_cookie_result_request_id() -> u64 {
    with_cookie_result(0, |result| result.request_id)
}

#[unsafe(no_mangle)]
/// Returns zero for success and a negative status for the oldest result.
pub extern "C" fn webview_flutter_linux_cookie_result_status() -> i32 {
    with_cookie_result(COOKIE_RESULT_ERROR, |result| result.status)
}

#[unsafe(no_mangle)]
/// Returns whether cookies existed before a successful clear, or `-1` when the
/// oldest operation was not a clear.
pub extern "C" fn webview_flutter_linux_cookie_result_had_cookies() -> i32 {
    with_cookie_result(-1, |result| result.had_cookies)
}

#[unsafe(no_mangle)]
/// Returns the effective accept policy carried by the oldest policy result, or
/// `-1` when the oldest operation did not read the policy.
pub extern "C" fn webview_flutter_linux_cookie_result_accept_policy() -> i32 {
    with_cookie_result(-1, |result| result.accept_policy)
}

#[unsafe(no_mangle)]
/// Returns the error byte length for the oldest cookie operation.
pub extern "C" fn webview_flutter_linux_cookie_result_error_length() -> usize {
    with_cookie_result(0, |result| result.error.len())
}

#[unsafe(no_mangle)]
/// Copies the oldest cookie-operation error into Dart-owned memory.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes.
pub unsafe extern "C" fn webview_flutter_linux_cookie_result_copy_error(
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    with_cookie_result(-2, |result| unsafe {
        copy_cookie_bytes(&result.error, destination, destination_length)
    })
}

#[unsafe(no_mangle)]
/// Returns the number of cookies carried by the oldest lookup result.
pub extern "C" fn webview_flutter_linux_cookie_result_cookie_count() -> u32 {
    with_cookie_result(0, |result| {
        result.cookies.len().min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Returns a cookie field's byte length.
///
/// Field `0` is name, `1` value, `2` domain, and `3` path. Zero also denotes
/// an unavailable index or selector; the copy operation distinguishes errors.
pub extern "C" fn webview_flutter_linux_cookie_result_field_length(
    cookie_index: u32,
    field: u32,
) -> usize {
    with_cookie_field(cookie_index, field, 0, <[u8]>::len)
}

#[unsafe(no_mangle)]
/// Copies one field from one cookie in the oldest lookup result.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes.
pub unsafe extern "C" fn webview_flutter_linux_cookie_result_copy_field(
    cookie_index: u32,
    field: u32,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    with_cookie_field(cookie_index, field, -2, |bytes| unsafe {
        copy_cookie_bytes(bytes, destination, destination_length)
    })
}

#[unsafe(no_mangle)]
/// Removes the oldest completed cookie operation after Dart copied it.
pub extern "C" fn webview_flutter_linux_cookie_result_pop() -> i32 {
    COOKIE_RESULTS.with_borrow_mut(|results| if results.pop_front().is_some() { 0 } else { -1 })
}
