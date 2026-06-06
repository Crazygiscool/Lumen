import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/journal_list_screen.dart';
import '../screens/settings_screen.dart';
import 'streak_widget.dart';

enum LumenPage {
  journal(Icons.article, 'Journal'),
  settings(Icons.settings, 'Settings');

  final IconData icon;
  final String label;
  const LumenPage(this.icon, this.label);
}

final List<LumenPage> _pages = LumenPage.values;

class LumenShell extends StatefulWidget {
  const LumenShell({super.key});

  @override
  State<LumenShell> createState() => _LumenShellState();
}

class _LumenShellState extends State<LumenShell> {
  int _selectedIndex = 0;

  void _onItemSelected(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topLeft,
                  radius: 1.2,
                  colors: [
                    cs.surfaceContainerHigh.withValues(alpha: 0.4),
                    cs.surface,
                  ],
                ),
              ),
            ),
          ),
          // Content
          Row(
            children: [
              // Frosted glass sidebar
              SizedBox(
                width: 64,
              child: ClipRect(
                child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      color: cs.surface.withValues(alpha: 0.5),
                      child: NavigationRail(
                        selectedIndex: _selectedIndex,
                        onDestinationSelected: _onItemSelected,
                        labelType: NavigationRailLabelType.none,
                        leading: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Icon(Icons.flare, color: cs.primary),
                            ),
                            Consumer(
                              builder: (_, _, _) => const StreakWidget(),
                            ),
                          ],
                        ),
                        destinations: _pages
                            .map(
                              (p) => NavigationRailDestination(
                                icon: Icon(p.icon),
                                selectedIcon: Icon(p.icon),
                                label: Text(p.label),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ),
              // Divider line
              SizedBox(
                width: 1,
                child: Container(color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              // Page content
              Expanded(child: _buildPage()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPage() {
    switch (_pages[_selectedIndex]) {
      case LumenPage.journal:
        return const JournalListScreen();
      case LumenPage.settings:
        return const SettingsScreen();
    }
  }
}
