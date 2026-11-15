import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/lumen_colors.dart';

/// AI privacy settings and model management.
///
/// Everything runs through the local Ollama server; nothing leaves the
/// user's machine unless they configure a different URL.
class AiSettingsScreen extends ConsumerWidget {
  const AiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final t = LumenColors.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('AI & Local Models', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 20),

        _Section(
          title: 'AI Features',
          children: [
            SwitchListTile(
              title: const Text('Enable AI features'),
              subtitle: const Text(
                'Chat, summarization, and RAG (retrieval-augmented generation) '
                'against your local notes.',
              ),
              value: settings.aiEnabled,
              onChanged: notifier.setAiEnabled,
              secondary: const Icon(Icons.psychology_outlined),
            ),
            const Divider(),
            _InfoRow(
              icon: Icons.info_outlined,
              label: 'Privacy',
              value: 'Everything runs through your local Ollama server '
                  '(default http://localhost:11434). No note text is sent to '
                  'any external service unless you change the Ollama URL.',
            ),
          ],
        ),

        _Section(
          title: 'Ollama Server',
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Ollama base URL',
                hintText: 'http://localhost:11434',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: settings.aiOllamaUrl),
              onChanged: notifier.setAiOllamaUrl,
            ),
            const SizedBox(height: 8),
            Text(
              'The URL of the Ollama server running on this machine. '
              'Leave blank to use the default (http://localhost:11434).',
              style: TextStyle(
                color: t.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),

        _Section(
          title: 'Default Models',
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Default chat model',
                hintText: 'llama3',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: settings.aiDefaultModel),
              onChanged: notifier.setAiDefaultModel,
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Embedding model (RAG)',
                hintText: 'nomic-embed-text',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: settings.aiEmbeddingModel),
              onChanged: notifier.setAiEmbeddingModel,
            ),
            const SizedBox(height: 8),
            Text(
              'The chat model is used for summarization and Q&A. The embedding '
              'model re-ranks search results for context-aware answers. Leave '
              'blank to use Ollama defaults.',
              style: TextStyle(
                color: t.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),

        _Section(
          title: 'How AI works in Lumen',
          children: [
            Text(
              'Lumen only sends notes you explicitly select as context. '
              'When you ask a question with RAG, Lumen first finds relevant '
              'notes using local full-text search, then sends those notes '
              '(and your question) to the local Ollama model. Nothing leaves '
              'your machine unless you configure a remote Ollama URL.',
              style: TextStyle(
                color: t.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ollama connection test not yet implemented'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Test connection'),
                ),
              ],
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
  const _InfoRow({required this.icon, required this.label, required this.value});
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
