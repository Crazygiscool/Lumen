import 'package:flutter/foundation.dart';

import '../ffi/vault_service.dart';

/// A Markdown note in the encrypted journal store.
@immutable
class JournalNote {
  const JournalNote({
    required this.relPath,
    required this.name,
    required this.modifiedMs,
    required this.size,
  });

  final String relPath;
  final String name;
  final int modifiedMs;
  final int size;

  /// The `YYYY-MM-DD` prefix Lumen uses for daily entries, if present.
  String? get date {
    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(name);
    return match?.group(1);
  }

  String get displayTitle {
    final stem = name.replaceAll(
      RegExp(r'\.(md|markdown)$', caseSensitive: false),
      '',
    );
    final d = date;
    if (d != null) {
      final rest = stem
          .substring(d.length)
          .replaceFirst(RegExp(r'^[\s_-]+'), '')
          .trim();
      if (rest.isEmpty) return 'Daily entry';
      return rest.replaceAll(RegExp(r'[-_]+'), ' ');
    }
    return stem.replaceAll(RegExp(r'[-_]+'), ' ');
  }
}

/// Reads and writes Markdown notes in the encrypted journal store.
class JournalService {
  JournalService(this._vault);

  final VaultService _vault;

  static final _markdown = RegExp(r'\.(md|markdown)$', caseSensitive: false);

  Future<List<JournalNote>> listNotes() async {
    final entries = await _vault.list();
    final notes = <JournalNote>[
      for (final e in entries)
        if (!e.isDir && _markdown.hasMatch(e.name))
          JournalNote(
            relPath: e.relPath,
            name: e.name,
            modifiedMs: e.modifiedMs,
            size: e.size,
          ),
    ];
    // Newest first; date-prefixed names sort lexicographically.
    notes.sort((a, b) {
      final byName = b.name.compareTo(a.name);
      return byName != 0 ? byName : b.modifiedMs.compareTo(a.modifiedMs);
    });
    return notes;
  }

  Future<String> read(String relPath) => _vault.readText(relPath);

  Future<void> write(String relPath, String text) =>
      _vault.writeText(relPath, text);

  Future<void> delete(String relPath) => _vault.delete(relPath);

  Future<List<Map<String, dynamic>>> search(String query) =>
      _vault.search(query);

  /// Today's entry filename (`YYYY-MM-DD.md`).
  String todayPath() => '${_isoDate(DateTime.now())}.md';

  /// A non-colliding filename for a brand-new note opened from the UI.
  Future<String> newNotePath() async {
    final existing = (await listNotes()).map((n) => n.relPath).toSet();
    final path = todayPath();
    if (!existing.contains(path)) return path;
    for (var i = 2; i < 1000; i++) {
      final candidate = path.replaceFirst('.md', '-$i.md');
      if (!existing.contains(candidate)) return candidate;
    }
    return 'entry-${DateTime.now().millisecondsSinceEpoch}.md';
  }

  /// Number of consecutive days (ending today or yesterday) with an entry.
  int streak(List<JournalNote> notes) {
    final dates = <String>{
      for (final n in notes)
        if (n.date != null) n.date!,
    };
    var cursor = DateTime.now();
    if (!dates.contains(_isoDate(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var count = 0;
    while (dates.contains(_isoDate(cursor))) {
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  static String _isoDate(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}
