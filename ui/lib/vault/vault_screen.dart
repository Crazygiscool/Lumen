import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/vault_service.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/lumen_colors.dart';
import '../theme/glass.dart';

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key, required this.tabId});

  final String tabId;

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  bool _customRoot = false;

  VaultNavNotifier get _nav =>
      ref.read(vaultNavProvider(widget.tabId).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(vaultProvider.notifier).recover();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultProvider);
    final v = ref.watch(vaultServiceProvider);
    final nav = ref.watch(vaultNavProvider(widget.tabId));

    if (!vault.unlocked) {
      return _VaultGate(
        customRoot: _customRoot,
        onToggleCustom: () => setState(() => _customRoot = !_customRoot),
        onUnlock: (path, pass) async {
          try {
            if (_customRoot) {
              await ref.read(vaultProvider.notifier).create(path, pass);
            } else {
              await ref.read(vaultProvider.notifier).unlock(path, pass);
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(
                context,
              )?.showSnackBar(SnackBar(content: Text(e.toString())));
            }
          }
        },
      );
    }

    if (nav.editing != null) {
      return _NoteEditor(
        notePath: nav.editing!,
        vault: v,
        onBack: () => _nav.closeEditor(),
      );
    }

    return _NoteExplorer(
      vault: v,
      dir: nav.folder,
      selected: nav.selected,
      onLock: () => ref.read(vaultProvider.notifier).lock(),
      onSelect: (e) => _nav.select(e?.relPath),
      onOpen: (e) => _nav.openNote(e.relPath),
      onNewNote: _newNote,
      onDelete: _deleteNote,
    );
  }

  Future<void> _newNote() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'note-name.md',
            helperText: 'Saved inside the encrypted vault',
          ),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final fname = name.toLowerCase().endsWith('.md') ? name : '$name.md';
    try {
      await ref.read(vaultServiceProvider).writeText(fname, '# $name\n\n');
      _nav.openNote(fname);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not create note: $e')));
      }
    }
  }

  Future<void> _deleteNote(VaultEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${e.name}?'),
        content: Text(
          'This permanently removes the note from the encrypted vault.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LumenColors.of(context).errorContainer,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(vaultServiceProvider).delete(e.relPath);
      if (ref.read(vaultNavProvider(widget.tabId)).selected == e.relPath) {
        _nav.select(null);
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: ${err.toString()}')),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------

class _VaultGate extends ConsumerStatefulWidget {
  const _VaultGate({
    required this.customRoot,
    required this.onToggleCustom,
    required this.onUnlock,
  });

  final bool customRoot;
  final VoidCallback onToggleCustom;
  final Future<void> Function(String path, String pass) onUnlock;

  @override
  ConsumerState<_VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends ConsumerState<_VaultGate> {
  final _path = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _path.dispose();
    _pass.dispose();
    super.dispose();
  }

  String _defaultPath() {
    final home = Platform.environment['HOME'] ?? '/';
    return '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}lumen-vault';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.customRoot) {
      _path.text = _defaultPath();
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: LumenColors.of(context).primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.lock_outline,
                        color: LumenColors.of(context).primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Encrypted Vault',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Notes live encrypted on disk (Argon2id + AES-256-GCM).',
                            style: TextStyle(
                              fontSize: 12,
                              color: LumenColors.of(context).onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (widget.customRoot)
                  TextField(
                    controller: _path,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Vault folder path',
                      hintText: '/home/you/Documents/lumen-vault',
                    ),
                  )
                else
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Vault folder',
                    ),
                    child: Text(
                      _defaultPath(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: lumenMonoFont,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: widget.onToggleCustom,
                      icon: Icon(
                        widget.customRoot ? Icons.check : Icons.edit_outlined,
                        size: 16,
                      ),
                      label: Text(
                        widget.customRoot
                            ? ' Using provided path'
                            : ' Use a custom path',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Passphrase',
                    hintText: 'At least 8 characters',
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          widget.customRoot
                              ? 'Create & unlock vault'
                              : 'Unlock vault',
                        ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.customRoot
                      ? 'This will create and fully encrypt the folder. No files remain readable on disk.'
                      : 'If the folder does not exist yet, it will be created as an empty vault.',
                  style: TextStyle(
                    fontSize: 11,
                    color: LumenColors.of(context).onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final path = _path.text.trim();
    final pass = _pass.text;
    if (path.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a vault path')));
      return;
    }
    if (pass.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passphrase must be at least 8 characters'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onUnlock(path, pass);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ---------------------------------------------------------------------------

class _NoteExplorer extends ConsumerWidget {
  const _NoteExplorer({
    required this.vault,
    required this.dir,
    required this.selected,
    required this.onLock,
    required this.onSelect,
    required this.onOpen,
    required this.onNewNote,
    required this.onDelete,
  });

  final VaultService vault;
  final String? dir;
  final String? selected;
  final VoidCallback onLock;
  final ValueChanged<VaultEntry?> onSelect;
  final ValueChanged<VaultEntry> onOpen;
  final VoidCallback onNewNote;
  final ValueChanged<VaultEntry> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(_vaultListProvider);
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: Glass(
            blurSigma: 14,
            radius: 0,
            fill: LumenColors.of(context).surfaceContainer,
            border: false,
            child: Row(
              children: [
                Icon(
                  Icons.lock,
                  size: 14,
                  color: LumenColors.of(context).success,
                ),
                const SizedBox(width: 8),
                Text(
                  'VAULT',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    color: LumenColors.of(context).outline,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Markdown notes · AES-256-GCM',
                    style: TextStyle(
                      fontSize: 12,
                      color: LumenColors.of(context).onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'New note',
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: onNewNote,
                ),
                IconButton(
                  tooltip: 'Lock',
                  icon: const Icon(Icons.lock_outline, size: 18),
                  onPressed: onLock,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: entries.when(
            loading: () =>
                Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => Center(
              child: Text(
                'Could not list vault: $e',
                style: TextStyle(color: LumenColors.of(context).error),
              ),
            ),
            data: (notes) {
              if (notes.isEmpty) {
                return Center(
                  child: Text(
                    'No notes yet. Create one with the + button.',
                    style: TextStyle(
                      color: LumenColors.of(context).onSurfaceVariant,
                    ),
                  ),
                );
              }
              return ListView.builder(
                itemCount: notes.length,
                itemBuilder: (c, i) {
                  final n = notes[i];
                  return ListTile(
                    dense: true,
                    selected: n.relPath == selected,
                    selectedTileColor: LumenColors.of(context).surfaceContainer,
                    leading: Icon(
                      n.isDir
                          ? Icons.folder_outlined
                          : Icons.description_outlined,
                      size: 18,
                      color: n.isDir
                          ? LumenColors.of(context).info
                          : LumenColors.of(context).primary,
                    ),
                    title: Text(
                      n.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                    subtitle: n.isDir
                        ? null
                        : Text(
                            formatDate(n.modifiedMs),
                            style: const TextStyle(fontSize: 11),
                          ),
                    onTap: () {
                      onSelect(n);
                      if (!n.isDir) onOpen(n);
                    },
                    onLongPress: () =>
                        showMenu(
                          context: context,
                          position: const RelativeRect.fromLTRB(100, 100, 0, 0),
                          items: [
                            PopupMenuItem(
                              value: 'open',
                              child: Text(n.isDir ? 'Open folder' : 'Open'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: const Text('Delete…'),
                            ),
                          ],
                        ).then((v) {
                          if (v == 'open' && !n.isDir) onOpen(n);
                          if (v == 'delete') onDelete(n);
                        }),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

final _vaultListProvider = FutureProvider.autoDispose<List<VaultEntry>>((ref) {
  return ref.watch(vaultServiceProvider).list();
});

// ---------------------------------------------------------------------------

class _NoteEditor extends ConsumerStatefulWidget {
  const _NoteEditor({
    required this.notePath,
    required this.vault,
    required this.onBack,
  });
  final String notePath;
  final VaultService vault;
  final VoidCallback onBack;

  @override
  ConsumerState<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<_NoteEditor> {
  late final TextEditingController _ctl;
  String? _raw;
  bool _preview = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController();
    _load();
  }

  @override
  void didUpdateWidget(_NoteEditor old) {
    super.didUpdateWidget(old);
    if (old.notePath != widget.notePath) {
      _raw = null;
      _ctl.clear();
      _load();
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final text = await widget.vault.readText(widget.notePath);
      if (mounted) {
        _ctl.text = text;
        setState(() => _raw = text);
      }
    } catch (e) {
      if (mounted) setState(() => _raw = '');
    }
  }

  Future<void> _save() async {
    await widget.vault.writeText(widget.notePath, _ctl.text);
    setState(() => _dirty = false);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: Glass(
            blurSigma: 14,
            radius: 0,
            fill: LumenColors.of(context).surfaceContainer,
            border: false,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back to vault',
                  icon: const Icon(Icons.arrow_back, size: 18),
                  onPressed: widget.onBack,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.notePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: lumenMonoFont,
                    ),
                  ),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.edit, size: 16),
                      label: Text('Edit'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.visibility_outlined, size: 16),
                      label: Text('Preview'),
                    ),
                  ],
                  selected: {_preview},
                  onSelectionChanged: (s) => setState(() => _preview = s.first),
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: _dirty ? _save : null,
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _raw == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _preview
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: MarkdownBody(
                    data: _ctl.text,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        fontSize: 15,
                        height: 1.6,
                        color: LumenColors.of(context).onSurface,
                      ),
                      h1: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: LumenColors.of(context).onSurface,
                      ),
                      h2: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                        color: LumenColors.of(context).onSurface,
                      ),
                      h3: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: LumenColors.of(context).onSurface,
                      ),
                      code: const TextStyle(
                        fontFamily: lumenMonoFont,
                        fontSize: 13,
                        color: LumenColors.codeKeyword,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: LumenColors.codeBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      blockquoteDecoration: BoxDecoration(
                        color: LumenColors.of(context).surfaceContainer,
                        border: Border(
                          left: BorderSide(
                            color: LumenColors.of(context).primary,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    controller: _ctl,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontFamily: lumenMonoFont,
                      fontSize: 14,
                      height: 1.6,
                    ),
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: LumenColors.codeBackground,
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => setState(() => _dirty = true),
                  ),
                ),
        ),
      ],
    );
  }
}
