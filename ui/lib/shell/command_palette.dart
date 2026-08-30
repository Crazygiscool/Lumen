import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/fs_service.dart';
import '../state/providers.dart';
import '../theme/lumen_colors.dart';
import 'tabs/tab_model.dart';
import 'tabs/tabs_provider.dart';

class CommandPaletteState {
  const CommandPaletteState({
    required this.visible,
    this.query = '',
    this.results = const [],
  });
  final bool visible;
  final String query;
  final List<Map<String, dynamic>> results;
}

class CommandPaletteNotifier extends Notifier<CommandPaletteState> {
  @override
  CommandPaletteState build() => const CommandPaletteState(visible: false);

  void open() => state = const CommandPaletteState(visible: true);
  void close() => state = const CommandPaletteState(visible: false);

  Future<void> search(String query) async {
    state = CommandPaletteState(visible: true, query: query);
    if (query.trim().isEmpty) {
      state = CommandPaletteState(visible: true, query: query);
      return;
    }
    final features = ref.read(featuresProvider);
    final results = <Map<String, dynamic>>[];

    for (final s in LumenSection.values) {
      if (s.feature != null && !features.enabled(s.feature!)) continue;
      final lower = query.toLowerCase();
      if (s.title.toLowerCase().contains(lower)) {
        results.add({'kind': 'section', 'title': s.title});
      }
    }

    // Only probe the filesystem once a term is present.
    try {
      final fs = ref.read(fsServiceProvider);
      final home = homePath();
      final files = await fs.search(home, query, maxResults: 50);
      for (final e in files) {
        results.add({'kind': 'file', 'title': e.path, 'entry': e});
      }
    } catch (_) {
      // Search errors are non-fatal in the palette.
    }
    state = CommandPaletteState(visible: true, query: query, results: results);
  }

  void run(Map<String, dynamic> cmd) {
    switch (cmd['kind']) {
      case 'section':
        final name = cmd['title'] as String;
        final section = LumenSection.values.firstWhere(
          (s) => s.title == name,
          orElse: () => LumenSection.settings,
        );
        ref.read(tabsProvider.notifier).activatePage(section);
      case 'file':
        final entry = cmd['entry'] as FsEntry;
        final target = entry.isDir ? entry.path : _parentOf(entry.path);
        ref
            .read(tabsProvider.notifier)
            .newTab(input: 'lumen://files/${Uri.encodeFull(target)}');
    }
    close();
  }
}

String _parentOf(String path) {
  var p = path;
  while (p.endsWith('/') || p.endsWith('\\')) {
    p = p.substring(0, p.length - 1);
  }
  final i = p.lastIndexOf(RegExp(r'[/\\]'));
  if (i <= 0) return '/';
  return p.substring(0, i);
}

String homePath() {
  final home = Platform.environment['HOME'];
  return home ?? (Platform.isWindows ? 'C:\\' : '/');
}

final commandPaletteProvider =
    NotifierProvider<CommandPaletteNotifier, CommandPaletteState>(
      CommandPaletteNotifier.new,
    );

class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({super.key});

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(commandPaletteProvider, (prev, next) {
      if (next.visible) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_focus.hasFocus) return;
          _focus.requestFocus();
        });
      }
    });

    final state = ref.watch(commandPaletteProvider);
    return Dialog(
      backgroundColor: LumenColors.of(context).surfaceContainer,
      insetPadding: const EdgeInsets.symmetric(horizontal: 160, vertical: 96),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Jump to a section or open a file…',
                  prefixIcon: Icon(Icons.search, size: 18),
                  border: InputBorder.none,
                  filled: false,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 15),
                onChanged: (q) =>
                    ref.read(commandPaletteProvider.notifier).search(q),
                onSubmitted: (q) {
                  final s = ref.read(commandPaletteProvider);
                  if (s.results.isNotEmpty) {
                    ref
                        .read(commandPaletteProvider.notifier)
                        .run(s.results.first);
                  }
                },
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: state.results.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        'No results.',
                        style: TextStyle(
                          color: LumenColors.of(context).onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: state.results.length,
                      itemBuilder: (context, i) {
                        final r = state.results[i];
                        final icon = r['kind'] == 'section'
                            ? Icons.arrow_right_alt
                            : ((r['entry'] as FsEntry).isDir
                                  ? Icons.folder_outlined
                                  : Icons.insert_drive_file_outlined);
                        return ListTile(
                          dense: true,
                          leading: Icon(icon, size: 18),
                          title: Text(
                            r['title'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () =>
                              ref.read(commandPaletteProvider.notifier).run(r),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
