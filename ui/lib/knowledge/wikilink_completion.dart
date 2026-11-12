import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../journal/journal_provider.dart';
import '../journal/journal_service.dart';
import '../theme/lumen_colors.dart';
import 'wikilinks.dart';

/// Hosts the editor and shows the completion list while a wikilink is being
/// typed.
///
/// The list is anchored to the editor, so it reads as a popup rather than a
/// panel. Only the notes the query matches are offered.
class WikilinkCompletionHost extends ConsumerStatefulWidget {
  const WikilinkCompletionHost({
    super.key,
    required this.controller,
    required this.onInsert,
    required this.child,
  });

  final TextEditingController controller;

  /// Called with the chosen note and the link that was being typed.
  final void Function(JournalNote note, ActiveWikilink active) onInsert;

  final Widget child;

  @override
  ConsumerState<WikilinkCompletionHost> createState() =>
      _WikilinkCompletionHostState();
}

class _WikilinkCompletionHostState
    extends ConsumerState<WikilinkCompletionHost> {
  final _anchor = LayerLink();
  OverlayEntry? _entry;
  ActiveWikilink? _active;
  List<JournalNote> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onChanged() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _clear();
      return;
    }

    final active = activeWikilink(text, selection.baseOffset);
    if (active == null) {
      _clear();
      return;
    }

    final notes = ref.read(journalNotesProvider).asData?.value ??
        const <JournalNote>[];
    final query = active.query.trim().toLowerCase();
    final suggestions = notes
        .where(
          (note) =>
              note.name.toLowerCase().contains(query) ||
              note.displayTitle.toLowerCase().contains(query),
        )
        .take(8)
        .toList();

    if (suggestions.isEmpty) {
      _clear();
      return;
    }

    _active = active;
    _suggestions = suggestions;
    _showOverlay();
  }

  void _clear() {
    _active = null;
    _suggestions = const [];
    _removeOverlay();
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  void _showOverlay() {
    final entry = _entry;
    if (entry != null) {
      entry.markNeedsBuild();
      return;
    }

    final created = OverlayEntry(
      builder: (context) => CompositedTransformFollower(
        link: _anchor,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 6),
        child: _SuggestionList(
          suggestions: _suggestions,
          onSelect: (note) {
            final active = _active;
            _clear();
            if (active != null) widget.onInsert(note, active);
          },
        ),
      ),
    );
    _entry = created;
    Overlay.of(context).insert(created);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _anchor,
      child: widget.child,
    );
  }
}

/// The list of notes offered for a wikilink.
class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.suggestions, required this.onSelect});

  final List<JournalNote> suggestions;
  final ValueChanged<JournalNote> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      color: t.surfaceHigh,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320, maxHeight: 280),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: suggestions.length,
          itemBuilder: (context, i) {
            final note = suggestions[i];
            return ListTile(
              dense: true,
              leading: Icon(Icons.article_outlined, color: t.primary, size: 18),
              title: Text(
                note.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                note.relPath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.onSurfaceVariant, fontSize: 11),
              ),
              onTap: () => onSelect(note),
            );
          },
        ),
      ),
    );
  }
}
