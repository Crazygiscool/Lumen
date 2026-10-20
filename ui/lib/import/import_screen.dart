import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../journal/journal_provider.dart';
import '../state/providers.dart';
import '../theme/lumen_colors.dart';
import '../widgets/path_picker.dart';

/// Import existing journals into the encrypted journal store.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  String? _busy;
  String? _message;
  bool _failed = false;

  Future<void> _run(
    String label,
    Future<(int, int)> Function(String path) import,
    PathPickerMode mode,
    List<String> extensions,
  ) async {
    final path = await showPathPicker(
      context,
      mode: mode,
      title: label,
      extensions: extensions,
    );
    if (path == null) return;
    setState(() {
      _busy = label;
      _message = null;
      _failed = false;
    });
    try {
      final (imported, skipped) = await import(path);
      ref.invalidate(journalNotesProvider);
      if (!mounted) return;
      setState(() {
        _busy = null;
        _failed = false;
        _message = skipped > 0
            ? 'Imported $imported ${_noun(imported)} ($skipped skipped).'
            : 'Imported $imported ${_noun(imported)}.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _failed = true;
        _message = 'Import failed: $e';
      });
    }
  }

  String _noun(int n) => n == 1 ? 'note' : 'notes';

  @override
  Widget build(BuildContext context) {
    final unlocked = ref.watch(journalVaultProvider).unlocked;
    final t = LumenColors.of(context);
    final service = ref.watch(journalVaultServiceProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Import', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Bring existing writing into your encrypted journal. '
          'Files are decrypted only in memory and re-encrypted on disk.',
          style: TextStyle(color: t.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        if (!unlocked)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unlock the journal first',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Imports write into the journal store, so it must be '
                    'unlocked.',
                    style: TextStyle(color: t.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => ref
                        .read(selectedSectionProvider.notifier)
                        .select(LumenSection.journal),
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Go to Journal'),
                  ),
                ],
              ),
            ),
          )
        else ...[
          _ImportCard(
            icon: Icons.auto_awesome_outlined,
            title: 'Stoic export',
            description:
                'Import a Stoic journal export folder or .zip '
                '(journal-entries.json, routines.json, answers.json). '
                'Media attachments are skipped.',
            busy: _busy == 'Stoic export',
            enabled: _busy == null,
            onPressed: () => _run(
              'Stoic export',
              service.importStoic,
              PathPickerMode.directory,
              const [],
            ),
            secondary: TextButton(
              onPressed: _busy != null
                  ? null
                  : () => _run(
                      'Stoic export',
                      service.importStoic,
                      PathPickerMode.file,
                      const ['.zip'],
                    ),
              child: const Text('Choose .zip instead'),
            ),
          ),
          _ImportCard(
            icon: Icons.data_object,
            title: 'JSON backup',
            description:
                'Import a Lumen JSON export (array of entries) or a generic '
                'JSON list of notes with body/text fields.',
            busy: _busy == 'JSON backup',
            enabled: _busy == null,
            onPressed: () => _run(
              'JSON backup',
              service.importJson,
              PathPickerMode.file,
              const ['.json'],
            ),
          ),
          _ImportCard(
            icon: Icons.description_outlined,
            title: 'Markdown folder',
            description:
                'Import every .md file under a folder. Files land under '
                'imported/ so nothing is overwritten.',
            busy: _busy == 'Markdown folder',
            enabled: _busy == null,
            onPressed: () => _run(
              'Markdown folder',
              service.importMarkdown,
              PathPickerMode.directory,
              const [],
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _message!,
                style: TextStyle(color: _failed ? t.error : t.primary),
              ),
            ),
        ],
      ],
    );
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.busy,
    required this.enabled,
    required this.onPressed,
    this.secondary,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: t.primary, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(description, style: TextStyle(color: t.onSurfaceVariant)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: !enabled || busy ? null : onPressed,
                        child: busy
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Choose…'),
                      ),
                      if (secondary != null) ...[
                        const SizedBox(width: 8),
                        secondary!,
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
