import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../knowledge/kb_provider.dart';
import '../theme/lumen_colors.dart';

/// The editor for the daily note template.
///
/// The preview renders the template as it is being typed, so a placeholder
/// shows what it will produce before the template is saved.
class TemplateEditorScreen extends ConsumerStatefulWidget {
  const TemplateEditorScreen({super.key});

  @override
  ConsumerState<TemplateEditorScreen> createState() =>
      _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends ConsumerState<TemplateEditorScreen> {
  final _controller = TextEditingController();

  Timer? _debounce;
  String _path = '';
  String _preview = '';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// The placeholders the daily template understands.
  static const _placeholders = <String, String>{
    '{{date}}': '2026-02-03',
    '{{date:%A, %B %d, %Y}}': 'Tuesday, February 03, 2026',
    '{{time}}': '14:32',
    '{{yesterday}}': '2026-02-02',
    '{{tomorrow}}': '2026-02-04',
    '{{week}}': '2026-W05',
    '{{month}}': '2026-02',
    '{{iso_week}}': '2026-W05',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // The core owns the path and creates the file if it is missing, so
      // the editor always starts from something usable.
      final template = await ref.read(kbServiceProvider).template();

      if (!mounted) return;
      setState(() {
        _path = template.path;
        _controller.text = template.content;
        _loading = false;
      });
      await _refreshPreview(template.content);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Re-renders the preview, a moment after the last keystroke.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _refreshPreview(value);
    });
    setState(() {});
  }

  Future<void> _refreshPreview(String template) async {
    try {
      final rendered = await ref
          .read(kbServiceProvider)
          .renderTemplate(template, DateTime.now());
      if (!mounted) return;
      setState(() => _preview = rendered);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final path = await ref
          .read(kbServiceProvider)
          .saveTemplate(_controller.text);
      if (!mounted) return;
      setState(() => _path = path);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Template saved')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Inserts a placeholder at the caret.
  void _insertPlaceholder(String placeholder) {
    final selection = _controller.selection;
    final text = _controller.text;
    final at = selection.isValid ? selection.start : text.length;
    final updated = text.replaceRange(at, at, placeholder);
    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: at + placeholder.length),
    );
    _onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Template'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Template file',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        _path,
                        style: TextStyle(color: t.onSurfaceVariant, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final entry in _placeholders.entries)
                            ActionChip(
                              label: Text(entry.key),
                              tooltip: entry.value,
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _insertPlaceholder(entry.key),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(_error!, style: TextStyle(color: t.error)),
                  ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 10, 20),
                          child: TextField(
                            controller: _controller,
                            onChanged: _onChanged,
                            expands: true,
                            maxLines: null,
                            minLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              height: 1.5,
                            ),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Template',
                              alignLabelWithHint: true,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 20, 20),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: t.surfaceContainer,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: t.outlineVariant),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                _preview.isEmpty ? 'Nothing to preview' : _preview,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(
                    children: [
                      Text(
                        'Preview for today',
                        style: TextStyle(color: t.onSurfaceVariant, fontSize: 12),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Save template'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
