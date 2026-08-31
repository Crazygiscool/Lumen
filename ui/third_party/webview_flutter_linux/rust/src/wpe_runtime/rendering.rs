// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! WPE frame transport, Irondash texture accessors, and render diagnostics.
//!
//! Callback-scoped DMA-BUF planes are copied synchronously into the
//! application-owned GL ring before WPE is told that it may reuse the buffer.

use std::{
    os::fd::{FromRawFd, OwnedFd},
    sync::atomic::{AtomicU32, AtomicU64},
};

use super::prelude::*;

const MAX_PLANES: usize = 4;
const RENDER_FENCE_TIMEOUT_MS: i32 = 100;

#[derive(Default)]
/// Per-view counters and latest-frame metadata exposed by diagnostic accessors.
///
/// Atomics let callbacks publish scalar state without retaining a borrow of the
/// thread-local handle registry across a WPE or texture operation.
pub(super) struct WpeMetrics {
    pub(super) frame_generation: AtomicU64,
    pub(super) paint_count: AtomicU64,
    pub(super) valid_paint_count: AtomicU64,
    pub(super) plane_count: AtomicU32,
    pub(super) format: AtomicU32,
    pub(super) modifier: AtomicU64,
    pub(super) width: AtomicU32,
    pub(super) height: AtomicU32,
    pub(super) first_plane_stride: AtomicU32,
    pub(super) context_menu_generation: AtomicU64,
    pub(super) option_menu_generation: AtomicU64,
    pub(super) input_method_generation: AtomicU64,
}

/// Connects WPE's `buffer-rendered` signal to the per-view texture transport.
///
/// Every callback releases the WPE buffer exactly once, including callbacks
/// that race with view disposal or receive unsupported buffer types. Supported
/// DMA-BUFs are copied synchronously before release.
pub(super) fn connect_buffer_rendered(view: *mut WpeView, native_view: Weak<NativeView>) {
    // SAFETY: view is a transfer-none GObject kept alive by the WebView.
    let view_object: glib::Object = unsafe { glib::translate::from_glib_none(view.cast()) };
    // SAFETY: The WPE type function returns a registered GType.
    let dma_buf_type = unsafe { glib::Type::from_glib(wpe_buffer_dma_buf_get_type()) };
    let raw_view = view as usize;
    view_object.connect_closure(
        "buffer-rendered",
        false,
        glib::closure_local!(move |_view: glib::Object, buffer: glib::Object| {
            let raw_buffer = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&buffer).0
                as *mut WpeBuffer;
            let view = raw_view as *mut WpeView;
            let Some(native_view) = native_view.upgrade() else {
                unsafe { wpe_view_buffer_released(view, raw_buffer) };
                return;
            };
            native_view
                .metrics
                .paint_count
                .fetch_add(1, Ordering::AcqRel);
            if buffer.type_().is_a(dma_buf_type) {
                // The callback owns the buffer until it explicitly releases it.
                // Import and complete the GPU copy synchronously in that window.
                let status = unsafe { copy_rendered_dma_buf(&native_view, raw_buffer) };
                if status == 0 {
                    native_view
                        .metrics
                        .valid_paint_count
                        .fetch_add(1, Ordering::AcqRel);
                    native_view.texture.mark_frame_available();
                }
            }
            // SAFETY: WPE emitted this buffer for this view; every callback path
            // releases it exactly once after any borrowed-fd work is complete.
            unsafe { wpe_view_buffer_released(view, raw_buffer) };
        }),
    );
}

/// Converts one callback-scoped WPE DMA-BUF into
/// [`DmaBufFrame`](crate::linux_texture::DmaBufFrame) metadata and forwards it
/// to the owning texture state.
///
/// The rendering fence is consumed and waited for before plane metadata is
/// read. This prevents EGL from importing producer-incomplete content.
///
/// # Safety
///
/// `buffer` must be a live `WpeBufferDmaBuf` emitted for `native_view` and must
/// remain owned by WPE for this call. The caller is responsible for invoking
/// `wpe_view_buffer_released` after this function returns.
unsafe fn copy_rendered_dma_buf(native_view: &NativeView, buffer: *mut WpeBuffer) -> i32 {
    let dma_buf = buffer.cast::<WpeBufferDmaBuf>();
    let width = unsafe { wpe_buffer_get_width(buffer) };
    let height = unsafe { wpe_buffer_get_height(buffer) };
    let plane_count = unsafe { wpe_buffer_dma_buf_get_n_planes(dma_buf) };
    if width <= 0 || height <= 0 || plane_count == 0 || plane_count as usize > MAX_PLANES {
        return -20;
    }

    let rendering_fence = unsafe { wpe_buffer_take_rendering_fence(buffer) };
    if rendering_fence >= 0 {
        // SAFETY: take_rendering_fence transfers ownership to the caller.
        let owned_fence = unsafe { OwnedFd::from_raw_fd(rendering_fence) };
        let mut poll_fd = libc::pollfd {
            fd: rendering_fence,
            events: libc::POLLIN,
            revents: 0,
        };
        // A sync_file becomes readable when the producer's rendering completes.
        let poll_status = unsafe { libc::poll(&mut poll_fd, 1, RENDER_FENCE_TIMEOUT_MS) };
        drop(owned_fence);
        if poll_status <= 0 {
            return -21;
        }
    }

    let generation = native_view
        .metrics
        .frame_generation
        .fetch_add(1, Ordering::AcqRel)
        .wrapping_add(1)
        .max(1);
    let mut frame = crate::linux_texture::DmaBufFrame {
        generation,
        plane_count,
        fds: [-1; MAX_PLANES],
        strides: [0; MAX_PLANES],
        offsets: [0; MAX_PLANES],
        modifier: unsafe { wpe_buffer_dma_buf_get_modifier(dma_buf) },
        format: unsafe { wpe_buffer_dma_buf_get_format(dma_buf) },
        coded_width: width,
        coded_height: height,
        visible_x: 0,
        visible_y: 0,
        visible_width: width,
        visible_height: height,
    };
    for plane in 0..plane_count {
        let index = plane as usize;
        frame.fds[index] = unsafe { wpe_buffer_dma_buf_get_fd(dma_buf, plane) };
        frame.offsets[index] = u64::from(unsafe { wpe_buffer_dma_buf_get_offset(dma_buf, plane) });
        frame.strides[index] = unsafe { wpe_buffer_dma_buf_get_stride(dma_buf, plane) };
        if frame.fds[index] < 0 || frame.strides[index] == 0 {
            return -22;
        }
    }

    native_view
        .metrics
        .plane_count
        .store(plane_count, Ordering::Release);
    native_view
        .metrics
        .format
        .store(frame.format, Ordering::Release);
    native_view
        .metrics
        .modifier
        .store(frame.modifier, Ordering::Release);
    native_view
        .metrics
        .width
        .store(width as u32, Ordering::Release);
    native_view
        .metrics
        .height
        .store(height as u32, Ordering::Release);
    native_view
        .metrics
        .first_plane_stride
        .store(frame.strides[0], Ordering::Release);

    let resize_status = native_view.texture.resize(width as u32, height as u32);
    if resize_status != 0 {
        return resize_status;
    }
    native_view.texture.copy_dma_buf(&frame)
}

#[unsafe(no_mangle)]
/// Returns the Flutter texture ID for `handle`, or zero if it is invalid.
pub extern "C" fn webview_flutter_linux_texture_id(handle: u64) -> i64 {
    native_view(handle).map_or(0, |view| view.texture.id())
}

#[unsafe(no_mangle)]
/// Returns the current physical texture width, or zero for an invalid handle.
pub extern "C" fn webview_flutter_linux_texture_width(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| view.texture.width())
}

#[unsafe(no_mangle)]
/// Returns the current physical texture height, or zero for an invalid handle.
pub extern "C" fn webview_flutter_linux_texture_height(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| view.texture.height())
}

#[unsafe(no_mangle)]
/// Returns the generation incremented after each effective texture resize.
pub extern "C" fn webview_flutter_linux_texture_generation(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| view.texture.generation())
}

#[unsafe(no_mangle)]
/// Marks this handle's Irondash texture as having a new frame.
///
/// Returns `-1` for an invalid/disposed handle or texture, and `-2` for a
/// poisoned texture lock.
pub extern "C" fn webview_flutter_linux_texture_request_frame(handle: u64) -> i32 {
    native_view(handle).map_or(-1, |view| view.texture.mark_frame_available())
}

#[unsafe(no_mangle)]
/// Returns the number of successful DMA-BUF-to-GL copies for this view.
pub extern "C" fn webview_flutter_linux_texture_dma_buf_copy_count(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| view.texture.dma_buf_copy_count())
}

#[unsafe(no_mangle)]
/// Returns the generation assigned to the latest accepted WPE frame.
pub extern "C" fn webview_flutter_linux_wpe_frame_generation(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| {
        view.metrics.frame_generation.load(Ordering::Acquire)
    })
}

#[unsafe(no_mangle)]
/// Returns the number of `buffer-rendered` signals observed for this view.
pub extern "C" fn webview_flutter_linux_wpe_paint_count(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| view.metrics.paint_count.load(Ordering::Acquire))
}

#[unsafe(no_mangle)]
/// Returns the number of rendered buffers successfully copied to the GL ring.
pub extern "C" fn webview_flutter_linux_wpe_valid_paint_count(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| {
        view.metrics.valid_paint_count.load(Ordering::Acquire)
    })
}

#[unsafe(no_mangle)]
/// Returns the plane count reported by the latest accepted DMA-BUF.
pub extern "C" fn webview_flutter_linux_wpe_plane_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| view.metrics.plane_count.load(Ordering::Acquire))
}

#[unsafe(no_mangle)]
/// Returns the DRM format reported by the latest accepted DMA-BUF.
pub extern "C" fn webview_flutter_linux_wpe_format(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| view.metrics.format.load(Ordering::Acquire))
}

#[unsafe(no_mangle)]
/// Returns the DRM modifier reported by the latest accepted DMA-BUF.
pub extern "C" fn webview_flutter_linux_wpe_modifier(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| view.metrics.modifier.load(Ordering::Acquire))
}

#[unsafe(no_mangle)]
/// Returns the width of the latest accepted WPE buffer.
pub extern "C" fn webview_flutter_linux_wpe_width(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| view.metrics.width.load(Ordering::Acquire))
}

#[unsafe(no_mangle)]
/// Returns the height of the latest accepted WPE buffer.
pub extern "C" fn webview_flutter_linux_wpe_height(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| view.metrics.height.load(Ordering::Acquire))
}

#[unsafe(no_mangle)]
/// Returns the first-plane stride of the latest accepted DMA-BUF.
pub extern "C" fn webview_flutter_linux_wpe_first_plane_stride(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.metrics.first_plane_stride.load(Ordering::Acquire)
    })
}
