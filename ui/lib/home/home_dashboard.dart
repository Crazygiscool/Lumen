import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../journal/journal_provider.dart';
import '../journal/journal_service.dart';
import '../shell/passphrase_dialog.dart';
import '../shell/tabs/tabs_provider.dart';
import '../state/providers.dart';
import '../theme/glass.dart';
import '../theme/lumen_colors.dart';
import '../wakatime/wakatime_provider.dart';
import '../wakatime/wakatime_service.dart';
import 'contribution_chart.dart';

class HomeDashboard extends ConsumerWidget {
  const HomeDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LumenColors.of(context);
    final settings = ref.watch(settingsProvider);
    final projects = ref.watch(projectsNotifierProvider);
    final activity = ref.watch(activityProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _HeaderBar(t: t),
        const SizedBox(height: 20),
        _DashboardGrid(
          t: t,
          goals: ref.watch(onboardingProvider).goals,
          onAddGoal: (text) =>
              ref.read(onboardingProvider.notifier).addGoal(text),
          onRemoveGoal: (text) =>
              ref.read(onboardingProvider.notifier).removeGoal(text),
          journalPath: settings.journalVaultPath,
          projects: projects,
          activity: activity,
          showProjects: ref.watch(featuresProvider).enabled(LumenFeature.projects),
          showWakatime: ref.watch(featuresProvider).enabled(LumenFeature.wakatime),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _HeaderBar extends ConsumerWidget {
  const _HeaderBar({required this.t});
  final LumenPalette t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Home',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: t.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Your goals, journal activity and projects at a glance.',
                style: TextStyle(fontSize: 13, color: t.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Reload',
          icon: const Icon(Icons.refresh, size: 18),
          onPressed: () {
            ref.invalidate(activityProvider);
            ref.read(projectsNotifierProvider.notifier).refresh();
          },
        ),
      ],
    );
  }
}

class _DashboardGrid extends StatelessWidget {
  const _DashboardGrid({
    required this.t,
    required this.goals,
    required this.onAddGoal,
    required this.onRemoveGoal,
    required this.journalPath,
    required this.projects,
    required this.activity,
    required this.showProjects,
    required this.showWakatime,
  });

  final LumenPalette t;
  final List<Goal> goals;
  final ValueChanged<String> onAddGoal;
  final ValueChanged<String> onRemoveGoal;
  final String? journalPath;
  final AsyncValue<List<Project>> projects;
  final AsyncValue<JournalActivity> activity;
  final bool showProjects;
  final bool showWakatime;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: wide ? (constraints.maxWidth - 16) * 0.62 : constraints.maxWidth,
              child: Column(
                children: [
                  _GoalsCard(
                    t: t,
                    goals: goals,
                    onAdd: onAddGoal,
                    onRemove: onRemoveGoal,
                  ),
                  const SizedBox(height: 16),
                  _ActivityCard(t: t, activity: activity),
                  if (showWakatime) ...[
                    const SizedBox(height: 16),
                    const _WakatimeCard(),
                  ],
                ],
              ),
            ),
            SizedBox(
              width: wide
                  ? (constraints.maxWidth - 16) * 0.38
                  : constraints.maxWidth,
              child: showProjects ? _ProjectsCard(
                t: t,
                path: journalPath,
                projects: projects,
              ) : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}

class _GoalsCard extends ConsumerWidget {
  const _GoalsCard({
    required this.t,
    required this.goals,
    required this.onAdd,
    required this.onRemove,
  });

  final LumenPalette t;
  final List<Goal> goals;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    return Glass(
      blurSigma: 0,
      radius: LumenColors.radiusLg,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag_outlined, size: 18, color: t.primary),
                const SizedBox(width: 8),
                Text(
                  'Current goals',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final g in goals)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 6, color: Colors.transparent),
                    Expanded(
                      child: Text(g.text, style: TextStyle(fontSize: 13.5, color: t.onSurface)),
                    ),
                    InkWell(
                      onTap: () => onRemove(g.text),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.close, size: 14, color: t.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            if (goals.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'No goals yet — define them in Getting Started.',
                  style: TextStyle(fontSize: 12.5, color: t.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Add a goal…',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      hintStyle: TextStyle(color: t.onSurfaceVariant),
                    ),
                    onSubmitted: (v) {
                      onAdd(v);
                      controller.clear();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Add goal',
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () {
                    onAdd(controller.text);
                    controller.clear();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends ConsumerWidget {
  const _ActivityCard({required this.t, required this.activity});
  final LumenPalette t;
  final AsyncValue<JournalActivity> activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final journal = ref.watch(journalVaultProvider);
    final locked = settings.journalVaultPath != null && !journal.unlocked;
    return Glass(
      blurSigma: 0,
      radius: LumenColors.radiusLg,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_outlined, size: 18, color: t.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Contribution chart',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.onSurface,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('Log today'),
                  onPressed: () => _logToday(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (locked)
              _JournalLockBanner(t: t, onUnlock: () => _unlockJournal(context, ref))
            else
              activity.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(
                  'Could not read the journal: $e',
                  style: TextStyle(fontSize: 12.5, color: t.onSurfaceVariant),
                ),
                data: (act) => ContributionChart(activity: act),
              ),
            const SizedBox(height: 8),
            Text(
              'Daily journal entries by day — log today to light up a cell.',
              style: TextStyle(fontSize: 11, color: t.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logToday(BuildContext context, WidgetRef ref) async {
    if (!ref.read(journalVaultProvider).unlocked) {
      final ok = await _unlockJournal(context, ref);
      if (ok != true) return;
    }
    await ref.read(journalServiceProvider).recordEntry();
    ref.invalidate(activityProvider);
  }

  /// Prompts for the journal passphrase and unlocks the journal store.
  /// Returns true when the store was unlocked successfully.
  Future<bool> _unlockJournal(BuildContext context, WidgetRef ref) async {
    final path = ref.read(settingsProvider).journalVaultPath;
    if (path == null) return false;
    final notifier = ref.read(journalVaultProvider.notifier);
    final ok = await PassphraseDialog.showUnlock(
      context,
      title: 'Unlock journal',
      label: 'Journal passphrase',
      path: path,
      onSubmit: (pass) => notifier.unlock(path, pass),
    );
    if (ok) {
      ref.invalidate(activityProvider);
      ref.invalidate(projectsProvider);
      ref.invalidate(projectsNotifierProvider);
    }
    return ok;
  }
}

/// Compact locked-state banner shown on the journal card after relaunching
/// with a configured (but not yet unlocked) journal store.
class _JournalLockBanner extends StatelessWidget {
  const _JournalLockBanner({required this.t, required this.onUnlock});
  final LumenPalette t;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.hairline),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 18, color: t.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your journal is locked. Unlock it to log today and see your contribution chart.',
              style: TextStyle(fontSize: 12.5, color: t.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onUnlock,
            icon: const Icon(Icons.key, size: 15),
            label: const Text('Unlock'),
          ),
        ],
      ),
    );
  }
}

class _ProjectsCard extends ConsumerWidget {
  const _ProjectsCard({required this.t, required this.path, required this.projects});
  final LumenPalette t;
  final String? path;
  final AsyncValue<List<Project>> projects;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Glass(
      blurSigma: 0,
      radius: LumenColors.radiusLg,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_copy_outlined, size: 18, color: t.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Project progress',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'New project',
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => _newProject(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 4),
            projects.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(
                'Could not load projects: $e',
                style: TextStyle(fontSize: 12.5, color: t.onSurfaceVariant),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No projects yet. Add one to track progress here.',
                      style: TextStyle(fontSize: 12.5, color: t.onSurfaceVariant),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final p in list) _ProjectTile(project: p),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _newProject(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (c) => const _ProjectDialog(),
    );
  }
}

class _ProjectDialog extends ConsumerStatefulWidget {
  const _ProjectDialog();
  @override
  ConsumerState<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends ConsumerState<_ProjectDialog> {
  final _title = TextEditingController();
  final _tasks = <TextEditingController>[];

  @override
  void dispose() {
    _title.dispose();
    for (final c in _tasks) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New project'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Project title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tasks (each toggles toward your progress bar)',
              style: TextStyle(
                fontSize: 12,
                color: LumenColors.of(context).onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < _tasks.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tasks[i],
                        decoration: const InputDecoration(
                          hintText: 'Task…',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      onPressed: () => setState(() {
                        _tasks.removeAt(i).dispose();
                      }),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _tasks.add(TextEditingController())),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add task'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final title = _title.text.trim();
            if (title.isEmpty) return;
            final tasks = [
              for (final c in _tasks)
                if (c.text.trim().isNotEmpty)
                  ProjectTask(text: c.text.trim()),
            ];
            await ref.read(projectsNotifierProvider.notifier).upsert(
              Project(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                title: title,
                tasks: tasks,
              ),
            );
            if (!mounted) return;
            Navigator.pop(this.context);
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _ProjectTile extends ConsumerWidget {
  const _ProjectTile({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LumenColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  project.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.onSurface,
                  ),
                ),
              ),
              Text(
                '${project.done}/${project.total}',
                style: TextStyle(fontSize: 12, color: t.onSurfaceVariant),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Delete project',
                icon: const Icon(Icons.delete_outline, size: 16),
                onPressed: () =>
                    ref.read(projectsNotifierProvider.notifier).remove(project.id),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: project.progress,
              minHeight: 6,
              backgroundColor: t.hairline,
            ),
          ),
          const SizedBox(height: 6),
          for (final task in project.tasks)
            InkWell(
              onTap: () => ref
                  .read(projectsNotifierProvider.notifier)
                  .toggle(project.id, task.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      task.done
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 15,
                      color: task.done ? t.success : t.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: task.done ? t.onSurfaceVariant : t.onSurface,
                          decoration: task.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 16),
        ],
      ),
    );
  }
}

class _WakatimeCard extends ConsumerWidget {
  const _WakatimeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LumenColors.of(context);
    final state = ref.watch(wakatimeProvider).asData?.value ?? const WakatimeState();

    void openSettings() {
      ref.read(tabsProvider.notifier).activatePage(LumenSection.settings);
    }

    return Glass(
      blurSigma: 0,
      radius: LumenColors.radiusLg,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 18, color: t.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Coding time',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.onSurface,
                    ),
                  ),
                ),
                if (state.active)
                  IconButton(
                    tooltip: 'Refresh WakaTime',
                    icon: const Icon(Icons.refresh, size: 16),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => ref.read(wakatimeProvider.notifier).refresh(),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (!state.active)
              _InlineMessage(
                text: 'Add your WakaTime API key in Settings to see coding stats.',
                action: TextButton(
                  onPressed: openSettings,
                  child: const Text('Open settings'),
                ),
              )
            else if (state.error != null)
              _InlineMessage(
                text: state.error!,
                action: TextButton(
                  onPressed: () => ref.read(wakatimeProvider.notifier).refresh(),
                  child: const Text('Retry'),
                ),
              )
            else
              _WakatimeStats(stats: state.stats, user: state.user),
          ],
        ),
      ),
    );
  }
}

class _WakatimeStats extends StatelessWidget {
  const _WakatimeStats({required this.stats, required this.user});
  final WakatimeStats? stats;
  final String? user;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final s = stats;
    if (s == null) return const LinearProgressIndicator();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (user != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${user!} · 7-day summary',
              style: TextStyle(fontSize: 12, color: t.onSurfaceVariant),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              s.humanTotal.isEmpty
                  ? '${s.totalSeconds.toStringAsFixed(0)}s'
                  : s.humanTotal,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                'coded · ${s.dailyAverageHuman.isEmpty ? '—' : s.dailyAverageHuman}/day',
                style: TextStyle(fontSize: 12, color: t.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (s.languages.isEmpty)
          Text(
            'No coding activity in the last 7 days.',
            style: TextStyle(fontSize: 12.5, color: t.onSurfaceVariant),
          )
        else
          for (final lang in s.languages.take(5)) ...[
            Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    lang.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: lang.percent.clamp(0.0, 1.0).toDouble(),
                      minHeight: 6,
                      backgroundColor: t.hairline,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    lang.humanTime,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, color: t.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
      ],
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, color: t.onSurfaceVariant),
          ),
        ),
        ?action,
      ],
    );
  }
}

