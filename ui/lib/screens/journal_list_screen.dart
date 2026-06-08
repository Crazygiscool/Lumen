import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../utils/responsive.dart';
import 'entry_view_screen.dart';
import 'new_entry_screen.dart';
import '../widgets/entry_card.dart';
import '../widgets/empty_state.dart';

class JournalListScreen extends ConsumerStatefulWidget {
  const JournalListScreen({super.key});

  @override
  ConsumerState<JournalListScreen> createState() => _JournalListScreenState();
}

class _JournalListScreenState extends ConsumerState<JournalListScreen> {
  String? _filterTag;
  final _fabKey = GlobalKey();

  void _openNewEntry(String kind) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewEntryScreen(initialKind: kind),
      ),
    );
    ref.read(entriesProvider.notifier).refresh();
  }

  Future<void> _deleteEntry(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      ref.read(entriesProvider.notifier).deleteEntry(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allEntries = ref.watch(entriesProvider);
    final journalEntries =
        allEntries.where((e) => e.kind == 'journal').toList();
    final tags = <String>{};
    for (final e in journalEntries) {
      tags.addAll(e.tags);
    }
    final sortedTags = tags.toList()..sort();
    final entries = _filterTag == null
        ? journalEntries
        : journalEntries
            .where((e) => e.tags.contains(_filterTag))
            .toList();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final narrow = isNarrow(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: narrow ? null : AppBar(
        title: const Text('Journal'),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          if (sortedTags.isNotEmpty)
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('All Entries'),
                      selected: _filterTag == null,
                      onSelected: (_) => setState(() => _filterTag = null),
                      backgroundColor: cs.surfaceContainerHigh,
                      selectedColor: cs.primaryContainer,
                    ),
                  ),
                  ...sortedTags.map((tag) {
                    final selected = tag == _filterTag;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text('#$tag'),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _filterTag = selected ? null : tag),
                        backgroundColor: cs.surfaceContainerHigh,
                        selectedColor: cs.primaryContainer,
                      ),
                    );
                  }),
                ],
              ),
            ),
          Expanded(
            child: entries.isEmpty
                ? const EmptyState(message: "No journal entries yet")
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Dismissible(
                          key: ValueKey(entry.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
                          ),
                          confirmDismiss: (_) async {
                            await _deleteEntry(entry.id);
                            return false;
                          },
                          child: EntryCard(
                            title: entry.displayTitle.isNotEmpty
                                ? entry.displayTitle
                                : entry.id,
                            preview: entry.author,
                            kind: entry.kind,
                            status: entry.status,
                            mood: entry.mood,
                            tags: entry.tags,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      EntryViewScreen(entry: entry),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: _fabKey,
        onPressed: () => _showKindMenu(context),
        label: const Text('New Entry'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  void _showKindMenu(BuildContext context) {
    final renderBox = _fabKey.currentContext?.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero);
    if (offset == null) return;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy,
        offset.dx + renderBox!.size.width,
        offset.dy + renderBox.size.height,
      ),
      items: const [
        PopupMenuItem(value: 'journal', child: Text('Journal')),
        PopupMenuItem(value: 'note', child: Text('Note')),
        PopupMenuItem(value: 'task', child: Text('Task')),
        PopupMenuItem(value: 'project', child: Text('Project')),
      ],
    ).then((kind) {
      if (kind != null) _openNewEntry(kind);
    });
  }
}
