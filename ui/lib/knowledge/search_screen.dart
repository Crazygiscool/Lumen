import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/lumen_colors.dart';
import 'highlight.dart';
import 'kb_provider.dart';
import 'kb_service.dart';

/// How the result list is narrowed by date.
enum DateFilter { all, today, week, month }

extension DateFilterInfo on DateFilter {
  String get label => switch (this) {
    DateFilter.all => 'All time',
    DateFilter.today => 'Today',
    DateFilter.week => 'This week',
    DateFilter.month => 'This month',
  };

  /// Whether a note dated [date] falls in this range.
  bool matches(DateTime? date, DateTime now) {
    if (date == null) return this == DateFilter.all;
    return switch (this) {
      DateFilter.all => true,
      DateFilter.today =>
        date.year == now.year &&
        date.month == now.month &&
        date.day == now.day,
      DateFilter.week => !date.isAfter(now) && now.difference(date).inDays < 7,
      DateFilter.month =>
        date.year == now.year &&
        date.month == now.month &&
        !date.isAfter(now),
    };
  }
}

/// The full-text search screen.
///
/// The query is debounced so a fast typist does not trigger one search per
/// keystroke, and the results carry the matched terms highlighted.
class KnowledgeSearchScreen extends ConsumerStatefulWidget {
  const KnowledgeSearchScreen({super.key});

  @override
  ConsumerState<KnowledgeSearchScreen> createState() =>
      _KnowledgeSearchScreenState();
}

class _KnowledgeSearchScreenState extends ConsumerState<KnowledgeSearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  Timer? _debounce;
  String _query = '';
  final Set<String> _tags = {};
  DateFilter _date = DateFilter.all;

  /// Paths of the notes carrying each selected tag.
  final Map<String, List<String>> _tagPaths = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Runs the search 150ms after the last keystroke.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _query = value);
    });
    setState(() {});
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _query = '');
    _focus.requestFocus();
  }

  /// Turns a tag filter on or off.
  ///
  /// Turning one on loads the notes carrying it, so the filter can be
  /// applied to the hits without reading every note's frontmatter.
  Future<void> _toggleTag(String tag) async {
    if (_tags.remove(tag)) {
      setState(() {});
      return;
    }
    setState(() => _tags.add(tag));
    if (_tagPaths.containsKey(tag)) return;
    try {
      final paths = await ref.read(kbServiceProvider).queryFrontmatter(tag: tag);
      if (!mounted) return;
      setState(() => _tagPaths[tag] = paths);
    } catch (_) {
      // A failed filter leaves the tag selected but matches nothing.
      if (mounted) setState(() => _tagPaths[tag] = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final unlocked = ref.watch(journalVaultProvider).unlocked;

    if (!unlocked) {
      return Center(
        child: Text(
          'Unlock the journal to search it.',
          style: TextStyle(color: t.onSurfaceVariant),
        ),
      );
    }

    final results = ref.watch(kbSearchProvider(_query));

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  onChanged: _onChanged,
                  onSubmitted: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search notes…',
                    border: const OutlineInputBorder(),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            onPressed: _clear,
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Ctrl+K',
                style: TextStyle(color: t.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _FilterBar(
            tags: _tags,
            date: _date,
            availableTags:
                ref.watch(kbTagsProvider).asData?.value ?? const <String>[],
            onTagToggle: _toggleTag,
            onDateChanged: (date) => setState(() => _date = date),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: results.when(
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (e, _) => Center(
                child: Text(
                  'Search failed: $e',
                  style: TextStyle(color: t.error),
                ),
              ),
              data: (hits) {
                if (_query.trim().isEmpty) {
                  return Center(
                    child: Text(
                      'Type to search titles, bodies, tags and frontmatter.',
                      style: TextStyle(color: t.onSurfaceVariant),
                    ),
                  );
                }
                final filtered = _applyFilters(hits);
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      'Nothing matches “${_query.trim()}”.',
                      style: TextStyle(color: t.onSurfaceVariant),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final hit = filtered[i];
                    return ListTile(
                      leading: Icon(
                        Icons.article_outlined,
                        color: t.onSurfaceVariant,
                      ),
                      title: Text(
                        hit.title.isEmpty ? hit.path : hit.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          HighlightedSnippet(
                            hit.snippet,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hit.path,
                            style: TextStyle(
                              color: t.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      onTap: () => ref
                          .read(openNoteProvider.notifier)
                          .open(hit.path),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Narrows the hits by the selected tags and date range.
  List<KbSearchHit> _applyFilters(List<KbSearchHit> hits) {
    if (_tags.isEmpty && _date == DateFilter.all) return hits;
    final now = DateTime.now();

    return hits.where((hit) {
      if (_date != DateFilter.all && !_date.matches(_dateOf(hit.path), now)) {
        return false;
      }
      for (final tag in _tags) {
        final paths = _tagPaths[tag];
        // A tag whose notes have not been loaded yet matches nothing.
        if (paths == null || !paths.contains(hit.path)) return false;
      }
      return true;
    }).toList();
  }

  /// The date a note's path carries, if it follows the `YYYY-MM-DD` shape.
  static DateTime? _dateOf(String path) {
    final match = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(path);
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }
}

/// The tag and date filters above the result list.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.tags,
    required this.date,
    required this.availableTags,
    required this.onTagToggle,
    required this.onDateChanged,
  });

  final Set<String> tags;
  final DateFilter date;
  final List<String> availableTags;
  final ValueChanged<String> onTagToggle;
  final ValueChanged<DateFilter> onDateChanged;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final filter in DateFilter.values)
          FilterChip(
            selected: filter == date,
            label: Text(filter.label),
            onSelected: (_) => onDateChanged(filter),
            selectedColor: t.primary.withValues(alpha: 0.2),
            checkmarkColor: t.primary,
          ),
        if (availableTags.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            'Tags',
            style: TextStyle(color: t.onSurfaceVariant, fontSize: 12),
          ),
          for (final tag in availableTags)
            FilterChip(
              selected: tags.contains(tag),
              label: Text(tag),
              onSelected: (_) => onTagToggle(tag),
              selectedColor: t.primary.withValues(alpha: 0.2),
              checkmarkColor: t.primary,
            ),
        ],
      ],
    );
  }
}
