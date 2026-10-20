import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/lumen_colors.dart';

enum PathPickerMode { directory, file }

/// In-app path picker built on `dart:io` (no native dialogs, no FFI).
///
/// Returns the chosen directory or file path, or null when cancelled.
Future<String?> showPathPicker(
  BuildContext context, {
  required PathPickerMode mode,
  String? initialPath,
  String title = 'Choose a folder',
  List<String> extensions = const [],
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PathPickerDialog(
      mode: mode,
      title: title,
      initialPath: initialPath,
      extensions: extensions,
    ),
  );
}

class _PathPickerDialog extends StatefulWidget {
  const _PathPickerDialog({
    required this.mode,
    required this.title,
    this.initialPath,
    this.extensions = const [],
  });

  final PathPickerMode mode;
  final String title;
  final String? initialPath;
  final List<String> extensions;

  @override
  State<_PathPickerDialog> createState() => _PathPickerDialogState();
}

class _PathPickerDialogState extends State<_PathPickerDialog> {
  late String _path;
  late final TextEditingController _pathCtl;
  bool _showHidden = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    final start = widget.initialPath?.trim();
    _path = (start != null && start.isNotEmpty)
        ? start
        : (widget.mode == PathPickerMode.directory
              ? home
              : Directory.current.path);
    final dir = Directory(_path);
    if (!dir.existsSync()) {
      _path = home;
    }
    _pathCtl = TextEditingController(text: _path);
  }

  @override
  void dispose() {
    _pathCtl.dispose();
    super.dispose();
  }

  Directory get _dir => Directory(_path);

  List<FileSystemEntity> _children() {
    try {
      final entries = _dir.listSync()
        ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      return entries.where((e) {
        final name = e.uri.pathSegments.last;
        if (!_showHidden && name.startsWith('.')) return false;
        if (e is File) return _matches(e.path);
        return true;
      }).toList();
    } catch (e) {
      _error = 'Could not read $_path: $e';
      return const [];
    }
  }

  bool _matches(String path) {
    if (widget.mode == PathPickerMode.directory) return false;
    if (widget.extensions.isEmpty) return true;
    final lower = path.toLowerCase();
    return widget.extensions.any(
      (ext) => lower.endsWith(ext.startsWith('.') ? ext : '.$ext'),
    );
  }

  void _navigate(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _error = null;
      _path = trimmed;
      _pathCtl.text = trimmed;
      _pathCtl.selection = TextSelection.collapsed(offset: trimmed.length);
    });
  }

  void _goUp() {
    final parent = _dir.parent;
    if (parent.path != _path) _navigate(parent.path);
  }

  void _choose() {
    if (widget.mode == PathPickerMode.directory) {
      Navigator.of(context).pop(_path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final children = _children();
    final dirs = children.whereType<Directory>().toList();
    final files = children.whereType<File>().toList();

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Up',
                  onPressed: _goUp,
                  icon: const Icon(Icons.arrow_upward),
                ),
                Expanded(
                  child: TextField(
                    controller: _pathCtl,
                    onSubmitted: _navigate,
                    decoration: InputDecoration(
                      labelText: 'Path',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Go',
                        icon: const Icon(Icons.subdirectory_arrow_left),
                        onPressed: () => _navigate(_pathCtl.text),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: _showHidden ? 'Hide hidden' : 'Show hidden',
                  onPressed: () =>
                      setState(() => _showHidden = !_showHidden),
                  icon: Icon(
                    _showHidden ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: t.error)),
              ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: t.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView(
                  children: [
                    for (final d in dirs)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(_baseName(d.path)),
                        onTap: () => _navigate(d.path),
                      ),
                    for (final f in files)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(_baseName(f.path)),
                        onTap: () => Navigator.of(context).pop(f.path),
                      ),
                    if (children.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('Nothing here')),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (widget.mode == PathPickerMode.directory)
          FilledButton(
            onPressed: _choose,
            child: const Text('Use this folder'),
          ),
      ],
    );
  }

  static String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }
}
