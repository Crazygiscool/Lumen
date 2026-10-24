import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../import/import_screen.dart';
import '../journal/journal_screen.dart';
import '../plugins/plugins_screen.dart';
import '../settings/settings_screen.dart';
import '../state/providers.dart';
import '../theme/glass.dart';
import '../theme/lumen_colors.dart';
import 'top_bar.dart';

/// Simplified single-window shell: Journal, Import, Plugins, Settings.
///
/// The native title bar is hidden, so [LumenTopBar] owns the window chrome and
/// [DragToResizeArea] restores edge resizing for the frameless window.
class LumenShell extends ConsumerStatefulWidget {
  const LumenShell({super.key});

  @override
  ConsumerState<LumenShell> createState() => _LumenShellState();
}

class _LumenShellState extends ConsumerState<LumenShell> {
  @override
  Widget build(BuildContext context) {
    final section = ref.watch(selectedSectionProvider);
    final t = LumenColors.of(context);

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DragToResizeArea(
          resizeEdgeSize: 6,
          child: Column(
            children: [
              const LumenTopBar(),
              Expanded(
                child: Row(
                  children: [
                    NavigationRail(
                      selectedIndex: LumenSection.values.indexOf(section),
                      onDestinationSelected: (i) => ref
                          .read(selectedSectionProvider.notifier)
                          .select(LumenSection.values[i]),
                      labelType: NavigationRailLabelType.all,
                      backgroundColor: t.surfaceContainer,
                      destinations: [
                        for (final s in LumenSection.values)
                          NavigationRailDestination(
                            icon: Icon(s.icon, color: t.onSurface),
                            selectedIcon: Icon(s.icon, color: t.primary),
                            label: Text(s.label),
                          ),
                      ],
                    ),
                    VerticalDivider(width: 1, color: t.outlineVariant),
                    Expanded(
                      child: IndexedStack(
                        index: LumenSection.values.indexOf(section),
                        children: const [
                          JournalScreen(),
                          ImportScreen(),
                          PluginsScreen(),
                          SettingsScreen(),
                        ],
                      ),
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
