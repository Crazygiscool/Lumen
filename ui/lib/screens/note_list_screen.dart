import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../utils/responsive.dart';
import '../widgets/entry_card.dart';
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
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Folder name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
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
              child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error))),
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
              child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ],
      ),
    );
    if (confirm == true) {
      ref.read(entriesProvider.notifier).deleteEntry(id);
    }
  }

  void _showContextMenu(BuildContext context, TapDownDetails details, String id) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        overlay.size.width - details.globalPosition.dx,
        overlay.size.height - details.globalPosition.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error, size: 20),
              const SizedBox(width: 8),
              const Text('Delete Note'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'delete') {
        _deleteEntry(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final allEntries = ref.watch(entriesProvider);
    final folders = ref.read(entriesProvider.notifier).listFolders();
    final notes = allEntries.where((e) => e.kind == 'note').toList();
    final filtered = _selectedFolderId == null
        ? notes
        : notes.where((e) => e.parentProjectId == _selectedFolderId).toList();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final narrow = isNarrow(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: narrow ? null : AppBar(
        title: const Text('Notes'),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bolt_outlined),
            tooltip: 'Quick Note',
            onPressed: () async {
              await showDialog(
                context: context,
                builder: (_) => const QuickNoteScreen(),
              );
              ref.read(entriesProvider.notifier).refresh();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Folder bar
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
                    label: const Text('All Notes'),
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
                      child: FilterChip(
                        label: Text(name),
                        avatar: Icon(Icons.folder_outlined, size: 16, color: selected ? cs.onPrimaryContainer : cs.primary),
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
                    label: const Text('New Folder'),
                    onPressed: _showNewFolderDialog,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          // Notes list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.note_alt_outlined, size: 64, color: cs.outlineVariant),
                        const SizedBox(height: 16),
                        Text(
                          _selectedFolderId == null
                              ? 'No notes yet'
                              : 'No notes in this folder',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: EntryCard(
                          title: entry.displayTitle.isNotEmpty
                              ? entry.displayTitle
                              : entry.id,
                          preview: entry.author,
                          kind: entry.kind,
                          tags: entry.tags,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    EntryViewScreen(entry: entry)),
                          ),
                          onSecondaryTap: (details) => _showContextMenu(context, details, entry.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NewEntryScreen()),
          );
          ref.read(entriesProvider.notifier).refresh();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
