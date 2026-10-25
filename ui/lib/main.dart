import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'ffi/plugin_service.dart';
import 'shell/lumen_shell.dart';
import 'state/providers.dart';
import 'theme/app_icons.dart';
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
    ref.watch(pluginFontsProvider);
    final activeThemeId =
        settings.activeThemeId ?? settings.activeThemePluginId;

    final List<PluginInfo> themePlugins = plugins.maybeWhen(
      data: (list) => list.all
          .where((p) => p.enabled && p.contributions['theme'] is Map)
          .toList(growable: true),
      orElse: () => const <PluginInfo>[],
    );

    PluginInfo? selectedThemePlugin;
    if (activeThemeId != null) {
      for (final plugin in themePlugins) {
        if (plugin.id == activeThemeId) {
          selectedThemePlugin = plugin;
          break;
        }
      }
    }

    final selectedBuiltinTheme = builtinThemeById(activeThemeId);
    final tokens = selectedBuiltinTheme?.tokens ??
        (selectedThemePlugin == null
            ? null
            : PluginThemeTokens.fromMap(
                (selectedThemePlugin.contributions['theme'] as Map)
                    .cast<String, dynamic>(),
              ));
    final effectiveTokens = settings.activeFontFamily == null
        ? tokens
        : (tokens ?? const PluginThemeTokens())
            .copyWith(fontFamily: settings.activeFontFamily);

    final iconSource = plugins.maybeWhen(
      data: (list) => list.all
          .where((p) => p.enabled && p.contributions['icons'] is Map)
          .toList(growable: true),
      orElse: () => const <PluginInfo>[],
    );
    final iconPlugins = List<PluginInfo>.from(iconSource)
      ..sort((a, b) => b.priority.compareTo(a.priority));
    PluginInfo? selectedIconPlugin;
    if (settings.activeIconPackId != null) {
      for (final plugin in iconPlugins) {
        if (plugin.id == settings.activeIconPackId) {
          selectedIconPlugin = plugin;
          break;
        }
      }
    }
    selectedIconPlugin ??= selectedThemePlugin != null &&
            selectedThemePlugin.contributions['icons'] is Map
        ? selectedThemePlugin
        : (iconPlugins.isEmpty ? null : iconPlugins.first);
    AppIcons.setActivePack(
      selectedIconPlugin == null
          ? null
          : (selectedIconPlugin.contributions['icons'] as Map)
              .cast<String, dynamic>(),
    );
    LumenColors.setActiveTheme(effectiveTokens);
    return MaterialApp(
      title: 'Lumen',
      debugShowCheckedModeBanner: false,
      theme: buildLumenTheme(dark: false, tokens: effectiveTokens),
      darkTheme: buildLumenTheme(dark: true, tokens: effectiveTokens),
      themeMode: resolveThemeMode(settings.themeSource),
      home: const LumenShell(),
    );
  }
}
