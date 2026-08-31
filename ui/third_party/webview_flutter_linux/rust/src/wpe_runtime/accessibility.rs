// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Native WPE accessibility snapshots and AT-SPI actions.
//!
//! WebKit publishes its remote accessibility tree through a WPE ATK socket.
//! This module owns platform-thread socket discovery, immutable snapshots,
//! generation checks, and the action ABI used by Flutter semantics. The
//! sibling `accessibility_worker` module owns every blocking remote object and
//! D-Bus operation so accessibility cannot freeze Flutter input or rendering.

use super::prelude::*;
use std::time::{Duration, Instant};

const ACCESSIBILITY_FAILURE_BACKOFF: Duration = Duration::from_secs(2);

/// Stable, serializable properties of one node in WebKit's native AT-SPI tree.
///
/// `object_identity` participates in change detection so a navigation that
/// replaces a node with an equivalent-looking object still invalidates stale
/// semantic actions. Bounds use WPE window coordinates, which share the
/// WebView surface's logical coordinate space.
#[derive(Clone, PartialEq)]
pub(super) struct AccessibilityNodeMetadata {
    pub(super) object_identity: Vec<u8>,
    pub(super) parent_index: i32,
    pub(super) role: Vec<u8>,
    pub(super) name: Vec<u8>,
    pub(super) description: Vec<u8>,
    pub(super) value: Vec<u8>,
    pub(super) x: i32,
    pub(super) y: i32,
    pub(super) width: i32,
    pub(super) height: i32,
    pub(super) states: u64,
    pub(super) actions: Vec<Vec<u8>>,
}

/// Latest bounded mirror of the web process's AT-SPI tree.
#[derive(Default)]
pub(super) struct AccessibilitySnapshot {
    generation: u64,
    available: bool,
    occupied: bool,
    truncated: bool,
    json: Vec<u8>,
    node_count: usize,
    next_request_id: u64,
    pending_request_id: Option<u64>,
    requested_plug_id: Vec<u8>,
    retry_after: Option<Instant>,
}

/// Copies the plug identifier published by WPE's occupied ATK socket.
fn accessibility_plug_id(accessible: *mut WpeViewAccessible) -> Vec<u8> {
    let socket = accessible.cast::<AtkSocketLayout>();
    let plug_id = unsafe { (*socket).embedded_plug_id };
    if plug_id.is_null() {
        return Vec::new();
    }
    unsafe { CStr::from_ptr(plug_id) }.to_bytes().to_vec()
}

/// Appends arbitrary UTF-8 bytes as one valid JSON string.
fn push_accessibility_json_string(output: &mut String, bytes: &[u8]) {
    output.push_str(&javascript_string_literal(&String::from_utf8_lossy(bytes)));
}

/// Serializes the immutable metadata copied from the native accessibility tree.
pub(super) fn accessibility_snapshot_json(
    generation: u64,
    available: bool,
    occupied: bool,
    truncated: bool,
    nodes: &[AccessibilityNodeMetadata],
) -> Vec<u8> {
    use std::fmt::Write;

    let mut output = String::with_capacity(nodes.len().saturating_mul(192));
    write!(
        output,
        "{{\"generation\":{generation},\"available\":{available},\"occupied\":{occupied},\"truncated\":{truncated},\"nodes\":["
    )
    .expect("writing to a String cannot fail");
    for (index, metadata) in nodes.iter().enumerate() {
        if index != 0 {
            output.push(',');
        }
        write!(
            output,
            "{{\"index\":{index},\"parent\":{},\"role\":",
            metadata.parent_index
        )
        .expect("writing to a String cannot fail");
        push_accessibility_json_string(&mut output, &metadata.role);
        output.push_str(",\"name\":");
        push_accessibility_json_string(&mut output, &metadata.name);
        output.push_str(",\"description\":");
        push_accessibility_json_string(&mut output, &metadata.description);
        output.push_str(",\"value\":");
        push_accessibility_json_string(&mut output, &metadata.value);
        write!(
            output,
            ",\"x\":{},\"y\":{},\"width\":{},\"height\":{},\"states\":{},\"actions\":[",
            metadata.x, metadata.y, metadata.width, metadata.height, metadata.states
        )
        .expect("writing to a String cannot fail");
        for (action_index, action) in metadata.actions.iter().enumerate() {
            if action_index != 0 {
                output.push(',');
            }
            push_accessibility_json_string(&mut output, action);
        }
        output.push_str("]}");
    }
    output.push_str("]}");
    output.into_bytes()
}

/// Exchanges immutable snapshots with the blocking AT-SPI worker.
///
/// Only `wpe_view_get_accessible`, `atk_socket_is_occupied`, and the socket's
/// already-owned plug identifier are read here. None of those operations cross
/// D-Bus. Tree traversal and actions remain on `webview-atspi`, so this FFI
/// call has bounded local work even when the web process is unresponsive.
fn refresh_accessibility_snapshot(
    handle: u64,
    native_view: &NativeView,
    requested_maximum: usize,
) -> u64 {
    let maximum = requested_maximum.clamp(1, MAX_ACCESSIBILITY_NODES);
    let accessible = native_view
        .runtime
        .borrow()
        .as_ref()
        .map(|runtime| unsafe { wpe_view_get_accessible(runtime.view) })
        .unwrap_or(std::ptr::null_mut());
    let available = !accessible.is_null();
    let occupied = available && unsafe { atk_socket_is_occupied(accessible.cast()) } != 0;
    let plug_id = if occupied {
        accessibility_plug_id(accessible)
    } else {
        Vec::new()
    };
    let mut current = native_view.accessibility.borrow_mut();
    let now = Instant::now();
    if let Some(response) = take_accessibility_response(handle) {
        let matches_pending = current.pending_request_id == Some(response.request_id)
            && current.requested_plug_id == plug_id;
        current.pending_request_id = None;
        if matches_pending {
            if response.failed {
                current.retry_after = Some(now + ACCESSIBILITY_FAILURE_BACKOFF);
            } else {
                current.generation = response.generation;
                current.available = response.available;
                current.occupied = response.occupied;
                current.truncated = response.truncated;
                current.node_count = response.node_count;
                current.json = response.json;
                current.retry_after = None;
            }
        }
    }

    let backing_off = current
        .retry_after
        .is_some_and(|retry_after| now < retry_after);
    if current.pending_request_id.is_none() && !backing_off {
        current.next_request_id = current.next_request_id.wrapping_add(1).max(1);
        let request_id = current.next_request_id;
        if request_accessibility_refresh(
            handle,
            request_id,
            current.generation,
            available,
            occupied,
            plug_id.clone(),
            maximum,
        ) {
            current.pending_request_id = Some(request_id);
            current.requested_plug_id = plug_id;
        } else {
            current.retry_after = Some(now + ACCESSIBILITY_FAILURE_BACKOFF);
        }
    }

    ensure_accessibility_snapshot(&mut current, available, occupied, occupied);
    current.generation
}

/// Publishes an initial or changed availability snapshot without remote nodes.
///
/// During a D-Bus backoff, preserving an existing populated snapshot avoids
/// making semantics flicker. A first failed refresh still needs valid JSON so
/// Dart can distinguish an occupied-but-temporarily-unresponsive tree from an
/// invalid native handle.
fn ensure_accessibility_snapshot(
    current: &mut AccessibilitySnapshot,
    available: bool,
    occupied: bool,
    truncated: bool,
) -> u64 {
    if !current.json.is_empty() {
        return current.generation;
    }
    current.generation = current.generation.wrapping_add(1).max(1);
    current.available = available;
    current.occupied = occupied;
    current.truncated = truncated;
    current.json =
        accessibility_snapshot_json(current.generation, available, occupied, truncated, &[]);
    current.generation
}

#[unsafe(no_mangle)]
/// Requests a bounded mirror of WebKit's native AT-SPI tree.
///
/// This returns the latest completed worker snapshot and queues at most one
/// later refresh. The returned generation changes only when availability,
/// occupancy, node identity, metadata, bounds, state, or actions change. Zero
/// denotes an invalid handle. Callers should request a refresh only while
/// Flutter semantics are enabled.
pub extern "C" fn webview_flutter_linux_wpe_accessibility_refresh(
    handle: u64,
    maximum_nodes: u32,
) -> u64 {
    native_view(handle).map_or(0, |view| {
        refresh_accessibility_snapshot(handle, &view, maximum_nodes as usize)
    })
}

#[unsafe(no_mangle)]
/// Returns the byte length of the current accessibility snapshot JSON.
pub extern "C" fn webview_flutter_linux_wpe_accessibility_json_length(handle: u64) -> usize {
    native_view(handle).map_or(0, |view| view.accessibility.borrow().json.len())
}

#[unsafe(no_mangle)]
/// Copies the current accessibility snapshot JSON into caller-owned memory.
///
/// # Safety
///
/// `destination` must address writable storage for at least
/// `destination_length` bytes. Empty snapshots are valid but still require a
/// non-null pointer so Dart can use one uniform allocation path.
pub unsafe extern "C" fn webview_flutter_linux_wpe_accessibility_copy_json(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    let Some(view) = native_view(handle) else {
        return -1;
    };
    let snapshot = view.accessibility.borrow();
    if destination.is_null()
        || destination_length < snapshot.json.len()
        || snapshot.json.len() > i32::MAX as usize
    {
        return -2;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(snapshot.json.as_ptr(), destination, snapshot.json.len())
    };
    snapshot.json.len() as i32
}

/// Validates a generation-scoped node before queuing remote worker work.
fn validate_accessibility_node(handle: u64, generation: u64, node_index: u32) -> i32 {
    let Some(view) = native_view(handle) else {
        return -1;
    };
    let snapshot = view.accessibility.borrow();
    if generation == 0 || snapshot.generation != generation {
        return -2;
    }
    if node_index as usize >= snapshot.node_count {
        return -3;
    }
    0
}

#[unsafe(no_mangle)]
/// Queues one action advertised by a generation-scoped native AT-SPI node.
///
/// A successful return means the worker accepted the command. The actual
/// cross-process call is deliberately asynchronous so an inaccessible web
/// process cannot freeze Flutter's platform thread.
pub extern "C" fn webview_flutter_linux_wpe_accessibility_do_action(
    handle: u64,
    generation: u64,
    node_index: u32,
    action_index: u32,
) -> i32 {
    let status = validate_accessibility_node(handle, generation, node_index);
    if status != 0 {
        return status;
    }
    if queue_accessibility_action(handle, generation, node_index as usize, action_index) {
        0
    } else {
        -4
    }
}

#[unsafe(no_mangle)]
/// Queues browser focus for one generation-scoped native AT-SPI component.
pub extern "C" fn webview_flutter_linux_wpe_accessibility_grab_focus(
    handle: u64,
    generation: u64,
    node_index: u32,
) -> i32 {
    let status = validate_accessibility_node(handle, generation, node_index);
    if status != 0 {
        return status;
    }
    if queue_accessibility_focus(handle, generation, node_index as usize) {
        0
    } else {
        -4
    }
}

#[unsafe(no_mangle)]
/// Replaces the contents of an editable generation-scoped AT-SPI node.
///
/// # Safety
///
/// `text` must point to readable NUL-terminated UTF-8 for this call.
pub unsafe extern "C" fn webview_flutter_linux_wpe_accessibility_set_text(
    handle: u64,
    generation: u64,
    node_index: u32,
    text: *const c_char,
) -> i32 {
    let text = match required_c_string(text) {
        Ok(text) => text,
        Err(status) => return status,
    };
    let status = validate_accessibility_node(handle, generation, node_index);
    if status != 0 {
        return status;
    }
    if queue_accessibility_text(handle, generation, node_index as usize, text.into_bytes()) {
        0
    } else {
        -4
    }
}

#[unsafe(no_mangle)]
/// Queues selection or caret offsets for a generation-scoped AT-SPI text node.
pub extern "C" fn webview_flutter_linux_wpe_accessibility_set_selection(
    handle: u64,
    generation: u64,
    node_index: u32,
    start_offset: i32,
    end_offset: i32,
) -> i32 {
    if start_offset < 0 || end_offset < 0 {
        return -4;
    }
    let status = validate_accessibility_node(handle, generation, node_index);
    if status != 0 {
        return status;
    }
    if queue_accessibility_selection(
        handle,
        generation,
        node_index as usize,
        start_offset,
        end_offset,
    ) {
        0
    } else {
        -5
    }
}

#[unsafe(no_mangle)]
/// Queues adjustment of a native AT-SPI value by its advertised increment.
pub extern "C" fn webview_flutter_linux_wpe_accessibility_adjust_value(
    handle: u64,
    generation: u64,
    node_index: u32,
    direction: i32,
) -> i32 {
    if direction != -1 && direction != 1 {
        return -4;
    }
    let status = validate_accessibility_node(handle, generation, node_index);
    if status != 0 {
        return status;
    }
    if queue_accessibility_value_adjustment(handle, generation, node_index as usize, direction) {
        0
    } else {
        -5
    }
}
