import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

class FfiException implements Exception {
  FfiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Locates and loads Lumen's native core library.
///
/// Tries, in order:
///  1. The Flutter bundle's `lib/` dir (packaged app).
///  2. The in-repo CMake lib dir (`ui/<platform>/lib` — dev `flutter run`).
///  3. The Cargo `target/release` output.
///
/// Initialization is non-fatal: if the library cannot be located the error is
/// surfaced lazily as a [FfiException] on the first call, so the UI renders a
/// graceful degraded state instead of crashing the widget tree.
class LumenFfi {
  LumenFfi._();

  static final LumenFfi instance = LumenFfi._();

  DynamicLibrary? _core;
  String? _initError;
  bool _initialized = false;

  bool get ready => _core != null;

  String? get initError => _initError;

  static String _platformDir() {
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    throw UnsupportedError('Unsupported platform');
  }

  static String _libName(String base) {
    if (Platform.isWindows) return '$base.dll';
    if (Platform.isMacOS) return 'lib$base.dylib';
    return 'lib$base.so';
  }

  static String _resolve(String base) {
    final name = _libName(base);
    final exeDir = File(Platform.resolvedExecutable).parent;
    final cwd = Directory.current.path;

    final candidates = <String>[
      p.join(exeDir.path, 'lib', name),
      p.join(cwd, 'ui', _platformDir(), 'lib', name),
      p.join(cwd, _platformDir(), 'lib', name),
      if (Platform.isMacOS) p.join(cwd, 'ui', 'macos', 'Runner', name),
      if (Platform.isMacOS) p.join(cwd, 'macos', 'Runner', name),
      p.join(cwd, 'target', 'release', name),
      p.join(cwd, '..', 'target', 'release', name),
    ].where((path) => File(path).existsSync()).toList();

    if (candidates.isEmpty) {
      throw FfiException(
        'lumen_core library not found. Build first:\n'
        '  cargo build --release --locked\n'
        '  make dev   (or: make)\n'
        'Looked for: $name in ${exeDir.path}/lib, $cwd/ui/${_platformDir()}/lib, $cwd/target/release',
      );
    }
    return candidates.first;
  }

  void init() {
    if (_initialized) return;
    _initialized = true;
    try {
      _core = DynamicLibrary.open(_resolve('lumen_core'));
    } catch (e) {
      _initError = e.toString();
    }
  }

  /// Invokes a method on `liblumen_core` (`lumen_vault_call`).
  Object? core(String method, [Map<String, Object?> args = const {}]) {
    final lib = _core;
    if (lib == null) throw FfiException(_initError ?? 'lumen_core not loaded');
    final call = lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)
    >('lumen_vault_call');
    final free = lib.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)
    >('lumen_vault_free');
    return _invoke(call, free, method, args);
  }

  /// Invokes the plugin inventory entry (`lumen_plugins_call`).
  Object? plugins(String method, [Map<String, Object?> args = const {}]) {
    final lib = _core;
    if (lib == null) throw FfiException(_initError ?? 'lumen_core not loaded');
    final call = lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)
    >('lumen_plugins_call');
    final free = lib.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)
    >('lumen_plugins_free');
    return _invoke(call, free, method, args);
  }

  Object? _invoke(
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>) call,
    void Function(Pointer<Utf8>) free,
    String method,
    Map<String, Object?> args,
  ) {
    final m = method.toNativeUtf8();
    final a = jsonEncode(args).toNativeUtf8();
    try {
      final result = call(m, a);
      if (result == nullptr) {
        throw FfiException('$method returned null');
      }
      final text = result.toDartString();
      free(result);
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      if (decoded['ok'] != true) {
        throw FfiException(decoded['error'] as String? ?? '$method failed');
      }
      return decoded['data'];
    } finally {
      malloc.free(a);
      malloc.free(m);
    }
  }
}
