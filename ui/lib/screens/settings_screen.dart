import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'export_import_screen.dart';
import 'stoic_import_screen.dart';
import 'sync_settings_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _lockOnStart = true;

  Future<void> _setPassword() async {
    final controller = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Set Password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New password',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (pw == null || pw.isEmpty) return;

    final ok = ref.read(authProvider.notifier).setPassword(pw);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Password set' : 'Failed to set password')),
    );
    setState(() {});
  }

  Future<void> _setUsername() async {
    final currentUsername = ref.read(userProvider);
    final controller = TextEditingController(text: currentUsername);
    final username = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Set Master Username'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Username',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (username == null || username.trim().isEmpty) return;

    ref.read(userProvider.notifier).setUsername(username.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Master Username updated')),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final username = ref.watch(userProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: 'Account'),
          _SettingsTile(
            title: 'Master Username',
            subtitle: 'Default author for new entries: $username',
            icon: Icons.person_outline,
            colorScheme: cs,
            onTap: _setUsername,
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: 'Security'),
          if (!ref.read(authProvider.notifier).hasPassword())
            _SettingsTile(
              title: 'Set Password',
              subtitle: 'Create a password to lock your journal',
              icon: Icons.lock_outline,
              colorScheme: cs,
              onTap: _setPassword,
            )
          else ...[
            _SettingsTile(
              title: 'Change Password',
              subtitle: 'Update your existing password',
              icon: Icons.lock_reset,
              colorScheme: cs,
              onTap: _setPassword,
            ),
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: SwitchListTile(
                secondary: Icon(Icons.lock_open, color: cs.primary),
                title: const Text('Lock on Start'),
                subtitle: const Text('Require password on app launch'),
                value: _lockOnStart,
                onChanged: (v) => setState(() => _lockOnStart = v),
              ),
            ),
          ],
          const SizedBox(height: 32),
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
          _SettingsTile(
            title: 'Import from Stoic',
            subtitle: 'Import entries from a Stoic iOS export',
            icon: Icons.auto_stories,
            colorScheme: cs,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const StoicImportScreen(),
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
