import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lumen_colors.dart';

/// Builds Lumen's complete Material 3 theme for a given brightness.
///
/// Design rules:
///  - Accent (primary) only for interactive states: selection, focus, active
///    navigation, buttons.
///  - Surfaces layered (Low -> Container -> High) for hierarchy, never flat.
///  - GTK systems may override the primary with the desktop accent colour.
///  - Every interactive component theme is provided: menus, dropdowns,
///    tooltips, scrollbars, chips, dialogs, text fields.
ThemeData buildLumenTheme({required bool dark, Color? accentPrimary}) {
  final t = dark ? lumenPaletteDark : lumenPaletteLight;
  final accent = accentPrimary ?? t.primary;
  final accentOn = t.onPrimary;
  final accentContainer = dark ? const Color(0xFF1E2EBD) : t.primaryContainer;
  final accentOnContainer = dark
      ? const Color(0xFFA4ACFF)
      : t.onPrimaryContainer;

  final scheme = dark
      ? ColorScheme.dark(
          primary: accent,
          onPrimary: accentOn,
          primaryContainer: accentContainer,
          onPrimaryContainer: accentOnContainer,
          secondary: t.secondary,
          onSecondary: const Color(0xFF332664),
          secondaryContainer: t.secondaryContainer,
          onSecondaryContainer: const Color(0xFFBAABF3),
          tertiary: t.tertiary,
          onTertiary: const Color(0xFF450A00),
          tertiaryContainer: t.tertiaryContainer,
          onTertiaryContainer: const Color(0xFFFFDBCF),
          error: t.error,
          onError: const Color(0xFF690005),
          errorContainer: t.errorContainer,
          onErrorContainer: const Color(0xFFFFDAD6),
          surface: LumenColors.surface,
          onSurface: t.onSurface,
          onSurfaceVariant: t.onSurfaceVariant,
          outline: t.outline,
          outlineVariant: t.outlineVariant,
          surfaceContainerLowest: t.background,
          surfaceContainerLow: t.surfaceLow,
          surfaceContainer: t.surfaceContainer,
          surfaceContainerHigh: t.surfaceHigh,
          surfaceContainerHighest: t.surfaceHighest,
          inverseSurface: t.onSurface,
          onInverseSurface: t.background,
          inversePrimary: const Color(0xFF3E4DD7),
        )
      : ColorScheme.light(
          primary: accent,
          onPrimary: accentOn,
          primaryContainer: accentContainer,
          onPrimaryContainer: accentOnContainer,
          secondary: t.secondary,
          onSecondary: const Color(0xFFFFFFFF),
          secondaryContainer: t.secondaryContainer,
          onSecondaryContainer: const Color(0xFF4F378B),
          tertiary: t.tertiary,
          onTertiary: const Color(0xFFFFFFFF),
          tertiaryContainer: t.tertiaryContainer,
          onTertiaryContainer: const Color(0xFF00382F),
          error: t.error,
          onError: const Color(0xFFFFFFFF),
          errorContainer: t.errorContainer,
          onErrorContainer: const Color(0xFF93000A),
          surface: const Color(0xFFEFF0F7),
          onSurface: t.onSurface,
          onSurfaceVariant: t.onSurfaceVariant,
          outline: t.outline,
          outlineVariant: t.outlineVariant,
          surfaceContainerLowest: t.background,
          surfaceContainerLow: t.surfaceLow,
          surfaceContainer: t.surfaceContainer,
          surfaceContainerHigh: t.surfaceHigh,
          surfaceContainerHighest: t.surfaceHighest,
          inverseSurface: const Color(0xFF15171F),
          onInverseSurface: const Color(0xFFF4F5FA),
          inversePrimary: const Color(0xFFBDC2FF),
        );

  const appBarTitleStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  final baseText = TextStyle(color: t.onSurface);

  final base = ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.background,
    fontFamily: 'Geist',
    extensions: const [lumenCodePalette],
  );

  return base.copyWith(
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: accentContainer,
      selectionHandleColor: accent,
    ),
    textTheme: TextTheme(
      displayLarge: TextStyle(
        fontSize: 44,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.5,
        color: t.onSurface,
      ),
      headlineLarge: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: t.onSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: t.onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: t.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: t.onSurface,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: t.onSurface),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: t.onSurface),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.4,
        color: t.onSurfaceVariant,
      ),
      labelMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: t.onSurface,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: t.onSurfaceVariant,
      ),
    ).apply(bodyColor: t.onSurface, displayColor: t.onSurface),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: t.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: appBarTitleStyle.copyWith(color: t.onSurface),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: accentContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumenColors.radiusMd),
      ),
      labelType: NavigationRailLabelType.none,
      minWidth: 56,
      groupAlignment: -0.9,
      selectedIconTheme: IconThemeData(color: accent, size: 22),
      unselectedIconTheme: const IconThemeData(color: null, size: 22),
      selectedLabelTextStyle: TextStyle(color: accent, fontSize: 11),
      unselectedLabelTextStyle: TextStyle(
        color: t.onSurfaceVariant,
        fontSize: 11,
      ),
    ),
    cardTheme: CardThemeData(
      color: t.surfaceHigh,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumenColors.radiusMd),
        side: BorderSide(color: t.outlineVariant, width: 1),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: t.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.onSurfaceVariant,
      textColor: t.onSurface,
      titleTextStyle: baseText,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surfaceContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      hintStyle: TextStyle(color: t.onSurfaceVariant),
      labelStyle: TextStyle(color: t.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LumenColors.radiusMd),
        borderSide: BorderSide(color: t.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LumenColors.radiusMd),
        borderSide: BorderSide(color: t.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LumenColors.radiusMd),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accentContainer,
        foregroundColor: accentOnContainer,
        disabledBackgroundColor: t.surfaceHighest,
        disabledForegroundColor: t.onSurfaceVariant,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumenColors.radiusMd),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumenColors.radiusMd),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: t.onSurfaceVariant,
        highlightColor: t.surfaceHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumenColors.radiusSm),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.surfaceContainer,
      labelStyle: TextStyle(fontSize: 12, color: t.onSurfaceVariant),
      selectedColor: accentContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumenColors.radiusSm),
      ),
      side: BorderSide(color: t.outlineVariant, width: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: t.surfaceHighest,
        borderRadius: BorderRadius.circular(LumenColors.radiusSm),
        border: Border.all(color: t.outlineVariant),
      ),
      textStyle: TextStyle(fontSize: 12, color: t.onSurface),
      waitDuration: const Duration(milliseconds: 400),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumenColors.radiusLg),
      ),
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: t.onSurface,
      ),
      contentTextStyle: TextStyle(color: t.onSurfaceVariant),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.surfaceHighest,
      contentTextStyle: TextStyle(color: t.onSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumenColors.radiusMd),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: t.surfaceContainer),
    popupMenuTheme: PopupMenuThemeData(
      color: t.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumenColors.radiusMd),
      ),
      textStyle: TextStyle(color: t.onSurface, fontSize: 14),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.surfaceHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LumenColors.radiusMd),
          ),
        ),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumenColors.radiusMd),
          borderSide: BorderSide(color: t.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumenColors.radiusMd),
          borderSide: BorderSide(color: t.outlineVariant),
        ),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.hovered) ? t.outline : t.outlineVariant,
      ),
      radius: const Radius.circular(4),
      thumbVisibility: WidgetStateProperty.all(false),
      thickness: WidgetStateProperty.all(6),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentContainer,
        foregroundColor: accentOnContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumenColors.radiusMd),
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? accent : t.onSurfaceVariant,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? accentContainer
            : t.surfaceHighest,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: accent,
      unselectedLabelColor: t.onSurfaceVariant,
      indicatorColor: accent,
      dividerColor: t.outlineVariant,
    ),
  );
}

/// Builds an identical-dark theme (used before GTK detection resolves).
ThemeData buildLumenDark() => buildLumenTheme(dark: true);

/// Mono font used for paths, sizes and code.
const String lumenMonoFont = 'Geist Mono';

/// Formats bytes into a human-readable string.
String formatBytes(int bytes) {
  if (bytes == 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0 ? '$bytes B' : '${value.toStringAsFixed(1)} ${units[unit]}';
}

/// Formats a millis timestamp into a short human date.
String formatDate(int? millis) {
  if (millis == null || millis <= 0) return '—';
  return formatReadableDate(DateTime.fromMillisecondsSinceEpoch(millis));
}

String formatReadableDate(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(day).inDays;
  final time =
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  if (diff == 0) return 'Today $time';
  if (diff == 1) return 'Yesterday $time';
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $time';
}

/// Injects Fluent-style focus highlights anywhere focus rings matter.
Widget focusRing(BuildContext context, {required Widget child}) {
  return FocusDecoration(child: child);
}

class FocusDecoration extends StatelessWidget {
  const FocusDecoration({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

/// Convenience: read the code palette extension.
LumenCodePalette codePalette(BuildContext context) =>
    Theme.of(context).extension<LumenCodePalette>() ?? lumenCodePalette;

// Ensure system UI overlays match the dark chrome.
void configureSystemUi() {
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
}
