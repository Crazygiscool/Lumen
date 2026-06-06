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
  final _kinds = ['all', 'journal', 'note', 'task', 'project'];
  String _filterKind = 'all';

  void _openNewEntry() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NewEntryScreen()),
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
    final entries = _filterKind == 'all'
        ? allEntries
        : allEntries.where((e) => e.kind == _filterKind).toList();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lumen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const _PlaceholderScreen(title: 'Settings')),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _kinds.map((kind) {
                final selected = kind == _filterKind;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(kind),
                    selected: selected,
                    onSelected: (_) => setState(() => _filterKind = kind),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const EmptyState(message: "No entries yet")
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
        onPressed: _openNewEntry,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  final String title;
  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: Text(title)));
  }
}
