import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/lumen_ffi.dart';
import '../ffi/sync_service.dart';
import '../knowledge/kb_provider.dart';
import '../knowledge/kb_service.dart';
import '../state/providers.dart';
import '../theme/lumen_colors.dart';

/// The command palette: fuzzy-searchable list of every action Lumen can
/// perform. Opened with `Ctrl+K` / `Cmd+K` from anywhere in the app.
class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({super.key});

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _filter = TextEditingController();
  final _focus = FocusNode();

  List<KbCommand> _commands = const [];
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _loadCommands();
  }

  @override
  void dispose() {
    _filter.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadCommands() async {
    final service = ref.read(kbServiceProvider);
    final commands = await service.listCommands();
    if (mounted) setState(() => _commands = commands);
  }

  List<KbCommand> _filtered(String query) {
    if (query.trim().isEmpty) return _commands;
    final q = query.toLowerCase();
    return _commands.where((c) {
      final haystack =
          '${c.title} ${c.description ?? ''} ${c.keywords.join(' ')}'
              .toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  /// Run the selected command.
  Future<void> _run(KbCommand command) async {
    final service = ref.read(kbServiceProvider);
    final nav = ref.read(selectedSectionProvider.notifier);

    switch (command.id) {
      // --- Navigation ------------------------------------------------------
      case 'journal.openDailyNote':
        nav.select(LumenSection.journal);
        break;
      case 'journal.openNote':
        break;
      case 'navigation.openSearch':
        nav.select(LumenSection.search);
        break;
      case 'navigation.openGraph':
        nav.select(LumenSection.graph);
        break;
      case 'navigation.openSettings':
        nav.select(LumenSection.settings);
        break;

      // --- Capture ---------------------------------------------------------
      case 'capture.newNote':
        break;
      case 'capture.newDailyNote':
        break;
      case 'capture.quickCapture':
        break;

      // --- Editing ---------------------------------------------------------
      case 'editing.togglePreview':
        break;
      case 'editing.insertWikilink':
        break;
      case 'editing.insertTag':
        break;
      case 'editing.wordCount':
        break;

      // --- View ------------------------------------------------------------
      case 'view.toggleTheme':
        break;
      case 'view.focusEditor':
        break;
      case 'view.zenMode':
        break;

      // --- Sync ------------------------------------------------------------
      case 'sync.syncNow':
        await SyncService(LumenFfi.instance).syncWebDAV(
          vaultPath: '', // filled from settings
        );
        break;
      case 'sync.showConflicts':
        break;
      case 'sync.exportBackup':
        break;

      // --- Plugins ---------------------------------------------------------
      case 'plugins.runPlugin':
        break;
      case 'plugins.configurePlugin':
        break;

      // --- Advanced --------------------------------------------------------
      case 'advanced.rebuildSearchIndex':
        break;
      case 'advanced.rebuildGraph':
        break;
      case 'advanced.verifyVault':
        break;

      default:
        try {
          await service.executeCommand(command.id);
        } catch (_) {
          // Ignore — command may not be implemented yet.
        }
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final query = _filter.text;
    final filtered = _filtered(query);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          setState(() {
            _selected = (_selected + 1).clamp(0, filtered.length - 1);
          });
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          setState(() {
            _selected = (_selected - 1).clamp(0, filtered.length - 1);
          });
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          if (filtered.isNotEmpty) {
            _run(filtered[_selected]);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: t.surfaceContainer,
                  border: Border(
                    bottom:
                        BorderSide(color: t.outlineVariant, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search,
                        color: t.onSurfaceVariant, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _filter,
                        focusNode: _focus,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search commands…',
                          hintStyle:
                              TextStyle(color: t.onSurfaceVariant),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        style: TextStyle(color: t.onSurface),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),

              // List
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final cmd = filtered[index];
                    final selected = index == _selected;
                    return ListTile(
                      selected: selected,
                      selectedTileColor: t.primary
                          .withValues(alpha: 0.10),
                      leading: Icon(
                        _iconFor(cmd.id),
                        color: selected
                            ? t.primary
                            : t.onSurfaceVariant,
                        size: 20,
                      ),
                      title: Text(
                        cmd.title,
                        style: TextStyle(
                          color: selected
                              ? t.primary
                              : t.onSurface,
                          fontWeight: selected
                              ? FontWeight.w600
                              : null,
                        ),
                      ),
                      subtitle: cmd.description != null
                          ? Text(
                              cmd.description!,
                              style: TextStyle(
                                color: t.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            )
                          : null,
                      trailing: Text(
                        cmd.source,
                        style: TextStyle(
                          color: t.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      onTap: () => _run(cmd),
                    );
                  },
                ),
              ),

              // Footer
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.surfaceContainer,
                  border: Border(
                    top:
                        BorderSide(color: t.outlineVariant, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.keyboard_arrow_up,
                        size: 16, color: t.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('↑↓ navigate',
                        style: TextStyle(
                            color: t.onSurfaceVariant, fontSize: 11)),
                    const SizedBox(width: 16),
                    Icon(Icons.keyboard_return,
                        size: 16, color: t.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('execute',
                        style: TextStyle(
                            color: t.onSurfaceVariant, fontSize: 11)),
                    const SizedBox(width: 16),
                    Icon(Icons.close,
                        size: 16, color: t.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('Esc close',
                        style: TextStyle(
                            color: t.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String id) {
    if (id.startsWith('journal.')) return Icons.edit_note;
    if (id.startsWith('navigation.')) return Icons.explore;
    if (id.startsWith('capture.')) return Icons.add;
    if (id.startsWith('editing.')) return Icons.edit;
    if (id.startsWith('view.')) return Icons.visibility;
    if (id.startsWith('sync.')) return Icons.sync;
    if (id.startsWith('plugins.')) return Icons.extension;
    if (id.startsWith('advanced.')) return Icons.build;
    return Icons.help;
  }
}

/// Show the command palette as a dialog.
Future<void> showCommandPalette(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => const CommandPalette(),
  );
}
