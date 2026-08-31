// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_linux/src/webview_cursor.dart';

void main() {
  test('maps every cursor name emitted by WPE WebKit', () {
    final cursors = <String, MouseCursor>{
      'default': SystemMouseCursors.basic,
      'crosshair': SystemMouseCursors.precise,
      'pointer': SystemMouseCursors.click,
      'text': SystemMouseCursors.text,
      'wait': SystemMouseCursors.wait,
      'help': SystemMouseCursors.help,
      'move': SystemMouseCursors.move,
      'e-resize': SystemMouseCursors.resizeRight,
      'n-resize': SystemMouseCursors.resizeUp,
      'ne-resize': SystemMouseCursors.resizeUpRight,
      'nw-resize': SystemMouseCursors.resizeUpLeft,
      's-resize': SystemMouseCursors.resizeDown,
      'se-resize': SystemMouseCursors.resizeDownRight,
      'sw-resize': SystemMouseCursors.resizeDownLeft,
      'w-resize': SystemMouseCursors.resizeLeft,
      'ns-resize': SystemMouseCursors.resizeUpDown,
      'ew-resize': SystemMouseCursors.resizeLeftRight,
      'nesw-resize': SystemMouseCursors.resizeUpRightDownLeft,
      'nwse-resize': SystemMouseCursors.resizeUpLeftDownRight,
      'col-resize': SystemMouseCursors.resizeColumn,
      'row-resize': SystemMouseCursors.resizeRow,
      'vertical-text': SystemMouseCursors.verticalText,
      'cell': SystemMouseCursors.cell,
      'context-menu': SystemMouseCursors.contextMenu,
      'alias': SystemMouseCursors.alias,
      'progress': SystemMouseCursors.progress,
      'no-drop': SystemMouseCursors.noDrop,
      'not-allowed': SystemMouseCursors.forbidden,
      'copy': SystemMouseCursors.copy,
      'none': SystemMouseCursors.none,
      'zoom-in': SystemMouseCursors.zoomIn,
      'zoom-out': SystemMouseCursors.zoomOut,
      'grab': SystemMouseCursors.grab,
      'grabbing': SystemMouseCursors.grabbing,
    };

    for (final MapEntry(:key, :value) in cursors.entries) {
      expect(flutterCursorForWpeName(key), same(value), reason: key);
    }
    expect(
      flutterCursorForWpeName('future-wpe-cursor'),
      same(SystemMouseCursors.basic),
    );
  });

  test('positions a custom cursor by its scaled hotspot', () {
    final cursor = NativeCustomBrowserCursor(
      generation: 7,
      width: 32,
      height: 48,
      hotspotX: 8,
      hotspotY: 12,
      pixels: Uint8List(32 * 48 * 4),
    );

    expect(
      logicalCustomCursorRect(cursor, const Offset(100, 80), 2),
      const Rect.fromLTWH(96, 74, 16, 24),
    );
  });
}
