import 'package:flutter/material.dart';

const _primary = Color(0xFFBDC2FF);
const _onPrimary = Color(0xFF0013A0);
const _primaryContainer = Color(0xFF1E2EBD);
const _onPrimaryContainer = Color(0xFFA4ACFF);
const _secondary = Color(0xFFCCBEFF);
const _onSecondary = Color(0xFF332664);
const _secondaryContainer = Color(0xFF4A3D7C);
const _onSecondaryContainer = Color(0xFFBAABF3);
const _tertiary = Color(0xFFFFB4A1);
const _onTertiary = Color(0xFF611300);
const _tertiaryContainer = Color(0xFF851D00);
const _onTertiaryContainer = Color(0xFFFF967B);
const _error = Color(0xFFFFB4AB);
const _onError = Color(0xFF690005);
const _errorContainer = Color(0xFF93000A);
const _onErrorContainer = Color(0xFFFFDAD6);
const _background = Color(0xFF0B1326);
const _surface = Color(0xFF0B1326);
const _onSurface = Color(0xFFDAE2FD);
const _onSurfaceVariant = Color(0xFFC6C5D7);
const _outline = Color(0xFF8F8FA0);
const _outlineVariant = Color(0xFF454654);
const _inverseSurface = Color(0xFFDAE2FD);
const _inversePrimary = Color(0xFF3E4DD7);
const _surfaceContainerLow = Color(0xFF131B2E);
const _surfaceContainer = Color(0xFF171F33);
const _surfaceContainerHigh = Color(0xFF222A3D);
const _surfaceContainerHighest = Color(0xFF2D3449);

ThemeData buildLumenTheme() {
  final colorScheme = ColorScheme.dark(
    primary: _primary,
    onPrimary: _onPrimary,
    primaryContainer: _primaryContainer,
    onPrimaryContainer: _onPrimaryContainer,
    secondary: _secondary,
    onSecondary: _onSecondary,
    secondaryContainer: _secondaryContainer,
    onSecondaryContainer: _onSecondaryContainer,
    tertiary: _tertiary,
    onTertiary: _onTertiary,
    tertiaryContainer: _tertiaryContainer,
    onTertiaryContainer: _onTertiaryContainer,
    error: _error,
    onError: _onError,
    errorContainer: _errorContainer,
    onErrorContainer: _onErrorContainer,
    surface: _surface,
    onSurface: _onSurface,
    surfaceContainerLow: _surfaceContainerLow,
    surfaceContainer: _surfaceContainer,
    surfaceContainerHigh: _surfaceContainerHigh,
    surfaceContainerHighest: _surfaceContainerHighest,
    onSurfaceVariant: _onSurfaceVariant,
    outline: _outline,
    outlineVariant: _outlineVariant,
    inverseSurface: _inverseSurface,
    inversePrimary: _inversePrimary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: _background,
    fontFamily: 'Geist',
    appBarTheme: const AppBarTheme(
      backgroundColor: _surfaceContainer,
      foregroundColor: _onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Geist',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: _onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: _surfaceContainerHigh,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _outlineVariant, width: 1),
      ),
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: _primaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      labelType: NavigationRailLabelType.none,
      minWidth: 64,
      unselectedIconTheme: const IconThemeData(color: _onSurfaceVariant),
      selectedIconTheme: const IconThemeData(color: _primary),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: _primaryContainer,
      foregroundColor: _primary,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surfaceContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: _outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: _outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: _primary, width: 1),
      ),
      labelStyle: const TextStyle(color: _onSurfaceVariant),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _primaryContainer,
        foregroundColor: _primary,
        disabledBackgroundColor: _surfaceContainerHighest,
        disabledForegroundColor: _onSurfaceVariant,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _primaryContainer,
        foregroundColor: _primary,
        disabledBackgroundColor: _surfaceContainerHighest,
        disabledForegroundColor: _onSurfaceVariant,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _primary,
        disabledForegroundColor: _onSurfaceVariant,
        side: const BorderSide(color: _primary),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _primary,
        disabledForegroundColor: _onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: _surfaceContainer,
      labelStyle: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 12,
        color: _onSurfaceVariant,
      ),
      side: const BorderSide(color: _outlineVariant, width: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: _surface,
      selectedItemColor: _primary,
      unselectedItemColor: _onSurfaceVariant,
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Geist',
        fontSize: 48,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.02,
        color: _onSurface,
      ),
      headlineLarge: TextStyle(
        fontFamily: 'Geist',
        fontSize: 32,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.01,
        color: _onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Geist',
        fontSize: 24,
        fontWeight: FontWeight.w500,
        color: _onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'Geist',
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: _onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Geist',
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: _onSurface,
      ),
      labelMedium: TextStyle(
        fontFamily: 'Geist',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.02,
        color: _onSurface,
      ),
      bodySmall: TextStyle(
        fontFamily: 'Geist',
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: _onSurfaceVariant,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: _outlineVariant,
      thickness: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: _surfaceContainerHigh,
      contentTextStyle: const TextStyle(color: _onSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
}
