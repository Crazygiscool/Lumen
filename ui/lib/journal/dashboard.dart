import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/app_icons.dart';
import '../theme/lumen_colors.dart';
import 'journal_provider.dart';
import 'journal_service.dart';
import 'quotes.dart';

/// A rearrangeable dashboard shown in the right pane when no note is open.
class JournalDashboard extends ConsumerStatefulWidget {
  const JournalDashboard({super.key, required this.onOpenNote});

  final ValueChanged<String> onOpenNote;

  @override
  ConsumerState<JournalDashboard> createState() => _JournalDashboardState();
}

class _JournalDashboardState extends ConsumerState<JournalDashboard> {
  Map<String, int> _dailyCounts = const {};
  final Map<String, ({int modifiedMs, int words})> _wordCache = {};
  final _quotes = QuoteService();
  bool _loadingCounts = false;
  bool _arranging = false;
  Quote? _quote;
  bool _loadingQuote = false;
  String? _quoteError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshCounts();
      _loadQuote();
    });
  }

  List<JournalNote> _notesOrEmpty() {
    final v = ref.read(journalNotesProvider);
    return v.whenOrNull(data: (n) => n) ?? const [];
  }

  @override
  void dispose() {
    _quotes.close();
    super.dispose();
  }

  Future<void> _refreshCounts() async {
    final notes = _notesOrEmpty();
    if (notes.isEmpty) {
      if (mounted) setState(() => _dailyCounts = const {});
      return;
    }
    setState(() => _loadingCounts = true);
    try {
      final counts = await ref
          .read(journalServiceProvider)
          .dailyWordCounts(notes, cache: _wordCache);
      // Drop cache entries for notes that no longer exist.
      final live = notes.map((n) => n.relPath).toSet();
      _wordCache.removeWhere((path, _) => !live.contains(path));
      if (mounted) setState(() => _dailyCounts = counts);
    } catch (_) {
      if (mounted) setState(() => _dailyCounts = const {});
    } finally {
      if (mounted) setState(() => _loadingCounts = false);
    }
  }

  Future<void> _loadQuote() async {
    final prefs = ref.read(dashboardPrefsProvider);
    final source = prefs.quoteSource;
    setState(() {
      _loadingQuote = true;
      _quoteError = null;
    });
    try {
      Quote q;
      if (source == QuoteSource.offline) {
        q = _quotes.offline();
      } else {
        final service = QuoteService(
          source: source,
          apiKey: prefs.quoteApiKey,
          customUrl: prefs.quoteCustomUrl,
        );
        try {
          q = await service.fetch().timeout(const Duration(seconds: 10));
        } finally {
          service.close();
        }
      }
      if (mounted) setState(() => _quote = q);
    } catch (e) {
      final fallback = _quotes.offline();
      if (mounted) {
        setState(() {
          _quote = fallback;
          _quoteError = source == QuoteSource.zenquotes
              ? 'Couldn\u2019t load zenquotes \u2014 showing an offline one.'
              : 'Couldn\u2019t load that quote source \u2014 showing an offline one.';
        });
      }
    } finally {
      if (mounted) setState(() => _loadingQuote = false);
    }
  }

  Future<void> _openOrCreateDated(DateTime date, {String? slot}) async {
    final notes = _notesOrEmpty();
    final service = ref.read(journalServiceProvider);
    final existing = JournalService.notePathForDate(notes, date, slot: slot);
    if (existing != null) {
      widget.onOpenNote(existing);
      return;
    }
    final taken = notes.map((n) => n.name).toSet();
    final path = JournalService.pathForDate(date, slot: slot, taken: taken);
    await service.write(path, _templateFor(date, slot));
    ref.invalidate(journalNotesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _refreshCounts();
    widget.onOpenNote(path);
  }

  static String _templateFor(DateTime date, String? slot) {
    final pretty = _prettyDate(date);
    if (slot == 'morning') {
      return '# $pretty \u2014 Morning\n\n## Intention\n\n## Top priorities\n- [ ] \n\n## Energy & focus\n\n';
    }
    if (slot == 'evening') {
      return '# $pretty \u2014 Evening\n\n## What happened\n\n## Gratitude\n- \n\n## Lessons & wins\n\n## Tomorrow\n\n';
    }
    return '# $pretty\n\n';
  }

  static String _prettyDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final prefs = ref.watch(dashboardPrefsProvider);
    final notesAsync = ref.watch(journalNotesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dashboard', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      _arranging
                          ? 'Drag a handle to reorder, or hide cards you don\u2019t need.'
                          : 'Your writing activity and a space to plan and reflect',
                      style: TextStyle(color: t.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _arranging = !_arranging),
                icon: Icon(_arranging ? Icons.check : Icons.tune, size: 18),
                label: Text(_arranging ? 'Done' : 'Arrange'),
              ),
              if (_arranging)
                IconButton(
                  tooltip: 'Show or hide cards',
                  onPressed: () => _showCardsSheet(context),
                  icon: const Icon(Icons.visibility_outlined),
                ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () {
                  _refreshCounts();
                  _loadQuote();
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: notesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => Center(child: Text('$e')),
            data: (_) => ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) =>
                  ref.read(dashboardPrefsProvider.notifier).reorder(oldIndex, newIndex),
              itemCount: prefs.visibleOrder.length,
              itemBuilder: (context, i) {
                final card = prefs.visibleOrder[i];
                return KeyedSubtree(
                  key: ValueKey(card.id),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _cardFor(card)),
                        if (_arranging) ...[
                          const SizedBox(width: 4),
                          Column(
                            children: [
                              if (i > 0)
                                IconButton(
                                  tooltip: 'Move up',
                                  iconSize: 18,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => ref
                                      .read(dashboardPrefsProvider.notifier)
                                      .moveBy(card, -1),
                                  icon: const Icon(Icons.keyboard_arrow_up),
                                ),
                              if (i < prefs.visibleOrder.length - 1)
                                IconButton(
                                  tooltip: 'Move down',
                                  iconSize: 18,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => ref
                                      .read(dashboardPrefsProvider.notifier)
                                      .moveBy(card, 1),
                                  icon: const Icon(Icons.keyboard_arrow_down),
                                ),
                              ReorderableDragStartListener(
                                index: i,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.drag_indicator, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        ..._pluginDashboardCards(context, ref),
      ],
    );
  }

  List<Widget> _pluginDashboardCards(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(pluginDashboardCardsProvider);
    if (cards.isEmpty) return const [];
    final t = LumenColors.of(context);
    return [
      for (final card in cards)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Card(
            child: ListTile(
              leading: Icon(AppIcons.resolve(card.icon), color: t.primary),
              title: Text(card.title),
              subtitle:
                  card.subtitle == null ? null : Text(card.subtitle!),
              trailing: Text(
                card.pluginId,
                style: TextStyle(
                  color: t.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _cardFor(DashboardCard card) {
    return switch (card) {
      DashboardCard.dayNight => _DayNightCard(
        onOpen: (date, slot) => _openOrCreateDated(date, slot: slot),
      ),
      DashboardCard.quote => _QuoteCard(
        quote: _quote,
        loading: _loadingQuote,
        error: _quoteError,
        onRefresh: () => _loadQuote(),
      ),
    };
  }

  void _showCardsSheet(BuildContext context) {
    final t = LumenColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(LumenColors.radiusLg)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final prefs = ref.watch(dashboardPrefsProvider);
            final notifier = ref.read(dashboardPrefsProvider.notifier);
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dashboard cards', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Choose which cards appear. Use Arrange on the dashboard to reorder them.',
                    style: TextStyle(color: t.onSurfaceVariant, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  for (final card in prefs.order)
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(card.icon, size: 20),
                      title: Text(card.label),
                      value: prefs.isVisible(card),
                      onChanged: (v) => notifier.setVisible(card, v),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          notifier.resetLayout();
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Reset to default'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Day / Night cards
// ---------------------------------------------------------------------------

class _DayNightCard extends StatelessWidget {
  const _DayNightCard({required this.onOpen});

  final void Function(DateTime date, String slot) onOpen;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wb_twilight, size: 18),
                const SizedBox(width: 8),
                Text('Plan & reflect', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ActionTile(
                    icon: Icons.wb_sunny_outlined,
                    title: 'Morning \u2014 Plan the day',
                    subtitle: 'Set intentions and priorities',
                    color: t.warning,
                    onTap: () => onOpen(today, 'morning'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionTile(
                    icon: Icons.nights_stay_outlined,
                    title: 'Evening \u2014 Reflect',
                    subtitle: 'Gratitude, wins, and lessons',
                    color: t.info,
                    onTap: () => onOpen(today, 'evening'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Creates a dated entry if one doesn\u2019t exist yet.',
              style: TextStyle(color: t.onSurfaceVariant, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(LumenColors.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LumenColors.radiusMd),
            border: Border.all(color: t.outlineVariant),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.12),
                t.surfaceContainer.withValues(alpha: 0.6),
              ],
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: t.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: t.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quote card
// ---------------------------------------------------------------------------

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.quote,
    required this.loading,
    required this.error,
    required this.onRefresh,
  });

  final Quote? quote;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final q = quote ?? const Quote(text: '...', author: '');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.format_quote_outlined, size: 18),
                const SizedBox(width: 8),
                Text('Wizarding wisdom', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  tooltip: 'Another quote',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: loading ? null : onRefresh,
                  icon: loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.shuffle),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '\u201c${q.text}\u201d',
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                fontStyle: FontStyle.italic,
                color: t.onSurface,
              ),
            ),
            if (q.author.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '\u2014 ${q.author}',
                  style: TextStyle(color: t.onSurfaceVariant),
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: TextStyle(color: t.warning, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}
