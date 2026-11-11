import 'dart:async';

import 'package:flutter/material.dart';

import '../../ffi/lumen_ffi.dart';
import '../../ffi/sync_service.dart';
import '../theme/lumen_colors.dart';

/// Settings screen for sync configuration.
class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key, required this.vaultPath});

  final String vaultPath;

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  late final SyncService _syncService;

  SyncStatus? _status;
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    final ffi = LumenFfi.instance;
    _syncService = SyncService(ffi);
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _syncService.init(widget.vaultPath);
      final status = await _syncService.status();
      if (mounted) {
        setState(() {
          _status = status;
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

  Future<void> _resolveConflict(SyncConflict conflict, bool keepLocal) async {
    try {
      await _syncService.resolveConflict(conflict.path, keepLocal: keepLocal);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Resolved conflict for ${conflict.path}')),
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resolve conflict: $e')),
        );
      }
    }
  }

  Future<void> _showConflictDialog(SyncConflict conflict) async {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Conflict: ${conflict.path}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Local:  ${conflict.localModified.toLocal()}'),
            Text('Remote: ${conflict.remoteModified.toLocal()}'),
            const SizedBox(height: 16),
            const Text('Choose which version to keep:'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resolveConflict(conflict, true);
            },
            child: const Text('Keep Local'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resolveConflict(conflict, false);
            },
            child: const Text('Keep Remote'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: LumenColors.of(context).error, size: 48),
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: LumenColors.of(context).error)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _refresh, child: const Text('Retry')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildStatusCard(),
                      const SizedBox(height: 16),
                      _buildMethodSelector(),
                      const SizedBox(height: 16),
                      if (_status?.conflicts.isNotEmpty ?? false) ...[
                        _buildConflictsSection(),
                        const SizedBox(height: 16),
                      ],
                      _buildActionsSection(),
                      const SizedBox(height: 16),
                      _buildBackupSection(),
                      const SizedBox(height: 16),
                      _buildSyncthingConfigSection(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatusCard() {
    final status = _status;
    if (status == null) return const SizedBox.shrink();
    final t = LumenColors.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status.enabled ? Icons.cloud_done : Icons.cloud_off,
                  color: status.enabled ? t.success : t.warning,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status.enabled ? 'Sync Enabled' : 'Sync Disabled',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Method: ${status.method}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatusRow('Last Sync', status.lastSync?.toLocal().toString() ?? 'Never'),
            _buildStatusRow('Pending Changes', status.pendingChanges.toString()),
            _buildStatusRow('Conflicts', status.conflicts.length.toString()),
            _buildStatusRow('Connected Devices', status.deviceStatus.length.toString()),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildMethodSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sync Method', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _methodChip(SyncMethod.syncthing, 'Syncthing', Icons.sync),
                _methodChip(SyncMethod.webdav, 'WebDAV', Icons.cloud),
                _methodChip(SyncMethod.none, 'None (Manual)', Icons.block),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _methodChip(SyncMethod method, String label, IconData icon) {
    final t = LumenColors.of(context);
    final selected = _status?.method == method;
    return FilterChip(
      selected: selected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 8), Text(label)],
      ),
      onSelected: (_) => _changeMethod(method),
      selectedColor: t.primary.withValues(alpha: 0.2),
      checkmarkColor: t.primary,
    );
  }

  Future<void> _changeMethod(SyncMethod method) async {
    // TODO: Update config via FFI
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Changing sync method to $method - restart required')),
    );
  }

  Widget _buildConflictsSection() {
    final conflicts = _status!.conflicts;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Conflicts (${conflicts.length})', style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...conflicts.map((c) => ListTile(
                  title: Text(c.path),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Local:  ${c.localModified.toLocal()} (${_shortHash(c.localHash)})'),
                      Text('Remote: ${c.remoteModified.toLocal()} (${_shortHash(c.remoteHash)})'),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_upward, size: 20),
                        tooltip: 'Keep Local',
                        onPressed: () => _showConflictDialog(c),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_downward, size: 20),
                        tooltip: 'Keep Remote',
                        onPressed: () => _showConflictDialog(c),
                      ),
                    ],
                  ),
                  onTap: () => _showConflictDialog(c),
                )),
          ],
        ),
      ),
    );
  }

  /// First few characters of a content hash, for display.
  static String _shortHash(String hash) =>
      hash.length <= 8 ? hash : hash.substring(0, 8);

  Widget _buildActionsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Actions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Sync Now'),
                ),
                OutlinedButton.icon(
                  onPressed: _showSetupWizard,
                  icon: const Icon(Icons.settings, size: 18),
                  label: const Text('Setup Wizard'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSetupWizard() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Syncthing Setup Wizard'),
        content: const Text('This will open the Syncthing Setup Wizard (not yet implemented).'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  Widget _buildBackupSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Encrypted Backup', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Create a portable, encrypted backup of your entire journal.'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _createBackup,
                    icon: const Icon(Icons.backup, size: 18),
                    label: const Text('Create Backup'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _restoreBackup,
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('Restore Backup'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createBackup() async {
    final passphrase = await _promptPassphrase('Enter passphrase for backup encryption');
    if (passphrase == null) return;

    final outputPath = '/tmp/lumen-backup-${DateTime.now().toIso8601String()}.lumen.bak.age';
    try {
      await _syncService.createBackup(
        vaultPath: widget.vaultPath,
        passphrase: passphrase,
        outputPath: outputPath,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup created at $outputPath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    }
  }

  Future<void> _restoreBackup() async {
    // TODO: Implement file picker for bundle selection
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Restore backup - file picker not yet implemented')),
    );
  }

  Future<String?> _promptPassphrase(String message) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(message),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Passphrase'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Widget _buildSyncthingConfigSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Syncthing Configuration', style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(
                  onPressed: _showSyncthingConfig,
                  icon: const Icon(Icons.code, size: 16),
                  label: const Text('View XML'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Generate Syncthing folder config XML for manual setup.'),
          ],
        ),
      ),
    );
  }

  Future<void> _showSyncthingConfig() async {
    try {
      final xml = await _syncService.generateSyncthingConfig(widget.vaultPath);
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Syncthing Folder Config'),
            content: SingleChildScrollView(
              child: SelectableText(xml, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate config: $e')),
        );
      }
    }
  }
}