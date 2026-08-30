import 'package:flutter/foundation.dart';

import '../ffi/lumen_ffi.dart';

/// Result of inspecting a path for tank encryption.
@immutable
class TankInfo {
  const TankInfo({
    required this.encrypted,
    this.name,
    this.size,
    this.chunks,
  });

  final bool encrypted;

  /// Original file basename (only when [encrypted]).
  final String? name;
  final int? size;
  final int? chunks;

  factory TankInfo.fromJson(Map<String, dynamic> j) => TankInfo(
    encrypted: j['encrypted'] as bool? ?? false,
    name: j['name'] as String?,
    size: (j['size'] as num?)?.toInt(),
    chunks: (j['chunks'] as num?)?.toInt(),
  );
}

/// Live tank state: root, whether a tank is set up there, and unlock status.
@immutable
class TankStatus {
  const TankStatus({required this.setup, required this.unlocked, this.root});
  final bool setup;
  final bool unlocked;
  final String? root;

  factory TankStatus.fromJson(Map<String, dynamic> j) => TankStatus(
    setup: j['setup'] as bool? ?? false,
    unlocked: j['unlocked'] as bool? ?? false,
    root: j['root'] as String?,
  );
}

/// Talks to the "tank" in `liblumen_core`: the third encrypted store holding
/// uniform ciphertext blobs for encrypt-any-file. Markers (`<name>.lumen-tank`)
/// stay in the file's original location.
class TankService {
  TankService(this._ffi);

  final LumenFfi _ffi;

  Future<TankStatus> status() async =>
      TankStatus.fromJson((_ffi.tank('tank.status') as Map<String, dynamic>));

  Future<void> setup(String path, String passphrase) =>
      _ffi.tank('tank.setup', {'path': path, 'passphrase': passphrase});

  Future<void> unlock(String path, String passphrase) =>
      _ffi.tank('tank.unlock', {'path': path, 'passphrase': passphrase});

  Future<void> setPath(String path) => _ffi.tank('tank.set_path', {'path': path});

  Future<void> lock() => _ffi.tank('tank.lock');

  Future<TankInfo> info(String path) async =>
      TankInfo.fromJson((_ffi.tank('file.info', {'path': path}) as Map<String, dynamic>));

  Future<Map<String, dynamic>> encrypt(String path) async =>
      _ffi.tank('file.encrypt', {'path': path}) as Map<String, dynamic>;

  Future<Map<String, dynamic>> decrypt(String path) async =>
      _ffi.tank('file.decrypt', {'path': path}) as Map<String, dynamic>;

  Future<Map<String, dynamic>> delete(String path) async =>
      _ffi.tank('file.delete', {'path': path}) as Map<String, dynamic>;
}