import 'package:flutter/material.dart';
import '../core/lumen_core.dart';
import '../core/models/journal_entry.dart';
import 'entry_view_screen.dart';
import 'new_entry_screen.dart';
import '../widgets/entry_card.dart';
import '../widgets/empty_state.dart';

class JournalListScreen extends StatefulWidget {
  final LumenCore lumen;

  const JournalListScreen({
    super.key,
    required this.lumen,
  });

  @override
  State<JournalListScreen> createState() => _JournalListScreenState();
}

class _JournalListScreenState extends State<JournalListScreen> {
  List<JournalEntry> _entries = [];
  String _filterKind = 'all';

  final _kinds = ['all', 'journal', 'note', 'task', 'project'];

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  void _loadEntries() {
    setState(() {
      _entries = widget.lumen.listEntries();
    });
  }

  List<JournalEntry> get _filteredEntries {
    if (_filterKind == 'all') return _entries;
    return _entries.where((e) => e.kind == _filterKind).toList();
  }

  void _openNewEntry() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewEntryScreen(lumen: widget.lumen),
      ),
    );
    _loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filteredEntries;

    return Scaffold(
      appBar: AppBar(title: const Text('Journal')),

      body: Column(
        children: [
          // Kind filter bar
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

          // Entry list
          Expanded(
            child: entries.isEmpty
                ? const EmptyState(message: "No entries yet")
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];

                      return EntryCard(
                        title: entry.displayTitle.isNotEmpty
                            ? entry.displayTitle
                            : entry.id,
                        preview: entry.author,
                        kind: entry.kind,
                        tags: entry.tags,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EntryViewScreen(
                                entry: entry,
                                lumen: widget.lumen,
                              ),
                            ),
                          );
                        },
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
