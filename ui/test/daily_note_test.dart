import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ffi/lumen_ffi.dart';
import 'package:lumen/ffi/vault_service.dart';
import 'package:lumen/journal/journal_provider.dart';
import 'package:lumen/journal/journal_service.dart';
import 'package:lumen/knowledge/daily_note.dart';
import 'package:lumen/knowledge/kb_provider.dart';
import 'package:lumen/state/providers.dart';

JournalNote _note(String relPath) => JournalNote(
  relPath: relPath,
  name: relPath,
  modifiedMs: 0,
  size: 0,
);

/// A native bridge fake that serves the template API and the note store.
class _FakeFfi implements LumenFfi {
  /// The notes in the vault.
  final Map<String, String> files = {};

  /// The notes written during the test.
  final Map<String, String> writes = {};

  @override
  bool get ready => true;

  @override
  String? get initError => null;

  @override
  void init() {}

  @override
  Object? core(String method, [Map<String, Object?> args = const {}]) {
    switch (method) {
      case 'vault.write_text':
        final path = args['path'] as String;
        final text = args['text'] as String;
        writes[path] = text;
        files[path] = text;
        return <String, Object?>{};
      case 'vault.read_text':
        final path = args['path'] as String;
        final text = files[path];
        if (text == null) throw StateError('no such note: $path');
        return <String, Object?>{'text': text};
      default:
        return <String, Object?>{'unlocked': true};
    }
  }

  @override
  Object? plugins(String method, [Map<String, Object?> args = const {}]) =>
      <String, Object?>{};

  @override
  Object? kb(String method, [Map<String, Object?> args = const {}]) {
    switch (method) {
      case 'kb.template.daily_path':
        return <String, Object?>{'path': '2026-02-03.md'};
      case 'kb.template.daily_render':
        return <String, Object?>{'content': '# 2026-02-03\n\n'};
      default:
        return <String, Object?>{};
    }
  }
}

void main() {
  testWidgets('a missing daily note is created from the template', (
    tester,
  ) async {
    final ffi = _FakeFfi();
    final container = ProviderContainer(
      overrides: [
        lumenFfiProvider.overrideWithValue(ffi),
        journalServiceProvider.overrideWithValue(
          JournalService(VaultService(ffi)),
        ),
        journalNotesProvider.overrideWith(
          (ref) async => const <JournalNote>[],
        ),
      ],
    );
    addTearDown(container.dispose);

    late String opened;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  opened = await openDailyNote(
                    ref,
                    date: DateTime(2026, 2, 3),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(opened, '2026-02-03.md');
    expect(ffi.writes['2026-02-03.md'], '# 2026-02-03\n\n');
    // The note is opened through the shared request, so the journal picks it
    // up wherever it is.
    expect(container.read(openNoteProvider), '2026-02-03.md');
  });

  testWidgets('an existing daily note is opened, not overwritten', (
    tester,
  ) async {
    final ffi = _FakeFfi();
    // The day already has a note in the vault.
    ffi.files['2026-02-03.md'] = '# My own entry\n';
    final container = ProviderContainer(
      overrides: [
        lumenFfiProvider.overrideWithValue(ffi),
        journalServiceProvider.overrideWithValue(
          JournalService(VaultService(ffi)),
        ),
        journalNotesProvider.overrideWith(
          (ref) async => [_note('2026-02-03.md')],
        ),
      ],
    );
    addTearDown(container.dispose);

    late String opened;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  opened = await openDailyNote(
                    ref,
                    date: DateTime(2026, 2, 3),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(opened, '2026-02-03.md');
    // Nothing was written: the day's note is left as the user left it.
    expect(ffi.writes, isEmpty);
  });

  test('the knowledge-base service is bound to the journal store', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(kbServiceProvider).store, 'journal');
  });
}
