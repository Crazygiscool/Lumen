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
    localModified:
        DateTime.tryParse(j['local_modified'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    remoteModified:
        DateTime.tryParse(j['remote_modified'] as String? ?? '') ??
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
    this.deviceError,
  });

  final bool enabled;
  final SyncMethod method;
  final DateTime? lastSync;
  final int pendingChanges;
  final List<SyncConflict> conflicts;
  final List<DeviceStatus> deviceStatus;

  /// Why the devices could not be asked about, if they could not.
  ///
  /// Syncthing may simply not be running, which is not a failure: the
  /// journal works either way. The reason is here so the app can say so
  /// instead of showing an empty device list with no explanation.
  final String? deviceError;

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
    deviceError: j['device_error'] as String?,
  );
}

/// What happened to a line in a difference.
enum DiffKind {
  same,
  added,
  removed;

  static DiffKind fromString(String s) {
    switch (s) {
      case 'added':
        return DiffKind.added;
      case 'removed':
        return DiffKind.removed;
      default:
        return DiffKind.same;
    }
  }

  @override
  String toString() {
    switch (this) {
      case DiffKind.same:
        return 'same';
      case DiffKind.added:
        return 'added';
      case DiffKind.removed:
        return 'removed';
    }
  }
}

/// A line of a difference between two versions of a note.
class DiffLine {
  const DiffLine({required this.kind, required this.text});

  final DiffKind kind;
  final String text;

  factory DiffLine.fromJson(Map<String, dynamic> j) => DiffLine(
    kind: DiffKind.fromString(j['kind'] as String? ?? 'same'),
    text: j['text'] as String? ?? '',
  );
}

/// The two versions of a conflicted note.
class ConflictVersions {
  const ConflictVersions({required this.local, required this.remote});

  /// The note as it stands on this device.
  final String local;

  /// The version the other device sent.
  final String remote;

  factory ConflictVersions.fromJson(Map<String, dynamic> j) => ConflictVersions(
    local: j['local'] as String? ?? '',
    remote: j['remote'] as String? ?? '',
  );
}

/// Whether the WebDAV secrets are kept, and whether the machine can keep
/// them at all.
class CredentialStatus {
  const CredentialStatus({
    required this.available,
    required this.hasPassword,
    required this.hasPassphrase,
  });

  /// Whether the machine has a keyring Lumen can use.
  final bool available;

  /// Whether the password of the account is kept.
  final bool hasPassword;

  /// Whether the passphrase that encrypts the uploads is kept.
  final bool hasPassphrase;

  factory CredentialStatus.fromJson(Map<String, dynamic> j) => CredentialStatus(
    available: j['available'] as bool? ?? false,
    hasPassword: j['password'] as bool? ?? false,
    hasPassphrase: j['passphrase'] as bool? ?? false,
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
    _ffi.kb(
      'kb.sync.resolve_conflict',
      _args({'path': path, 'keep_local': keepLocal}),
    );
  }

  /// Generate Syncthing folder configuration XML.
  Future<String> generateSyncthingConfig(String vaultPath) async {
    final data =
        _ffi.kb(
              'kb.sync.generate_syncthing_config',
              _args({'vault_path': vaultPath}),
            )
            as Map<String, dynamic>;
    return data['config'] as String? ?? '';
  }

  /// Create encrypted backup bundle.
  Future<void> createBackup({
    required String vaultPath,
    required String passphrase,
    required String outputPath,
  }) async {
    _ffi.kb(
      'kb.sync.backup.create',
      _args({
        'vault_path': vaultPath,
        'passphrase': passphrase,
        'output_path': outputPath,
      }),
    );
  }

  /// Restore encrypted backup bundle.
  Future<void> restoreBackup({
    required String bundlePath,
    required String passphrase,
    required String targetDir,
  }) async {
    _ffi.kb(
      'kb.sync.backup.restore',
      _args({
        'bundle_path': bundlePath,
        'passphrase': passphrase,
        'target_dir': targetDir,
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Conflicts
  // ---------------------------------------------------------------------------

  /// The two versions of a conflicted note.
  ///
  /// Both versions are decrypted by the core, because the version the other
  /// device sent is an encrypted file inside the vault.
  Future<ConflictVersions> conflictVersions({
    required String vaultPath,
    required String path,
  }) async {
    final data =
        _ffi.kb(
              'kb.sync.conflict_versions',
              _args({'vault_path': vaultPath, 'path': path}),
            )
            as Map<String, dynamic>;
    return ConflictVersions.fromJson(data);
  }

  /// The difference between the two versions of a conflicted note.
  Future<List<DiffLine>> conflictDiff({
    required String vaultPath,
    required String path,
  }) async {
    final data =
        _ffi.kb(
              'kb.sync.conflict_diff',
              _args({'vault_path': vaultPath, 'path': path}),
            )
            as Map<String, dynamic>;
    return _diffLines(data);
  }

  /// The difference between two texts.
  Future<List<DiffLine>> diffLines({
    required String oldText,
    required String newText,
  }) async {
    final data =
        _ffi.kb('kb.diff.lines', _args({'old': oldText, 'new': newText}))
            as Map<String, dynamic>;
    return _diffLines(data);
  }

  /// The lines of a difference, as the core sent them.
  List<DiffLine> _diffLines(Map<String, dynamic> data) =>
      (data['lines'] as List<dynamic>? ?? const [])
          .map((e) => DiffLine.fromJson((e as Map<String, dynamic>).cast()))
          .toList();

  // ---------------------------------------------------------------------------
  // Credentials
  // ---------------------------------------------------------------------------

  /// Keep the WebDAV secrets in the operating system's keyring.
  ///
  /// The password of the account and the passphrase that encrypts the
  /// uploads are two different secrets, and neither of them is written to
  /// the configuration file.
  Future<void> setCredentials({String? password, String? passphrase}) async {
    _ffi.kb(
      'kb.sync.credentials.set',
      _args({'password': ?password, 'passphrase': ?passphrase}),
    );
  }

  /// Whether the WebDAV secrets are kept.
  Future<CredentialStatus> credentialsStatus() async {
    final data =
        _ffi.kb('kb.sync.credentials.status', _args()) as Map<String, dynamic>;
    return CredentialStatus.fromJson(data);
  }

  /// Forget the WebDAV secrets.
  Future<void> clearCredentials() async {
    _ffi.kb('kb.sync.credentials.clear', _args());
  }

  /// Test a WebDAV account.
  ///
  /// The password is read from the keyring by the core, so it does not
  /// travel through the app.
  Future<void> connectWebDAV({
    required String url,
    required String username,
    required bool encrypt,
  }) async {
    _ffi.kb(
      'kb.sync.webdav.connect',
      _args({'url': url, 'username': username, 'encrypt': encrypt}),
    );
  }

  /// Upload the vault to a WebDAV account.
  Future<void> syncWebDAV({
    required String vaultPath,
    required String url,
    required String username,
    required bool encrypt,
  }) async {
    _ffi.kb(
      'kb.sync.webdav.sync',
      _args({
        'vault_path': vaultPath,
        'url': url,
        'username': username,
        'encrypt': encrypt,
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  /// The configuration of Lumen.
  Future<Map<String, dynamic>> config() async {
    final data = _ffi.kb('kb.config.get', _args());
    // The map is copied into one that holds anything, so a part of it can
    // be changed and written back without running into the types of the
    // parts that were not.
    return Map<String, dynamic>.from(data as Map);
  }

  /// Write the configuration of Lumen.
  Future<void> setConfig(Map<String, dynamic> config) async {
    _ffi.kb('kb.config.set', _args({'config': config}));
  }

  /// Choose the method Lumen syncs with.
  ///
  /// The choice is written to the configuration, so it is still there the
  /// next time Lumen starts.
  Future<void> setSyncMethod(SyncMethod method) async {
    final config = await this.config();
    final sync = Map<String, dynamic>.from(config['sync'] as Map? ?? const {});
    sync['method'] = method.toString();
    config['sync'] = sync;
    await setConfig(config);
  }

  /// Write the settings of the WebDAV account.
  ///
  /// Only the address and the name of the account are written here; the
  /// password and the passphrase that encrypts the uploads stay in the
  /// keyring.
  Future<void> setWebDAVSettings({
    required String url,
    required String username,
    required bool encrypt,
  }) async {
    final config = await this.config();
    final sync = Map<String, dynamic>.from(config['sync'] as Map? ?? const {});
    final webdav = Map<String, dynamic>.from(
      sync['webdav'] as Map? ?? const {},
    );
    webdav['url'] = url;
    webdav['username'] = username;
    webdav['encrypt'] = encrypt;
    sync['webdav'] = webdav;
    config['sync'] = sync;
    await setConfig(config);
  }
}
