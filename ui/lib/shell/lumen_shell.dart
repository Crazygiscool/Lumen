import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../console/console_screen.dart';
import '../files/files_screen.dart';
import '../github/github_screen.dart';
import '../graph/graph_screen.dart';
import '../home/home_dashboard.dart';
import '../lab/os_lab_screen.dart';
import '../projects/projects_screen.dart';
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
import 'web/lumen_web_view.dart';

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
    section: LumenSection.home,
    icon: Icons.home_outlined,
    label: 'Home',
    tooltip: 'Home tab — Ctrl+1',
    shortcut: '1',
  ),
  LumenSectionSpec(
    section: LumenSection.files,
    icon: Icons.folder_outlined,
    label: 'Files',
    tooltip: 'Files tab — Ctrl+2',
    shortcut: '2',
  ),
  LumenSectionSpec(
    section: LumenSection.vault,
    icon: Icons.lock_outline,
    label: 'Vault',
    tooltip: 'Vault tab — Ctrl+3',
    shortcut: '3',
  ),
  LumenSectionSpec(
    section: LumenSection.graph,
    icon: Icons.hub_outlined,
    label: 'Graph',
    tooltip: 'Graph tab — Ctrl+4',
    shortcut: '4',
  ),
  LumenSectionSpec(
    section: LumenSection.osLab,
    icon: Icons.memory,
    label: 'OS Lab',
    tooltip: 'OS Lab tab — Ctrl+5',
    shortcut: '5',
  ),
  LumenSectionSpec(
    section: LumenSection.console,
    icon: Icons.terminal,
    label: 'Console',
    tooltip: 'Console tab — Ctrl+6',
    shortcut: '6',
  ),
  LumenSectionSpec(
    section: LumenSection.projects,
    icon: Icons.grid_view_outlined,
    label: 'Projects',
    tooltip: 'Projects tab — Ctrl+8',
    shortcut: '8',
  ),
  LumenSectionSpec(
    section: LumenSection.github,
    icon: Icons.account_tree_outlined,
    label: 'GitHub',
    tooltip: 'GitHub tab — Ctrl+9',
    shortcut: '9',
  ),
  LumenSectionSpec(
    section: LumenSection.settings,
    icon: Icons.settings_outlined,
    label: 'Settings',
    tooltip: 'Settings tab — Ctrl+7',
    shortcut: '7',
  ),
];

final Map<LogicalKeyboardKey, LumenSection> _shortcutKeyToSection = {
  LogicalKeyboardKey.digit1: LumenSection.home,
  LogicalKeyboardKey.digit2: LumenSection.files,
  LogicalKeyboardKey.digit3: LumenSection.vault,
  LogicalKeyboardKey.digit4: LumenSection.graph,
  LogicalKeyboardKey.digit5: LumenSection.osLab,
  LogicalKeyboardKey.digit6: LumenSection.console,
  LogicalKeyboardKey.digit7: LumenSection.settings,
  LogicalKeyboardKey.digit8: LumenSection.projects,
  LogicalKeyboardKey.digit9: LumenSection.github,
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
        return LumenWebView(tabId: tab.id, startUrl: tab.url);
      case TabKind.lumen:
        return switch (tab.page) {
          LumenSection.home => const HomeDashboard(),
          LumenSection.files => FilesScreen(tabId: tab.id),
          LumenSection.vault => VaultScreen(tabId: tab.id),
          LumenSection.graph => const GraphScreen(),
          LumenSection.osLab => const OsLabScreen(),
          LumenSection.console => const ConsoleScreen(),
          LumenSection.projects => const ProjectsScreen(),
          LumenSection.github => const GithubScreen(),
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
    final features = ref.watch(featuresProvider);

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
              child: SizedBox(
                width: 56,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 12),
                      child: Tooltip(
                        message: 'Lumen',
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: t.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.auto_awesome,
                            color: t.primary,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    for (final s in _sections)
                      if (_sectionEnabled(s.section, features))
                        _ActivityButton(
                          tooltip: s.tooltip,
                          icon: s.icon,
                          selected: active?.page == s.section,
                          onTap: () => ref
                              .read(tabsProvider.notifier)
                              .activatePage(s.section),
                        ),
                    const Spacer(),
                  ],
                ),
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

/// Whether [section] is shown on the activity bar. Core sections are always
/// on; feature-gated sections consult the feature registry.
bool _sectionEnabled(LumenSection section, FeaturesState features) =>
    section.feature == null || features.enabled(section.feature!);

class _ActivityButton extends StatelessWidget {
  const _ActivityButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(
            icon,
            size: 20,
            color: selected ? t.primary : t.onSurfaceVariant,
          ),
          style: IconButton.styleFrom(
            backgroundColor: selected ? t.primaryContainer : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}
