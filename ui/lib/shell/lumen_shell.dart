import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../ffi/plugin_service.dart';
import '../import/import_screen.dart';
import '../journal/journal_screen.dart';
import '../plugins/plugins_screen.dart';
import '../settings/settings_screen.dart';
import '../state/providers.dart';
import '../theme/app_icons.dart';
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
  String? _selectedPinId;
  final Set<String> _hiddenSidebarPins = <String>{};

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
        ? LumenSection.values.indexOf(section).clamp(0, total - 1)
        : coreCount + pins.indexWhere((pin) => pin.id == _selectedPinId);

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
                      selectedIndex: selectedIndex.clamp(0, total - 1),
                      onDestinationSelected: (index) {
                        if (index < coreCount) {
                          _selectedPinId = null;
                          ref
                              .read(selectedSectionProvider.notifier)
                              .select(LumenSection.values[index]);
                        } else {
                          final pin = pins[index - coreCount];
                          if (pin.action.startsWith('section:')) {
                            final targetName = pin.action.substring('section:'.length);
                            final target = LumenSection.values.firstWhere(
                              (section) =>
                                  section.name == targetName ||
                                  section.label.toLowerCase() ==
                                      targetName.toLowerCase(),
                              orElse: () => LumenSection.journal,
                            );
                            ref
                                .read(selectedSectionProvider.notifier)
                                .select(target);
                            setState(() => _selectedPinId = null);
                          } else {
                            setState(() => _selectedPinId = pin.id);
                          }
                        }
                      },
                      labelType: NavigationRailLabelType.all,
                      backgroundColor: t.surfaceContainer,
                      destinations: [
                        for (final s in LumenSection.values)
                          NavigationRailDestination(
                            icon: GestureDetector(
                              onSecondaryTapDown: (details) => _showCoreMenu(
                                details.globalPosition,
                              ),
                              child: Icon(s.icon, color: t.onSurface),
                            ),
                            selectedIcon: Icon(s.icon, color: t.primary),
                            label: Text(s.label),
                          ),
                        for (final pin in pins)
                          NavigationRailDestination(
                            icon: GestureDetector(
                              onSecondaryTapDown: (details) =>
                                  _showPinMenu(details.globalPosition, pin),
                              child: Icon(
                                AppIcons.resolve(pin.icon),
                                color: t.onSurface,
                              ),
                            ),
                            selectedIcon: Icon(
                              AppIcons.resolve(pin.icon),
                              color: t.primary,
                            ),
                            label: Text(pin.label),
                          ),
                      ],
                    ),
                    VerticalDivider(width: 1, color: t.outlineVariant),
                    Expanded(
                      child: IndexedStack(
                        index: (_selectedPinId == null
                                ? LumenSection.values.indexOf(section)
                                : coreCount +
                                    pins.indexWhere(
                                      (pin) => pin.id == _selectedPinId,
                                    ))
                            .clamp(0, total - 1),
                        children: [
                          const JournalScreen(),
                          const ImportScreen(),
                          const PluginsScreen(),
                          const SettingsScreen(),
                          for (final pin in pins)
                            _PluginPinPanel(pin: pin),
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

  Future<void> _showCoreMenu(Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem<String>(value: 'plugins', child: Text('Plugin manager')),
      ],
    );
    if (!mounted) return;
    if (selected == 'plugins') {
      ref.read(selectedSectionProvider.notifier).select(LumenSection.plugins);
      setState(() => _selectedPinId = null);
    }
  }

  Future<void> _showPinMenu(Offset position, PluginSidebarPin pin) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<String>(value: 'open', child: Text('Open')),
        const PopupMenuItem<String>(value: 'hide', child: Text('Hide pin')),
        const PopupMenuItem<String>(
          value: 'disable',
          child: Text('Disable plugin'),
        ),
      ],
    );
    if (!mounted) return;
    switch (selected) {
      case 'open':
        setState(() => _selectedPinId = pin.id);
        break;
      case 'hide':
        setState(() => _hiddenSidebarPins.add(pin.id));
        break;
      case 'disable':
        await ref.read(pluginServiceProvider).setEnabled(pin.pluginId, false);
        ref.invalidate(pluginsProvider);
        setState(() => _selectedPinId = null);
        break;
    }
  }
}

class _PluginPinPanel extends ConsumerWidget {
  const _PluginPinPanel({required this.pin});

  final PluginSidebarPin pin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LumenColors.of(context);
    final plugins = ref.watch(pluginsProvider);
    return plugins.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) {
        PluginInfo? plugin;
        for (final candidate in list.all) {
          if (candidate.id == pin.pluginId) {
            plugin = candidate;
            break;
          }
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              pin.label,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              plugin?.description ?? 'Plugin-provided sidebar destination.',
              style: TextStyle(color: t.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (plugin != null)
              ListTile(
                leading: const Icon(Icons.extension_outlined),
                title: Text(plugin.name),
                subtitle: Text('v${plugin.version}'),
                trailing: Text(plugin.enabled ? 'Enabled' : 'Disabled'),
              ),
            const SizedBox(height: 12),
            Text(
              'Contributions are managed on the Plugins screen.',
              style: TextStyle(color: t.onSurfaceVariant, fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}
