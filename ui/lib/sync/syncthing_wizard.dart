import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../ffi/lumen_ffi.dart';
import '../../ffi/sync_service.dart';
import '../theme/lumen_colors.dart';

/// Syncthing setup wizard - guides user through Syncthing installation and configuration.
class SyncthingWizardScreen extends StatefulWidget {
  const SyncthingWizardScreen({super.key, required this.vaultPath});

  final String vaultPath;

  @override
  State<SyncthingWizardScreen> createState() => _SyncthingWizardScreenState();
}

class _SyncthingWizardScreenState extends State<SyncthingWizardScreen> {
  late final SyncService _syncService;
  late final LumenFfi _ffi;

  int _step = 0;
  bool _syncthingInstalled = false;
  String? _syncthingVersion;
  String? _apiKey;
  String? _configPath;
  String? _folderId;
  String? _generatedConfig;
  String? _error;
  bool _loading = false;

  static const _steps = [
    'Detect Syncthing',
    'Configure Folder',
    'Device Pairing',
    'Verify Sync',
  ];

  @override
  void initState() {
    super.initState();
    _ffi = LumenFfi.instance;
    _syncService = SyncService(_ffi);
    _detectSyncthing();
  }

  Future<void> _detectSyncthing() async {
    setState(() => _loading = true);
    try {
      // Check if Syncthing is in PATH
      final result = await Process.run('syncthing', ['--version']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        final versionMatch = RegExp(r'v?(\d+\.\d+\.\d+)').firstMatch(output);
        setState(() {
          _syncthingInstalled = true;
          _syncthingVersion = versionMatch?.group(1) ?? 'unknown';
        });
        // Try to find config and API key
        await _findSyncthingConfig();
      } else {
        setState(() => _syncthingInstalled = false);
      }
    } catch (e) {
      setState(() => _syncthingInstalled = false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _findSyncthingConfig() async {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = [
      '$home/.config/syncthing/config.xml',
      '$home/Library/Application Support/Syncthing/config.xml',
      '$home/AppData/Local/Syncthing/config.xml',
    ];
    for (final path in candidates) {
      if (await File(path).exists()) {
        setState(() => _configPath = path);
        // Try to extract API key
        final content = await File(path).readAsString();
        final apiKeyMatch = RegExp(r'<apikey>([^<]+)</apikey>').firstMatch(content);
        if (apiKeyMatch != null) {
          setState(() => _apiKey = apiKeyMatch.group(1));
        }
        break;
      }
    }
  }

  Future<void> _generateConfig() async {
    setState(() => _loading = true);
    try {
      final config = await _syncService.generateSyncthingConfig(widget.vaultPath);
      setState(() {
        _generatedConfig = config;
        // Extract folder ID from generated config
        final folderIdMatch = RegExp(r'id="([^"]+)"').firstMatch(config);
        _folderId = folderIdMatch?.group(1);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSyncthingUI() async {
    if (_apiKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot find Syncthing API key')),
      );
      return;
    }
    // Open Syncthing Web UI in browser
    final uri = Uri.parse('http://127.0.0.1:8384');
    // TODO: Use url_launcher to open browser
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Open Syncthing UI at $uri (API key: $_apiKey)')),
    );
  }

  Future<void> _verifySync() async {
    setState(() => _loading = true);
    try {
      await _syncService.init(widget.vaultPath);
      final status = await _syncService.status();
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sync Verification'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Enabled: ${status.enabled ? "Yes" : "No"}'),
                Text('Method: ${status.method}'),
                Text('Last Sync: ${status.lastSync?.toLocal() ?? "Never"}'),
                Text('Conflicts: ${status.conflicts.length}'),
                Text('Devices: ${status.deviceStatus.length}'),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _nextStep() {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
      if (_step == 1) _generateConfig();
    }
  }

  void _prevStep() {
    if (_step > 0) setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Syncthing Setup Wizard')),
      body: Column(
        children: [
          // Step indicator
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: List.generate(_steps.length, (i) {
                return Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: i <= _step ? t.primary : t.surfaceContainer,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      if (i < _steps.length - 1) const SizedBox(width: 8),
                    ],
                  ),
                );
              }),
            ),
          ),
          // Step label
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Step ${_step + 1}: ${_steps[_step]}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: t.primary),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Step content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorView()
                    : _buildStepContent(),
          ),
          // Navigation
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_step > 0)
                  TextButton.icon(
                    onPressed: _prevStep,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  )
                else
                  const SizedBox(width: 80),
                if (_step < _steps.length - 1)
                  ElevatedButton.icon(
                    onPressed: _canProceed() ? _nextStep : null,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next'),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _verifySync,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Finish'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _canProceed() {
    switch (_step) {
      case 0:
        return _syncthingInstalled;
      case 1:
        return _generatedConfig != null;
      case 2:
        return _apiKey != null;
      default:
        return true;
    }
  }

  Widget _buildErrorView() {
    final t = LumenColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: t.error, size: 48),
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: t.error)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () => setState(() => _error = null), child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _buildDetectStep();
      case 1:
        return _buildConfigureStep();
      case 2:
        return _buildPairingStep();
      case 3:
        return _buildVerifyStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDetectStep() {
    final t = LumenColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _syncthingInstalled ? Icons.check_circle : Icons.error_outline,
            size: 64,
            color: _syncthingInstalled ? t.success : t.warning,
          ),
          const SizedBox(height: 16),
          Text(
            _syncthingInstalled
                ? 'Syncthing detected (v$_syncthingVersion)'
                : 'Syncthing not found',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          if (_syncthingInstalled) ...[
            Text('Config: ${_configPath ?? "Not found"}'),
            Text('API Key: ${_apiKey != null ? "Found" : "Not found"}'),
            const SizedBox(height: 16),
            const Text('Syncthing is ready. Proceed to folder configuration.'),
          ] else ...[
            const SizedBox(height: 16),
            const Text('Please install Syncthing first:'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (Platform.isLinux) ...[
                  ElevatedButton.icon(
                    onPressed: () => _launchUrl('https://syncthing.net/downloads/'),
                    icon: const Icon(Icons.download),
                    label: const Text('Download for Linux'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _launchUrl('https://apt.syncthing.net/'),
                    icon: const Icon(Icons.terminal),
                    label: const Text('Add APT Repository'),
                  ),
                ],
                if (Platform.isMacOS) ...[
                  ElevatedButton.icon(
                    onPressed: () => _launchUrl('https://syncthing.net/downloads/'),
                    icon: const Icon(Icons.download),
                    label: const Text('Download for macOS'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _runCommand('brew install syncthing'),
                    icon: const Icon(Icons.terminal),
                    label: const Text('Install via Homebrew'),
                  ),
                ],
                if (Platform.isWindows) ...[
                  ElevatedButton.icon(
                    onPressed: () => _launchUrl('https://syncthing.net/downloads/'),
                    icon: const Icon(Icons.download),
                    label: const Text('Download for Windows'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _runCommand('winget install Syncthing.Syncthing'),
                    icon: const Icon(Icons.terminal),
                    label: const Text('Install via Winget'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _detectSyncthing,
              child: const Text('Re-check'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfigureStep() {
    final t = LumenColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.folder, size: 64, color: t.primary),
          const SizedBox(height: 16),
          Text('Folder Configuration', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Generated Syncthing folder config:'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Folder ID: ${_folderId ?? "lumen-journal-<random>"}'),
                Text('Path: ${widget.vaultPath}'),
                Text('Type: Send & Receive'),
                Text('Versioning: Staggered (30 days)'),
                Text('Ignore Patterns: *.tmp, *.swp, .lumen/search/, .lumen/*.lock'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('To apply this configuration:'),
          const SizedBox(height: 8),
          const Text('1. Open Syncthing Web UI (http://127.0.0.1:8384)'),
          const Text('2. Click "Add Folder"'),
          const Text('3. Use the settings above'),
          const Text('4. Share the folder with your other devices'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _openSyncthingUI,
            icon: const Icon(Icons.open_in_browser),
            label: const Text('Open Syncthing UI'),
          ),
        ],
      ),
    );
  }

  Widget _buildPairingStep() {
    final t = LumenColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.devices, size: 64, color: t.primary),
          const SizedBox(height: 16),
          Text('Device Pairing', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Share your device ID with other devices to sync:'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                const Text('Device ID:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SelectableText(
                  'SYNCTHING-DEVICE-ID-HERE',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                ),
                const SizedBox(height: 16),
                const Text('On your other device:'),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!kIsWeb) ...[
                      OutlinedButton.icon(
                        onPressed: () => _launchUrl('https://play.google.com/store/apps/details?id=com.nutomic.syncthingandroid'),
                        icon: const Icon(Icons.android),
                        label: const Text('Android: Syncthing'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _launchUrl('https://apps.apple.com/app/mobius-sync/id1510429293'),
                        icon: const Icon(Icons.phone_iphone),
                        label: const Text('iOS: Möbius Sync'),
                      ),
                    ],
                    OutlinedButton.icon(
                      onPressed: () => _launchUrl('https://syncthing.net/downloads/'),
                      icon: const Icon(Icons.computer),
                      label: const Text('Desktop: Syncthing'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Once paired, devices will appear in the Devices tab of Syncthing UI.'),
        ],
      ),
    );
  }

  Widget _buildVerifyStep() {
    final t = LumenColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified, size: 64, color: t.success),
          const SizedBox(height: 16),
          Text('Verify Sync', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Create a test note on one device and verify it appears on the other.'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _verifySync,
            icon: const Icon(Icons.sync),
            label: const Text('Check Sync Status'),
          ),
          const SizedBox(height: 16),
          const Text('If sync is working, you\'ll see "Sync Active" in the status dashboard.'),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    // TODO: Use url_launcher
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Open: $url')));
  }

  Future<void> _runCommand(String cmd) async {
    // TODO: Show command to run
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Run: $cmd')));
  }
}