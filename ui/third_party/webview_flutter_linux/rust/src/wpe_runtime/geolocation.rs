// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Application-supplied geolocation for WPE's headless web context.
//!
//! WPE normally falls back to GeoClue when no application handles the
//! geolocation manager's `start` signal. Registering the Dart provider flips a
//! native flag: subsequent starts are claimed, copied into a bounded event
//! queue, and completed by explicit position or failure calls. With no Dart
//! provider registered, the signal returns `false` and preserves WPE's GeoClue
//! behavior.

use super::prelude::*;

const MAX_GEOLOCATION_EVENTS: usize = 32;
const GEOLOCATION_ALTITUDE: u32 = 1 << 0;
const GEOLOCATION_ALTITUDE_ACCURACY: u32 = 1 << 1;
const GEOLOCATION_HEADING: u32 = 1 << 2;
const GEOLOCATION_SPEED: u32 = 1 << 3;
const GEOLOCATION_OPTIONAL_MASK: u32 =
    GEOLOCATION_ALTITUDE | GEOLOCATION_ALTITUDE_ACCURACY | GEOLOCATION_HEADING | GEOLOCATION_SPEED;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct GeolocationEvent {
    active: bool,
    high_accuracy: bool,
}

thread_local! {
    /// Retains the process-wide manager and its signal closures once installed.
    static GEOLOCATION_MANAGER: RefCell<Option<glib::Object>> = const { RefCell::new(None) };
    static GEOLOCATION_PROVIDER_ENABLED: Cell<bool> = const { Cell::new(false) };
    static GEOLOCATION_ACTIVE: Cell<bool> = const { Cell::new(false) };
    static GEOLOCATION_EVENTS: RefCell<VecDeque<GeolocationEvent>> = const {
        RefCell::new(VecDeque::new())
    };
}

fn geolocation_manager_pointer() -> Option<*mut WebKitGeolocationManager> {
    let context = unsafe { webkit_web_context_get_default() };
    if context.is_null() {
        return None;
    }
    let manager = unsafe { webkit_web_context_get_geolocation_manager(context) };
    (!manager.is_null()).then_some(manager)
}

fn manager_high_accuracy(manager: *mut WebKitGeolocationManager) -> bool {
    unsafe { webkit_geolocation_manager_get_enable_high_accuracy(manager) != 0 }
}

fn enqueue_event(event: GeolocationEvent) {
    GEOLOCATION_EVENTS.with_borrow_mut(|events| {
        if events.back() == Some(&event) {
            return;
        }
        if events.len() == MAX_GEOLOCATION_EVENTS {
            events.pop_front();
        }
        events.push_back(event);
    });
}

/// Installs exactly one signal bridge on WPE's application-global manager.
fn ensure_geolocation_bridge() -> Result<*mut WebKitGeolocationManager, i32> {
    if let Some(manager) = GEOLOCATION_MANAGER.with_borrow(|manager| manager.clone()) {
        return Ok(
            ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&manager)
                .0
                .cast(),
        );
    }
    let manager = geolocation_manager_pointer().ok_or(-1)?;
    let manager_object: glib::Object = unsafe { from_glib_none(manager.cast()) };
    let manager_address = manager as usize;

    manager_object.connect_local("start", false, move |_| {
        let claimed = GEOLOCATION_PROVIDER_ENABLED.get();
        if claimed {
            GEOLOCATION_ACTIVE.set(true);
            let manager = manager_address as *mut WebKitGeolocationManager;
            enqueue_event(GeolocationEvent {
                active: true,
                high_accuracy: manager_high_accuracy(manager),
            });
        }
        Some(claimed.to_value())
    });

    manager_object.connect_local("stop", false, move |_| {
        if GEOLOCATION_ACTIVE.replace(false) {
            let manager = manager_address as *mut WebKitGeolocationManager;
            enqueue_event(GeolocationEvent {
                active: false,
                high_accuracy: manager_high_accuracy(manager),
            });
        }
        None
    });

    manager_object.connect_local("notify::enable-high-accuracy", false, move |_| {
        if GEOLOCATION_PROVIDER_ENABLED.get() && GEOLOCATION_ACTIVE.get() {
            let manager = manager_address as *mut WebKitGeolocationManager;
            enqueue_event(GeolocationEvent {
                active: true,
                high_accuracy: manager_high_accuracy(manager),
            });
        }
        None
    });

    GEOLOCATION_MANAGER.replace(Some(manager_object));
    Ok(manager)
}

#[derive(Clone, Copy)]
struct GeolocationPositionValues {
    latitude: f64,
    longitude: f64,
    accuracy: f64,
    optional_mask: u32,
    altitude: f64,
    altitude_accuracy: f64,
    heading: f64,
    speed: f64,
}

impl GeolocationPositionValues {
    fn is_valid(self) -> bool {
        self.latitude.is_finite()
            && (-90.0..=90.0).contains(&self.latitude)
            && self.longitude.is_finite()
            && (-180.0..=180.0).contains(&self.longitude)
            && self.accuracy.is_finite()
            && self.accuracy >= 0.0
            && self.optional_mask & !GEOLOCATION_OPTIONAL_MASK == 0
            && (self.optional_mask & GEOLOCATION_ALTITUDE == 0 || self.altitude.is_finite())
            && (self.optional_mask & GEOLOCATION_ALTITUDE_ACCURACY == 0
                || self.altitude_accuracy.is_finite() && self.altitude_accuracy >= 0.0)
            && (self.optional_mask & GEOLOCATION_HEADING == 0
                || self.heading.is_finite() && (0.0..360.0).contains(&self.heading))
            && (self.optional_mask & GEOLOCATION_SPEED == 0
                || self.speed.is_finite() && self.speed >= 0.0)
    }
}

#[unsafe(no_mangle)]
/// Enables the Dart provider or restores WPE's unclaimed GeoClue fallback.
pub extern "C" fn webview_flutter_linux_geolocation_set_provider_enabled(enabled: i32) -> i32 {
    let manager = match ensure_geolocation_bridge() {
        Ok(manager) => manager,
        Err(status) => return status,
    };
    let enabled = enabled != 0;
    GEOLOCATION_PROVIDER_ENABLED.set(enabled);
    if !enabled && GEOLOCATION_ACTIVE.replace(false) {
        unsafe {
            webkit_geolocation_manager_failed(
                manager,
                c"Application geolocation provider was disabled".as_ptr(),
            )
        };
    }
    if !enabled {
        GEOLOCATION_EVENTS.with_borrow_mut(VecDeque::clear);
    }
    0
}

#[unsafe(no_mangle)]
/// Returns the number of pending provider lifecycle events.
pub extern "C" fn webview_flutter_linux_geolocation_event_count() -> u32 {
    GEOLOCATION_EVENTS.with_borrow(|events| events.len().min(u32::MAX as usize) as u32)
}

#[unsafe(no_mangle)]
/// Returns one while the oldest event requests position updates.
pub extern "C" fn webview_flutter_linux_geolocation_event_active() -> i32 {
    GEOLOCATION_EVENTS
        .with_borrow(|events| events.front().map_or(-1, |event| i32::from(event.active)))
}

#[unsafe(no_mangle)]
/// Returns one when the oldest event requests high-accuracy updates.
pub extern "C" fn webview_flutter_linux_geolocation_event_high_accuracy() -> i32 {
    GEOLOCATION_EVENTS.with_borrow(|events| {
        events
            .front()
            .map_or(-1, |event| i32::from(event.high_accuracy))
    })
}

#[unsafe(no_mangle)]
/// Removes the oldest provider lifecycle event.
pub extern "C" fn webview_flutter_linux_geolocation_event_pop() -> i32 {
    GEOLOCATION_EVENTS.with_borrow_mut(|events| i32::from(events.pop_front().is_none()))
}

#[unsafe(no_mangle)]
/// Publishes one validated W3C geolocation position to every WPE view.
pub extern "C" fn webview_flutter_linux_geolocation_update_position(
    latitude: f64,
    longitude: f64,
    accuracy: f64,
    timestamp_seconds: u64,
    optional_mask: u32,
    altitude: f64,
    altitude_accuracy: f64,
    heading: f64,
    speed: f64,
) -> i32 {
    if !(GeolocationPositionValues {
        latitude,
        longitude,
        accuracy,
        optional_mask,
        altitude,
        altitude_accuracy,
        heading,
        speed,
    })
    .is_valid()
    {
        return -1;
    }
    if !GEOLOCATION_PROVIDER_ENABLED.get() || !GEOLOCATION_ACTIVE.get() {
        return -2;
    }
    let manager = match ensure_geolocation_bridge() {
        Ok(manager) => manager,
        Err(status) => return status,
    };
    let position = unsafe { webkit_geolocation_position_new(latitude, longitude, accuracy) };
    if position.is_null() {
        return -3;
    }
    unsafe {
        if timestamp_seconds != 0 {
            webkit_geolocation_position_set_timestamp(position, timestamp_seconds);
        }
        if optional_mask & GEOLOCATION_ALTITUDE != 0 {
            webkit_geolocation_position_set_altitude(position, altitude);
        }
        if optional_mask & GEOLOCATION_ALTITUDE_ACCURACY != 0 {
            webkit_geolocation_position_set_altitude_accuracy(position, altitude_accuracy);
        }
        if optional_mask & GEOLOCATION_HEADING != 0 {
            webkit_geolocation_position_set_heading(position, heading);
        }
        if optional_mask & GEOLOCATION_SPEED != 0 {
            webkit_geolocation_position_set_speed(position, speed);
        }
        webkit_geolocation_manager_update_position(manager, position);
        webkit_geolocation_position_free(position);
    }
    0
}

#[unsafe(no_mangle)]
/// Reports that the application provider cannot determine a position.
///
/// # Safety
///
/// `message` must point to readable NUL-terminated UTF-8 for this call.
pub unsafe extern "C" fn webview_flutter_linux_geolocation_failed(message: *const c_char) -> i32 {
    let message = match required_c_string(message) {
        Ok(message) if !message.is_empty() => message,
        _ => return -1,
    };
    if !GEOLOCATION_PROVIDER_ENABLED.get() || !GEOLOCATION_ACTIVE.get() {
        return -2;
    }
    let manager = match ensure_geolocation_bridge() {
        Ok(manager) => manager,
        Err(status) => return status,
    };
    let message = match CString::new(message) {
        Ok(message) => message,
        Err(_) => return -1,
    };
    unsafe { webkit_geolocation_manager_failed(manager, message.as_ptr()) };
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_required_and_optional_position_fields() {
        let valid = GeolocationPositionValues {
            latitude: 18.0179,
            longitude: -76.8099,
            accuracy: 12.0,
            optional_mask: GEOLOCATION_ALTITUDE | GEOLOCATION_HEADING,
            altitude: 14.0,
            altitude_accuracy: 0.0,
            heading: 359.9,
            speed: 0.0,
        };
        assert!(valid.is_valid());
        assert!(
            !GeolocationPositionValues {
                latitude: 91.0,
                ..valid
            }
            .is_valid()
        );
        assert!(
            !GeolocationPositionValues {
                accuracy: -1.0,
                ..valid
            }
            .is_valid()
        );
        assert!(
            !GeolocationPositionValues {
                optional_mask: GEOLOCATION_HEADING,
                heading: 360.0,
                ..valid
            }
            .is_valid()
        );
    }

    #[test]
    fn coalesces_duplicate_provider_events_and_bounds_the_queue() {
        GEOLOCATION_EVENTS.with_borrow_mut(VecDeque::clear);
        let started = GeolocationEvent {
            active: true,
            high_accuracy: false,
        };
        enqueue_event(started);
        enqueue_event(started);
        assert_eq!(webview_flutter_linux_geolocation_event_count(), 1);

        for index in 0..=MAX_GEOLOCATION_EVENTS {
            enqueue_event(GeolocationEvent {
                active: index.is_multiple_of(2),
                high_accuracy: false,
            });
        }
        assert!(webview_flutter_linux_geolocation_event_count() <= MAX_GEOLOCATION_EVENTS as u32);
        GEOLOCATION_EVENTS.with_borrow_mut(VecDeque::clear);
    }
}
