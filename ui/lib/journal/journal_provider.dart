import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'journal_service.dart';

/// Wraps the encrypted journal store (own passphrase/keys; may share the
/// vault folder), using the persisted journal path.
final journalServiceProvider = Provider<JournalService>((ref) {
  final vault = ref.watch(journalVaultServiceProvider);
  return JournalService(vault);
});

/// Loads the stored projects (progress bars) from the journal store.
final projectsProvider = FutureProvider<List<Project>>((ref) {
  ref.watch(journalVaultProvider);
  return ref.watch(journalServiceProvider).loadProjects();
});

/// Contribution activity over the trailing year.
final activityProvider = FutureProvider<JournalActivity>((ref) {
  ref.watch(journalVaultProvider);
  return ref.watch(journalServiceProvider).activity();
});

/// A project list notifier for add/edit/toggle/delete with refresh.
class ProjectsNotifier extends AsyncNotifier<List<Project>> {
  @override
  Future<List<Project>> build() {
    ref.watch(journalVaultProvider);
    return ref.watch(journalServiceProvider).loadProjects();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(journalServiceProvider).loadProjects(),
    );
  }

  Future<void> upsert(Project project) async {
    await ref.read(journalServiceProvider).upsertProject(project);
    await refresh();
  }

  Future<void> remove(String id) async {
    await ref.read(journalServiceProvider).deleteProject(id);
    await refresh();
  }

  Future<void> toggle(String projectId, String taskId) async {
    await ref.read(journalServiceProvider).toggleTask(projectId, taskId);
    await refresh();
  }

  Future<void> addTask(
    String projectId,
    String text, {
    DateTime? due,
    String column = 'todo',
  }) async {
    final task = ProjectTask(text: text.trim(), column: column, due: due);
    await ref.read(journalServiceProvider).addTask(projectId, task);
    await refresh();
  }

  Future<void> removeTask(String projectId, String taskId) async {
    await ref.read(journalServiceProvider).removeTask(projectId, taskId);
    await refresh();
  }

  Future<void> moveTask(
    String projectId,
    String taskId,
    String column, {
    String? insertBefore,
  }) async {
    await ref
        .read(journalServiceProvider)
        .setTaskColumn(projectId, taskId, column, insertBefore: insertBefore);
    await refresh();
  }
}

final projectsNotifierProvider = AsyncNotifierProvider<ProjectsNotifier, List<Project>>(
  ProjectsNotifier.new,
);
