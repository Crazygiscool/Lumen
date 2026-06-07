import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lumen'),
      ),
      body: Column(
        children: [
          if (sortedTags.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('all'),
                      selected: _filterTag == null,
                      onSelected: (_) => setState(() => _filterTag = null),
                    ),
                  ),
                  ...sortedTags.map((tag) {
                    final selected = tag == _filterTag;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(tag),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _filterTag = selected ? null : tag),
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
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Dismissible(
                        key: ValueKey(entry.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: theme.colorScheme.error,
                          child: const Icon(Icons.delete, color: Colors.white),
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
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showKindMenu(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showKindMenu(BuildContext context) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(1, 1, 1, 1),
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
