import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voo_kanban/voo_kanban.dart';

import '../core/models/journal_entry.dart';
import '../core/providers.dart';
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
      'done': Icons.check_circle,
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Board')),
      body: tasks.isEmpty
          ? Center(
              child: Text('Create tasks to populate the board',
                  style: TextStyle(color: cs.onSurfaceVariant)))
          : _buildBoard(tasks, allEntries, cs),
    );
  }

  Widget _buildBoard(
      List<JournalEntry> tasks, List<JournalEntry> allEntries, ColorScheme cs) {
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
          color: isSelected ? cs.primaryContainer : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry?.displayTitle.isNotEmpty == true
                      ? entry!.displayTitle
                      : card.data,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry != null && entry.priority != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: entry.priority == 'high'
                                ? cs.error
                                : cs.outline),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(entry.priority!,
                          style: TextStyle(
                              fontSize: 9,
                              color: entry.priority == 'high'
                                  ? cs.error
                                  : cs.onSurfaceVariant)),
                    ),
                  ),
                if (entry != null && entry.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 2,
                      children: entry.tags
                          .take(3)
                          .map((t) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainer,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Text(t,
                                    style: TextStyle(
                                        fontSize: 8,
                                        color: cs.onSurfaceVariant)),
                              ))
                          .toList(),
                    ),
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
