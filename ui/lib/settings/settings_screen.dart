import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/lumen_colors.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final gtkAsync = ref.watch(gtkThemeProvider);
    final gtk = gtkAsync.value;

    final gtkReadout = gtkAsync.isLoading
        ? ('Detecting desktop theme…', Icons.hourglass_top)
        : (gtk == null || !gtk.available)
        ? ('GTK theme not detected', Icons.help_outline)
        : (
            'GTK ${(gtk.colorScheme ?? 'default')} · accent ${gtk.accentName ?? '—'}',
            Icons.desktop_windows_outlined,
          );

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: LumenColors.of(context).primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.auto_awesome,
              color: LumenColors.of(context).primary,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'Lumen',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
        ),
        Center(
          child: Text(
            'Explorer-first OS workbench · v2.4.0',
            style: TextStyle(
              fontSize: 12,
              color: LumenColors.of(context).onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 28),
        _Section(
          title: 'Appearance',
          children: [
            _Row(
              label: 'Theme',
              child: SegmentedButton<ThemeSource>(
                segments: [
                  ButtonSegment(
                    value: ThemeSource.system,
                    icon: Icon(Icons.brightness_auto_outlined, size: 16),
                    label: const Text('System'),
                  ),
                  ButtonSegment(
                    value: ThemeSource.dark,
                    icon: const Icon(Icons.dark_mode_outlined, size: 16),
                    label: const Text('Dark'),
                  ),
                  ButtonSegment(
                    value: ThemeSource.light,
                    icon: const Icon(Icons.light_mode_outlined, size: 16),
                    label: const Text('Light'),
                  ),
                ],
                selected: {settings.themeSource},
                onSelectionChanged: (s) => notifier.setThemeSource(s.first),
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            _Row(
              label: 'Match desktop accent',
              valueText: 'Follow GTK accent colour',
              child: Switch(
                value: settings.matchGtkAccent,
                onChanged: notifier.setMatchGtkAccent,
              ),
            ),
            _Row(
              label: 'Desktop theme',
              valueText: null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    gtkReadout.$2,
                    size: 15,
                    color: LumenColors.of(context).onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      gtkReadout.$1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'Geist Mono',
                        color: LumenColors.of(context).onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh, size: 15),
                    tooltip: 'Re-read desktop theme',
                    onPressed: () => ref.invalidate(gtkThemeProvider),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _Section(
          title: 'Shortcuts',
          children: [
            _Row(label: 'Command palette', valueText: 'Ctrl+P'),
            _Row(label: 'Sections', valueText: 'Ctrl+1 … Ctrl+6'),
          ],
        ),
        const SizedBox(height: 20),
        const _Section(
          title: 'About',
          children: [
            _Row(label: 'Linux, macOS, Windows', valueText: 'supported'),
            _Row(label: 'Encryption', valueText: 'Argon2id + AES-256-GCM'),
            _Row(label: 'Native core', valueText: 'Rust · fscore · lumen_core'),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: LumenColors.of(context).outline,
                ),
              ),
            ),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(indent: 16, endIndent: 16),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, this.child, this.valueText});
  final String label;
  final Widget? child;
  final String? valueText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          if (valueText != null)
            Text(
              valueText!,
              style: TextStyle(
                fontSize: 13,
                color: LumenColors.of(context).onSurfaceVariant,
              ),
            ),
          if (child != null) Flexible(child: child!),
        ],
      ),
    );
  }
}
