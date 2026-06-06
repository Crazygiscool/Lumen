import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/journal_entry.dart';
import '../core/providers.dart';
import '../utils/frontmatter.dart';
import 'board_screen.dart';
import 'entry_view_screen.dart';

class ProjectDetailScreen extends ConsumerStatefulWidget {
  final JournalEntry project;
  const ProjectDetailScreen({super.key, required this.project});

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  String? _decryptedText;
  bool _decrypting = false;
  final _passwordController = TextEditingController();
  ParsedEntry? _parsed;

  void _decrypt() {
    setState(() => _decrypting = true);
    try {
      final text = ref
          .read(entriesProvider.notifier)
          .decryptEntry(widget.project.id, _passwordController.text.trim());
      setState(() {
        _decryptedText = text;
        _parsed = parseFrontmatter(text);
        _decrypting = false;
      });
    } catch (e) {
      setState(() => _decrypting = false);
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.project;
    final allEntries = ref.watch(entriesProvider);
    final childTasks = allEntries
        .where((e) => e.parentProjectId == entry.id && e.kind == 'task')
        .toList();
    final milestones = allEntries
        .where((e) => e.parentProjectId == entry.id && e.kind == 'project')
        .toList();
    final title = entry.displayTitle.isNotEmpty ? entry.displayTitle : entry.id;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Metadata
          Row(children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Text('project',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant)),
            ),
            const SizedBox(width: 8),
            Text(entry.author,
                style: TextStyle(color: cs.onSurfaceVariant)),
            const Spacer(),
          ]),
          const SizedBox(height: 8),
          if (entry.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 4,
                children: entry.tags
                    .map((t) => Chip(
                          label: Text(t,
                              style: const TextStyle(fontSize: 11)),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ))
                    .toList(),
              ),
            ),

          // Decrypt section
          if (_decryptedText != null && _parsed != null) ...[
            if (_parsed!.body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_parsed!.body,
                    style: const TextStyle(fontSize: 15)),
              ),
          ] else ...[
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _decrypting ? null : _decrypt,
                child: _decrypting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2),
                      )
                    : const Text('Decrypt'),
              ),
            ]),
            const SizedBox(height: 16),
          ],

          // Actions
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.dashboard, size: 18),
              label: const Text('Open Kanban Board'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const BoardScreen()),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Milestones
          if (milestones.isNotEmpty) ...[
            Text('Milestones',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: cs.onSurface)),
            const SizedBox(height: 8),
            ...milestones.map((m) => ListTile(
                  leading: Icon(Icons.flag, color: cs.primary),
                  title: Text(m.displayTitle.isNotEmpty
                      ? m.displayTitle
                      : m.id),
                  subtitle: Text(m.author,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => EntryViewScreen(entry: m)),
                  ),
                )),
            const SizedBox(height: 16),
          ],

          // Child tasks
          Text('Tasks (${childTasks.length})',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: cs.onSurface)),
          const SizedBox(height: 8),
          if (childTasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('No tasks assigned to this project',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            )
          else
            ...childTasks.map((t) => Card(
                  child: ListTile(
                    leading: Icon(
                      t.status == 'done'
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: t.status == 'done'
                          ? Colors.green
                          : cs.onSurfaceVariant,
                      size: 20,
                    ),
                    title: Text(
                      t.displayTitle.isNotEmpty ? t.displayTitle : t.id,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Row(children: [
                      if (t.priority != null)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: t.priority == 'high'
                                    ? cs.error
                                    : cs.outline),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(t.priority!,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: t.priority == 'high'
                                      ? cs.error
                                      : cs.onSurfaceVariant)),
                        ),
                      if (t.dueDate != null)
                        Text(t.dueDate!,
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant)),
                    ]),
                    trailing: PopupMenuButton<String>(
                      onSelected: (status) {
                        ref
                            .read(entriesProvider.notifier)
                            .setEntryStatus(t.id, status);
                      },
                      itemBuilder: (_) {
                        return ['todo', 'in_progress', 'done']
                            .map((s) => PopupMenuItem<String>(
                                  value: s,
                                  child: Text(s.replaceAll('_', ' ')),
                                ))
                            .toList();
                      },
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => EntryViewScreen(entry: t)),
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}
