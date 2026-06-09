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
  Pointer<Utf8>,
);
typedef LumenAddEntry = void Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef LumenUpdateEntryNative = Void Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef LumenUpdateEntry = void Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef LumenSetEntryMoodNative = Void Function(
    Pointer<Utf8>, Pointer<Utf8>);
typedef LumenSetEntryMood = void Function(
    Pointer<Utf8>, Pointer<Utf8>);

typedef LumenSetEntryStatusNative = Void Function(
    Pointer<Utf8>, Pointer<Utf8>);
typedef LumenSetEntryStatus = void Function(
    Pointer<Utf8>, Pointer<Utf8>);

typedef LumenDeleteEntryNative = Void Function(Pointer<Utf8>);
typedef LumenDeleteEntry = void Function(Pointer<Utf8>);

typedef LumenGetEntryNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef LumenGetEntry = Pointer<Utf8> Function(Pointer<Utf8>);

typedef LumenListEntriesNative = Pointer<Utf8> Function();
typedef LumenListEntries = Pointer<Utf8> Function();

typedef LumenSearchEntriesNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef LumenSearchEntries = Pointer<Utf8> Function(Pointer<Utf8>);

typedef LumenSearchFtsNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef LumenSearchFts = Pointer<Utf8> Function(Pointer<Utf8>);

typedef LumenGetStreakNative = Int32 Function();
typedef LumenGetStreak = int Function();

typedef LumenDecryptEntryNative = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef LumenDecryptEntry = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef LumenParseTaskNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef LumenParseTask = Pointer<Utf8> Function(Pointer<Utf8>);

typedef LumenListFoldersNative = Pointer<Utf8> Function();
typedef LumenListFolders = Pointer<Utf8> Function();

typedef LumenCreateFolderNative = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>);
typedef LumenCreateFolder = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>);

typedef LumenDeleteFolderNative = Void Function(Pointer<Utf8>);
typedef LumenDeleteFolder = void Function(Pointer<Utf8>);

typedef LumenMoveToFolderNative = Void Function(
    Pointer<Utf8>, Pointer<Utf8>);
typedef LumenMoveToFolder = void Function(
    Pointer<Utf8>, Pointer<Utf8>);

typedef LumenTogglePinNative = Int32 Function(Pointer<Utf8>);
typedef LumenTogglePin = int Function(Pointer<Utf8>);

typedef LumenExportProjectNative = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>);
typedef LumenExportProject = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>);

typedef LumenExportAllNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef LumenExportAll = Pointer<Utf8> Function(Pointer<Utf8>);

typedef LumenImportNative = Int32 Function(Pointer<Utf8>);
typedef LumenImport = int Function(Pointer<Utf8>);

typedef LumenUnlockNative = Int32 Function(Pointer<Utf8>);
typedef LumenUnlock = int Function(Pointer<Utf8>);

typedef LumenLockNative = Int32 Function();
typedef LumenLock = int Function();

typedef LumenIsUnlockedNative = Int32 Function();
typedef LumenIsUnlocked = int Function();

typedef LumenHasPasswordNative = Int32 Function();
typedef LumenHasPassword = int Function();

typedef LumenSetPasswordNative = Int32 Function(Pointer<Utf8>);
typedef LumenSetPassword = int Function(Pointer<Utf8>);

typedef LumenListVaultsNative = Pointer<Utf8> Function();
typedef LumenListVaults = Pointer<Utf8> Function();

typedef LumenOpenVaultNative = Int32 Function(Pointer<Utf8>);
typedef LumenOpenVault = int Function(Pointer<Utf8>);

typedef LumenSyncPushNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef LumenSyncPush = int Function(Pointer<Utf8>, Pointer<Utf8>);

typedef LumenSyncPullNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef LumenSyncPull = Pointer<Utf8> Function(Pointer<Utf8>);

typedef LumenSyncListConflictsNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef LumenSyncListConflicts = Pointer<Utf8> Function(Pointer<Utf8>);

typedef LumenSyncAcceptConflictNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef LumenSyncAcceptConflict = int Function(Pointer<Utf8>, Pointer<Utf8>, int);

typedef LumenFreeStringNative = Void Function(Pointer<Utf8>);
typedef LumenFreeString = void Function(Pointer<Utf8>);

typedef LumenAddAssetNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef LumenAddAsset = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef LumenGetAssetsNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef LumenGetAssets = Pointer<Utf8> Function(Pointer<Utf8>);

typedef LumenGetAssetDataNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef LumenGetAssetData = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);

typedef LumenImportStoicNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef LumenImportStoic = int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

class LumenCore {
  late final DynamicLibrary _lib;
  late final LumenAddEntry _addEntry;
  late final LumenUpdateEntry _updateEntry;
  late final LumenSetEntryMood _setEntryMood;
  late final LumenSetEntryStatus _setEntryStatus;
  late final LumenDeleteEntry _deleteEntry;
  late final LumenGetEntry _getEntry;
  late final LumenListEntries _listEntries;
  late final LumenSearchEntries _searchEntries;
  late final LumenSearchFts _searchFts;
  late final LumenGetStreak _getStreak;
  late final LumenDecryptEntry _decryptEntry;
  late final LumenParseTask _parseTask;
  late final LumenListFolders _listFolders;
  late final LumenCreateFolder _createFolder;
  late final LumenDeleteFolder _deleteFolder;
  late final LumenMoveToFolder _moveToFolder;
  late final LumenTogglePin _togglePin;
  late final LumenExportProject _exportProject;
  late final LumenExportAll _exportAll;
  late final LumenImport _import;
  late final LumenUnlock _unlock;
  late final LumenLock _lock;
  late final LumenIsUnlocked _isUnlocked;
  late final LumenHasPassword _hasPassword;
  late final LumenSetPassword _setPassword;
  late final LumenListVaults _listVaults;
  late final LumenOpenVault _openVault;
  late final LumenSyncPush _syncPush;
  late final LumenSyncPull _syncPull;
  late final LumenSyncListConflicts _syncListConflicts;
  late final LumenSyncAcceptConflict _syncAcceptConflict;
  late final LumenAddAsset _addAsset;
  late final LumenGetAssets _getAssets;
  late final LumenGetAssetData _getAssetData;
  late final LumenImportStoic _importStoic;
  late final LumenFreeString _freeString;

  LumenCore() {
    _lib = loadLumenLibrary();

    _addEntry = _lib
        .lookupFunction<LumenAddEntryNative, LumenAddEntry>('lumen_add_entry');
    _updateEntry = _lib.lookupFunction<LumenUpdateEntryNative, LumenUpdateEntry>(
        'lumen_update_entry');
    _setEntryMood = _lib.lookupFunction<LumenSetEntryMoodNative,
        LumenSetEntryMood>('lumen_set_entry_mood');
    _setEntryStatus = _lib.lookupFunction<LumenSetEntryStatusNative,
        LumenSetEntryStatus>('lumen_set_entry_status');
    _deleteEntry = _lib.lookupFunction<LumenDeleteEntryNative, LumenDeleteEntry>(
        'lumen_delete_entry');
    _getEntry = _lib
        .lookupFunction<LumenGetEntryNative, LumenGetEntry>('lumen_get_entry');
    _listEntries = _lib.lookupFunction<LumenListEntriesNative,
        LumenListEntries>('lumen_list_entries');
    _searchEntries = _lib.lookupFunction<LumenSearchEntriesNative,
        LumenSearchEntries>('lumen_search_entries');
    _searchFts = _lib.lookupFunction<LumenSearchFtsNative,
        LumenSearchFts>('lumen_search_entries_fts');
    _getStreak = _lib
        .lookupFunction<LumenGetStreakNative, LumenGetStreak>('lumen_get_streak');
    _decryptEntry = _lib.lookupFunction<LumenDecryptEntryNative,
        LumenDecryptEntry>('lumen_decrypt_entry');
    _parseTask = _lib
        .lookupFunction<LumenParseTaskNative, LumenParseTask>('lumen_parse_task');
    _listFolders = _lib
        .lookupFunction<LumenListFoldersNative, LumenListFolders>('lumen_list_folders');
    _createFolder = _lib.lookupFunction<LumenCreateFolderNative,
        LumenCreateFolder>('lumen_create_folder');
    _deleteFolder = _lib
        .lookupFunction<LumenDeleteFolderNative, LumenDeleteFolder>('lumen_delete_folder');
    _moveToFolder = _lib.lookupFunction<LumenMoveToFolderNative,
        LumenMoveToFolder>('lumen_move_to_folder');
    _togglePin = _lib
        .lookupFunction<LumenTogglePinNative, LumenTogglePin>('lumen_toggle_pin');
    _exportProject = _lib.lookupFunction<LumenExportProjectNative,
        LumenExportProject>('lumen_export_project');
    _exportAll = _lib.lookupFunction<LumenExportAllNative, LumenExportAll>(
        'lumen_export_all');
    _import =
        _lib.lookupFunction<LumenImportNative, LumenImport>('lumen_import');
    _unlock = _lib.lookupFunction<LumenUnlockNative, LumenUnlock>('lumen_unlock');
    _lock = _lib.lookupFunction<LumenLockNative, LumenLock>('lumen_lock');
    _isUnlocked = _lib.lookupFunction<LumenIsUnlockedNative, LumenIsUnlocked>('lumen_is_unlocked');
    _hasPassword = _lib.lookupFunction<LumenHasPasswordNative, LumenHasPassword>('lumen_has_password');
    _setPassword = _lib.lookupFunction<LumenSetPasswordNative, LumenSetPassword>('lumen_set_password');
    _listVaults = _lib.lookupFunction<LumenListVaultsNative, LumenListVaults>('lumen_list_vaults');
    _openVault = _lib.lookupFunction<LumenOpenVaultNative, LumenOpenVault>('lumen_open_vault');
    _syncPush =
        _lib.lookupFunction<LumenSyncPushNative, LumenSyncPush>('lumen_sync_push');
    _syncPull =
        _lib.lookupFunction<LumenSyncPullNative, LumenSyncPull>('lumen_sync_pull');
    _syncListConflicts = _lib.lookupFunction<LumenSyncListConflictsNative, LumenSyncListConflicts>('lumen_sync_list_conflicts');
    _syncAcceptConflict = _lib.lookupFunction<LumenSyncAcceptConflictNative, LumenSyncAcceptConflict>('lumen_sync_accept_conflict');
    _addAsset = _lib.lookupFunction<LumenAddAssetNative, LumenAddAsset>('lumen_add_asset');
    _getAssets = _lib.lookupFunction<LumenGetAssetsNative, LumenGetAssets>('lumen_get_assets');
    _getAssetData = _lib.lookupFunction<LumenGetAssetDataNative, LumenGetAssetData>('lumen_get_asset_data');
    _importStoic = _lib.lookupFunction<LumenImportStoicNative, LumenImportStoic>('lumen_import_stoic');
    _freeString = _lib.lookupFunction<LumenFreeStringNative, LumenFreeString>(
        'lumen_free_string');
  }

  void _free(Pointer<Utf8> ptr) {
    if (ptr != nullptr) _freeString(ptr);
  }

  void addEntry(String text, String author, String password,
      {String id = '',
      String kind = 'journal',
      List<String> tags = const [],
      String displayTitle = ''}) {
    final tagsJson = jsonEncode(tags);

    final idPtr = id.toNativeUtf8();
    final textPtr = text.toNativeUtf8();
    final authorPtr = author.toNativeUtf8();
    final passwordPtr = password.toNativeUtf8();
    final kindPtr = kind.toNativeUtf8();
    final tagsPtr = tagsJson.toNativeUtf8();
    final displayTitlePtr = displayTitle.toNativeUtf8();

    _addEntry(
        idPtr, textPtr, authorPtr, passwordPtr, kindPtr, tagsPtr, displayTitlePtr);

    malloc.free(idPtr);
    malloc.free(textPtr);
    malloc.free(authorPtr);
    malloc.free(passwordPtr);
    malloc.free(kindPtr);
    malloc.free(tagsPtr);
    malloc.free(displayTitlePtr);
  }

  void updateEntry(String id, String text, String author, String password,
      {String kind = 'journal',
      List<String> tags = const [],
      String displayTitle = ''}) {
    final tagsJson = jsonEncode(tags);

    final idPtr = id.toNativeUtf8();
    final textPtr = text.toNativeUtf8();
    final authorPtr = author.toNativeUtf8();
    final passwordPtr = password.toNativeUtf8();
    final kindPtr = kind.toNativeUtf8();
    final tagsPtr = tagsJson.toNativeUtf8();
    final displayTitlePtr = displayTitle.toNativeUtf8();

    _updateEntry(
        idPtr, textPtr, authorPtr, passwordPtr, kindPtr, tagsPtr, displayTitlePtr);

    malloc.free(idPtr);
    malloc.free(textPtr);
    malloc.free(authorPtr);
    malloc.free(passwordPtr);
    malloc.free(kindPtr);
    malloc.free(tagsPtr);
    malloc.free(displayTitlePtr);
  }

  void setEntryMood(String id, String? mood) {
    final idPtr = id.toNativeUtf8();
    final moodPtr = mood?.toNativeUtf8() ?? nullptr;
    _setEntryMood(idPtr, moodPtr);
    malloc.free(idPtr);
    if (moodPtr != nullptr) malloc.free(moodPtr);
  }

  void setEntryStatus(String id, String status) {
    final idPtr = id.toNativeUtf8();
    final statusPtr = status.toNativeUtf8();
    _setEntryStatus(idPtr, statusPtr);
    malloc.free(idPtr);
    malloc.free(statusPtr);
  }

  void deleteEntry(String id) {
    final idPtr = id.toNativeUtf8();
    _deleteEntry(idPtr);
    malloc.free(idPtr);
  }

  JournalEntry? getEntry(String id) {
    final idPtr = id.toNativeUtf8();
    final ptr = _getEntry(idPtr);
    malloc.free(idPtr);

    final jsonStr = ptr.toDartString();
    _free(ptr);

    if (jsonStr.isEmpty || jsonStr == 'null') return null;
    final decoded = jsonDecode(jsonStr);
    if (decoded == null) return null;
    return JournalEntry.fromJson(decoded as Map<String, dynamic>);
  }

  List<JournalEntry> listEntries() {
    final ptr = _listEntries();
    final jsonStr = ptr.toDartString();
    _free(ptr);

    final decoded = jsonDecode(jsonStr) as List<dynamic>;
    return decoded
        .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  List<JournalEntry> searchEntries(String query) {
    final queryPtr = query.toNativeUtf8();
    final ptr = _searchEntries(queryPtr);
    malloc.free(queryPtr);

    final jsonStr = ptr.toDartString();
    _free(ptr);

    final decoded = jsonDecode(jsonStr) as List<dynamic>;
    return decoded
        .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  List<JournalEntry> searchEntriesFts(String query) {
    final queryPtr = query.toNativeUtf8();
    final ptr = _searchFts(queryPtr);
    malloc.free(queryPtr);

    final jsonStr = ptr.toDartString();
    _free(ptr);

    final decoded = jsonDecode(jsonStr) as List<dynamic>;
    return decoded
        .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  int getStreak() {
    return _getStreak();
  }

  String decryptEntry(String id, String password) {
    final idPtr = id.toNativeUtf8();
    final pwPtr = password.toNativeUtf8();

    final resultPtr = _decryptEntry(idPtr, pwPtr);
    final result = resultPtr.toDartString();
    _free(resultPtr);

    malloc.free(idPtr);
    malloc.free(pwPtr);

    return result;
  }

  Map<String, dynamic> parseTask(String text) {
    final textPtr = text.toNativeUtf8();
    final resultPtr = _parseTask(textPtr);
    final jsonStr = resultPtr.toDartString();
    _free(resultPtr);
    malloc.free(textPtr);
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> listFolders() {
    final ptr = _listFolders();
    final jsonStr = ptr.toDartString();
    _free(ptr);
    final decoded = jsonDecode(jsonStr) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  String createFolder(String name, {String? parentId}) {
    final namePtr = name.toNativeUtf8();
    final parentPtr = parentId?.toNativeUtf8() ?? nullptr;
    final resultPtr = _createFolder(namePtr, parentPtr);
    final id = resultPtr.toDartString();
    _free(resultPtr);
    malloc.free(namePtr);
    if (parentPtr != nullptr) malloc.free(parentPtr);
    return id;
  }

  void deleteFolder(String id) {
    final idPtr = id.toNativeUtf8();
    _deleteFolder(idPtr);
    malloc.free(idPtr);
  }

  void moveToFolder(String entryId, {String? folderId}) {
    final eidPtr = entryId.toNativeUtf8();
    final fidPtr = folderId?.toNativeUtf8() ?? nullptr;
    _moveToFolder(eidPtr, fidPtr);
    malloc.free(eidPtr);
    if (fidPtr != nullptr) malloc.free(fidPtr);
  }

  bool togglePin(String entryId) {
    final idPtr = entryId.toNativeUtf8();
    final result = _togglePin(idPtr);
    malloc.free(idPtr);
    return result != 0;
  }

  String exportProject(String projectId, String password) {
    final idPtr = projectId.toNativeUtf8();
    final pwPtr = password.toNativeUtf8();
    final resultPtr = _exportProject(idPtr, pwPtr);
    final result = resultPtr.toDartString();
    _free(resultPtr);
    malloc.free(idPtr);
    malloc.free(pwPtr);
    return result;
  }

  String exportAll(String password) {
    final pwPtr = password.toNativeUtf8();
    final resultPtr = _exportAll(pwPtr);
    final result = resultPtr.toDartString();
    _free(resultPtr);
    malloc.free(pwPtr);
    return result;
  }

  int import(String json) {
    final jsonPtr = json.toNativeUtf8();
    final result = _import(jsonPtr);
    malloc.free(jsonPtr);
    return result;
  }

  bool unlock(String password) {
    final pwPtr = password.toNativeUtf8();
    final result = _unlock(pwPtr);
    malloc.free(pwPtr);
    return result != 0;
  }

  bool lock() {
    return _lock() != 0;
  }

  bool isUnlocked() {
    return _isUnlocked() != 0;
  }

  bool hasPassword() {
    return _hasPassword() != 0;
  }

  bool setPassword(String password) {
    final pwPtr = password.toNativeUtf8();
    final result = _setPassword(pwPtr);
    malloc.free(pwPtr);
    return result != 0;
  }

  List<String> listVaults() {
    final ptr = _listVaults();
    final json = ptr.toDartString();
    _free(ptr);
    final decoded = jsonDecode(json) as List;
    return decoded.cast<String>();
  }

  bool openVault(String name) {
    final namePtr = name.toNativeUtf8();
    final result = _openVault(namePtr);
    malloc.free(namePtr);
    return result != 0;
  }

  int syncPush(String syncDbPath, List<String> entryIds) {
    final pathPtr = syncDbPath.toNativeUtf8();
    final idsJson = jsonEncode(entryIds);
    final idsPtr = idsJson.toNativeUtf8();
    final result = _syncPush(pathPtr, idsPtr);
    malloc.free(pathPtr);
    malloc.free(idsPtr);
    return result;
  }

  String syncPull(String syncDbPath) {
    final pathPtr = syncDbPath.toNativeUtf8();
    final resultPtr = _syncPull(pathPtr);
    malloc.free(pathPtr);
    if (resultPtr == nullptr) return '[]';
    final result = resultPtr.toDartString();
    _free(resultPtr);
    return result;
  }

  String syncListConflicts(String syncDbPath) {
    final pathPtr = syncDbPath.toNativeUtf8();
    final resultPtr = _syncListConflicts(pathPtr);
    malloc.free(pathPtr);
    if (resultPtr == nullptr) return '[]';
    final result = resultPtr.toDartString();
    _free(resultPtr);
    return result;
  }

  bool syncAcceptConflict(String syncDbPath, String conflictId, bool keepLocal) {
    final pathPtr = syncDbPath.toNativeUtf8();
    final cidPtr = conflictId.toNativeUtf8();
    final result = _syncAcceptConflict(pathPtr, cidPtr, keepLocal ? 1 : 0);
    malloc.free(pathPtr);
    malloc.free(cidPtr);
    return result != 0;
  }

  String addAsset(String entryId, String fileName, String mimeType, String base64Data, String password) {
    final entryIdPtr = entryId.toNativeUtf8();
    final fileNamePtr = fileName.toNativeUtf8();
    final mimeTypePtr = mimeType.toNativeUtf8();
    final dataPtr = base64Data.toNativeUtf8();
    final pwPtr = password.toNativeUtf8();
    final resultPtr = _addAsset(entryIdPtr, fileNamePtr, mimeTypePtr, dataPtr, pwPtr);
    final result = resultPtr.toDartString();
    _free(resultPtr);
    malloc.free(entryIdPtr);
    malloc.free(fileNamePtr);
    malloc.free(mimeTypePtr);
    malloc.free(dataPtr);
    malloc.free(pwPtr);
    return result;
  }

  String getAssets(String entryId) {
    final entryIdPtr = entryId.toNativeUtf8();
    final resultPtr = _getAssets(entryIdPtr);
    malloc.free(entryIdPtr);
    if (resultPtr == nullptr) return '[]';
    final result = resultPtr.toDartString();
    _free(resultPtr);
    return result;
  }

  String getAssetData(String assetId, String password) {
    final assetIdPtr = assetId.toNativeUtf8();
    final pwPtr = password.toNativeUtf8();
    final resultPtr = _getAssetData(assetIdPtr, pwPtr);
    malloc.free(assetIdPtr);
    malloc.free(pwPtr);
    if (resultPtr == nullptr) return '{"error":"null"}';
    final result = resultPtr.toDartString();
    _free(resultPtr);
    return result;
  }

  int importStoic(String exportDir, String password, String author) {
    final dirPtr = exportDir.toNativeUtf8();
    final pwPtr = password.toNativeUtf8();
    final authorPtr = author.toNativeUtf8();
    final result = _importStoic(dirPtr, pwPtr, authorPtr);
    malloc.free(dirPtr);
    malloc.free(pwPtr);
    malloc.free(authorPtr);
    return result;
  }
}
