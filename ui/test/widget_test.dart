import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumen/main.dart';
import 'package:lumen/shell/lumen_shell.dart';
import 'package:lumen/shell/tabs/tab_model.dart';
import 'package:lumen/shell/tabs/tabs_provider.dart';
import 'package:lumen/state/providers.dart';
import 'package:lumen/theme/app_theme.dart';
import 'package:lumen/theme/lumen_colors.dart';

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
      expect(resolveInput('lumen://vault').kind, TabKind.lumen);
      expect(resolveInput('lumen://vault').page, LumenSection.vault);
      expect(resolveInput('lumen://oslab').page, LumenSection.osLab);
      expect(resolveInput('lumen://lab').page, LumenSection.osLab);
      expect(resolveInput('lumen://graph').page, LumenSection.graph);
      expect(resolveInput('lumen:console').page, LumenSection.console);
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
  });

  group('TabsNotifier', () {
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
    testWidgets('renders a navigation rail and tab chrome', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: LumenApp()));
      await tester.pumpAndSettle();

      expect(find.byType(LumenShell), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
      for (final label in [
        'Files',
        'Vault',
        'Graph',
        'OS Lab',
        'Console',
        'Settings',
      ]) {
        expect(find.text(label, skipOffstage: false), findsWidgets);
      }

      // Open Settings as a new tab via the rail (without native libs).
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byIcon(Icons.settings_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lumen', skipOffstage: false), findsWidgets);
      expect(find.text('Ctrl+P', skipOffstage: false), findsOneWidget);
    });
  });
}
