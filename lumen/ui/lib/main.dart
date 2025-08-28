// Flutter app entrypoint for Lumen
import 'package:flutter/material.dart';
import 'screens/journal_list_screen.dart';
import 'screens/entry_view_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/plugin_config_screen.dart';

void main() {
  runApp(const LumenApp());
}

class LumenApp extends StatelessWidget {
  const LumenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumen',
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFFFFD600),
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.yellow,
          accentColor: Colors.orangeAccent,
        ).copyWith(
          secondary: Colors.orangeAccent,
        ),
        scaffoldBackgroundColor: const Color(0xFFFFF8E1),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFD600),
          foregroundColor: Colors.deepOrange,
          elevation: 4,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFFFD600),
          foregroundColor: Colors.white,
          elevation: 8,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: Colors.deepOrange,
            fontWeight: FontWeight.bold,
            fontSize: 28,
            shadows: [Shadow(color: Colors.orangeAccent, blurRadius: 8)],
          ),
          bodyMedium: TextStyle(
            color: Colors.brown,
            fontSize: 16,
          ),
        ),
        useMaterial3: true, // Modern Material Design
      ),
      home: const JournalListScreen(),
      debugShowCheckedModeBanner: false,
      // Set the app icon for supported platforms
      // For desktop, use windowManager or similar package for icon
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = <Widget>[
    JournalListScreen(),
    SettingsScreen(),
    PluginConfigScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.book),
            label: 'Journal',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.extension),
            label: 'Plugins',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
