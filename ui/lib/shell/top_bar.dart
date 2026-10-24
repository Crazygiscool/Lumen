import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/lumen_colors.dart';

/// Lumen's own window chrome.
///
/// The native title bar is hidden (see `WindowOptions` in `main.dart`), so this
/// strip is the only way to move, minimise, maximise or close the window. The
/// left side carries the wordmark, the middle is a drag region, and the right
/// side mirrors the usual desktop window controls.
class LumenTopBar extends StatefulWidget {
  const LumenTopBar({super.key});

  static const double height = 40;

  @override
  State<LumenTopBar> createState() => _LumenTopBarState();
}

class _LumenTopBarState extends State<LumenTopBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    try {
      final maximized = await windowManager.isMaximized();
      _setMaximized(maximized);
    } catch (_) {
      // No plugin (widget tests) or unsupported platform: stay unmaximized.
    }
  }

  @override
  void onWindowMaximize() => _setMaximized(true);

  @override
  void onWindowUnmaximize() => _setMaximized(false);

  @override
  void onWindowRestore() => _setMaximized(false);

  void _setMaximized(bool value) {
    if (!mounted || _maximized == value) return;
    setState(() => _maximized = value);
  }

  Future<void> _toggleMaximize() async {
    try {
      if (_maximized) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {
      // Ignore: nothing to toggle without a window manager.
    }
  }

  Future<void> _minimize() async {
    try {
      await windowManager.minimize();
    } catch (_) {
      // Ignore.
    }
  }

  Future<void> _close() async {
    try {
      await windowManager.close();
    } catch (_) {
      // Ignore.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final textStyle = Theme.of(context).textTheme.labelSmall;

    return Container(
      height: LumenTopBar.height,
      decoration: BoxDecoration(
        color: t.glassStrong,
        border: Border(bottom: BorderSide(color: t.hairline, width: 1)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(LumenColors.radiusSm),
            child: Image.asset(
              'lib/assets/lumen_logo.png',
              width: 18,
              height: 18,
              filterQuality: FilterQuality.medium,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'LUMEN',
            style: (textStyle ?? const TextStyle()).copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
              color: t.onSurface,
            ),
          ),
          Expanded(
            child: DragToMoveArea(
              child: MouseRegion(
                cursor: SystemMouseCursors.basic,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          _WindowButton(
            icon: Icons.horizontal_rule_rounded,
            tooltip: 'Minimize',
            onPressed: _minimize,
          ),
          _WindowButton(
            icon: _maximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            tooltip: _maximized ? 'Restore' : 'Maximize',
            iconSize: 14,
            onPressed: _toggleMaximize,
          ),
          _WindowButton(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            dangerous: true,
            onPressed: _close,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 16,
    this.dangerous = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double iconSize;
  final bool dangerous;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final hoverColor = widget.dangerous ? const Color(0xFFE81123) : t.glassHover;
    final iconColor = widget.dangerous && _hovering ? Colors.white : t.onSurface;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            width: 44,
            height: LumenTopBar.height,
            alignment: Alignment.center,
            color: _hovering ? hoverColor : Colors.transparent,
            child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}
