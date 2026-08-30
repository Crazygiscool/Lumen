import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../journal/journal_provider.dart';
import '../journal/journal_service.dart';
import '../theme/lumen_colors.dart';

/// Project manager: master list of projects (progress bars), with a detail
/// pane that switches between a task checklist, a kanban board (drag between
/// columns) and a gantt timeline.
class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  String? _selectedId;

  Project? _selected(List<Project> all) {
    if (all.isEmpty) return null;
    final match = all.where((p) => p.id == _selectedId);
    if (match.isNotEmpty) return match.first;
    final first = all.first;
    _selectedId = first.id;
    return first;
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final projects = ref.watch(projectsNotifierProvider);
    return projects.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Could not load projects: $e', style: TextStyle(color: t.error)),
      ),
      data: (all) {
        final selected = _selected(all);
        return Row(
          children: [
            SizedBox(
              width: 250,
              child: _ProjectRail(
                projects: all,
                selectedId: selected?.id,
                onSelect: (id) => setState(() => _selectedId = id),
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: t.hairline),
            Expanded(
              child: selected == null
                  ? const _EmptyDetail()
                  : _ProjectDetail(project: selected),
            ),
          ],
        );
      },
    );
  }
}

enum _DetailView { tasks, board, timeline }

class _ProjectRail extends ConsumerWidget {
  const _ProjectRail({
    required this.projects,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Project> projects;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LumenColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 8, 6),
          child: Row(
            children: [
              Text(
                'Projects',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: t.onSurface,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'New project',
                icon: const Icon(Icons.add, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: () => _newProject(context, ref),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: projects.isEmpty
              ? Center(
                  child: Text(
                    'No projects yet.\nCreate one to get started.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: t.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: projects.length,
                  itemBuilder: (context, i) {
                    final p = projects[i];
                    final selected = p.id == selectedId;
                    return InkWell(
                      onTap: () => onSelect(p.id),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: selected ? t.primaryContainer.withValues(alpha: 0.5) : null,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    p.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${p.done}/${p.total}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: t.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: p.progress,
                                minHeight: 5,
                                backgroundColor: t.hairline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _newProject(BuildContext context, WidgetRef ref) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _NewProjectDialog(),
    );
    if (title == null || title.trim().isEmpty) return;
    await ref.read(projectsNotifierProvider.notifier).upsert(
      Project(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title.trim(),
      ),
    );
    if (!context.mounted) return;
  }
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New project'),
      content: SizedBox(
        width: 340,
        child: TextField(
          controller: _ctl,
          autofocus: true,
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
          },
          decoration: const InputDecoration(
            labelText: 'Project title',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctl.text.trim()),
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.grid_view_outlined, size: 40, color: t.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            'Select or create a project to manage tasks.',
            style: TextStyle(fontSize: 13, color: t.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ProjectDetail extends ConsumerStatefulWidget {
  const _ProjectDetail({required this.project});

  final Project project;

  @override
  ConsumerState<_ProjectDetail> createState() => _ProjectDetailState();
}

class _ProjectDetailState extends ConsumerState<_ProjectDetail> {
  _DetailView _detailView = _DetailView.tasks;

  Project get project {
    final all = ref.watch(projectsNotifierProvider).asData?.value;
    if (all == null) return widget.project;
    return all.firstWhere(
      (p) => p.id == widget.project.id,
      orElse: () => widget.project,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final p = project;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${p.done} of ${p.total} done',
                style: TextStyle(fontSize: 12, color: t.onSurfaceVariant),
              ),
              IconButton(
                tooltip: 'Delete project',
                icon: const Icon(Icons.delete_outline, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Delete project?'),
                      content: Text('"${p.title}" and its tasks will be removed.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await ref.read(projectsNotifierProvider.notifier).remove(p.id);
                  }
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: p.progress,
              minHeight: 7,
              backgroundColor: t.hairline,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SegmentedButton<_DetailView>(
            segments: const [
              ButtonSegment(
                value: _DetailView.tasks,
                label: Text('Tasks'),
                icon: Icon(Icons.checklist, size: 16),
              ),
              ButtonSegment(
                value: _DetailView.board,
                label: Text('Board'),
                icon: Icon(Icons.view_kanban_outlined, size: 16),
              ),
              ButtonSegment(
                value: _DetailView.timeline,
                label: Text('Timeline'),
                icon: Icon(Icons.timeline, size: 16),
              ),
            ],
            selected: {_detailView},
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onSelectionChanged: (s) => setState(() => _detailView = s.first),
          ),
        ),
        const Divider(height: 20),
        Expanded(
          child: switch (_detailView) {
            _DetailView.tasks => _TasksView(project: p),
            _DetailView.board => _BoardView(project: p),
            _DetailView.timeline => _TimelineView(project: p),
          },
        ),
      ],
    );
  }
}

class _TasksView extends ConsumerStatefulWidget {
  const _TasksView({required this.project});

  final Project project;

  @override
  ConsumerState<_TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends ConsumerState<_TasksView> {
  final TextEditingController _ctl = TextEditingController();
  DateTime? _due;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now.add(const Duration(days: 1)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _due = picked);
  }

  void _add() {
    final text = _ctl.text.trim();
    if (text.isEmpty) return;
    ref.read(projectsNotifierProvider.notifier).addTask(
      widget.project.id,
      text,
      due: _due,
    );
    _ctl.clear();
    setState(() => _due = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final project = widget.project;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctl,
                  decoration: InputDecoration(
                    hintText: 'Add a task…',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    suffixIcon: IconButton(
                      tooltip: 'Set due date',
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      onPressed: _pickDue,
                    ),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _add,
                child: const Text('Add'),
              ),
            ],
          ),
        ),
        if (_due != null && _due?.isAfter(DateTime.now().subtract(const Duration(days: 1))) == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Due ${_formatDate(_due!)}',
                style: TextStyle(fontSize: 11.5, color: t.primary),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Expanded(
          child: project.tasks.isEmpty
              ? Center(
                  child: Text(
                    'No tasks yet.',
                    style: TextStyle(fontSize: 13, color: t.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  itemCount: project.tasks.length,
                  itemBuilder: (context, i) {
                    final task = project.tasks[i];
                    return _TaskRow(
                      projectId: project.id,
                      task: task,
                      onToggle: () => ref
                          .read(projectsNotifierProvider.notifier)
                          .toggle(project.id, task.id),
                      onDelete: () => ref
                          .read(projectsNotifierProvider.notifier)
                          .removeTask(project.id, task.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.projectId,
    required this.task,
    required this.onToggle,
    required this.onDelete,
  });

  final String projectId;
  final ProjectTask task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(
              task.done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 17,
              color: task.done ? t.success : t.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                task.text,
                style: TextStyle(
                  fontSize: 13.5,
                  color: task.done ? t.onSurfaceVariant : t.onSurface,
                  decoration: task.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (task.due != null)
              Text(
                _formatDate(task.due!),
                style: TextStyle(fontSize: 11, color: t.onSurfaceVariant),
              ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Delete task',
              icon: const Icon(Icons.close, size: 15),
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

// --- Kanban board ------------------------------------------------------------

class _DragTask {
  const _DragTask({
    required this.projectId,
    required this.taskId,
    required this.from,
  });
  final String projectId;
  final String taskId;
  final String from;
}

const _columns = <String, String>{
  'todo': 'To do',
  'doing': 'Doing',
  'done': 'Done',
};

class _BoardView extends ConsumerWidget {
  const _BoardView({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final col in _columns.entries) ...[
            SizedBox(
              width: 300,
              child: _BoardColumn(project: project, column: col.key, title: col.value),
            ),
            const SizedBox(width: 14),
          ],
        ],
      ),
    );
  }
}

class _BoardColumn extends ConsumerWidget {
  const _BoardColumn({required this.project, required this.column, required this.title});

  final Project project;
  final String column;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LumenColors.of(context);
    final tasks = [
      for (final task in project.tasks)
        if (task.status == column) task,
    ];
    final columnColor = switch (column) {
      'doing' => t.warning,
      'done' => t.success,
      _ => t.primary,
    };

    void move(_DragTask data, {String? insertBefore}) {
      ref.read(projectsNotifierProvider.notifier).moveTask(
        data.projectId,
        data.taskId,
        column,
        insertBefore: insertBefore,
      );
    }

    return DragTarget<_DragTask>(
      onAcceptWithDetails: (d) => move(d.data),
      builder: (context, candidates, _) {
        final highlighted = candidates.isNotEmpty;
        return Container(
          constraints: const BoxConstraints(minHeight: 200),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: highlighted ? t.surfaceContainer : t.surfaceLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlighted ? columnColor.withValues(alpha: 0.6) : t.hairline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: columnColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    '${tasks.length}',
                    style: TextStyle(fontSize: 11, color: t.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(
                      'Drop tasks here',
                      style: TextStyle(fontSize: 11.5, color: t.onSurfaceVariant),
                    ),
                  ),
                )
              else
                for (final task in tasks)
                  DragTarget<_DragTask>(
                    onWillAcceptWithDetails: (d) => d.data.from != column,
                    onAcceptWithDetails: (d) => move(d.data, insertBefore: task.id),
                    builder: (context, candidates, _) {
                      final over = candidates.isNotEmpty;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: over ? columnColor.withValues(alpha: 0.7) : Colors.transparent,
                            ),
                          ),
                          child: Draggable<_DragTask>(
                            data: _DragTask(
                              projectId: project.id,
                              taskId: task.id,
                              from: column,
                            ),
                            feedback: Material(
                              color: t.glass,
                              borderRadius: BorderRadius.circular(8),
                              elevation: 4,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Container(
                                  width: 220,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: t.surfaceContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    task.text,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                              ),
                            ),
                            child: _BoardCard(task: task, highlighted: over),
                          ),
                        ),
                      );
                    },
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.task, this.highlighted = false});

  final ProjectTask task;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: highlighted ? t.primaryContainer.withValues(alpha: 0.4) : t.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.text,
            style: const TextStyle(fontSize: 12.5),
          ),
          if (task.due != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 11),
                const SizedBox(width: 4),
                Text(
                  _formatDate(task.due!),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: t.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// --- Gantt timeline ----------------------------------------------------------

class _TimelineView extends StatelessWidget {
  const _TimelineView({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final tasks = project.tasks.where((task) => task.due != null).toList();
    return tasks.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No due dates yet. Add tasks with a due date to see a timeline.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: t.onSurfaceVariant),
              ),
            ),
          )
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _GanttChart(tasks: tasks),
          );
  }
}

class _GanttChart extends StatelessWidget {
  const _GanttChart({required this.tasks});

  final List<ProjectTask> tasks;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    var start = today;
    var end = today.add(const Duration(days: 3));
    for (final task in tasks) {
      final due = DateUtils.dateOnly(task.due!);
      final taskStart = task.start == null
          ? due.subtract(const Duration(days: 3))
          : DateUtils.dateOnly(task.start!);
      if (taskStart.isBefore(start)) start = taskStart;
      if (due.isAfter(end)) end = due;
    }
    final span = end.difference(start).inDays + 1;
    const pxPerDay = 46.0;
    const rowHeight = 32.0;
    const headerHeight = 30.0;

    return CustomPaint(
      size: Size(
        (span * pxPerDay).ceilToDouble() + 30,
        headerHeight + tasks.length * rowHeight + 16,
      ),
      painter: _GanttPainter(
        tasks: tasks,
        start: start,
        end: end,
        pxPerDay: pxPerDay,
        rowHeight: rowHeight,
        headerHeight: headerHeight,
        today: today,
        colors: t,
      ),
    );
  }
}

class _GanttPainter extends CustomPainter {
  _GanttPainter({
    required this.tasks,
    required this.start,
    required this.end,
    required this.pxPerDay,
    required this.rowHeight,
    required this.headerHeight,
    required this.today,
    required this.colors,
  });

  final List<ProjectTask> tasks;
  final DateTime start;
  final DateTime end;
  final double pxPerDay;
  final double rowHeight;
  final double headerHeight;
  final DateTime today;
  final LumenPalette colors;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = colors.hairline;
    final label = colors.onSurfaceVariant;
    final headerPaint = Paint()..style = PaintingStyle.fill;
    final barPaint = Paint()..strokeWidth = 1;

    final days = end.difference(start).inDays + 1;
    for (var i = 0; i <= days; i++) {
      final x = 30 + i * pxPerDay;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = grid.withValues(alpha: i == 0 ? 0 : 0.6)
          ..strokeWidth = 0.5,
      );
      final day = start.add(Duration(days: i));
      _text(
        canvas,
        '${day.month}/${day.day}',
        Offset(x + 4, 8),
        label,
        fontSize: 10,
      );
    }
    canvas.drawLine(
      Offset(30, headerHeight),
      Offset(size.width, headerHeight),
      Paint()..color = grid,
    );

    // Weekend shading + today marker.
    for (var i = 0; i < days; i++) {
      final day = start.add(Duration(days: i));
      if (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
        final x = 30 + i * pxPerDay;
        headerPaint.color = colors.surfaceLow;
        canvas.drawRect(
          Rect.fromLTWH(x, 0, pxPerDay, size.height),
          headerPaint,
        );
      }
    }
    if (!today.isBefore(start) && !today.isAfter(end)) {
      final x = 30 + today.difference(start).inDays * pxPerDay;
      canvas.drawLine(
        Offset(x, headerHeight),
        Offset(x, size.height),
        Paint()
          ..color = colors.primary.withValues(alpha: 0.55)
          ..strokeWidth = 1.2,
      );
    }

    var y = headerHeight + rowHeight / 2;
    for (final task in tasks) {
      final due = DateUtils.dateOnly(task.due!);
      final taskStart = task.start == null
          ? due.subtract(const Duration(days: 3))
          : DateUtils.dateOnly(task.start!);
      final barStart = taskStart.isBefore(start) ? start : taskStart;
      final x0 = 30 + barStart.difference(start).inDays * pxPerDay;
      final x1 = 30 + due.difference(start).inDays * pxPerDay + pxPerDay;
      final color = task.done
          ? colors.success
          : due.isBefore(today)
              ? colors.warning
              : colors.primary;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x0,
          y - 7,
          (x1 - x0).clamp(8.0, double.infinity).toDouble(),
          14,
        ),
        const Radius.circular(4),
      );
      barPaint.color = color;
      barPaint.style = PaintingStyle.fill;
      canvas.drawRRect(rect, barPaint);
      _text(
        canvas,
        task.text,
        Offset(x0 + 8, y - 6),
        colors.onSurface,
        fontSize: 10.5,
        maxWidth: (x1 - x0).clamp(30.0, 240.0).toDouble(),
      );
      y += rowHeight;
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    required double fontSize,
    double maxWidth = double.infinity,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _GanttPainter old) =>
      old.tasks != tasks ||
      old.start != start ||
      old.end != end ||
      old.colors != colors;
}

// --- shared helpers ----------------------------------------------------------

String _formatDate(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}