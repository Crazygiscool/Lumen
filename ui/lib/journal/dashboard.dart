import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
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
    final source = ref.read(dashboardPrefsProvider).quoteSource;
    setState(() {
      _loadingQuote = true;
      _quoteError = null;
    });
    try {
      Quote q;
      if (source == QuoteSource.online) {
        q = await _quotes.fetchOnline().timeout(const Duration(seconds: 10));
      } else {
        q = _quotes.offline();
      }
      if (mounted) setState(() => _quote = q);
    } catch (e) {
      final fallback = _quotes.offline();
      if (mounted) {
        setState(() {
          _quote = fallback;
          _quoteError = source == QuoteSource.online
              ? 'Couldn\u2019t load online quote \u2014 showing an offline one.'
              : null;
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

    ref.listen<AsyncValue<List<JournalNote>>>(journalNotesProvider, (_, next) {
      if (next.hasValue) _refreshCounts();
    });

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
                      'Your writing activity and a space to plan and reflect',
                      style: TextStyle(color: t.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => _showArrangeSheet(context),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Arrange'),
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
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _cardFor(DashboardCard card) {
    return switch (card) {
      DashboardCard.graph => _ContributionGraph(
        dailyCounts: _dailyCounts,
        loading: _loadingCounts,
        onDayTap: (date) => _openOrCreateDated(date),
      ),
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

  void _showArrangeSheet(BuildContext context) {
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
                  Text('Arrange dashboard', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Drag to reorder, or show/hide cards. Order is saved automatically.',
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
// Contribution graph
// ---------------------------------------------------------------------------

class _ContributionGraph extends StatefulWidget {
  const _ContributionGraph({
    required this.dailyCounts,
    required this.loading,
    required this.onDayTap,
  });

  final Map<String, int> dailyCounts;
  final bool loading;
  final ValueChanged<DateTime> onDayTap;

  @override
  State<_ContributionGraph> createState() => _ContributionGraphState();
}

class _ContributionGraphState extends State<_ContributionGraph> {
  static const _weeks = 20;
  static const _maxWeeksBack = 260; // ~5 years

  /// How many weeks the visible window is shifted into the past.
  int _weeksBack = 0;

  static String _fmt(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = today.subtract(Duration(days: _weeksBack * 7));
    final startDate = end.subtract(const Duration(days: _weeks * 7 - 1));
    final aligned = DateTime(startDate.year, startDate.month, startDate.day)
        .subtract(Duration(days: startDate.weekday - DateTime.monday));

    final values = widget.dailyCounts.values.toList();
    final maxWords = values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b);

    final cells = <Widget>[];
    for (var row = 0; row < 7; row++) {
      final rowWidgets = <Widget>[];
      for (var week = 0; week < _weeks; week++) {
        final day = aligned.add(Duration(days: week * 7 + row));
        if (day.isAfter(end)) {
          continue;
        }
        final iso = _fmt(day);
        final words = widget.dailyCounts[iso] ?? 0;
        double alpha = 0;
        if (words > 0) {
          if (maxWords == 0) {
            alpha = 0.4;
          } else {
            final ratio = (words / maxWords).clamp(0.0, 1.0);
            if (ratio <= 0.25) {
              alpha = 0.35;
            } else if (ratio <= 0.5) {
              alpha = 0.55;
            } else if (ratio <= 0.75) {
              alpha = 0.8;
            } else {
              alpha = 1.0;
            }
          }
        }
        final color = alpha == 0
            ? LumenColors.of(context).surfaceContainer
            : LumenColors.of(context).primary.withValues(alpha: alpha);
        final isToday =
            day.year == now.year && day.month == now.month && day.day == now.day;
        rowWidgets.add(Padding(
          padding: const EdgeInsets.all(1.5),
          child: Tooltip(
            message: words == 0
                ? '$iso — no words'
                : '$iso — ${_formatNumber(words)} word${words == 1 ? '' : 's'}',
            child: InkWell(
              borderRadius: BorderRadius.circular(3),
              onTap: () => widget.onDayTap(day),
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                  border: isToday
                      ? Border.all(color: t.primary, width: 1)
                      : Border.all(
                          color: t.outlineVariant.withValues(alpha: 0.6),
                          width: 0.5,
                        ),
                ),
              ),
            ),
          ),
        ));
      }
      if (rowWidgets.isNotEmpty) {
        cells.add(Row(children: rowWidgets));
      }
    }

    final rangeLabel = _weeksBack == 0
        ? 'Last $_weeks weeks'
        : '${_fmt(aligned)} → ${_fmt(end)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month_outlined, size: 18),
                const SizedBox(width: 8),
                Text('Writing activity', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    rangeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.onSurfaceVariant, fontSize: 11),
                  ),
                ),
                const Spacer(),
                if (widget.loading)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                IconButton(
                  tooltip: 'Earlier',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: _weeksBack >= _maxWeeksBack
                      ? null
                      : () => setState(() => _weeksBack += 12),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Later',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: _weeksBack == 0
                      ? null
                      : () => setState(
                          () => _weeksBack = (_weeksBack - 12).clamp(0, _maxWeeksBack),
                        ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              maxWords == 0
                  ? 'No words yet'
                  : '${_formatNumber(maxWords)} words in your busiest day',
              style: TextStyle(color: t.onSurfaceVariant, fontSize: 11),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: cells,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Less', style: TextStyle(color: t.onSurfaceVariant, fontSize: 10)),
                const SizedBox(width: 6),
                for (final a in const [0.0, 0.35, 0.55, 0.8, 1.0])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: a == 0
                            ? LumenColors.of(context).surfaceContainer
                            : LumenColors.of(context).primary.withValues(alpha: a),
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: t.outlineVariant.withValues(alpha: 0.6),
                          width: 0.5,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Text('More', style: TextStyle(color: t.onSurfaceVariant, fontSize: 10)),
                const Spacer(),
                Flexible(
                  child: Text(
                    'Click a day to open or create it',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: t.onSurfaceVariant, fontSize: 10),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(int n) {
    if (n < 1000) return '$n';
    final digits = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buf.write(',');
      }
      buf.write(digits[i]);
    }
    return buf.toString();
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
