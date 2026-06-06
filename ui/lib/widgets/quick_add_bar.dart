import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

class QuickAddBar extends ConsumerStatefulWidget {
  final void Function()? onSaved;

  const QuickAddBar({super.key, this.onSaved});

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  final _controller = TextEditingController();
  final _passwordController = TextEditingController(text: 'default');
  final _authorController = TextEditingController(text: 'me');

  String _generateId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0xFFFFFFFF);
    return '${ts}_${rand.toRadixString(16).padLeft(8, '0')}';
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final parsed = ref.read(entriesProvider.notifier).parseTask(text);
    final id = _generateId();

    ref.read(entriesProvider.notifier).addEntry(
          text,
          _authorController.text.trim(),
          _passwordController.text.trim(),
          id: id,
          kind: 'task',
          tags: (parsed['tags'] as List<dynamic>?)?.cast<String>() ?? [],
          displayTitle: (parsed['title'] as String?) ?? text,
        );

    if (parsed['priority'] != null && parsed['priority'] is String) {
      ref
          .read(entriesProvider.notifier)
          .setEntryStatus(id, parsed['priority'] as String);
    }

    _controller.clear();
    widget.onSaved?.call();
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
