import '../ffi/lumen_ffi.dart';

/// Sync method type.
enum SyncMethod {
  syncthing,
  webdav,
  none;

  static SyncMethod fromString(String s) {
    switch (s) {
      case 'syncthing':
        return SyncMethod.syncthing;
      case 'webdav':
        return SyncMethod.webdav;
      default:
        return SyncMethod.none;
    }
  }

  @override
  String toString() {
    switch (this) {
      case SyncMethod.syncthing:
        return 'syncthing';
      case SyncMethod.webdav:
        return 'webdav';
      case SyncMethod.none:
        return 'none';
    }
  }
}

/// Sync conflict between local and remote versions.
class SyncConflict {
  const SyncConflict({
    required this.path,
    required this.localModified,
    required this.remoteModified,
    required this.localHash,
    required this.remoteHash,
  });

  final String path;
  final DateTime localModified;
  final DateTime remoteModified;
  final String localHash;
  final String remoteHash;

  factory SyncConflict.fromJson(Map<String, dynamic> j) => SyncConflict(
        path: j['path'] as String? ?? '',
        localModified: DateTime.tryParse(j['local_modified'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        remoteModified: DateTime.tryParse(j['remote_modified'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        localHash: j['local_hash'] as String? ?? '',
        remoteHash: j['remote_hash'] as String? ?? '',
      );
}

/// Connected device status.
class DeviceStatus {
  const DeviceStatus({
    required this.id,
    required this.name,
    required this.connected,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final bool connected;
  final DateTime? lastSeen;

  factory DeviceStatus.fromJson(Map<String, dynamic> j) => DeviceStatus(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        connected: j['connected'] as bool? ?? false,
        lastSeen: j['last_seen'] != null
            ? DateTime.tryParse(j['last_seen'] as String)
            : null,
      );
}

/// Sync status for UI display.
class SyncStatus {
  const SyncStatus({
    required this.enabled,
    required this.method,
    required this.lastSync,
    required this.pendingChanges,
    required this.conflicts,
    required this.deviceStatus,
  });

  final bool enabled;
  final SyncMethod method;
  final DateTime? lastSync;
  final int pendingChanges;
  final List<SyncConflict> conflicts;
  final List<DeviceStatus> deviceStatus;

  factory SyncStatus.fromJson(Map<String, dynamic> j) => SyncStatus(
        enabled: j['enabled'] as bool? ?? false,
        method: SyncMethod.fromString(j['method']?.toString() ?? 'none'),
        lastSync: j['last_sync'] != null
            ? DateTime.tryParse(j['last_sync'] as String)
            : null,
        pendingChanges: (j['pending_changes'] as num?)?.toInt() ?? 0,
        conflicts: (j['conflicts'] as List<dynamic>? ?? const [])
            .map((e) => SyncConflict.fromJson((e as Map<String, dynamic>).cast()))
            .toList(),
        deviceStatus: (j['device_status'] as List<dynamic>? ?? const [])
            .map((e) => DeviceStatus.fromJson((e as Map<String, dynamic>).cast()))
            .toList(),
      );
}

/// Service for sync operations (Syncthing, WebDAV, backups).
class SyncService {
  SyncService(this._ffi);

  final LumenFfi _ffi;

  Map<String, Object?> _args([Map<String, Object?> base = const {}]) => base;

  /// Initialize sync for a vault.
  Future<void> init(String vaultPath) async {
    _ffi.kb('kb.sync.init', _args({'vault_path': vaultPath}));
  }

  /// Get current sync status.
  Future<SyncStatus> status() async {
    final data = _ffi.kb('kb.sync.status', _args()) as Map<String, dynamic>;
    return SyncStatus.fromJson(data);
  }

  /// List detected conflicts.
  Future<List<SyncConflict>> conflicts() async {
    final data = _ffi.kb('kb.sync.conflicts', _args()) as Map<String, dynamic>;
    final list = data['conflicts'] as List<dynamic>? ?? const [];
    return list
        .map((e) => SyncConflict.fromJson((e as Map<String, dynamic>).cast()))
        .toList();
  }

  /// Resolve a conflict by choosing local or remote version.
  Future<void> resolveConflict(String path, {required bool keepLocal}) async {
    _ffi.kb('kb.sync.resolve_conflict', _args({'path': path, 'keep_local': keepLocal}));
  }

  /// Generate Syncthing folder configuration XML.
  Future<String> generateSyncthingConfig(String vaultPath) async {
    final data = _ffi.kb('kb.sync.generate_syncthing_config', _args({'vault_path': vaultPath}))
        as Map<String, dynamic>;
    return data['config'] as String? ?? '';
  }

  /// Create encrypted backup bundle.
  Future<void> createBackup({
    required String vaultPath,
    required String passphrase,
    required String outputPath,
  }) async {
    _ffi.kb('kb.sync.backup.create', _args({
      'vault_path': vaultPath,
      'passphrase': passphrase,
      'output_path': outputPath,
    }));
  }

  /// Restore encrypted backup bundle.
  Future<void> restoreBackup({
    required String bundlePath,
    required String passphrase,
    required String targetDir,
  }) async {
    _ffi.kb('kb.sync.backup.restore', _args({
      'bundle_path': bundlePath,
      'passphrase': passphrase,
      'target_dir': targetDir,
    }));
  }
}