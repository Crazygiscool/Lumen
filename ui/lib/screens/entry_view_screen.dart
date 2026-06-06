import 'package:flutter/material.dart';
import '../core/models/journal_entry.dart';
import '../core/lumen_core.dart';

class EntryViewScreen extends StatefulWidget {
  final JournalEntry entry;
  final LumenCore lumen;

  const EntryViewScreen({
    super.key,
    required this.entry,
    required this.lumen,
  });

  @override
  State<EntryViewScreen> createState() => _EntryViewScreenState();
}

class _EntryViewScreenState extends State<EntryViewScreen> {
  String? _decryptedText;
  bool _decrypting = false;
  final _passwordController = TextEditingController();

  void _attemptDecrypt() {
    setState(() => _decrypting = true);

    try {
      final text = widget.entry
          .decryptText(_passwordController.text.trim(), widget.lumen);

      setState(() {
        _decryptedText = text;
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
  Widget build(BuildContext context) {
    final entry = widget.entry;

    return Scaffold(
      appBar: AppBar(title: Text(entry.id)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.kind,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "Author: ${entry.provenance.author}",
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(width: 8),
                Text(
                  "Created: ${entry.provenance.timestamp}",
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
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
                            label: Text(t, style: const TextStyle(fontSize: 11)),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ))
                      .toList(),
                ),
              ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _decryptedText ??
                      "This entry is encrypted.\nEnter password to decrypt.",
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "Password"),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _decrypting ? null : _attemptDecrypt,
                  child: _decrypting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("Decrypt"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
