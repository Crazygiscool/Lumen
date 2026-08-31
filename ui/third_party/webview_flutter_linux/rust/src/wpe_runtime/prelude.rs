// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Shared implementation vocabulary for the WPE runtime modules.
//!
//! The runtime is split by browser capability, but those capabilities operate
//! on the same thread-affine view state and hand-written native ABI. Keeping
//! their common types here lets `wpe_runtime.rs` remain a readable module map
//! without making every capability import arbitrary sibling internals through
//! `super::*`.

pub(super) use std::{
    cell::{Cell, RefCell},
    collections::{HashMap, HashSet, VecDeque},
    ffi::{CStr, CString, c_char, c_void},
    mem,
    rc::{Rc, Weak},
    sync::{
        OnceLock,
        atomic::{AtomicBool, Ordering},
    },
};

pub(super) use glib::{
    prelude::*,
    translate::{FromGlib, ToGlibPtr, from_glib_full, from_glib_none},
};

pub(super) use crate::system_clipboard::{
    ClipboardSnapshot, MAX_CLIPBOARD_FORMATS, prioritized_formats,
};

pub(super) const MAX_NAVIGATION_EVENTS: usize = 256;
pub(super) const MAX_DOWNLOAD_EVENTS: usize = 256;
pub(super) const MAX_DOWNLOAD_REQUESTS: usize = 32;
pub(super) const MAX_ACCESSIBILITY_NODES: usize = 2048;
pub(super) const MAX_ACCESSIBILITY_ACTIONS: usize = 16;
pub(super) const MAX_ACCESSIBILITY_TEXT_BYTES: usize = 4096;

// WebKitGTK/WPE serializes session history as a public, versioned GVariant.
// Version 2 is the current format in the minimum supported WPE WebKit 2.52.
// A history item retains its native form body, which is the only public WPE
// API path capable of representing a POST main-frame navigation.
pub(super) const SESSION_STATE_TYPE_V2: &str = "(qa(s(ssssasmayxx(ii)dm(sa(uaysxmxmds))av)u)mu)";
pub(super) const BACK_FORWARD_LIST_ITEM_TYPE_V2: &str = "(s(ssssasmayxx(ii)dm(sa(uaysxmxmds))av)u)";

pub(super) const NAVIGATION_EVENT_STARTED: u32 = 1;
pub(super) const NAVIGATION_EVENT_REDIRECTED: u32 = 2;
pub(super) const NAVIGATION_EVENT_COMMITTED: u32 = 3;
pub(super) const NAVIGATION_EVENT_FINISHED: u32 = 4;
pub(super) const NAVIGATION_EVENT_PROGRESS: u32 = 5;
pub(super) const NAVIGATION_EVENT_RESOURCE_ERROR: u32 = 6;
pub(super) const NAVIGATION_EVENT_HTTP_ERROR: u32 = 7;
pub(super) const NAVIGATION_EVENT_WEB_PROCESS_TERMINATED: u32 = 8;

pub(super) const DOWNLOAD_EVENT_CREATED_DESTINATION: u32 = 1;
pub(super) const DOWNLOAD_EVENT_PROGRESS: u32 = 2;
pub(super) const DOWNLOAD_EVENT_FAILED: u32 = 3;
pub(super) const DOWNLOAD_EVENT_FINISHED: u32 = 4;

pub(super) const COOKIE_RESULT_SUCCESS: i32 = 0;
pub(super) const COOKIE_RESULT_ERROR: i32 = -1;
pub(super) const WEBSITE_DATA_RESULT_SUCCESS: i32 = 0;
pub(super) const WEBSITE_DATA_RESULT_ERROR: i32 = -1;

pub(super) const WPE_EVENT_POINTER_DOWN: i32 = 1;
pub(super) const WPE_EVENT_POINTER_UP: i32 = 2;
pub(super) const WPE_EVENT_POINTER_MOVE: i32 = 3;
pub(super) const WPE_EVENT_POINTER_ENTER: i32 = 4;
pub(super) const WPE_EVENT_POINTER_LEAVE: i32 = 5;
pub(super) const WPE_EVENT_KEYBOARD_KEY_DOWN: i32 = 7;
pub(super) const WPE_EVENT_KEYBOARD_KEY_UP: i32 = 8;
pub(super) const WPE_EVENT_TOUCH_DOWN: i32 = 9;
pub(super) const WPE_EVENT_TOUCH_UP: i32 = 10;
pub(super) const WPE_EVENT_TOUCH_MOVE: i32 = 11;
pub(super) const WPE_EVENT_TOUCH_CANCEL: i32 = 12;
pub(super) const WPE_INPUT_SOURCE_MOUSE: i32 = 0;
pub(super) const WPE_INPUT_SOURCE_KEYBOARD: i32 = 2;
pub(super) const WPE_INPUT_SOURCE_TOUCHSCREEN: i32 = 3;
pub(super) const WPE_INPUT_SOURCE_TOUCHPAD: i32 = 4;
pub(super) const WPE_AVAILABLE_INPUT_DEVICE_MOUSE: u32 = 1 << 0;
pub(super) const WPE_AVAILABLE_INPUT_DEVICE_KEYBOARD: u32 = 1 << 1;
pub(super) const WPE_AVAILABLE_INPUT_DEVICE_TOUCHSCREEN: u32 = 1 << 2;

pub(super) const WPE_MODIFIER_KEYBOARD_CONTROL: u32 = 1 << 0;
pub(super) const WPE_MODIFIER_KEYBOARD_SHIFT: u32 = 1 << 1;
pub(super) const WPE_MODIFIER_KEYBOARD_ALT: u32 = 1 << 2;
pub(super) const WPE_MODIFIER_KEYBOARD_META: u32 = 1 << 3;
pub(super) const WPE_MODIFIER_KEYBOARD_CAPS_LOCK: u32 = 1 << 4;
pub(super) const WPE_MODIFIER_POINTER_BUTTON1: u32 = 1 << 8;
pub(super) const WPE_MODIFIER_POINTER_BUTTON2: u32 = 1 << 9;
pub(super) const WPE_MODIFIER_POINTER_BUTTON3: u32 = 1 << 10;

pub(super) use super::accessibility::AccessibilitySnapshot;
pub(super) use super::accessibility_worker::{
    begin_accessibility_worker_view_discard, queue_accessibility_action, queue_accessibility_focus,
    queue_accessibility_selection, queue_accessibility_text, queue_accessibility_value_adjustment,
    request_accessibility_refresh, take_accessibility_response,
    take_accessibility_worker_view_discarded,
};
pub(super) use super::construction::*;
#[cfg(test)]
pub(super) use super::cursor::{CursorData, MAX_CURSOR_DIMENSION, custom_cursor_data};
pub(super) use super::cursor::{
    CursorSnapshot, install_headless_cursor_callbacks, register_cursor_view, unregister_cursor_view,
};
#[cfg(test)]
pub(super) use super::downloads::enqueue_download_event;
pub(super) use super::downloads::{
    DownloadEventSnapshot, DownloadRequestSnapshot, connect_downloads,
};
pub(super) use super::ffi_helpers::*;
#[cfg(test)]
pub(super) use super::input::{
    unicode_to_xkb_keyval, wpe_event_time_from_monotonic_micros, wpe_pointer_move_event_type,
    wpe_touch_event_type, xkb_keycode_from_usb_hid, xkb_keyval,
};
#[cfg(test)]
pub(super) use super::javascript::{
    JAVASCRIPT_RESULT_ERROR, JAVASCRIPT_RESULT_SUCCESS, enqueue_javascript_result,
    javascript_channel_wrapper, page_presentation_style,
};
pub(super) use super::javascript::{
    JavaScriptChannelRegistration, JavaScriptMessageSnapshot, JavaScriptResultSnapshot,
    install_navigation_frame_bridge, javascript_string_literal,
};
pub(super) use super::lifecycle::*;
pub(super) use super::menus::{
    ContextMenuSnapshot, OptionMenuSnapshot, connect_context_menu, connect_option_menu,
};
pub(super) use super::native_ffi::*;
pub(super) use super::navigation::{
    DeferredNavigationPolicy, NavigationEventSnapshot, NavigationFrameHint,
    connect_navigation_events, webview_uri,
};
#[cfg(test)]
pub(super) use super::navigation::{
    enqueue_navigation_event, post_history_item_variant, should_enqueue_main_frame_lifecycle,
};
pub(super) use super::notifications::{
    NotificationSnapshot, cancel_notifications, connect_notifications,
};
pub(super) use super::rendering::{WpeMetrics, connect_buffer_rendered};
#[cfg(test)]
pub(super) use super::requests::geolocation_permission_blocked;
pub(super) use super::requests::{
    FileChooserRequestSnapshot, HttpAuthRequestSnapshot, MAX_FILE_CHOOSER_VALUES,
    NavigationPolicyBackend, NavigationPolicyRequestSnapshot, PermissionRequestSnapshot,
    ScriptDialogRequestSnapshot, SslAuthErrorSnapshot, cancel_navigation_policy_backend,
    connect_file_chooser_requests, connect_http_auth_requests, connect_permission_requests,
    connect_permission_state_queries, connect_script_dialogs, connect_ssl_auth_errors,
    reply_web_process_navigation, use_policy_decision_with_media_policy,
};
#[cfg(test)]
pub(super) use super::requests::{host_from_https_uri, supports_username_password_authentication};
pub(super) use super::session::*;
pub(super) use super::state::*;
#[cfg(test)]
pub(super) use super::storage::*;
pub(super) use super::surface::*;
pub(super) use super::text_input::{InputMethodSnapshot, create_input_method_context};
#[cfg(test)]
pub(super) use super::text_input::{
    flutter_input_method_context, flutter_input_method_context_get_type,
    flutter_input_method_get_preedit,
};
pub(super) use super::web_process_extension::{
    PreparedNavigationPolicyGate, configure_web_process_extension, connect_web_process_frame_hints,
    discard_navigation_policy_gate, discard_request_header_handoff, prepare_navigation_policy_gate,
    prepare_request_header_handoff,
};
#[cfg(test)]
pub(super) use super::windows::{
    MAX_FULLSCREEN_EVENTS, MAX_POPUP_REQUESTS, enqueue_fullscreen_snapshot, enqueue_popup_snapshot,
};
pub(super) use super::windows::{
    PopupRequestSnapshot, connect_fullscreen_events, connect_popup_creation,
    enqueue_fullscreen_event,
};
