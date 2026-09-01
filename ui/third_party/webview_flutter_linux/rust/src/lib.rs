// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Native half of `webview_flutter_linux`.
//!
//! The library deliberately exposes a small C ABI rather than binding Dart to
//! Rust types. Dart creates a view through
//! `webview_flutter_linux_view_create`, retains the returned integer handle,
//! and supplies that handle to every later operation. The WPE module owns the
//! handle registry and the browser objects; the texture module owns the
//! Irondash registration and all EGL/GL state associated with a view.
//!
//! ## Threading model
//!
//! WPE and GLib objects are thread-affine and stay on Flutter's Linux platform
//! thread. Irondash asks for texture payloads on Flutter's raster thread, so
//! only the texture provider and its atomics/mutex-protected GL state cross the
//! thread boundary. Browser objects are never marked `Send` or `Sync`.
//!
//! ## ABI conventions
//!
//! Mutating functions return `0` on success and a negative status on failure.
//! Read-only accessors use zero as the invalid-handle/default value. Any ABI
//! shape change must increment `API_VERSION` and be mirrored in
//! `lib/src/native_frame_bindings.dart`.

use std::f32::consts::TAU;

#[cfg(target_os = "linux")]
mod linux_texture;
#[cfg(all(target_os = "linux", feature = "wpe-runtime"))]
mod system_clipboard;
#[cfg(all(target_os = "linux", feature = "wpe-runtime"))]
mod wpe_runtime;

const API_VERSION: u32 = 29;
/// Initial texture width used before WPE supplies its first buffer.
pub(crate) const WIDTH: usize = 800;
/// Initial texture height used before WPE supplies its first buffer.
pub(crate) const HEIGHT: usize = 450;
const BYTES_PER_PIXEL: usize = 4;
const MAX_DYNAMIC_FRAME_BYTE_LENGTH: usize = 512 * 1024 * 1024;

#[unsafe(no_mangle)]
/// Returns the native ABI version expected by the Dart bindings.
///
/// This call is handle-independent so Dart can reject an incompatible library
/// before allocating browser or graphics resources.
pub extern "C" fn webview_flutter_linux_api_version() -> u32 {
    API_VERSION
}

/// Calculates the byte length of an RGBA frame without integer overflow.
///
/// Zero-sized frames and allocations above 512 MiB are rejected. The same
/// guard protects initial fallback frames and later WPE-driven resizes.
pub(crate) fn checked_dynamic_frame_byte_length(width: u32, height: u32) -> Option<usize> {
    let width = usize::try_from(width).ok()?;
    let height = usize::try_from(height).ok()?;
    if width == 0 || height == 0 {
        return None;
    }
    let length = width.checked_mul(height)?.checked_mul(BYTES_PER_PIXEL)?;
    (length <= MAX_DYNAMIC_FRAME_BYTE_LENGTH).then_some(length)
}

/// Renders the deterministic placeholder shown until the first WPE DMA-BUF is
/// imported.
///
/// `pixels` must contain at least `width * height * 4` bytes. Callers establish
/// that invariant with [`checked_dynamic_frame_byte_length`] before invoking
/// this function. Once a browser frame is imported, the GL ring stops using
/// this CPU-generated diagnostic image.
pub(crate) fn render_flutter_texture_test_frame(
    pixels: &mut [u8],
    width: usize,
    height: usize,
    generation: u64,
) {
    let accent = (generation % 96) as u8;
    for y in 0..height {
        for x in 0..width {
            let offset = (y * width + x) * BYTES_PER_PIXEL;
            let grid = x % 32 == 0 || y % 32 == 0;
            let checker = ((x / 32) + (y / 32)) % 2 == 0;
            let diagonal = x * height / width.max(1) == y;
            let rgba = if diagonal {
                [255, 205, 92, 255]
            } else if grid {
                [69, 220, 185, 255]
            } else if checker {
                [27, 34 + accent / 3, 57 + accent / 2, 255]
            } else {
                [18, 23, 39 + accent / 4, 255]
            };
            pixels[offset..offset + BYTES_PER_PIXEL].copy_from_slice(&rgba);
        }
    }

    let radius = width.min(height) as f32 * 0.16;
    let center_x = width as f32 * 0.72;
    let center_y = height as f32 * 0.48;
    let phase = generation as f32 * 0.035;
    for step in 0..180 {
        let angle = step as f32 / 180.0 * TAU + phase;
        let x = (center_x + angle.cos() * radius) as isize;
        let y = (center_y + angle.sin() * radius) as isize;
        if x < 0 || y < 0 || x >= width as isize || y >= height as isize {
            continue;
        }
        let offset = (y as usize * width + x as usize) * BYTES_PER_PIXEL;
        pixels[offset..offset + BYTES_PER_PIXEL].copy_from_slice(&[255, 118, 97, 255]);
    }
}
