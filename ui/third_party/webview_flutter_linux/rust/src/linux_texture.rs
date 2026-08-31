// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Per-view Flutter texture transport for Linux.
//!
//! A [`TextureState`] is created for each native WebView handle. It registers
//! one Irondash `FlTextureGL` with the Flutter engine and owns a three-slot GL
//! ring. WPE delivers borrowed DMA-BUFs on the platform thread; this module
//! waits for the producer fence, imports the planes into EGL, copies the image
//! into the next application-owned slot, then returns before WPE releases the
//! buffer. Flutter therefore never samples a texture still owned by WebKit.
//!
//! The Irondash payload callback runs on Flutter's raster thread. Shared scalar
//! state lives in [`TextureMetrics`] atomics and mutable GL resources live
//! behind the provider mutex. WPE/GLib objects never enter this module.
//!
//! ## GL ownership invariants
//!
//! - Texture names are created in Flutter's share group by the raster callback.
//! - DMA-BUF copies use a private surfaceless context sharing that group.
//! - The caller's EGL display, context, draw/read surfaces, and API are restored
//!   before a copy returns.
//! - A WPE buffer is only borrowed for the synchronous duration of
//!   [`TextureState::copy_dma_buf`]; file descriptors are never closed here.
//! - Published slots are application-owned and rotate only after a completed
//!   copy and fence wait.

use std::{
    ffi::{c_char, c_void},
    ptr,
    sync::{
        Arc, Mutex, OnceLock, Weak,
        atomic::{AtomicBool, AtomicI64, AtomicU32, AtomicU64, AtomicUsize, Ordering},
        mpsc::{SyncSender, TrySendError, sync_channel},
    },
    thread,
    time::Instant,
};

use irondash_texture::{
    BoxedGLTexture, GLTexture, GLTextureProvider, PayloadProvider, SendableTexture, Texture,
};

use crate::{HEIGHT, WIDTH, checked_dynamic_frame_byte_length, render_flutter_texture_test_frame};

type EglDisplay = *mut c_void;
type EglContext = *mut c_void;
type EglSurface = *mut c_void;
type EglConfig = *mut c_void;
type EglImage = *mut c_void;
type GlSync = *mut c_void;

const GL_TEXTURE_2D: u32 = 0x0DE1;
const GL_TEXTURE_MIN_FILTER: u32 = 0x2801;
const GL_TEXTURE_MAG_FILTER: u32 = 0x2800;
const GL_TEXTURE_WRAP_S: u32 = 0x2802;
const GL_TEXTURE_WRAP_T: u32 = 0x2803;
const GL_NEAREST: i32 = 0x2600;
const GL_CLAMP_TO_EDGE: i32 = 0x812F;
const GL_RGBA8: i32 = 0x8058;
const GL_RGBA: u32 = 0x1908;
const GL_UNSIGNED_BYTE: u32 = 0x1401;
const GL_UNPACK_ALIGNMENT: u32 = 0x0CF5;
const GL_TEXTURE_BINDING_2D: u32 = 0x8069;
const GL_READ_FRAMEBUFFER: u32 = 0x8CA8;
const GL_DRAW_FRAMEBUFFER: u32 = 0x8CA9;
const GL_READ_FRAMEBUFFER_BINDING: u32 = 0x8CAA;
const GL_DRAW_FRAMEBUFFER_BINDING: u32 = 0x8CA6;
const GL_COLOR_ATTACHMENT0: u32 = 0x8CE0;
const GL_FRAMEBUFFER_COMPLETE: u32 = 0x8CD5;
const GL_COLOR_BUFFER_BIT: u32 = 0x00004000;
const GL_SYNC_GPU_COMMANDS_COMPLETE: u32 = 0x9117;
const GL_SYNC_FLUSH_COMMANDS_BIT: u32 = 0x00000001;
const GL_TIMEOUT_EXPIRED: u32 = 0x911B;
const GL_WAIT_FAILED: u32 = 0x911D;
const GL_NO_ERROR: u32 = 0;

/// Maximum number of distinct texture notifications waiting for the worker.
///
/// A view coalesces all of its unpublished frames into one notification, so
/// this bound limits pathological multi-view pressure rather than ordinary
/// frame rate. Dropping a notification is safe: the next rendered frame tries
/// again after the pending flag is cleared.
const FRAME_NOTIFICATION_QUEUE_CAPACITY: usize = 256;

static FRAME_NOTIFICATION_SENDER: OnceLock<Option<SyncSender<Weak<TextureState>>>> =
    OnceLock::new();

const EGL_NONE: i32 = 0x3038;
const EGL_CONFIG_ID: i32 = 0x3028;
const EGL_CONTEXT_CLIENT_VERSION: i32 = 0x3098;
const EGL_DRAW: i32 = 0x3059;
const EGL_READ: i32 = 0x305A;
const EGL_WIDTH: i32 = 0x3057;
const EGL_HEIGHT: i32 = 0x3056;
const EGL_LINUX_DMA_BUF_EXT: u32 = 0x3270;
const EGL_LINUX_DRM_FOURCC_EXT: i32 = 0x3271;
const EGL_DMA_BUF_PLANE0_FD_EXT: i32 = 0x3272;
const EGL_DMA_BUF_PLANE0_OFFSET_EXT: i32 = 0x3273;
const EGL_DMA_BUF_PLANE0_PITCH_EXT: i32 = 0x3274;
const EGL_DMA_BUF_PLANE1_FD_EXT: i32 = 0x3275;
const EGL_DMA_BUF_PLANE1_OFFSET_EXT: i32 = 0x3276;
const EGL_DMA_BUF_PLANE1_PITCH_EXT: i32 = 0x3277;
const EGL_DMA_BUF_PLANE2_FD_EXT: i32 = 0x3278;
const EGL_DMA_BUF_PLANE2_OFFSET_EXT: i32 = 0x3279;
const EGL_DMA_BUF_PLANE2_PITCH_EXT: i32 = 0x327A;
const EGL_DMA_BUF_PLANE3_FD_EXT: i32 = 0x3440;
const EGL_DMA_BUF_PLANE3_OFFSET_EXT: i32 = 0x3441;
const EGL_DMA_BUF_PLANE3_PITCH_EXT: i32 = 0x3442;
const EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT: i32 = 0x3443;
const EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT: i32 = 0x3444;
const EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT: i32 = 0x3445;
const EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT: i32 = 0x3446;
const EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT: i32 = 0x3447;
const EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT: i32 = 0x3448;
const EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT: i32 = 0x3449;
const EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT: i32 = 0x344A;
const EGL_DMA_BUF_PLANE_FD_ATTRIBUTES: [i32; 4] = [
    EGL_DMA_BUF_PLANE0_FD_EXT,
    EGL_DMA_BUF_PLANE1_FD_EXT,
    EGL_DMA_BUF_PLANE2_FD_EXT,
    EGL_DMA_BUF_PLANE3_FD_EXT,
];
const EGL_DMA_BUF_PLANE_OFFSET_ATTRIBUTES: [i32; 4] = [
    EGL_DMA_BUF_PLANE0_OFFSET_EXT,
    EGL_DMA_BUF_PLANE1_OFFSET_EXT,
    EGL_DMA_BUF_PLANE2_OFFSET_EXT,
    EGL_DMA_BUF_PLANE3_OFFSET_EXT,
];
const EGL_DMA_BUF_PLANE_PITCH_ATTRIBUTES: [i32; 4] = [
    EGL_DMA_BUF_PLANE0_PITCH_EXT,
    EGL_DMA_BUF_PLANE1_PITCH_EXT,
    EGL_DMA_BUF_PLANE2_PITCH_EXT,
    EGL_DMA_BUF_PLANE3_PITCH_EXT,
];
const EGL_DMA_BUF_PLANE_MODIFIER_LO_ATTRIBUTES: [i32; 4] = [
    EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT,
    EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT,
    EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT,
    EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT,
];
const EGL_DMA_BUF_PLANE_MODIFIER_HI_ATTRIBUTES: [i32; 4] = [
    EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT,
    EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT,
    EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT,
    EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT,
];
const COPY_FENCE_TIMEOUT_NS: u64 = 16_000_000;
const TEXTURE_SLOT_COUNT: usize = 3;

/// Cross-thread scalar state for one Flutter texture.
///
/// WPE-side code updates dimensions and copy diagnostics on the platform
/// thread. The Irondash provider reads them on the raster thread. Acquire and
/// release ordering makes a newly published GL name/dimension visible without
/// moving the thread-affine browser objects across threads.
pub(crate) struct TextureMetrics {
    id: AtomicI64,
    width: AtomicU32,
    height: AtomicU32,
    generation: AtomicU64,
    gl_name: AtomicU32,
    egl_display: AtomicUsize,
    egl_context: AtomicUsize,
    dma_buf_generation: AtomicU64,
    dma_buf_status: AtomicI64,
    dma_buf_copy_count: AtomicU64,
    dma_buf_last_copy_micros: AtomicU64,
    dma_buf_max_copy_micros: AtomicU64,
    dma_buf_fence_fallback_count: AtomicU64,
}

impl Default for TextureMetrics {
    fn default() -> Self {
        Self {
            id: AtomicI64::new(0),
            width: AtomicU32::new(WIDTH as u32),
            height: AtomicU32::new(HEIGHT as u32),
            generation: AtomicU64::new(1),
            gl_name: AtomicU32::new(0),
            egl_display: AtomicUsize::new(0),
            egl_context: AtomicUsize::new(0),
            dma_buf_generation: AtomicU64::new(0),
            dma_buf_status: AtomicI64::new(0),
            dma_buf_copy_count: AtomicU64::new(0),
            dma_buf_last_copy_micros: AtomicU64::new(0),
            dma_buf_max_copy_micros: AtomicU64::new(0),
            dma_buf_fence_fallback_count: AtomicU64::new(0),
        }
    }
}

const fn fourcc(a: u8, b: u8, c: u8, d: u8) -> u32 {
    a as u32 | (b as u32) << 8 | (c as u32) << 16 | (d as u32) << 24
}

const DRM_FORMAT_ARGB8888: u32 = fourcc(b'A', b'R', b'2', b'4');
const DRM_FORMAT_ABGR8888: u32 = fourcc(b'A', b'B', b'2', b'4');

type EglGetCurrentDisplay = unsafe extern "C" fn() -> EglDisplay;
type EglGetCurrentContext = unsafe extern "C" fn() -> EglContext;
type EglGetCurrentSurface = unsafe extern "C" fn(i32) -> EglSurface;
type EglQueryContext = unsafe extern "C" fn(EglDisplay, EglContext, i32, *mut i32) -> u32;
type EglChooseConfig =
    unsafe extern "C" fn(EglDisplay, *const i32, *mut EglConfig, i32, *mut i32) -> u32;
type EglQueryApi = unsafe extern "C" fn() -> u32;
type EglBindApi = unsafe extern "C" fn(u32) -> u32;
type EglCreateContext =
    unsafe extern "C" fn(EglDisplay, EglConfig, EglContext, *const i32) -> EglContext;
type EglDestroyContext = unsafe extern "C" fn(EglDisplay, EglContext) -> u32;
type EglMakeCurrent = unsafe extern "C" fn(EglDisplay, EglSurface, EglSurface, EglContext) -> u32;
type GlGenTextures = unsafe extern "C" fn(i32, *mut u32);
type GlDeleteTextures = unsafe extern "C" fn(i32, *const u32);
type GlBindTexture = unsafe extern "C" fn(u32, u32);
type GlTexParameteri = unsafe extern "C" fn(u32, u32, i32);
type GlTexImage2D = unsafe extern "C" fn(u32, i32, i32, i32, i32, i32, u32, u32, *const c_void);
type GlPixelStorei = unsafe extern "C" fn(u32, i32);
type GlGetIntegerv = unsafe extern "C" fn(u32, *mut i32);
type GlGetError = unsafe extern "C" fn() -> u32;
type GlGenFramebuffers = unsafe extern "C" fn(i32, *mut u32);
type GlDeleteFramebuffers = unsafe extern "C" fn(i32, *const u32);
type GlBindFramebuffer = unsafe extern "C" fn(u32, u32);
type GlFramebufferTexture2D = unsafe extern "C" fn(u32, u32, u32, u32, i32);
type GlCheckFramebufferStatus = unsafe extern "C" fn(u32) -> u32;
type GlBlitFramebuffer = unsafe extern "C" fn(i32, i32, i32, i32, i32, i32, i32, i32, u32, u32);
type GlEglImageTargetTexture2d = unsafe extern "C" fn(u32, EglImage);
type GlFenceSync = unsafe extern "C" fn(u32, u32) -> GlSync;
type GlFlush = unsafe extern "C" fn();
type GlClientWaitSync = unsafe extern "C" fn(GlSync, u32, u64) -> u32;
type GlDeleteSync = unsafe extern "C" fn(GlSync);
type GlFinish = unsafe extern "C" fn();
type EglCreateImageKhr =
    unsafe extern "C" fn(EglDisplay, EglContext, u32, *mut c_void, *const i32) -> EglImage;
type EglDestroyImageKhr = unsafe extern "C" fn(EglDisplay, EglImage) -> u32;

#[link(name = "epoxy")]
unsafe extern "C" {
    fn epoxy_has_egl_extension(display: EglDisplay, extension: *const c_char) -> bool;
    #[link_name = "epoxy_eglGetCurrentDisplay"]
    static eglGetCurrentDisplay: EglGetCurrentDisplay;
    #[link_name = "epoxy_eglGetCurrentContext"]
    static eglGetCurrentContext: EglGetCurrentContext;
    #[link_name = "epoxy_eglGetCurrentSurface"]
    static eglGetCurrentSurface: EglGetCurrentSurface;
    #[link_name = "epoxy_eglQueryContext"]
    static eglQueryContext: EglQueryContext;
    #[link_name = "epoxy_eglChooseConfig"]
    static eglChooseConfig: EglChooseConfig;
    #[link_name = "epoxy_eglQueryAPI"]
    static eglQueryAPI: EglQueryApi;
    #[link_name = "epoxy_eglBindAPI"]
    static eglBindAPI: EglBindApi;
    #[link_name = "epoxy_eglCreateContext"]
    static eglCreateContext: EglCreateContext;
    #[link_name = "epoxy_eglDestroyContext"]
    static eglDestroyContext: EglDestroyContext;
    #[link_name = "epoxy_eglMakeCurrent"]
    static eglMakeCurrent: EglMakeCurrent;
    static epoxy_glGenTextures: GlGenTextures;
    static epoxy_glDeleteTextures: GlDeleteTextures;
    static epoxy_glBindTexture: GlBindTexture;
    static epoxy_glTexParameteri: GlTexParameteri;
    static epoxy_glTexImage2D: GlTexImage2D;
    static epoxy_glPixelStorei: GlPixelStorei;
    static epoxy_glGetIntegerv: GlGetIntegerv;
    static epoxy_glGetError: GlGetError;
    static epoxy_glGenFramebuffers: GlGenFramebuffers;
    static epoxy_glDeleteFramebuffers: GlDeleteFramebuffers;
    static epoxy_glBindFramebuffer: GlBindFramebuffer;
    static epoxy_glFramebufferTexture2D: GlFramebufferTexture2D;
    static epoxy_glCheckFramebufferStatus: GlCheckFramebufferStatus;
    static epoxy_glBlitFramebuffer: GlBlitFramebuffer;
    static epoxy_glEGLImageTargetTexture2DOES: GlEglImageTargetTexture2d;
    static epoxy_glFenceSync: GlFenceSync;
    static epoxy_glFlush: GlFlush;
    static epoxy_glClientWaitSync: GlClientWaitSync;
    static epoxy_glDeleteSync: GlDeleteSync;
    static epoxy_glFinish: GlFinish;
    static epoxy_eglCreateImageKHR: EglCreateImageKhr;
    static epoxy_eglDestroyImageKHR: EglDestroyImageKhr;
}

#[derive(Clone, Copy)]
/// Borrowed description of one WPE DMA-BUF frame.
///
/// The file descriptors remain owned by WPE. They are valid only while the
/// `buffer-rendered` callback is active and must not be closed, duplicated into
/// long-lived state, or accessed after the callback releases the buffer.
pub(crate) struct DmaBufFrame {
    /// Monotonic generation assigned by the owning native view.
    pub generation: u64,
    /// Number of populated entries in `fds`, `strides`, and `offsets`.
    pub plane_count: u32,
    /// Borrowed plane file descriptors; unused entries contain `-1`.
    pub fds: [i32; 4],
    /// Plane row strides in bytes.
    pub strides: [u32; 4],
    /// Plane byte offsets from the start of each DMA-BUF.
    pub offsets: [u64; 4],
    /// DRM format modifier shared by the planes.
    pub modifier: u64,
    /// DRM fourcc supplied by WPE, or the WPE legacy zero/one aliases.
    pub format: u32,
    /// Full buffer width allocated by the producer.
    pub coded_width: i32,
    /// Full buffer height allocated by the producer.
    pub coded_height: i32,
    /// X origin of the visible rectangle.
    pub visible_x: i32,
    /// Y origin of the visible rectangle.
    pub visible_y: i32,
    /// Width copied into the Flutter texture.
    pub visible_width: i32,
    /// Height copied into the Flutter texture.
    pub visible_height: i32,
}

/// Raster-thread GL resources for one texture provider.
///
/// `names` belong to Flutter's GL share group. `copy_context` is created lazily
/// from the raster callback's current context, then used synchronously by WPE
/// frame callbacks. `published_slot` always identifies the last completely
/// copied texture, never the slot currently being written.
struct GlState {
    names: [u32; TEXTURE_SLOT_COUNT],
    published_slot: usize,
    allocated_width: u32,
    allocated_height: u32,
    uploaded_generation: u64,
    imported_dma_buf_generation: u64,
    copy_display: usize,
    copy_context: usize,
    copy_api: u32,
    pixels: Vec<u8>,
}

impl Default for GlState {
    fn default() -> Self {
        Self {
            names: [0; TEXTURE_SLOT_COUNT],
            published_slot: 0,
            allocated_width: 0,
            allocated_height: 0,
            uploaded_generation: 0,
            imported_dma_buf_generation: 0,
            copy_display: 0,
            copy_context: 0,
            copy_api: 0,
            pixels: Vec::new(),
        }
    }
}

impl GlState {
    /// Returns the GL name currently safe for Flutter to sample.
    fn published_name(&self) -> u32 {
        self.names[self.published_slot]
    }

    /// Lazily creates the surfaceless context used for DMA-BUF copies.
    ///
    /// # Safety
    ///
    /// Flutter's raster EGL context must be current on the calling thread. The
    /// returned context shares its object namespace with that Flutter context.
    /// No context/surface pointers are retained except as opaque owned handles.
    unsafe fn ensure_copy_context(&mut self) -> bool {
        if self.copy_context != 0 {
            return true;
        }
        // SAFETY: Flutter invokes the Irondash GL provider with its raster GL
        // context current. Every handle is copied, not retained by reference.
        let display = unsafe { eglGetCurrentDisplay() };
        let flutter_context = unsafe { eglGetCurrentContext() };
        if display.is_null()
            || flutter_context.is_null()
            || !unsafe { epoxy_has_egl_extension(display, c"EGL_KHR_surfaceless_context".as_ptr()) }
        {
            return false;
        }

        let mut config_id = 0;
        let mut client_version = 0;
        if unsafe { eglQueryContext(display, flutter_context, EGL_CONFIG_ID, &mut config_id) } == 0
            || unsafe {
                eglQueryContext(
                    display,
                    flutter_context,
                    EGL_CONTEXT_CLIENT_VERSION,
                    &mut client_version,
                )
            } == 0
        {
            return false;
        }
        let attributes = [EGL_CONFIG_ID, config_id, EGL_NONE];
        let mut config = ptr::null_mut();
        let mut count = 0;
        if unsafe { eglChooseConfig(display, attributes.as_ptr(), &mut config, 1, &mut count) } == 0
            || count != 1
        {
            return false;
        }
        let context_attributes = [EGL_CONTEXT_CLIENT_VERSION, client_version, EGL_NONE];
        let copy_context = unsafe {
            eglCreateContext(
                display,
                config,
                flutter_context,
                context_attributes.as_ptr(),
            )
        };
        if copy_context.is_null() {
            return false;
        }
        self.copy_display = display as usize;
        self.copy_context = copy_context as usize;
        self.copy_api = unsafe { eglQueryAPI() };
        true
    }

    /// Produces the payload returned to Flutter for the next raster frame.
    ///
    /// The method allocates the three application-owned textures on first use,
    /// reallocates them after a size generation change, and uploads the
    /// diagnostic fallback until WPE successfully imports a browser frame.
    ///
    /// # Safety
    ///
    /// Called only by Irondash while Flutter's raster GL context is current.
    unsafe fn populate(&mut self, metrics: &TextureMetrics) -> Result<TextureSnapshot, i32> {
        let width = metrics.width.load(Ordering::Acquire);
        let height = metrics.height.load(Ordering::Acquire);
        let generation = metrics.generation.load(Ordering::Acquire);
        let byte_length = checked_dynamic_frame_byte_length(width, height).ok_or(-40)?;

        if self.names[0] == 0 {
            unsafe { epoxy_glGenTextures(TEXTURE_SLOT_COUNT as i32, self.names.as_mut_ptr()) };
            if self.names.contains(&0) {
                return Err(-41);
            }
            for name in self.names {
                unsafe {
                    epoxy_glBindTexture(GL_TEXTURE_2D, name);
                    epoxy_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
                    epoxy_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
                    epoxy_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
                    epoxy_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
                }
            }
            self.published_slot = 0;
        }

        if self.allocated_width != width || self.allocated_height != height {
            for name in self.names {
                unsafe {
                    epoxy_glBindTexture(GL_TEXTURE_2D, name);
                    epoxy_glTexImage2D(
                        GL_TEXTURE_2D,
                        0,
                        GL_RGBA8,
                        width as i32,
                        height as i32,
                        0,
                        GL_RGBA,
                        GL_UNSIGNED_BYTE,
                        ptr::null(),
                    );
                }
            }
            self.published_slot = 0;
            self.allocated_width = width;
            self.allocated_height = height;
            self.uploaded_generation = 0;
            self.imported_dma_buf_generation = 0;
        }

        let name = self.published_name();
        unsafe { epoxy_glBindTexture(GL_TEXTURE_2D, name) };
        let _ = unsafe { self.ensure_copy_context() };

        if self.imported_dma_buf_generation == 0 && self.uploaded_generation != generation {
            self.pixels.resize(byte_length, 0);
            render_flutter_texture_test_frame(
                &mut self.pixels,
                width as usize,
                height as usize,
                generation,
            );
            unsafe {
                epoxy_glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
                epoxy_glTexImage2D(
                    GL_TEXTURE_2D,
                    0,
                    GL_RGBA8,
                    width as i32,
                    height as i32,
                    0,
                    GL_RGBA,
                    GL_UNSIGNED_BYTE,
                    self.pixels.as_ptr().cast(),
                );
            }
            self.uploaded_generation = generation;
        }

        if unsafe { epoxy_glGetError() } != GL_NO_ERROR {
            return Err(-42);
        }

        let display = unsafe { eglGetCurrentDisplay() } as usize;
        let context = unsafe { eglGetCurrentContext() } as usize;
        metrics.gl_name.store(name, Ordering::Release);
        metrics.egl_display.store(display, Ordering::Release);
        metrics.egl_context.store(context, Ordering::Release);
        Ok(TextureSnapshot {
            name,
            width: width as i32,
            height: height as i32,
        })
    }
}

impl Drop for GlState {
    fn drop(&mut self) {
        if self.copy_display != 0 && self.copy_context != 0 {
            // SAFETY: This context is owned by the state and is never current
            // outside the bounded copy operation.
            unsafe {
                eglDestroyContext(
                    self.copy_display as EglDisplay,
                    self.copy_context as EglContext,
                );
            }
        }
        // Flutter's GL context is not guaranteed to be current during drop.
        // Calling glDeleteTextures here would therefore be undefined. The
        // engine/share-group teardown reclaims these names after unregistering
        // the Irondash texture.
        self.names = [0; TEXTURE_SLOT_COUNT];
    }
}

/// Irondash payload provider shared with Flutter's raster thread.
///
/// The provider outlives individual payload snapshots. Its mutex serializes
/// texture allocation/readout with platform-thread DMA-BUF copies.
struct TextureProvider {
    state: Mutex<GlState>,
    metrics: Arc<TextureMetrics>,
    frame_notification_pending: Arc<AtomicBool>,
}

impl TextureProvider {
    fn new(metrics: Arc<TextureMetrics>, frame_notification_pending: Arc<AtomicBool>) -> Self {
        Self {
            state: Mutex::new(GlState::default()),
            metrics,
            frame_notification_pending,
        }
    }
}

/// Immutable payload handed to Flutter for a single texture lookup.
///
/// `GLTexture` borrows these fields only for the duration of Irondash's
/// callback, so the snapshot can be allocated independently on every lookup.
struct TextureSnapshot {
    name: u32,
    width: i32,
    height: i32,
}

impl GLTextureProvider for TextureSnapshot {
    fn get(&self) -> GLTexture<'_> {
        GLTexture {
            target: GL_TEXTURE_2D,
            name: &self.name,
            width: self.width,
            height: self.height,
        }
    }
}

impl PayloadProvider<BoxedGLTexture> for TextureProvider {
    fn get_payload(&self) -> BoxedGLTexture {
        // A poisoned/temporarily unavailable state lock must not unwind across
        // Flutter's C callback. Reuse the last published values instead.
        let fallback = TextureSnapshot {
            name: self.metrics.gl_name.load(Ordering::Acquire),
            width: self.metrics.width.load(Ordering::Acquire) as i32,
            height: self.metrics.height.load(Ordering::Acquire) as i32,
        };
        let Ok(mut state) = self.state.lock() else {
            self.frame_notification_pending
                .store(false, Ordering::Release);
            return Box::new(fallback);
        };
        // SAFETY: Irondash invokes this provider on Flutter's raster thread
        // while its GL context is current.
        let snapshot = unsafe { state.populate(&self.metrics) }.unwrap_or(fallback);
        // Clearing while the provider still owns the GL-state lock prevents a
        // producer from copying a newer frame, observing the old `true` flag,
        // and losing the notification for that frame.
        self.frame_notification_pending
            .store(false, Ordering::Release);
        Box::new(snapshot)
    }
}

/// Complete texture-side state associated with one native WebView handle.
///
/// The `Arc` returned by [`TextureState::new`] is owned by the platform-thread
/// native view and by WPE signal closures while callbacks can still arrive.
/// The Irondash texture holds the provider independently for raster callbacks.
/// Shutdown unregisters the Flutter texture before resetting the GL provider.
pub(crate) struct TextureState {
    metrics: Arc<TextureMetrics>,
    provider: Arc<TextureProvider>,
    texture: Mutex<Option<Arc<SendableTexture<BoxedGLTexture>>>>,
    frame_notification_pending: Arc<AtomicBool>,
}

/// Returns the process-wide handoff used to leave a Dart FFI call before
/// notifying Flutter's Linux texture registrar.
///
/// WPE is advanced by a Dart timer through `webview_flutter_linux_wpe_pump`.
/// Its `buffer-rendered` signal therefore runs *inside* a Dart FFI invocation
/// on Flutter's platform thread. Calling the Linux texture registrar directly
/// from that callback may synchronously ask the engine to enter the already
/// current Dart isolate, which is fatal during hot restart. The worker calls
/// Irondash from a foreign thread; `SendableTexture` then posts the registrar
/// operation back to the platform run loop, after the FFI frame has returned.
fn frame_notification_sender() -> Option<&'static SyncSender<Weak<TextureState>>> {
    FRAME_NOTIFICATION_SENDER
        .get_or_init(|| {
            let (sender, receiver) =
                sync_channel::<Weak<TextureState>>(FRAME_NOTIFICATION_QUEUE_CAPACITY);
            let worker = thread::Builder::new()
                .name("webview-linux-texture-notify".to_owned())
                .spawn(move || {
                    while let Ok(texture) = receiver.recv() {
                        if let Some(texture) = texture.upgrade() {
                            texture.notify_flutter_from_worker();
                        }
                    }
                });
            worker.ok().map(|_| sender)
        })
        .as_ref()
}

impl TextureState {
    /// Registers a new GL texture with the Flutter engine.
    ///
    /// `engine_handle` is the opaque `FlEngine` handle supplied by
    /// `irondash_engine_context`. Returns `-3` when registration fails and `-4`
    /// when the engine returns a non-positive texture identifier.
    pub(crate) fn new(engine_handle: i64) -> Result<Arc<Self>, i32> {
        let metrics = Arc::new(TextureMetrics::default());
        let frame_notification_pending = Arc::new(AtomicBool::new(false));
        let provider = Arc::new(TextureProvider::new(
            metrics.clone(),
            frame_notification_pending.clone(),
        ));
        let texture =
            Texture::new_with_provider(engine_handle, provider.clone()).map_err(|_| -3)?;
        let id = texture.id();
        if id <= 0 {
            return Err(-4);
        }
        let texture = texture.into_sendable_texture();
        metrics.id.store(id, Ordering::Release);
        let state = Arc::new(Self {
            metrics,
            provider,
            texture: Mutex::new(Some(texture)),
            frame_notification_pending,
        });
        if state.mark_frame_available() != 0 {
            return Err(-5);
        }
        Ok(state)
    }

    /// Returns Flutter's texture identifier, or zero after shutdown.
    pub(crate) fn id(&self) -> i64 {
        self.metrics.id.load(Ordering::Acquire)
    }

    /// Returns the current physical texture width.
    pub(crate) fn width(&self) -> u32 {
        self.metrics.width.load(Ordering::Acquire)
    }

    /// Returns the current physical texture height.
    pub(crate) fn height(&self) -> u32 {
        self.metrics.height.load(Ordering::Acquire)
    }

    /// Returns the resize generation observed by the raster provider.
    pub(crate) fn generation(&self) -> u64 {
        self.metrics.generation.load(Ordering::Acquire)
    }

    /// Returns the number of completed zero-copy-to-GPU frame copies.
    pub(crate) fn dma_buf_copy_count(&self) -> u64 {
        self.metrics.dma_buf_copy_count.load(Ordering::Acquire)
    }

    /// Publishes a new physical size to the raster provider.
    ///
    /// The GL allocation occurs lazily on the raster thread. A generation is
    /// advanced only when either dimension changes. Invalid or excessive
    /// allocations return `-1` without changing the current size.
    pub(crate) fn resize(&self, width: u32, height: u32) -> i32 {
        if checked_dynamic_frame_byte_length(width, height).is_none() {
            return -1;
        }
        let old_width = self.metrics.width.swap(width, Ordering::AcqRel);
        let old_height = self.metrics.height.swap(height, Ordering::AcqRel);
        if old_width != width || old_height != height {
            self.metrics.generation.fetch_add(1, Ordering::AcqRel);
        }
        0
    }

    /// Unregisters this view's Flutter texture and resets its GL state.
    ///
    /// WPE signal closures must be disconnected/dropped before this method is
    /// called. The operation is idempotent at the resource level, though the
    /// public handle registry prevents a second call for the same handle.
    pub(crate) fn shutdown(&self) -> i32 {
        let Ok(mut texture) = self.texture.lock() else {
            return -2;
        };
        texture.take();
        self.frame_notification_pending
            .store(false, Ordering::Release);
        self.metrics.id.store(0, Ordering::Release);
        self.metrics.gl_name.store(0, Ordering::Release);
        self.metrics.egl_display.store(0, Ordering::Release);
        self.metrics.egl_context.store(0, Ordering::Release);
        let Ok(mut state) = self.provider.state.lock() else {
            return -3;
        };
        *state = GlState::default();
        0
    }

    /// Schedules Flutter to sample the newest texture payload.
    ///
    /// Calls are coalesced until Flutter's raster callback consumes the current
    /// payload. The registrar call is deliberately handed to a worker first so
    /// it cannot execute synchronously inside the Dart FFI frame that pumps
    /// WPE. Returns `-1` after shutdown, `-2` for a poisoned texture mutex,
    /// `-3` when the worker is unavailable, or `-4` when its bounded queue is
    /// full or disconnected.
    pub(crate) fn mark_frame_available(self: &Arc<Self>) -> i32 {
        {
            let texture = match self.texture.lock() {
                Ok(texture) => texture,
                Err(_) => return -2,
            };
            if texture.is_none() {
                return -1;
            }
        }
        if self
            .frame_notification_pending
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_err()
        {
            return 0;
        }
        let Some(sender) = frame_notification_sender() else {
            self.frame_notification_pending
                .store(false, Ordering::Release);
            return -3;
        };
        match sender.try_send(Arc::downgrade(self)) {
            Ok(()) => 0,
            Err(TrySendError::Full(_) | TrySendError::Disconnected(_)) => {
                self.frame_notification_pending
                    .store(false, Ordering::Release);
                -4
            }
        }
    }

    /// Runs only on the notification worker, never inside a Dart FFI call.
    ///
    /// Irondash detects that this is not Flutter's platform thread and posts
    /// the actual registrar call to its run loop. A concurrent shutdown turns
    /// the texture option into `None`, making a queued notification harmless.
    fn notify_flutter_from_worker(&self) {
        let texture = match self.texture.lock() {
            Ok(texture) => texture.clone(),
            Err(_) => {
                self.frame_notification_pending
                    .store(false, Ordering::Release);
                return;
            }
        };
        let Some(texture) = texture else {
            self.frame_notification_pending
                .store(false, Ordering::Release);
            return;
        };
        texture.mark_frame_available();
    }

    /// Imports and copies one borrowed WPE DMA-BUF into the next ring slot.
    ///
    /// The copy is synchronous: a successful return guarantees that the
    /// source buffer may be released to WPE and the destination slot is safe
    /// to publish. `-31` indicates that Flutter has not yet invoked the raster
    /// provider, so no shared copy context/texture allocation exists.
    pub(crate) fn copy_dma_buf(&self, frame: &DmaBufFrame) -> i32 {
        let Ok(mut state) = self.provider.state.lock() else {
            self.publish_dma_buf_result(frame.generation, -2, 0, false);
            return -2;
        };
        if state.copy_context == 0
            || state.published_name() == 0
            || state.allocated_width == 0
            || state.allocated_height == 0
        {
            self.publish_dma_buf_result(frame.generation, -31, 0, false);
            return -31;
        }

        // SAFETY: The copy context is private to this state, shares Flutter's
        // texture namespace, and is restored before returning to WPE.
        unsafe { self.copy_dma_buf_locked(&mut state, frame) }
    }
}

impl TextureState {
    /// Performs the bounded copy while preserving the caller's EGL state.
    ///
    /// A frame is written into the slot after `published_slot`; that slot only
    /// becomes visible after import, blit, and GPU fence completion succeed.
    ///
    /// # Safety
    ///
    /// `state.copy_context` must be a live context owned by `state` and sharing
    /// Flutter's texture namespace. Every DMA-BUF descriptor in `frame` must
    /// remain valid until this function returns.
    unsafe fn copy_dma_buf_locked(&self, state: &mut GlState, frame: &DmaBufFrame) -> i32 {
        let previous_display = unsafe { eglGetCurrentDisplay() };
        let previous_context = unsafe { eglGetCurrentContext() };
        let previous_draw = unsafe { eglGetCurrentSurface(EGL_DRAW) };
        let previous_read = unsafe { eglGetCurrentSurface(EGL_READ) };
        let previous_api = unsafe { eglQueryAPI() };
        let copy_display = state.copy_display as EglDisplay;
        let copy_context = state.copy_context as EglContext;
        if unsafe { eglBindAPI(state.copy_api) } == 0
            || unsafe {
                eglMakeCurrent(copy_display, ptr::null_mut(), ptr::null_mut(), copy_context)
            } == 0
        {
            unsafe { eglBindAPI(previous_api) };
            self.publish_dma_buf_result(frame.generation, -32, 0, false);
            return -32;
        }

        let frame_width = frame.visible_width.max(0) as u32;
        let frame_height = frame.visible_height.max(0) as u32;
        let mut preparation_status = 0;
        if frame_width == 0 || frame_height == 0 {
            preparation_status = -33;
        } else if state.allocated_width != frame_width || state.allocated_height != frame_height {
            for name in state.names {
                unsafe {
                    epoxy_glBindTexture(GL_TEXTURE_2D, name);
                    epoxy_glTexImage2D(
                        GL_TEXTURE_2D,
                        0,
                        GL_RGBA8,
                        frame_width as i32,
                        frame_height as i32,
                        0,
                        GL_RGBA,
                        GL_UNSIGNED_BYTE,
                        ptr::null(),
                    );
                }
            }
            if unsafe { epoxy_glGetError() } != GL_NO_ERROR {
                preparation_status = -34;
            } else {
                state.published_slot = 0;
                state.allocated_width = frame_width;
                state.allocated_height = frame_height;
                state.uploaded_generation = 0;
                state.imported_dma_buf_generation = 0;
            }
        }

        let destination_slot = (state.published_slot + 1) % TEXTURE_SLOT_COUNT;
        let destination_name = state.names[destination_slot];
        let started = Instant::now();
        let mut fence_fallback = false;
        let status = if preparation_status != 0 {
            preparation_status
        } else {
            unsafe {
                copy_dma_buf_to_texture(
                    frame,
                    destination_name,
                    state.allocated_width,
                    state.allocated_height,
                    &mut fence_fallback,
                )
            }
        };
        let copy_micros = started.elapsed().as_micros().min(u128::from(u64::MAX)) as u64;
        if status == 0 {
            state.published_slot = destination_slot;
            state.imported_dma_buf_generation = frame.generation;
            self.metrics
                .gl_name
                .store(destination_name, Ordering::Release);
        }
        self.publish_dma_buf_result(frame.generation, status, copy_micros, fence_fallback);

        if !previous_display.is_null() {
            unsafe {
                eglMakeCurrent(
                    previous_display,
                    previous_draw,
                    previous_read,
                    previous_context,
                )
            };
        } else {
            unsafe {
                eglMakeCurrent(
                    copy_display,
                    ptr::null_mut(),
                    ptr::null_mut(),
                    ptr::null_mut(),
                )
            };
        }
        unsafe { eglBindAPI(previous_api) };
        status
    }

    /// Atomically publishes diagnostics for the most recent copy attempt.
    ///
    /// The copy count advances only on success; timing and status are retained
    /// for failures so Dart-side diagnostics can distinguish “no frame yet”
    /// from import/copy errors.
    fn publish_dma_buf_result(
        &self,
        generation: u64,
        status: i32,
        copy_micros: u64,
        fallback: bool,
    ) {
        self.metrics
            .dma_buf_generation
            .store(generation, Ordering::Release);
        self.metrics
            .dma_buf_status
            .store(i64::from(status), Ordering::Release);
        self.metrics
            .dma_buf_last_copy_micros
            .store(copy_micros, Ordering::Release);
        self.metrics
            .dma_buf_max_copy_micros
            .fetch_max(copy_micros, Ordering::AcqRel);
        if status == 0 {
            self.metrics
                .dma_buf_copy_count
                .fetch_add(1, Ordering::AcqRel);
        }
        if fallback {
            self.metrics
                .dma_buf_fence_fallback_count
                .fetch_add(1, Ordering::AcqRel);
        }
    }
}

/// Imports the borrowed planes as an EGL image and blits into a GL texture.
///
/// The function translates WPE's legacy zero/one format aliases to DRM fourcc,
/// validates all plane metadata before constructing EGL attributes, and waits
/// for a destination fence before destroying the temporary import objects.
///
/// # Safety
///
/// A compatible EGL context must be current; `destination_name` must name a
/// texture in that context's share group; all populated frame file descriptors
/// must remain valid for the complete call. This function never assumes
/// ownership of those descriptors.
unsafe fn copy_dma_buf_to_texture(
    frame: &DmaBufFrame,
    destination_name: u32,
    destination_width: u32,
    destination_height: u32,
    fence_fallback: &mut bool,
) -> i32 {
    let display = unsafe { eglGetCurrentDisplay() };
    if display.is_null()
        || unsafe { eglGetCurrentContext() }.is_null()
        || !unsafe { epoxy_has_egl_extension(display, c"EGL_EXT_image_dma_buf_import".as_ptr()) }
    {
        return -10;
    }
    let drm_format = match frame.format {
        0 => DRM_FORMAT_ABGR8888,
        1 => DRM_FORMAT_ARGB8888,
        format => format,
    };
    let plane_count = frame.plane_count as usize;
    if !(1..=frame.fds.len()).contains(&plane_count)
        || drm_format == 0
        || frame.coded_width <= 0
        || frame.coded_height <= 0
        || frame.visible_width <= 0
        || frame.visible_height <= 0
        || (0..plane_count).any(|plane| {
            frame.fds[plane] < 0
                || frame.offsets[plane] > i32::MAX as u64
                || frame.strides[plane] == 0
                || frame.strides[plane] > i32::MAX as u32
        })
    {
        return -11;
    }
    if frame.visible_width as u32 != destination_width
        || frame.visible_height as u32 != destination_height
    {
        return -15;
    }

    let mut attributes = vec![
        EGL_WIDTH,
        frame.coded_width,
        EGL_HEIGHT,
        frame.coded_height,
        EGL_LINUX_DRM_FOURCC_EXT,
        drm_format as i32,
    ];
    let supports_modifiers = unsafe {
        epoxy_has_egl_extension(display, c"EGL_EXT_image_dma_buf_import_modifiers".as_ptr())
    };
    for plane in 0..plane_count {
        attributes.extend_from_slice(&[
            EGL_DMA_BUF_PLANE_FD_ATTRIBUTES[plane],
            frame.fds[plane],
            EGL_DMA_BUF_PLANE_OFFSET_ATTRIBUTES[plane],
            frame.offsets[plane] as i32,
            EGL_DMA_BUF_PLANE_PITCH_ATTRIBUTES[plane],
            frame.strides[plane] as i32,
        ]);
        if supports_modifiers {
            attributes.extend_from_slice(&[
                EGL_DMA_BUF_PLANE_MODIFIER_LO_ATTRIBUTES[plane],
                frame.modifier as u32 as i32,
                EGL_DMA_BUF_PLANE_MODIFIER_HI_ATTRIBUTES[plane],
                (frame.modifier >> 32) as u32 as i32,
            ]);
        }
    }
    attributes.push(EGL_NONE);
    let image = unsafe {
        epoxy_eglCreateImageKHR(
            display,
            ptr::null_mut(),
            EGL_LINUX_DMA_BUF_EXT,
            ptr::null_mut(),
            attributes.as_ptr(),
        )
    };
    if image.is_null() {
        return -12;
    }

    let mut previous_texture = 0;
    let mut previous_read_framebuffer = 0;
    let mut previous_draw_framebuffer = 0;
    unsafe {
        epoxy_glGetIntegerv(GL_TEXTURE_BINDING_2D, &mut previous_texture);
        epoxy_glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &mut previous_read_framebuffer);
        epoxy_glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &mut previous_draw_framebuffer);
    }

    let mut source_texture = 0;
    let mut read_framebuffer = 0;
    let mut draw_framebuffer = 0;
    unsafe {
        epoxy_glGenTextures(1, &mut source_texture);
        epoxy_glBindTexture(GL_TEXTURE_2D, source_texture);
        epoxy_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        epoxy_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        epoxy_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        epoxy_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        epoxy_glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, image);

        epoxy_glGenFramebuffers(1, &mut read_framebuffer);
        epoxy_glBindFramebuffer(GL_READ_FRAMEBUFFER, read_framebuffer);
        epoxy_glFramebufferTexture2D(
            GL_READ_FRAMEBUFFER,
            GL_COLOR_ATTACHMENT0,
            GL_TEXTURE_2D,
            source_texture,
            0,
        );
        epoxy_glGenFramebuffers(1, &mut draw_framebuffer);
        epoxy_glBindFramebuffer(GL_DRAW_FRAMEBUFFER, draw_framebuffer);
        epoxy_glFramebufferTexture2D(
            GL_DRAW_FRAMEBUFFER,
            GL_COLOR_ATTACHMENT0,
            GL_TEXTURE_2D,
            destination_name,
            0,
        );
    }

    let mut status = 0;
    if unsafe { epoxy_glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) } != GL_FRAMEBUFFER_COMPLETE
        || unsafe { epoxy_glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) } != GL_FRAMEBUFFER_COMPLETE
    {
        status = -13;
    } else {
        unsafe {
            epoxy_glBlitFramebuffer(
                frame.visible_x,
                frame.visible_y,
                frame.visible_x + frame.visible_width,
                frame.visible_y + frame.visible_height,
                0,
                0,
                destination_width as i32,
                destination_height as i32,
                GL_COLOR_BUFFER_BIT,
                GL_NEAREST as u32,
            );
        }
        let fence = unsafe { epoxy_glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0) };
        if fence.is_null() {
            *fence_fallback = true;
            unsafe { epoxy_glFinish() };
        } else {
            unsafe { epoxy_glFlush() };
            let wait_status = unsafe {
                epoxy_glClientWaitSync(fence, GL_SYNC_FLUSH_COMMANDS_BIT, COPY_FENCE_TIMEOUT_NS)
            };
            unsafe { epoxy_glDeleteSync(fence) };
            if wait_status == GL_TIMEOUT_EXPIRED || wait_status == GL_WAIT_FAILED {
                *fence_fallback = true;
                unsafe { epoxy_glFinish() };
            }
            if wait_status == GL_WAIT_FAILED {
                status = -16;
            }
        }
        if unsafe { epoxy_glGetError() } != GL_NO_ERROR {
            status = -14;
        }
    }

    unsafe {
        epoxy_glBindFramebuffer(GL_READ_FRAMEBUFFER, previous_read_framebuffer as u32);
        epoxy_glBindFramebuffer(GL_DRAW_FRAMEBUFFER, previous_draw_framebuffer as u32);
        epoxy_glBindTexture(GL_TEXTURE_2D, previous_texture as u32);
        epoxy_glDeleteFramebuffers(1, &read_framebuffer);
        epoxy_glDeleteFramebuffers(1, &draw_framebuffer);
        epoxy_glDeleteTextures(1, &source_texture);
        epoxy_eglDestroyImageKHR(display, image);
    }
    status
}
