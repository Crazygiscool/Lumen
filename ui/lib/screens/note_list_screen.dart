import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'entry_view_screen.dart';
import 'new_entry_screen.dart';
import 'quick_note_screen.dart';

class NoteListScreen extends ConsumerStatefulWidget {
  const NoteListScreen({super.key});

  @override
  ConsumerState<NoteListScreen> createState() => _NoteListScreenState();
}

class _NoteListScreenState extends ConsumerState<NoteListScreen> {
  String? _selectedFolderId;

  void _showNewFolderDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Folder name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref
                    .read(entriesProvider.notifier)
                    .createFolder(controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFolder(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text('Entries in this folder will be unlinked.'),
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
      ref.read(entriesProvider.notifier).deleteFolder(id);
      if (_selectedFolderId == id) {
        setState(() => _selectedFolderId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allEntries = ref.watch(entriesProvider);
    final folders = ref.read(entriesProvider.notifier).listFolders();
    final notes = allEntries.where((e) => e.kind == 'note').toList();
    final filtered = _selectedFolderId == null
        ? notes
        : notes.where((e) => e.parentProjectId == _selectedFolderId).toList();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bolt),
            tooltip: 'Quick Note',
            onPressed: () async {
              await showDialog(
                context: context,
                builder: (_) => const QuickNoteScreen(),
              );
              ref.read(entriesProvider.notifier).refresh();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NewEntryScreen()),
              );
              ref.read(entriesProvider.notifier).refresh();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Folder bar
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _selectedFolderId == null,
                    onSelected: (_) =>
                        setState(() => _selectedFolderId = null),
                  ),
                ),
                ...folders.map((f) {
                  final id = f['id'] as String;
                  final name = f['name'] as String;
                  final selected = id == _selectedFolderId;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onLongPress: () => _deleteFolder(id, name),
                      child: ChoiceChip(
                        label: Text(name),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _selectedFolderId = id),
                      ),
                    ),
                  );
                }),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('Folder'),
                    onPressed: _showNewFolderDialog,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Notes list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _selectedFolderId == null
                          ? 'No notes yet'
                          : 'No notes in this folder',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      final title = entry.displayTitle.isNotEmpty
                          ? entry.displayTitle
                          : entry.id;
                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onLongPress: () {
                            ref
                                .read(entriesProvider.notifier)
                                .togglePin(entry.id);
                          },
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    EntryViewScreen(entry: entry)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (entry.pinned)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 6),
                                        child: Icon(Icons.push_pin,
                                            size: 14,
                                            color: cs.primary),
                                      ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: cs.surfaceContainer,
                                        borderRadius:
                                            BorderRadius.circular(4),
                                        border: Border.all(
                                            color: cs.outlineVariant),
                                      ),
                                      child: Text('note',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: cs.onSurfaceVariant)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      entry.provenance.author,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant),
                                    ),
                                    const Spacer(),
                                    Icon(Icons.more_horiz,
                                        size: 18,
                                        color: cs.onSurfaceVariant),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 18)),
                                const SizedBox(height: 4),
                                Text(
                                  entry.provenance.timestamp,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant),
                                ),
                                if (entry.tags.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Wrap(
                                      spacing: 4,
                                      children: entry.tags
                                          .map((t) => Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: cs.surfaceContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                      color: cs.outlineVariant),
                                                ),
                                                child: Text(t,
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        color: cs
                                                            .onSurfaceVariant)),
                                              ))
                                          .toList(),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
