import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

class StreakWidget extends ConsumerWidget {
  const StreakWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(entriesProvider);
    final streak = ref.read(entriesProvider.notifier).getStreak();
    final cs = Theme.of(context).colorScheme;

    if (streak == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department,
              size: 16, color: cs.primary),
          const SizedBox(width: 4),
          Text(
            '$streak',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: cs.primary,
              fontFamily: 'Geist',
            ),
          ),
          const SizedBox(width: 2),
          Text(
            streak == 1 ? 'day' : 'days',
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
              fontFamily: 'Geist',
            ),
          ),
        ],
      ),
    );
  }
}
