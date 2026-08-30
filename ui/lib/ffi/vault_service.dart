import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../ffi/lumen_ffi.dart';

@immutable
class VaultEntry {
  const VaultEntry({
    required this.name,
    required this.relPath,
    required this.isDir,
    required this.size,
    required this.modifiedMs,
  });

  final String name;
  final String relPath;
  final bool isDir;
  final int size;
  final int modifiedMs;

  factory VaultEntry.fromJson(Map<String, dynamic> j) => VaultEntry(
    name: j['name'] as String? ?? '',
    relPath: j['rel_path'] as String? ?? '',
    isDir: j['is_dir'] as bool? ?? false,
    size: (j['size'] as num?)?.toInt() ?? 0,
    modifiedMs: (j['modified_ms'] as num?)?.toInt() ?? 0,
  );
}

/// A store currently unlocked on disk (`root` + which passphrase container).
@immutable
class VaultStoreRecord {
  const VaultStoreRecord({
    required this.root,
    required this.store,
  });

  /// `vault` (the knowledge base) or `journal`.
  final String store;
  final String root;

  factory VaultStoreRecord.fromJson(Map<String, dynamic> j) => VaultStoreRecord(
    root: j['root'] as String? ?? '',
    store: j['store'] as String? ?? 'vault',
  );
}

/// Targets one encrypted store (`vault` / `journal`) in `liblumen_core`.
///
/// Methods that operate on files are resolved against the store's
/// currently-unlocked root; passphrases are never retained in Dart.
class VaultService {
  VaultService(this._ffi, {this.store = 'vault'});

  final LumenFfi _ffi;

  /// Which encrypted store this service talks to.
  final String store;

  Map<String, Object?> args([Map<String, Object?> base = const {}]) =>
      {...base, 'store': store};

  Future<void> create(String path, String passphrase) =>
      _ffi.core('vault.create', args({'path': path, 'passphrase': passphrase}));

  Future<void> unlock(String path, String passphrase) =>
      _ffi.core('vault.unlock', args({'path': path, 'passphrase': passphrase}));

  /// Lock this service's store.
  Future<void> lock() => _ffi.core('vault.lock', args());

  /// Lock every open store.
  Future<void> lockAll() => _ffi.core('vault.lock_all');

  Future<bool> isUnlocked() async {
    final data = _ffi.core('vault.is_unlocked', args()) as Map<String, dynamic>;
    return data['unlocked'] as bool? ?? false;
  }

  Future<Map<String, dynamic>> info() async =>
      _ffi.core('vault.info', args()) as Map<String, dynamic>;

  Future<List<VaultStoreRecord>> openStores() async {
    final data = _ffi.core('vault.open_stores') as Map<String, dynamic>;
    final records = data['stores'] as List<dynamic>? ?? const [];
    return [
      for (final r in records)
        VaultStoreRecord.fromJson((r as Map<String, dynamic>).cast()),
    ];
  }

  Future<List<VaultEntry>> list([String path = '']) async {
    final data = _ffi.core('vault.list', args({'path': path})) as List<dynamic>;
    return data
        .map((e) => VaultEntry.fromJson((e as Map<String, dynamic>).cast()))
        .toList();
  }

  Future<String> readText(String path) async {
    final data = _ffi.core('vault.read_text', args({'path': path}));
    return (data as Map<String, dynamic>)['text'] as String;
  }

  Future<Uint8List> readBytes(String path) async {
    final data = _ffi.core('vault.read', args({'path': path}));
    final b64 = (data as Map<String, dynamic>)['data'] as String;
    return base64Decode(b64);
  }

  Future<void> writeText(String path, String text) =>
      _ffi.core('vault.write_text', args({'path': path, 'text': text}));

  Future<void> writeBytes(String path, Uint8List bytes) =>
      _ffi.core('vault.write', args({'path': path, 'data': base64Encode(bytes)}));

  Future<void> mkdir(String path) => _ffi.core('vault.mkdir', args({'path': path}));

  Future<void> delete(String path) => _ffi.core('vault.delete', args({'path': path}));

  Future<void> rename(String from, String to) =>
      _ffi.core('vault.rename', args({'from': from, 'to': to}));

  Future<List<Map<String, dynamic>>> search(
    String query, {
    int maxResults = 200,
  }) async {
    final data = _ffi.core('vault.search', args({
      'query': query,
      'max_results': maxResults,
    }));
    return (data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<int> export(String dest) async {
    final data = _ffi.core('vault.export', args({'path': dest}));
    return (data as Map<String, dynamic>)['exported'] as int? ?? 0;
  }
}