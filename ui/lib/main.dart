import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shell/command_palette.dart';
import 'shell/lumen_shell.dart';
import 'shell/tabs/tabs_provider.dart';
import 'shell/web/ad_block_service.dart';
import 'state/providers.dart';
import 'theme/app_theme.dart';
import 'theme/glass.dart';
import 'theme/lumen_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureSystemUi();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => SettingsNotifier(prefs)),
        tabsProvider.overrideWith(() => TabsNotifier(prefs)),
        adBlockProvider.overrideWith(() => AdBlockNotifier(prefs)),
        onboardingProvider.overrideWith(() => OnboardingNotifier(prefs)),
        featuresProvider.overrideWith(() => FeaturesNotifier(prefs)),
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
    final palette = ref.watch(commandPaletteProvider);
    final gtk = ref.watch(gtkThemeProvider).value;
    final themeMode = resolveThemeMode(settings.themeSource, gtk);
    final accentName = settings.matchGtkAccent ? gtk?.accentName : null;

    return MaterialApp(
      title: 'Lumen',
      debugShowCheckedModeBanner: false,
      theme: buildLumenTheme(
        dark: false,
        accentPrimary: gtkAccentPrimary(accentName, dark: false),
      ),
      darkTheme: buildLumenTheme(
        dark: true,
        accentPrimary: gtkAccentPrimary(accentName, dark: true),
      ),
      themeMode: themeMode,
      home: AmbientBackground(
        child: Stack(
          children: [
            const LumenShell(),
            if (palette.visible) const CommandPalette(),
          ],
        ),
      ),
    );
  }
}
