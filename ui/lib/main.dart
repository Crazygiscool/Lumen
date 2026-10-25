import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'ffi/plugin_service.dart';
import 'shell/lumen_shell.dart';
import 'state/providers.dart';
import 'theme/app_theme.dart';
import 'theme/lumen_colors.dart';
import 'theme/plugin_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureSystemUi();
  await windowManager.ensureInitialized();

  // Lumen draws its own title bar (lib/shell/top_bar.dart), so the native one
  // is hidden. Keep the size in sync with the GTK runner's default size.
  const windowOptions = WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(960, 640),
    center: true,
    backgroundColor: Colors.black,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  unawaited(
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    }),
  );

  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => SettingsNotifier(prefs)),
        pluginsProvider.overrideWith(() => PluginNotifier(prefs)),
        dashboardPrefsProvider.overrideWith(
          () => DashboardPrefsNotifier(prefs),
        ),
      ],
      child: const LumenApp(),
    ),
  );
}

class LumenApp extends ConsumerWidget {
  const LumenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final plugins = ref.watch(pluginsProvider);
    final List<PluginInfo> themePlugins = plugins.maybeWhen(
      data: (list) => list.all
          .where((p) => p.enabled && p.contributions['theme'] is Map)
          .toList(growable: false),
      orElse: () => const <PluginInfo>[],
    );
    PluginInfo? selectedTheme;
    if (settings.activeThemePluginId != null) {
      for (final plugin in themePlugins) {
        if (plugin.id == settings.activeThemePluginId) {
          selectedTheme = plugin;
          break;
        }
      }
    }
    if (selectedTheme == null && themePlugins.isNotEmpty) {
      selectedTheme = themePlugins.fold<PluginInfo?>(
        null,
        (best, plugin) =>
            best == null || plugin.priority > best.priority ? plugin : best,
      );
    }
    final tokens = selectedTheme == null
        ? null
        : PluginThemeTokens.fromMap(
            (selectedTheme.contributions['theme'] as Map)
                .cast<String, dynamic>(),
          );
    LumenColors.setActiveTheme(tokens);
    return MaterialApp(
      title: 'Lumen',
      debugShowCheckedModeBanner: false,
      theme: buildLumenTheme(dark: false, tokens: tokens),
      darkTheme: buildLumenTheme(dark: true, tokens: tokens),
      themeMode: resolveThemeMode(settings.themeSource),
      home: const LumenShell(),
    );
  }
}
