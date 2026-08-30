import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../ffi/vault_service.dart';

/// A project with a title and a list of tasks. Progress is derived from the
/// ratio of done tasks to total tasks (a progress bar per project).
@immutable
class Project {
  const Project({
    required this.id,
    required this.title,
    this.tasks = const [],
    this.repo,
  });
  final String id;
  final String title;
  final List<ProjectTask> tasks;

  /// GitHub repo (`owner/name`) this project is linked to, if any.
  final String? repo;

  int get done => tasks.where((t) => t.done).length;
  int get total => tasks.length;
  double get progress => total == 0 ? 0 : done / total;

  Project copyWith({String? id, String? title, List<ProjectTask>? tasks, String? repo, bool clearRepo = false}) =>
      Project(
        id: id ?? this.id,
        title: title ?? this.title,
        tasks: tasks ?? this.tasks,
        repo: clearRepo ? null : (repo ?? this.repo),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (repo != null) 'repo': repo,
    'tasks': [for (final t in tasks) t.toJson()],
  };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    repo: j['repo'] as String?,
    tasks: [
      for (final t in (j['tasks'] as List<dynamic>? ?? const []))
        ProjectTask.fromJson(t as Map<String, dynamic>),
    ],
  );
}

@immutable
class ProjectTask {
  const ProjectTask({
    required this.text,
    this.id = '',
    this.done = false,
    this.column = 'todo',
    this.start,
    this.due,
    this.github,
  });
  final String text;
  final String id;
  final bool done;

  /// Kanban column: `todo`, `doing` or `done`. Kept in sync with [done].
  final String column;
  final DateTime? start;
  final DateTime? due;

  /// GitHub issue number this task is linked to (from a linked repo).
  final int? github;

  /// Column derived from the done flag, ignoring stale stored values.
  String get status => done ? 'done' : (column == 'done' ? 'todo' : column);

  ProjectTask copyWith({
    String? text,
    String? id,
    bool? done,
    String? column,
    DateTime? start,
    DateTime? due,
    int? github,
    bool clearGithub = false,
  }) => ProjectTask(
    text: text ?? this.text,
    id: id ?? this.id,
    done: done ?? this.done,
    column: column ?? this.column,
    start: start ?? this.start,
    due: due ?? this.due,
    github: clearGithub ? null : (github ?? this.github),
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    'id': id,
    'done': done,
    'column': column,
    if (github != null) 'github': github,
    if (start != null) 'start': start!.toIso8601String(),
    if (due != null) 'due': due!.toIso8601String(),
  };

  factory ProjectTask.fromJson(Map<String, dynamic> j) => ProjectTask(
    text: j['text'] as String? ?? '',
    id: j['id'] as String? ?? '',
    done: j['done'] as bool? ?? false,
    column: j['column'] as String? ?? (j['done'] as bool? ?? false ? 'done' : 'todo'),
    github: (j['github'] as num?)?.toInt(),
    start: _parseDate(j['start'] as String?),
    due: _parseDate(j['due'] as String?),
  );
}

DateTime? _parseDate(String? s) {
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// Aggregates journal activity for the contribution chart: date -> entry count.
@immutable
class JournalActivity {
  const JournalActivity({required this.days});
  /// `days[date]` = number of journal entries written that day.
  final Map<DateTime, int> days;

  int countFor(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return days[key] ?? 0;
  }

  int get total => days.values.fold(0, (a, b) => a + b);
}

/// Reads/writes the journal vault (an encrypted folder) — daily markdown
/// entries plus a `projects.json` for task/project progress.
class JournalService {
  JournalService(this._vault);

  final VaultService _vault;

  static const _projectsFile = 'projects.json';

  // --- Projects ------------------------------------------------------------

  Future<List<Project>> loadProjects() async {
    try {
      final raw = await _vault.readText(_projectsFile);
      final decoded = jsonDecode(raw) as List<dynamic>;
      return [
        for (final p in decoded)
          Project.fromJson((p as Map<String, dynamic>)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveProjects(List<Project> projects) async {
    await _vault.writeText(
      _projectsFile,
      const JsonEncoder.withIndent('  ').convert(
        [for (final p in projects) p.toJson()],
      ),
    );
  }

  Future<Project> upsertProject(Project project) async {
    final all = await loadProjects();
    final i = all.indexWhere((p) => p.id == project.id);
    if (i >= 0) {
      all[i] = _withTaskIds(project);
    } else {
      all.add(_withTaskIds(project));
    }
    await _saveProjects(all);
    return project;
  }

  Future<void> deleteProject(String id) async {
    final all = await loadProjects();
    await _saveProjects([for (final p in all) if (p.id != id) p]);
  }

  /// Fills in stable ids for tasks that predate the id field.
  Project _withTaskIds(Project project) {
    var n = 0;
    final tasks = [
      for (final t in project.tasks)
        t.id.isEmpty
            ? t.copyWith(id: 'task-${project.id}-${n++}')
            : t,
    ];
    return project.copyWith(tasks: tasks);
  }

  Future<void> toggleTask(String projectId, String taskId) async {
    await _updateProject(projectId, (p, tasks) {
      final i = tasks.indexWhere((t) => t.id == taskId);
      if (i < 0) return;
      final t = tasks[i];
      final done = !t.done;
      tasks[i] = t.copyWith(done: done, column: done ? 'done' : 'todo');
    });
  }

  Future<void> addTask(String projectId, ProjectTask task) async {
    await _updateProject(projectId, (p, tasks) {
      tasks.add(
        task.id.isEmpty ? task.copyWith(id: 'task-$projectId-${tasks.length}') : task,
      );
    });
  }

  Future<void> updateTask(String projectId, ProjectTask task) async {
    await _updateProject(projectId, (p, tasks) {
      final i = tasks.indexWhere((t) => t.id == task.id);
      if (i < 0) {
        tasks.add(task);
      } else {
        tasks[i] = task;
      }
    });
  }

  Future<void> removeTask(String projectId, String taskId) async {
    await _updateProject(projectId, (p, tasks) {
      tasks.removeWhere((t) => t.id == taskId);
    });
  }

  /// Moves a task to [column] (`todo`/`doing`/`done`), keeping its order
  /// within the project task list when [insertBefore] matches a sibling id.
  Future<void> setTaskColumn(
    String projectId,
    String taskId,
    String column, {
    String? insertBefore,
  }) async {
    await _updateProject(projectId, (p, tasks) {
      final i = tasks.indexWhere((t) => t.id == taskId);
      if (i < 0) return;
      final task = tasks.removeAt(i);
      final done = column == 'done';
      final moved = task.copyWith(column: done ? 'done' : column, done: done);
      if (insertBefore == null || insertBefore == task.id) {
        tasks.insert(i, moved);
        return;
      }
      final j = tasks.indexWhere((t) => t.id == insertBefore);
      tasks.insert(j < 0 ? tasks.length : j, moved);
    });
  }

  Future<void> _updateProject(
    String projectId,
    void Function(Project project, List<ProjectTask> tasks) mutate,
  ) async {
    final all = await loadProjects();
    final i = all.indexWhere((p) => p.id == projectId);
    if (i < 0) return;
    final tasks = [...all[i].tasks];
    mutate(all[i], tasks);
    all[i] = _withTaskIds(all[i].copyWith(tasks: tasks));
    await _saveProjects(all);
  }

  // --- Journal entries + contributions -------------------------------------

  /// The journal entry filename for [date] (YYYY-MM-DD.md).
  static String entryFileFor(DateTime date) {
    final m =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return '$m.md';
  }

  /// Records writing to today's (or [date]'s) journal entry — this is the
  /// "contribution". Returns the entry filename touched.
  Future<String> recordEntry({DateTime? date}) async {
    final d = date ?? DateTime.now();
    final fname = entryFileFor(d);
    try {
      final existing = await _vault.readText(fname);
      if (existing.trim().isNotEmpty) return fname;
    } catch (_) {
      // no existing entry yet
    }
    try {
      await _vault.writeText(fname, _newEntryBody(d));
    } catch (_) {
      // entry may not be creatable if vault is locked/missing — swallow
    }
    return fname;
  }

  String _newEntryBody(DateTime d) {
    final m = _months[d.month]!;
    return '# $m ${d.day}, ${d.year}\n\n';
  }

  static const _months = {
    1: 'January', 2: 'February', 3: 'March', 4: 'April', 5: 'May', 6: 'June',
    7: 'July', 8: 'August', 9: 'September', 10: 'October', 11: 'November',
    12: 'December',
  };

  /// Builds the contribution calendar from the dates of markdown entries in
  /// the vault, over the trailing [days] window ending [end].
  Future<JournalActivity> activity({int days = 365, DateTime? end}) async {
    final endDay = end ?? DateTime.now();
    final result = <DateTime, int>{};
    List<dynamic> entries;
    try {
      entries = await _vault.list('');
    } catch (_) {
      return JournalActivity(days: result);
    }
    for (final raw in entries) {
      final e = raw as Map<String, dynamic>;
      final name = (e['name'] as String?) ?? '';
      final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})\.md$').firstMatch(name);
      if (m == null) continue;
      final yr = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      final day = int.parse(m.group(3)!);
      final date = DateTime(yr, mo, day);
      final diff = endDay.difference(date).inDays;
      if (diff >= 0 && diff < days) {
        result[date] = (result[date] ?? 0) + 1;
      }
    }
    return JournalActivity(days: result);
  }
}
