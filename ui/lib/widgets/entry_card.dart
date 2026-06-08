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
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant, width: 1),
      ),
      color: cs.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _KindBadge(kind: kind, cs: cs),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: tags
                      .map((t) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '#$t',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: cs.onSecondaryContainer,
                                fontFamily: 'Geist',
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  final String kind;
  final ColorScheme cs;

  const _KindBadge({required this.kind, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Text(
        kind.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: cs.onSurfaceVariant,
          letterSpacing: 0.5,
          fontFamily: 'Geist',
        ),
      ),
    );
  }
}
