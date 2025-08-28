import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef LumenAddEntryNative = Void Function(
  Pointer<Char>, Pointer<Char>, Pointer<Char>, Pointer<Char>);
typedef LumenAddEntry = void Function(
  Pointer<Char>, Pointer<Char>, Pointer<Char>, Pointer<Char>);

typedef LumenListEntriesNative = Pointer<Char> Function();
typedef LumenListEntries = Pointer<Char> Function();

class LumenCore {
  late DynamicLibrary _lib;

  LumenCore() {
    _lib = DynamicLibrary.open(
      Platform.isLinux ? 'liblumen_core.so' :
      Platform.isMacOS ? 'liblumen_core.dylib' :
      'lumen_core.dll'
    );
  }

  void addEntry(String id, String text, String author, String password) {
    final addEntry = _lib
      .lookupFunction<LumenAddEntryNative, LumenAddEntry>('lumen_add_entry');
    addEntry(id.toNativeUtf8().cast(), text.toNativeUtf8().cast(), author.toNativeUtf8().cast(), password.toNativeUtf8().cast());
  }

  List<String> listEntries() {
    final listEntries = _lib
      .lookupFunction<LumenListEntriesNative, LumenListEntries>('lumen_list_entries');
    final ptr = listEntries();
    final result = ptr.cast<Utf8>().toDartString();
    return result.split(',');
  }
}
