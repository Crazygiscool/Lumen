import 'package:flutter/material.dart';

import '../core/models/journal_entry.dart';

class GanttChart extends StatelessWidget {
  final List<JournalEntry> tasks;
  final double rowHeight;
  final double dayWidth;

  const GanttChart({
    super.key,
    required this.tasks,
    this.rowHeight = 32,
    this.dayWidth = 20,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sorted = List<JournalEntry>.from(tasks)
      ..sort((a, b) => (a.dueDate ?? '').compareTo(b.dueDate ?? ''));

    if (sorted.isEmpty) {
      return SizedBox(
        height: 100,
        child: Center(
          child: Text('No tasks with due dates',
              style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      );
    }

    // Determine date range
    final dates = sorted
        .map((t) => t.dueDate)
        .where((d) => d != null)
        .cast<String>()
        .toList();
    if (dates.isEmpty) return const SizedBox.shrink();

    dates.sort();
    final startDate = DateTime.tryParse(dates.first);
    final endDate = DateTime.tryParse(dates.last);
    if (startDate == null || endDate == null) return const SizedBox.shrink();

    final totalDays = endDate.difference(startDate).inDays + 1;
    final totalWidth = totalDays * dayWidth;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth + 120,
        height: sorted.length * rowHeight + 40,
        child: CustomPaint(
          painter: _GanttPainter(
            tasks: sorted,
            startDate: startDate,
            dayWidth: dayWidth,
            rowHeight: rowHeight,
            primaryColor: cs.primary,
            surfaceVariant: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _GanttPainter extends CustomPainter {
  final List<JournalEntry> tasks;
  final DateTime startDate;
  final double dayWidth;
  final double rowHeight;
  final Color primaryColor;
  final Color surfaceVariant;

  _GanttPainter({
    required this.tasks,
    required this.startDate,
    required this.dayWidth,
    required this.rowHeight,
    required this.primaryColor,
    required this.surfaceVariant,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final labelWidth = 120.0;
    final headerPaint = TextStyle(
      color: surfaceVariant,
      fontSize: 10,
    );

    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      final y = i * rowHeight + 40;

      // Task label
      final title = task.displayTitle.isNotEmpty ? task.displayTitle : task.id;
      final tp = TextPainter(
        text: TextSpan(text: title, style: headerPaint),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: labelWidth - 8);
      tp.paint(canvas, Offset(4, y + 8));

      // Bar
      if (task.dueDate != null) {
        final dueDate = DateTime.tryParse(task.dueDate!);
        if (dueDate != null) {
          final daysFromStart = dueDate.difference(startDate).inDays;
          final barX = labelWidth + daysFromStart * dayWidth;
          final barColor = task.status == 'done'
              ? const Color(0xFF4CAF50)
              : primaryColor;

          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(barX, y + 8, dayWidth * 1.5, rowHeight - 16),
              const Radius.circular(4),
            ),
            Paint()..color = barColor.withValues(alpha: 0.7),
          );
        }
      }
    }

  }

  @override
  bool shouldRepaint(covariant _GanttPainter oldDelegate) => true;
}
