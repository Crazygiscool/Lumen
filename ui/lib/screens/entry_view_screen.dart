import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/journal_entry.dart';
import '../core/providers.dart';
import '../utils/frontmatter.dart';
import '../utils/wiki_links.dart';
import 'home_screen.dart';
import 'new_entry_screen.dart';

class EntryViewScreen extends ConsumerStatefulWidget {
  final JournalEntry entry;

  const EntryViewScreen({super.key, required this.entry});

  @override
  ConsumerState<EntryViewScreen> createState() => _EntryViewScreenState();
}

class _EntryViewScreenState extends ConsumerState<EntryViewScreen> {
  String? _decryptedText;
  bool _decrypting = false;
  final _passwordController = TextEditingController();
  ParsedEntry? _parsed;
  late JournalEntry _currentEntry;

  @override
  void initState() {
    super.initState();
    _currentEntry = widget.entry;
  }

  void _attemptDecrypt() async {
    if (_passwordController.text.trim().isEmpty) return;
    setState(() => _decrypting = true);

    try {
      final text = await ref
          .read(entriesProvider.notifier)
          .decryptEntryAsync(_currentEntry.id, _passwordController.text.trim());

      setState(() {
        _decryptedText = text;
        _parsed = parseFrontmatter(text);
        _decrypting = false;
      });
    } catch (e) {
      setState(() => _decrypting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to decrypt: $e")),
      );
    }
  }

  void _editEntry() async {
    if (_decryptedText == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please decrypt the entry before editing")),
      );
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewEntryScreen(
          entryToEdit: _currentEntry,
          initialText: _decryptedText,
        ),
      ),
    );

    if (result == true) {
      // Refresh local entry data
      final updated = ref.read(entriesProvider).firstWhere((e) => e.id == _currentEntry.id);
      setState(() {
        _currentEntry = updated;
        // Re-decrypt with same password if possible
        try {
          final text = ref.read(entriesProvider.notifier).decryptEntry(_currentEntry.id, _passwordController.text.trim());
          _decryptedText = text;
          _parsed = parseFrontmatter(text);
        } catch (_) {
          _decryptedText = null;
          _parsed = null;
        }
      });
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Widget _buildHistoryTimeline(ColorScheme cs, JournalEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Icon(Icons.history, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Edit History',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
          ...entry.history.reversed.map((record) {
            final ts = record.timestamp;
            final date = ts.length >= 10 ? ts.substring(0, 10) : ts;
            final time = ts.length >= 19 ? ts.substring(11, 19) : '';
            return Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 0),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 20,
                      child: Column(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Container(
                              width: 2,
                              color: cs.outlineVariant.withValues(alpha: 0.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.reason,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$date • $time • ${record.author}',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = _currentEntry;
    final priority = entry.priority ?? _parsed?.metadata['priority'];
    final title = _parsed?.metadata['title'] ?? entry.displayTitle;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final focusMode = ref.watch(focusModeProvider);

    return Scaffold(
      appBar: focusMode ? null : AppBar(
        title: Text(title.isNotEmpty ? title : 'Entry View'),
        actions: [
          if (_decryptedText != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Entry',
              onPressed: _editEntry,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (!focusMode) ...[
                Row(
                  children: [
                    _KindBadge(kind: entry.kind, cs: cs),
                    const SizedBox(width: 12),
                    if (entry.mood != null)
                      _MoodBadge(mood: entry.mood!, cs: cs),
                    if (priority != null) ...[
                      const SizedBox(width: 12),
                      _PriorityBadge(priority: priority, cs: cs),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  title.isNotEmpty ? title : "(Untitled Entry)",
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.person_outline, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(entry.provenance.author, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    const SizedBox(width: 16),
                    Icon(Icons.calendar_today_outlined, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(entry.provenance.timestamp, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
                if (entry.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Wrap(
                      spacing: 8,
                      children: entry.tags
                          .map((t) => Chip(
                                label: Text('#$t'),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                labelStyle: TextStyle(fontSize: 11, color: cs.onSecondaryContainer),
                                backgroundColor: cs.secondaryContainer.withValues(alpha: 0.3),
                                side: BorderSide.none,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ))
                          .toList(),
                    ),
                  ),
                const SizedBox(height: 32),
              ],
              
              if (_decryptedText == null)
                _buildUnlockUI(cs, theme)
              else
                _buildContentUI(cs, theme, entry),
                
              if (!focusMode && _decryptedText != null && entry.kind == 'journal' && entry.history.isNotEmpty)
                _buildHistoryTimeline(cs, entry),
                
              const SizedBox(height: 64),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnlockUI(ColorScheme cs, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(Icons.lock_person_outlined, size: 64, color: cs.primary),
          const SizedBox(height: 24),
          Text(
            "Encrypted Content",
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "Enter your vault password to view this entry.",
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: "Password",
              prefixIcon: const Icon(Icons.lock_outline),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              filled: true,
              fillColor: cs.surface,
            ),
            onSubmitted: (_) => _attemptDecrypt(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _decrypting ? null : _attemptDecrypt,
              icon: _decrypting 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.key_outlined),
              label: const Text("Unlock Entry", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentUI(ColorScheme cs, ThemeData theme, JournalEntry entry) {
    if (_parsed == null) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarkdownBody(
          data: renderWikiLinks(_parsed!.body),
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            h1: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            h2: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            code: TextStyle(
              backgroundColor: cs.surfaceContainerHigh,
              fontFamily: 'monospace',
              fontSize: 14,
            ),
            codeblockDecoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onTapLink: (text, href, title) {
            if (href != null) {
              final target = parseWikiLinkTap(href);
              if (target != null) {
                final allEntries = ref.read(entriesProvider);
                final matched = allEntries.where((e) =>
                    e.displayTitle.toLowerCase() == target.toLowerCase() ||
                    e.id == target);
                if (matched.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EntryViewScreen(entry: matched.first),
                    ),
                  );
                }
              }
            }
          },
        ),
      ],
    );
  }
}

class _KindBadge extends StatelessWidget {
  final String kind;
  final ColorScheme cs;
  const _KindBadge({required this.kind, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        kind.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: cs.onPrimaryContainer,
          fontFamily: 'Geist',
        ),
      ),
    );
  }
}

class _MoodBadge extends StatelessWidget {
  final String mood;
  final ColorScheme cs;
  const _MoodBadge({required this.mood, required this.cs});

  @override
  Widget build(BuildContext context) {
    final emoji = switch (mood) {
      'happy' => '😊',
      'neutral' => '😐',
      'sad' => '😔',
      'angry' => '😡',
      'tired' => '😴',
      _ => '❓',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(mood.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final String priority;
  final ColorScheme cs;
  const _PriorityBadge({required this.priority, required this.cs});

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      'high' => cs.error,
      'medium' => cs.primary,
      _ => cs.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.priority_high, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            priority.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'Geist',
            ),
          ),
        ],
      ),
    );
  }
}
