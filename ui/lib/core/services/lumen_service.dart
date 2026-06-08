import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../lumen_core.dart';
import '../models/journal_entry.dart';
import 'core_provider.dart';

class EntriesNotifier extends Notifier<List<JournalEntry>> {
  late final LumenCore _lumen;

  @override
  List<JournalEntry> build() {
    _lumen = ref.read(lumenCoreProvider);
    return _lumen.listEntries();
  }

  void refresh() {
    state = _lumen.listEntries();
  }

  // Background decryption helper
  static String _decryptInBackground(Map<String, String> args) {
    final core = LumenCore();
    return core.decryptEntry(args['id']!, args['password']!);
  }

  Future<String> decryptEntryAsync(String id, String password) async {
    return compute(_decryptInBackground, {
      'id': id,
      'password': password,
    });
  }

  static void _addEntryInBackground(Map<String, dynamic> args) {
    final core = LumenCore();
    core.addEntry(
      args['text']!,
      args['author']!,
      args['password']!,
      id: args['id']!,
      kind: args['kind']!,
      tags: args['tags']!,
      displayTitle: args['displayTitle']!,
    );
  }

  Future<void> addEntry(String text, String author, String password,
      {String id = '',
      String kind = 'journal',
      List<String> tags = const [],
      String displayTitle = ''}) async {
    await compute(_addEntryInBackground, {
      'text': text,
      'author': author,
      'password': password,
      'id': id,
      'kind': kind,
      'tags': tags,
      'displayTitle': displayTitle,
    });
    refresh();
  }

  static void _updateEntryInBackground(Map<String, dynamic> args) {
    final core = LumenCore();
    core.updateEntry(
      args['id']!,
      args['text']!,
      args['author']!,
      args['password']!,
      kind: args['kind']!,
      tags: args['tags']!,
      displayTitle: args['displayTitle']!,
    );
  }

  Future<void> updateEntry(String id, String text, String author, String password,
      {String kind = 'journal',
      List<String> tags = const [],
      String displayTitle = ''}) async {
    await compute(_updateEntryInBackground, {
      'id': id,
      'text': text,
      'author': author,
      'password': password,
      'kind': kind,
      'tags': tags,
      'displayTitle': displayTitle,
    });
    refresh();
  }

  void setEntryMood(String id, String? mood) {
    _lumen.setEntryMood(id, mood);
    refresh();
  }

  void setEntryStatus(String id, String status) {
    _lumen.setEntryStatus(id, status);
    refresh();
  }

  void deleteEntry(String id) {
    _lumen.deleteEntry(id);
    refresh();
  }

  List<JournalEntry> search(String query) {
    return _lumen.searchEntries(query);
  }

  List<JournalEntry> searchFts(String query) {
    return _lumen.searchEntriesFts(query);
  }

  int getStreak() {
    return _lumen.getStreak();
  }

  String decryptEntry(String id, String password) {
    return _lumen.decryptEntry(id, password);
  }

  Map<String, dynamic> parseTask(String text) {
    return _lumen.parseTask(text);
  }

  List<Map<String, dynamic>> listFolders() {
    return _lumen.listFolders();
  }

  String createFolder(String name, {String? parentId}) {
    final id = _lumen.createFolder(name, parentId: parentId);
    refresh();
    return id;
  }

  void deleteFolder(String id) {
    _lumen.deleteFolder(id);
    refresh();
  }

  void moveToFolder(String entryId, {String? folderId}) {
    _lumen.moveToFolder(entryId, folderId: folderId);
    refresh();
  }

  bool togglePin(String entryId) {
    final result = _lumen.togglePin(entryId);
    refresh();
    return result;
  }

  String exportProject(String projectId, String password) {
    return _lumen.exportProject(projectId, password);
  }

  String exportAll(String password) {
    return _lumen.exportAll(password);
  }

  int import(String json) {
    final count = _lumen.import(json);
    if (count > 0) refresh();
    return count;
  }
}

final entriesProvider =
    NotifierProvider<EntriesNotifier, List<JournalEntry>>(EntriesNotifier.new);
