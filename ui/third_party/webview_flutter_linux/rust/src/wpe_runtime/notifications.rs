// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Flutter-owned presentation and lifecycle for Web Notifications.
//!
//! WPE's `show-notification` signal lends a [`WebKitNotification`] to the
//! embedder. Returning `true` suppresses the optional libnotify fallback, so
//! this module retains the object until Dart presents, clicks, or closes it.
//! WebKit may independently withdraw a notification when page script closes it
//! or navigation occurs; the native `closed` signal removes retained state and
//! queues an ID for Dart so application UI can disappear as well.

use super::prelude::*;

const MAX_NOTIFICATIONS: usize = 32;
const MAX_NOTIFICATION_CLOSED_EVENTS: usize = 64;

/// Owned metadata and native lifetime for one page-created notification.
pub(super) struct NotificationSnapshot {
    id: u64,
    title: Vec<u8>,
    body: Vec<u8>,
    tag: Vec<u8>,
    has_tag: bool,
    url: Vec<u8>,
    pub(super) notification: glib::Object,
}

/// Enqueues one terminal close transition without duplicates or growth.
pub(super) fn enqueue_notification_closed_event(events: &mut VecDeque<u64>, id: u64) {
    if events.contains(&id) {
        return;
    }
    if events.len() == MAX_NOTIFICATION_CLOSED_EVENTS {
        events.pop_front();
    }
    events.push_back(id);
}

/// Captures notifications for Flutter instead of invoking native UI.
pub(super) fn connect_notifications(webview: &glib::Object, native_view: Weak<NativeView>) {
    let raw_webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(webview).0
        as *mut WebKitWebView as usize;
    webview.connect_local("show-notification", false, move |values| {
        let notification = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        };
        if notification.is_null() {
            return Some(false.to_value());
        }
        let notification_pointer = notification.cast::<WebKitNotification>();
        let Some(native_view) = native_view.upgrade() else {
            unsafe { webkit_notification_close(notification_pointer) };
            return Some(true.to_value());
        };
        let retained_count = native_view.notification_requests.borrow().len()
            + native_view.pending_notifications.borrow().len();
        if retained_count >= MAX_NOTIFICATIONS {
            unsafe { webkit_notification_close(notification_pointer) };
            return Some(true.to_value());
        }
        let id = {
            let mut next = native_view.next_notification_id.borrow_mut();
            let id = (*next).max(1);
            *next = id.wrapping_add(1).max(1);
            id
        };
        // SAFETY: the signal supplies a live transfer-none GObject. Retaining
        // it is required because Flutter notification UI may outlive this
        // callback by an arbitrary amount of time.
        let notification: glib::Object = unsafe { from_glib_none(notification) };
        let closed_view = Rc::downgrade(&native_view);
        notification.connect_local("closed", false, move |_| {
            let native_view = closed_view.upgrade()?;
            {
                let mut requests = native_view.notification_requests.borrow_mut();
                if let Some(index) = requests.iter().position(|request| request.id == id) {
                    requests.remove(index);
                }
            }
            let delivered = native_view
                .pending_notifications
                .borrow_mut()
                .remove(&id)
                .is_some();
            if delivered {
                enqueue_notification_closed_event(
                    &mut native_view.notification_closed_events.borrow_mut(),
                    id,
                );
            }
            // A notification withdrawn before Flutter's next pump was never
            // visible to Dart, so it needs no corresponding close event.
            None
        });
        let pointer = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&notification)
            .0
            .cast::<WebKitNotification>();
        let tag = unsafe { webkit_notification_get_tag(pointer) };
        native_view
            .notification_requests
            .borrow_mut()
            .push_back(NotificationSnapshot {
                id,
                title: foreign_bytes(unsafe { webkit_notification_get_title(pointer) }),
                body: foreign_bytes(unsafe { webkit_notification_get_body(pointer) }),
                tag: foreign_bytes(tag),
                has_tag: !tag.is_null(),
                url: webview_uri(raw_webview as *mut WebKitWebView),
                notification,
            });
        Some(true.to_value())
    });
}

/// Closes every native notification retained by this view.
///
/// Notifications still queued for Dart have no public object to close. IDs in
/// the pending map have already been delivered, so a surviving controller must
/// receive a close event when its web process exits. Final view disposal sets
/// `report_delivered` to false because Dart closes its objects synchronously
/// before releasing the native handle and can no longer poll this queue.
pub(super) fn cancel_notifications(native_view: &NativeView, report_delivered: bool) {
    let queued: Vec<_> = native_view
        .notification_requests
        .borrow_mut()
        .drain(..)
        .map(|snapshot| snapshot.notification)
        .collect();
    let pending: Vec<_> = native_view
        .pending_notifications
        .borrow_mut()
        .drain()
        .map(|(id, snapshot)| (id, snapshot.notification))
        .collect();
    if report_delivered {
        let mut events = native_view.notification_closed_events.borrow_mut();
        for (id, _) in &pending {
            enqueue_notification_closed_event(&mut events, *id);
        }
    } else {
        native_view.notification_closed_events.borrow_mut().clear();
    }
    for notification in queued
        .into_iter()
        .chain(pending.into_iter().map(|(_, notification)| notification))
    {
        let pointer = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&notification)
            .0
            .cast::<WebKitNotification>();
        unsafe { webkit_notification_close(pointer) };
    }
}

/// Applies an operation to the oldest notification waiting for Dart.
fn with_notification<T: Copy>(
    handle: u64,
    fallback: T,
    operation: impl FnOnce(&NotificationSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    native_view
        .notification_requests
        .borrow()
        .front()
        .map_or(fallback, operation)
}

#[unsafe(no_mangle)]
/// Returns the number of page notifications waiting for Flutter.
pub extern "C" fn webview_flutter_linux_wpe_notification_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.notification_requests
            .borrow()
            .len()
            .min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Returns the bridge ID of the oldest waiting notification.
pub extern "C" fn webview_flutter_linux_wpe_notification_id(handle: u64) -> u64 {
    with_notification(handle, 0, |notification| notification.id)
}

#[unsafe(no_mangle)]
/// Returns whether the oldest notification supplied a tag.
pub extern "C" fn webview_flutter_linux_wpe_notification_has_tag(handle: u64) -> i32 {
    with_notification(handle, 0, |notification| i32::from(notification.has_tag))
}

/// Selects a copied string field from the oldest waiting notification.
fn with_notification_field<T: Copy>(
    handle: u64,
    field: u32,
    fallback: T,
    operation: impl FnOnce(&[u8]) -> T,
) -> T {
    with_notification(handle, fallback, |notification| {
        let bytes = match field {
            0 => &notification.title,
            1 => &notification.body,
            2 => &notification.tag,
            3 => &notification.url,
            _ => return fallback,
        };
        operation(bytes)
    })
}

#[unsafe(no_mangle)]
/// Returns a notification field's UTF-8 byte length.
pub extern "C" fn webview_flutter_linux_wpe_notification_field_length(
    handle: u64,
    field: u32,
) -> usize {
    with_notification_field(handle, field, 0, <[u8]>::len)
}

#[unsafe(no_mangle)]
/// Copies title, body, tag, or source URL into Dart-owned memory.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes.
pub unsafe extern "C" fn webview_flutter_linux_wpe_notification_copy_field(
    handle: u64,
    field: u32,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_notification_field(handle, field, -2, |bytes| {
        if destination_length < bytes.len() || bytes.len() > i32::MAX as usize {
            return -3;
        }
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), destination, bytes.len()) };
        bytes.len() as i32
    })
}

#[unsafe(no_mangle)]
/// Moves the oldest notification into Flutter's active set.
pub extern "C" fn webview_flutter_linux_wpe_notification_take(handle: u64) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let Some(notification) = native_view.notification_requests.borrow_mut().pop_front() else {
        return 1;
    };
    native_view
        .pending_notifications
        .borrow_mut()
        .insert(notification.id, notification);
    0
}

#[unsafe(no_mangle)]
/// Clicks or closes one delivered notification.
///
/// Action `0` closes the notification and is terminal. Action `1` reports a
/// click while retaining it for a later page- or Flutter-driven close.
pub extern "C" fn webview_flutter_linux_wpe_notification_respond(
    handle: u64,
    notification_id: u64,
    action: u32,
) -> i32 {
    if action > 1 {
        return -3;
    }
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let notification = {
        let pending = native_view.pending_notifications.borrow();
        let Some(notification) = pending.get(&notification_id) else {
            return -2;
        };
        notification.notification.clone()
    };
    let pointer = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&notification)
        .0
        .cast::<WebKitNotification>();
    if action == 1 {
        unsafe { webkit_notification_clicked(pointer) };
        return 0;
    }
    unsafe { webkit_notification_close(pointer) };
    // WPE normally emits `closed` synchronously. Keep a defensive fallback so
    // an alternate build cannot strand the native reference or Dart object.
    if native_view
        .pending_notifications
        .borrow_mut()
        .remove(&notification_id)
        .is_some()
    {
        enqueue_notification_closed_event(
            &mut native_view.notification_closed_events.borrow_mut(),
            notification_id,
        );
    }
    0
}

#[unsafe(no_mangle)]
/// Returns the number of delivered notifications withdrawn by WebKit.
pub extern "C" fn webview_flutter_linux_wpe_notification_closed_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.notification_closed_events
            .borrow()
            .len()
            .min(u32::MAX as usize) as u32
    })
}

#[unsafe(no_mangle)]
/// Removes and returns the oldest notification close event.
pub extern "C" fn webview_flutter_linux_wpe_notification_closed_take(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| {
        view.notification_closed_events
            .borrow_mut()
            .pop_front()
            .unwrap_or(0)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bounds_and_deduplicates_notification_close_events() {
        let mut events = VecDeque::new();
        enqueue_notification_closed_event(&mut events, 7);
        enqueue_notification_closed_event(&mut events, 7);
        assert_eq!(events, VecDeque::from([7]));

        for id in 8..=(MAX_NOTIFICATION_CLOSED_EVENTS as u64 + 8) {
            enqueue_notification_closed_event(&mut events, id);
        }
        assert_eq!(events.len(), MAX_NOTIFICATION_CLOSED_EVENTS);
        assert_eq!(events.front(), Some(&9));
        assert_eq!(
            events.back(),
            Some(&(MAX_NOTIFICATION_CLOSED_EVENTS as u64 + 8))
        );
    }
}
