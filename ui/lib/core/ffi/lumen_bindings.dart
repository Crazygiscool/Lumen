import 'dart:ffi';
import 'package:ffi/ffi.dart';

typedef LumenAddEntryNative = Void Function(
  Pointer<Char>, Pointer<Char>, Pointer<Char>, Pointer<Char>);
typedef LumenAddEntry = void Function(
  Pointer<Char>, Pointer<Char>, Pointer<Char>, Pointer<Char>);

typedef LumenListEntriesNative = Pointer<Char> Function();
typedef LumenListEntries = Pointer<Char> Function();

class LumenBindings {
  late final LumenAddEntry _addEntry;
  late final LumenListEntries _listEntries;

  LumenBindings(DynamicLibrary lib) {
    _addEntry = lib
        .lookupFunction<LumenAddEntryNative, LumenAddEntry>('lumen_add_entry');

    _listEntries = lib.lookupFunction<LumenListEntriesNative,
        LumenListEntries>('lumen_list_entries');
  }

  void addEntry(String id, String text, String author, String password) {
    _addEntry(
      id.toNativeUtf8().cast(),
      text.toNativeUtf8().cast(),
      author.toNativeUtf8().cast(),
      password.toNativeUtf8().cast(),
    );
  }

  List<String> listEntries() {
    final ptr = _listEntries();
    final csv = ptr.cast<Utf8>().toDartString();
    return csv.split(',');
  }
}
