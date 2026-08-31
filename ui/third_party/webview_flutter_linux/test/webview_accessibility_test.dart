// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_linux/src/webview_accessibility.dart';

void main() {
  test('decodes a generation-scoped native accessibility snapshot', () {
    final tree = NativeAccessibilityTree.fromJson('''
      {
        "generation": 7,
        "available": true,
        "occupied": true,
        "truncated": false,
        "nodes": [
          {
            "index": 0,
            "parent": -1,
            "role": "document web",
            "name": "Example",
            "description": "",
            "value": "",
            "x": 0,
            "y": 0,
            "width": 800,
            "height": 450,
            "states": 4194432,
            "actions": []
          },
          {
            "index": 1,
            "parent": 0,
            "role": "push button",
            "name": "Continue",
            "description": "Advances to the next step",
            "value": "",
            "x": 20,
            "y": 30,
            "width": 120,
            "height": 40,
            "states": 12583040,
            "actions": ["press"]
          }
        ]
      }
    ''');

    expect(tree.generation, 7);
    expect(tree.available, isTrue);
    expect(tree.occupied, isTrue);
    expect(tree.truncated, isFalse);
    expect(tree.nodes, hasLength(2));
    expect(tree.nodes[1].parentIndex, 0);
    expect(tree.nodes[1].bounds.left, 20);
    expect(tree.nodes[1].actions, <String>['press']);
    expect(primaryAccessibilityActionIndex(tree.nodes[1]), 0);
  });

  test('rejects nodes that precede their native parent', () {
    expect(
      () => NativeAccessibilityTree.fromJson('''
        {
          "generation": 1,
          "available": true,
          "occupied": true,
          "truncated": false,
          "nodes": [{
            "index": 0,
            "parent": 0,
            "role": "text",
            "name": "bad",
            "description": "",
            "value": "",
            "x": 0,
            "y": 0,
            "width": 1,
            "height": 1,
            "states": 0,
            "actions": []
          }]
        }
      '''),
      throwsFormatException,
    );
  });

  test('maps AT-SPI state bits without treating adjacent bits as present', () {
    final node = NativeAccessibilityNode(
      index: 0,
      parentIndex: -1,
      role: 'check box',
      name: 'Remember me',
      description: '',
      value: '',
      bounds: const Rect.fromLTWH(0, 0, 20, 20),
      states:
          (1 << NativeAccessibilityState.checked.wireValue) |
          (1 << NativeAccessibilityState.enabled.wireValue),
      actions: const <String>['toggle'],
    );

    expect(node.hasState(NativeAccessibilityState.checked), isTrue);
    expect(node.hasState(NativeAccessibilityState.enabled), isTrue);
    expect(node.hasState(NativeAccessibilityState.editable), isFalse);
    expect(accessibilityRoleIsCheckable(node.role), isTrue);
  });

  test('prefers semantic click actions over native fallback order', () {
    final node = NativeAccessibilityNode(
      index: 0,
      parentIndex: -1,
      role: 'link',
      name: 'Details',
      description: '',
      value: '',
      bounds: const Rect.fromLTWH(0, 0, 80, 20),
      states: 0,
      actions: const <String>['show-menu', 'jump', 'click'],
    );

    expect(primaryAccessibilityActionIndex(node), 2);
  });

  test('converts UTF-16 selection offsets to AT-SPI scalar offsets', () {
    const text = 'A😀éZ';

    expect(utf16OffsetToAccessibilityOffset(text, 0), 0);
    expect(utf16OffsetToAccessibilityOffset(text, 1), 1);
    expect(utf16OffsetToAccessibilityOffset(text, 2), 1);
    expect(utf16OffsetToAccessibilityOffset(text, 3), 2);
    expect(utf16OffsetToAccessibilityOffset(text, text.length), 5);
  });
}
