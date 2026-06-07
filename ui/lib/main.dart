import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/new_entry_screen.dart';
import 'screens/setup_screen.dart';
import 'utils/theme.dart';
import 'l10n/app_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: LumenApp()));
}

class LumenApp extends ConsumerWidget {
  const LumenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(authProvider);
    final hasPassword = ref.read(authProvider.notifier).hasPassword();

    return MaterialApp(
      title: 'Lumen',
      theme: buildLumenTheme(),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('es'),
        Locale('fr'),
      ],
      home: unlocked
          ? const HomeScreen()
          : (!hasPassword ? const SetupScreen() : const LockScreen()),
      routes: {
        '/new': (context) => const NewEntryScreen(),
      },
    );
  }
}
