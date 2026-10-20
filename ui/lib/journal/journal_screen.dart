import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/lumen_colors.dart';
import '../widgets/path_picker.dart';
import 'journal_provider.dart';
import 'journal_service.dart';

/// The journal: an encrypted list of Markdown notes with an inline editor.
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  String? _editing;
  bool _dirty = false;
  bool _preview = false;
  String _search = '';

  final _searchCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final path = ref.read(settingsProvider).journalVaultPath;
      if (path != null && path.isNotEmpty) {
        ref.read(journalVaultProvider.notifier).recover();
      }
    });
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(journalVaultProvider);

    // Locking can happen from Settings too; drop the open note so unlocking a
    // different folder never shows a stale editor.
    ref.listen<VaultUiState>(journalVaultProvider, (previous, next) {
      if (!next.unlocked && _editing != null) {
        setState(() {
          _editing = null;
          _dirty = false;
          _preview = false;
        });
      }
    });

    if (!vault.unlocked) {
      return _JournalGate(
        defaultPath: ref.watch(settingsProvider).journalVaultPath,
      );
    }
    return _buildJournal(context, ref, vault.root);
  }

  Widget _buildJournal(BuildContext context, WidgetRef ref, String? root) {
    final notesAsync = ref.watch(journalNotesProvider);
    final t = LumenColors.of(context);
    return notesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (e, _) => _ErrorState(message: '$e'),
      data: (notes) {
        final query = _search.trim().toLowerCase();
        final filtered = query.isEmpty
            ? notes
            : notes
                  .where(
                    (n) => n.name.toLowerCase().contains(query),
                  )
                  .toList();
        return Row(
          children: [
            SizedBox(
              width: 320,
              child: _JournalList(
                notes: filtered,
                selected: _editing,
                streakDays: ref.read(journalServiceProvider).streak(notes),
                root: root,
                searchController: _searchCtl,
                onSearchChanged: (v) => setState(() => _search = v),
                onNew: _createNote,
                onSelect: _open,
                onLock: _lock,
              ),
            ),
            VerticalDivider(width: 1, color: t.outlineVariant),
            Expanded(
              child: _editing == null
                  ? _EmptyState(onNew: _createNote)
                  : _NoteEditor(
                      key: ValueKey(_editing),
                      relPath: _editing!,
                      preview: _preview,
                      onTogglePreview: () =>
                          setState(() => _preview = !_preview),
                      onDirty: () => setState(() => _dirty = true),
                      onSaved: _onSaved,
                      onDelete: _delete,
                      onClose: _closeEditor,
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createNote() async {
    final service = ref.read(journalServiceProvider);
    final path = await service.newNotePath();
    await service.write(path, '');
    ref.invalidate(journalNotesProvider);
    if (mounted) {
      setState(() {
        _openNow(path);
        _preview = false;
      });
    }
  }

  void _open(String relPath) {
    if (_dirty && _editing != relPath) {
      // Keep it simple: save-on-switch is handled by the editor's own button;
      // switching discards unsaved changes after a prompt.
      _confirmDiscard(() => setState(() => _openNow(relPath)));
      return;
    }
    setState(() => _openNow(relPath));
  }

  void _openNow(String relPath) {
    _editing = relPath;
    _dirty = false;
  }

  void _closeEditor() {
    void close() => setState(() {
      _editing = null;
      _dirty = false;
    });
    if (_dirty) {
      _confirmDiscard(close);
    } else {
      close();
    }
  }

  void _onSaved() {
    setState(() => _dirty = false);
    ref.invalidate(journalNotesProvider);
  }

  Future<void> _delete(String relPath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text('“$relPath” will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(journalServiceProvider).delete(relPath);
    ref.invalidate(journalNotesProvider);
    if (mounted) {
      setState(() {
        _editing = null;
        _dirty = false;
        _preview = false;
      });
    }
  }

  Future<void> _lock() async {
    Future<void> doLock() async {
      await ref.read(journalVaultProvider.notifier).lock();
      ref.invalidate(journalNotesProvider);
      if (mounted) {
        setState(() {
          _editing = null;
          _dirty = false;
          _preview = false;
        });
      }
    }

    if (_dirty) {
      _confirmDiscard(() {
        doLock();
      });
      return;
    }
    await doLock();
  }

  void _confirmDiscard(VoidCallback onDiscard) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text('Your edits have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDiscard();
            },
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Unlock / create gate
// ---------------------------------------------------------------------------

class _JournalGate extends ConsumerStatefulWidget {
  const _JournalGate({this.defaultPath});

  final String? defaultPath;

  @override
  ConsumerState<_JournalGate> createState() => _JournalGateState();
}

class _JournalGateState extends ConsumerState<_JournalGate> {
  final _path = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path.text = widget.defaultPath ?? _defaultFolder();
  }

  static String _defaultFolder() {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    return '$home/Documents/lumen-journal';
  }

  @override
  void dispose() {
    _path.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool create}) async {
    final path = _path.text.trim();
    final pass = _pass.text;
    if (path.isEmpty) {
      setState(() => _error = 'Choose a journal folder.');
      return;
    }
    if (pass.length < 8) {
      setState(() => _error = 'Passphrase must be at least 8 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (create) {
        Directory(path).createSync(recursive: true);
      }
      final notifier = ref.read(journalVaultProvider.notifier);
      if (create) {
        await notifier.create(path, pass);
      } else {
        await notifier.unlock(path, pass);
      }
      ref.read(settingsProvider.notifier).setJournalVaultPath(path);
      ref.invalidate(journalNotesProvider);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _browse() async {
    final picked = await showPathPicker(
      context,
      mode: PathPickerMode.directory,
      initialPath: _path.text,
      title: 'Choose journal folder',
    );
    if (picked != null) setState(() => _path.text = picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Image.asset(
                    'lib/assets/lumen_logo.png',
                    height: 56,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.lock_outline, color: t.primary),
                    const SizedBox(width: 12),
                    Text(
                      'Unlock your journal',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Notes are encrypted on disk with AES-256-GCM. '
                  'The passphrase never leaves this device.',
                  style: TextStyle(color: t.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _path,
                  decoration: InputDecoration(
                    labelText: 'Journal folder',
                    helperText: 'A .lumen folder is created here.',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Browse',
                      icon: const Icon(Icons.folder_open),
                      onPressed: _browse,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  onSubmitted: (_) => _submit(create: false),
                  decoration: const InputDecoration(
                    labelText: 'Passphrase',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: t.error)),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _submit(create: false),
                        child: const Text('Unlock'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : () => _submit(create: true),
                        child: _busy
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Create journal'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// List pane
// ---------------------------------------------------------------------------

class _JournalList extends StatelessWidget {
  const _JournalList({
    required this.notes,
    required this.selected,
    required this.streakDays,
    required this.root,
    required this.searchController,
    required this.onSearchChanged,
    required this.onNew,
    required this.onSelect,
    required this.onLock,
  });

  final List<JournalNote> notes;
  final String? selected;
  final int streakDays;
  final String? root;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onNew;
  final ValueChanged<String> onSelect;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Journal',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      streakDays > 0
                          ? '$streakDays day streak'
                          : '${notes.length} notes',
                      style: TextStyle(
                        color: t.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'New note',
                onPressed: onNew,
                icon: const Icon(Icons.add),
              ),
              IconButton(
                tooltip: 'Lock journal',
                onPressed: onLock,
                icon: const Icon(Icons.lock_outline),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: 'Filter notes…',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: notes.isEmpty
              ? Center(
                  child: Text(
                    'No notes yet.\nCreate your first entry.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  itemCount: notes.length,
                  itemBuilder: (context, i) {
                    final note = notes[i];
                    final active = note.relPath == selected;
                    return ListTile(
                      dense: true,
                      selected: active,
                      leading: Icon(
                        Icons.article_outlined,
                        color: active ? t.primary : t.onSurfaceVariant,
                      ),
                      title: Text(
                        note.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        note.relPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: t.onSurfaceVariant,
                        ),
                      ),
                      onTap: () => onSelect(note.relPath),
                    );
                  },
                ),
        ),
        if (root != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              root!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.onSurfaceVariant, fontSize: 11),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Editor pane
// ---------------------------------------------------------------------------

class _NoteEditor extends ConsumerStatefulWidget {
  const _NoteEditor({
    super.key,
    required this.relPath,
    required this.preview,
    required this.onTogglePreview,
    required this.onDirty,
    required this.onSaved,
    required this.onDelete,
    required this.onClose,
  });

  final String relPath;
  final bool preview;
  final VoidCallback onTogglePreview;
  final VoidCallback onDirty;
  final VoidCallback onSaved;
  final ValueChanged<String> onDelete;
  final VoidCallback onClose;

  @override
  ConsumerState<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<_NoteEditor> {
  final _ctl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final text = await ref.read(journalServiceProvider).read(widget.relPath);
      if (!mounted) return;
      _ctl.text = text;
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final body = _ctl.text;
      await ref
          .read(journalServiceProvider)
          .write(widget.relPath, body);
      String message = 'Saved';
      try {
        final title = _titleOf(body);
        final feedback = await ref
            .read(pluginServiceProvider)
            .run(widget.relPath, title, body);
        if (feedback.isNotEmpty) message = 'Saved — ${feedback.join(' · ')}';
      } catch (_) {
        // Plugins are optional; never block saving a note.
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _titleOf(String body) {
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ')) {
        final title = trimmed.substring(2).trim();
        if (title.isNotEmpty) return title;
      }
    }
    return 'Note';
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.relPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.onSurfaceVariant),
                ),
              ),
              IconButton(
                tooltip: widget.preview ? 'Edit' : 'Preview',
                onPressed: widget.onTogglePreview,
                icon: Icon(
                  widget.preview
                      ? Icons.edit_outlined
                      : Icons.visibility_outlined,
                ),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: () => widget.onDelete(widget.relPath),
                icon: const Icon(Icons.delete_outline),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: TextStyle(color: t.error)),
          ),
        Expanded(
          child: widget.preview
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Markdown(
                    data: _ctl.text.isEmpty ? '_Empty note_' : _ctl.text,
                    selectable: true,
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: TextField(
                    controller: _ctl,
                    onChanged: (_) => widget.onDirty(),
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontFamily: lumenMonoFont,
                      fontSize: 13,
                      height: 1.5,
                    ),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '# Start writing…',
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNew});
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_outlined, size: 48, color: t.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'Select a note or create a new one',
            style: TextStyle(color: t.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onNew,
            icon: const Icon(Icons.add),
            label: const Text('New note'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: t.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
