import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../journal/journal_provider.dart';
import '../state/providers.dart';
import '../theme/lumen_colors.dart';
import 'kb_provider.dart';
import 'wikilinks.dart';

/// A note that links to the note being read.
class BacklinkEntry {
  const BacklinkEntry({
    required this.path,
    required this.title,
    required this.context,
  });

  final String path;
  final String title;

  /// The text around the link, so the reference reads in place.
  final String context;
}

/// The notes that link to the note being read.
///
/// The panel is opened from the editor. Each entry shows the surrounding
/// text, so a link is readable without opening the note it comes from.
class BacklinksPanel extends ConsumerStatefulWidget {
  const BacklinksPanel({super.key, required this.relPath});

  /// The note whose backlinks are listed.
  final String relPath;

  @override
  ConsumerState<BacklinksPanel> createState() => _BacklinksPanelState();
}

class _BacklinksPanelState extends ConsumerState<BacklinksPanel> {
  late Future<List<BacklinkEntry>> _entries;

  @override
  void initState() {
    super.initState();
    _entries = _load();
  }

  @override
  void didUpdateWidget(BacklinksPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relPath != widget.relPath) {
      _entries = _load();
    }
  }

  Future<List<BacklinkEntry>> _load() async {
    final service = ref.read(kbServiceProvider);
    final paths = await service.backlinks(widget.relPath);
    final notes = ref.read(journalServiceProvider);

    final entries = <BacklinkEntry>[];
    for (final path in paths) {
      String title = path;
      String context = '';
      try {
        final body = await notes.read(path);
        context = wikilinkContext(body, widget.relPath);
        final all = ref.read(journalNotesProvider).asData?.value ?? const [];
        final match = all.where((n) => n.relPath == path).firstOrNull;
        if (match != null) title = match.displayTitle;
      } catch (_) {
        // A backlink to a note that cannot be read is still worth listing.
      }
      entries.add(
        BacklinkEntry(path: path, title: title, context: context),
      );
    }

    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);

    return FutureBuilder<List<BacklinkEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Backlinks failed: ${snapshot.error}',
              style: TextStyle(color: t.error),
            ),
          );
        }

        final entries = snapshot.data ?? const [];
        if (entries.isEmpty) {
          return Center(
            child: Text(
              'Nothing links here yet.',
              style: TextStyle(color: t.onSurfaceVariant),
            ),
          );
        }

        return ListView.separated(
          itemCount: entries.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final entry = entries[i];
            return ListTile(
              leading: Icon(Icons.link, color: t.primary),
              title: Text(entry.title),
              subtitle: entry.context.isEmpty
                  ? null
                  : Text(
                      entry.context,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
              onTap: () {
                Navigator.of(context).pop();
                openJournalNote(ref, entry.path);
              },
            );
          },
        );
      },
    );
  }
}

/// Opens the backlinks of a note in a sheet.
Future<void> showBacklinksPanel(
  BuildContext context, {
  required String relPath,
}) {
  final t = LumenColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: t.surfaceHigh,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.link, color: t.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Links to this note',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: BacklinksPanel(relPath: relPath),
          ),
        ],
      ),
    ),
  );
}
