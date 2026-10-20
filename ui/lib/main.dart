import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shell/lumen_shell.dart';
import 'state/providers.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureSystemUi();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => SettingsNotifier(prefs)),
        pluginsProvider.overrideWith(() => PluginNotifier(prefs)),
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
    return MaterialApp(
      title: 'Lumen',
      debugShowCheckedModeBanner: false,
      theme: buildLumenTheme(dark: false),
      darkTheme: buildLumenTheme(dark: true),
      themeMode: resolveThemeMode(settings.themeSource),
      home: const LumenShell(),
    );
  }
}
