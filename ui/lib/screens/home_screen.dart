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

final focusModeProvider = NotifierProvider<FocusModeNotifier, bool>(
    FocusModeNotifier.new);

class FocusModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

enum LumenSection {
  journal(Icons.article, 'Journal'),
  notes(Icons.note, 'Notes'),
  tasks(Icons.checklist, 'Tasks'),
  board(Icons.dashboard, 'Kanban'),
  mind(Icons.bubble_chart, 'Mind Map'),
  settings(Icons.settings, 'Settings');

  final IconData icon;
  final String label;
  const LumenSection(this.icon, this.label);
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  LumenSection _section = LumenSection.journal;
  bool _sidebarHover = false;

  @override
  Widget build(BuildContext context) {
    final focusMode = ref.watch(focusModeProvider);
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
              title: Text(_section.label),
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
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: cs.primaryContainer),
            child: Text(
              'Lumen',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                  ),
            ),
          ),
          for (final s in LumenSection.values)
            ListTile(
              leading: Icon(s.icon),
              title: Text(s.label),
              selected: _section == s,
              onTap: () {
                setState(() => _section = s);
                Navigator.pop(context);
              },
            ),
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
                SizedBox(width: 1, child: Container(color: cs.outlineVariant)),
              Expanded(child: _buildPage()),
            ],
          ),
          if (focusMode)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              left: _sidebarHover ? 0 : -240,
              top: 0,
              bottom: 0,
              width: 240,
              child: _buildSidebar(cs),
            ),
        ],
      ),
    );
  }

  Widget _buildSingleColumn(ColorScheme _) {
    return _buildPage();
  }

  Widget _buildSidebar(ColorScheme cs) {
    // Frosted glass sidebar on wide
    final focusMode = ref.watch(focusModeProvider);
    if (focusMode) return const SizedBox.shrink();

    return SizedBox(
      width: 240,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: cs.surface.withValues(alpha: 0.5),
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.flare, color: cs.primary, size: 28),
                      const SizedBox(width: 8),
                      Text(
                        'Lumen',
                        style:
                            Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const Spacer(),
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
                VaultSwitcher(onChanged: () => setState(() {})),
                const SizedBox(height: 8),
                // Sections
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        ...LumenSection.values.map((s) {
                      final active = _section == s;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Material(
                          color: active
                              ? cs.primaryContainer.withValues(alpha: 0.3)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() => _section = s),
                            child: Container(
                              decoration: active
                                  ? BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          color: cs.primary,
                                          width: 2,
                                        ),
                                      ),
                                    )
                                  : null,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
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
                                          ? cs.primary
                                          : cs.onSurfaceVariant,
                                      fontWeight: active
                                          ? FontWeight.w600
                                          : FontWeight.w400,
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
                const Spacer(),
                // Streak
                const StreakWidget(),
                // Lock button
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => ref.read(authProvider.notifier).lock(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline,
                                size: 20, color: cs.onSurfaceVariant),
                            const SizedBox(width: 12),
                            Text(
                              'Lock',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildPage() {
    switch (_section) {
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
