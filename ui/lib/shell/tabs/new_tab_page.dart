import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../theme/lumen_colors.dart';
import 'tab_model.dart';
import 'tabs_provider.dart';

class NewTabPage extends ConsumerWidget {
  const NewTabPage({super.key, this.onFocusAddress});

  final VoidCallback? onFocusAddress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LumenColors.of(context);
    final dial = [
      for (final s in LumenSection.values)
        _DialTile(
          icon: s.icon,
          title: s.title,
          subtitle: 'lumen://${s.pathName}',
          onTap: () => ref.read(tabsProvider.notifier).activatePage(s),
        ),
      if (onFocusAddress != null)
        _DialTile(
          icon: Icons.travel_explore,
          title: 'Web',
          subtitle: 'or search the web',
          onTap: onFocusAddress!,
        ),
    ];

    return Column(
      children: [
        const SizedBox(height: 56),
        Icon(Icons.auto_awesome, size: 34, color: t.primary),
        const SizedBox(height: 10),
        Text(
          'Lumen',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: t.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Type in the address bar to explore\nlumen:// pages, files, or any website',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: t.onSurfaceVariant),
        ),
        const SizedBox(height: 36),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final tile in dial) SizedBox(width: 200, child: tile),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _DialTile extends StatefulWidget {
  const _DialTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_DialTile> createState() => _DialTileState();
}

class _DialTileState extends State<_DialTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          height: 88,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered ? t.glassHover : t.surfaceLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.hairline, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: t.primaryContainer.withValues(
                    alpha: _hovered ? 1 : 0.55,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, size: 18, color: t.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: t.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: t.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
