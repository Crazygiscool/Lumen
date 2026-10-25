import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/plugin_service.dart';
import '../state/providers.dart';
import 'lumen_colors.dart';

/// A dedicated screen for selecting and applying Lumen themes live.
class ThemeManagerScreen extends ConsumerWidget {
  const ThemeManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LumenColors.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final plugins = ref.watch(pluginsProvider);

    final themes = plugins.maybeWhen(
      data: (list) => list.all
          .where((plugin) => plugin.enabled && plugin.contributions['theme'] is Map)
          .toList(growable: false),
      orElse: () => const <PluginInfo>[],
    );

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Theme manager', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Select a Lumen theme and apply it live. Themes may contribute '
          'colors, fonts, icons, and other presentation tokens.',
          style: TextStyle(color: t.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        _ThemeOptionTile(
          title: 'Lumen default',
          subtitle: 'The built-in midnight/daylight appearance.',
          selected: settings.activeThemePluginId == null,
          onTap: () => notifier.setActiveThemePluginId(null),
        ),
        for (final plugin in themes)
          _ThemeOptionTile(
            title: plugin.name,
            subtitle: plugin.description ?? 'Plugin-contributed theme.',
            selected: settings.activeThemePluginId == plugin.id,
            onTap: () => notifier.setActiveThemePluginId(plugin.id),
          ),
        if (themes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'No plugin themes are enabled. Enable one on the Plugins screen.',
              style: TextStyle(color: t.onSurfaceVariant),
            ),
          ),
      ],
    );
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