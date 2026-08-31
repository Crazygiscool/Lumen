// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:ui';

/// AT-SPI states mirrored from WebKit's native web-process accessibility tree.
///
/// The integer values are part of AT-SPI's stable C enum. Keeping the names
/// here makes Dart semantics mapping readable without exposing AT-SPI through
/// package's public API.
enum NativeAccessibilityState {
  checked(4),
  collapsed(5),
  editable(7),
  enabled(8),
  expandable(9),
  expanded(10),
  focusable(11),
  focused(12),
  multiline(17),
  selectable(22),
  selected(23),
  sensitive(24),
  showing(25),
  visible(30),
  indeterminate(32),
  required(33),
  invalidEntry(36),
  checkable(41),
  readOnly(43);

  const NativeAccessibilityState(this.wireValue);

  /// Bit position in the native AT-SPI state mask.
  final int wireValue;
}

/// One immutable node copied from WebKit's authoritative AT-SPI tree.
final class NativeAccessibilityNode {
  /// Creates a generation-scoped native accessibility node.
  NativeAccessibilityNode({
    required this.index,
    required this.parentIndex,
    required this.role,
    required this.name,
    required this.description,
    required this.value,
    required this.bounds,
    required this.states,
    required List<String> actions,
  }) : actions = List<String>.unmodifiable(actions);

  /// Index used by generation-scoped native actions.
  final int index;

  /// Parent index in this snapshot, or -1 for a document root.
  final int parentIndex;

  /// AT-SPI's stable, lower-case role name.
  final String role;

  /// Native accessible name, commonly derived from ARIA or a label element.
  final String name;

  /// Native accessible description or hint.
  final String description;

  /// Text/value exposed by AT-SPI when it adds information beyond [name].
  final String value;

  /// Logical bounds relative to the WebView surface.
  final Rect bounds;

  /// Complete AT-SPI state bit mask.
  final int states;

  /// Ordered native action names accepted by the node.
  final List<String> actions;

  /// Whether this node currently contains [state].
  bool hasState(NativeAccessibilityState state) =>
      states & (1 << state.wireValue) != 0;

  /// Whether this node is both visible and currently showing in its viewport.
  bool get isShowing =>
      hasState(NativeAccessibilityState.visible) &&
      hasState(NativeAccessibilityState.showing);
}

/// A bounded, generation-scoped copy of WebKit's native accessibility tree.
final class NativeAccessibilityTree {
  /// Creates an immutable accessibility tree snapshot.
  NativeAccessibilityTree({
    required this.generation,
    required this.available,
    required this.occupied,
    required this.truncated,
    required List<NativeAccessibilityNode> nodes,
  }) : nodes = List<NativeAccessibilityNode>.unmodifiable(nodes);

  /// Decodes the Rust bridge's validated JSON wire representation.
  factory NativeAccessibilityTree.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded case <String, Object?>{
      'generation': final int generation,
      'available': final bool available,
      'occupied': final bool occupied,
      'truncated': final bool truncated,
      'nodes': final List<Object?> rawNodes,
    }) {
      final nodes = <NativeAccessibilityNode>[];
      for (final rawNode in rawNodes) {
        if (rawNode case <String, Object?>{
          'index': final int index,
          'parent': final int parent,
          'role': final String role,
          'name': final String name,
          'description': final String description,
          'value': final String value,
          'x': final int x,
          'y': final int y,
          'width': final int width,
          'height': final int height,
          'states': final int states,
          'actions': final List<Object?> rawActions,
        }) {
          if (index != nodes.length || parent >= index) {
            throw const FormatException(
              'Accessibility nodes are not in parent-before-child order.',
            );
          }
          final actions = rawActions.whereType<String>().toList();
          if (actions.length != rawActions.length) {
            throw const FormatException(
              'Accessibility action names must be strings.',
            );
          }
          nodes.add(
            NativeAccessibilityNode(
              index: index,
              parentIndex: parent,
              role: role,
              name: name,
              description: description,
              value: value,
              bounds: Rect.fromLTWH(
                x.toDouble(),
                y.toDouble(),
                width.toDouble(),
                height.toDouble(),
              ),
              states: states,
              actions: actions,
            ),
          );
          continue;
        }
        throw const FormatException('Malformed accessibility node.');
      }
      return NativeAccessibilityTree(
        generation: generation,
        available: available,
        occupied: occupied,
        truncated: truncated,
        nodes: nodes,
      );
    }
    throw const FormatException('Malformed accessibility snapshot.');
  }

  /// Generation required by every native action on [nodes].
  final int generation;

  /// Whether this WPE build exposes a native accessible object.
  final bool available;

  /// Whether WebKit's web-process AT-SPI plug is bound to the WPE socket.
  final bool occupied;

  /// Whether the native tree exceeded the package's defensive node cap.
  final bool truncated;

  /// Nodes in native depth-first traversal order.
  final List<NativeAccessibilityNode> nodes;
}

/// Whether [role] should behave as a Flutter text field.
bool accessibilityRoleIsTextField(String role) =>
    role == 'entry' || role == 'password text';

/// Whether [role] represents a checkable control rather than a plain button.
bool accessibilityRoleIsCheckable(String role) =>
    role == 'check box' ||
    role == 'radio button' ||
    role == 'toggle button' ||
    role == 'check menu item' ||
    role == 'radio menu item';

/// Selects the native action that best represents Flutter's semantic tap.
int? primaryAccessibilityActionIndex(NativeAccessibilityNode node) {
  if (node.actions.isEmpty) return null;
  for (final preferred in const <String>[
    'click',
    'press',
    'activate',
    'jump',
    'open',
  ]) {
    final index = node.actions.indexOf(preferred);
    if (index >= 0) return index;
  }
  return 0;
}

/// Converts a Dart UTF-16 code-unit offset to AT-SPI's Unicode-scalar offset.
///
/// A malformed offset between a surrogate pair rounds down to the scalar's
/// start so an assistive technology cannot split one browser character.
int utf16OffsetToAccessibilityOffset(String value, int utf16Offset) {
  final target = utf16Offset.clamp(0, value.length);
  var codeUnits = 0;
  var scalars = 0;
  while (codeUnits < target) {
    final first = value.codeUnitAt(codeUnits);
    final isHighSurrogate = first >= 0xd800 && first <= 0xdbff;
    if (isHighSurrogate &&
        codeUnits + 1 < value.length &&
        value.codeUnitAt(codeUnits + 1) >= 0xdc00 &&
        value.codeUnitAt(codeUnits + 1) <= 0xdfff) {
      if (codeUnits + 1 >= target) break;
      codeUnits += 2;
    } else {
      codeUnits += 1;
    }
    scalars += 1;
  }
  return scalars;
}
