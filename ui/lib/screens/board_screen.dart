import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voo_kanban/voo_kanban.dart';

import '../core/models/journal_entry.dart';
import '../core/providers.dart';
import '../utils/responsive.dart';
import 'entry_view_screen.dart';

class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  List<KanbanLane<String>> _buildLanes(List<JournalEntry> tasks) {
    final statuses = ['todo', 'in_progress', 'done'];
    const statusLabels = {
      'todo': 'To Do',
      'in_progress': 'In Progress',
      'done': 'Done',
    };
    const statusIcons = {
      'todo': Icons.radio_button_unchecked,
      'in_progress': Icons.pending_actions,
      'done': Icons.check_circle_outline,
    };
    final statusColors = {
      'todo': Colors.grey,
      'in_progress': Colors.blue,
      'done': Colors.green,
    };

    return statuses.map((status) {
      final filtered =
          tasks.where((t) => (t.status ?? 'todo') == status).toList();
      return KanbanLane<String>(
        id: status,
        title: statusLabels[status]!,
        icon: statusIcons[status],
        color: statusColors[status],
        cards: filtered.asMap().entries.map((e) {
          final entry = e.value;
          return KanbanCard<String>(
            id: entry.id,
            data: entry.id,
            laneId: status,
            index: e.key,
          );
        }).toList(),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final allEntries = ref.watch(entriesProvider);
    final tasks = allEntries.where((e) => e.kind == 'task').toList();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final narrow = isNarrow(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: narrow ? null : AppBar(
        title: const Text('Kanban Board'),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.dashboard_outlined, size: 64, color: cs.outlineVariant),
                  const SizedBox(height: 16),
                  Text('Create tasks to populate the board',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
                ],
              ))
          : Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: _buildBoard(tasks, allEntries, cs, theme),
            ),
    );
  }

  Widget _buildBoard(
      List<JournalEntry> tasks, List<JournalEntry> allEntries, ColorScheme cs, ThemeData theme) {
    final entryMap = {for (final e in allEntries) e.id: e};
    final lanes = _buildLanes(tasks);

    return VooKanbanBoard<String>(
      lanes: lanes,
      config: const KanbanConfig(
        enableUndo: true,
        enableKeyboardNavigation: true,
        showCardCount: true,
        showWipLimitIndicators: true,
      ),
      cardBuilder: (context, card, isSelected) {
        final entry = entryMap[card.data];
        return Card(
          elevation: isSelected ? 4 : 0,
          color: isSelected ? cs.primaryContainer : cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? cs.primary : cs.outlineVariant,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry?.displayTitle.isNotEmpty == true
                      ? entry!.displayTitle
                      : card.data,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry != null && (entry.priority != null || entry.tags.isNotEmpty))
                  const SizedBox(height: 10),
                Row(
                  children: [
                    if (entry != null && entry.priority != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: (entry.priority == 'high' ? cs.error : cs.primary)
                              .withValues(alpha: 0.1),
                          border: Border.all(
                              color: (entry.priority == 'high' ? cs.error : cs.primary)
                                  .withValues(alpha: 0.5)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(entry.priority!,
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: entry.priority == 'high'
                                    ? cs.error
                                    : cs.primary)),
                      ),
                    const SizedBox(width: 4),
                    if (entry != null && entry.tags.isNotEmpty)
                      Expanded(
                        child: Wrap(
                          spacing: 2,
                          children: entry.tags
                              .take(2)
                              .map((t) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('#$t',
                                        style: TextStyle(
                                            fontSize: 9,
                                            color: cs.onSurfaceVariant)),
                                  ))
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
      onCardMoved: (card, fromLaneId, toLaneId, newIndex) {
        ref
            .read(entriesProvider.notifier)
            .setEntryStatus(card.data, toLaneId);
      },
      onCardTap: (card) {
        final entry = entryMap[card.data];
        if (entry != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => EntryViewScreen(entry: entry)),
          );
        }
      },
    );
  }
}
