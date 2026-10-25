import 'package:flutter/material.dart';

import '../ffi/plugin_service.dart';
import 'lumen_colors.dart';

/// Normalized theme overrides contributed by plugins. Missing fields inherit
/// from Lumen's built-in palette, so plugins only need to set the tokens they
/// care about.
@immutable
class PluginThemeTokens {
  const PluginThemeTokens({
    this.primary,
    this.onPrimary,
    this.primaryContainer,
    this.onPrimaryContainer,
    this.secondary,
    this.background,
    this.surfaceLow,
    this.surfaceContainer,
    this.surfaceHigh,
    this.surfaceHighest,
    this.onSurface,
    this.onSurfaceVariant,
    this.outline,
    this.outlineVariant,
    this.error,
    this.success,
    this.warning,
    this.info,
    this.fontFamily,
    this.radiusMultiplier,
  });

  final Color? primary;
  final Color? onPrimary;
  final Color? primaryContainer;
  final Color? onPrimaryContainer;
  final Color? secondary;
  final Color? background;
  final Color? surfaceLow;
  final Color? surfaceContainer;
  final Color? surfaceHigh;
  final Color? surfaceHighest;
  final Color? onSurface;
  final Color? onSurfaceVariant;
  final Color? outline;
  final Color? outlineVariant;
  final Color? error;
  final Color? success;
  final Color? warning;
  final Color? info;
  final String? fontFamily;
  final double? radiusMultiplier;

  PluginThemeTokens copyWith({
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? secondary,
    Color? background,
    Color? surfaceLow,
    Color? surfaceContainer,
    Color? surfaceHigh,
    Color? surfaceHighest,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? outline,
    Color? outlineVariant,
    Color? error,
    Color? success,
    Color? warning,
    Color? info,
    String? fontFamily,
    double? radiusMultiplier,
  }) => PluginThemeTokens(
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    primaryContainer: primaryContainer ?? this.primaryContainer,
    onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
    secondary: secondary ?? this.secondary,
    background: background ?? this.background,
    surfaceLow: surfaceLow ?? this.surfaceLow,
    surfaceContainer: surfaceContainer ?? this.surfaceContainer,
    surfaceHigh: surfaceHigh ?? this.surfaceHigh,
    surfaceHighest: surfaceHighest ?? this.surfaceHighest,
    onSurface: onSurface ?? this.onSurface,
    onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
    outline: outline ?? this.outline,
    outlineVariant: outlineVariant ?? this.outlineVariant,
    error: error ?? this.error,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    info: info ?? this.info,
    fontFamily: fontFamily ?? this.fontFamily,
    radiusMultiplier: radiusMultiplier ?? this.radiusMultiplier,
  );

  static Color? _color(Object? value) {
    if (value is String && value.startsWith('#')) {
      final hex = value.substring(1);
      if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
      if (hex.length == 8) return Color(int.parse(hex, radix: 16));
    }
    if (value is int) return Color(value);
    return null;
  }

  factory PluginThemeTokens.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PluginThemeTokens();
    return PluginThemeTokens(
      primary: _color(map['primary']),
      onPrimary: _color(map['onPrimary']),
      primaryContainer: _color(map['primaryContainer']),
      onPrimaryContainer: _color(map['onPrimaryContainer']),
      secondary: _color(map['secondary']),
      background: _color(map['background']),
      surfaceLow: _color(map['surfaceLow']),
      surfaceContainer: _color(map['surfaceContainer']),
      surfaceHigh: _color(map['surfaceHigh']),
      surfaceHighest: _color(map['surfaceHighest']),
      onSurface: _color(map['onSurface']),
      onSurfaceVariant: _color(map['onSurfaceVariant']),
      outline: _color(map['outline']),
      outlineVariant: _color(map['outlineVariant']),
      error: _color(map['error']),
      success: _color(map['success']),
      warning: _color(map['warning']),
      info: _color(map['info']),
      fontFamily: map['fontFamily'] as String?,
      radiusMultiplier: (map['radiusMultiplier'] as num?)?.toDouble(),
    );
  }

  LumenPalette applyTo(
    LumenPalette base, {
    Color? accentPrimary,
  }) {
    return base.copyWith(
      primary: primary ?? accentPrimary ?? base.primary,
      onPrimary: onPrimary ?? base.onPrimary,
      primaryContainer: primaryContainer ?? base.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? base.onPrimaryContainer,
      secondary: secondary ?? base.secondary,
      background: background ?? base.background,
      surfaceLow: surfaceLow ?? base.surfaceLow,
      surfaceContainer: surfaceContainer ?? base.surfaceContainer,
      surfaceHigh: surfaceHigh ?? base.surfaceHigh,
      surfaceHighest: surfaceHighest ?? base.surfaceHighest,
      onSurface: onSurface ?? base.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? base.onSurfaceVariant,
      outline: outline ?? base.outline,
      outlineVariant: outlineVariant ?? base.outlineVariant,
      error: error ?? base.error,
      success: success ?? base.success,
      warning: warning ?? base.warning,
      info: info ?? base.info,
    );
  }

  static PluginThemeTokens? resolveFromPlugins(List<PluginInfo> plugins) {
    final candidates = plugins
        .where((p) {
          if (!(p.enabled && p.contributions['theme'] is Map)) return false;
          final map = (p.contributions['theme'] as Map)
              .cast<String, dynamic>();
          return map['applyByDefault'] != false;
        })
        .toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    if (candidates.isEmpty) return null;
    return PluginThemeTokens.fromMap(
      (candidates.first.contributions['theme'] as Map).cast<String, dynamic>(),
    );
  }
}
/// A theme that ships with Lumen itself, rather than arriving as a plugin.
@immutable
class BuiltinTheme {
  const BuiltinTheme({
    required this.id,
    required this.name,
    required this.tokens,
  });

  final String id;
  final String name;
  final PluginThemeTokens tokens;
}

const List<BuiltinTheme> builtinThemes = <BuiltinTheme>[
  BuiltinTheme(
    id: 'lumen',
    name: 'Lumen default',
    tokens: PluginThemeTokens(),
  ),
  BuiltinTheme(
    id: 'aurora',
    name: 'Aurora',
    tokens: PluginThemeTokens(
      primary: Color(0xFF9FD0FF),
      primaryContainer: Color(0xFF1B3A6B),
      onPrimaryContainer: Color(0xFFDCEBFF),
      secondary: Color(0xFFBDA9FF),
      background: Color(0xFF070B14),
      surfaceLow: Color(0xFF101826),
      surfaceContainer: Color(0xFF152033),
      surfaceHigh: Color(0xFF1C2A42),
      surfaceHighest: Color(0xFF243552),
      onSurface: Color(0xFFEAF0FF),
      onSurfaceVariant: Color(0xFFA9B7D5),
      outline: Color(0xFF6B7FA8),
      outlineVariant: Color(0xFF3A4B70),
      success: Color(0xFF7DD8A4),
      warning: Color(0xFFF5C877),
      error: Color(0xFFFFB4AB),
      fontFamily: 'Geist',
    ),
  ),
  BuiltinTheme(
    id: 'ember',
    name: 'Ember',
    tokens: PluginThemeTokens(
      primary: Color(0xFFFFB47A),
      primaryContainer: Color(0xFF6B2E12),
      onPrimaryContainer: Color(0xFFFFE0C7),
      secondary: Color(0xFFFFD45A),
      background: Color(0xFF120A06),
      surfaceLow: Color(0xFF1F120B),
      surfaceContainer: Color(0xFF2A1810),
      surfaceHigh: Color(0xFF3A2317),
      surfaceHighest: Color(0xFF4A2F1F),
      onSurface: Color(0xFFF6ECE3),
      onSurfaceVariant: Color(0xFFCDB7A6),
      outline: Color(0xFF8A6F5D),
      outlineVariant: Color(0xFF5A4031),
      success: Color(0xFF9ED6A8),
      warning: Color(0xFFF0C16C),
      error: Color(0xFFFFB4AB),
      fontFamily: 'Geist',
    ),
  ),
  BuiltinTheme(
    id: 'forest',
    name: 'Forest',
    tokens: PluginThemeTokens(
      primary: Color(0xFF7FD6A6),
      primaryContainer: Color(0xFF17422D),
      onPrimaryContainer: Color(0xFFD8F7E6),
      secondary: Color(0xFF8BD3FF),
      background: Color(0xFF06110C),
      surfaceLow: Color(0xFF0E1C16),
      surfaceContainer: Color(0xFF14261E),
      surfaceHigh: Color(0xFF1B3328),
      surfaceHighest: Color(0xFF244234),
      onSurface: Color(0xFFE6F2EC),
      onSurfaceVariant: Color(0xFFA6C0B4),
      outline: Color(0xFF6F9082),
      outlineVariant: Color(0xFF3D574B),
      success: Color(0xFF8BE0B0),
      warning: Color(0xFFF2D38B),
      error: Color(0xFFFFB4AB),
      fontFamily: 'Geist',
    ),
  ),
];

BuiltinTheme? builtinThemeById(String? id) {
  if (id == null) return null;
  for (final theme in builtinThemes) {
    if (theme.id == id) return theme;
  }
  return null;
}
