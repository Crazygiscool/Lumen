import 'package:flutter/material.dart';

import '../ffi/lumen_ffi.dart';
import '../ffi/sync_service.dart';
import '../theme/lumen_colors.dart';

/// Shows what changed between the two versions of a conflicted note.
///
/// The difference is worked out by the core, which can read both versions:
/// the one the other device sent is an encrypted file inside the vault, so
/// the app could not have compared them on its own.
class ConflictResolutionScreen extends StatefulWidget {
  const ConflictResolutionScreen({
    super.key,
    required this.conflict,
    required this.vaultPath,
    this.service,
  });

  /// The conflict to resolve.
  final SyncConflict conflict;

  /// The folder holding the vault.
  final String vaultPath;

  /// The service to ask; the native one is used when none is given.
  final SyncService? service;

  @override
  State<ConflictResolutionScreen> createState() =>
      _ConflictResolutionScreenState();
}

class _ConflictResolutionScreenState extends State<ConflictResolutionScreen> {
  late final SyncService _service =
      widget.service ?? SyncService(LumenFfi.instance);

  List<DiffLine>? _lines;
  String? _error;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Ask the core for the difference between the two versions.
  Future<void> _load() async {
    setState(() {
      _lines = null;
      _error = null;
    });
    try {
      final lines = await _service.conflictDiff(
        vaultPath: widget.vaultPath,
        path: widget.conflict.path,
      );
      if (mounted) setState(() => _lines = lines);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Keep one of the two versions.
  Future<void> _resolve({required bool keepLocal}) async {
    setState(() => _resolving = true);
    try {
      await _service.resolveConflict(
        widget.conflict.path,
        keepLocal: keepLocal,
        vaultPath: widget.vaultPath,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _resolving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resolve the conflict: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final lines = _lines;

    return Scaffold(
      appBar: AppBar(title: Text('Conflict: ${widget.conflict.path}')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: t.info, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Local: ${widget.conflict.localModified.toLocal()}  •  '
                    'Remote: ${widget.conflict.remoteModified.toLocal()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody(lines, t)),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _resolving
                        ? null
                        : () => _resolve(keepLocal: false),
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    label: const Text('Keep Remote'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _resolving
                        ? null
                        : () => _resolve(keepLocal: true),
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    label: const Text('Keep Local'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(List<DiffLine>? lines, LumenPalette t) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: t.error, size: 40),
              const SizedBox(height: 12),
              Text(
                'The difference could not be shown.\n$_error',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.error),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    if (lines == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (lines.isEmpty) {
      return Center(
        child: Text(
          'The two versions are the same.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: lines.length,
      itemBuilder: (context, index) => _DiffRow(line: lines[index], palette: t),
    );
  }
}

/// One line of the difference.
class _DiffRow extends StatelessWidget {
  const _DiffRow({required this.line, required this.palette});

  final DiffLine line;
  final LumenPalette palette;

  @override
  Widget build(BuildContext context) {
    final (marker, color) = switch (line.kind) {
      DiffKind.added => ('+', palette.success),
      DiffKind.removed => ('-', palette.error),
      DiffKind.same => (' ', palette.onSurfaceVariant),
    };

    return Container(
      color: line.kind == DiffKind.same ? null : color.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            child: Text(
              marker,
              style: TextStyle(
                color: color,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              line.text,
              style: TextStyle(
                color: line.kind == DiffKind.same
                    ? palette.onSurfaceVariant
                    : palette.onSurface,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
