import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/journal_entry.dart';
import '../core/providers.dart';
import '../widgets/quick_add_bar.dart';
import 'entry_view_screen.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  String _filter = 'all';

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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: Column(
        children: [
          QuickAddBar(onSaved: () => ref.read(entriesProvider.notifier).refresh()),
          // Filter tabs
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildFilterChip('All', 'all'),
                _buildFilterChip('Today', 'today'),
                _buildFilterChip('Upcoming', 'upcoming'),
                _buildFilterChip('Done', 'done'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Text(
                      _filter == 'all'
                          ? 'No tasks yet'
                          : 'No tasks in this view',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final entry = tasks[index];
                      final title = entry.displayTitle.isNotEmpty
                          ? entry.displayTitle
                          : entry.id;
                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    EntryViewScreen(entry: entry)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(title,
                                          style: const TextStyle(
                                              fontWeight:
                                                  FontWeight.w600)),
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
                                        Icon(Icons.event,
                                            size: 14,
                                            color: cs.onSurfaceVariant),
                                        const SizedBox(width: 4),
                                        Text(entry.dueDate!,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: cs.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                if (entry.tags.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Wrap(
                                      spacing: 4,
                                      children: entry.tags
                                          .map((t) => Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: cs.surfaceContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          4),
                                                  border: Border.all(
                                                      color:
                                                          cs.outlineVariant),
                                                ),
                                                child: Text(t,
                                                    style: TextStyle(
                                                        fontSize: 10,
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
