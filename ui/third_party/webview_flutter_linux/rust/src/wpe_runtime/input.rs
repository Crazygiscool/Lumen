// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Flutter-to-WPE pointer, touch, trackpad, and keyboard event dispatch.
//!
//! This module owns the translation from Flutter's platform-neutral event
//! values to WPE event types, modifier masks, XKB keycodes, and XKB keysyms.
//! Keeping the translation beside the exported input ABI makes it possible to
//! audit input semantics without navigating browser lifecycle or rendering.

use super::{prelude::*, settings::record_scroll_lifecycle_input};

/// Translates Flutter/CEF-compatible modifier bits into WPE modifier bits.
///
/// The Dart side intentionally uses DOM/CEF-style flags. Keeping the mapping at
/// this boundary isolates WPE's bit layout from Flutter keyboard code.
fn wpe_modifiers(modifiers: u32) -> u32 {
    let mut result = 0;
    if modifiers & (1 << 2) != 0 {
        result |= WPE_MODIFIER_KEYBOARD_CONTROL;
    }
    if modifiers & (1 << 1) != 0 {
        result |= WPE_MODIFIER_KEYBOARD_SHIFT;
    }
    if modifiers & (1 << 3) != 0 {
        result |= WPE_MODIFIER_KEYBOARD_ALT;
    }
    if modifiers & (1 << 7) != 0 {
        result |= WPE_MODIFIER_KEYBOARD_META;
    }
    if modifiers & (1 << 0) != 0 {
        result |= WPE_MODIFIER_KEYBOARD_CAPS_LOCK;
    }
    if modifiers & (1 << 4) != 0 {
        result |= WPE_MODIFIER_POINTER_BUTTON1;
    }
    if modifiers & (1 << 5) != 0 {
        result |= WPE_MODIFIER_POINTER_BUTTON2;
    }
    if modifiers & (1 << 6) != 0 {
        result |= WPE_MODIFIER_POINTER_BUTTON3;
    }
    result
}

/// Converts Flutter's USB HID physical-key usage into the XKB keycode expected
/// by WPE (evdev code plus XKB's historical offset of eight).
pub(super) fn xkb_keycode_from_usb_hid(native_key_code: i32) -> u32 {
    let usage = native_key_code as u32;
    if usage >> 16 != 0x07 {
        return 0;
    }
    match usage & 0xffff {
        0x04 => 0x26,                                  // KeyA
        0x05 => 0x38,                                  // KeyB
        0x06 => 0x36,                                  // KeyC
        0x07 => 0x28,                                  // KeyD
        0x08 => 0x1a,                                  // KeyE
        0x09 => 0x29,                                  // KeyF
        0x0a => 0x2a,                                  // KeyG
        0x0b => 0x2b,                                  // KeyH
        0x0c => 0x1f,                                  // KeyI
        0x0d => 0x2c,                                  // KeyJ
        0x0e => 0x2d,                                  // KeyK
        0x0f => 0x2e,                                  // KeyL
        0x10 => 0x3a,                                  // KeyM
        0x11 => 0x39,                                  // KeyN
        0x12 => 0x20,                                  // KeyO
        0x13 => 0x21,                                  // KeyP
        0x14 => 0x18,                                  // KeyQ
        0x15 => 0x1b,                                  // KeyR
        0x16 => 0x27,                                  // KeyS
        0x17 => 0x1c,                                  // KeyT
        0x18 => 0x1e,                                  // KeyU
        0x19 => 0x37,                                  // KeyV
        0x1a => 0x19,                                  // KeyW
        0x1b => 0x35,                                  // KeyX
        0x1c => 0x1d,                                  // KeyY
        0x1d => 0x34,                                  // KeyZ
        0x1e..=0x26 => 0x0a + (usage & 0xffff) - 0x1e, // Digit1..9
        0x27 => 0x13,                                  // Digit0
        0x28 => 0x24,                                  // Enter
        0x29 => 0x09,                                  // Escape
        0x2a => 0x16,                                  // Backspace
        0x2b => 0x17,                                  // Tab
        0x2c => 0x41,                                  // Space
        0x2d => 0x14,                                  // Minus
        0x2e => 0x15,                                  // Equal
        0x2f => 0x22,                                  // BracketLeft
        0x30 => 0x23,                                  // BracketRight
        0x31 => 0x33,                                  // Backslash
        0x32 => 0x5e,                                  // IntlBackslash
        0x33 => 0x2f,                                  // Semicolon
        0x34 => 0x30,                                  // Quote
        0x35 => 0x31,                                  // Backquote
        0x36 => 0x3b,                                  // Comma
        0x37 => 0x3c,                                  // Period
        0x38 => 0x3d,                                  // Slash
        0x39 => 0x42,                                  // CapsLock
        0x3a..=0x43 => 0x43 + (usage & 0xffff) - 0x3a, // F1..F10
        0x44 => 0x5f,                                  // F11
        0x45 => 0x60,                                  // F12
        0x46 => 0x6b,                                  // PrintScreen
        0x47 => 0x4e,                                  // ScrollLock
        0x48 => 0x7f,                                  // Pause
        0x49 => 0x76,                                  // Insert
        0x4a => 0x6e,                                  // Home
        0x4b => 0x70,                                  // PageUp
        0x4c => 0x77,                                  // Delete
        0x4d => 0x73,                                  // End
        0x4e => 0x75,                                  // PageDown
        0x4f => 0x72,                                  // ArrowRight
        0x50 => 0x71,                                  // ArrowLeft
        0x51 => 0x74,                                  // ArrowDown
        0x52 => 0x6f,                                  // ArrowUp
        0x53 => 0x4d,                                  // NumLock
        0x54 => 0x6a,                                  // NumpadDivide
        0x55 => 0x3f,                                  // NumpadMultiply
        0x56 => 0x52,                                  // NumpadSubtract
        0x57 => 0x56,                                  // NumpadAdd
        0x58 => 0x68,                                  // NumpadEnter
        0x59 => 0x57,                                  // Numpad1
        0x5a => 0x58,                                  // Numpad2
        0x5b => 0x59,                                  // Numpad3
        0x5c => 0x53,                                  // Numpad4
        0x5d => 0x54,                                  // Numpad5
        0x5e => 0x55,                                  // Numpad6
        0x5f => 0x4f,                                  // Numpad7
        0x60 => 0x50,                                  // Numpad8
        0x61 => 0x51,                                  // Numpad9
        0x62 => 0x5a,                                  // Numpad0
        0x63 => 0x5b,                                  // NumpadDecimal
        0x64 => 0x5e,                                  // IntlBackslash
        0x65 => 0x87,                                  // ContextMenu
        0x67 => 0x7d,                                  // NumpadEqual
        0xe0 => 0x25,                                  // ControlLeft
        0xe1 => 0x32,                                  // ShiftLeft
        0xe2 => 0x40,                                  // AltLeft
        0xe3 => 0x85,                                  // MetaLeft
        0xe4 => 0x69,                                  // ControlRight
        0xe5 => 0x3e,                                  // ShiftRight
        0xe6 => 0x6c,                                  // AltRight
        0xe7 => 0x86,                                  // MetaRight
        _ => 0,
    }
}

/// Encodes a Unicode scalar as an XKB keysym.
///
/// Latin-1 values map directly; other scalars use XKB's `0x01000000 | codepoint`
/// convention. Invalid Unicode values return zero.
pub(super) fn unicode_to_xkb_keyval(character: u32) -> u32 {
    match character {
        0 => 0,
        1..=0xff => character,
        0x100..=0x10ffff => 0x0100_0000 | character,
        _ => 0,
    }
}

/// Chooses the XKB keysym for a Flutter key event.
///
/// Printable event text wins when present. Physical HID usages cover letters,
/// digits, and punctuation when shortcuts such as Ctrl+A suppress text. The
/// final Windows/DOM key-code table handles navigation and function keys.
pub(super) fn xkb_keyval(windows_key_code: i32, native_key_code: i32, character: u32) -> u32 {
    let character_keyval = unicode_to_xkb_keyval(character);
    if character_keyval != 0 {
        return character_keyval;
    }
    if (0x41..=0x5a).contains(&windows_key_code) {
        return windows_key_code as u32 + 0x20;
    }
    if (0x30..=0x39).contains(&windows_key_code) {
        return windows_key_code as u32;
    }
    match windows_key_code {
        0x08 => 0xff08, // Backspace
        0x09 => 0xff09, // Tab
        0x0d => 0xff0d, // Return
        0x10 => match native_key_code as u32 & 0xffff {
            0xe5 => 0xffe2,
            _ => 0xffe1,
        },
        0x11 => match native_key_code as u32 & 0xffff {
            0xe4 => 0xffe4,
            _ => 0xffe3,
        },
        0x12 => match native_key_code as u32 & 0xffff {
            0xe6 => 0xffea,
            _ => 0xffe9,
        },
        0x14 => 0xffe5,                                         // CapsLock
        0x1b => 0xff1b,                                         // Escape
        0x20 => 0x20,                                           // Space
        0x21 => 0xff55,                                         // PageUp
        0x22 => 0xff56,                                         // PageDown
        0x23 => 0xff57,                                         // End
        0x24 => 0xff50,                                         // Home
        0x25 => 0xff51,                                         // ArrowLeft
        0x26 => 0xff52,                                         // ArrowUp
        0x27 => 0xff53,                                         // ArrowRight
        0x28 => 0xff54,                                         // ArrowDown
        0x2d => 0xff63,                                         // Insert
        0x2e => 0xffff,                                         // Delete
        0x5b => 0xffeb,                                         // MetaLeft / SuperLeft
        0x5c => 0xffec,                                         // MetaRight / SuperRight
        0x70..=0x7b => 0xffbe + windows_key_code as u32 - 0x70, // F1..F12
        0x90 => 0xff7f,                                         // NumLock
        0x91 => 0xff14,                                         // ScrollLock
        _ => 0,
    }
}

/// Delivers one newly allocated WPE event and releases its caller reference.
///
/// # Safety
///
/// `view` must be live for the duration of the call. A non-null `event` must
/// have been created for that exact view and carry one reference owned by this
/// function. Null events are ignored because WPE constructors may fail.
unsafe fn dispatch_event(view: *mut WpeView, event: *mut WpeEvent) {
    if event.is_null() {
        return;
    }
    unsafe {
        wpe_view_event(view, event);
        wpe_event_unref(event);
    }
}

/// Converts GLib's signed microsecond clock to WPE's wrapping millisecond time.
///
/// WPE follows the conventional 32-bit input-event clock used by Wayland and
/// X11. Truncating the millisecond value therefore deliberately preserves the
/// low 32 bits when a machine has been running for more than roughly 49 days.
/// A negative value is not expected from GLib's monotonic clock, but mapping it
/// to zero keeps this pure boundary well-defined for tests and unusual hosts.
pub(super) const fn wpe_event_time_from_monotonic_micros(micros: i64) -> u32 {
    if micros <= 0 {
        0
    } else {
        (micros as u64 / 1_000) as u32
    }
}

/// Returns the current monotonic time in the unit and width required by WPE.
///
/// WPE accepts zero as “timestamp unavailable,” but WebKit then samples its
/// clock separately while converting each event. Supplying the source clock
/// directly preserves the temporal relationship between touch, precise-scroll,
/// pointer, and keyboard streams generated by this embedder.
fn wpe_event_time() -> u32 {
    // SAFETY: `g_get_monotonic_time` has no preconditions or owned result.
    wpe_event_time_from_monotonic_micros(unsafe { glib::ffi::g_get_monotonic_time() })
}

pub(super) fn wpe_pointer_move_event_type(pointer_transition: i32) -> Option<i32> {
    match pointer_transition {
        0 => Some(WPE_EVENT_POINTER_MOVE),
        1 => Some(WPE_EVENT_POINTER_LEAVE),
        2 => Some(WPE_EVENT_POINTER_ENTER),
        _ => None,
    }
}

#[unsafe(no_mangle)]
/// Sends an absolute pointer-move event in logical view coordinates.
pub extern "C" fn webview_flutter_linux_wpe_send_mouse_move(
    handle: u64,
    x: i32,
    y: i32,
    modifiers: u32,
    pointer_transition: i32,
) -> i32 {
    let Some(event_type) = wpe_pointer_move_event_type(pointer_transition) else {
        return -1;
    };
    with_view(handle, |view| {
        // SAFETY: event is created for this live view and consumed by event().
        let event = unsafe {
            wpe_event_pointer_move_new(
                event_type,
                view,
                WPE_INPUT_SOURCE_MOUSE,
                wpe_event_time(),
                wpe_modifiers(modifiers),
                x as f64,
                y as f64,
                0.0,
                0.0,
            )
        };
        unsafe { dispatch_event(view, event) };
    })
}

#[unsafe(no_mangle)]
/// Sends a pointer-button press or release.
///
/// Dart button indices `0..=2` are converted to WPE's `1..=3` numbering.
/// Press counts outside `1..=3` are rejected before constructing the event.
pub extern "C" fn webview_flutter_linux_wpe_send_mouse_button(
    handle: u64,
    x: i32,
    y: i32,
    modifiers: u32,
    button: u32,
    mouse_up: i32,
    click_count: i32,
) -> i32 {
    if button > 2 || !(1..=3).contains(&click_count) {
        return -1;
    }
    with_view(handle, |view| {
        let event_type = if mouse_up != 0 {
            WPE_EVENT_POINTER_UP
        } else {
            WPE_EVENT_POINTER_DOWN
        };
        let event = unsafe {
            wpe_event_pointer_button_new(
                event_type,
                view,
                WPE_INPUT_SOURCE_MOUSE,
                wpe_event_time(),
                wpe_modifiers(modifiers),
                button + 1,
                x as f64,
                y as f64,
                if mouse_up != 0 { 0 } else { click_count as u32 },
            )
        };
        unsafe { dispatch_event(view, event) };
    })
}

#[unsafe(no_mangle)]
/// Sends a discrete two-axis mouse-wheel event at the supplied position.
pub extern "C" fn webview_flutter_linux_wpe_send_mouse_wheel(
    handle: u64,
    x: i32,
    y: i32,
    modifiers: u32,
    delta_x: i32,
    delta_y: i32,
) -> i32 {
    let result = with_view(handle, |view| {
        let event = unsafe {
            wpe_event_scroll_new(
                view,
                WPE_INPUT_SOURCE_MOUSE,
                wpe_event_time(),
                wpe_modifiers(modifiers),
                delta_x as f64,
                delta_y as f64,
                0,
                0,
                x as f64,
                y as f64,
            )
        };
        unsafe { dispatch_event(view, event) };
    });
    if result == 0 {
        record_scroll_lifecycle_input(handle);
    }
    result
}

#[unsafe(no_mangle)]
/// Sends one precise touchpad-scroll update or its terminating stop event.
///
/// WPE uses the input source and `is_stop` bit to maintain a continuous
/// gesture stream. Keeping this separate from mouse-wheel input lets WebKit
/// apply touchpad-specific scrolling and momentum behavior.
pub extern "C" fn webview_flutter_linux_wpe_send_trackpad_scroll(
    handle: u64,
    x: i32,
    y: i32,
    modifiers: u32,
    delta_x: f64,
    delta_y: f64,
    is_stop: i32,
) -> i32 {
    let result = with_view(handle, |view| {
        let event = unsafe {
            wpe_event_scroll_new(
                view,
                WPE_INPUT_SOURCE_TOUCHPAD,
                wpe_event_time(),
                wpe_modifiers(modifiers),
                delta_x,
                delta_y,
                1,
                i32::from(is_stop != 0),
                x as f64,
                y as f64,
            )
        };
        unsafe { dispatch_event(view, event) };
    });
    if result == 0 {
        record_scroll_lifecycle_input(handle);
    }
    result
}

pub(super) fn wpe_touch_event_type(event_type: u32) -> Option<i32> {
    match event_type {
        0 => Some(WPE_EVENT_TOUCH_DOWN),
        1 => Some(WPE_EVENT_TOUCH_MOVE),
        2 => Some(WPE_EVENT_TOUCH_UP),
        3 => Some(WPE_EVENT_TOUCH_CANCEL),
        _ => None,
    }
}

#[unsafe(no_mangle)]
/// Sends a touchscreen contact event in logical view coordinates.
///
/// `event_type` uses the Dart bridge ordering `down`, `move`, `up`, `cancel`.
/// `sequence_id` remains stable for the lifetime of one Flutter pointer, which
/// allows WebKit to recognize scrolling and multi-touch gestures itself.
pub extern "C" fn webview_flutter_linux_wpe_send_touch(
    handle: u64,
    event_type: u32,
    modifiers: u32,
    sequence_id: u32,
    x: i32,
    y: i32,
) -> i32 {
    let Some(event_type) = wpe_touch_event_type(event_type) else {
        return -1;
    };
    let result = with_view(handle, |view| {
        let event = unsafe {
            wpe_event_touch_new(
                event_type,
                view,
                WPE_INPUT_SOURCE_TOUCHSCREEN,
                wpe_event_time(),
                wpe_modifiers(modifiers),
                sequence_id,
                x as f64,
                y as f64,
            )
        };
        unsafe { dispatch_event(view, event) };
    });
    if result == 0 {
        record_scroll_lifecycle_input(handle);
    }
    result
}

#[unsafe(no_mangle)]
/// Translates and sends a Flutter keyboard event to WPE.
///
/// Dart event types `0`, `1`, and `3` are key-down variants; `2` is key-up.
/// Modifier, USB HID, DOM Windows key code, and Unicode data are combined into
/// the XKB keycode/keysym pair expected by WPE.
pub extern "C" fn webview_flutter_linux_wpe_send_key(
    handle: u64,
    event_type: u32,
    modifiers: u32,
    windows_key_code: i32,
    native_key_code: i32,
    character: u32,
    _unmodified_character: u32,
) -> i32 {
    let event_type = match event_type {
        0 | 1 | 3 => WPE_EVENT_KEYBOARD_KEY_DOWN,
        2 => WPE_EVENT_KEYBOARD_KEY_UP,
        _ => return -1,
    };
    with_view(handle, |view| {
        let event = unsafe {
            wpe_event_keyboard_new(
                event_type,
                view,
                WPE_INPUT_SOURCE_KEYBOARD,
                wpe_event_time(),
                wpe_modifiers(modifiers),
                xkb_keycode_from_usb_hid(native_key_code),
                xkb_keyval(windows_key_code, native_key_code, character),
            )
        };
        unsafe { dispatch_event(view, event) };
    })
}
