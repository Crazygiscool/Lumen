// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';

/// Browser-owned cursor state copied from the versioned native ABI.
sealed class NativeBrowserCursor {
  const NativeBrowserCursor({required this.generation});

  /// Monotonic native generation for this complete cursor snapshot.
  final int generation;
}

/// A standard cursor represented by WPE's platform cursor name.
final class NativeNamedBrowserCursor extends NativeBrowserCursor {
  const NativeNamedBrowserCursor({
    required super.generation,
    required this.name,
  });

  final String name;
}

/// A WebKit custom cursor represented as tightly packed BGRA8888 pixels.
final class NativeCustomBrowserCursor extends NativeBrowserCursor {
  const NativeCustomBrowserCursor({
    required super.generation,
    required this.width,
    required this.height,
    required this.hotspotX,
    required this.hotspotY,
    required this.pixels,
  });

  /// Physical pixel width supplied by WebKit.
  final int width;

  /// Physical pixel height supplied by WebKit.
  final int height;

  /// Physical X coordinate whose point must remain below the system pointer.
  final int hotspotX;

  /// Physical Y coordinate whose point must remain below the system pointer.
  final int hotspotY;

  /// Premultiplied BGRA8888 pixels with no row padding.
  final Uint8List pixels;
}

/// Maps every named cursor currently emitted by WPE WebKit to Flutter's Linux
/// system cursor vocabulary.
///
/// Unknown future names deliberately retain the ordinary arrow instead of
/// hiding the cursor or inventing behavior. Custom cursors do not use this
/// mapping; Flutter draws their pixels above the external texture.
MouseCursor flutterCursorForWpeName(String name) => switch (name) {
  'default' => SystemMouseCursors.basic,
  'crosshair' => SystemMouseCursors.precise,
  'pointer' => SystemMouseCursors.click,
  'text' => SystemMouseCursors.text,
  'wait' => SystemMouseCursors.wait,
  'help' => SystemMouseCursors.help,
  'move' => SystemMouseCursors.move,
  'e-resize' => SystemMouseCursors.resizeRight,
  'n-resize' => SystemMouseCursors.resizeUp,
  'ne-resize' => SystemMouseCursors.resizeUpRight,
  'nw-resize' => SystemMouseCursors.resizeUpLeft,
  's-resize' => SystemMouseCursors.resizeDown,
  'se-resize' => SystemMouseCursors.resizeDownRight,
  'sw-resize' => SystemMouseCursors.resizeDownLeft,
  'w-resize' => SystemMouseCursors.resizeLeft,
  'ns-resize' => SystemMouseCursors.resizeUpDown,
  'ew-resize' => SystemMouseCursors.resizeLeftRight,
  'nesw-resize' => SystemMouseCursors.resizeUpRightDownLeft,
  'nwse-resize' => SystemMouseCursors.resizeUpLeftDownRight,
  'col-resize' => SystemMouseCursors.resizeColumn,
  'row-resize' => SystemMouseCursors.resizeRow,
  'vertical-text' => SystemMouseCursors.verticalText,
  'cell' => SystemMouseCursors.cell,
  'context-menu' => SystemMouseCursors.contextMenu,
  'alias' => SystemMouseCursors.alias,
  'progress' => SystemMouseCursors.progress,
  'no-drop' => SystemMouseCursors.noDrop,
  'not-allowed' => SystemMouseCursors.forbidden,
  'copy' => SystemMouseCursors.copy,
  'none' => SystemMouseCursors.none,
  'zoom-in' => SystemMouseCursors.zoomIn,
  'zoom-out' => SystemMouseCursors.zoomOut,
  'grab' => SystemMouseCursors.grab,
  'grabbing' => SystemMouseCursors.grabbing,
  _ => SystemMouseCursors.basic,
};

/// Converts WebKit's physical custom-cursor geometry into the Flutter surface
/// rectangle whose hotspot remains fixed at [pointerPosition].
Rect logicalCustomCursorRect(
  NativeCustomBrowserCursor cursor,
  Offset pointerPosition,
  double deviceScaleFactor,
) {
  final scale = deviceScaleFactor.clamp(0.5, 4).toDouble();
  return Rect.fromLTWH(
    pointerPosition.dx - cursor.hotspotX / scale,
    pointerPosition.dy - cursor.hotspotY / scale,
    cursor.width / scale,
    cursor.height / scale,
  );
}
