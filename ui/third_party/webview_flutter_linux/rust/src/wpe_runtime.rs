// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! WPE WebKit runtime and C ABI for individual Linux WebViews.
//!
//! Each successful [`webview_flutter_linux_view_create`] call inserts one
//! [`NativeView`] into the platform thread's `VIEWS` registry and returns a
//! monotonically increasing, non-zero handle. Every later FFI function resolves
//! that handle rather than dereferencing a Dart-owned pointer. Disposing a view
//! removes it from the registry first, making stale or repeated calls fail
//! without accessing released browser state.
//!
//! ## Module layout
//!
//! Shared ownership and handle lookup live in `state`; `construction` builds
//! fully connected WebKit/WPE objects; `lifecycle` owns the public create and
//! dispose ABI; `surface` handles geometry and borrowed view access; and
//! `ffi_helpers` contains the small foreign-value copy routines. The remaining
//! modules each own one browser capability and its Dart-facing ABI.
//!
//! ## Thread affinity and callbacks
//!
//! GLib, WebKit, and WPE objects are not `Send`. The registry is therefore
//! thread-local and all Dart calls must originate from Flutter's Linux platform
//! thread. Signal closures capture `Weak<NativeView>` references: they cannot
//! keep a disposed browser alive, and they can detect teardown before touching
//! texture or menu state. Only [`crate::linux_texture::TextureState`] crosses
//! to Flutter's raster thread through `Arc`, atomics, and mutexes.
//!
//! ## Buffer lifetime
//!
//! WPE owns every `WpeBuffer` and its DMA-BUF file descriptors. During
//! `buffer-rendered`, this module waits for WPE's rendering fence, synchronously
//! copies the borrowed planes into an application-owned GL ring, then calls
//! `wpe_view_buffer_released` exactly once. No buffer pointer or borrowed file
//! descriptor is retained after the callback.
//!
//! ## Return values
//!
//! Commands return `0` on success. Negative values identify invalid arguments,
//! invalid handles, unavailable native objects, or lower-level WPE/texture
//! failures. Accessors return zero (or `-1` where negative is representable)
//! when a handle or requested value is unavailable. The Dart wrapper converts
//! command failures into `StateError`s.

mod accessibility;
mod accessibility_dbus;
mod accessibility_worker;
mod clipboard;
mod construction;
mod cursor;
mod downloads;
mod ffi_helpers;
mod geolocation;
mod input;
mod javascript;
mod lifecycle;
mod menus;
mod native_ffi;
mod navigation;
mod notifications;
mod prelude;
mod rendering;
mod requests;
mod session;
mod settings;
mod state;
mod storage;
mod surface;
mod text_input;
mod web_process_extension;
mod windows;

#[cfg(test)]
mod tests;
