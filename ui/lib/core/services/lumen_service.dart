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

  void addEntry(String text, String author, String password,
      {String id = '',
      String kind = 'journal',
      List<String> tags = const [],
      String displayTitle = ''}) {
    _lumen.addEntry(text, author, password,
        id: id, kind: kind, tags: tags, displayTitle: displayTitle);
    refresh();
  }

  void updateEntry(String id, String text, String author, String password,
      {String kind = 'journal',
      List<String> tags = const [],
      String displayTitle = ''}) {
    _lumen.updateEntry(id, text, author, password,
        kind: kind, tags: tags, displayTitle: displayTitle);
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
