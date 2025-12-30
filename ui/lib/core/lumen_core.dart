import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

import 'ffi/lumen_loader.dart';
import 'models/journal_entry.dart';

typedef LumenAddEntryNative = Void Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef LumenAddEntry = void Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef LumenListEntriesNative = Pointer<Utf8> Function();
typedef LumenListEntries = Pointer<Utf8> Function();

typedef LumenDecryptEntryNative = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef LumenDecryptEntry = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
);

class LumenCore {
  late final DynamicLibrary _lib;
  late final LumenAddEntry _addEntry;
  late final LumenListEntries _listEntries;
  late final LumenDecryptEntry _decryptEntry;

  LumenCore() {
    _lib = loadLumenLibrary();

    _addEntry = _lib
        .lookupFunction<LumenAddEntryNative, LumenAddEntry>('lumen_add_entry');
    _listEntries = _lib.lookupFunction<LumenListEntriesNative,
        LumenListEntries>('lumen_list_entries');
    _decryptEntry = _lib.lookupFunction<LumenDecryptEntryNative,
        LumenDecryptEntry>('lumen_decrypt_entry');
  }

  void addEntry(String id, String text, String author, String password) {
    final idPtr = id.toNativeUtf8();
    final textPtr = text.toNativeUtf8();
    final authorPtr = author.toNativeUtf8();
    final passwordPtr = password.toNativeUtf8();

    _addEntry(idPtr, textPtr, authorPtr, passwordPtr);

    malloc.free(idPtr);
    malloc.free(textPtr);
    malloc.free(authorPtr);
    malloc.free(passwordPtr);
  }

  List<JournalEntry> listEntries() {
    final ptr = _listEntries();
    final jsonStr = ptr.toDartString();

    final decoded = jsonDecode(jsonStr) as List<dynamic>;
    return decoded
        .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  String decryptEntry(String id, String password) {
    final idPtr = id.toNativeUtf8();
    final pwPtr = password.toNativeUtf8();

    final resultPtr = _decryptEntry(idPtr, pwPtr);
    final result = resultPtr.toDartString();

    malloc.free(idPtr);
    malloc.free(pwPtr);

    return result;
  }
}
