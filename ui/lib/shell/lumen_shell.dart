import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../console/console_screen.dart';
import '../files/files_screen.dart';
import '../graph/graph_screen.dart';
import '../lab/os_lab_screen.dart';
import '../settings/settings_screen.dart';
import '../state/providers.dart';
import '../theme/glass.dart';
import '../theme/lumen_colors.dart';
import '../vault/vault_screen.dart';
import 'command_palette.dart';
import 'tabs/address_bar.dart';
import 'tabs/tab_strip.dart';
import 'tabs/tab_model.dart';
import 'tabs/new_tab_page.dart';
import 'tabs/tabs_provider.dart';
import 'tabs/web_tab_content.dart';

class LumenSectionSpec {
  const LumenSectionSpec({
    required this.section,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.shortcut,
  });
  final LumenSection section;
  final IconData icon;
  final String label;
  final String tooltip;
  final String shortcut;
}

const _sections = [
  LumenSectionSpec(
    section: LumenSection.files,
    icon: Icons.folder_outlined,
    label: 'Files',
    tooltip: 'Files tab — Ctrl+1',
    shortcut: '1',
  ),
  LumenSectionSpec(
    section: LumenSection.vault,
    icon: Icons.lock_outline,
    label: 'Vault',
    tooltip: 'Vault tab — Ctrl+2',
    shortcut: '2',
  ),
  LumenSectionSpec(
    section: LumenSection.graph,
    icon: Icons.hub_outlined,
    label: 'Graph',
    tooltip: 'Graph tab — Ctrl+3',
    shortcut: '3',
  ),
  LumenSectionSpec(
    section: LumenSection.osLab,
    icon: Icons.memory,
    label: 'OS Lab',
    tooltip: 'OS Lab tab — Ctrl+4',
    shortcut: '4',
  ),
  LumenSectionSpec(
    section: LumenSection.console,
    icon: Icons.terminal,
    label: 'Console',
    tooltip: 'Console tab — Ctrl+5',
    shortcut: '5',
  ),
  LumenSectionSpec(
    section: LumenSection.settings,
    icon: Icons.settings_outlined,
    label: 'Settings',
    tooltip: 'Settings tab — Ctrl+6',
    shortcut: '6',
  ),
];

final Map<LogicalKeyboardKey, LumenSection> _shortcutKeyToSection = {
  LogicalKeyboardKey.digit1: LumenSection.files,
  LogicalKeyboardKey.digit2: LumenSection.vault,
  LogicalKeyboardKey.digit3: LumenSection.graph,
  LogicalKeyboardKey.digit4: LumenSection.osLab,
  LogicalKeyboardKey.digit5: LumenSection.console,
  LogicalKeyboardKey.digit6: LumenSection.settings,
};

class LumenShell extends ConsumerStatefulWidget {
  const LumenShell({super.key});

  @override
  ConsumerState<LumenShell> createState() => _LumenShellState();
}

class _LumenShellState extends ConsumerState<LumenShell> {
  final FocusNode _focusNode = FocusNode();
  final FocusNode _addressFocus = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed || kb.isMetaPressed;
    final tabs = ref.read(tabsProvider.notifier);

    if (ctrl) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyT:
          tabs.newTab();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyW:
          final a = ref.read(tabsProvider).active;
          if (a != null) tabs.closeTab(a.id);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyL:
          _addressFocus.requestFocus();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyP:
          ref.read(commandPaletteProvider.notifier).open();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyR:
          tabs.reload();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.tab:
          final c = ref.read(tabsProvider);
          if (c.tabs.length > 1) {
            final idx = c.activeIndex;
            final next = kb.isShiftPressed
                ? (idx - 1 + c.tabs.length) % c.tabs.length
                : (idx + 1) % c.tabs.length;
            tabs.activate(c.tabs[next].id);
          }
          return KeyEventResult.handled;
      }
      final section = _shortcutKeyToSection[event.logicalKey];
      if (section != null) {
        tabs.activatePage(section);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (kb.isAltPressed) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        tabs.back();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        tabs.forward();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Widget _tabContent(LumenTab tab) {
    switch (tab.kind) {
      case TabKind.newtab:
        return NewTabPage(onFocusAddress: () => _addressFocus.requestFocus());
      case TabKind.web:
        return WebTabContent(url: tab.url);
      case TabKind.lumen:
        return switch (tab.page) {
          LumenSection.files => FilesScreen(tabId: tab.id),
          LumenSection.vault => VaultScreen(tabId: tab.id),
          LumenSection.graph => const GraphScreen(),
          LumenSection.osLab => const OsLabScreen(),
          LumenSection.console => const ConsoleScreen(),
          LumenSection.settings => const SettingsScreen(),
          null => const SizedBox.shrink(),
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final theme = Theme.of(context);
    final tabs = ref.watch(tabsProvider);
    final active = tabs.active;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        body: Row(
          children: [
            Glass(
              blurSigma: 20,
              radius: 0,
              fill: t.glass,
              border: false,
              child: NavigationRail(
                selectedIndex: active?.page?.index,
                onDestinationSelected: (i) => ref
                    .read(tabsProvider.notifier)
                    .activatePage(LumenSection.values[i]),
                leading: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Tooltip(
                    message: 'Lumen',
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: t.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        color: t.primary,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                destinations: [
                  for (final s in _sections)
                    NavigationRailDestination(
                      icon: Icon(s.icon),
                      selectedIcon: Icon(s.icon),
                      label: Text(s.label),
                    ),
                ],
                trailing: const Spacer(),
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant,
            ),
            Expanded(
              child: Column(
                children: [
                  const TabStrip(),
                  AddressBar(focusNode: _addressFocus),
                  Expanded(
                    child: IndexedStack(
                      index: tabs.activeIndex,
                      children: [
                        for (final tab in tabs.tabs)
                          KeyedSubtree(
                            key: ValueKey(tab.id),
                            child: _tabContent(tab),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
