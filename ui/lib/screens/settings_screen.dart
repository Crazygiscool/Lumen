import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.setPassword),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.password,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.done),
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
    final userState = ref.read(userProvider);
    String? selectedUser = userState.currentUser;
    final passwordController = TextEditingController();
    
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.switchUser),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select a registered user profile and enter vault password to switch.'),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                value: selectedUser,
                decoration: InputDecoration(
                  labelText: l10n.currentUser,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                items: userState.allUsers.map((u) => DropdownMenuItem(
                  value: u.username,
                  child: Text(u.username),
                )).toList(),
                onChanged: (v) => setDialogState(() => selectedUser = v),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.vaultPassword,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.switchUser),
            ),
          ],
        ),
      ),
    );

    if (result == true && selectedUser != null) {
      final ok = ref.read(authProvider.notifier).unlock(passwordController.text.trim());
      if (ok) {
        await ref.read(userProvider.notifier).setUsername(selectedUser!);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Switched to user: $selectedUser')),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid password. Switch failed.')),
        );
      }
    }
  }

  Future<void> _addUser() async {
    final controller = TextEditingController();
    final passwordController = TextEditingController();
    
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.registerNewUser),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Add a new author profile to this vault. Requires vault password.'),
            const SizedBox(height: 24),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.newUsername,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person_add_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.vaultPassword,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.register),
          ),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      final ok = ref.read(authProvider.notifier).unlock(passwordController.text.trim());
      if (ok) {
        await ref.read(userProvider.notifier).addUser(controller.text.trim());
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New user registered')),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid password. Registration failed.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final userState = ref.watch(userProvider);
    final username = userState.currentUser ?? 'None';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: l10n.account),
          _SettingsTile(
            title: l10n.currentUser,
            subtitle: 'Logged in as: $username',
            icon: Icons.person_outline,
            colorScheme: cs,
            onTap: _setUsername,
          ),
          _SettingsTile(
            title: l10n.userManagement,
            subtitle: userState.isAdmin ? 'Register or switch users' : 'Admin only',
            icon: Icons.group_outlined,
            colorScheme: cs,
            disabled: !userState.isAdmin,
            onTap: _addUser,
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: l10n.security),
          if (!ref.read(authProvider.notifier).hasPassword())
            _SettingsTile(
              title: l10n.setPassword,
              subtitle: 'Create a password to lock your journal',
              icon: Icons.lock_outline,
              colorScheme: cs,
              onTap: _setPassword,
            )
          else ...[
            _SettingsTile(
              title: l10n.changePassword,
              subtitle: 'Update your existing password',
              icon: Icons.lock_reset,
              colorScheme: cs,
              onTap: _setPassword,
            ),
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: SwitchListTile(
                secondary: Icon(Icons.lock_open, color: cs.primary),
                title: Text(l10n.lockOnStart),
                subtitle: const Text('Require password on app launch'),
                value: _lockOnStart,
                onChanged: (v) => setState(() => _lockOnStart = v),
              ),
            ),
          ],
          const SizedBox(height: 32),
          _SectionHeader(title: l10n.general),
          _SettingsTile(
            title: l10n.theme,
            subtitle: 'Light / Dark (coming soon)',
            icon: Icons.brightness_6,
            disabled: true,
            colorScheme: cs,
          ),
          _SettingsTile(
            title: l10n.notifications,
            subtitle: 'Enable reminders (coming soon)',
            icon: Icons.notifications,
            disabled: true,
            colorScheme: cs,
          ),
          const SizedBox(height: 32),
          _SectionHeader(title: l10n.sync),
          _SettingsTile(
            title: l10n.syncSettings,
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
          _SectionHeader(title: l10n.data),
          _SettingsTile(
            title: l10n.exportImport,
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
            title: l10n.importStoic,
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
          _SectionHeader(title: l10n.advanced),
          _SettingsTile(
            title: l10n.developerMode,
            subtitle: 'Show debug tools',
            icon: Icons.developer_mode,
            disabled: true,
            colorScheme: cs,
          ),
          _SettingsTile(
            title: l10n.resetApp,
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
