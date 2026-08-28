import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../ffi/lumen_ffi.dart';

@immutable
class FsEntry {
  const FsEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.isSymlink,
    required this.size,
    required this.modifiedMs,
    required this.permissions,
    required this.owner,
    this.symlinkTarget,
    this.extension,
    required this.isHidden,
    this.modifiedReadable,
  });

  final String name;
  final String path;
  final bool isDir;
  final bool isSymlink;
  final int size;
  final int modifiedMs;
  final String permissions;
  final String owner;
  final String? symlinkTarget;
  final String? extension;
  final bool isHidden;
  final String? modifiedReadable;

  factory FsEntry.fromJson(Map<String, dynamic> j) => FsEntry(
    name: j['name'] as String? ?? '',
    path: j['path'] as String? ?? '',
    isDir: j['is_dir'] as bool? ?? false,
    isSymlink: j['is_symlink'] as bool? ?? false,
    size: (j['size'] as num?)?.toInt() ?? 0,
    modifiedMs: (j['modified_ms'] as num?)?.toInt() ?? 0,
    permissions: j['permissions'] as String? ?? '',
    owner: j['owner'] as String? ?? '',
    symlinkTarget: j['symlink_target'] as String?,
    extension: j['extension'] as String?,
    isHidden: j['is_hidden'] as bool? ?? false,
    modifiedReadable: j['modified_readable'] as String?,
  );

  bool get isFile => !isDir;
}

class DuNode {
  const DuNode({
    required this.name,
    required this.path,
    required this.size,
    required this.children,
  });

  final String name;
  final String path;
  final int size;
  final List<DuNode> children;

  factory DuNode.fromJson(Map<String, dynamic> j) => DuNode(
    name: j['name'] as String? ?? '',
    path: j['path'] as String? ?? '',
    size: (j['size'] as num?)?.toInt() ?? 0,
    children: (j['children'] as List<dynamic>? ?? [])
        .map((c) => DuNode.fromJson(c as Map<String, dynamic>))
        .toList(),
  );
}

class FsService {
  FsService(this._ffi);

  final LumenFfi _ffi;

  Future<List<FsEntry>> list(String path, {bool showHidden = false}) async {
    final data = _ffi.fscore('fs.list', {
      'path': path,
      'show_hidden': showHidden,
    });
    return (data as List<dynamic>)
        .map((e) => FsEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<FsEntry> stat(String path) async {
    final data = _ffi.fscore('fs.stat', {'path': path}) as Map<String, dynamic>;
    return FsEntry.fromJson(data);
  }

  Future<Uint8List> readBytes(
    String path, {
    int maxBytes = 5 * 1024 * 1024,
  }) async {
    final data = _ffi.fscore('fs.read', {'path': path, 'max_bytes': maxBytes});
    final b64 = (data as Map<String, dynamic>)['data'] as String;
    return base64Decode(b64);
  }

  Future<String> readText(String path) async {
    return utf8.decode(await readBytes(path));
  }

  Future<void> writeBytes(String path, Uint8List bytes) async {
    _ffi.fscore('fs.write', {'path': path, 'data': base64Encode(bytes)});
  }

  Future<void> writeText(String path, String text) async {
    await writeBytes(path, Uint8List.fromList(utf8.encode(text)));
  }

  Future<void> mkdir(String path) => _ffi.fscore('fs.mkdir', {'path': path});

  Future<void> rename(String from, String to) =>
      _ffi.fscore('fs.rename', {'from': from, 'to': to});

  Future<void> copy(String from, String to) =>
      _ffi.fscore('fs.copy', {'from': from, 'to': to});

  Future<void> delete(String path) => _ffi.fscore('fs.delete', {'path': path});

  Future<void> trash(String path) => _ffi.fscore('fs.trash', {'path': path});

  Future<List<FsEntry>> search(
    String root,
    String query, {
    bool showHidden = false,
    int maxResults = 300,
  }) async {
    final data = _ffi.fscore('fs.search', {
      'root': root,
      'query': query,
      'show_hidden': showHidden,
      'max_results': maxResults,
    });
    return (data as List<dynamic>)
        .map((e) => FsEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DuNode> du(String path, {int maxDepth = 3}) async {
    final data = _ffi.fscore('fs.du', {'path': path, 'max_depth': maxDepth});
    return DuNode.fromJson(data as Map<String, dynamic>);
  }
}

class SystemService {
  SystemService(this._ffi);

  final LumenFfi _ffi;

  Future<Map<String, dynamic>> hardware() async =>
      _ffi.fscore('sys.hardware', {}) as Map<String, dynamic>;

  Future<List<dynamic>> processes() async =>
      _ffi.fscore('sys.processes', {}) as List<dynamic>;

  Future<List<dynamic>> mounts() async =>
      _ffi.fscore('sys.mounts', {}) as List<dynamic>;

  Future<List<dynamic>> disks() async =>
      _ffi.fscore('sys.disks', {}) as List<dynamic>;

  /// Reads the host desktop's GTK theme (color-scheme + accent colour).
  Future<Map<String, dynamic>> gtk() async =>
      _ffi.fscore('sys.gtk', {}) as Map<String, dynamic>;
}
