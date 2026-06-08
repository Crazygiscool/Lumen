import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/journal_entry.dart';
import '../core/providers.dart';
import '../utils/responsive.dart';
import '../widgets/quick_add_bar.dart';
import 'entry_view_screen.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  String _filter = 'all';

  Future<void> _deleteEntry(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ],
      ),
    );
    if (confirm == true) {
      ref.read(entriesProvider.notifier).deleteEntry(id);
    }
  }

  void _showContextMenu(BuildContext context, TapDownDetails details, String id) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        overlay.size.width - details.globalPosition.dx,
        overlay.size.height - details.globalPosition.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error, size: 20),
              const SizedBox(width: 8),
              const Text('Delete Task'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'delete') {
        _deleteEntry(id);
      }
    });
  }

  List<JournalEntry> _filterTasks(List<JournalEntry> tasks) {
    switch (_filter) {
      case 'today':
        final today = DateTime.now().toIso8601String().substring(0, 10);
        return tasks.where((e) => e.dueDate == today).toList();
      case 'upcoming':
        final today = DateTime.now().toIso8601String().substring(0, 10);
        return tasks
            .where((e) =>
                e.dueDate != null &&
                e.dueDate!.compareTo(today) > 0 &&
                e.status != 'done')
            .toList();
      case 'done':
        return tasks.where((e) => e.status == 'done').toList();
      default:
        return tasks;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allEntries = ref.watch(entriesProvider);
    final allTasks = allEntries.where((e) => e.kind == 'task').toList();
    final tasks = _filterTasks(allTasks);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final narrow = isNarrow(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: narrow ? null : AppBar(
        title: const Text('Tasks'),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: QuickAddBar(onSaved: () => ref.read(entriesProvider.notifier).refresh()),
          ),
          // Filter tabs
          Container(
            height: 50,
            padding: const EdgeInsets.only(bottom: 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildFilterChip('All', 'all'),
                _buildFilterChip('Today', 'today'),
                _buildFilterChip('Upcoming', 'upcoming'),
                _buildFilterChip('Done', 'done'),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.checklist, size: 64, color: cs.outlineVariant),
                        const SizedBox(height: 16),
                        Text(
                          _filter == 'all'
                              ? 'No tasks yet'
                              : 'No tasks in this view',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final entry = tasks[index];
                      final title = entry.displayTitle.isNotEmpty
                          ? entry.displayTitle
                          : entry.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: cs.outlineVariant, width: 1),
                          ),
                          child: GestureDetector(
                            onSecondaryTapDown: (details) =>
                                _showContextMenu(context, details, entry.id),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        EntryViewScreen(entry: entry)),
                              ),
                              onLongPress: () => _showContextMenu(context,
                                  TapDownDetails(globalPosition: Offset.zero),
                                  entry.id),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(title,
                                              style: theme.textTheme.titleSmall
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      letterSpacing: -0.2)),
                                        ),
                                        if (entry.priority != null)
                                          _PriorityBadge(
                                              priority: entry.priority!,
                                              cs: cs),
                                        if (entry.status != null)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(left: 8),
                                            child: _StatusChip(
                                                status: entry.status!, cs: cs),
                                          ),
                                      ],
                                    ),
                                    if (entry.dueDate != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Row(
                                          children: [
                                            Icon(Icons.calendar_today_outlined,
                                                size: 14, color: cs.primary),
                                            const SizedBox(width: 6),
                                            Text(entry.dueDate!,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    color:
                                                        cs.onSurfaceVariant)),
                                          ],
                                        ),
                                      ),
                                    if (entry.tags.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Wrap(
                                          spacing: 6,
                                          children: entry.tags
                                              .map((t) => Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: cs
                                                          .surfaceContainerHigh,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                    ),
                                                    child: Text('#$t',
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color: cs
                                                                .onSurfaceVariant)),
                                                  ))
                                              .toList(),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final String priority;
  final ColorScheme cs;
  const _PriorityBadge({required this.priority, required this.cs});

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      'high' => cs.error,
      'medium' => cs.primary,
      _ => cs.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(priority,
          style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final ColorScheme cs;
  const _StatusChip({required this.status, required this.cs});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'done' => const Color(0xFF4CAF50),
      'in_progress' => const Color(0xFF2196F3),
      _ => cs.outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(status.replaceAll('_', ' '),
          style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
