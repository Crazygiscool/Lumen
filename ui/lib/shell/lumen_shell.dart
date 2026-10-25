import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../import/import_screen.dart';
import '../journal/journal_screen.dart';
import '../plugins/plugins_screen.dart';
import '../settings/settings_screen.dart';
import '../state/providers.dart';
import '../theme/app_icons.dart';
import '../theme/glass.dart';
import '../theme/theme_manager_screen.dart';
import '../theme/lumen_colors.dart';
import 'top_bar.dart';

class LumenShell extends ConsumerStatefulWidget {
  const LumenShell({super.key});

  @override
  ConsumerState<LumenShell> createState() => _LumenShellState();
}

class _LumenShellState extends ConsumerState<LumenShell> {
  String? _selectedPinId;
  final Set<String> _hiddenSidebarPins = <String>{};
  Map<String, String> _iconOverrides = <String, String>{};

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final raw = prefs.getString('lumen.sidebarIconOverrides');
      if (raw == null || raw.isEmpty) return;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final next = <String, String>{};
          decoded.forEach((key, value) {
            if (value is String) next[key.toString()] = value;
          });
          if (mounted) setState(() => _iconOverrides = next);
        }
      } catch (_) {
        // Ignore malformed icon-preference data.
      }
    });
  }

  Future<void> _saveIconOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'lumen.sidebarIconOverrides',
      jsonEncode(_iconOverrides),
    );
  }

  String _iconKeyForCore(LumenSection section) => 'section:${section.name}';

  String _iconKeyForPin(PluginSidebarPin pin) => 'pin:${pin.id}';

  IconData _resolveIcon(String key, IconData fallback) {
    final override = _iconOverrides[key];
    if (override != null && AppIcons.builtin.containsKey(override)) {
      return AppIcons.builtin[override]!;
    }
    return fallback;
  }

  Future<void> _persistIconOverride(String key, String iconName) async {
    setState(() => _iconOverrides[key] = iconName);
    await _saveIconOverrides();
  }

  Future<void> _showRailMenu(
    Offset position,
    String key, {
    PluginSidebarPin? pin,
  }) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            'Choose icon',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        const PopupMenuDivider(),
        for (final name in AppIcons.availableIconNames)
          PopupMenuItem<String>(
            value: 'icon:$name',
            child: Row(
              children: [
                Icon(AppIcons.builtin[name], size: 18),
                const SizedBox(width: 10),
                Text(name),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'reset',
          child: Text('Reset icon'),
        ),
        if (pin != null)
          const PopupMenuItem<String>(value: 'hide', child: Text('Hide pin')),
      ],
    );

    if (!mounted || selected == null) return;
    if (selected == 'reset') {
      setState(() => _iconOverrides.remove(key));
      await _saveIconOverrides();
      return;
    }
    if (selected == 'hide' && pin != null) {
      setState(() => _hiddenSidebarPins.add(pin.id));
      return;
    }
    if (selected.startsWith('icon:')) {
      await _persistIconOverride(key, selected.substring('icon:'.length));
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = ref.watch(selectedSectionProvider);
    final t = LumenColors.of(context);
    final allPins = ref.watch(pluginSidebarPinsProvider);
    final pins = allPins
        .where((pin) => !_hiddenSidebarPins.contains(pin.id))
        .toList(growable: false);
    if (_selectedPinId != null &&
        !pins.any((pin) => pin.id == _selectedPinId)) {
      _selectedPinId = null;
    }

    final coreCount = LumenSection.values.length;
    final total = coreCount + pins.length;
    final selectedIndex = _selectedPinId == null
        ? LumenSection.values.indexOf(section).clamp(0, total == 0 ? 1 : total - 1)
        : coreCount + pins.indexWhere((pin) => pin.id == _selectedPinId);

    final screens = ref.watch(pluginScreensProvider);

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
                      selectedIndex: total == 0
                          ? 0
                          : selectedIndex.clamp(0, total - 1),
                      onDestinationSelected: (index) {
                        if (index < coreCount) {
                          _selectedPinId = null;
                          ref
                              .read(selectedSectionProvider.notifier)
                              .select(LumenSection.values[index]);
                        } else {
                          final pin = pins[index - coreCount];
                          if (pin.action.startsWith('section:')) {
                            final target = _sectionFromName(
                              pin.action.substring('section:'.length),
                            );
                            ref
                                .read(selectedSectionProvider.notifier)
                                .select(target);
                            setState(() => _selectedPinId = null);
                          } else if (pin.action.startsWith('screen:')) {
                            setState(() => _selectedPinId = pin.id);
                          } else {
                            setState(() => _selectedPinId = pin.id);
                          }
                        }
                      },
                      labelType: NavigationRailLabelType.all,
                      backgroundColor: t.surfaceContainer,
                      destinations: [
                        for (final value in LumenSection.values)
                          NavigationRailDestination(
                            icon: GestureDetector(
                              onSecondaryTapDown: (details) =>
                                  _showRailMenu(
                                    details.globalPosition,
                                    _iconKeyForCore(value),
                                  ),
                              child: Icon(
                                _resolveIcon(
                                  _iconKeyForCore(value),
                                  value.icon,
                                ),
                                color: t.onSurface,
                              ),
                            ),
                            selectedIcon: Icon(
                              _resolveIcon(
                                _iconKeyForCore(value),
                                value.icon,
                              ),
                              color: t.primary,
                            ),
                            label: Text(value.label),
                          ),
                        for (final pin in pins)
                          NavigationRailDestination(
                            icon: GestureDetector(
                              onSecondaryTapDown: (details) =>
                                  _showRailMenu(
                                    details.globalPosition,
                                    _iconKeyForPin(pin),
                                    pin: pin,
                                  ),
                              child: Icon(
                                _resolveIcon(
                                  _iconKeyForPin(pin),
                                  AppIcons.resolve(pin.icon),
                                ),
                                color: t.onSurface,
                              ),
                            ),
                            selectedIcon: Icon(
                              _resolveIcon(
                                _iconKeyForPin(pin),
                                AppIcons.resolve(pin.icon),
                              ),
                              color: t.primary,
                            ),
                            label: Text(pin.label),
                          ),
                      ],
                    ),
                    VerticalDivider(width: 1, color: t.outlineVariant),
                    Expanded(
                      child: IndexedStack(
                        index: _selectedPinId == null
                            ? _sectionIndex(section)
                            : coreCount +
                                pins.indexWhere(
                                  (pin) => pin.id == _selectedPinId,
                                ),
                        children: [
                          const JournalScreen(),
                          const PluginsScreen(),
                          const SettingsScreen(),
                          for (final pin in pins)
                            _PluginScreenSurface(
                              pin: pin,
                              screen: _screenForPin(pin, screens),
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
      ),
    );
  }

  int _sectionIndex(LumenSection section) {
    final index = LumenSection.values.indexOf(section);
    return index < 0 ? 0 : index;
  }

  LumenSection _sectionFromName(String name) {
    return LumenSection.values.firstWhere(
      (value) => value.name == name || value.label.toLowerCase() == name.toLowerCase(),
      orElse: () => LumenSection.journal,
    );
  }

  PluginScreen? _screenForPin(PluginSidebarPin pin, List<PluginScreen> screens) {
    for (final screen in screens) {
      if (screen.id == pin.id) return screen;
    }
    for (final screen in screens) {
      if (screen.pluginId == pin.pluginId) return screen;
    }
    return null;
  }
}

class _PluginScreenSurface extends ConsumerWidget {
  const _PluginScreenSurface({required this.pin, required this.screen});

  final PluginSidebarPin pin;
  final PluginScreen? screen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final template = screen?.template ?? 'markdown';
    switch (template) {
      case 'import':
        return const ImportScreen();
      case 'journal':
        return const JournalScreen();
      case 'plugins':
        return const PluginsScreen();
      case 'settings':
        return const SettingsScreen();
      case 'theme':
        return const ThemeManagerScreen();
      default:
        return _MarkdownPluginScreen(
          title: screen?.title ?? pin.label,
          body: screen?.body ?? 'Plugin-contributed screen.',
        );
    }
  }
}

class _MarkdownPluginScreen extends StatelessWidget {
  const _MarkdownPluginScreen({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Markdown(
            data: body,
            selectable: true,
          ),
        ],
      ),
    );
  }
}