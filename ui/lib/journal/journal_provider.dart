import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'journal_service.dart';

/// Reads/writes the encrypted journal store.
final journalServiceProvider = Provider<JournalService>((ref) {
  return JournalService(ref.watch(journalVaultServiceProvider));
});

/// All Markdown notes in the journal, newest first. Rebuilds when the store
/// is (un)locked.
final journalNotesProvider = FutureProvider<List<JournalNote>>((ref) async {
  final unlocked = ref.watch(journalVaultProvider).unlocked;
  if (!unlocked) return const [];
  return ref.watch(journalServiceProvider).listNotes();
});
