import 'package:flutter/material.dart';

class PluginConfigScreen extends StatelessWidget {
  const PluginConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugin Configuration'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _SectionHeader(title: 'Installed Plugins'),
          _PluginTile(
            name: 'Encryption Plugin',
            description: 'Provides AES‑256 encryption for journal entries.',
          ),
          _PluginTile(
            name: 'Feedback Plugin',
            description: 'Collects anonymous usage feedback.',
          ),
          _PluginTile(
            name: 'Storage Plugin',
            description: 'Handles persistent storage and indexing.',
          ),

          SizedBox(height: 32),
          _SectionHeader(title: 'Coming Soon'),
          _PluginTile(
            name: 'Cloud Sync',
            description: 'Sync entries across devices.',
            disabled: true,
          ),
          _PluginTile(
            name: 'AI Summaries',
            description: 'Generate short summaries of long entries.',
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

class _PluginTile extends StatelessWidget {
  final String name;
  final String description;
  final bool disabled;

  const _PluginTile({
    required this.name,
    required this.description,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: disabled ? Colors.grey.shade200 : Colors.white,
      elevation: disabled ? 0 : 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        title: Text(
          name,
          style: TextStyle(
            color: disabled ? Colors.grey : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          description,
          style: TextStyle(
            color: disabled ? Colors.grey : Colors.brown,
          ),
        ),
        trailing: disabled
            ? const Icon(Icons.lock, color: Colors.grey)
            : const Icon(Icons.settings, color: Colors.deepOrange),
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
