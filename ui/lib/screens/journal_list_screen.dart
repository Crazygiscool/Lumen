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

  void _openNewEntry() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewEntryScreen(lumen: widget.lumen),
      ),
    );

    // Refresh after returning
    _loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Journal')),

      body: _entries.isEmpty
          ? const EmptyState(message: "No entries yet")
          : ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];

                return EntryCard(
                  title: entry.id,
                  preview: entry.author,
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

      floatingActionButton: FloatingActionButton(
        onPressed: _openNewEntry,
        child: const Icon(Icons.add),
      ),
    );
  }
}
