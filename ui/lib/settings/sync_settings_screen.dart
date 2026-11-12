import 'dart:async';

import 'package:flutter/material.dart';

import '../../ffi/lumen_ffi.dart';
import '../../ffi/sync_service.dart';
import '../theme/lumen_colors.dart';
import '../widgets/path_picker.dart';
import '../../sync/conflict_resolution_screen.dart';
import '../../sync/syncthing_wizard.dart';
import '../../sync/webdav_setup_screen.dart';

/// Settings screen for sync configuration.
class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key, required this.vaultPath, this.service});

  final String vaultPath;

  /// The service to ask; the native one is used when none is given.
  final SyncService? service;

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  late final SyncService _syncService =
      widget.service ?? SyncService(LumenFfi.instance);

  SyncStatus? _status;
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refresh(),
    );
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

  /// Show the difference between the two versions of a conflicted note.
  ///
  /// The user is asked to pick a version, so the difference is shown first:
  /// the two versions are encrypted, and only the core can read them both.
  Future<void> _showConflict(SyncConflict conflict) async {
    final resolved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConflictResolutionScreen(
          conflict: conflict,
          vaultPath: widget.vaultPath,
          service: _syncService,
        ),
      ),
    );
    if (resolved ?? false) {
      await _refresh();
    }
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
                  Icon(
                    Icons.error_outline,
                    color: LumenColors.of(context).error,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: LumenColors.of(context).error),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refresh,
                    child: const Text('Retry'),
                  ),
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
            _buildStatusRow(
              'Last Sync',
              status.lastSync?.toLocal().toString() ?? 'Never',
            ),
            _buildStatusRow(
              'Pending Changes',
              status.pendingChanges.toString(),
            ),
            _buildStatusRow('Conflicts', status.conflicts.length.toString()),
            _buildStatusRow(
              'Connected Devices',
              status.deviceStatus.length.toString(),
            ),
            if (status.deviceError != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: t.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.deviceError!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
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
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
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

  /// Choose the method Lumen syncs with.
  ///
  /// The choice is written to the configuration, so it is still there the
  /// next time Lumen starts.
  Future<void> _changeMethod(SyncMethod method) async {
    try {
      await _syncService.setSyncMethod(method);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lumen will sync with $method.')));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not change the sync method: $e')),
      );
    }

    // WebDAV needs an account, so the setup is offered right away.
    if (method == SyncMethod.webdav && mounted) {
      await _showWebDAVSetup();
    }
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
                Text(
                  'Conflicts (${conflicts.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...conflicts.map(
              (c) => ListTile(
                title: Text(c.path),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Local:  ${c.localModified.toLocal()} (${_shortHash(c.localHash)})',
                    ),
                    Text(
                      'Remote: ${c.remoteModified.toLocal()} (${_shortHash(c.remoteHash)})',
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, size: 20),
                      tooltip: 'Keep Local',
                      onPressed: () => _showConflict(c),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_downward, size: 20),
                      tooltip: 'Keep Remote',
                      onPressed: () => _showConflict(c),
                    ),
                  ],
                ),
                onTap: () => _showConflict(c),
              ),
            ),
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
                OutlinedButton.icon(
                  onPressed: _showWebDAVSetup,
                  icon: const Icon(Icons.cloud_outlined, size: 18),
                  label: const Text('WebDAV Account'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The Syncthing wizard, which walks through the installation and the
  /// folder.
  Future<void> _showSetupWizard() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SyncthingWizardScreen(vaultPath: widget.vaultPath),
      ),
    );
    if (mounted) await _refresh();
  }

  /// The WebDAV account.
  Future<void> _showWebDAVSetup() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WebDAVSetupScreen(service: _syncService),
      ),
    );
    if ((saved ?? false) && mounted) {
      await _refresh();
    }
  }

  Widget _buildBackupSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Encrypted Backup',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create a portable, encrypted backup of your entire journal.',
            ),
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

  /// Write an encrypted backup of the journal to a file of the user's
  /// choosing.
  Future<void> _createBackup() async {
    final folder = await showPathPicker(
      context,
      mode: PathPickerMode.directory,
      title: 'Where should the backup be written?',
      initialPath: widget.vaultPath,
    );
    if (folder == null || !mounted) return;

    final name = await _promptText(
      'Name of the backup',
      'lumen-backup-${DateTime.now().toIso8601String()}.lumen.bak.age',
    );
    if (name == null || name.trim().isEmpty || !mounted) return;

    final passphrase = await _promptPassphrase(
      'Enter passphrase for backup encryption',
    );
    if (passphrase == null) return;

    final outputPath = '$folder/${name.trim()}';
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
      }
    }
  }

  /// Restore an encrypted backup into a folder of the user's choosing.
  Future<void> _restoreBackup() async {
    final bundle = await showPathPicker(
      context,
      mode: PathPickerMode.file,
      title: 'Which backup should be restored?',
      extensions: const ['.age'],
    );
    if (bundle == null || !mounted) return;

    final target = await showPathPicker(
      context,
      mode: PathPickerMode.directory,
      title: 'Where should the backup be restored?',
      initialPath: widget.vaultPath,
    );
    if (target == null || !mounted) return;

    final passphrase = await _promptPassphrase(
      'Enter passphrase for backup decryption',
    );
    if (passphrase == null) return;

    try {
      await _syncService.restoreBackup(
        bundlePath: bundle,
        passphrase: passphrase,
        targetDir: target,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Backup restored to $target')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
    }
  }

  Future<String?> _promptPassphrase(String message) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  /// Ask for a single line of text.
  Future<String?> _promptText(String message, String initial) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(message),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
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
                Text(
                  'Syncthing Configuration',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton.icon(
                  onPressed: _showSyncthingConfig,
                  icon: const Icon(Icons.code, size: 16),
                  label: const Text('View XML'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Generate Syncthing folder config XML for manual setup.',
            ),
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
              child: SelectableText(
                xml,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
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
