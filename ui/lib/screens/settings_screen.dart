import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'export_import_screen.dart';
import 'sync_settings_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: 'General'),
          _SettingsTile(
            title: 'Theme',
            subtitle: 'Light / Dark (coming soon)',
            icon: Icons.brightness_6,
            disabled: true,
            colorScheme: cs,
          ),
          _SettingsTile(
            title: 'Notifications',
            subtitle: 'Enable reminders (coming soon)',
            icon: Icons.notifications,
            disabled: true,
            colorScheme: cs,
          ),
          const SizedBox(height: 32),
          _SectionHeader(title: 'Sync'),
          _SettingsTile(
            title: 'Sync Settings',
            subtitle: 'Configure local sync directory',
            icon: Icons.sync,
            colorScheme: cs,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SyncSettingsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 32),
          _SectionHeader(title: 'Data'),
          _SettingsTile(
            title: 'Export / Import',
            subtitle: 'Backup or restore your entries',
            icon: Icons.transfer_within_a_station,
            colorScheme: cs,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ExportImportScreen(),
              ),
            ),
          ),
          const SizedBox(height: 32),
          _SectionHeader(title: 'Advanced'),
          _SettingsTile(
            title: 'Developer Mode',
            subtitle: 'Show debug tools',
            icon: Icons.developer_mode,
            disabled: true,
            colorScheme: cs,
          ),
          _SettingsTile(
            title: 'Reset App',
            subtitle: 'Clear all data (coming soon)',
            icon: Icons.delete_forever,
            disabled: true,
            colorScheme: cs,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool disabled;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colorScheme,
    this.disabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: Icon(
          icon,
          color: disabled ? cs.onSurfaceVariant : cs.primary,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: disabled ? cs.onSurfaceVariant : cs.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: disabled ? cs.onSurfaceVariant : cs.onSurfaceVariant,
          ),
        ),
        trailing: disabled
            ? Icon(Icons.lock, color: cs.onSurfaceVariant)
            : Icon(Icons.chevron_right, color: cs.primary),
        onTap: disabled ? null : (onTap ?? () {}),
      ),
    );
  }
}
