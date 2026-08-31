// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Direct, bounded access to WebKit's remote AT-SPI objects.
//!
//! WPE exposes an ATK socket locally, but the accessible tree behind that
//! socket belongs to the sandboxed WebProcess. The socket's plug identifier is
//! an AT-SPI bus name and object path. This module talks to those objects using
//! the protocol published by `at-spi2-core`, rather than wrapping them in
//! `libatspi` proxies.
//!
//! The distinction is important for process isolation. A WebProcess can exit
//! between any two accessibility calls. GIO reports that as an ordinary D-Bus
//! error, while the corresponding `libatspi` proxy teardown has historically
//! crashed inside `libatspi` when the remote process disappeared. Every call
//! here has a short timeout and all returned values are copied into Rust-owned
//! data before control returns to the worker.

use super::accessibility::AccessibilityNodeMetadata;
use super::prelude::*;
use gio::{BusType, DBusCallFlags, DBusConnection, DBusConnectionFlags};
use glib::{ToVariant, Variant};

const ACCESSIBILITY_DBUS_TIMEOUT_MILLISECONDS: i32 = 100;
const ACCESSIBILITY_BUS_NAME: &str = "org.a11y.Bus";
const ACCESSIBILITY_BUS_PATH: &str = "/org/a11y/bus";
const ACCESSIBILITY_BUS_INTERFACE: &str = "org.a11y.Bus";
const PROPERTIES_INTERFACE: &str = "org.freedesktop.DBus.Properties";
const ACCESSIBLE_INTERFACE: &str = "org.a11y.atspi.Accessible";
const ACTION_INTERFACE: &str = "org.a11y.atspi.Action";
const COMPONENT_INTERFACE: &str = "org.a11y.atspi.Component";
const EDITABLE_TEXT_INTERFACE: &str = "org.a11y.atspi.EditableText";
const TEXT_INTERFACE: &str = "org.a11y.atspi.Text";
const VALUE_INTERFACE: &str = "org.a11y.atspi.Value";

/// An owned reference to one remote accessible object.
///
/// AT-SPI object references use the D-Bus signature `(so)`: a destination bus
/// name followed by an object path. Keeping those two strings, rather than a
/// native proxy, makes node lifetime independent of WebProcess lifetime.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub(super) struct AccessibilityRemoteNode {
    bus_name: String,
    object_path: String,
}

impl AccessibilityRemoteNode {
    /// Parses the plug identifier copied from WPE's occupied ATK socket.
    pub(super) fn from_plug_id(plug_id: &[u8]) -> Option<Self> {
        let separator = plug_id.windows(2).position(|window| window == b":/")?;
        let bus_name = std::str::from_utf8(&plug_id[..separator]).ok()?;
        let object_path = std::str::from_utf8(&plug_id[separator + 1..]).ok()?;
        Self::new(bus_name, object_path)
    }

    fn new(bus_name: &str, object_path: &str) -> Option<Self> {
        if bus_name.is_empty() || !object_path.starts_with('/') {
            return None;
        }
        Some(Self {
            bus_name: bus_name.to_owned(),
            object_path: object_path.to_owned(),
        })
    }

    fn child(&self, bus_name: String, object_path: String) -> Option<Self> {
        // Some AT-SPI implementations omit the destination when a returned
        // object is served by the same peer as its parent.
        let bus_name = if bus_name.is_empty() {
            self.bus_name.clone()
        } else {
            bus_name
        };
        Self::new(&bus_name, &object_path)
    }

    /// Stable bytes used to invalidate actions after a remote object changes.
    fn identity(&self) -> Vec<u8> {
        let mut identity = Vec::with_capacity(self.bus_name.len() + self.object_path.len() + 1);
        identity.extend_from_slice(self.bus_name.as_bytes());
        identity.push(0);
        identity.extend_from_slice(self.object_path.as_bytes());
        identity
    }
}

/// Immutable result of reading one remote object.
pub(super) struct AccessibilityRemoteSnapshot {
    pub(super) metadata: AccessibilityNodeMetadata,
    pub(super) children: Vec<AccessibilityRemoteNode>,
}

/// Worker-owned connection to the dedicated AT-SPI message bus.
pub(super) struct AccessibilityDbusClient {
    connection: DBusConnection,
}

impl AccessibilityDbusClient {
    /// Discovers the accessibility bus from the user's session bus and opens a
    /// private authenticated connection to it.
    pub(super) fn connect() -> Result<Self, ()> {
        let session =
            gio::bus_get_sync(BusType::Session, None::<&gio::Cancellable>).map_err(|_| ())?;
        let reply = session
            .call_sync(
                Some(ACCESSIBILITY_BUS_NAME),
                ACCESSIBILITY_BUS_PATH,
                ACCESSIBILITY_BUS_INTERFACE,
                "GetAddress",
                None,
                None,
                DBusCallFlags::NONE,
                ACCESSIBILITY_DBUS_TIMEOUT_MILLISECONDS,
                None::<&gio::Cancellable>,
            )
            .map_err(|_| ())?;
        let (address,) = reply.get::<(String,)>().ok_or(())?;
        let connection = DBusConnection::for_address_sync(
            &address,
            DBusConnectionFlags::AUTHENTICATION_CLIENT
                | DBusConnectionFlags::MESSAGE_BUS_CONNECTION,
            None,
            None::<&gio::Cancellable>,
        )
        .map_err(|_| ())?;
        Ok(Self { connection })
    }

    /// Reads all fields required by Flutter semantics plus the node's children.
    ///
    /// Child traversal is the only required remote result: without it a tree
    /// would silently appear complete while actually losing descendants.
    /// Optional interfaces and descriptive fields degrade to empty/default
    /// values, matching the permissive behavior of assistive-technology clients.
    pub(super) fn snapshot_node(
        &self,
        node: &AccessibilityRemoteNode,
        parent_index: i32,
    ) -> Result<AccessibilityRemoteSnapshot, ()> {
        let interfaces = self
            .method(node, ACCESSIBLE_INTERFACE, "GetInterfaces", None)
            .ok()
            .and_then(|reply| reply.get::<(Vec<String>,)>())
            .map(|(interfaces,)| interfaces)
            .unwrap_or_default();
        let children = self.children(node)?;
        let role = self.string_method(node, ACCESSIBLE_INTERFACE, "GetRoleName", None);
        let name = self.string_property(node, ACCESSIBLE_INTERFACE, "Name");
        let description = self.string_property(node, ACCESSIBLE_INTERFACE, "Description");
        let value = self.text_value(node, &interfaces, &role, &name);
        let (x, y, width, height) = self.bounds(node, &interfaces);
        let actions = self.actions(node, &interfaces);
        let states = self.states(node);

        Ok(AccessibilityRemoteSnapshot {
            metadata: AccessibilityNodeMetadata {
                object_identity: node.identity(),
                parent_index,
                role,
                name,
                description,
                value,
                x,
                y,
                width,
                height,
                states,
                actions,
            },
            children,
        })
    }

    pub(super) fn do_action(&self, node: &AccessibilityRemoteNode, index: u32) {
        let Ok(index) = i32::try_from(index) else {
            return;
        };
        let count = self
            .property(node, ACTION_INTERFACE, "NActions")
            .ok()
            .and_then(|value| value.get::<i32>())
            .unwrap_or(0);
        if index >= 0 && index < count {
            let _ = self.method(
                node,
                ACTION_INTERFACE,
                "DoAction",
                Some(&(index,).to_variant()),
            );
        }
    }

    pub(super) fn grab_focus(&self, node: &AccessibilityRemoteNode) {
        let _ = self.method(node, COMPONENT_INTERFACE, "GrabFocus", None);
    }

    pub(super) fn set_text(&self, node: &AccessibilityRemoteNode, text: &[u8]) {
        let Ok(text) = std::str::from_utf8(text) else {
            return;
        };
        let _ = self.method(
            node,
            EDITABLE_TEXT_INTERFACE,
            "SetTextContents",
            Some(&(text,).to_variant()),
        );
    }

    pub(super) fn set_selection(
        &self,
        node: &AccessibilityRemoteNode,
        start_offset: i32,
        end_offset: i32,
    ) {
        if start_offset == end_offset {
            let _ = self.method(
                node,
                TEXT_INTERFACE,
                "SetCaretOffset",
                Some(&(start_offset,).to_variant()),
            );
            return;
        }
        let selections = self
            .method(node, TEXT_INTERFACE, "GetNSelections", None)
            .ok()
            .and_then(|reply| reply.get::<(i32,)>())
            .map(|(count,)| count)
            .unwrap_or(0);
        let (method, parameters) = if selections > 0 {
            (
                "SetSelection",
                (0_i32, start_offset, end_offset).to_variant(),
            )
        } else {
            ("AddSelection", (start_offset, end_offset).to_variant())
        };
        let _ = self.method(node, TEXT_INTERFACE, method, Some(&parameters));
    }

    pub(super) fn adjust_value(&self, node: &AccessibilityRemoteNode, direction: i32) {
        let Some(current) = self
            .property(node, VALUE_INTERFACE, "CurrentValue")
            .ok()
            .and_then(|value| value.get::<f64>())
            .filter(|value| value.is_finite())
        else {
            return;
        };
        let increment = self
            .property(node, VALUE_INTERFACE, "MinimumIncrement")
            .ok()
            .and_then(|value| value.get::<f64>())
            .filter(|value| value.is_finite() && *value > 0.0)
            .unwrap_or(1.0);
        let next = current + increment * f64::from(direction);
        let parameters = (VALUE_INTERFACE, "CurrentValue", next.to_variant()).to_variant();
        let _ = self.method(node, PROPERTIES_INTERFACE, "Set", Some(&parameters));
    }

    fn children(&self, node: &AccessibilityRemoteNode) -> Result<Vec<AccessibilityRemoteNode>, ()> {
        let reply = self.method(node, ACCESSIBLE_INTERFACE, "GetChildren", None)?;
        let (children,) = reply.get::<(Vec<(String, String)>,)>().ok_or(())?;
        Ok(children
            .into_iter()
            .filter_map(|(bus_name, object_path)| node.child(bus_name, object_path))
            .collect())
    }

    fn bounds(
        &self,
        node: &AccessibilityRemoteNode,
        interfaces: &[String],
    ) -> (i32, i32, i32, i32) {
        if !supports_interface(interfaces, COMPONENT_INTERFACE) {
            return (0, 0, 0, 0);
        }
        self.method(
            node,
            COMPONENT_INTERFACE,
            "GetExtents",
            Some(&(1_u32,).to_variant()),
        )
        .ok()
        .and_then(|reply| reply.get::<((i32, i32, i32, i32),)>())
        .map(|((x, y, width, height),)| (x, y, width.max(0), height.max(0)))
        .unwrap_or((0, 0, 0, 0))
    }

    fn actions(&self, node: &AccessibilityRemoteNode, interfaces: &[String]) -> Vec<Vec<u8>> {
        if !supports_interface(interfaces, ACTION_INTERFACE) {
            return Vec::new();
        }
        let count = self
            .property(node, ACTION_INTERFACE, "NActions")
            .ok()
            .and_then(|value| value.get::<i32>())
            .unwrap_or(0)
            .clamp(0, MAX_ACCESSIBILITY_ACTIONS as i32);
        (0..count)
            .map(|index| {
                let parameters = (index,).to_variant();
                self.string_method(node, ACTION_INTERFACE, "GetName", Some(&parameters))
            })
            .collect()
    }

    fn text_value(
        &self,
        node: &AccessibilityRemoteNode,
        interfaces: &[String],
        role: &[u8],
        name: &[u8],
    ) -> Vec<u8> {
        if !supports_interface(interfaces, TEXT_INTERFACE) {
            return Vec::new();
        }
        let should_read = name.is_empty()
            || role == b"entry"
            || role == b"password text"
            || role == b"text"
            || role == b"static"
            || role == b"paragraph"
            || role == b"heading";
        if !should_read {
            return Vec::new();
        }
        self.string_method(
            node,
            TEXT_INTERFACE,
            "GetText",
            Some(&(0_i32, -1_i32).to_variant()),
        )
    }

    fn states(&self, node: &AccessibilityRemoteNode) -> u64 {
        self.method(node, ACCESSIBLE_INTERFACE, "GetState", None)
            .ok()
            .and_then(|reply| reply.get::<(Vec<u32>,)>())
            .map(|(words,)| state_words(&words))
            .unwrap_or(0)
    }

    fn string_property(
        &self,
        node: &AccessibilityRemoteNode,
        interface: &str,
        property: &str,
    ) -> Vec<u8> {
        self.property(node, interface, property)
            .ok()
            .and_then(|value| value.get::<String>())
            .map(|value| bounded_text(value.into_bytes()))
            .unwrap_or_default()
    }

    fn string_method(
        &self,
        node: &AccessibilityRemoteNode,
        interface: &str,
        method: &str,
        parameters: Option<&Variant>,
    ) -> Vec<u8> {
        self.method(node, interface, method, parameters)
            .ok()
            .and_then(|reply| reply.get::<(String,)>())
            .map(|(value,)| bounded_text(value.into_bytes()))
            .unwrap_or_default()
    }

    fn property(
        &self,
        node: &AccessibilityRemoteNode,
        interface: &str,
        property: &str,
    ) -> Result<Variant, ()> {
        let parameters = (interface, property).to_variant();
        let reply = self.method(node, PROPERTIES_INTERFACE, "Get", Some(&parameters))?;
        let (value,) = reply.get::<(Variant,)>().ok_or(())?;
        Ok(value)
    }

    fn method(
        &self,
        node: &AccessibilityRemoteNode,
        interface: &str,
        method: &str,
        parameters: Option<&Variant>,
    ) -> Result<Variant, ()> {
        self.connection
            .call_sync(
                Some(&node.bus_name),
                &node.object_path,
                interface,
                method,
                parameters,
                None,
                DBusCallFlags::NONE,
                ACCESSIBILITY_DBUS_TIMEOUT_MILLISECONDS,
                None::<&gio::Cancellable>,
            )
            .map_err(|_| ())
    }
}

fn supports_interface(interfaces: &[String], expected: &str) -> bool {
    interfaces.iter().any(|interface| interface == expected)
}

fn bounded_text(mut bytes: Vec<u8>) -> Vec<u8> {
    if bytes.len() <= MAX_ACCESSIBILITY_TEXT_BYTES {
        return bytes;
    }
    bytes.truncate(MAX_ACCESSIBILITY_TEXT_BYTES);
    while std::str::from_utf8(&bytes).is_err() {
        bytes.pop();
    }
    bytes
}

fn state_words(words: &[u32]) -> u64 {
    words
        .iter()
        .take(2)
        .enumerate()
        .fold(0_u64, |states, (index, word)| {
            states | (u64::from(*word) << (index * 32))
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_wpe_atspi_plug_identifiers_without_native_proxies() {
        let node = AccessibilityRemoteNode::from_plug_id(b":1.42:/org/a11y/atspi/accessible/7")
            .expect("valid plug identifier");
        assert_eq!(node.bus_name, ":1.42");
        assert_eq!(node.object_path, "/org/a11y/atspi/accessible/7");
        assert!(AccessibilityRemoteNode::from_plug_id(b"not-a-plug").is_none());
    }

    #[test]
    fn combines_the_two_atspi_state_bitset_words() {
        assert_eq!(
            state_words(&[0x8000_0001, 0x0000_0003]),
            0x0000_0003_8000_0001
        );
    }

    #[test]
    fn remote_identity_includes_both_destination_and_path() {
        let first = AccessibilityRemoteNode::new(":1.1", "/node/1").unwrap();
        let second = AccessibilityRemoteNode::new(":1.2", "/node/1").unwrap();
        assert_ne!(first.identity(), second.identity());
    }
}
