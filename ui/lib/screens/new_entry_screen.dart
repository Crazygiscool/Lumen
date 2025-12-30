import 'package:flutter/material.dart';
import '../core/lumen_core.dart';

class NewEntryScreen extends StatefulWidget {
  final LumenCore lumen;

  const NewEntryScreen({super.key, required this.lumen});

  @override
  State<NewEntryScreen> createState() => _NewEntryScreenState();
}

class _NewEntryScreenState extends State<NewEntryScreen> {
  final _idController = TextEditingController();
  final _textController = TextEditingController();
  final _authorController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _saving = false;

  void _saveEntry() async {
    setState(() => _saving = true);

    try {
      widget.lumen.addEntry(
        _idController.text.trim(),
        _textController.text.trim(),
        _authorController.text.trim(),
        _passwordController.text.trim(),
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save entry: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Entry")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _idController,
              decoration: const InputDecoration(labelText: "Entry ID"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _authorController,
              decoration: const InputDecoration(labelText: "Author"),
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
                controller: _textController,
                decoration: const InputDecoration(
                  labelText: "Entry Text",
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
    );
  }
}
