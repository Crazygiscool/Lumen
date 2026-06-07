import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../core/providers.dart';
import '../core/models/journal_entry.dart';

final syncPathProvider = NotifierProvider<SyncPathNotifier, String?>(SyncPathNotifier.new);

class SyncPathNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setPath(String path) => state = path;
}

class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  bool _syncing = false;
  List<Map<String, dynamic>> _conflicts = [];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final syncPath = ref.watch(syncPathProvider);
    final entries = ref.watch(entriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: 'Sync Location'),
          Card(
            child: ListTile(
              leading: Icon(Icons.folder, color: cs.primary),
              title: Text(syncPath ?? 'Not configured'),
              subtitle: Text(
                syncPath != null ? 'Tap to change' : 'Select a sync directory',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.folder_open),
                onPressed: _pickSyncPath,
              ),
            ),
          ),
          if (syncPath != null) ...[
            const SizedBox(height: 16),
            _SectionHeader(title: 'Actions'),
            FilledButton.icon(
              onPressed: _syncing ? null : _syncNow,
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(_syncing ? 'Syncing...' : 'Sync Now'),
            ),
            const SizedBox(height: 16),
            _SectionHeader(title: 'Entry Status'),
            Text(
              '${entries.length} entries ready for sync',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            if (_conflicts.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionHeader(title: 'Conflicts'),
              ..._conflicts.map((c) => _ConflictCard(
                    conflict: c,
                    onAcceptLocal: () => _acceptConflict(c['id'] as String, true),
                    onAcceptRemote: () => _acceptConflict(c['id'] as String, false),
                    colorScheme: cs,
                  )),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _pickSyncPath() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Sync Directory',
    );
    if (path != null) {
      ref.read(syncPathProvider.notifier).setPath(path);
    }
  }

  Future<void> _acceptConflict(String conflictId, bool keepLocal) async {
    final syncPath = ref.read(syncPathProvider);
    if (syncPath == null) return;

    final lumen = ref.read(lumenCoreProvider);
    final ok = lumen.syncAcceptConflict('$syncPath/lumen_sync.db', conflictId, keepLocal);
    if (ok) {
      setState(() => _conflicts.removeWhere((c) => c['id'] == conflictId));
      ref.read(entriesProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(keepLocal ? 'Accepted local version' : 'Accepted remote version')),
        );
      }
    }
  }

  Future<void> _syncNow() async {
    final syncPath = ref.read(syncPathProvider);
    if (syncPath == null) return;

    setState(() => _syncing = true);

    try {
      final lumen = ref.read(lumenCoreProvider);
      final entries = ref.read(entriesProvider);
      final entryIds = entries.map((e) => e.id).toList();

      final syncDb = '$syncPath/lumen_sync.db';

      final pushed = lumen.syncPush(syncDb, entryIds);
      if (pushed < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text('Sync push failed')),
          );
        }
        return;
      }

      final pulledJson = lumen.syncPull(syncDb);
      final pulledList = jsonDecode(pulledJson) as List;
      final pulledEntries =
          pulledList.map((e) => JournalEntry.fromJson(e as Map<String, dynamic>)).toList();

      if (pulledEntries.isNotEmpty) {
        final imported =
            ref.read(entriesProvider.notifier).import(jsonEncode(pulledList));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Synced: $pushed pushed, $imported pulled')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Synced: $pushed pushed, 0 pulled')),
          );
        }
      }

      // Check for conflicts after sync
      final conflictsJson = lumen.syncListConflicts(syncDb);
      final conflictsList = jsonDecode(conflictsJson) as List;
      setState(() => _conflicts = conflictsList.cast<Map<String, dynamic>>());
      if (_conflicts.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_conflicts.length} conflict(s) detected — resolve below')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }
}

class _ConflictCard extends StatelessWidget {
  final Map<String, dynamic> conflict;
  final VoidCallback onAcceptLocal;
  final VoidCallback onAcceptRemote;
  final ColorScheme colorScheme;

  const _ConflictCard({
    required this.conflict,
    required this.onAcceptLocal,
    required this.onAcceptRemote,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: cs.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Entry: ${conflict['entry_id']}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Local: ${conflict['local_timestamp']}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            Text(
              'Remote: ${conflict['remote_timestamp']}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onAcceptLocal,
                    child: const Text('Keep Local'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: onAcceptRemote,
                    child: const Text('Keep Remote'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
