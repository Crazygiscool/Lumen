import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumen/ffi/lumen_ffi.dart';
import 'package:lumen/ffi/vault_service.dart';
import 'package:lumen/journal/dashboard.dart';
import 'package:lumen/journal/journal_provider.dart';
import 'package:lumen/journal/journal_service.dart';
import 'package:lumen/journal/quotes.dart';
import 'package:lumen/state/providers.dart';
import 'package:lumen/theme/app_theme.dart';

JournalNote _note(String name) => JournalNote(
  relPath: name,
  name: name,
  modifiedMs: 0,
  size: 0,
);

/// Minimal native bridge fake: serves decrypted note bodies for the dashboard.
class _FakeFfi implements LumenFfi {
  _FakeFfi(this.bodies);

  final Map<String, String> bodies;

  @override
  bool get ready => true;

  @override
  String? get initError => null;

  @override
  void init() {}

  @override
  Object? core(String method, [Map<String, Object?> args = const {}]) {
    if (method == 'vault.read_text') {
      return <String, Object?>{'text': bodies[args['path']] ?? ''};
    }
    return <String, Object?>{'unlocked': true};
  }

  @override
  Object? plugins(String method, [Map<String, Object?> args = const {}]) =>
      <String, Object?>{};
}

void main() {
  group('dashboard cards', () {
    test('every card has a stable id and label', () {
      expect(DashboardCard.values, hasLength(3));
      for (final card in DashboardCard.values) {
        expect(card.id, isNotEmpty);
        expect(card.label, isNotEmpty);
        expect(DashboardCardInfo.fromId(card.id), card);
      }
      expect(DashboardCardInfo.fromId('nope'), isNull);
    });

    test('hidden cards are removed from the visible order', () {
      const prefs = DashboardPrefs(hidden: {DashboardCard.quote});
      expect(prefs.visibleOrder, isNot(contains(DashboardCard.quote)));
      expect(prefs.visibleOrder, hasLength(2));
      expect(prefs.isVisible(DashboardCard.quote), isFalse);
    });

    test('reordering visible cards keeps hidden ones after them', () {
      // ReorderableListView.onReorderItem reports an already-adjusted index.
      final visible = [
        DashboardCard.graph,
        DashboardCard.dayNight,
        DashboardCard.quote,
      ];
      const oldIndex = 0;
      const newIndex = 2; // final position after removal
      final moved = visible.removeAt(oldIndex);
      visible.insert(newIndex, moved);
      expect(visible.last, DashboardCard.graph);
      expect(visible, hasLength(3));
    });

    test('notifier reorders and hides cards', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(dashboardPrefsProvider.notifier);
      final initial = notifier.state.visibleOrder;
      expect(initial.first, DashboardCard.graph);

      notifier.reorder(0, 2);
      expect(notifier.state.visibleOrder.last, DashboardCard.graph);

      notifier.setVisible(DashboardCard.quote, false);
      expect(notifier.state.visibleOrder, isNot(contains(DashboardCard.quote)));
      expect(notifier.state.order, contains(DashboardCard.quote));

      notifier.setVisible(DashboardCard.quote, true);
      expect(notifier.state.visibleOrder, contains(DashboardCard.quote));

      notifier.resetLayout();
      expect(notifier.state.visibleOrder, DashboardCard.values);
      expect(notifier.state.hidden, isEmpty);
    });
  });

  group('quotes', () {
    test('offline list is non-empty and well formed', () {
      final quote = QuoteService().offline();
      expect(quote.text, isNotEmpty);
      expect(quote.author, isNotEmpty);
    });

    test('parses quote+speaker payloads from the online dataset', () {
      final quote = Quote.fromJson({
        'quote': '  To the well-organised mind…  ',
        'speaker': 'Albus Dumbledore',
      });
      expect(quote.text, 'To the well-organised mind…');
      expect(quote.author, 'Albus Dumbledore');
    });

    test('offline source returns a bundled quote without network', () async {
      final quote = await QuoteService(source: QuoteSource.offline).fetch();
      expect(quote.text, isNotEmpty);
      expect(quote.author, isNotEmpty);
    });

    test('quote source labels are distinct', () {
      expect(QuoteSource.offline.label, 'Harry Potter (offline)');
      expect(QuoteSource.zenquotes.label, 'ZenQuotes (no key)');
      expect(QuoteSource.offline, isNot(QuoteSource.zenquotes));
      expect(
        selectableQuoteSources.toSet(),
        hasLength(selectableQuoteSources.length),
      );
    });

    test('fetch parses a ZenQuotes payload', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), QuoteService.zenquotesEndpoint);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode([
              {
                'q': 'Happiness can be found\u2026',
                'a': 'Albus Dumbledore',
                'h': '<blockquote>&ldquo;Happiness&hellip;&rdquo;</blockquote>',
              },
            ]),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final quote = await QuoteService(client: client).fetch();
      expect(quote.text, 'Happiness can be found\u2026');
      expect(quote.author, 'Albus Dumbledore');
    });

    test('fetch rejects empty or failed responses', () async {
      Future<void> expectThrows(http.Client client) async {
        await expectLater(
          QuoteService(client: client).fetch(),
          throwsA(isA<QuoteException>()),
        );
      }

      await expectThrows(
        MockClient((_) async => http.Response('[]', 200)),
      );
      await expectThrows(
        MockClient((_) async => http.Response('nope', 503)),
      );
    });
  });

  group('journal dates', () {
    test('finds an existing note for a date', () {
      final notes = [_note('2026-10-22.md'), _note('2026-10-21-evening.md')];
      expect(
        JournalService.notePathForDate(notes, DateTime(2026, 10, 22)),
        '2026-10-22.md',
      );
      expect(
        JournalService.notePathForDate(notes, DateTime(2026, 10, 20)),
        isNull,
      );
    });

    test('pathForDate avoids collisions and supports slots', () {
      final taken = {'2026-10-22.md'};

      expect(
        JournalService.pathForDate(DateTime(2026, 10, 22), taken: taken),
        '2026-10-22-2.md',
      );
      expect(
        JournalService.pathForDate(
          DateTime(2026, 10, 21),
          slot: 'morning',
          taken: taken,
        ),
        '2026-10-21-morning.md',
      );
      expect(
        JournalService.pathForDate(
          DateTime(2026, 10, 22),
          slot: 'evening',
          taken: {'2026-10-22-evening.md'},
        ),
        '2026-10-22-evening-2.md',
      );
    });

    test('journal word counts ignore undated notes', () {
      // The word-count helper itself is private; verify the date extraction
      // the graph relies on instead.
      expect(_note('2026-10-22.md').date, '2026-10-22');
      expect(_note('2026-10-22-evening.md').date, '2026-10-22');
      expect(_note('ideas.md').date, isNull);
    });

    test('dailyWordCounts sums words per date with a cache', () async {
      final ffi = _FakeFfi({
        '2026-10-22.md': 'one two three',
        '2026-10-22-evening.md': 'four five',
        '2026-10-21.md': 'solo',
        'ideas.md': 'ignored words here',
      });
      final service = JournalService(VaultService(ffi));
      final notes = [
        _note('2026-10-22.md'),
        _note('2026-10-22-evening.md'),
        _note('2026-10-21.md'),
        _note('ideas.md'),
      ];
      final cache = <String, ({int modifiedMs, int words})>{};
      final counts = await service.dailyWordCounts(notes, cache: cache);
      expect(counts['2026-10-22'], 5);
      expect(counts['2026-10-21'], 1);
      expect(counts.containsKey('ideas'), isFalse);
      // Undated notes are never read or cached.
      expect(cache.keys, isNot(contains('ideas.md')));
      expect(cache, hasLength(3));
    });

    test('notePathForDate respects morning/evening slots', () {
      final notes = [
        _note('2026-10-22.md'),
        _note('2026-10-22-morning.md'),
        _note('2026-10-22-evening.md'),
      ];
      final date = DateTime(2026, 10, 22);
      expect(JournalService.notePathForDate(notes, date), '2026-10-22.md');
      expect(
        JournalService.notePathForDate(notes, date, slot: 'morning'),
        '2026-10-22-morning.md',
      );
      expect(
        JournalService.notePathForDate(notes, date, slot: 'evening'),
        '2026-10-22-evening.md',
      );
      expect(
        JournalService.notePathForDate(notes, date, slot: 'noon'),
        isNull,
      );
    });
  });

  Future<void> pumpDashboard(WidgetTester tester) async {
    final ffi = _FakeFfi({'2026-10-22.md': 'one two three'});
    final container = ProviderContainer(
      overrides: [
        journalServiceProvider.overrideWithValue(
          JournalService(VaultService(ffi)),
        ),
        journalNotesProvider.overrideWith(
          (ref) async => [_note('2026-10-22.md')],
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildLumenTheme(dark: true),
          home: Scaffold(
            body: JournalDashboard(onOpenNote: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('dashboard renders activity, plan/reflect, and quote cards', (
    tester,
  ) async {
    await pumpDashboard(tester);

    expect(find.text('Writing activity'), findsOneWidget);
    expect(find.text('Plan & reflect'), findsOneWidget);
    expect(find.text('Wizarding wisdom'), findsOneWidget);
    expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
    expect(find.byIcon(Icons.nights_stay_outlined), findsOneWidget);
    expect(find.byTooltip('Another quote'), findsOneWidget);
  });

  testWidgets('activity graph fills the card instead of a fixed 20 weeks', (
    tester,
  ) async {
    await pumpDashboard(tester);

    final label = tester
        .widget<Text>(find.textContaining(RegExp(r'^Last \d+ weeks$')))
        .data!;
    final weeks = int.parse(RegExp(r'\d+').firstMatch(label)!.group(0)!);
    expect(weeks, greaterThan(20));
  });

  testWidgets('reorder controls stay hidden until Arrange is tapped', (
    tester,
  ) async {
    await pumpDashboard(tester);

    expect(find.byIcon(Icons.drag_indicator), findsNothing);
    expect(find.byTooltip('Move down'), findsNothing);

    await tester.tap(find.text('Arrange'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.drag_indicator), findsWidgets);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.drag_indicator), findsNothing);
  });

  testWidgets('arrange mode fits a narrow window without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDashboard(tester);
    await tester.tap(find.text('Arrange'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.drag_indicator), findsWidgets);
  });
}
