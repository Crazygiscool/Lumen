import 'package:flutter/material.dart';

import '../theme/lumen_colors.dart';
import 'kb_service.dart';

/// The metadata editor for a note.
///
/// The panel owns the frontmatter; the text field beside it owns the body.
/// The two are joined when the note is saved, so editing a tag never
/// disturbs the text and vice versa.
class FrontmatterEditor extends StatefulWidget {
  const FrontmatterEditor({
    super.key,
    required this.frontmatter,
    required this.onChanged,
    this.availableTags = const [],
  });

  final KbFrontmatter frontmatter;
  final ValueChanged<KbFrontmatter> onChanged;

  /// Tags already used in the vault, offered as completions.
  final List<String> availableTags;

  @override
  State<FrontmatterEditor> createState() => _FrontmatterEditorState();
}

class _FrontmatterEditorState extends State<FrontmatterEditor> {
  final _tagInput = TextEditingController();
  final _aliasInput = TextEditingController();
  final _customKey = TextEditingController();
  final _customValue = TextEditingController();

  @override
  void dispose() {
    _tagInput.dispose();
    _aliasInput.dispose();
    _customKey.dispose();
    _customValue.dispose();
    super.dispose();
  }

  void _update(KbFrontmatter next) => widget.onChanged(next);

  void _addTag(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty || widget.frontmatter.tags.contains(tag)) {
      _tagInput.clear();
      return;
    }
    _update(
      widget.frontmatter.copyWith(
        tags: [...widget.frontmatter.tags, tag],
      ),
    );
    _tagInput.clear();
  }

  void _removeTag(String tag) {
    _update(
      widget.frontmatter.copyWith(
        tags: widget.frontmatter.tags.where((t) => t != tag).toList(),
      ),
    );
  }

  void _addAlias() {
    final alias = _aliasInput.text.trim();
    if (alias.isEmpty || widget.frontmatter.aliases.contains(alias)) {
      _aliasInput.clear();
      return;
    }
    _update(
      widget.frontmatter.copyWith(
        aliases: [...widget.frontmatter.aliases, alias],
      ),
    );
    _aliasInput.clear();
  }

  void _submitAlias(String alias) => _addAlias();

  void _removeAlias(String alias) {
    _update(
      widget.frontmatter.copyWith(
        aliases: widget.frontmatter.aliases.where((a) => a != alias).toList(),
      ),
    );
  }

  void _addCustomField() {
    final key = _customKey.text.trim();
    final value = _customValue.text.trim();
    if (key.isEmpty) return;
    _update(
      widget.frontmatter.copyWith(
        custom: {...widget.frontmatter.custom, key: value},
      ),
    );
    _customKey.clear();
    _customValue.clear();
  }

  void _removeCustomField(String key) {
    final custom = {...widget.frontmatter.custom}..remove(key);
    _update(widget.frontmatter.copyWith(custom: custom));
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final fm = widget.frontmatter;

    return Container(
      decoration: BoxDecoration(
        color: t.surfaceContainer,
        border: Border(bottom: BorderSide(color: t.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field(
            label: 'Title',
            child: TextFormField(
              initialValue: fm.title,
              onChanged: (value) => _update(fm.copyWith(title: value)),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Note title',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _Field(
            label: 'Tags',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (fm.tags.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in fm.tags)
                        InputChip(
                          label: Text(tag),
                          onDeleted: () => _removeTag(tag),
                        ),
                    ],
                  ),
                if (fm.tags.isNotEmpty) const SizedBox(height: 8),
                _ChipInput(
                  controller: _tagInput,
                  hint: 'Add a tag',
                  suggestions: widget.availableTags
                      .where((tag) => !fm.tags.contains(tag))
                      .toList(),
                  onSubmit: _addTag,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _Field(
            label: 'Aliases',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (fm.aliases.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final alias in fm.aliases)
                        InputChip(
                          label: Text(alias),
                          onDeleted: () => _removeAlias(alias),
                        ),
                    ],
                  ),
                if (fm.aliases.isNotEmpty) const SizedBox(height: 8),
                _ChipInput(
                  controller: _aliasInput,
                  hint: 'Add an alias',
                  suggestions: const [],
                  onSubmit: _submitAlias,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _Field(
            label: 'Fields',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in fm.custom.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            style: TextStyle(color: t.onSurfaceVariant),
                          ),
                        ),
                        Expanded(
                          child: Text('${entry.value}'),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _removeCustomField(entry.key),
                          icon: const Icon(Icons.close, size: 16),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customKey,
                        onSubmitted: (_) => _addCustomField(),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'key',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _customValue,
                        onSubmitted: (_) => _addCustomField(),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'value',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Add field',
                      onPressed: _addCustomField,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled row in the metadata panel.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              label,
              style: TextStyle(color: t.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// A text field that offers completions as the user types.
class _ChipInput extends StatefulWidget {
  const _ChipInput({
    required this.controller,
    required this.hint,
    required this.suggestions,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String hint;
  final List<String> suggestions;
  final ValueChanged<String> onSubmit;

  @override
  State<_ChipInput> createState() => _ChipInputState();
}

class _ChipInputState extends State<_ChipInput> {
  @override
  Widget build(BuildContext context) {
    final query = widget.controller.text.trim().toLowerCase();
    final matches = query.isEmpty
        ? widget.suggestions.take(6).toList()
        : widget.suggestions
              .where((option) => option.toLowerCase().contains(query))
              .take(6)
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          onChanged: (_) => setState(() {}),
          onSubmitted: widget.onSubmit,
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint,
            border: const OutlineInputBorder(),
          ),
        ),
        if (matches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final suggestion in matches)
                  ActionChip(
                    label: Text(suggestion),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => widget.onSubmit(suggestion),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
