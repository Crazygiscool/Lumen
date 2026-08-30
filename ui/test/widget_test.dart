import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumen/main.dart';
import 'package:lumen/shell/lumen_shell.dart';
import 'package:lumen/shell/tabs/tab_model.dart';
import 'package:lumen/shell/tabs/tabs_provider.dart';
import 'package:lumen/files/editor/file_workspace_provider.dart';
import 'package:lumen/ffi/fs_service.dart';
import 'package:lumen/ffi/lumen_ffi.dart';
import 'package:lumen/github/github_service.dart';
import 'package:lumen/journal/journal_service.dart';
import 'package:lumen/settings/settings_screen.dart';
import 'package:lumen/state/providers.dart';
import 'package:lumen/theme/app_theme.dart';
import 'package:lumen/theme/lumen_colors.dart';
import 'package:lumen/wakatime/wakatime_service.dart';

/// A [FsService] that serves canned files from a map instead of the native
/// core, so editor logic can be tested in pure Dart.
class _FakeFs extends FsService {
  _FakeFs(this.files) : super(LumenFfi.instance);
  final Map<String, String> files;

  @override
  Future<String> readText(String path) async {
    final value = files[path];
    if (value == null) throw Exception('no such file: $path');
    return value;
  }

  @override
  Future<void> writeText(String path, String text) async {
    files[path] = text;
  }
}

void main() {
  group('Theme', () {
    test('builds a Material 3 dark theme', () {
      final theme = buildLumenTheme(dark: true);
      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, true);
      expect(theme.extension<LumenCodePalette>(), isNotNull);
    });

    test('light theme resolves a light brightness', () {
      final theme = buildLumenTheme(dark: false);
      expect(theme.brightness, Brightness.light);
    });

    test('syntax palette is exposed', () {
      final palette = buildLumenTheme(dark: true).extension<LumenCodePalette>();
      expect(palette, isNotNull);
      expect(palette!.background, isNot(palette.keyword));
    });

    test('resolveThemeMode follows GTK + force overrides', () {
      final gtkDark = GtkTheme(
        available: true,
        colorScheme: 'prefer-dark',
        accentName: 'blue',
      );
      final gtkLight = GtkTheme(
        available: true,
        colorScheme: 'prefer-light',
        accentName: 'blue',
      );
      expect(resolveThemeMode(ThemeSource.system, gtkDark), ThemeMode.dark);
      expect(resolveThemeMode(ThemeSource.system, gtkLight), ThemeMode.light);
      expect(resolveThemeMode(ThemeSource.system, null), ThemeMode.dark);
      expect(resolveThemeMode(ThemeSource.dark, gtkLight), ThemeMode.dark);
      expect(resolveThemeMode(ThemeSource.light, gtkDark), ThemeMode.light);
    });

    test('GTK accents map per-brightness', () {
      expect(gtkAccentPrimary('blue', dark: true), isNot(null));
      expect(gtkAccentPrimary('blue', dark: false), isNot(null));
      expect(
        gtkAccentPrimary('blue', dark: true),
        isNot(gtkAccentPrimary('blue', dark: false)),
      );
      expect(gtkAccentPrimary('nonsense', dark: true), isNull);
    });

    test('formatBytes and formatDate helpers behave', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
    });
  });

  group('Address bar resolver', () {
    test('resolves lumen:// pages', () {
      expect(resolveInput('lumen://home').kind, TabKind.lumen);
      expect(resolveInput('lumen://home').page, LumenSection.home);
      expect(resolveInput('lumen://vault').kind, TabKind.lumen);
      expect(resolveInput('lumen://vault').page, LumenSection.vault);
      expect(resolveInput('lumen://oslab').page, LumenSection.osLab);
      expect(resolveInput('lumen://lab').page, LumenSection.osLab);
      expect(resolveInput('lumen://welcome').page, LumenSection.welcome);
      expect(resolveInput('lumen://graph').page, LumenSection.graph);
      expect(resolveInput('lumen:console').page, LumenSection.console);
      expect(resolveInput('lumen://projects').page, LumenSection.projects);
      expect(resolveInput('lumen://settings').page, LumenSection.settings);
      expect(resolveInput('').kind, TabKind.newtab);
      expect(resolveInput('lumen://files').kind, TabKind.lumen);
    });

    test('resolves a lumen://files deep link to an absolute path', () {
      final spec = resolveInput(
        'lumen://files//home/user/x',
        homePath: '/home',
      );
      expect(spec.page, LumenSection.files);
      expect(spec.path, '/home/user/x');
      expect(spec.url, startsWith('lumen://files/'));

      final rel = resolveInput(
        'lumen://files/Documents/x',
        homePath: '/home/user',
      );
      expect(rel.path, '/home/user/Documents/x');
    });

    test('resolves a lumen://vault deep link', () {
      final spec = resolveInput('lumen://vault/notes/a.md');
      expect(spec.page, LumenSection.vault);
      expect(spec.path, 'notes/a.md');
    });

    test('web urls open externally; plain text becomes a search', () {
      expect(resolveInput('https://example.com/path').kind, TabKind.web);
      expect(resolveInput('example.com').url, 'https://example.com');
      expect(resolveInput('www.example.com').kind, TabKind.web);
      expect(resolveInput('hello world').url, contains('duckduckgo.com'));
      expect(resolveInput('hello world').kind, TabKind.web);
    });

    test('absolute paths open the files section', () {
      final spec = resolveInput('/home/user/notes/idea.md');
      expect(spec.page, LumenSection.files);
      expect(spec.path, '/home/user/notes/idea.md');
      expect(spec.url, startsWith('lumen://files/'));
    });
  });

  group('TabsNotifier', () {
    test('starts on the wizard tab for a first run, new tab otherwise',
        () async {
      final first = ProviderContainer();
      addTearDown(first.dispose);
      expect(
        first.read(tabsProvider).active!.page,
        LumenSection.welcome,
        reason: 'no onboardingDone means the welcome wizard is the first tab',
      );

      SharedPreferences.setMockInitialValues({'onboardingDone': true});
      final prefs = await SharedPreferences.getInstance();
      final t = ProviderContainer(
        overrides: [tabsProvider.overrideWith(() => TabsNotifier(prefs))],
      );
      addTearDown(t.dispose);
      expect(t.read(tabsProvider).active!.kind, TabKind.newtab);
    });

    test('opens and activates tabs', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(tabsProvider.notifier);

      expect(container.read(tabsProvider).tabs, hasLength(1));

      final id = notifier.newTab();
      final state = container.read(tabsProvider);
      expect(state.tabs, hasLength(2));
      expect(state.activeId, id);
      notifier.activate(state.tabs[0].id);
      expect(container.read(tabsProvider).activeId, state.tabs[0].id);
    });

    test('closeTab removes the tab and activates a neighbor', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(tabsProvider.notifier);

      final a = notifier.newTab();
      notifier.newTab();
      expect(container.read(tabsProvider).tabs, hasLength(3));

      notifier.closeTab(a);
      var state = container.read(tabsProvider);
      expect(state.tabs, hasLength(2));
      expect(state.tabById(a), isNull);

      // Closing the last tab keeps exactly one fresh tab.
      while (state.tabs.length > 1) {
        notifier.closeTab(state.tabs.last.id);
        state = container.read(tabsProvider);
      }
      notifier.closeTab(state.tabs.single.id);
      expect(container.read(tabsProvider).tabs, hasLength(1));
      expect(container.read(tabsProvider).tabs.single.kind, TabKind.newtab);
    });

    test('activatePage focuses an existing tab or creates one', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(tabsProvider.notifier);

      final a = notifier.activatePage(LumenSection.graph);
      notifier.activatePage(LumenSection.graph);
      expect(
        a,
        container.read(tabsProvider).activeId,
        reason: 'second call focuses the existing tab',
      );
      expect(container.read(tabsProvider).tabs, hasLength(2));
    });

    test('navigate pushes history; back/forward walk it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(tabsProvider.notifier);

      notifier.navigate('lumen://vault');
      var active = container.read(tabsProvider).active;
      expect(active!.page, LumenSection.vault);

      notifier.navigate('lumen://graph');
      active = container.read(tabsProvider).active;
      expect(active!.page, LumenSection.graph);

      expect(notifier.back(), isTrue);
      expect(container.read(tabsProvider).active!.page, LumenSection.vault);
      expect(notifier.forward(), isTrue);
      expect(container.read(tabsProvider).active!.page, LumenSection.graph);
      expect(notifier.forward(), isFalse);
    });
  });

  group('Shell', () {
    testWidgets('renders an activity bar and tab chrome', (tester) async {
      SharedPreferences.setMockInitialValues({'onboardingDone': true});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onboardingProvider.overrideWith(() => OnboardingNotifier(prefs)),
            tabsProvider.overrideWith(() => TabsNotifier(prefs)),
          ],
          child: const LumenApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LumenShell), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      for (final tooltip in [
        'Home tab — Ctrl+1',
        'Files tab — Ctrl+2',
        'Vault tab — Ctrl+3',
        'Graph tab — Ctrl+4',
        'OS Lab tab — Ctrl+5',
        'Console tab — Ctrl+6',
        'Projects tab — Ctrl+8',
        'Settings tab — Ctrl+7',
      ]) {
        expect(find.byTooltip(tooltip), findsOneWidget);
      }

      // Open Settings as a new tab via the activity bar (without native libs).
      await tester.tap(find.byTooltip('Settings tab — Ctrl+7'));
      await tester.pumpAndSettle();
      expect(find.text('Lumen', skipOffstage: false), findsWidgets);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('feature-gated sections disappear from the activity bar',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'onboardingDone': true,
        'featureProjects': false,
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onboardingProvider.overrideWith(() => OnboardingNotifier(prefs)),
            tabsProvider.overrideWith(() => TabsNotifier(prefs)),
            featuresProvider.overrideWith(() => FeaturesNotifier(prefs)),
          ],
          child: const LumenApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Projects tab — Ctrl+8'), findsNothing);
      expect(find.byTooltip('Settings tab — Ctrl+7'), findsOneWidget);
    });
  });

  group('Features', () {
    test('default state enables every feature', () {
      const features = FeaturesState();
      for (final feature in LumenFeature.values) {
        expect(features.enabled(feature), isTrue);
      }
    });

    test('toggles persist to shared preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [featuresProvider.overrideWith(() => FeaturesNotifier(prefs))],
      );
      addTearDown(container.dispose);

      expect(
        container.read(featuresProvider).enabled(LumenFeature.github),
        isTrue,
      );
      container.read(featuresProvider.notifier).set(LumenFeature.github, false);
      expect(
        container.read(featuresProvider).enabled(LumenFeature.github),
        isFalse,
      );
      expect(prefs.getBool(LumenFeature.github.key), isFalse);

      final second = ProviderContainer(
        overrides: [featuresProvider.overrideWith(() => FeaturesNotifier(prefs))],
      );
      addTearDown(second.dispose);
      expect(second.read(featuresProvider).enabled(LumenFeature.github), isFalse);
    });
  });

  group('Editor workspace', () {
    test('splits panes side by side, tracks dirty and saves', () async {
      final fs = _FakeFs({'/a.txt': 'hello', '/b.txt': 'world'});
      final container = ProviderContainer(
        overrides: [fsServiceProvider.overrideWithValue(fs)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(fileWorkspaceProvider('t1').notifier);

      await notifier.openFile('/a.txt');
      var state = container.read(fileWorkspaceProvider('t1'));
      expect(state.layout, isA<PaneLeaf>());
      expect(panesOf(state.layout!), hasLength(1));
      expect(panesOf(state.layout!).single.text, 'hello');
      final aId = panesOf(state.layout!).single.id;

      await notifier.openFile('/b.txt');
      state = container.read(fileWorkspaceProvider('t1'));
      expect(panesOf(state.layout!), hasLength(2));
      expect(state.layout, isA<PaneSplit>());
      expect((state.layout as PaneSplit).axis, Axis.horizontal);
      final bId = panesOf(state.layout!)
          .firstWhere((p) => p.path == '/b.txt')
          .id;

      notifier.syncDirty(aId, true);
      EditorPaneState paneOf(String id) => panesOf(
        container.read(fileWorkspaceProvider('t1')).layout!,
      ).firstWhere((p) => p.id == id);
      expect(paneOf(aId).dirty, isTrue);

      expect(await notifier.save(aId, 'edited'), isTrue);
      expect(fs.files['/a.txt'], 'edited');
      expect(paneOf(aId).dirty, isFalse);

      notifier.closePane(bId);
      state = container.read(fileWorkspaceProvider('t1'));
      expect(state.layout, isA<PaneLeaf>());
      expect(panesOf(state.layout!), hasLength(1));
    });

    test('adjustWeightToward shifts divider weight toward a pane', () {
      const left = PaneLeaf(pane: EditorPaneState(id: 'a', path: '/a'));
      const right = PaneLeaf(pane: EditorPaneState(id: 'b', path: '/b'));
      const split = PaneSplit(
        axis: Axis.horizontal,
        children: [left, right],
        weights: [0.5, 0.5],
      );

      final after = adjustWeightToward(split, 'b', 0.2) as PaneSplit;
      expect(after.weights[0], closeTo(0.7, 1e-9));
      expect(after.weights[1], closeTo(0.3, 1e-9));

      final clamped = adjustWeightToward(split, 'b', 0.9) as PaneSplit;
      expect(clamped.weights[1], closeTo(0.1, 1e-9));
      expect(clamped.weights[0] + clamped.weights[1], closeTo(1.0, 1e-9));
    });
  });

  group('Project model', () {
    test('round-trips tasks with ids, columns and dates', () {
      final task = ProjectTask(
        text: 'Ship it',
        id: 't1',
        column: 'doing',
        start: DateTime(2026, 8, 1),
        due: DateTime(2026, 8, 10),
      );
      final restored = ProjectTask.fromJson(task.toJson());
      expect(restored.text, 'Ship it');
      expect(restored.id, 't1');
      expect(restored.column, 'doing');
      expect(restored.start, DateTime(2026, 8, 1));
      expect(restored.due, DateTime(2026, 8, 10));
      expect(restored.done, isFalse);
    });

    test('legacy tasks default to the todo column', () {
      final legacy = ProjectTask.fromJson({'text': 'old'});
      expect(legacy.column, 'todo');
      expect(legacy.done, isFalse);
      expect(legacy.status, 'todo');
    });

    test('status follows the done flag, not a stale column', () {
      const done = ProjectTask(text: 'x', column: 'doing', done: true);
      expect(done.status, 'done');
      const stale = ProjectTask(text: 'x', column: 'done', done: false);
      expect(stale.status, 'todo');
    });

    test('progress derives from done tasks', () {
      const p = Project(
        id: 'p1',
        title: 'Demo',
        tasks: [
          ProjectTask(text: 'a', done: true),
          ProjectTask(text: 'b'),
          ProjectTask(text: 'c', done: true),
        ],
      );
      expect(p.done, 2);
      expect(p.total, 3);
      expect(p.progress, closeTo(2 / 3, 1e-9));
    });

    test('round-trips github issue numbers and repo links', () {
      const task = ProjectTask(text: 'Fix bug', id: 't', github: 42);
      final restored = ProjectTask.fromJson(task.toJson());
      expect(restored.github, 42);

      const linked = Project(id: 'p', title: 'Core', repo: 'user/core');
      final reloaded = Project.fromJson(linked.toJson());
      expect(reloaded.repo, 'user/core');
    });
  });

  group('GitHub service', () {
    test('fetches the user, filters forks and closes issues', () async {
      var patchedPath = '';
      final service = GithubService(
        client: MockClient((req) async {
          if (req.url.path == '/user') {
            return http.Response('{"login": "octo", "id": 1}', 200);
          }
          if (req.url.path == '/user/repos') {
            return http.Response(
              '[{"full_name": "octo/app", "fork": false},'
              ' {"full_name": "octo/forked", "fork": true}]',
              200,
            );
          }
          if (req.url.path == '/repos/octo/app/issues') {
            return http.Response(
              '[{"number": 7, "title": "First", "state": "open", "updated_at": "2026-01-02T00:00:00Z"},'
              ' {"number": 9, "title": "Second", "state": "open"}]',
              200,
            );
          }
          if (req.method == 'PATCH') {
            patchedPath = req.url.path;
            expect(req.body, contains('"closed"'));
            return http.Response('{"number": 7, "state": "closed"}', 200);
          }
          return http.Response('{}', 404);
        }),
      );

      final user = await service.me('token');
      expect(user.login, 'octo');

      final repos = await service.repos('token');
      expect(repos, hasLength(1));
      expect(repos.single.fullName, 'octo/app');

      final issues = await service.issues('token', 'octo/app');
      expect(issues, hasLength(2));
      expect(issues.first.number, 7);
      expect(issues.first.title, 'First');

      await service.setIssueState('token', 'octo/app', 7, closed: true);
      expect(patchedPath, '/repos/octo/app/issues/7');
    });

    test('bubbles up GitHub error messages', () async {
      final service = GithubService(
        client: MockClient(
          (_) async => http.Response('{"message": "Bad credentials"}', 401),
        ),
      );
      await expectLater(
        service.me('nope'),
        throwsA(isA<GithubException>()
            .having((e) => e.message, 'message', 'Bad credentials')),
      );
    });
  });

  group('WakaTime service', () {
    test('parses stats and uses basic auth with the key', () async {
      String? auth;
      final service = WakatimeService(
        client: MockClient((req) async {
          auth = req.headers['Authorization'];
          if (req.url.path.endsWith('/stats/last_7_days')) {
            return http.Response(
              '{"data": {"human_readable_total": "4 hrs 12 mins",'
              ' "human_readable_daily_average": "36 mins",'
              ' "total_seconds": 15120.0,'
              ' "languages": [{"name": "Dart", "percent": 62.5, "text": "2 hrs 38 mins"},'
              ' {"name": "Rust", "percent": 37.5, "text": "1 hr 34 mins"}]}}',
              200,
            );
          }
          return http.Response('{"data": {"display_name": "czar"}}', 200);
        }),
      );

      final user = await service.user('secret');
      expect(user, 'czar');
      expect(auth, 'Basic ${base64Encode(utf8.encode('secret:'))}');

      final stats = await service.stats('secret');
      expect(stats.humanTotal, '4 hrs 12 mins');
      expect(stats.languages.first.name, 'Dart');
      expect(stats.languages.first.percent, closeTo(62.5, 1e-9));
    });

    test('throws on a rejected API key', () async {
      final service = WakatimeService(
        client: MockClient(
          (_) async => http.Response('{"error":"x"}', 401),
        ),
      );
      await expectLater(
        service.user('bad'),
        throwsA(isA<WakatimeException>()),
      );
    });
  });
}
