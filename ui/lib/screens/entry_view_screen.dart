import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/journal_entry.dart';
import '../core/providers.dart';
import '../utils/frontmatter.dart';
import '../utils/wiki_links.dart';
import 'home_screen.dart';

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

  void _attemptDecrypt() {
    setState(() => _decrypting = true);

    try {
      final text = ref
          .read(entriesProvider.notifier)
          .decryptEntry(widget.entry.id, _passwordController.text.trim());

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

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Widget _buildHistoryTimeline(ColorScheme cs, JournalEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.history, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Edit History',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
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
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 16,
                      child: Column(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Container(
                              width: 1,
                              color: cs.outlineVariant.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.reason,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            '$date $time — ${record.author}',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
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
    final entry = widget.entry;
    final title = _parsed?.metadata['title'];
    final cs = Theme.of(context).colorScheme;
    final focusMode = ref.watch(focusModeProvider);

    return Scaffold(
      appBar: focusMode ? null : AppBar(title: Text(title ?? entry.id)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!focusMode) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(4),
                          border:
                              Border.all(color: cs.outlineVariant, width: 1),
                        ),
                        child: Text(
                          entry.kind,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                            fontFamily: 'Geist',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Author: ${entry.provenance.author}",
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Created: ${entry.provenance.timestamp}",
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (entry.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 4,
                        children: entry.tags
                            .map((t) => Chip(
                                  label: Text(t),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ))
                            .toList(),
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
                Expanded(
                  child: _decryptedText != null && _parsed != null
                      ? ListView(
                          children: [
                            if (!focusMode &&
                                _parsed!.metadata['priority'] != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Chip(
                                  label: Text(
                                    'Priority: ${_parsed!.metadata['priority']}',
                                  ),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            Markdown(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              data: renderWikiLinks(_parsed!.body),
                              selectable: true,
                              onTapLink: (text, href, title) {
                                if (href != null) {
                                  final target = parseWikiLinkTap(href);
                                  if (target != null) {
                                    final allEntries =
                                        ref.read(entriesProvider);
                                    final matched = allEntries.where((e) =>
                                        e.displayTitle.toLowerCase() ==
                                            target.toLowerCase() ||
                                        e.id == target);
                                    if (matched.isNotEmpty) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => EntryViewScreen(
                                              entry: matched.first),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                            ),
                            if (!focusMode &&
                                entry.kind == 'journal' &&
                                entry.history.isNotEmpty)
                              _buildHistoryTimeline(cs, entry),
                          ],
                        )
                      : SingleChildScrollView(
                          child: Text(
                            _decryptedText ??
                                "This entry is encrypted.\nEnter password to decrypt.",
                            style: TextStyle(
                              fontSize: 16,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 20),
                if (!focusMode || _decryptedText == null)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: "Password",
                            hintText: "Enter encryption password",
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _decrypting ? null : _attemptDecrypt,
                        child: _decrypting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text("Decrypt"),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
