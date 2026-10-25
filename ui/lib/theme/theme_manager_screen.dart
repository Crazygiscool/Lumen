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
          .where(
            (plugin) =>
                plugin.id != 'theme_manager' &&
                plugin.enabled &&
                plugin.contributions['theme'] is Map,
          )
          .toList(growable: false),
      orElse: () => const <PluginInfo>[],
    );

    final allThemes = <_ThemeChoice>[
      const _ThemeChoice(id: null, label: 'Lumen default', tokens: null),
      for (final theme in builtinThemes)
        if (theme.id != 'lumen')
          _ThemeChoice(id: theme.id, label: theme.name, tokens: theme.tokens),
      for (final plugin in pluginThemes)
        _ThemeChoice(
          id: plugin.id,
          label: plugin.name,
          tokens: PluginThemeTokens.fromMap(
            (plugin.contributions['theme'] as Map).cast<String, dynamic>(),
          ),
        ),
    ];

    final requestedActiveId = settings.activeThemeId ?? settings.activeThemePluginId;
    final activeId = allThemes.any((choice) => choice.id == requestedActiveId)
        ? requestedActiveId
        : null;
    final availableFonts = <String>{'Geist'};
    if (settings.activeFontFamily != null &&
        settings.activeFontFamily!.isNotEmpty) {
      availableFonts.add(settings.activeFontFamily!);
    }
    for (final plugin in pluginThemes) {
      final family =
          ((plugin.contributions['theme'] as Map?)?['fontFamily'] as String?);
      if (family != null && family.isNotEmpty) availableFonts.add(family);
    }
    final fontList = availableFonts.toList(growable: true)..sort();

    final iconPlugins = plugins.maybeWhen(
      data: (list) => list.all
          .where((plugin) => plugin.enabled && plugin.contributions['icons'] is Map)
          .toList(growable: false),
      orElse: () => const <PluginInfo>[],
    );

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Theme manager', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Choose a theme card, then customize fonts and icons. Changes are '
          'applied live.',
          style: TextStyle(color: t.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final choice in allThemes)
              _ThemeCard(
                choice: choice,
                selected: activeId == choice.id,
                onApply: () => notifier.setActiveThemeId(choice.id),
              ),
          ],
        ),
        const SizedBox(height: 28),
        Text('Font customization', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        DropdownButton<String>(
          value: settings.activeFontFamily ?? 'Geist',
          isExpanded: true,
          items: [
            for (final font in fontList)
              DropdownMenuItem<String>(value: font, child: Text(font)),
          ],
          onChanged: (value) {
            if (value == null) return;
            notifier.setActiveFontFamily(value == 'Geist' ? null : value);
          },
        ),
        const SizedBox(height: 28),
        Text('Icon customization', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        DropdownButton<String>(
          value: settings.activeIconPackId ?? '',
          isExpanded: true,
          items: [
            const DropdownMenuItem<String>(value: '', child: Text('Default Lumen')),
            for (final plugin in iconPlugins)
              DropdownMenuItem<String>(
                value: plugin.id,
                child: Text(plugin.name),
              ),
          ],
          onChanged: (value) {
            if (value == null || value.isEmpty) {
              notifier.setActiveIconPackId(null);
            } else {
              notifier.setActiveIconPackId(value);
            }
          },
        ),
      ],
    );
  }
}

class _ThemeChoice {
  const _ThemeChoice({
    required this.id,
    required this.label,
    required this.tokens,
  });

  final String? id;
  final String label;
  final PluginThemeTokens? tokens;
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.choice,
    required this.selected,
    required this.onApply,
  });

  final _ThemeChoice choice;
  final bool selected;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final palette = (choice.tokens ?? const PluginThemeTokens()).applyTo(lumenPaletteDark);

    return SizedBox(
      width: 220,
      child: Card(
        color: palette.surfaceHigh,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      choice.label,
                      style: TextStyle(
                        color: palette.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle, color: palette.primary, size: 18),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final color in <Color>[
                    palette.primary,
                    palette.secondary,
                    palette.background,
                    palette.surfaceContainer,
                    palette.onSurface,
                  ])
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.outlineVariant),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selected ? null : onApply,
                  child: Text(selected ? 'Active' : 'Apply'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}