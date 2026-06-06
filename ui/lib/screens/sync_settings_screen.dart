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

  Future<void> _syncNow() async {
    final syncPath = ref.read(syncPathProvider);
    if (syncPath == null) return;

    setState(() => _syncing = true);

    try {
      final lumen = ref.read(lumenCoreProvider);
      final entries = ref.read(entriesProvider);
      final entryIds = entries.map((e) => e.id).toList();

      final syncDb = '$syncPath/lumen_sync.db';

      // Push local entries to sync DB
      final pushed = lumen.syncPush(syncDb, entryIds);
      if (pushed < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text('Sync push failed')),
          );
        }
        return;
      }

      // Pull remote entries from sync DB
      final pulledJson = lumen.syncPull(syncDb);
      final pulledList = jsonDecode(pulledJson) as List;
      final pulledEntries =
          pulledList.map((e) => JournalEntry.fromJson(e as Map<String, dynamic>)).toList();

      // Import pulled entries into primary DB
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
