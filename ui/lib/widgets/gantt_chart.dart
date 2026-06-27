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
    final labelWidth = 120.0;
    final headerHeight = 24.0;
    final totalWidth = totalDays * dayWidth;
    final totalHeight = sorted.length * rowHeight + headerHeight;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: labelWidth + totalWidth,
        height: totalHeight,
        child: CustomPaint(
          painter: _GanttPainter(
            tasks: sorted,
            startDate: startDate,
            endDate: endDate,
            dayWidth: dayWidth,
            rowHeight: rowHeight,
            labelWidth: labelWidth,
            headerHeight: headerHeight,
            primaryColor: cs.primary,
            surfaceVariant: cs.onSurfaceVariant,
            surfaceColor: cs.surfaceContainerHighest,
            outlineColor: cs.outlineVariant,
            doneColor: const Color(0xFF4CAF50),
          ),
        ),
      ),
    );
  }
}

class _GanttPainter extends CustomPainter {
  final List<JournalEntry> tasks;
  final DateTime startDate;
  final DateTime endDate;
  final double dayWidth;
  final double rowHeight;
  final double labelWidth;
  final double headerHeight;
  final Color primaryColor;
  final Color surfaceVariant;
  final Color surfaceColor;
  final Color outlineColor;
  final Color doneColor;

  _GanttPainter({
    required this.tasks,
    required this.startDate,
    required this.endDate,
    required this.dayWidth,
    required this.rowHeight,
    required this.labelWidth,
    required this.headerHeight,
    required this.primaryColor,
    required this.surfaceVariant,
    required this.surfaceColor,
    required this.outlineColor,
    required this.doneColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawDateHeaders(canvas);
    _drawTaskBars(canvas);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final totalDays = endDate.difference(startDate).inDays + 1;
    final gridPaint = Paint()
      ..color = outlineColor.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Vertical grid lines (weekly emphasis)
    for (var d = 0; d < totalDays; d++) {
      final x = labelWidth + d * dayWidth;
      final date = startDate.add(Duration(days: d));
      if (date.weekday == DateTime.monday) {
        canvas.drawLine(
          Offset(x, headerHeight),
          Offset(x, size.height),
          Paint()
            ..color = outlineColor.withValues(alpha: 0.5)
            ..strokeWidth = 0.5,
        );
      }
    }

    // Horizontal grid lines
    for (var i = 0; i <= tasks.length; i++) {
      final y = headerHeight + i * rowHeight;
      canvas.drawLine(
        Offset(labelWidth, y),
        Offset(size.width, y),
        gridPaint,
      );
    }
  }

  void _drawDateHeaders(Canvas canvas) {
    final totalDays = endDate.difference(startDate).inDays + 1;
    final textStyle = TextStyle(
      color: surfaceVariant,
      fontSize: 9,
    );

    // Separator line below header
    canvas.drawLine(
      Offset(0, headerHeight),
      Offset(labelWidth + totalDays * dayWidth, headerHeight),
      Paint()
        ..color = outlineColor.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    // Day-of-month labels
    for (var d = 0; d < totalDays; d++) {
      final date = startDate.add(Duration(days: d));
      final x = labelWidth + d * dayWidth + dayWidth / 2;

      final tp = TextPainter(
        text: TextSpan(
          text: '${date.day}',
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, headerHeight / 2 - tp.height / 2));

      // Weekend shading
      if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
        canvas.drawRect(
          Rect.fromLTWH(
            labelWidth + d * dayWidth,
            headerHeight,
            dayWidth,
            tasks.length * rowHeight,
          ),
          Paint()..color = surfaceColor.withValues(alpha: 0.15),
        );
      }
    }

    // Month labels (draw at first occurrence of each month)
    final monthsDrawn = <String>{};
    for (var d = 0; d < totalDays; d++) {
      final date = startDate.add(Duration(days: d));
      final monthKey = '${date.year}-${date.month}';
      if (!monthsDrawn.contains(monthKey)) {
        monthsDrawn.add(monthKey);
        final months = [
          '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        final x = labelWidth + d * dayWidth;
        final monthTp = TextPainter(
          text: TextSpan(
            text: '${months[date.month]} ${date.year}',
            style: TextStyle(
              color: surfaceVariant,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        monthTp.paint(canvas, Offset(x + 2, 2));
      }
    }
  }

  void _drawTaskBars(Canvas canvas) {
    final labelStyle = TextStyle(
      color: surfaceVariant,
      fontSize: 10,
    );

    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      final y = headerHeight + i * rowHeight;

      // Task label
      final title = task.displayTitle.isNotEmpty ? task.displayTitle : task.id;
      final tp = TextPainter(
        text: TextSpan(text: title, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: labelWidth - 8);
      tp.paint(canvas, Offset(4, y + rowHeight / 2 - tp.height / 2));

      // Bar
      if (task.dueDate != null) {
        final dueDate = DateTime.tryParse(task.dueDate!);
        if (dueDate != null) {
          final daysFromStart = dueDate.difference(startDate).inDays;
          final barX = labelWidth + daysFromStart * dayWidth;

          // Status color
          Color barColor;
          switch (task.status) {
            case 'done':
              barColor = doneColor;
            case 'in_progress':
              barColor = primaryColor;
            default:
              barColor = surfaceVariant;
          }

          final barWidth = dayWidth * 1.5;
          final barHeight = rowHeight - 12;
          final barY = y + (rowHeight - barHeight) / 2;

          final rrect = RRect.fromRectAndRadius(
            Rect.fromLTWH(barX, barY, barWidth, barHeight),
            const Radius.circular(3),
          );
          canvas.drawRRect(rrect, Paint()..color = barColor.withValues(alpha: 0.7));

          // Today indicator
          final today = DateTime.now();
          if (dueDate.year == today.year &&
              dueDate.month == today.month &&
              dueDate.day == today.day) {
            canvas.drawRRect(
              rrect,
              Paint()
                ..color = primaryColor
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5,
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GanttPainter oldDelegate) => true;
}
