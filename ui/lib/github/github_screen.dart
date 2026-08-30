import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../journal/journal_provider.dart';
import '../journal/journal_service.dart';
import '../state/providers.dart';
import '../theme/lumen_colors.dart';
import 'github_provider.dart';
import 'github_service.dart';

/// GitHub workspace: connects a personal access token, lists repositories,
/// links repositories to projects and syncs issues into those projects.
class GithubScreen extends ConsumerWidget {
  const GithubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final github = ref.watch(githubProvider);
    return github.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ConnectView(error: '$e'),
      data: (ws) {
        if (!ws.connected) return _ConnectView(error: ws.error);
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _HeaderCard(ws: ws),
            if (ws.error != null) ...[
              const SizedBox(height: 14),
              _ErrorBanner(message: ws.error!),
            ],
            const SizedBox(height: 14),
            _LinkedProjectsCard(),
            const SizedBox(height: 14),
            _RepositoriesCard(repos: ws.repos),
          ],
        );
      },
    );
  }
}

class _ConnectView extends ConsumerStatefulWidget {
  const _ConnectView({this.error});
  final String? error;

  @override
  ConsumerState<_ConnectView> createState() => _ConnectViewState();
}

class _ConnectViewState extends ConsumerState<_ConnectView> {
  final TextEditingController _tok = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _tok.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.account_tree_outlined, size: 22, color: t.primary),
                    const SizedBox(width: 10),
                    const Text(
                      'Connect GitHub',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'A personal access token links repositories to your projects and '
                  'syncs issues as tasks.',
                  style: TextStyle(fontSize: 12.5, color: t.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _tok,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Personal access token (PAT)',
                    hintText: 'github_pat_…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _connect(),
                ),
                if (widget.error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    widget.error!,
                    style: TextStyle(fontSize: 12, color: t.error),
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _connect,
                    icon: _busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login, size: 16),
                    label: const Text('Connect'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    final ok = await ref.read(githubProvider.notifier).connect(_tok.text);
    setState(() => _busy = false);
    if (ok && _tok.text.isNotEmpty) _tok.clear();
  }
}

class _HeaderCard extends ConsumerWidget {
  const _HeaderCard({required this.ws});
  final GithubWorkspace ws;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LumenColors.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: t.primaryContainer,
              child: ws.avatarUrl == null
                  ? Icon(Icons.person_outline, size: 20, color: t.primary)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ws.login ?? 'GitHub',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${ws.repos.length} repositories · '
                    'last sync ${ws.lastSync?.toLocal().toString().split(' ').first ?? 'never'}',
                    style: TextStyle(fontSize: 12, color: t.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: () => ref.read(githubProvider.notifier).refresh(),
            ),
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout, size: 18),
              onPressed: () => ref.read(githubProvider.notifier).disconnect(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: t.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 12, color: t.error)),
          ),
        ],
      ),
    );
  }
}

class _LinkedProjectsCard extends ConsumerWidget {
  const _LinkedProjectsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LumenColors.of(context);
    final projects = ref.watch(projectsNotifierProvider).asData?.value ?? const <Project>[];
    final linked = [for (final p in projects) if (p.repo != null) p];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'LINKED PROJECTS & ISSUE SYNC'.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: t.outline,
                ),
              ),
            ),
            const Divider(indent: 16, endIndent: 16),
            if (linked.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Link a repository to a project below — syncing imports its open '
                  'issues as tasks.',
                  style: TextStyle(fontSize: 12.5, color: t.onSurfaceVariant),
                ),
              )
            else
              for (final project in linked) _LinkedProject(project: project),
          ],
        ),
      ),
    );
  }
}

class _LinkedProject extends ConsumerStatefulWidget {
  const _LinkedProject({required this.project});
  final Project project;

  @override
  ConsumerState<_LinkedProject> createState() => _LinkedProjectState();
}

class _LinkedProjectState extends ConsumerState<_LinkedProject> {
  static const _empty = <GithubPull>[];
  AsyncValue<List<GithubPull>> _pulls = const AsyncValue.data(_empty);
  bool _showPulls = false;

  Future<void> _loadPulls() async {
    final token = ref.read(settingsProvider).githubToken;
    if (token == null) return;
    _pulls = const AsyncValue.loading();
    setState(() {});
    try {
      final pulls = await ref
          .read(githubServiceProvider)
          .pulls(token, widget.project.repo!);
      _pulls = AsyncValue.data(pulls);
    } catch (e) {
      _pulls = AsyncValue.error(e, StackTrace.current);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final project = widget.project;
    final syncing = ref.watch(githubProvider).asData?.value.syncing ?? false;

    Future<void> sync() async {
      final report = await ref.read(githubProvider.notifier).syncProject(project.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Synced ${project.repo}: +${report.added} issues imported, '
            '${report.closed} closed.',
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.title,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      project.repo!,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                        color: t.primary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: syncing ? null : sync,
                icon: syncing
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync, size: 15),
                label: Text(syncing ? 'Syncing…' : 'Sync'),
              ),
              IconButton(
                tooltip: 'New issue',
                icon: const Icon(Icons.add_comment_outlined, size: 17),
                onPressed: syncing ? null : () => _createIssue(context),
              ),
              IconButton(
                tooltip: _showPulls ? 'Hide pull requests' : 'Show pull requests',
                icon: const Icon(Icons.merge_type, size: 17),
                onPressed: () {
                  setState(() => _showPulls = !_showPulls);
                  if (_showPulls) _loadPulls();
                },
              ),
            ],
          ),
        ),
        for (final task in project.tasks)
          if (task.github != null) _LinkedTask(project: project, task: task),
        if (_showPulls)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: _pulls.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(
                'Could not load pull requests: $e',
                style: TextStyle(fontSize: 12, color: t.error),
              ),
              data: (pulls) => pulls.isEmpty
                  ? Text(
                      'No pull requests on this repository.',
                      style: TextStyle(fontSize: 12, color: t.onSurfaceVariant),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final pull in pulls.take(8))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Icon(
                                  pull.state == 'open'
                                      ? Icons.merge_type
                                      : Icons.check_box_outlined,
                                  size: 14,
                                  color: pull.state == 'open'
                                      ? t.success
                                      : t.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '#${pull.number} ${pull.title}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
      ],
    );
  }

  Future<void> _createIssue(BuildContext context) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _NewIssueDialog(),
    );
    if (title == null || title.trim().isEmpty) return;
    await ref.read(githubProvider.notifier).createIssue(widget.project.id, title.trim());
  }
}

class _LinkedTask extends ConsumerWidget {
  const _LinkedTask({required this.project, required this.task});
  final Project project;
  final ProjectTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LumenColors.of(context);
    return InkWell(
      onTap: () => ref
          .read(projectsNotifierProvider.notifier)
          .toggle(project.id, task.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(
              task.done ? Icons.check_circle : Icons.circle_outlined,
              size: 15,
              color: task.done ? t.success : t.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              '#${task.github}',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: t.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                task.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  decoration: task.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewIssueDialog extends StatefulWidget {
  const _NewIssueDialog();

  @override
  State<_NewIssueDialog> createState() => _NewIssueDialogState();
}

class _NewIssueDialogState extends State<_NewIssueDialog> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New issue'),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _ctl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Issue title',
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

class _RepositoriesCard extends ConsumerWidget {
  const _RepositoriesCard({required this.repos});
  final List<GithubRepo> repos;

  Future<void> _linkTo(
    BuildContext context,
    WidgetRef ref,
    GithubRepo repo,
  ) async {
    final projects = ref.read(projectsNotifierProvider).asData?.value ?? const <Project>[];

    // Unlink any other project currently bound to this repo.
    final holder = projects.where((p) => p.repo == repo.fullName && p.repo != null).toList();
    final target = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text('Link ${repo.fullName} to a project'),
        children: [
          for (final p in projects)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, p.id),
              child: Text(
                p.title,
                style: TextStyle(
                  decoration: holder.contains(p) ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '__clear__'),
            child: const Text('Unlink from all'),
          ),
        ],
      ),
    );
    if (target == null) return;
    if (target == '__clear__') {
      for (final p in holder) {
        await ref.read(githubProvider.notifier).linkRepo(p.id, null);
      }
      return;
    }
    for (final p in holder) {
      await ref.read(githubProvider.notifier).linkRepo(p.id, null);
    }
    await ref.read(githubProvider.notifier).linkRepo(target, repo.fullName);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LumenColors.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'REPOSITORIES'.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: t.outline,
                ),
              ),
            ),
            const Divider(indent: 16, endIndent: 16),
            if (repos.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No repositories found for this account.',
                  style: TextStyle(fontSize: 12.5, color: t.onSurfaceVariant),
                ),
              )
            else
              for (final repo in repos.take(60))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.folder_copy_outlined, size: 16, color: t.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              repo.fullName,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            if (repo.description != null)
                              Text(
                                repo.description!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: t.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Link to project',
                        icon: Icon(
                          Icons.link,
                          size: 16,
                          color: _linkedProjectId(ref, repo.fullName) != null
                              ? t.primary
                              : t.onSurfaceVariant,
                        ),
                        onSelected: (_) => _linkTo(context, ref, repo),
                        itemBuilder: (_) => [
                          for (final p in ref
                              .read(projectsNotifierProvider)
                              .asData
                              ?.value ??
                              const <Project>[])
                            PopupMenuItem(
                              value: p.id,
                              child: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          if (ref.read(projectsNotifierProvider).asData?.value != null)
                            const PopupMenuItem(
                              value: '__clear__',
                              child: Text('Unlink'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String? _linkedProjectId(WidgetRef ref, String fullName) {
    for (final p in ref.read(projectsNotifierProvider).asData?.value ?? const <Project>[]) {
      if (p.repo == fullName) return p.id;
    }
    return null;
  }
}