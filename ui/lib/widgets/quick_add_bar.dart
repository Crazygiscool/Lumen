import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../utils/id_utils.dart';

class QuickAddBar extends ConsumerStatefulWidget {
  final void Function()? onSaved;

  const QuickAddBar({super.key, this.onSaved});

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  final _controller = TextEditingController();
  final _passwordController = TextEditingController(text: 'default');
  late final TextEditingController _authorController;

  @override
  void initState() {
    super.initState();
    final userState = ref.read(userProvider);
    _authorController = TextEditingController(text: userState.currentUser);
  }

  void _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final parsed = ref.read(entriesProvider.notifier).parseTask(text);
    final cs = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Title', parsed['title'] ?? text),
            if (parsed['priority'] != null)
              _buildInfoRow('Priority', parsed['priority']),
            if (parsed['due_date'] != null)
              _buildInfoRow('Due', parsed['due_date']),
            if (parsed['tags'] != null && (parsed['tags'] as List).isNotEmpty)
              _buildInfoRow('Tags', (parsed['tags'] as List).join(', ')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final id = generateLumenId();
      
      // Build body with frontmatter but empty content
      final buf = StringBuffer();
      buf.writeln('---');
      buf.writeln('kind: task');
      if (parsed['priority'] != null) {
        buf.writeln('priority: ${parsed['priority']}');
      }
      if (parsed['due_date'] != null) {
        buf.writeln('due_date: ${parsed['due_date']}');
      }
      buf.writeln('---');
      buf.writeln('');

      await ref.read(entriesProvider.notifier).addEntry(
            buf.toString(), // Frontmatter only, empty body
            _authorController.text.trim(),
            _passwordController.text.trim(),
            id: id,
            kind: 'task',
            tags: (parsed['tags'] as List<dynamic>?)?.cast<String>() ?? [],
            displayTitle: (parsed['title'] as String?) ?? text,
          );

      _controller.clear();
      widget.onSaved?.call();
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _passwordController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Quick add task... (p:high #tag due:friday)',
                isDense: true,
                filled: true,
                fillColor: cs.surfaceContainer,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send, size: 18),
            onPressed: _submit,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
