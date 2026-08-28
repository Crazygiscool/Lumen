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

class VaultService {
  VaultService(this._ffi);

  final LumenFfi _ffi;

  Future<void> create(String path, String passphrase) =>
      _ffi.core('vault.create', {'path': path, 'passphrase': passphrase});

  Future<void> unlock(String path, String passphrase) =>
      _ffi.core('vault.unlock', {'path': path, 'passphrase': passphrase});

  Future<void> lock() => _ffi.core('vault.lock');

  Future<bool> isUnlocked() async {
    final data = _ffi.core('vault.is_unlocked') as Map<String, dynamic>;
    return data['unlocked'] as bool? ?? false;
  }

  Future<Map<String, dynamic>> info() async {
    final data = _ffi.core('vault.info') as Map<String, dynamic>;
    return data;
  }

  Future<List<VaultEntry>> list([String path = '']) async {
    final data = _ffi.core('vault.list', {'path': path}) as List<dynamic>;
    return data
        .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> readText(String path) async {
    final data = _ffi.core('vault.read_text', {'path': path});
    return (data as Map<String, dynamic>)['text'] as String;
  }

  Future<Uint8List> readBytes(String path) async {
    final data = _ffi.core('vault.read', {'path': path});
    final b64 = (data as Map<String, dynamic>)['data'] as String;
    return base64Decode(b64);
  }

  Future<void> writeText(String path, String text) =>
      _ffi.core('vault.write_text', {'path': path, 'text': text});

  Future<void> writeBytes(String path, Uint8List bytes) =>
      _ffi.core('vault.write', {'path': path, 'data': base64Encode(bytes)});

  Future<void> mkdir(String path) => _ffi.core('vault.mkdir', {'path': path});

  Future<void> delete(String path) => _ffi.core('vault.delete', {'path': path});

  Future<void> rename(String from, String to) =>
      _ffi.core('vault.rename', {'from': from, 'to': to});

  Future<List<Map<String, dynamic>>> search(
    String query, {
    int maxResults = 200,
  }) async {
    final data = _ffi.core('vault.search', {
      'query': query,
      'max_results': maxResults,
    });
    return (data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<int> export(String dest) async {
    final data = _ffi.core('vault.export', {'path': dest});
    return (data as Map<String, dynamic>)['exported'] as int? ?? 0;
  }
}
