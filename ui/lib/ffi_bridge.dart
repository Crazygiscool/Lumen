import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef LumenAddEntryNative = Void Function(
  Pointer<Char>, Pointer<Char>, Pointer<Char>, Pointer<Char>);
typedef LumenAddEntry = void Function(
  Pointer<Char>, Pointer<Char>, Pointer<Char>, Pointer<Char>);

typedef LumenListEntriesNative = Pointer<Char> Function();
typedef LumenListEntries = Pointer<Char> Function();

class LumenCore {
  late DynamicLibrary _lib;

  LumenCore() {
    // Flutter desktop resolves the executable inside data/flutter_assets
    final exePath = Platform.resolvedExecutable;

    // exePath = <bundle>/data/flutter_assets/kernel_blob.bin
    final assetsDir = p.dirname(exePath);     // flutter_assets
    final dataDir = p.dirname(assetsDir);     // data
    final bundleDir = p.dirname(dataDir);     // <bundle>

    // Native libraries live in <bundle>/lib/
    final libDir = p.join(bundleDir, 'lib');

    final libPath = Platform.isLinux
        ? p.join(libDir, 'liblumen_core.so')
        : Platform.isMacOS
            ? p.join(libDir, 'liblumen_core.dylib')
            : Platform.isWindows
                ? p.join(libDir, 'lumen_core.dll')
                : throw UnsupportedError('Unsupported platform');

    _lib = DynamicLibrary.open(libPath);
  }

  void addEntry(String id, String text, String author, String password) {
    final addEntry = _lib.lookupFunction<
        LumenAddEntryNative, LumenAddEntry>('lumen_add_entry');

    addEntry(
      id.toNativeUtf8().cast(),
      text.toNativeUtf8().cast(),
      author.toNativeUtf8().cast(),
      password.toNativeUtf8().cast(),
    );
  }

  List<String> listEntries() {
    final listEntries = _lib.lookupFunction<
        LumenListEntriesNative, LumenListEntries>('lumen_list_entries');

    final ptr = listEntries();
    final result = ptr.cast<Utf8>().toDartString();
    return result.split(',');
  }
}
