import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../utils/journal_prompts.dart';

class NewEntryScreen extends ConsumerStatefulWidget {
  final String initialKind;
  const NewEntryScreen({super.key, this.initialKind = 'journal'});

  @override
  ConsumerState<NewEntryScreen> createState() => _NewEntryScreenState();
}

class _NewEntryScreenState extends ConsumerState<NewEntryScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _authorController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tagsController = TextEditingController();

  late String _kind;
  String _priority = 'medium';
  String? _mood;
  bool _encryptTitle = false;
  final _kinds = ['journal', 'note', 'task', 'project'];
  final _priorities = ['low', 'medium', 'high'];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
  }

  static const _moods = [
    ('😊', 'happy'),
    ('😐', 'neutral'),
    ('😔', 'sad'),
    ('😡', 'angry'),
    ('😴', 'tired'),
  ];

  String _generateId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0xFFFFFFFF);
    return '${ts}_${rand.toRadixString(16).padLeft(8, '0')}';
  }

  String _buildBody() {
    switch (_kind) {
      case 'journal':
        return _bodyController.text.trim();
      case 'note':
      case 'task':
      case 'project':
        final buf = StringBuffer();
        buf.writeln('---');
        buf.writeln('kind: $_kind');
        if (_titleController.text.trim().isNotEmpty) {
          buf.writeln('title: ${_titleController.text.trim()}');
        }
        if (_kind == 'task') {
          buf.writeln('priority: $_priority');
        }
        buf.writeln('---');
        buf.writeln('');
        buf.write(_bodyController.text.trim());
        return buf.toString();
      default:
        return _bodyController.text.trim();
    }
  }

  void _saveEntry() async {
    setState(() => _saving = true);

    try {
      final tags = _tagsController.text.trim().isEmpty
          ? <String>[]
          : _tagsController.text
              .split(',')
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList();

      final id = _generateId();

      ref.read(entriesProvider.notifier).addEntry(
            _buildBody(),
            _authorController.text.trim(),
            _passwordController.text.trim(),
            id: id,
            kind: _kind,
            tags: tags,
            displayTitle:
                _encryptTitle ? '' : _titleController.text.trim(),
          );

      if (_kind == 'journal' && _mood != null) {
        ref.read(entriesProvider.notifier).setEntryMood(id, _mood);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save entry: $e")),
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _authorController.dispose();
    _passwordController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Entry")),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: "Kind"),
              items: _kinds
                  .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _kind = v);
              },
            ),
            const SizedBox(height: 12),
            if (_kind == 'journal') ...[
              // Mood picker
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _moods.map((m) {
                    final (emoji, value) = m;
                    final selected = _mood == value;
                    return GestureDetector(
                      onTap: () => setState(
                          () => _mood = selected ? null : value),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: selected ? 1.0 : 0.4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Text(emoji, style: const TextStyle(fontSize: 28)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              // Journal prompt
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 16,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          randomPrompt(),
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_kind != 'journal')
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: "Title"),
                ),
              ),
            if (_kind == 'task')
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  initialValue: _priority,
                  decoration: const InputDecoration(labelText: "Priority"),
                  items: _priorities
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _priority = v);
                  },
                ),
              ),
            if (_kind != 'journal')
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Show title in list',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Switch(
                      value: !_encryptTitle,
                      onChanged: (v) =>
                          setState(() => _encryptTitle = !v),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: _authorController,
              decoration: const InputDecoration(labelText: "Author"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: "Tags (comma-separated)",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _bodyController,
                decoration: const InputDecoration(
                  labelText: "Body",
                  alignLabelWithHint: true,
                ),
                maxLines: null,
                expands: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveEntry,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text("Save Entry"),
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
