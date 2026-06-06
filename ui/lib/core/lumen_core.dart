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
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef LumenAddEntry = void Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
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

typedef LumenFreeStringNative = Void Function(Pointer<Utf8>);
typedef LumenFreeString = void Function(Pointer<Utf8>);

class LumenCore {
  late final DynamicLibrary _lib;
  late final LumenAddEntry _addEntry;
  late final LumenListEntries _listEntries;
  late final LumenDecryptEntry _decryptEntry;
  late final LumenFreeString _freeString;

  LumenCore() {
    _lib = loadLumenLibrary();

    _addEntry = _lib
        .lookupFunction<LumenAddEntryNative, LumenAddEntry>('lumen_add_entry');
    _listEntries = _lib.lookupFunction<LumenListEntriesNative,
        LumenListEntries>('lumen_list_entries');
    _decryptEntry = _lib.lookupFunction<LumenDecryptEntryNative,
        LumenDecryptEntry>('lumen_decrypt_entry');
    _freeString = _lib.lookupFunction<LumenFreeStringNative, LumenFreeString>(
        'lumen_free_string');
  }

  void addEntry(String text, String author, String password,
      {String id = '', String kind = 'journal', List<String> tags = const []}) {
    final tagsJson = jsonEncode(tags);

    final idPtr = id.toNativeUtf8();
    final textPtr = text.toNativeUtf8();
    final authorPtr = author.toNativeUtf8();
    final passwordPtr = password.toNativeUtf8();
    final kindPtr = kind.toNativeUtf8();
    final tagsPtr = tagsJson.toNativeUtf8();

    _addEntry(idPtr, textPtr, authorPtr, passwordPtr, kindPtr, tagsPtr);

    malloc.free(idPtr);
    malloc.free(textPtr);
    malloc.free(authorPtr);
    malloc.free(passwordPtr);
    malloc.free(kindPtr);
    malloc.free(tagsPtr);
  }

  List<JournalEntry> listEntries() {
    final ptr = _listEntries();
    final jsonStr = ptr.toDartString();
    _freeString(ptr);

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
    _freeString(resultPtr);

    malloc.free(idPtr);
    malloc.free(pwPtr);

    return result;
  }
}
