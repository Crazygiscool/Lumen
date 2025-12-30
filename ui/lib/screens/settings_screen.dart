import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _SectionHeader(title: 'General'),
          _SettingsTile(
            title: 'Theme',
            subtitle: 'Light / Dark (coming soon)',
            icon: Icons.brightness_6,
            disabled: true,
          ),
          _SettingsTile(
            title: 'Notifications',
            subtitle: 'Enable reminders (coming soon)',
            icon: Icons.notifications,
            disabled: true,
          ),

          SizedBox(height: 32),
          _SectionHeader(title: 'Advanced'),
          _SettingsTile(
            title: 'Developer Mode',
            subtitle: 'Show debug tools',
            icon: Icons.developer_mode,
            disabled: true,
          ),
          _SettingsTile(
            title: 'Reset App',
            subtitle: 'Clear all data (coming soon)',
            icon: Icons.delete_forever,
            disabled: true,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.deepOrange,
              fontWeight: FontWeight.bold,
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

  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: disabled ? Colors.grey.shade200 : Colors.white,
      elevation: disabled ? 0 : 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: Icon(
          icon,
          color: disabled ? Colors.grey : Colors.deepOrange,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: disabled ? Colors.grey : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: disabled ? Colors.grey : Colors.brown,
          ),
        ),
        trailing: disabled
            ? const Icon(Icons.lock, color: Colors.grey)
            : const Icon(Icons.chevron_right, color: Colors.deepOrange),
        onTap: disabled
            ? null
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Open "$title" settings')),
                );
              },
      ),
    );
  }
}
