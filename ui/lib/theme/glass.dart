import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'lumen_colors.dart';

/// Paints Lumen's pitch-black backdrop: a very dark base lit by two soft
/// indigo/violet glows, softly blurred. Everything else floats above it.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.background,
        gradient: RadialGradient(
          radius: 1.35,
          colors: [t.glowDeep, t.background],
          stops: const [0.0, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -140,
            left: -140,
            width: 460,
            height: 460,
            child: _Glow(color: t.glowIndigo, opacity: 0.17),
          ),
          Positioned(
            bottom: -180,
            right: -160,
            width: 520,
            height: 520,
            child: _Glow(color: t.glowViolet, opacity: 0.12),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
            child: const SizedBox.expand(),
          ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.opacity});
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// A frosted panel: backdrop blur + translucent fill + hairline border.
///
/// Use for chrome that overlays content (toolbars, top bars) and for
/// floating surfaces (dialogs, command palette, popup menus). Side panels and
/// cards should use a lower `blurSigma` (or 0) to keep text crisp.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    this.child,
    this.blurSigma = 16,
    this.fill,
    this.radius = LumenColors.radiusMd,
    this.border = true,
    this.hairline,
    this.padding,
  });

  final Widget? child;
  final double blurSigma;
  final Color? fill;
  final double radius;
  final bool border;
  final Color? hairline;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: blurSigma > 0
            ? ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma)
            : ImageFilter.blur(sigmaX: 0.001, sigmaY: 0.001),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fill ?? LumenColors.of(context).glass,
            borderRadius: BorderRadius.circular(radius),
            border: border
                ? Border.all(
                    color: hairline ?? LumenColors.of(context).hairline,
                    width: 1,
                  )
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Shorthand for glass chrome strips used across screen toolbars.
class GlassBar extends StatelessWidget {
  const GlassBar({
    super.key,
    this.height = 48,
    this.blurSigma = 16,
    required this.child,
  });

  final double height;
  final double blurSigma;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Glass(
        blurSigma: blurSigma,
        radius: 0,
        fill: LumenColors.of(context).glassStrong,
        border: false,
        child: child,
      ),
    );
  }
}

/// Soft glow shadow used to lift floating surfaces off the backdrop.
BoxShadow glowShadow({
  Color color = LumenColors.primary,
  double opacity = 0.16,
  double blur = 30,
}) {
  return BoxShadow(
    color: color.withValues(alpha: opacity),
    blurRadius: blur,
    spreadRadius: 0,
    offset: const Offset(0, 10),
  );
}
