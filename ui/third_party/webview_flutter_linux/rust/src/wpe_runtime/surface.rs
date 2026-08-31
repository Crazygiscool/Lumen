// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! WPE surface geometry and borrowed native-view access helpers.

use super::prelude::*;

pub(super) fn valid_surface_geometry(width: u32, height: u32, scale: f64) -> bool {
    width != 0
        && height != 0
        && width <= 16_384
        && height <= 16_384
        && scale.is_finite()
        && (0.05..=20.0).contains(&scale)
        && (width as f64 * scale).ceil() <= 16_384.0
        && (height as f64 * scale).ceil() <= 16_384.0
}

#[unsafe(no_mangle)]
/// Updates the WPE toplevel's logical size and Flutter display scale.
///
/// WPE multiplies the logical dimensions by `scale` when allocating its render
/// buffer. Keeping those values separate gives CSS the same viewport and
/// `devicePixelRatio` that Flutter exposes while the texture remains sharp on
/// HiDPI displays. The resulting physical dimensions may not exceed 16384.
pub extern "C" fn webview_flutter_linux_wpe_resize(
    handle: u64,
    width: u32,
    height: u32,
    scale: f64,
) -> i32 {
    if !valid_surface_geometry(width, height, scale) {
        return -1;
    }
    let Some(native_view) = native_view(handle) else {
        return -3;
    };
    {
        let runtime = native_view.runtime.borrow();
        let Some(runtime) = runtime.as_ref() else {
            return -3;
        };
        // SAFETY: `toplevel` is a transfer-none child of the live WebView. The
        // headless implementation has no native screen that could publish a
        // scale, so this embedder supplies Flutter's value directly through
        // the platform notification API.
        let mut current_width = 0;
        let mut current_height = 0;
        unsafe { wpe_toplevel_get_size(runtime.toplevel, &mut current_width, &mut current_height) };
        if current_width != width as i32 || current_height != height as i32 {
            let resized =
                unsafe { wpe_toplevel_resize(runtime.toplevel, width as i32, height as i32) };
            if resized == 0 {
                return -4;
            }
        }
        let current_scale = unsafe { wpe_toplevel_get_scale(runtime.toplevel) };
        if (current_scale - scale).abs() > f64::EPSILON {
            unsafe { wpe_toplevel_scale_changed(runtime.toplevel, scale) };
        }
        0
    }
}

/// Runs a synchronous operation with a transfer-none WebKit view pointer.
///
/// The runtime borrow and strong `Rc` remain live for the complete operation,
/// preventing disposal from invalidating the pointer during re-entrant code.
pub(super) fn with_webview(handle: u64, operation: impl FnOnce(*mut WebKitWebView)) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -3;
    };
    let runtime = native_view.runtime.borrow();
    let Some(runtime) = runtime.as_ref() else {
        return -3;
    };
    let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
        as *mut WebKitWebView;
    operation(webview);
    0
}

/// Runs a synchronous operation with a transfer-none WPE view pointer.
///
/// The runtime borrow and strong `Rc` remain live for the complete operation,
/// preventing disposal from invalidating the pointer during re-entrant code.
pub(super) fn with_view(handle: u64, operation: impl FnOnce(*mut WpeView)) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -3;
    };
    {
        let runtime = native_view.runtime.borrow();
        let Some(runtime) = runtime.as_ref() else {
            return -3;
        };
        operation(runtime.view);
        0
    }
}
