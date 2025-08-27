import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef LumenAddEntryNative = ffi.Void Function(
  ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef LumenListEntriesNative = ffi.Pointer<ffi.Char> Function();

class LumenCore {
  late ffi.DynamicLibrary _lib;

  LumenCore() {
    _lib = ffi.DynamicLibrary.open(
      Platform.isLinux ? 'liblumen_core.so' :
      Platform.isMacOS ? 'liblumen_core.dylib' :
      'lumen_core.dll'
    );
  }

  void addEntry(String id, String text, String author, String password) {
    final addEntry = _lib
      .lookupFunction<LumenAddEntryNative, LumenAddEntryNative>('lumen_add_entry');
    addEntry(id.toNativeUtf8().cast(), text.toNativeUtf8().cast(), author.toNativeUtf8().cast(), password.toNativeUtf8().cast());
  }

  List<String> listEntries() {
    final listEntries = _lib
      .lookupFunction<LumenListEntriesNative, LumenListEntriesNative>('lumen_list_entries');
    final ptr = listEntries();
    final result = ptr.cast<Utf8>().toDartString();
    return result.split(',');
  }
}
