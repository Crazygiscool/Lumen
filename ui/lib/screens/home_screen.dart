import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../utils/responsive.dart';
import '../widgets/streak_widget.dart';
import '../widgets/vault_switcher.dart';
import 'journal_list_screen.dart';
import 'note_list_screen.dart';
import 'task_list_screen.dart';
import 'board_screen.dart';
import 'mind_screen.dart';
import 'settings_screen.dart';
import 'search_results_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _sidebarHover = false;

  @override
  Widget build(BuildContext context) {
    final focusMode = ref.watch(focusModeProvider);
    final section = ref.watch(sectionProvider);
    final narrow = isNarrow(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: narrow && !focusMode
          ? AppBar(
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              title: Text(section.label),
              actions: _buildActions(),
            )
          : null,
      drawer: narrow && !focusMode ? _buildDrawer(cs) : null,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            final ctrl = HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed;
            if (ctrl && event.logicalKey == LogicalKeyboardKey.period) {
              ref.read(focusModeProvider.notifier).toggle();
              return KeyEventResult.handled;
            }
            if (ctrl && event.logicalKey == LogicalKeyboardKey.keyF) {
              _openSearch(context);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: focusMode || narrow
            ? _buildSingleColumn(cs)
            : _buildWideLayout(cs),
      ),
    );
  }

  List<Widget> _buildActions() {
    return [
      IconButton(
        icon: const Icon(Icons.search),
        tooltip: 'Search (Ctrl+F)',
        onPressed: () => _openSearch(context),
      ),
      IconButton(
        icon: const Icon(Icons.visibility_outlined),
        tooltip: 'Focus mode (Ctrl+.)',
        onPressed: () =>
            ref.read(focusModeProvider.notifier).toggle(),
      ),
    ];
  }

  void _openSearch(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchResultsScreen()),
    );
  }

  Widget _buildDrawer(ColorScheme cs) {
    final section = ref.watch(sectionProvider);
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: cs.primaryContainer),
            margin: EdgeInsets.zero,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.flare, color: cs.primary, size: 32),
                  const SizedBox(width: 12),
                  Text(
                    'Lumen',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final s in LumenSection.values)
                  ListTile(
                    leading: Icon(s.icon),
                    title: Text(s.label),
                    selected: section == s,
                    onTap: () {
                      ref.read(sectionProvider.notifier).setSection(s);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
          const Divider(),
          const StreakWidget(),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Lock'),
            onTap: () {
              Navigator.pop(context);
              ref.read(authProvider.notifier).lock();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildWideLayout(ColorScheme cs) {
    final focusMode = ref.watch(focusModeProvider);

    return MouseRegion(
      onHover: (event) {
        if (focusMode) {
          setState(() => _sidebarHover = event.localPosition.dx < 60);
        }
      },
      onExit: (_) {
        if (focusMode) {
          setState(() => _sidebarHover = false);
        }
      },
      child: Stack(
        children: [
          Row(
            children: [
              if (!focusMode)
                _buildSidebar(cs),
              if (!focusMode)
                VerticalDivider(width: 1, thickness: 1, color: cs.outlineVariant),
              Expanded(child: _buildPage()),
            ],
          ),
          if (focusMode)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              left: _sidebarHover ? 0 : -260,
              top: 0,
              bottom: 0,
              width: 260,
              child: _buildSidebar(cs, forceShow: true),
            ),
        ],
      ),
    );
  }

  Widget _buildSingleColumn(ColorScheme _) {
    return _buildPage();
  }

  Widget _buildSidebar(ColorScheme cs, {bool forceShow = false}) {
    final focusMode = ref.watch(focusModeProvider);
    final section = ref.watch(sectionProvider);

    if (focusMode && !forceShow) return const SizedBox.shrink();

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: forceShow ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(5, 0),
          )
        ] : null,
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: Row(
              children: [
                Icon(Icons.flare, color: cs.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Lumen',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                ),
                const Spacer(),
                if (!forceShow)
                  IconButton(
                    icon: const Icon(Icons.visibility_outlined, size: 20),
                    tooltip: 'Focus mode (Ctrl+.)',
                    onPressed: () =>
                        ref.read(focusModeProvider.notifier).toggle(),
                  ),
              ],
            ),
          ),
          // Vault switcher
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: VaultSwitcher(onChanged: () => setState(() {})),
          ),
          const SizedBox(height: 16),
          // Sections
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                ...LumenSection.values.map((s) {
                  final active = section == s;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: active
                          ? cs.primaryContainer.withValues(alpha: 0.5)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        ref.read(sectionProvider.notifier).setSection(s);
                        if (forceShow) setState(() => _sidebarHover = false);
                      },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          child: Row(
                            children: [
                              Icon(s.icon,
                                  size: 20,
                                  color: active
                                      ? cs.primary
                                      : cs.onSurfaceVariant),
                              const SizedBox(width: 12),
                              Text(
                                s.label,
                                style: TextStyle(
                                  color: active
                                      ? cs.onSurface
                                      : cs.onSurfaceVariant,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const Divider(indent: 16, endIndent: 16),
          // Streak
          const StreakWidget(),
          // Lock button
          Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => ref.read(authProvider.notifier).lock(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline,
                          size: 20, color: cs.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Text(
                        'Lock App',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildPage() {
    final LumenSection section = ref.watch(sectionProvider);
    switch (section) {
      case LumenSection.journal:
        return const JournalListScreen();
      case LumenSection.notes:
        return const NoteListScreen();
      case LumenSection.tasks:
        return const TaskListScreen();
      case LumenSection.board:
        return const BoardScreen();
      case LumenSection.mind:
        return const MindScreen();
      case LumenSection.settings:
        return const SettingsScreen();
    }
  }
}
