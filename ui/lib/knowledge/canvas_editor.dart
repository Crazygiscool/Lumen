import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/lumen_ffi.dart';
import '../knowledge/canvas_service.dart';
import '../state/providers.dart';
import '../theme/lumen_colors.dart';

class CanvasEditor extends ConsumerStatefulWidget {
  const CanvasEditor({super.key, required this.path});

  final String path;

  @override
  ConsumerState<CanvasEditor> createState() => _CanvasEditorState();
}

class _CanvasEditorState extends ConsumerState<CanvasEditor> {
  CanvasDocument? _doc;
  CanvasElement? _selected;
  Offset? _startPoint;
  Offset? _currentPoint;
  List<Offset> _currentStroke = [];
  CanvasElementType _tool = CanvasElementType.rectangle;
  Color _strokeColor = Colors.black;
  Color _fillColor = Colors.transparent;
  double _strokeWidth = 2.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = ref.read(canvasServiceProvider);
    final docs = await service.list();
    final existing = docs.firstWhere(
      (d) => d.id == widget.path || d.title == widget.path,
      orElse: () => CanvasDocument(
        id: widget.path,
        title: widget.path,
        elements: const [],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      ),
    );
    if (mounted) setState(() => _doc = existing);
  }

  Future<void> _save() async {
    final doc = _doc;
    if (doc == null) return;
    final service = ref.read(canvasServiceProvider);
    await service.save(doc);
  }

  void _startStroke(Offset localPosition) {
    setState(() {
      _startPoint = localPosition;
      _currentPoint = localPosition;
      _currentStroke = [localPosition];
    });
  }

  void _updateStroke(Offset localPosition) {
    setState(() {
      _currentPoint = localPosition;
      _currentStroke.add(localPosition);
    });
  }

  void _endStroke() {
    if (_currentStroke.isEmpty) return;

    final minX = _currentStroke.map((p) => p.dx).reduce(math.min);
    final minY = _currentStroke.map((p) => p.dy).reduce(math.min);
    final maxX = _currentStroke.map((p) => p.dx).reduce(math.max);
    final maxY = _currentStroke.map((p) => p.dy).reduce(math.max);

    final element = CanvasElement(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: 'freehand',
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
      strokeColor: _strokeColor,
      fillColor: Colors.transparent,
      strokeWidth: _strokeWidth,
      points: List.from(_currentStroke),
    );

    setState(() {
      final doc = _doc;
      if (doc == null) return;
      _doc = doc.copyWith(elements: [...doc.elements, element]);
      _currentStroke = [];
      _startPoint = null;
      _currentPoint = null;
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Canvas Editor'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _save,
            tooltip: 'Save',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildToolbar(t),
          Expanded(
            child: GestureDetector(
              onPanStart: (details) => _startStroke(details.localPosition),
              onPanUpdate: (details) => _updateStroke(details.localPosition),
              onPanEnd: (_) => _endStroke(),
              child: CustomPaint(
                size: Size.infinite,
                painter: _CanvasPainter(
                  doc: _doc,
                  selected: _selected,
                  currentStroke: _currentStroke,
                  currentPoint: _currentPoint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(LumenPalette t) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: t.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: t.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          _toolButton(Icons.edit, _tool == CanvasElementType.rectangle, t,
              () => setState(() => _tool = CanvasElementType.rectangle)),
          _toolButton(Icons.crop, _tool == CanvasElementType.ellipse, t,
              () => setState(() => _tool = CanvasElementType.ellipse)),
          _toolButton(Icons.line_style, _tool == CanvasElementType.line, t,
              () => setState(() => _tool = CanvasElementType.line)),
          _toolButton(Icons.arrow_right, _tool == CanvasElementType.arrow, t,
              () => setState(() => _tool = CanvasElementType.arrow)),
          _toolButton(Icons.text_fields, _tool == CanvasElementType.text, t,
              () => setState(() => _tool = CanvasElementType.text)),
          _toolButton(Icons.format_align_center, _tool == CanvasElementType.freehand, t,
              () => setState(() => _tool = CanvasElementType.freehand)),
          const Spacer(),
          _colorPicker(_strokeColor, (c) => setState(() => _strokeColor = c)),
          const SizedBox(width: 8),
          _colorPicker(_fillColor, (c) => setState(() => _fillColor = c)),
          const SizedBox(width: 8),
          const Text('Width:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          DropdownButton<double>(
            value: _strokeWidth,
            items: [1, 2, 4, 6, 8]
                .map((w) => DropdownMenuItem(
                      value: w.toDouble(),
                      child: Text('$w'),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _strokeWidth = v!),
          ),
        ],
      ),
    );
  }

  Widget _toolButton(IconData icon, bool selected, LumenPalette t,
      VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, color: selected ? t.primary : null),
      onPressed: onPressed,
    );
  }

  Widget _colorPicker(Color color, ValueChanged<Color> onChanged) {
    return InkWell(
      onTap: () async {
        final picked = await showDialog<Color>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Pick a color'),
            content: Container(
              width: 200,
              height: 200,
              color: color,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, color),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, color),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.2)),
        ),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  final CanvasDocument? doc;
  final CanvasElement? selected;
  final List<Offset> currentStroke;
  final Offset? currentPoint;

  _CanvasPainter({
    this.doc,
    this.selected,
    this.currentStroke = const [],
    this.currentPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (currentStroke.isNotEmpty && currentPoint != null) {
      final paint = Paint()
        ..color = Colors.black
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawPoints(ui.PointMode.points, currentStroke, paint);
      canvas.drawLine(currentStroke.last, currentPoint!, paint);
    }

    final d = doc;
    if (d == null) return;

    for (final element in d.elements) {
      final isSelected = selected?.id == element.id;
      final paint = Paint()
        ..color = element.strokeColor
        ..strokeWidth = element.strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final rect = Rect.fromLTWH(
        element.x,
        element.y,
        element.width,
        element.height,
      );

      switch (element.type) {
        case 'rectangle':
          canvas.drawRect(rect, paint..style = PaintingStyle.stroke);
          canvas.drawRect(rect, Paint()
            ..color = element.fillColor
            ..style = PaintingStyle.fill);
          break;
        case 'ellipse':
          canvas.drawOval(rect, paint..style = PaintingStyle.stroke);
          canvas.drawOval(rect, Paint()
            ..color = element.fillColor
            ..style = PaintingStyle.fill);
          break;
        case 'line':
          canvas.drawLine(
            Offset(element.x, element.y),
            Offset(element.x + element.width, element.y + element.height),
            paint,
          );
          break;
        case 'arrow':
          canvas.drawLine(
            Offset(element.x, element.y),
            Offset(element.x + element.width, element.y + element.height),
            paint,
          );
          break;
        case 'text':
          final textSpan = TextSpan(
            text: element.text ?? '',
            style: TextStyle(
              color: element.strokeColor,
              fontSize: element.fontSize ?? 16,
            ),
          );
          final textPainter = TextPainter(
            text: textSpan,
            textDirection: TextDirection.ltr,
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(element.x, element.y));
          break;
        case 'freehand':
          if (element.points != null && element.points!.isNotEmpty) {
            final path = Path();
            path.moveTo(element.points!.first.dx,
                element.points!.first.dy);
            for (var i = 1; i < element.points!.length; i++) {
              path.lineTo(element.points![i].dx, element.points![i].dy);
            }
            canvas.drawPath(path, paint);
          }
          break;
      }

      if (isSelected) {
        canvas.drawRect(rect.inflate(4), Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      }
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter old) {
    return old.doc != doc ||
        old.selected != selected ||
        old.currentStroke != currentStroke ||
        old.currentPoint != currentPoint;
  }
}

enum CanvasElementType {
  rectangle,
  ellipse,
  line,
  arrow,
  text,
  freehand,
}
