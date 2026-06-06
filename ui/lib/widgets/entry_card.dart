import 'package:flutter/material.dart';

import 'status_badge.dart';

class EntryCard extends StatelessWidget {
  final String title;
  final String preview;
  final String kind;
  final String? status;
  final String? mood;
  final List<String> tags;
  final VoidCallback onTap;

  const EntryCard({
    super.key,
    required this.title,
    required this.preview,
    required this.kind,
    this.status,
    this.mood,
    this.tags = const [],
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final moodEmoji = switch (mood) {
      'happy' => '😊',
      'neutral' => '😐',
      'sad' => '😔',
      'angry' => '😡',
      'tired' => '😴',
      _ => null,
    };

    return Card(
      child: ListTile(
        title: Row(
          children: [
            if (status != null) ...[
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: StatusBadge(status!),
              ),
            ],
            if (moodEmoji != null) ...[
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(moodEmoji, style: const TextStyle(fontSize: 16)),
              ),
            ],
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: cs.outlineVariant, width: 1),
              ),
              child: Text(
                kind,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                  fontFamily: 'Geist',
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            if (tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 4,
                  children: tags
                      .map((t) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainer,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: cs.outlineVariant, width: 1),
                            ),
                            child: Text(
                              t,
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                                fontFamily: 'Geist',
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
          ],
        ),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}
