import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../journal/quotes.dart';
import '../state/providers.dart';
import '../theme/lumen_colors.dart';
import '../widgets/path_picker.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final vault = ref.watch(journalVaultProvider);
    final t = LumenColors.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 20),

        _Section(
          title: 'Appearance',
          children: [
            SegmentedButton<ThemeSource>(
              segments: const [
                ButtonSegment(
                  value: ThemeSource.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeSource.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeSource.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
              ],
              selected: {settings.themeSource},
              onSelectionChanged: (s) => notifier.setThemeSource(s.first),
            ),
          ],
        ),

        _Section(
          title: 'Journal',
          children: [
            _InfoRow(
              icon: vault.unlocked ? Icons.lock_open : Icons.lock_outline,
              label: 'Status',
              value: vault.unlocked ? 'Unlocked' : 'Locked',
            ),
            _InfoRow(
              icon: Icons.folder_outlined,
              label: 'Location',
              value: vault.root ?? settings.journalVaultPath ?? 'Not set',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showPathPicker(
                      context,
                      mode: PathPickerMode.directory,
                      initialPath:
                          vault.root ?? settings.journalVaultPath,
                      title: 'Choose journal folder',
                    );
                    if (picked != null) {
                      if (vault.unlocked) {
                        await ref.read(journalVaultProvider.notifier).lock();
                      }
                      notifier.setJournalVaultPath(picked);
                    }
                  },
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: const Text('Change folder'),
                ),
                if (vault.unlocked)
                  FilledButton.tonalIcon(
                    onPressed: () => ref
                        .read(journalVaultProvider.notifier)
                        .lock(),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Lock now'),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => ref
                        .read(selectedSectionProvider.notifier)
                        .select(LumenSection.journal),
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Unlock'),
                  ),
              ],
            ),
          ],
        ),

        _Section(
          title: 'Dashboard',
          children: [
            Row(
              children: [
                const Icon(Icons.format_quote_outlined, size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Quote source'),
                      Text(
                        'Offline uses a bundled Harry Potter quote list. Online fetches a public dataset (needs internet).',
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                DropdownButton<QuoteSource>(
                  value: ref.watch(dashboardPrefsProvider).quoteSource,
                  items: [
                    for (final s in QuoteSource.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(dashboardPrefsProvider.notifier).setQuoteSource(v);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(dashboardPrefsProvider.notifier).resetLayout();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Dashboard layout reset')),
                    );
                  },
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('Reset card order'),
                ),
              ],
            ),
          ],
        ),

        _Section(
          title: 'Plugins',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.extension_outlined),
              title: const Text('Installed plugins'),
              subtitle: const Text(
                'Built-in and on-disk plugins. Toggle which ones run.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ref
                  .read(selectedSectionProvider.notifier)
                  .select(LumenSection.plugins),
            ),
          ],
        ),

        _Section(
          title: 'About',
          children: [
            Text(
              'Lumen\n\n'
              'Journal notes are encrypted on disk with AES-256-GCM and an '
              'Argon2id-derived key. Imports are re-encrypted into the '
              'journal; nothing is written in plaintext.',
              style: TextStyle(color: t.onSurfaceVariant),
            ),
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
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: t.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(color: t.onSurfaceVariant)),
          ),
          Expanded(
            child: SelectableText(
              value,
              maxLines: 2,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
