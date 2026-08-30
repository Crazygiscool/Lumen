import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/fs_service.dart';
import '../state/providers.dart';
import '../theme/lumen_colors.dart';

/// In-app folder picker built on Lumen's own file service (no native dialogs).
///
/// Returns the selected directory path, or null when cancelled.
Future<String?> showFolderPicker(
  BuildContext context, {
  String? initialPath,
  String title = 'Choose a folder',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _FolderPickerDialog(
      title: title,
      initialPath: initialPath,
    ),
  );
}

class _FolderPickerDialog extends ConsumerStatefulWidget {
  const _FolderPickerDialog({required this.title, this.initialPath});

  final String title;
  final String? initialPath;

  @override
  ConsumerState<_FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends ConsumerState<_FolderPickerDialog> {
  late String _path;
  late final TextEditingController _pathCtl;
  List<FsEntry> _dirs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath ?? Platform.environment['HOME'] ?? '/';
    _pathCtl = TextEditingController(text: _path);
    _load();
  }

  @override
  void dispose() {
    _pathCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fs = ref.read(fsServiceProvider);
      final entries = await fs.list(_path);
      final dirs = [
        for (final e in entries)
          if (e.isDir && !e.isHidden) e,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) {
        setState(() {
          _dirs = dirs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _open(String path) {
    setState(() {
      _path = path;
      _pathCtl.text = path;
    });
    _load();
  }

  void _up() {
    final parent = Directory(_path).parent.path;
    if (parent == _path) return;
    _open(parent);
  }

  List<String> _crumbs() {
    final parts = _path.split(Platform.pathSeparator).where((p) => p.isNotEmpty).toList();
    final crumbs = <String>[];
    if (_path.startsWith('/')) crumbs.add('/');
    var acc = _path.startsWith('/') ? '/' : '';
    for (final p in parts) {
      acc = acc.endsWith('/') ? '$acc$p' : '$acc/$p';
      crumbs.add(p);
    }
    return crumbs;
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.folder_open, size: 20, color: t.primary),
          const SizedBox(width: 8),
          Text(widget.title, style: const TextStyle(fontSize: 17)),
        ],
      ),
      content: SizedBox(
        width: 460,
        height: 380,
        child: Column(
          children: [
            TextField(
              controller: _pathCtl,
              decoration: InputDecoration(
                labelText: 'Path',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Go',
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  onPressed: () => _open(_pathCtl.text.trim()),
                ),
              ),
              onSubmitted: (v) => _open(v.trim()),
              onChanged: (v) => _path = v,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Up',
                    onPressed: _up,
                    icon: const Icon(Icons.arrow_upward, size: 18),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < _crumbs().length; i++)
                            _crumb(i),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: t.error)))
                  : _dirs.isEmpty
                  ? Center(
                      child: Text(
                        'No subfolders here.',
                        style: TextStyle(color: t.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _dirs.length,
                      itemBuilder: (c, i) {
                        final e = _dirs[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.folder_outlined,
                            size: 18,
                            color: t.info,
                          ),
                          title: Text(
                            e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            size: 16,
                          ),
                          onTap: () => _open(e.path),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _path),
          icon: const Icon(Icons.check, size: 18),
          label: Text('Use this folder'),
        ),
      ],
    );
  }

  Widget _crumb(int i) {
    final t = LumenColors.of(context);
    final crumbs = _crumbs();
    final label = crumbs[i];
    final isLast = i == crumbs.length - 1;

    // Recompute the absolute path of each crumb.
    var acc = _path.startsWith('/') ? '/' : '';
    for (var j = 0; j <= i; j++) {
      final part = crumbs[j];
      acc = acc.endsWith('/') ? '$acc$part' : '$acc/$part';
    }

    return InkWell(
      onTap: isLast ? null : () => _open(acc),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          label == '/' ? '/' : isLast ? label : '$label  ›',
          style: TextStyle(
            fontSize: 12.5,
            fontFamily: 'Geist Mono',
            color: isLast ? t.onSurface : t.primary,
            fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}