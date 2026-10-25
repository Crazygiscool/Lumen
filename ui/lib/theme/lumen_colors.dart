import 'package:flutter/material.dart';

/// Single source of truth for Lumen's palette and design tokens.
///
/// "Midnight Glass": a pitch-black dark base lit by soft indigo/violet glows,
/// with a matching "Daylight Glass" variant for systems that prefer light.
/// Chrome and floating surfaces are translucent glass with hairline borders;
/// interactive accent (primary) is reserved for interactive states only.
///
/// Screens should resolve tokens through [LumenColors.of] so they follow the
/// active brightness. Static constants mirror the dark palette for places that
/// must stay dark regardless of theme (code editor surfaces, ambient glows).
abstract final class LumenColors {
  // -------------------------------------------------------------------------
  // Ambient glow (painted behind everything, very low opacity)
  // -------------------------------------------------------------------------
  static const glowIndigo = Color(0xFF3D4FFF);
  static const glowViolet = Color(0xFF7F5AFF);
  static const glowDeep = Color(0xFF000000);

  // --- Pitch-black base (dark) ---
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF000000);

  // --- Glass surface tokens (alpha components) ---
  static const glass = Color(0x99000000);
  static const glassStrong = Color(0xCC000000);
  static const glassFloat = Color(0xF2000000);
  static const glassHover = Color(0x14FFFFFF);
  static const glassSelected = Color(0x273D4FFF);

  // Legacy surface names kept for the light palette mapping.
  static const surfaceLow = Color(0xB3000000);
  static const surfaceContainer = Color(0xD9000000);
  static const surfaceHigh = Color(0xEF000000);
  static const surfaceHighest = Color(0xFF000000);

  static const hairline = Color(0x14FFFFFF);
  static const hairlineStrong = Color(0x26FFFFFF);

  // --- Text & outlines ---
  static const onSurface = Color(0xFFE6E9F5);
  static const onSurfaceVariant = Color(0xFF9BA1B8);
  static const outline = Color(0xFF6B7288);
  static const outlineVariant = Color(0x558B90A5);

  // --- Accent (primary) — default indigo, overridden by GTK accent ---
  static const primary = Color(0xFFBDC2FF);
  static const onPrimary = Color(0xFF0013A0);
  static const primaryContainer = Color(0xFF1E2EBD);
  static const onPrimaryContainer = Color(0xFFA4ACFF);

  static const secondary = Color(0xFFCCBEFF);
  static const onSecondary = Color(0xFF332664);
  static const secondaryContainer = Color(0xFF4A3D7C);
  static const onSecondaryContainer = Color(0xFFBAABF3);

  static const tertiary = Color(0xFFFFB4A1);
  static const tertiaryContainer = Color(0xFF851D00);

  // --- Functional palette (colorblind-safe) ---
  static const error = Color(0xFFFFB4AB);
  static const onError = Color(0xFF690005);
  static const errorContainer = Color(0xFF93000A);
  static const success = Color(0xFF7DD8A4);
  static const warning = Color(0xFFF5C877);
  static const info = Color(0xFF82C7F5);

  static const radiusSm = 4.0;
  static const radiusMd = 8.0;
  static const radiusLg = 12.0;
  static const radiusXl = 18.0;

  /// Resolves the palette for the currently active brightness.
  static dynamic _activePluginTheme;

  static void setActiveTheme(dynamic tokens) {
    _activePluginTheme = tokens;
  }

  static LumenPalette of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? lumenPaletteDark : lumenPaletteLight;
    final tokens = _activePluginTheme;
    if (tokens == null) return base;
    return tokens.applyTo(base) as LumenPalette;
  }
}

/// Runtime token set resolved from the active brightness.
@immutable
class LumenPalette {
  const LumenPalette({
    required this.background,
    required this.glowIndigo,
    required this.glowViolet,
    required this.glowDeep,
    required this.glass,
    required this.glassStrong,
    required this.glassFloat,
    required this.glassHover,
    required this.glassSelected,
    required this.surfaceLow,
    required this.surfaceContainer,
    required this.surfaceHigh,
    required this.surfaceHighest,
    required this.hairline,
    required this.hairlineStrong,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.tertiaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.info,
    required this.success,
    required this.warning,
  });

  final Color background;
  final Color glowIndigo;
  final Color glowViolet;
  final Color glowDeep;
  final Color glass;
  final Color glassStrong;
  final Color glassFloat;
  final Color glassHover;
  final Color glassSelected;
  final Color surfaceLow;
  final Color surfaceContainer;
  final Color surfaceHigh;
  final Color surfaceHighest;
  final Color hairline;
  final Color hairlineStrong;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color tertiaryContainer;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color info;
  final Color success;
  final Color warning;

  LumenPalette copyWith({
    Color? background,
    Color? glowIndigo,
    Color? glowViolet,
    Color? glowDeep,
    Color? glass,
    Color? glassStrong,
    Color? glassFloat,
    Color? glassHover,
    Color? glassSelected,
    Color? surfaceLow,
    Color? surfaceContainer,
    Color? surfaceHigh,
    Color? surfaceHighest,
    Color? hairline,
    Color? hairlineStrong,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? outline,
    Color? outlineVariant,
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? secondary,
    Color? onSecondary,
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? tertiary,
    Color? tertiaryContainer,
    Color? error,
    Color? onError,
    Color? errorContainer,
    Color? info,
    Color? success,
    Color? warning,
  }) => LumenPalette(
    background: background ?? this.background,
    glowIndigo: glowIndigo ?? this.glowIndigo,
    glowViolet: glowViolet ?? this.glowViolet,
    glowDeep: glowDeep ?? this.glowDeep,
    glass: glass ?? this.glass,
    glassStrong: glassStrong ?? this.glassStrong,
    glassFloat: glassFloat ?? this.glassFloat,
    glassHover: glassHover ?? this.glassHover,
    glassSelected: glassSelected ?? this.glassSelected,
    surfaceLow: surfaceLow ?? this.surfaceLow,
    surfaceContainer: surfaceContainer ?? this.surfaceContainer,
    surfaceHigh: surfaceHigh ?? this.surfaceHigh,
    surfaceHighest: surfaceHighest ?? this.surfaceHighest,
    hairline: hairline ?? this.hairline,
    hairlineStrong: hairlineStrong ?? this.hairlineStrong,
    onSurface: onSurface ?? this.onSurface,
    onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
    outline: outline ?? this.outline,
    outlineVariant: outlineVariant ?? this.outlineVariant,
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    primaryContainer: primaryContainer ?? this.primaryContainer,
    onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
    secondary: secondary ?? this.secondary,
    onSecondary: onSecondary ?? this.onSecondary,
    secondaryContainer: secondaryContainer ?? this.secondaryContainer,
    onSecondaryContainer: onSecondaryContainer ?? this.onSecondaryContainer,
    tertiary: tertiary ?? this.tertiary,
    tertiaryContainer: tertiaryContainer ?? this.tertiaryContainer,
    error: error ?? this.error,
    onError: onError ?? this.onError,
    errorContainer: errorContainer ?? this.errorContainer,
    info: info ?? this.info,
    success: success ?? this.success,
    warning: warning ?? this.warning,
  );
}

const lumenPaletteDark = LumenPalette(
  background: LumenColors.background,
  glowIndigo: LumenColors.glowIndigo,
  glowViolet: LumenColors.glowViolet,
  glowDeep: LumenColors.glowDeep,
  glass: LumenColors.glass,
  glassStrong: LumenColors.glassStrong,
  glassFloat: LumenColors.glassFloat,
  glassHover: LumenColors.glassHover,
  glassSelected: LumenColors.glassSelected,
  surfaceLow: LumenColors.surfaceLow,
  surfaceContainer: LumenColors.surfaceContainer,
  surfaceHigh: LumenColors.surfaceHigh,
  surfaceHighest: LumenColors.surfaceHighest,
  hairline: LumenColors.hairline,
  hairlineStrong: LumenColors.hairlineStrong,
  onSurface: LumenColors.onSurface,
  onSurfaceVariant: LumenColors.onSurfaceVariant,
  outline: LumenColors.outline,
  outlineVariant: LumenColors.outlineVariant,
  primary: LumenColors.primary,
  onPrimary: LumenColors.onPrimary,
  primaryContainer: LumenColors.primaryContainer,
  onPrimaryContainer: LumenColors.onPrimaryContainer,
  secondary: LumenColors.secondary,
  onSecondary: LumenColors.onSecondary,
  secondaryContainer: LumenColors.secondaryContainer,
  onSecondaryContainer: LumenColors.onSecondaryContainer,
  tertiary: LumenColors.tertiary,
  tertiaryContainer: LumenColors.tertiaryContainer,
  error: LumenColors.error,
  onError: LumenColors.onError,
  errorContainer: LumenColors.errorContainer,
  info: LumenColors.info,
  success: LumenColors.success,
  warning: LumenColors.warning,
);

const lumenPaletteLight = LumenPalette(
  background: Color(0xFFF4F5FA),
  glowIndigo: Color(0xFFB9C6FF),
  glowViolet: Color(0xFFE2D6FF),
  glowDeep: Color(0xFFE9EAF7),
  glass: Color(0xE6FFFFFF),
  glassStrong: Color(0xF2FFFFFF),
  glassFloat: Color(0xFAFFFFFF),
  glassHover: Color(0x0E000000),
  glassSelected: Color(0x263E4DD7),
  surfaceLow: Color(0xE6FFFFFF),
  surfaceContainer: Color(0xEFFFFFFF),
  surfaceHigh: Color(0xFFFFFFFF),
  surfaceHighest: Color(0xFFE7E9F3),
  hairline: Color(0x12000000),
  hairlineStrong: Color(0x26000000),
  onSurface: Color(0xFF15171F),
  onSurfaceVariant: Color(0xFF494E63),
  outline: Color(0xFF757A8D),
  outlineVariant: Color(0x33848A9F),
  primary: Color(0xFF3E4DD7),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFDDE0FF),
  onPrimaryContainer: Color(0xFF0F1FB2),
  secondary: Color(0xFF6750A4),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE8DEF8),
  onSecondaryContainer: Color(0xFF4F378B),
  tertiary: Color(0xFF006B5F),
  tertiaryContainer: Color(0xFF9ADFD2),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  info: Color(0xFF00639B),
  success: Color(0xFF1B7F4D),
  warning: Color(0xFF7A5C00),
);
