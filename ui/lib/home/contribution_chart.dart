import 'package:flutter/material.dart';

import '../journal/journal_service.dart';
import '../theme/lumen_colors.dart';

/// A GitHub-style contribution calendar: one column per week, one cell per
/// day, shaded by the number of journal entries written that day.
class ContributionChart extends StatelessWidget {
  const ContributionChart({super.key, required this.activity, this.weeks = 26});

  final JournalActivity activity;
  final int weeks;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final today = DateTime.now();
    final todayMid = DateTime(today.year, today.month, today.day);
    // Start at the beginning of the week containing (today - weeks*7).
    final start =
        todayMid.subtract(Duration(days: (weeks * 7) + todayMid.weekday - 1));

    final days = <DateTime>[];
    for (var i = 0; i < weeks * 7; i++) {
      days.add(start.add(Duration(days: i)));
    }

    Color shade(int count) {
      if (count <= 0) return t.hairline;
      if (count == 1) return t.primaryContainer.withValues(alpha: 0.45);
      if (count == 2) return t.primaryContainer.withValues(alpha: 0.7);
      return t.primary;
    }

    const cell = 12.0;
    const gap = 3.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${activity.total} entries in the last year',
                style: TextStyle(fontSize: 12, color: t.onSurfaceVariant),
              ),
              const Spacer(),
              for (final level in [0, 1, 2, 3])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Container(
                    width: cell,
                    height: cell,
                    decoration: BoxDecoration(
                      color: shade(level),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: cell,
            child: Row(
              children: [
                for (var w = 0; w < weeks; w++)
                  Padding(
                    padding: const EdgeInsets.only(right: gap),
                    child: Column(
                      children: [
                        for (var d = 0; d < 7; d++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: gap),
                            child: Tooltip(
                              message: _tooltip(days[w * 7 + d]),
                              child: Container(
                                width: cell,
                                height: cell,
                                decoration: BoxDecoration(
                                  color: shade(activity.countFor(days[w * 7 + d])),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _tooltip(DateTime day) {
    final count = activity.countFor(day);
    final label =
        '${_months[day.month]} ${day.day}, ${day.year}';
    if (count == 0) return '$label — no entries';
    return '$label — $count ${count == 1 ? 'entry' : 'entries'}';
  }

  static const _months = {
    1: 'Jan', 2: 'Feb', 3: 'Mar', 4: 'Apr', 5: 'May', 6: 'Jun',
    7: 'Jul', 8: 'Aug', 9: 'Sep', 10: 'Oct', 11: 'Nov', 12: 'Dec',
  };
}
