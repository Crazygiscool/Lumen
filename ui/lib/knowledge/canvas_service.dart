import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/lumen_ffi.dart';

/// A canvas element: rectangle, ellipse, line, arrow, text, or freehand stroke.
@immutable
class CanvasElement {
  const CanvasElement({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.strokeColor,
    required this.fillColor,
    required this.strokeWidth,
    this.text,
    this.fontSize,
    this.points,
  });

  final String id;
  final String type; // rectangle, ellipse, line, arrow, text, freehand
  final double x;
  final double y;
  final double width;
  final double height;
  final Color strokeColor;
  final Color fillColor;
  final double strokeWidth;
  final String? text;
  final double? fontSize;
  final List<Offset>? points; // for freehand strokes

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'strokeColor': strokeColor.value.toRadixString(16).padLeft(8, '0'),
      'fillColor': fillColor.value.toRadixString(16).padLeft(8, '0'),
      'strokeWidth': strokeWidth,
      if (text != null) 'text': text,
      if (fontSize != null) 'fontSize': fontSize,
      if (points != null)
        'points': points!
            .map((p) => {'x': p.dx, 'y': p.dy})
            .toList(),
    };
  }

  factory CanvasElement.fromJson(Map<String, dynamic> j) => CanvasElement(
    id: j['id'] as String,
    type: j['type'] as String,
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    width: (j['width'] as num).toDouble(),
    height: (j['height'] as num).toDouble(),
    strokeColor: Color(int.parse('0x${j['strokeColor']}')),
    fillColor: Color(int.parse('0x${j['fillColor']}')),
    strokeWidth: (j['strokeWidth'] as num).toDouble(),
    text: j['text'] as String?,
    fontSize: (j['fontSize'] as num?)?.toDouble(),
    points: (j['points'] as List<dynamic>?)
        ?.map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
        .toList(),
  );
}

/// A canvas document: a collection of elements with metadata.
@immutable
class CanvasDocument {
  const CanvasDocument({
    required this.id,
    required this.title,
    required this.elements,
    required this.createdAt,
    required this.modifiedAt,
  });

  final String id;
  final String title;
  final List<CanvasElement> elements;
  final DateTime createdAt;
  final DateTime modifiedAt;

  Map<String, dynamic> toJson() {
    return {
      'type': 'excalidraw',
      'version': 2,
      'source': 'lumen',
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
      'elements': elements.map((e) => e.toJson()).toList(),
    };
  }

  factory CanvasDocument.fromJson(Map<String, dynamic> j) => CanvasDocument(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    elements: (j['elements'] as List<dynamic>? ?? const [])
        .map((e) => CanvasElement.fromJson(e as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(j['createdAt'] as String? ??
        DateTime.now().toIso8601String()),
    modifiedAt: DateTime.parse(j['modifiedAt'] as String? ??
        DateTime.now().toIso8601String()),
  );
}

/// Manages canvas documents in the vault.
class CanvasService {
  CanvasService(this._ffi);

  final LumenFfi _ffi;

  /// List all canvas documents in the vault.
  Future<List<CanvasDocument>> list() async {
    final data = _ffi.kb('canvas.list') as Map<String, dynamic>;
    final list = data['documents'] as List<dynamic>? ?? const [];
    return [
      for (final c in list)
        CanvasDocument.fromJson(c as Map<String, dynamic>),
    ];
  }

  /// Create a new canvas document.
  Future<CanvasDocument> create({
    required String title,
  }) async {
    final data = await _ffi.kb('canvas.create', {
      'title': title,
    });
    return CanvasDocument.fromJson(data as Map<String, dynamic>);
  }

  /// Save a canvas document.
  Future<void> save(CanvasDocument doc) async {
    await _ffi.kb('canvas.save', doc.toJson());
  }

  /// Delete a canvas document.
  Future<void> delete(String id) async {
    await _ffi.kb('canvas.delete', {'id': id});
  }
}

/// Provider for the canvas service.
final canvasServiceProvider = Provider<CanvasService>((ref) {
  return CanvasService(LumenFfi.instance);
});
