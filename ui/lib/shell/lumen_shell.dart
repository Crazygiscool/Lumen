import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../import/import_screen.dart';
import '../journal/journal_screen.dart';
import '../plugins/plugins_screen.dart';
import '../settings/settings_screen.dart';
import '../state/providers.dart';
import '../theme/glass.dart';
import '../theme/lumen_colors.dart';

/// Simplified single-window shell: Journal, Import, Plugins, Settings.
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
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: LumenSection.values.indexOf(section),
              onDestinationSelected: (i) => ref
                  .read(selectedSectionProvider.notifier)
                  .select(LumenSection.values[i]),
              labelType: NavigationRailLabelType.all,
              backgroundColor: t.surfaceContainer,
              leading: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Tooltip(
                  message: 'Lumen',
                  child: Icon(Icons.auto_stories_outlined, color: t.primary),
                ),
              ),
              destinations: [
                for (final s in LumenSection.values)
                  NavigationRailDestination(
                    icon: Icon(s.icon),
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
    );
  }
}
