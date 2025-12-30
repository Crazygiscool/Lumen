import 'package:flutter/material.dart';
import 'core/lumen_core.dart';
import 'screens/journal_list_screen.dart';
import 'screens/new_entry_screen.dart';
import 'utils/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize backend once
  final lumen = LumenCore();

  runApp(LumenApp(lumen: lumen));
}

class LumenApp extends StatelessWidget {
  final LumenCore lumen;

  const LumenApp({super.key, required this.lumen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumen',
      theme: buildLumenTheme(),
      debugShowCheckedModeBanner: false,

      // Use named routes so your "New Entry" button works
      initialRoute: '/',
      routes: {
        '/': (context) => JournalListScreen(lumen: lumen),
        '/new': (context) => NewEntryScreen(lumen: lumen),
      },
    );
  }
}
