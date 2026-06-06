import 'package:flutter/material.dart';

class PluginConfigScreen extends StatelessWidget {
  const PluginConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Plugin Configuration')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: 'Installed Plugins'),
          _PluginTile(
            name: 'Encryption Plugin',
            description: 'Provides AES‑256 encryption for journal entries.',
            colorScheme: cs,
          ),
          _PluginTile(
            name: 'Feedback Plugin',
            description: 'Collects anonymous usage feedback.',
            colorScheme: cs,
          ),
          _PluginTile(
            name: 'Storage Plugin',
            description: 'Handles persistent storage and indexing.',
            colorScheme: cs,
          ),
          const SizedBox(height: 32),
          _SectionHeader(title: 'Coming Soon'),
          _PluginTile(
            name: 'Cloud Sync',
            description: 'Sync entries across devices.',
            disabled: true,
            colorScheme: cs,
          ),
          _PluginTile(
            name: 'AI Summaries',
            description: 'Generate short summaries of long entries.',
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

class _PluginTile extends StatelessWidget {
  final String name;
  final String description;
  final bool disabled;
  final ColorScheme colorScheme;

  const _PluginTile({
    required this.name,
    required this.description,
    required this.colorScheme,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        title: Text(
          name,
          style: TextStyle(
            color: disabled ? cs.onSurfaceVariant : cs.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          description,
          style: TextStyle(
            color: disabled ? cs.onSurfaceVariant : cs.onSurfaceVariant,
          ),
        ),
        trailing: disabled
            ? Icon(Icons.lock, color: cs.onSurfaceVariant)
            : Icon(Icons.settings, color: cs.primary),
        onTap: disabled
            ? null
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Configure "$name"')),
                );
              },
      ),
    );
  }
}
