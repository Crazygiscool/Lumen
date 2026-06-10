import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../utils/id_utils.dart';

class QuickNoteScreen extends ConsumerStatefulWidget {
  const QuickNoteScreen({super.key});

  @override
  ConsumerState<QuickNoteScreen> createState() => _QuickNoteScreenState();
}

class _QuickNoteScreenState extends ConsumerState<QuickNoteScreen> {
  late final TextEditingController _bodyController;
  late final TextEditingController _authorController;
  late final TextEditingController _passwordController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bodyController = TextEditingController();
    final userState = ref.read(userProvider);
    _authorController = TextEditingController(text: userState.currentUser ?? '');
    _passwordController = TextEditingController();
  }

  void _save() async {
    setState(() => _saving = true);
    try {
      final id = generateLumenId();
      await ref.read(entriesProvider.notifier).addEntry(
            _bodyController.text.trim(),
            _authorController.text.trim(),
            _passwordController.text.trim(),
            id: id,
            kind: 'note',
            tags: ['inbox'],
            displayTitle: _bodyController.text.trim().split('\n').first,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  }

  @override
  void dispose() {
    _bodyController.dispose();
    _authorController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final userState = ref.watch(userProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.note_add, size: 20, color: cs.primary),
                    const SizedBox(width: 8),
                    Text('Quick Note',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: userState.allUsers.any((u) => u.username == _authorController.text) ? _authorController.text : null,
                  decoration: const InputDecoration(
                    labelText: 'Author',
                    isDense: true,
                    prefixIcon: Icon(Icons.person_outline, size: 20),
                  ),
                  items: userState.allUsers.map((u) => DropdownMenuItem(
                    value: u.username,
                    child: Text(u.username),
                  )).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _authorController.text = v);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _bodyController,
                  decoration: const InputDecoration(
                    labelText: 'Note body',
                    hintText: 'Type your note...',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                if (_saving) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
