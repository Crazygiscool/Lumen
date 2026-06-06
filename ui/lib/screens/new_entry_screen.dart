import 'package:flutter/material.dart';
import '../core/lumen_core.dart';

class NewEntryScreen extends StatefulWidget {
  final LumenCore lumen;

  const NewEntryScreen({super.key, required this.lumen});

  @override
  State<NewEntryScreen> createState() => _NewEntryScreenState();
}

class _NewEntryScreenState extends State<NewEntryScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _authorController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tagsController = TextEditingController();

  String _kind = 'journal';
  String _priority = 'medium';
  final _kinds = ['journal', 'note', 'task', 'project'];
  final _priorities = ['low', 'medium', 'high'];
  bool _saving = false;

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

      widget.lumen.addEntry(
        _buildBody(),
        _authorController.text.trim(),
        _passwordController.text.trim(),
        kind: _kind,
        tags: tags,
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
            // Kind selector
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

            // Title field (for all kinds except journal)
            if (_kind != 'journal')
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: "Title"),
                ),
              ),

            // Priority field (task only)
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

            // Metadata
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

            // Body text
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
    );
  }
}
