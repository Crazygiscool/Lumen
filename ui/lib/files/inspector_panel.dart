import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/fs_service.dart';
import '../theme/app_theme.dart';
import '../theme/lumen_colors.dart';

class InspectorPanel extends ConsumerStatefulWidget {
  const InspectorPanel({super.key, required this.entry, required this.fs});
  final FsEntry? entry;
  final FsService fs;

  @override
  ConsumerState<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends ConsumerState<InspectorPanel> {
  FsEntry? _fresh;
  Object? _error;

  @override
  void didUpdateWidget(covariant InspectorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry != widget.entry) {
      _refresh();
    }
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final entry = widget.entry;
    setState(() {
      _fresh = null;
      _error = null;
    });
    if (entry == null) return;
    try {
      final s = await widget.fs.stat(entry.path);
      if (mounted) setState(() => _fresh = s);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    if (entry == null) {
      return Container(
        color: LumenColors.of(context).surfaceLow,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Select an item to inspect it.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: LumenColors.of(context).onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ),
      );
    }
    final detail = _fresh ?? entry;
    return Container(
      color: LumenColors.of(context).surfaceLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'INSPECTOR',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      color: LumenColors.of(context).outline,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 14),
                  onPressed: _refresh,
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  detail.isDir
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 28,
                  color: detail.isDir
                      ? LumenColors.of(context).info
                      : LumenColors.of(context).primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    detail.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '$_error',
                style: TextStyle(
                  fontSize: 11,
                  color: LumenColors.of(context).error,
                ),
              ),
            ),
          if (detail.isDir)
            const SizedBox(height: 4)
          else ...[
            const Divider(height: 24, indent: 16, endIndent: 16),
            _row('Size', formatBytes(detail.size)),
          ],
          const Divider(height: 24, indent: 16, endIndent: 16),
          _row('Modified', formatDate(detail.modifiedMs)),
          _row('Kind', detail.isDir ? 'Folder' : 'File'),
          if (detail.extension != null)
            _row('Extension', '.${detail.extension}'),
          if (detail.isSymlink) _row('Link to', detail.symlinkTarget ?? ''),
          _row('Permissions', detail.permissions),
          _row('Owner', detail.owner),
          const Divider(height: 24, indent: 16, endIndent: 16),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Path',
              style: TextStyle(
                fontSize: 11,
                color: LumenColors.of(context).outline,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SelectableText(
              detail.path,
              style: TextStyle(
                fontSize: 11,
                fontFamily: lumenMonoFont,
                color: LumenColors.of(context).onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: LumenColors.of(context).onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontFamily: lumenMonoFont,
                color: LumenColors.of(context).onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
