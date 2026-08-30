import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../journal/journal_provider.dart';
import '../journal/journal_service.dart';
import '../state/providers.dart';
import 'github_service.dart';

final githubServiceProvider = Provider<GithubService>((ref) => GithubService());

@immutable
class GithubWorkspace {
  const GithubWorkspace({
    this.login,
    this.avatarUrl,
    this.repos = const [],
    this.error,
    this.syncing = false,
    this.lastSync,
  });

  final String? login;
  final String? avatarUrl;
  final List<GithubRepo> repos;
  final String? error;
  final bool syncing;
  final DateTime? lastSync;

  bool get connected => login != null;

  GithubWorkspace copyWith({
    String? login,
    String? avatarUrl,
    List<GithubRepo>? repos,
    String? error,
    bool? syncing,
    DateTime? lastSync,
    bool clearError = false,
  }) => GithubWorkspace(
    login: login ?? this.login,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    repos: repos ?? this.repos,
    error: clearError ? null : (error ?? this.error),
    syncing: syncing ?? this.syncing,
    lastSync: lastSync ?? this.lastSync,
  );
}

/// Result of a single project->repo sync.
class GithubSyncReport {
  const GithubSyncReport({required this.projectId, this.added = 0, this.closed = 0});
  final String projectId;
  final int added;
  final int closed;
}

class GithubNotifier extends AsyncNotifier<GithubWorkspace> {
  @override
  Future<GithubWorkspace> build() async {
    final token = ref.watch(settingsProvider).githubToken;
    if (token == null || token.trim().isEmpty) {
      return const GithubWorkspace();
    }
    try {
      final service = ref.watch(githubServiceProvider);
      final user = await service.me(token);
      final repos = await service.repos(token);
      return GithubWorkspace(
        login: user.login,
        avatarUrl: user.avatarUrl,
        repos: repos,
      );
    } catch (e) {
      return GithubWorkspace(error: e.toString());
    }
  }

  Future<bool> connect(String token) async {
    final value = token.trim();
    if (value.isEmpty) return false;
    // Probe the token first so a bad PAT doesn't stick around.
    try {
      final user = await ref.read(githubServiceProvider).me(value);
      ref.read(settingsProvider.notifier).setGithubToken(value);
      ref.read(settingsProvider.notifier).setGithubLogin(user.login);
      await ref.read(projectsNotifierProvider.notifier).refresh();
      ref.invalidateSelf();
      return true;
    } catch (e) {
      state = AsyncValue.data(
        state.asData?.value.copyWith(error: e.toString()) ??
            GithubWorkspace(error: e.toString()),
      );
      return false;
    }
  }

  Future<void> disconnect() async {
    final settings = ref.read(settingsProvider.notifier);
    settings.setGithubToken(null);
    settings.setGithubLogin(null);
    ref.invalidateSelf();
  }

  Future<void> refresh() async {
    final token = ref.read(settingsProvider).githubToken;
    if (token == null) return;
    try {
      final service = ref.read(githubServiceProvider);
      final user = await service.me(token);
      final repos = await service.repos(token);
      state = AsyncValue.data(
        state.asData?.value.copyWith(
              login: user.login,
              avatarUrl: user.avatarUrl,
              repos: repos,
              clearError: true,
            ) ??
            GithubWorkspace(
              login: user.login,
              avatarUrl: user.avatarUrl,
              repos: repos,
            ),
      );
    } catch (e) {
      state = AsyncValue.data(
        state.asData?.value.copyWith(error: e.toString()) ??
            GithubWorkspace(error: e.toString()),
      );
    }
  }

  /// Links [projectId] to a GitHub repo (`owner/name`). Pass null to unlink.
  Future<void> linkRepo(String projectId, String? repo) async {
    final projects = await ref.read(journalServiceProvider).loadProjects();
    final i = projects.indexWhere((p) => p.id == projectId);
    if (i < 0) return;
    final project = projects[i];
    if (repo == null) {
      await ref
          .read(journalServiceProvider)
          .upsertProject(project.copyWith(repo: null, clearRepo: true));
    } else if (project.repo != repo) {
      await ref
          .read(journalServiceProvider)
          .upsertProject(project.copyWith(repo: repo));
    }
    await ref.read(projectsNotifierProvider.notifier).refresh();
  }

  /// One-way merge for a linked project: open issues become local tasks (keyed
  /// by issue number), and tasks marked done close their issue remotely.
  Future<GithubSyncReport> syncProject(String projectId) async {
    final token = ref.read(settingsProvider).githubToken;
    if (token == null) {
      throw GithubException('Connect your GitHub token first');
    }
    final projects = await ref.read(journalServiceProvider).loadProjects();
    final project = projects.firstWhere(
      (p) => p.id == projectId,
      orElse: () => throw GithubException('Project not found'),
    );
    final repo = project.repo;
    if (repo == null) {
      throw GithubException('Link this project to a repository first');
    }

    state = AsyncValue.data(
      (state.asData?.value ?? const GithubWorkspace()).copyWith(syncing: true),
    );
    try {
      final service = ref.read(githubServiceProvider);
      final open = await service.issues(token, repo, state: 'open');
      final existing = {
        for (final t in project.tasks)
          if (t.github != null) t.github!,
      };

      var tasks = [...project.tasks];
      var added = 0;
      for (final issue in open) {
        if (existing.contains(issue.number)) continue;
        tasks.add(
          ProjectTask(
            text: issue.title,
            id: 'gh-$projectId-${issue.number}',
            github: issue.number,
          ),
        );
        added++;
      }

      var closed = 0;
      for (final task in tasks) {
        final number = task.github;
        if (number == null || !task.done) continue;
        if (existing.contains(number)) {
          await service.setIssueState(token, repo, number, closed: true);
          closed++;
        }
      }

      await ref
          .read(journalServiceProvider)
          .upsertProject(project.copyWith(tasks: tasks));
      await ref.read(projectsNotifierProvider.notifier).refresh();
      final updated = (state.asData?.value ?? const GithubWorkspace()).copyWith(
        syncing: false,
        error: null,
        lastSync: DateTime.now(),
      );
      state = AsyncValue.data(updated);
      return GithubSyncReport(projectId: projectId, added: added, closed: closed);
    } catch (e) {
      state = AsyncValue.data(
        (state.asData?.value ?? const GithubWorkspace())
            .copyWith(syncing: false, error: e.toString()),
      );
      rethrow;
    }
  }

  /// Creates an issue on the project's linked repo and mirrors it as a task.
  Future<void> createIssue(String projectId, String title) async {
    final token = ref.read(settingsProvider).githubToken;
    if (token == null) {
      throw GithubException('Connect your GitHub token first');
    }
    final projects = await ref.read(journalServiceProvider).loadProjects();
    final project = projects.firstWhere(
      (p) => p.id == projectId,
      orElse: () => throw GithubException('Project not found'),
    );
    final repo = project.repo;
    if (repo == null) {
      throw GithubException('Link this project to a repository first');
    }
    final issue = await ref.read(githubServiceProvider).createIssue(
      token,
      repo,
      title,
      body: 'Created from Lumen',
    );
    await ref.read(journalServiceProvider).addTask(
      projectId,
      ProjectTask(
        text: issue.title,
        id: 'gh-$projectId-${issue.number}',
        github: issue.number,
      ),
    );
    await ref.read(projectsNotifierProvider.notifier).refresh();
  }
}

final githubProvider = AsyncNotifierProvider<GithubNotifier, GithubWorkspace>(
  GithubNotifier.new,
);