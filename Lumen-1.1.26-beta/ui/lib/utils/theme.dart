import 'package:flutter/material.dart';

ThemeData buildLumenTheme() {
  return ThemeData(
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
    useMaterial3: true,
  );
}
