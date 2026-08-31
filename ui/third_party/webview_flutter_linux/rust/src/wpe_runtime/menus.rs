// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Flutter-owned context menus and HTML option menus.
//!
//! WPE's native menu signal values are callback-scoped. This module snapshots
//! visible fields, retains only the native actions or option menu needed for a
//! later response, and exposes generation-based polling through the C ABI.

use super::prelude::*;

/// Flutter-readable copy of the current WebKit context menu.
///
/// Coordinates use WPE's logical view space and can be placed directly over
/// the Flutter texture.
pub(super) struct ContextMenuSnapshot {
    x: f64,
    y: f64,
    items: Vec<ContextMenuItemSnapshot>,
}

/// One retained context-menu action.
///
/// The title is copied immediately. `action` and optional `target` receive
/// native references so Flutter may activate them after WebKit's signal ends.
struct ContextMenuItemSnapshot {
    title: Vec<u8>,
    is_separator: bool,
    stock_action: i32,
    action: *mut GAction,
    target: *mut GVariant,
}

const CONTEXT_MENU_ACTION_COPY: i32 = 13;
const CONTEXT_MENU_ACTION_CUT: i32 = 14;
const CONTEXT_MENU_ACTION_PASTE: i32 = 15;

/// Returns the WebKit editing command for stock actions that operate on the
/// current view rather than on a link, media element, or custom target.
fn editing_command(stock_action: i32) -> Option<&'static [u8]> {
    match stock_action {
        CONTEXT_MENU_ACTION_COPY => Some(b"Copy\0"),
        CONTEXT_MENU_ACTION_CUT => Some(b"Cut\0"),
        CONTEXT_MENU_ACTION_PASTE => Some(b"Paste\0"),
        _ => None,
    }
}

/// Flutter-readable copy plus retained ownership for one HTML select menu.
///
/// The `WebKitOptionMenu` is a transfer-none signal argument. Retaining its
/// GObject permits Flutter to present an asynchronous popup and then activate
/// or close the native menu exactly once. Bounds use logical WPE pixels.
pub(super) struct OptionMenuSnapshot {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    items: Vec<OptionMenuItemSnapshot>,
    pub(super) menu: glib::Object,
}

/// One immutable option copied from WebKit before the signal returns.
struct OptionMenuItemSnapshot {
    native_index: u32,
    label: Vec<u8>,
    tooltip: Vec<u8>,
    is_group_label: bool,
    is_group_child: bool,
    is_enabled: bool,
    is_selected: bool,
}

impl Drop for ContextMenuItemSnapshot {
    fn drop(&mut self) {
        // Balance the native references acquired while snapshotting the menu.
        // Separators and targetless actions legitimately store null pointers.
        unsafe {
            if !self.action.is_null() {
                glib::gobject_ffi::g_object_unref(self.action.cast());
            }
            if !self.target.is_null() {
                g_variant_unref(self.target);
            }
        }
    }
}

/// Replaces WebKit's native menu with a retained snapshot consumed by Flutter.
///
/// Returning `true` suppresses the WPE-native presentation. Menu action and
/// target references are retained until Flutter activates/dismisses the menu or
/// the view is disposed.
pub(super) fn connect_context_menu(webview: &glib::Object, native_view: Weak<NativeView>) {
    webview.connect_closure(
        "context-menu",
        false,
        glib::closure_local!(move |_webview: glib::Object,
                                   menu: glib::Object,
                                   _hit_test: glib::Object|
              -> bool {
            let raw_menu = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&menu).0
                as *mut WebKitContextMenu;
            let mut x = 0;
            let mut y = 0;
            unsafe { webkit_context_menu_get_position(raw_menu, &mut x, &mut y) };
            let item_count = unsafe { webkit_context_menu_get_n_items(raw_menu) };
            let mut items = Vec::with_capacity(item_count as usize);
            for index in 0..item_count {
                let item = unsafe { webkit_context_menu_get_item_at_position(raw_menu, index) };
                if item.is_null() {
                    continue;
                }
                let title = unsafe { webkit_context_menu_item_get_title(item) };
                let title = if title.is_null() {
                    Vec::new()
                } else {
                    unsafe { CStr::from_ptr(title) }.to_bytes().to_vec()
                };
                let action = unsafe { webkit_context_menu_item_get_gaction(item) };
                let action = if action.is_null() {
                    std::ptr::null_mut()
                } else {
                    unsafe { glib::gobject_ffi::g_object_ref(action.cast()) }.cast()
                };
                let target = unsafe { webkit_context_menu_item_get_gaction_target(item) };
                let target = if target.is_null() {
                    std::ptr::null_mut()
                } else {
                    unsafe { g_variant_ref(target) }
                };
                items.push(ContextMenuItemSnapshot {
                    title,
                    is_separator: unsafe { webkit_context_menu_item_is_separator(item) != 0 },
                    stock_action: unsafe { webkit_context_menu_item_get_stock_action(item) },
                    action,
                    target,
                });
            }
            let Some(native_view) = native_view.upgrade() else {
                return true;
            };
            native_view
                .metrics
                .context_menu_generation
                .fetch_add(1, Ordering::AcqRel);
            native_view.context_menu.replace(Some(ContextMenuSnapshot {
                x: f64::from(x),
                y: f64::from(y),
                items,
            }));
            true
        }),
    );
}

/// Replaces WebKit's GTK-backed `<select>` popup with retained Flutter data.
///
/// The menu and its bounds are transfer-none signal arguments. All visible
/// strings and flags are copied synchronously, while one strong GObject
/// reference keeps the menu resolvable after this callback. Returning `true`
/// suppresses the default toolkit handler. The native `close` signal clears a
/// stale snapshot if the element disappears before Flutter responds.
pub(super) fn connect_option_menu(webview: &glib::Object, native_view: Weak<NativeView>) {
    webview.connect_local("show-option-menu", false, move |values| {
        let raw_menu = unsafe {
            glib::gobject_ffi::g_value_get_object(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[1]).0,
            )
        };
        if raw_menu.is_null() {
            return Some(true.to_value());
        }
        let menu_pointer = raw_menu.cast::<WebKitOptionMenu>();
        let Some(native_view) = native_view.upgrade() else {
            unsafe { webkit_option_menu_close(menu_pointer) };
            return Some(true.to_value());
        };

        let rectangle = unsafe {
            glib::gobject_ffi::g_value_get_boxed(
                ToGlibPtr::<*const glib::gobject_ffi::GValue>::to_glib_none(&values[2]).0,
            )
        }
        .cast::<WebKitRectangle>();
        let (x, y, width, height) = if rectangle.is_null() {
            (0.0, 0.0, 0.0, 0.0)
        } else {
            unsafe {
                (
                    f64::from((*rectangle).x),
                    f64::from((*rectangle).y),
                    f64::from((*rectangle).width.max(0)),
                    f64::from((*rectangle).height.max(0)),
                )
            }
        };
        let item_count = unsafe { webkit_option_menu_get_n_items(menu_pointer) };
        let mut items = Vec::with_capacity(item_count as usize);
        for native_index in 0..item_count {
            let item = unsafe { webkit_option_menu_get_item(menu_pointer, native_index) };
            if item.is_null() {
                continue;
            }
            items.push(OptionMenuItemSnapshot {
                native_index,
                label: foreign_bytes(unsafe { webkit_option_menu_item_get_label(item) }),
                tooltip: foreign_bytes(unsafe { webkit_option_menu_item_get_tooltip(item) }),
                is_group_label: unsafe { webkit_option_menu_item_is_group_label(item) } != 0,
                is_group_child: unsafe { webkit_option_menu_item_is_group_child(item) } != 0,
                is_enabled: unsafe { webkit_option_menu_item_is_enabled(item) } != 0,
                is_selected: unsafe { webkit_option_menu_item_is_selected(item) } != 0,
            });
        }
        if items.is_empty() {
            unsafe { webkit_option_menu_close(menu_pointer) };
            return Some(true.to_value());
        }

        // Only one select popup may be active for a WebView. Closing the old
        // request before installing the new snapshot prevents a late response
        // from targeting an element that no longer owns browser focus.
        if let Some(previous) = native_view.option_menu.take() {
            let previous =
                ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&previous.menu)
                    .0
                    .cast::<WebKitOptionMenu>();
            unsafe { webkit_option_menu_close(previous) };
        }

        // SAFETY: raw_menu is a live transfer-none GObject signal argument.
        let retained: glib::Object = unsafe { from_glib_none(raw_menu) };
        let menu_identity = raw_menu as usize;
        let close_view = Rc::downgrade(&native_view);
        retained.connect_local("close", false, move |_| {
            let native_view = close_view.upgrade()?;
            let is_current = {
                let current = native_view.option_menu.borrow();
                current.as_ref().is_some_and(|snapshot| {
                    ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&snapshot.menu).0
                        as usize
                        == menu_identity
                })
            };
            if is_current {
                native_view.option_menu.take();
                native_view
                    .metrics
                    .option_menu_generation
                    .fetch_add(1, Ordering::AcqRel);
            }
            None
        });
        native_view.option_menu.replace(Some(OptionMenuSnapshot {
            x,
            y,
            width,
            height,
            items,
            menu: retained,
        }));
        native_view
            .metrics
            .option_menu_generation
            .fetch_add(1, Ordering::AcqRel);
        Some(true.to_value())
    });
}

/// Resolves one retained menu item while keeping fallback behavior uniform for
/// invalid handles, absent menus, and out-of-range indices.
fn with_context_menu_item<T: Copy>(
    handle: u64,
    index: u32,
    fallback: T,
    operation: impl FnOnce(&ContextMenuItemSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    native_view
        .context_menu
        .borrow()
        .as_ref()
        .map_or(fallback, |snapshot| {
            snapshot
                .items
                .get(index as usize)
                .map_or(fallback, operation)
        })
}

/// Resolves one copied HTML option-menu entry without exposing native pointers.
fn with_option_menu_item<T: Copy>(
    handle: u64,
    index: u32,
    fallback: T,
    operation: impl FnOnce(&OptionMenuItemSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    native_view
        .option_menu
        .borrow()
        .as_ref()
        .and_then(|snapshot| snapshot.items.get(index as usize))
        .map_or(fallback, operation)
}

#[unsafe(no_mangle)]
/// Returns the generation of the latest Flutter-owned context-menu snapshot.
///
/// Zero means no context menu has ever been captured for this handle.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_generation(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| {
        view.metrics.context_menu_generation.load(Ordering::Acquire)
    })
}

#[unsafe(no_mangle)]
/// Returns the context-menu X position in logical WPE coordinates.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_x(handle: u64) -> f64 {
    native_view(handle).map_or(0.0, |view| {
        view.context_menu
            .borrow()
            .as_ref()
            .map_or(0.0, |menu| menu.x)
    })
}

#[unsafe(no_mangle)]
/// Returns the context-menu Y position in logical WPE coordinates.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_y(handle: u64) -> f64 {
    native_view(handle).map_or(0.0, |view| {
        view.context_menu
            .borrow()
            .as_ref()
            .map_or(0.0, |menu| menu.y)
    })
}

#[unsafe(no_mangle)]
/// Returns the number of entries in the retained menu snapshot.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_item_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.context_menu
            .borrow()
            .as_ref()
            .map_or(0, |snapshot| snapshot.items.len() as u32)
    })
}

#[unsafe(no_mangle)]
/// Returns the UTF-8 title length for a retained menu entry.
///
/// Separators, invalid indices, and missing menus return zero.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_item_title_length(
    handle: u64,
    index: u32,
) -> usize {
    with_context_menu_item(handle, index, 0, |item| item.title.len())
}

#[unsafe(no_mangle)]
/// Copies one retained menu title into caller-owned storage.
///
/// Returns the byte count, `-1` for a null destination, `-2` for an unavailable
/// item, or `-3` when the provided capacity is too small.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes and remain
/// valid for the duration of this call.
pub unsafe extern "C" fn webview_flutter_linux_wpe_context_menu_item_copy_title(
    handle: u64,
    index: u32,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_context_menu_item(handle, index, -2, |item| {
        if destination_length < item.title.len() {
            return -3;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(item.title.as_ptr(), destination, item.title.len())
        };
        item.title.len().min(i32::MAX as usize) as i32
    })
}

#[unsafe(no_mangle)]
/// Returns one when the indexed context-menu entry is a separator.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_item_is_separator(
    handle: u64,
    index: u32,
) -> i32 {
    with_context_menu_item(handle, index, 0, |item| i32::from(item.is_separator))
}

#[unsafe(no_mangle)]
/// Returns one when the indexed menu entry owns an enabled `GAction`.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_item_is_enabled(
    handle: u64,
    index: u32,
) -> i32 {
    with_context_menu_item(handle, index, 0, |item| {
        if item.action.is_null() {
            0
        } else {
            unsafe { i32::from(g_action_get_enabled(item.action) != 0) }
        }
    })
}

#[unsafe(no_mangle)]
/// Returns WebKit's stable stock-action identifier for one menu entry.
///
/// Zero represents a separator/no-op; 10,000 represents an application custom
/// action. Invalid handles or indices also return zero.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_item_stock_action(
    handle: u64,
    index: u32,
) -> i32 {
    with_context_menu_item(handle, index, 0, |item| item.stock_action)
}

#[unsafe(no_mangle)]
/// Activates a retained WebKit context-menu action and clears the snapshot.
///
/// Returns `-2` for a missing item and `-3` for a separator or disabled action.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_activate(handle: u64, index: u32) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let raw_webview = {
        let runtime = native_view.runtime.borrow();
        let Some(runtime) = runtime.as_ref() else {
            return -2;
        };
        ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
            as *mut WebKitWebView
    };
    let status = native_view
        .context_menu
        .borrow()
        .as_ref()
        .and_then(|snapshot| snapshot.items.get(index as usize))
        .map_or(-2, |item| {
            if item.action.is_null() || unsafe { g_action_get_enabled(item.action) } == 0 {
                return -3;
            }
            if let Some(command) = editing_command(item.stock_action) {
                unsafe {
                    webkit_web_view_execute_editing_command(raw_webview, command.as_ptr().cast())
                };
            } else {
                unsafe { g_action_activate(item.action, item.target) };
            }
            0
        });
    if status == 0 {
        native_view.context_menu.take();
    }
    status
}

#[unsafe(no_mangle)]
/// Clears the retained context menu without activating an action.
///
/// Returns zero when a menu was dismissed, one when no menu was pending, and
/// `-1` for an invalid handle.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_dismiss(handle: u64) -> i32 {
    native_view(handle).map_or(-1, |view| i32::from(view.context_menu.take().is_none()))
}

#[unsafe(no_mangle)]
/// Returns the generation changed whenever an HTML option menu opens or closes.
pub extern "C" fn webview_flutter_linux_wpe_option_menu_generation(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| {
        view.metrics.option_menu_generation.load(Ordering::Acquire)
    })
}

#[unsafe(no_mangle)]
/// Returns one while an HTML option menu is retained for Flutter.
pub extern "C" fn webview_flutter_linux_wpe_option_menu_available(handle: u64) -> i32 {
    native_view(handle).map_or(0, |view| i32::from(view.option_menu.borrow().is_some()))
}

macro_rules! option_menu_coordinate {
    ($name:ident, $field:ident) => {
        #[unsafe(no_mangle)]
        pub extern "C" fn $name(handle: u64) -> f64 {
            native_view(handle).map_or(0.0, |view| {
                view.option_menu
                    .borrow()
                    .as_ref()
                    .map_or(0.0, |menu| menu.$field)
            })
        }
    };
}

option_menu_coordinate!(webview_flutter_linux_wpe_option_menu_x, x);
option_menu_coordinate!(webview_flutter_linux_wpe_option_menu_y, y);
option_menu_coordinate!(webview_flutter_linux_wpe_option_menu_width, width);
option_menu_coordinate!(webview_flutter_linux_wpe_option_menu_height, height);

#[unsafe(no_mangle)]
/// Returns the number of entries in the retained HTML option menu.
pub extern "C" fn webview_flutter_linux_wpe_option_menu_item_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.option_menu
            .borrow()
            .as_ref()
            .map_or(0, |menu| menu.items.len().min(u32::MAX as usize) as u32)
    })
}

#[unsafe(no_mangle)]
/// Returns one copied option-menu string field's UTF-8 byte length.
///
/// Field zero is the label and field one is the tooltip.
pub extern "C" fn webview_flutter_linux_wpe_option_menu_item_field_length(
    handle: u64,
    index: u32,
    field: u32,
) -> usize {
    with_option_menu_item(handle, index, 0, |item| match field {
        0 => item.label.len(),
        1 => item.tooltip.len(),
        _ => 0,
    })
}

#[unsafe(no_mangle)]
/// Copies an option-menu label or tooltip into caller-owned storage.
///
/// Returns the copied byte count, `-1` for a null destination, `-2` for an
/// invalid handle/index/field, and `-3` when the destination is too small.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes.
pub unsafe extern "C" fn webview_flutter_linux_wpe_option_menu_item_copy_field(
    handle: u64,
    index: u32,
    field: u32,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_option_menu_item(handle, index, -2, |item| {
        let bytes = match field {
            0 => item.label.as_slice(),
            1 => item.tooltip.as_slice(),
            _ => return -2,
        };
        if destination_length < bytes.len() || bytes.len() > i32::MAX as usize {
            return -3;
        }
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), destination, bytes.len()) };
        bytes.len() as i32
    })
}

macro_rules! option_menu_item_flag {
    ($name:ident, $field:ident) => {
        #[unsafe(no_mangle)]
        pub extern "C" fn $name(handle: u64, index: u32) -> i32 {
            with_option_menu_item(handle, index, 0, |item| i32::from(item.$field))
        }
    };
}

option_menu_item_flag!(
    webview_flutter_linux_wpe_option_menu_item_is_group_label,
    is_group_label
);
option_menu_item_flag!(
    webview_flutter_linux_wpe_option_menu_item_is_group_child,
    is_group_child
);
option_menu_item_flag!(
    webview_flutter_linux_wpe_option_menu_item_is_enabled,
    is_enabled
);
option_menu_item_flag!(
    webview_flutter_linux_wpe_option_menu_item_is_selected,
    is_selected
);

#[unsafe(no_mangle)]
/// Activates one enabled option and then closes its retained native menu.
pub extern "C" fn webview_flutter_linux_wpe_option_menu_activate(handle: u64, index: u32) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let native_index = {
        let menu = native_view.option_menu.borrow();
        let Some(item) = menu
            .as_ref()
            .and_then(|snapshot| snapshot.items.get(index as usize))
        else {
            return -2;
        };
        if !item.is_enabled || item.is_group_label {
            return -3;
        }
        item.native_index
    };
    let snapshot = native_view
        .option_menu
        .take()
        .expect("option menu item was checked above");
    let menu = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&snapshot.menu)
        .0
        .cast::<WebKitOptionMenu>();
    unsafe {
        webkit_option_menu_activate_item(menu, native_index);
        webkit_option_menu_close(menu);
    }
    native_view
        .metrics
        .option_menu_generation
        .fetch_add(1, Ordering::AcqRel);
    0
}

#[unsafe(no_mangle)]
/// Closes a retained HTML option menu without changing the element value.
pub extern "C" fn webview_flutter_linux_wpe_option_menu_dismiss(handle: u64) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let Some(snapshot) = native_view.option_menu.take() else {
        return 1;
    };
    let menu = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&snapshot.menu)
        .0
        .cast::<WebKitOptionMenu>();
    unsafe { webkit_option_menu_close(menu) };
    native_view
        .metrics
        .option_menu_generation
        .fetch_add(1, Ordering::AcqRel);
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_only_stock_editing_actions_to_current_view_commands() {
        assert_eq!(
            editing_command(CONTEXT_MENU_ACTION_COPY),
            Some(&b"Copy\0"[..])
        );
        assert_eq!(
            editing_command(CONTEXT_MENU_ACTION_CUT),
            Some(&b"Cut\0"[..])
        );
        assert_eq!(
            editing_command(CONTEXT_MENU_ACTION_PASTE),
            Some(&b"Paste\0"[..])
        );
        assert_eq!(editing_command(1), None);
        assert_eq!(editing_command(10_000), None);
    }
}
