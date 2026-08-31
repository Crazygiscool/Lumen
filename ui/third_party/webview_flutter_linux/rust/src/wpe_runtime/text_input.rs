// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! WebKit input-method adapter and its C ABI.
//!
//! The adapter subclasses `WebKitInputMethodContext` so Flutter's text-input
//! client can own preedit and commit behavior without a GTK input method. All
//! state remains attached to the platform-thread-local `NativeView`.

use super::prelude::*;

/// Latest editable-element state reported by WebKit's input-method callbacks.
///
/// WebKit describes cursor and selection positions as UTF-8 byte offsets.
/// Those offsets are retained verbatim across the native ABI; Dart converts
/// them to the UTF-16 code-unit indexing used by `TextEditingValue`. Only the
/// latest snapshot is required because each generation is a complete state,
/// unlike navigation events where intermediate transitions are observable.
#[derive(Default)]
pub(super) struct InputMethodSnapshot {
    focused: bool,
    text: Vec<u8>,
    cursor_index: u32,
    selection_index: u32,
    cursor_x: i32,
    cursor_y: i32,
    cursor_width: i32,
    cursor_height: i32,
    input_purpose: i32,
    input_hints: u32,
}

type GObjectFinalize = unsafe extern "C" fn(*mut glib::gobject_ffi::GObject);

/// Parent finalizer captured before the adapter overrides the class slot.
static INPUT_METHOD_PARENT_FINALIZE: OnceLock<Option<GObjectFinalize>> = OnceLock::new();

/// Returns the concrete adapter layout for a WebKit parent pointer.
///
/// # Safety
///
/// `context` must be an instance of the type returned by
/// [`flutter_input_method_context_get_type`].
pub(super) unsafe fn flutter_input_method_context(
    context: *mut WebKitInputMethodContext,
) -> &'static mut FlutterInputMethodContext {
    unsafe { &mut *context.cast::<FlutterInputMethodContext>() }
}

/// Runs an operation with the live view owning an input-method adapter.
fn with_input_method_owner(
    context: *mut WebKitInputMethodContext,
    operation: impl FnOnce(&NativeView),
) {
    if context.is_null() {
        return;
    }
    let adapter = unsafe { flutter_input_method_context(context) };
    if adapter.owner.is_null() {
        return;
    }
    let owner = unsafe { &*adapter.owner };
    if let Some(owner) = owner.upgrade() {
        operation(&owner);
    }
}

fn publish_input_method_state(native_view: &NativeView) {
    native_view
        .metrics
        .input_method_generation
        .fetch_add(1, Ordering::Release);
}

unsafe extern "C" fn flutter_input_method_set_enable_preedit(
    context: *mut WebKitInputMethodContext,
    enabled: i32,
) {
    let adapter = unsafe { flutter_input_method_context(context) };
    adapter.preedit_enabled = i32::from(enabled != 0);
}

pub(super) unsafe extern "C" fn flutter_input_method_get_preedit(
    context: *mut WebKitInputMethodContext,
    text: *mut *mut c_char,
    underlines: *mut *mut glib::ffi::GList,
    cursor_offset: *mut u32,
) {
    let adapter = unsafe { flutter_input_method_context(context) };
    if !text.is_null() {
        let source = if adapter.preedit_enabled != 0 && !adapter.preedit_text.is_null() {
            adapter.preedit_text.cast_const()
        } else {
            c"".as_ptr()
        };
        unsafe { text.write(glib::ffi::g_strdup(source)) };
    }
    if !underlines.is_null() {
        // WebKit applies its default preedit styling when no explicit
        // underline list is supplied.
        unsafe { underlines.write(std::ptr::null_mut()) };
    }
    if !cursor_offset.is_null() {
        unsafe { cursor_offset.write(adapter.preedit_cursor_offset) };
    }
}

unsafe extern "C" fn flutter_input_method_filter_key_event(
    _context: *mut WebKitInputMethodContext,
    _key_event: *mut c_void,
) -> i32 {
    // Flutter's platform text-input plugin filters character-producing keys
    // before they reach this WebView. Returning false keeps navigation and
    // shortcut keys on WebKit's ordinary WPE event path.
    0
}

unsafe extern "C" fn flutter_input_method_focus_in(context: *mut WebKitInputMethodContext) {
    with_input_method_owner(context, |native_view| {
        let mut state = native_view.input_method.borrow_mut();
        state.input_purpose = unsafe { webkit_input_method_context_get_input_purpose(context) };
        state.input_hints = unsafe { webkit_input_method_context_get_input_hints(context) };
    });
}

unsafe extern "C" fn flutter_input_method_focus_out(context: *mut WebKitInputMethodContext) {
    let adapter = unsafe { flutter_input_method_context(context) };
    adapter.preedit_active = 0;
    adapter.preedit_cursor_offset = 0;
    if !adapter.preedit_text.is_null() {
        unsafe { glib::ffi::g_free(adapter.preedit_text.cast()) };
    }
    adapter.preedit_text = unsafe { glib::ffi::g_strdup(c"".as_ptr()) };
    with_input_method_owner(context, |native_view| {
        native_view.input_method.borrow_mut().focused = false;
        publish_input_method_state(native_view);
    });
}

unsafe extern "C" fn flutter_input_method_cursor_area(
    context: *mut WebKitInputMethodContext,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
) {
    with_input_method_owner(context, |native_view| {
        let mut state = native_view.input_method.borrow_mut();
        state.cursor_x = x;
        state.cursor_y = y;
        state.cursor_width = width.max(0);
        state.cursor_height = height.max(0);
        drop(state);
        publish_input_method_state(native_view);
    });
}

unsafe extern "C" fn flutter_input_method_surrounding(
    context: *mut WebKitInputMethodContext,
    text: *const c_char,
    length: u32,
    cursor_index: u32,
    selection_index: u32,
) {
    if text.is_null() && length != 0 {
        return;
    }
    let bytes = if length == 0 {
        &[][..]
    } else {
        unsafe { std::slice::from_raw_parts(text.cast::<u8>(), length as usize) }
    };
    with_input_method_owner(context, |native_view| {
        let mut state = native_view.input_method.borrow_mut();
        state.focused = true;
        state.text.clear();
        state.text.extend_from_slice(bytes);
        state.cursor_index = cursor_index.min(length);
        state.selection_index = selection_index.min(length);
        state.input_purpose = unsafe { webkit_input_method_context_get_input_purpose(context) };
        state.input_hints = unsafe { webkit_input_method_context_get_input_hints(context) };
        drop(state);
        publish_input_method_state(native_view);
    });
}

unsafe extern "C" fn flutter_input_method_reset(context: *mut WebKitInputMethodContext) {
    let adapter = unsafe { flutter_input_method_context(context) };
    adapter.preedit_active = 0;
    adapter.preedit_cursor_offset = 0;
    if !adapter.preedit_text.is_null() {
        unsafe { glib::ffi::g_free(adapter.preedit_text.cast()) };
    }
    adapter.preedit_text = unsafe { glib::ffi::g_strdup(c"".as_ptr()) };
    with_input_method_owner(context, |native_view| {
        native_view.input_method.borrow_mut().focused = false;
        publish_input_method_state(native_view);
    });
}

unsafe extern "C" fn flutter_input_method_finalize(object: *mut glib::gobject_ffi::GObject) {
    let adapter = unsafe { &mut *object.cast::<FlutterInputMethodContext>() };
    if !adapter.owner.is_null() {
        drop(unsafe { Box::from_raw(adapter.owner) });
        adapter.owner = std::ptr::null_mut();
    }
    if !adapter.preedit_text.is_null() {
        unsafe { glib::ffi::g_free(adapter.preedit_text.cast()) };
        adapter.preedit_text = std::ptr::null_mut();
    }
    if let Some(Some(parent_finalize)) = INPUT_METHOD_PARENT_FINALIZE.get() {
        unsafe { parent_finalize(object) };
    }
}

unsafe extern "C" fn flutter_input_method_class_init(class: *mut c_void, _class_data: *mut c_void) {
    let class = unsafe { &mut *class.cast::<WebKitInputMethodContextClass>() };
    let _ = INPUT_METHOD_PARENT_FINALIZE.set(class.parent_class.finalize);
    class.parent_class.finalize = Some(flutter_input_method_finalize);
    class.set_enable_preedit = Some(flutter_input_method_set_enable_preedit);
    class.get_preedit = Some(flutter_input_method_get_preedit);
    class.filter_key_event = Some(flutter_input_method_filter_key_event);
    class.notify_focus_in = Some(flutter_input_method_focus_in);
    class.notify_focus_out = Some(flutter_input_method_focus_out);
    class.notify_cursor_area = Some(flutter_input_method_cursor_area);
    class.notify_surrounding = Some(flutter_input_method_surrounding);
    class.reset = Some(flutter_input_method_reset);
}

unsafe extern "C" fn flutter_input_method_instance_init(
    instance: *mut glib::gobject_ffi::GTypeInstance,
    _class: *mut c_void,
) {
    let adapter = unsafe { &mut *instance.cast::<FlutterInputMethodContext>() };
    adapter.owner = std::ptr::null_mut();
    adapter.preedit_text = unsafe { glib::ffi::g_strdup(c"".as_ptr()) };
    adapter.preedit_cursor_offset = 0;
    adapter.preedit_enabled = 1;
    adapter.preedit_active = 0;
}

/// Registers the concrete adapter once in GLib's process-wide type system.
pub(super) fn flutter_input_method_context_get_type() -> glib::ffi::GType {
    static TYPE: OnceLock<glib::ffi::GType> = OnceLock::new();
    *TYPE.get_or_init(|| unsafe {
        glib::gobject_ffi::g_type_register_static_simple(
            webkit_input_method_context_get_type(),
            c"WebviewFlutterLinuxInputMethodContext".as_ptr(),
            mem::size_of::<WebKitInputMethodContextClass>() as u32,
            Some(flutter_input_method_class_init),
            mem::size_of::<FlutterInputMethodContext>() as u32,
            Some(flutter_input_method_instance_init),
            0,
        )
    })
}

/// Creates one adapter and binds its callbacks weakly to a native view.
pub(super) fn create_input_method_context(
    native_view: Weak<NativeView>,
) -> Result<glib::Object, i32> {
    let object = unsafe {
        glib::gobject_ffi::g_object_new(
            flutter_input_method_context_get_type(),
            std::ptr::null::<c_char>(),
        )
    };
    if object.is_null() {
        return Err(-11);
    }
    let adapter = unsafe { &mut *object.cast::<FlutterInputMethodContext>() };
    adapter.owner = Box::into_raw(Box::new(native_view));
    Ok(unsafe { from_glib_full(object) })
}

/// Applies an operation to the Flutter input-method adapter installed on a
/// live WebView. The runtime's strong reference keeps the context valid for
/// the complete duration of the closure.
fn with_input_method_context(
    handle: u64,
    operation: impl FnOnce(*mut WebKitInputMethodContext),
) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -2;
    };
    let context =
        ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.input_method_context).0
            as *mut WebKitInputMethodContext;
    if context.is_null() {
        return -3;
    }
    operation(context);
    0
}

/// Returns the newest complete editable-element snapshot generation.
#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_input_method_generation(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| {
        view.metrics.input_method_generation.load(Ordering::Acquire)
    })
}

#[unsafe(no_mangle)]
/// Returns one while WebKit has an editable element focused.
pub extern "C" fn webview_flutter_linux_wpe_input_method_focused(handle: u64) -> i32 {
    native_view(handle).map_or(-1, |view| i32::from(view.input_method.borrow().focused))
}

#[unsafe(no_mangle)]
/// Returns the UTF-8 byte length of the latest surrounding text.
pub extern "C" fn webview_flutter_linux_wpe_input_method_text_length(handle: u64) -> usize {
    native_view(handle).map_or(0, |view| view.input_method.borrow().text.len())
}

#[unsafe(no_mangle)]
/// Copies the latest surrounding text into caller-owned storage.
///
/// Returns the byte count, `-1` for a null destination, `-2` for an invalid
/// handle, and `-3` when the destination is too small.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes. The pointer
/// is never retained after this call.
pub unsafe extern "C" fn webview_flutter_linux_wpe_input_method_copy_text(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    let Some(native_view) = native_view(handle) else {
        return -2;
    };
    let state = native_view.input_method.borrow();
    if destination_length < state.text.len() || state.text.len() > i32::MAX as usize {
        return -3;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(state.text.as_ptr(), destination, state.text.len());
    }
    state.text.len() as i32
}

macro_rules! input_method_scalar {
    ($name:ident, $return_type:ty, $fallback:expr, $field:ident) => {
        #[unsafe(no_mangle)]
        pub extern "C" fn $name(handle: u64) -> $return_type {
            native_view(handle).map_or($fallback, |view| view.input_method.borrow().$field)
        }
    };
}

input_method_scalar!(
    webview_flutter_linux_wpe_input_method_cursor_index,
    u32,
    0,
    cursor_index
);
input_method_scalar!(
    webview_flutter_linux_wpe_input_method_selection_index,
    u32,
    0,
    selection_index
);
input_method_scalar!(
    webview_flutter_linux_wpe_input_method_cursor_x,
    i32,
    0,
    cursor_x
);
input_method_scalar!(
    webview_flutter_linux_wpe_input_method_cursor_y,
    i32,
    0,
    cursor_y
);
input_method_scalar!(
    webview_flutter_linux_wpe_input_method_cursor_width,
    i32,
    0,
    cursor_width
);
input_method_scalar!(
    webview_flutter_linux_wpe_input_method_cursor_height,
    i32,
    0,
    cursor_height
);
input_method_scalar!(
    webview_flutter_linux_wpe_input_method_purpose,
    i32,
    0,
    input_purpose
);
input_method_scalar!(
    webview_flutter_linux_wpe_input_method_hints,
    u32,
    0,
    input_hints
);

#[unsafe(no_mangle)]
/// Replaces WebKit's visible preedit string and cursor.
///
/// `cursor_offset` is measured in Unicode scalar values within `text`.
/// Starting the first non-final update emits `preedit-started`; every update
/// emits `preedit-changed`, causing WebKit to call the adapter's `get_preedit`
/// virtual method.
///
/// # Safety
///
/// `text` must point to a readable NUL-terminated UTF-8 string for this call.
pub unsafe extern "C" fn webview_flutter_linux_wpe_input_method_set_preedit(
    handle: u64,
    text: *const c_char,
    cursor_offset: u32,
) -> i32 {
    let text = match required_c_string(text) {
        Ok(text) => text,
        Err(status) => return status,
    };
    let text = match std::ffi::CString::new(text) {
        Ok(text) => text,
        Err(_) => return -2,
    };
    with_input_method_context(handle, |context| {
        let adapter = unsafe { flutter_input_method_context(context) };
        if !adapter.preedit_text.is_null() {
            unsafe { glib::ffi::g_free(adapter.preedit_text.cast()) };
        }
        adapter.preedit_text = unsafe { glib::ffi::g_strdup(text.as_ptr()) };
        adapter.preedit_cursor_offset = cursor_offset;
        let was_active = adapter.preedit_active != 0;
        adapter.preedit_active = 1;
        if !was_active {
            unsafe {
                glib::gobject_ffi::g_signal_emit_by_name(
                    context.cast(),
                    c"preedit-started".as_ptr(),
                );
            }
        }
        unsafe {
            glib::gobject_ffi::g_signal_emit_by_name(context.cast(), c"preedit-changed".as_ptr());
        }
    })
}

#[unsafe(no_mangle)]
/// Commits a completed input-method sequence into WebKit's active editor.
///
/// An active preedit remains identifiable while the commit signal runs, then
/// receives an empty preedit update and `preedit-finished`. This matches the
/// ordering accepted from desktop IM contexts.
///
/// # Safety
///
/// `text` must point to a readable NUL-terminated UTF-8 string for this call.
pub unsafe extern "C" fn webview_flutter_linux_wpe_input_method_commit(
    handle: u64,
    text: *const c_char,
) -> i32 {
    let text = match required_c_string(text) {
        Ok(text) => text,
        Err(status) => return status,
    };
    let text = match std::ffi::CString::new(text) {
        Ok(text) => text,
        Err(_) => return -2,
    };
    with_input_method_context(handle, |context| {
        let adapter = unsafe { flutter_input_method_context(context) };
        unsafe {
            glib::gobject_ffi::g_signal_emit_by_name(
                context.cast(),
                c"committed".as_ptr(),
                text.as_ptr(),
            );
        }
        if adapter.preedit_active != 0 {
            if !adapter.preedit_text.is_null() {
                unsafe { glib::ffi::g_free(adapter.preedit_text.cast()) };
            }
            adapter.preedit_text = unsafe { glib::ffi::g_strdup(c"".as_ptr()) };
            adapter.preedit_cursor_offset = 0;
            adapter.preedit_active = 0;
            unsafe {
                glib::gobject_ffi::g_signal_emit_by_name(
                    context.cast(),
                    c"preedit-changed".as_ptr(),
                );
                glib::gobject_ffi::g_signal_emit_by_name(
                    context.cast(),
                    c"preedit-finished".as_ptr(),
                );
            }
        }
    })
}

#[unsafe(no_mangle)]
/// Cancels the current composition without inserting text.
pub extern "C" fn webview_flutter_linux_wpe_input_method_cancel_preedit(handle: u64) -> i32 {
    with_input_method_context(handle, |context| {
        let adapter = unsafe { flutter_input_method_context(context) };
        if adapter.preedit_active == 0 {
            return;
        }
        if !adapter.preedit_text.is_null() {
            unsafe { glib::ffi::g_free(adapter.preedit_text.cast()) };
        }
        adapter.preedit_text = unsafe { glib::ffi::g_strdup(c"".as_ptr()) };
        adapter.preedit_cursor_offset = 0;
        adapter.preedit_active = 0;
        unsafe {
            glib::gobject_ffi::g_signal_emit_by_name(context.cast(), c"preedit-changed".as_ptr());
            glib::gobject_ffi::g_signal_emit_by_name(context.cast(), c"preedit-finished".as_ptr());
        }
    })
}

#[unsafe(no_mangle)]
/// Requests deletion relative to WebKit's active editor cursor.
///
/// Both values are Unicode character counts, not UTF-8 byte offsets. Negative
/// offsets address text before the cursor.
pub extern "C" fn webview_flutter_linux_wpe_input_method_delete_surrounding(
    handle: u64,
    offset: i32,
    character_count: u32,
) -> i32 {
    with_input_method_context(handle, |context| unsafe {
        glib::gobject_ffi::g_signal_emit_by_name(
            context.cast(),
            c"delete-surrounding".as_ptr(),
            offset,
            character_count,
        );
    })
}

#[unsafe(no_mangle)]
/// Sends focus-in or focus-out to the WPE view for this handle.
pub extern "C" fn webview_flutter_linux_wpe_set_focus(handle: u64, focused: i32) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -1;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -2;
    };
    let context =
        ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.input_method_context).0
            as *mut WebKitInputMethodContext;
    if context.is_null() {
        return -3;
    }
    unsafe {
        if focused != 0 {
            webkit_input_method_context_notify_focus_in(context);
            wpe_view_focus_in(runtime.view);
        } else {
            webkit_input_method_context_notify_focus_out(context);
            wpe_view_focus_out(runtime.view);
        }
    }
    0
}
