import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/plugin_service.dart';
import '../state/providers.dart';
import 'lumen_colors.dart';
import 'plugin_theme.dart';

class ThemeManagerScreen extends ConsumerWidget {
  const ThemeManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LumenColors.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final plugins = ref.watch(pluginsProvider);

    final pluginThemes = plugins.maybeWhen(
      data: (list) => list.all
          .where((plugin) => plugin.enabled && plugin.contributions['theme'] is Map)
          .toList(growable: false),
      orElse: () => const <PluginInfo>[],
    );

    final activeId = settings.activeThemeId ?? settings.activeThemePluginId;
    final dropdownItems = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(value: null, child: Text('Lumen default')),
      for (final theme in builtinThemes)
        if (theme.id != 'lumen')
          DropdownMenuItem<String?>(value: theme.id, child: Text(theme.name)),
      for (final plugin in pluginThemes)
        DropdownMenuItem<String?>(value: plugin.id, child: Text(plugin.name)),
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Theme manager', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Select a Lumen theme and apply it live, including colors, fonts, '
          'and icon variants when provided.',
          style: TextStyle(color: t.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        DropdownButton<String?>(
          value: activeId,
          isExpanded: true,
          items: dropdownItems,
          onChanged: (value) {
            final builtin = builtinThemeById(value);
            if (value == 'lumen' || builtin != null && value == 'lumen') {
              notifier.setActiveThemeId(null);
              return;
            }
            notifier.setActiveThemeId(value);
          },
        ),
        const SizedBox(height: 12),
        ...dropdownItems
            .where((item) => item.value != null)
            .map(
              (item) => _ThemeOptionTile(
                title: item.child is Text
                    ? (item.child as Text).data ?? ''
                    : '',
                subtitle: item.value == null
                    ? 'Built-in theme'
                    : _subtitleFor(item.value!, pluginThemes),
                selected: activeId == item.value,
                onTap: () => notifier.setActiveThemeId(item.value),
              ),
            ),
      ],
    );
  }

  String _subtitleFor(String id, List<PluginInfo> pluginThemes) {
    for (final plugin in pluginThemes) {
      if (plugin.id == id) return plugin.description ?? 'Plugin-contributed theme.';
    }
    final builtin = builtinThemeById(id);
    if (builtin != null) return 'Built-in theme.';
    return 'Theme';
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          selected ? Icons.check_circle : Icons.palette_outlined,
          color: selected ? t.primary : t.onSurfaceVariant,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: selected ? const Text('Active') : null,
        onTap: onTap,
      ),
    );
  }
}