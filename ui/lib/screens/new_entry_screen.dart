import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/journal_entry.dart';
import '../core/providers.dart';
import '../utils/id_utils.dart';
import '../utils/journal_prompts.dart';

class NewEntryScreen extends ConsumerStatefulWidget {
  final String initialKind;
  final JournalEntry? entryToEdit;
  final String? initialText;

  const NewEntryScreen({
    super.key, 
    this.initialKind = 'journal', 
    this.entryToEdit,
    this.initialText,
  });

  @override
  ConsumerState<NewEntryScreen> createState() => _NewEntryScreenState();
}

class _NewEntryScreenState extends ConsumerState<NewEntryScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final TextEditingController _authorController;
  late final TextEditingController _passwordController;
  late final TextEditingController _tagsController;

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
    _kind = widget.entryToEdit?.kind ?? widget.initialKind;
    _titleController = TextEditingController(text: widget.entryToEdit?.displayTitle ?? '');
    _bodyController = TextEditingController(text: widget.initialText ?? '');
    
    // Auto-fill author with master username if it's a new entry
    final masterUsername = ref.read(userProvider);
    _authorController = TextEditingController(
      text: widget.entryToEdit?.provenance.author ?? masterUsername,
    );

    _passwordController = TextEditingController();
    _tagsController = TextEditingController(text: widget.entryToEdit?.tags.join(', ') ?? '');
    _mood = widget.entryToEdit?.mood;
    _encryptTitle = widget.entryToEdit?.displayTitle.isEmpty ?? false;
    
    if (widget.entryToEdit?.priority != null) {
      _priority = widget.entryToEdit!.priority!;
    }
  }

  static const _moods = [
    ('😊', 'happy'),
    ('😐', 'neutral'),
    ('😔', 'sad'),
    ('😡', 'angry'),
    ('😴', 'tired'),
  ];

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
    // Only require body for journal entries
    if (_kind == 'journal' && _bodyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Journal entry cannot be empty")),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final tags = _tagsController.text.trim().isEmpty
          ? <String>[]
          : _tagsController.text
              .split(',')
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList();

      final notifier = ref.read(entriesProvider.notifier);
      final id = widget.entryToEdit?.id ?? generateLumenId();

      if (widget.entryToEdit != null) {
        await notifier.updateEntry(
          id,
          _buildBody(),
          _authorController.text.trim(),
          _passwordController.text.trim(),
          kind: _kind,
          tags: tags,
          displayTitle: _encryptTitle ? '' : _titleController.text.trim(),
        );
      } else {
        await notifier.addEntry(
          _buildBody(),
          _authorController.text.trim(),
          _passwordController.text.trim(),
          id: id,
          kind: _kind,
          tags: tags,
          displayTitle: _encryptTitle ? '' : _titleController.text.trim(),
        );
      }

      if (_kind == 'journal' && _mood != null) {
        notifier.setEntryMood(id, _mood);
      }

      if (mounted) Navigator.pop(context, true);
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isEdit = widget.entryToEdit != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? "Edit Entry" : "New Entry"),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveEntry,
            child: _saving 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text("SAVE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Kind and Metadata
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _kind,
                      decoration: InputDecoration(
                        labelText: "Entry Kind",
                        prefixIcon: const Icon(Icons.category_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: _kinds
                          .map((k) => DropdownMenuItem(value: k, child: Text(k.toUpperCase(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _kind = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (_kind == 'task')
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _priority,
                        decoration: InputDecoration(
                          labelText: "Priority",
                          prefixIcon: const Icon(Icons.priority_high),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: _priorities
                            .map((p) => DropdownMenuItem(value: p, child: Text(p.toUpperCase(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _priority = v);
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              
              if (_kind == 'journal') ...[
                Text("How are you feeling?", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _moods.map((m) {
                    final (emoji, value) = m;
                    final selected = _mood == value;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: InkWell(
                          onTap: () => setState(() => _mood = selected ? null : value),
                          borderRadius: BorderRadius.circular(16),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected ? cs.primary : cs.outlineVariant,
                                width: 2,
                              ),
                            ),
                            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 32))),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.secondaryContainer),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline, size: 20, color: cs.secondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          randomPrompt(),
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.onSecondaryContainer,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              if (_kind != 'journal') ...[
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: "Title",
                    hintText: "Enter a descriptive title",
                    prefixIcon: const Icon(Icons.title),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.visibility_off_outlined, size: 20),
                    const SizedBox(width: 12),
                    const Text('Hide title in entry lists (encrypt title)'),
                    const Spacer(),
                    Switch(
                      value: _encryptTitle,
                      onChanged: (v) => setState(() => _encryptTitle = v),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _authorController,
                      decoration: InputDecoration(
                        labelText: "Author",
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "Password",
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        hintText: isEdit ? "Enter to confirm" : "Set password",
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _tagsController,
                decoration: InputDecoration(
                  labelText: "Tags",
                  hintText: "comma, separated, tags",
                  prefixIcon: const Icon(Icons.tag),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),
              Text("Body Content", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyController,
                decoration: InputDecoration(
                  hintText: "Write your content here... (Markdown supported)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                  fillColor: cs.surfaceContainerLow,
                ),
                maxLines: 15,
                minLines: 8,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _saving ? null : _saveEntry,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _saving 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
                label: Text(isEdit ? "Update Entry" : "Create Entry", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 64),
            ],
          ),
        ),
      ),
    );
  }
}
