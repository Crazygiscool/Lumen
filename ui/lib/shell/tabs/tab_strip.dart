import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/lumen_colors.dart';
import '../../theme/glass.dart';
import 'tab_model.dart';
import 'tabs_provider.dart';

class TabStrip extends ConsumerStatefulWidget {
  const TabStrip({super.key});

  @override
  ConsumerState<TabStrip> createState() => _TabStripState();
}

class _TabStripState extends ConsumerState<TabStrip> {
  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final tabs = ref.watch(tabsProvider);

    return SizedBox(
      height: 38,
      child: Glass(
        blurSigma: 14,
        radius: 0,
        fill: t.surfaceContainer,
        border: false,
        child: Row(
          children: [
            const SizedBox(width: 8),
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final tab in tabs.tabs)
                    _TabChip(
                      tab: tab,
                      active: tab.id == tabs.activeId,
                      onTap: () =>
                          ref.read(tabsProvider.notifier).activate(tab.id),
                      onClose: () =>
                          ref.read(tabsProvider.notifier).closeTab(tab.id),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'New tab (Ctrl+T)',
              icon: const Icon(Icons.add, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: () => ref.read(tabsProvider.notifier).newTab(),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatefulWidget {
  const _TabChip({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final LumenTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final active = widget.active;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            height: 28,
            constraints: const BoxConstraints(maxWidth: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: active
                  ? t.surfaceContainer
                  : _hovered
                  ? t.glassHover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: active ? Border.all(color: t.hairline, width: 1) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.tab.icon,
                  size: 14,
                  color: active ? t.primary : t.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: active ? t.onSurface : t.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close,
                      size: 13,
                      color: active ? t.onSurface : t.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
