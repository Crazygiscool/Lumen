// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Cursor callbacks, snapshots, and C ABI for headless WPE views.
//!
//! WPE's headless backend has no toolkit cursor implementation. This module
//! installs the missing class callbacks once, maps callback-scoped view
//! pointers back to weak native owners, and copies bounded cursor data for Dart.

use std::sync::OnceLock;

use super::prelude::*;

pub(super) const MAX_CURSOR_DIMENSION: u32 = 512;
const MAX_CURSOR_NAME_BYTES: usize = 128;
const MAX_CURSOR_BYTES: usize = 4 * 1024 * 1024;
const CURSOR_KIND_NAMED: u32 = 1;
const CURSOR_KIND_CUSTOM: u32 = 2;

thread_local! {
    // Cursor callbacks receive a WPEView pointer rather than our public handle.
    // Weak values preserve that callback lookup without extending browser
    // lifetime or exposing the pointer through Dart.
    static CURSOR_VIEWS: RefCell<HashMap<usize, Weak<NativeView>>> = RefCell::new(HashMap::new());
}

/// Cursor resolved by WebKit for the content currently below the pointer.
///
/// Named cursors use the WPE/Wayland cursor vocabulary. Custom cursors retain
/// tightly packed premultiplied ARGB8888 pixels; on the supported little-endian
/// Linux target those bytes are BGRA in memory and can be decoded directly by
/// Flutter's `PixelFormat.bgra8888` path.
#[derive(Clone, PartialEq)]
pub(super) enum CursorData {
    Named(Vec<u8>),
    Custom {
        width: u32,
        height: u32,
        hotspot_x: u32,
        hotspot_y: u32,
        pixels: Vec<u8>,
    },
}

/// Latest complete cursor state copied out of WPE-owned memory.
///
/// Generation changes only for an effective cursor change, which lets Dart
/// avoid allocating names or pixel buffers on every 16 ms browser pump.
pub(super) struct CursorSnapshot {
    pub(super) generation: u64,
    data: CursorData,
}

impl Default for CursorSnapshot {
    fn default() -> Self {
        Self {
            generation: 1,
            data: CursorData::Named(b"default".to_vec()),
        }
    }
}

impl CursorSnapshot {
    /// Replaces the snapshot only when WebKit resolved a different cursor.
    pub(super) fn update(&mut self, data: CursorData) -> bool {
        if self.data == data {
            return false;
        }
        self.data = data;
        self.generation = self.generation.wrapping_add(1).max(1);
        true
    }
}

// Retaining the class reference for the process lifetime is intentional. A
// GObject class vtable is shared by every instance of that final type, and
// releasing our only explicit reference after replacing its cursor slots would
// permit class finalization to discard the installed callbacks.
static HEADLESS_VIEW_CLASS: OnceLock<usize> = OnceLock::new();

/// Installs the cursor vfuncs omitted by WPE's headless view implementation.
///
/// The hook is process-wide because GObject classes are process-wide, while
/// [`CURSOR_VIEWS`] makes delivery opt-in per view. Consequently an unrelated
/// headless WPE view in the same process still reaches these callbacks but is
/// ignored unless this library registered its exact instance pointer.
pub(super) fn install_headless_cursor_callbacks() -> Result<(), i32> {
    let class_address = *HEADLESS_VIEW_CLASS.get_or_init(|| unsafe {
        let view_type = wpe_view_headless_get_type();
        if view_type == 0 {
            return 0;
        }
        let class = glib::gobject_ffi::g_type_class_ref(view_type).cast::<WpeViewClass>();
        if class.is_null() {
            return 0;
        }
        // WPEViewHeadless is final and its class initializer leaves these two
        // slots null. We intentionally do not chain because there is no cursor
        // implementation to preserve in the headless backend.
        (*class).set_cursor_from_name = Some(headless_cursor_from_name);
        (*class).set_cursor_from_bytes = Some(headless_cursor_from_bytes);
        class as usize
    });
    if class_address == 0 { Err(-11) } else { Ok(()) }
}

/// Registers one live WPE instance for cursor callbacks after its strong
/// browser owner has been installed in [`NativeView::runtime`].
pub(super) fn register_cursor_view(view: *mut WpeView, native_view: &Rc<NativeView>) {
    if view.is_null() {
        return;
    }
    CURSOR_VIEWS.with_borrow_mut(|views| {
        views.insert(view as usize, Rc::downgrade(native_view));
    });
}

/// Removes the pointer lookup before the WPE object can be finalized or its
/// address reused by a later browser.
pub(super) fn unregister_cursor_view(view: *mut WpeView) {
    if view.is_null() {
        return;
    }
    CURSOR_VIEWS.with_borrow_mut(|views| {
        views.remove(&(view as usize));
    });
}

/// Resolves a callback-scoped WPE pointer without holding the registry borrow
/// while cursor state is updated. Stale weak entries are removed defensively.
fn cursor_native_view(view: *mut WpeView) -> Option<Rc<NativeView>> {
    if view.is_null() {
        return None;
    }
    let key = view as usize;
    let native_view = CURSOR_VIEWS.with_borrow(|views| views.get(&key).and_then(Weak::upgrade));
    if native_view.is_none() {
        CURSOR_VIEWS.with_borrow_mut(|views| {
            views.remove(&key);
        });
    }
    native_view
}

/// Publishes an effective cursor change without panicking on a re-entrant WPE
/// callback. A skipped update is preferable to unwinding across the C ABI.
fn update_cursor(native_view: &NativeView, data: CursorData) {
    let Ok(mut cursor) = native_view.cursor.try_borrow_mut() else {
        return;
    };
    cursor.update(data);
}

/// Copies a possibly padded ARGB8888 cursor into tightly packed rows.
///
/// Bounds are deliberately independent from page content: malformed or
/// unexpectedly large custom cursor images cannot force unbounded FFI copies.
pub(super) fn custom_cursor_data(
    bytes: &[u8],
    width: u32,
    height: u32,
    stride: u32,
    hotspot_x: u32,
    hotspot_y: u32,
) -> Option<CursorData> {
    if width == 0
        || height == 0
        || width > MAX_CURSOR_DIMENSION
        || height > MAX_CURSOR_DIMENSION
        || hotspot_x >= width
        || hotspot_y >= height
    {
        return None;
    }
    let packed_stride = (width as usize).checked_mul(4)?;
    let source_stride = stride as usize;
    if source_stride < packed_stride {
        return None;
    }
    let required_source = (height as usize)
        .checked_sub(1)?
        .checked_mul(source_stride)?
        .checked_add(packed_stride)?;
    let packed_length = (height as usize).checked_mul(packed_stride)?;
    if required_source > bytes.len() || packed_length > MAX_CURSOR_BYTES {
        return None;
    }
    let mut pixels = Vec::with_capacity(packed_length);
    for row in 0..height as usize {
        let start = row.checked_mul(source_stride)?;
        let end = start.checked_add(packed_stride)?;
        pixels.extend_from_slice(bytes.get(start..end)?);
    }
    Some(CursorData::Custom {
        width,
        height,
        hotspot_x,
        hotspot_y,
        pixels,
    })
}

/// Receives WebKit's resolved platform cursor name from the headless view.
///
/// # Safety
///
/// WPE guarantees `view` is the live instance invoking its class vfunc and
/// `name` is a readable NUL-terminated string for the duration of this call.
unsafe extern "C" fn headless_cursor_from_name(view: *mut WpeView, name: *const c_char) {
    if name.is_null() {
        return;
    }
    let Some(native_view) = cursor_native_view(view) else {
        return;
    };
    let bytes = unsafe { CStr::from_ptr(name) }.to_bytes();
    let bounded_length = bytes.len().min(MAX_CURSOR_NAME_BYTES);
    update_cursor(
        &native_view,
        CursorData::Named(bytes[..bounded_length].to_vec()),
    );
}

/// Receives and copies WebKit's custom ARGB8888 cursor before its `GBytes`
/// owner leaves the callback.
///
/// # Safety
///
/// WPE guarantees all pointers and dimensions satisfy the public
/// `set_cursor_from_bytes` vfunc contract for the duration of this call.
unsafe extern "C" fn headless_cursor_from_bytes(
    view: *mut WpeView,
    bytes: *mut glib::ffi::GBytes,
    width: u32,
    height: u32,
    stride: u32,
    hotspot_x: u32,
    hotspot_y: u32,
) {
    if bytes.is_null() {
        return;
    }
    let Some(native_view) = cursor_native_view(view) else {
        return;
    };
    let mut byte_length = 0;
    let data = unsafe { glib::ffi::g_bytes_get_data(bytes, &mut byte_length) }.cast::<u8>();
    if data.is_null() || byte_length == 0 || byte_length > MAX_CURSOR_BYTES {
        // Some Skia-backed WPE releases invoke this vfunc with an empty
        // pixmap when their cursor image is GPU-backed. Do not retain whatever
        // cursor happened to precede it: that could leave the pointer hidden
        // or display an unrelated resize/text shape over the new element.
        update_cursor(&native_view, CursorData::Named(b"default".to_vec()));
        return;
    }
    let source = unsafe { std::slice::from_raw_parts(data, byte_length) };
    let cursor = custom_cursor_data(source, width, height, stride, hotspot_x, hotspot_y)
        .unwrap_or_else(|| CursorData::Named(b"default".to_vec()));
    update_cursor(&native_view, cursor);
}

/// Resolves the latest immutable cursor snapshot for one public view handle.
fn with_cursor<T: Copy>(
    handle: u64,
    fallback: T,
    operation: impl FnOnce(&CursorSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    operation(&native_view.cursor.borrow())
}

#[unsafe(no_mangle)]
/// Returns the generation of WebKit's latest effective cursor change.
pub extern "C" fn webview_flutter_linux_wpe_cursor_generation(handle: u64) -> u64 {
    with_cursor(handle, 0, |cursor| cursor.generation)
}

#[unsafe(no_mangle)]
/// Returns `1` for a named cursor, `2` for a custom cursor, or zero when the
/// handle is invalid.
pub extern "C" fn webview_flutter_linux_wpe_cursor_kind(handle: u64) -> u32 {
    with_cursor(handle, 0, |cursor| match &cursor.data {
        CursorData::Named(_) => CURSOR_KIND_NAMED,
        CursorData::Custom { .. } => CURSOR_KIND_CUSTOM,
    })
}

#[unsafe(no_mangle)]
/// Returns the byte length of the current WPE cursor name, or zero for custom
/// cursors and invalid handles.
pub extern "C" fn webview_flutter_linux_wpe_cursor_name_length(handle: u64) -> usize {
    with_cursor(handle, 0, |cursor| match &cursor.data {
        CursorData::Named(name) => name.len(),
        CursorData::Custom { .. } => 0,
    })
}

#[unsafe(no_mangle)]
/// Copies the current WPE cursor name into caller-owned storage.
///
/// Returns the byte count, `-1` for a null destination, `-2` for an invalid
/// handle, `-3` when the current cursor is custom, and `-4` when the destination
/// is too small.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes and remains
/// owned by the caller.
pub unsafe extern "C" fn webview_flutter_linux_wpe_cursor_copy_name(
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
    let cursor = native_view.cursor.borrow();
    let CursorData::Named(name) = &cursor.data else {
        return -3;
    };
    if destination_length < name.len() || name.len() > i32::MAX as usize {
        return -4;
    }
    unsafe { std::ptr::copy_nonoverlapping(name.as_ptr(), destination, name.len()) };
    name.len() as i32
}

macro_rules! custom_cursor_scalar {
    ($name:ident, $field:ident) => {
        #[unsafe(no_mangle)]
        pub extern "C" fn $name(handle: u64) -> u32 {
            with_cursor(handle, 0, |cursor| match &cursor.data {
                CursorData::Custom { $field, .. } => *$field,
                CursorData::Named(_) => 0,
            })
        }
    };
}

custom_cursor_scalar!(webview_flutter_linux_wpe_cursor_width, width);
custom_cursor_scalar!(webview_flutter_linux_wpe_cursor_height, height);
custom_cursor_scalar!(webview_flutter_linux_wpe_cursor_hotspot_x, hotspot_x);
custom_cursor_scalar!(webview_flutter_linux_wpe_cursor_hotspot_y, hotspot_y);

#[unsafe(no_mangle)]
/// Returns the tightly packed custom cursor byte length, or zero for a named
/// cursor and invalid handles.
pub extern "C" fn webview_flutter_linux_wpe_cursor_pixels_length(handle: u64) -> usize {
    with_cursor(handle, 0, |cursor| match &cursor.data {
        CursorData::Custom { pixels, .. } => pixels.len(),
        CursorData::Named(_) => 0,
    })
}

#[unsafe(no_mangle)]
/// Copies the current tightly packed custom cursor pixels.
///
/// Returns the byte count, `-1` for a null destination, `-2` for an invalid
/// handle, `-3` when the current cursor is named, and `-4` when the destination
/// is too small.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes and remains
/// owned by the caller.
pub unsafe extern "C" fn webview_flutter_linux_wpe_cursor_copy_pixels(
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
    let cursor = native_view.cursor.borrow();
    let CursorData::Custom { pixels, .. } = &cursor.data else {
        return -3;
    };
    if destination_length < pixels.len() || pixels.len() > i32::MAX as usize {
        return -4;
    }
    unsafe { std::ptr::copy_nonoverlapping(pixels.as_ptr(), destination, pixels.len()) };
    pixels.len() as i32
}
