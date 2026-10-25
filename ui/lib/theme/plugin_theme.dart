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
        .where((p) => p.enabled && p.contributions['theme'] is Map)
        .toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    if (candidates.isEmpty) return null;
    return PluginThemeTokens.fromMap(
      (candidates.first.contributions['theme'] as Map).cast<String, dynamic>(),
    );
  }
}