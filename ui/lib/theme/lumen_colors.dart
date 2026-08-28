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
  static const glowDeep = Color(0xFF16083A);

  // --- Pitch-black base (dark) ---
  static const background = Color(0xFF04050A);
  static const surface = Color(0xFF080A12);

  // --- Glass surface tokens (alpha components) ---
  static const glass = Color(0x990B0E1A);
  static const glassStrong = Color(0xCC0B0E1A);
  static const glassFloat = Color(0xF20D1120);
  static const glassHover = Color(0x14FFFFFF);
  static const glassSelected = Color(0x273D4FFF);

  // Legacy surface names kept for the light palette mapping.
  static const surfaceLow = Color(0xB30B0E1A);
  static const surfaceContainer = Color(0xD90B0E1A);
  static const surfaceHigh = Color(0xEF101420);
  static const surfaceHighest = Color(0xFF1A2031);

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

  // --- Code syntax palette (stays dark in both modes: self-contained panel) ---
  static const codeBackground = Color(0xFF06080F);
  static const codeKeyword = Color(0xFFC792EA);
  static const codeString = Color(0xFF9ECE6A);
  static const codeComment = Color(0xFF6C7486);
  static const codeFunction = Color(0xFF82AAFF);
  static const codeType = Color(0xFFE1B56A);
  static const codeNumber = Color(0xFFF7768E);
  static const codePunct = Color(0xFFB6BBD0);

  static const radiusSm = 4.0;
  static const radiusMd = 8.0;
  static const radiusLg = 12.0;
  static const radiusXl = 18.0;

  /// Resolves the palette for the currently active brightness.
  static LumenPalette of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? lumenPaletteDark : lumenPaletteLight;
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

/// Maps a GNOME accent-colour name to Lumen's primary for the given brightness.
Color? gtkAccentPrimary(String? name, {required bool dark}) {
  final pair = name == null
      ? null
      : switch (name) {
          'blue' => (
            dark: const Color(0xFF8DB3F5),
            light: const Color(0xFF205FBF),
          ),
          'teal' => (
            dark: const Color(0xFF7FD8DE),
            light: const Color(0xFF00696E),
          ),
          'green' => (
            dark: const Color(0xFF8FE3B0),
            light: const Color(0xFF1E7A45),
          ),
          'yellow' => (
            dark: const Color(0xFFF7DF8A),
            light: const Color(0xFF8A6400),
          ),
          'purple' => (
            dark: const Color(0xFFC79BF5),
            light: const Color(0xFF6E3BB0),
          ),
          'red' => (
            dark: const Color(0xFFFF9D96),
            light: const Color(0xFFC13929),
          ),
          'orange' => (
            dark: const Color(0xFFFFB97A),
            light: const Color(0xFF9A4D00),
          ),
          'slate' => (
            dark: const Color(0xFFC7C9D4),
            light: const Color(0xFF6B6F7A),
          ),
          'pink' => (
            dark: const Color(0xFFF7A2F2),
            light: const Color(0xFF9C3399),
          ),
          _ => null,
        };
  return pair == null ? null : (dark ? pair.dark : pair.light);
}

/// The [ThemeMode] matching a GTK `color-scheme` value.
ThemeMode? gtkSchemeToMode(String? scheme) {
  switch (scheme) {
    case 'prefer-dark':
    case 'default':
      return ThemeMode.dark;
    case 'prefer-light':
      return ThemeMode.light;
    default:
      return null;
  }
}

/// Full syntax-highlight palette carried through the theme.
@immutable
class LumenCodePalette extends ThemeExtension<LumenCodePalette> {
  const LumenCodePalette({
    required this.background,
    required this.keyword,
    required this.string,
    required this.comment,
    required this.function,
    required this.typeName,
    required this.number,
    required this.punctuation,
  });

  final Color background;
  final Color keyword;
  final Color string;
  final Color comment;
  final Color function;
  final Color typeName;
  final Color number;
  final Color punctuation;

  @override
  LumenCodePalette copyWith({
    Color? background,
    Color? keyword,
    Color? string,
    Color? comment,
    Color? function,
    Color? typeName,
    Color? number,
    Color? punctuation,
  }) {
    return LumenCodePalette(
      background: background ?? this.background,
      keyword: keyword ?? this.keyword,
      string: string ?? this.string,
      comment: comment ?? this.comment,
      function: function ?? this.function,
      typeName: typeName ?? this.typeName,
      number: number ?? this.number,
      punctuation: punctuation ?? this.punctuation,
    );
  }

  @override
  LumenCodePalette lerp(covariant LumenCodePalette? other, double t) {
    if (other == null) return this;
    return LumenCodePalette(
      background: Color.lerp(background, other.background, t)!,
      keyword: Color.lerp(keyword, other.keyword, t)!,
      string: Color.lerp(string, other.string, t)!,
      comment: Color.lerp(comment, other.comment, t)!,
      function: Color.lerp(function, other.function, t)!,
      typeName: Color.lerp(typeName, other.typeName, t)!,
      number: Color.lerp(number, other.number, t)!,
      punctuation: Color.lerp(punctuation, other.punctuation, t)!,
    );
  }
}

const lumenCodePalette = LumenCodePalette(
  background: LumenColors.codeBackground,
  keyword: LumenColors.codeKeyword,
  string: LumenColors.codeString,
  comment: LumenColors.codeComment,
  function: LumenColors.codeFunction,
  typeName: LumenColors.codeType,
  number: LumenColors.codeNumber,
  punctuation: LumenColors.codePunct,
);
