import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../journal/journal_provider.dart';
import '../journal/journal_service.dart';
import '../state/providers.dart';
import 'kb_provider.dart';

/// Opens the daily note for a date, creating it from the template when it
/// does not exist yet.
///
/// The note is created from the user's daily template, so every daily entry
/// starts from the same shape. An existing note is left untouched — the
/// button opens it rather than overwriting it.
///
/// Returns the path of the note.
Future<String> openDailyNote(WidgetRef ref, {DateTime? date}) async {
  final when = date ?? DateTime.now();
  final kb = ref.read(kbServiceProvider);
  final service = ref.read(journalServiceProvider);

  final path = await kb.dailyNotePath(when);

  if (!await _exists(service, path)) {
    final content = await kb.renderDailyTemplate(when);
    await service.write(path, content);
    ref.invalidate(journalNotesProvider);
  }

  openJournalNote(ref, path);
  return path;
}

/// Whether the note at [path] is already there.
///
/// The vault itself is the answer: the note list may still be loading when
/// the user reaches for the button, and a note that is not in the list yet
/// must not be overwritten.
Future<bool> _exists(JournalService service, String path) async {
  try {
    await service.read(path);
    return true;
  } catch (_) {
    // A note that cannot be read is treated as missing, so the template
    // gives the day a fresh start rather than failing outright.
    return false;
  }
}
