import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/fs_service.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../theme/lumen_colors.dart';
import 'editor/editor_pane.dart';
import 'editor/file_workspace_provider.dart';
import 'editor/split_grid.dart';
import 'inspector_panel.dart';

enum _ViewMode { grid, list }

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key, required this.tabId});

  final String tabId;

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  _ViewMode _viewMode = _ViewMode.grid;
  bool _showHidden = false;
  bool _inspectorOpen = false;
  FsEntry? _selected;
  final FocusNode _node = FocusNode();

  AsyncNotifierProvider<DirNotifier, DirState> get _dir =>
      fileExplorerProvider(widget.tabId);

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  Future<void> _cdUp(String path) async {
    final parts = path
        .split(Platform.pathSeparator)
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;
    parts.removeLast();
    final parent = Platform.isWindows
        ? '${parts.join(Platform.pathSeparator)}${Platform.pathSeparator}'
        : '/${parts.join('/')}';
    await ref.read(_dir.notifier).cd(parent);
    setState(() => _selected = null);
  }

  Future<void> _open(FsEntry entry) async {
    setState(() => _selected = entry);
    if (!entry.isDir) return;
    _node.requestFocus();
    await ref.read(_dir.notifier).cd(entry.path);
    setState(() => _selected = null);
  }

  Future<void> _openEditor(FsEntry entry) async {
    setState(() => _selected = entry);
    _node.requestFocus();
    await ref
        .read(fileWorkspaceProvider(widget.tabId).notifier)
        .openFile(entry.path);
  }

  Future<void> _newFolder() async {
    final state = ref.read(_dir).value;
    if (state == null) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'folder name'),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final path = '${state.path}${Platform.pathSeparator}$name';
      await ref.read(fsServiceProvider).mkdir(path);
      await ref.read(_dir.notifier).refresh();
    } catch (e) {
      _toast('Could not create folder: $e');
    }
  }

  Future<void> _rename(FsEntry entry) async {
    final controller = TextEditingController(text: entry.name);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == entry.name) return;
    try {
      final parent = entry.path.substring(
        0,
        entry.path.length - entry.name.length,
      );
      await ref.read(fsServiceProvider).rename(entry.path, '$parent$name');
      await ref.read(_dir.notifier).refresh();
    } catch (e) {
      _toast('Rename failed: ${_short(e.toString())}');
    }
  }

  Future<void> _trash(FsEntry entry) async {
    try {
      await ref.read(fsServiceProvider).trash(entry.path);
      await ref.read(_dir.notifier).refresh();
      _toast('Moved ${entry.name} to trash');
    } catch (e) {
      _toast('Trash failed: ${_short(e.toString())}');
    }
  }

  Future<void> _delete(FsEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${entry.name}?'),
        content: Text(
          'This permanently removes the item and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LumenColors.of(context).errorContainer,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(fsServiceProvider).delete(entry.path);
      await ref.read(_dir.notifier).refresh();
    } catch (e) {
      _toast('Delete failed: ${_short(e.toString())}');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _short(String s) => s.length > 140 ? '${s.substring(0, 140)}…' : s;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_dir);
    final fs = ref.read(fsServiceProvider);
    final ws = ref.watch(fileWorkspaceProvider(widget.tabId));
    final wsNotifier = ref.read(fileWorkspaceProvider(widget.tabId).notifier);

    return Column(
      children: [
        _Toolbar(
          path: state.value?.path ?? '',
          viewMode: _viewMode,
          showHidden: _showHidden,
          inspectorOpen: _inspectorOpen,
          loading: state.isLoading,
          onBack: () => _cdUp(state.value?.path ?? ''),
          onNavigate: (path) async {
            await ref.read(_dir.notifier).cd(path);
            setState(() => _selected = null);
          },
          onReload: () => ref.read(_dir.notifier).refresh(),
          onViewMode: (m) => setState(() => _viewMode = m),
          onToggleHidden: () {
            setState(() => _showHidden = !_showHidden);
            ref.read(_dir.notifier).toggleHidden();
          },
          onToggleInspector: () =>
              setState(() => _inspectorOpen = !_inspectorOpen),
          onNewFolder: _newFolder,
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 180,
                child: _PlacesSidebar(
                  current: state.value?.path ?? '',
                  onPick: (path) async {
                    await ref.read(_dir.notifier).cd(path);
                    setState(() => _selected = null);
                  },
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              Expanded(
                child: state.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (e, st) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not read directory.\n$e',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: LumenColors.of(context).error),
                      ),
                    ),
                  ),
                  data: (d) => LayoutBuilder(
                    builder: (context, c) {
                      final total = c.maxWidth;
                      final hasPanes = ws.hasPanes;
                      final explorerWidth = total <= 0
                          ? total
                          : hasPanes
                              ? (total * 0.40).clamp(260.0, 560.0)
                              : total;
                      final divider = VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      );
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: explorerWidth,
                            child: _FilesArea(
                              state: d,
                              viewMode: _viewMode,
                              selected: _selected,
                              onOpen: _open,
                              onOpenEditor: _openEditor,
                              onSelect: (e) => setState(() => _selected = e),
                              onRename: _rename,
                              onTrash: _trash,
                              onDelete: _delete,
                              onCopyPath: (e) {
                                Clipboard.setData(ClipboardData(text: e.path));
                                _toast('Path copied');
                              },
                            ),
                          ),
                          if (hasPanes) ...[
                            divider,
                            Expanded(
                              child: SplitGrid(
                                layout: ws.layout!,
                                onAdaptWeight: (id, f) =>
                                    wsNotifier.adjustWeight(id, f),
                                paneBuilder: (pane) => EditorPaneView(
                                  key: ValueKey(pane.id),
                                  pane: pane,
                                  notifier: wsNotifier,
                                  active: pane.id == ws.activePaneId,
                                  onFocusPane: () =>
                                      wsNotifier.focusPane(pane.id),
                                ),
                              ),
                            ),
                          ] else if (_inspectorOpen) ...[
                            divider,
                            SizedBox(
                              width: 280,
                              child: InspectorPanel(entry: _selected, fs: fs),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.path,
    required this.viewMode,
    required this.showHidden,
    required this.inspectorOpen,
    required this.loading,
    required this.onBack,
    required this.onNavigate,
    required this.onReload,
    required this.onViewMode,
    required this.onToggleHidden,
    required this.onToggleInspector,
    required this.onNewFolder,
  });

  final String path;
  final _ViewMode viewMode;
  final bool showHidden;
  final bool inspectorOpen;
  final bool loading;
  final VoidCallback onBack;
  final ValueChanged<String> onNavigate;
  final VoidCallback onReload;
  final ValueChanged<_ViewMode> onViewMode;
  final VoidCallback onToggleHidden;
  final VoidCallback onToggleInspector;
  final VoidCallback onNewFolder;

  @override
  Widget build(BuildContext context) {
    final parts = path
        .split(Platform.pathSeparator)
        .where((e) => e.isNotEmpty)
        .toList();
    return SizedBox(
      height: 48,
      child: Glass(
        blurSigma: 14,
        radius: 0,
        fill: LumenColors.of(context).surfaceContainer,
        border: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back (Alt+Left)',
                icon: const Icon(Icons.arrow_back, size: 18),
                onPressed: parts.isEmpty ? null : onBack,
              ),
              IconButton(
                tooltip: loading ? 'Loading…' : 'Reload',
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: onReload,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _Breadcrumb(
                        label: Platform.isWindows ? 'C:' : '/',
                        onTap: () => onNavigate(
                          Platform.isWindows
                              ? 'C:${Platform.pathSeparator}'
                              : '/',
                        ),
                      ),
                      for (var i = 0; i < parts.length; i++) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 2),
                          child: Icon(
                            Icons.chevron_right,
                            size: 14,
                            color: LumenColors.of(context).onSurfaceVariant,
                          ),
                        ),
                        _Breadcrumb(
                          label: parts[i],
                          isLast: i == parts.length - 1,
                          onTap: () {
                            final full = Platform.isWindows
                                ? '${parts.sublist(0, i + 1).join(Platform.pathSeparator)}${Platform.pathSeparator}'
                                : '/${parts.sublist(0, i + 1).join('/')}';
                            onNavigate(full);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(width: 8),
              IconButton(
                tooltip: 'Toggle hidden files',
                icon: Icon(Icons.filter_none, size: 18),
                isSelected: showHidden,
                selectedIcon: Icon(
                  Icons.filter_none,
                  size: 18,
                  color: LumenColors.of(context).primary,
                ),
                onPressed: onToggleHidden,
              ),
              PopupMenuButton<_ViewMode>(
                tooltip: 'View',
                icon: const Icon(Icons.view_agenda_outlined, size: 18),
                initialValue: viewMode,
                onSelected: onViewMode,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _ViewMode.grid, child: Text('Grid')),
                  PopupMenuItem(value: _ViewMode.list, child: Text('List')),
                ],
              ),
              IconButton(
                tooltip: 'New folder',
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                onPressed: onNewFolder,
              ),
              IconButton(
                tooltip: inspectorOpen ? 'Hide inspector' : 'Show inspector',
                icon: Icon(Icons.info_outline, size: 18),
                isSelected: inspectorOpen,
                selectedIcon: Icon(
                  Icons.info,
                  size: 18,
                  color: LumenColors.of(context).primary,
                ),
                onPressed: onToggleInspector,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({
    required this.label,
    required this.onTap,
    this.isLast = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isLast ? null : onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
            color: isLast
                ? LumenColors.of(context).onSurface
                : LumenColors.of(context).onSurfaceVariant,
            fontFamily: lumenMonoFont,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _PlacesSidebar extends StatelessWidget {
  const _PlacesSidebar({required this.current, required this.onPick});
  final String current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final home = Platform.environment['HOME'] ?? '/';
    final places = <(IconData, String, String)>[
      (Icons.home_outlined, 'Home', home),
      (
        Icons.folder_open_outlined,
        'Documents',
        '$home${Platform.pathSeparator}Documents',
      ),
      (
        Icons.download_outlined,
        'Downloads',
        '$home${Platform.pathSeparator}Downloads',
      ),
      (Icons.folder_outlined, 'Current vault', current),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: LumenColors.of(context).surfaceLow,
        border: Border(
          right: BorderSide(color: LumenColors.of(context).hairline, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, 4, 8, 6),
            child: Text(
              'PLACES',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                color: LumenColors.of(context).outline,
              ),
            ),
          ),
          for (final (icon, label, path) in places)
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                dense: true,
                minLeadingWidth: 24,
                leading: Icon(icon, size: 16),
                title: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                selected: path == current,
                selectedColor: LumenColors.of(context).primary,
                selectedTileColor: LumenColors.of(context).surfaceContainer,
                onTap: () => onPick(path),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 8, 6),
            child: Text(
              'PATH',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                color: LumenColors.of(context).outline,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              current,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontFamily: lumenMonoFont,
                color: LumenColors.of(context).onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _FilesArea extends StatelessWidget {
  const _FilesArea({
    required this.state,
    required this.viewMode,
    required this.selected,
    required this.onOpen,
    required this.onOpenEditor,
    required this.onSelect,
    required this.onRename,
    required this.onTrash,
    required this.onDelete,
    required this.onCopyPath,
  });

  final DirState state;
  final _ViewMode viewMode;
  final FsEntry? selected;
  final ValueChanged<FsEntry> onOpen;
  final ValueChanged<FsEntry> onOpenEditor;
  final ValueChanged<FsEntry> onSelect;
  final ValueChanged<FsEntry> onRename;
  final ValueChanged<FsEntry> onTrash;
  final ValueChanged<FsEntry> onDelete;
  final ValueChanged<FsEntry> onCopyPath;

  @override
  Widget build(BuildContext context) {
    final dirs = state.entries.where((e) => e.isDir).toList();
    final files = state.entries.where((e) => !e.isDir).toList();

    Widget item(FsEntry e) {
      return _FileTile(
        entry: e,
        highlighted: e.path == selected?.path,
        viewMode: viewMode,
        showContext: showContextMenu,
        onTap: () => onOpen(e),
        onOpenEditor: () => onOpenEditor(e),
        onSelect: () => onSelect(e),
      );
    }

    final content = viewMode == _ViewMode.grid
        ? GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.1,
            ),
            itemCount: dirs.length + files.length,
            itemBuilder: (c, i) =>
                item(i < dirs.length ? dirs[i] : files[i - dirs.length]),
          )
        : ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: dirs.length + files.length,
            itemBuilder: (c, i) =>
                item(i < dirs.length ? dirs[i] : files[i - dirs.length]),
          );

    if (state.entries.isEmpty) {
      return Center(
        child: Text(
          'This folder is empty.',
          style: TextStyle(color: LumenColors.of(context).onSurfaceVariant),
        ),
      );
    }
    return content;
  }

  void showContextMenu(BuildContext context, FsEntry entry, Offset pos) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, 0, 0),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem(
          value: 'open',
          child: Text(entry.isDir ? 'Open' : 'Open file'),
        ),
        PopupMenuItem(value: 'rename', child: const Text('Rename…')),
        PopupMenuItem(value: 'copy', child: const Text('Copy path')),
        if (!entry.isDir) const PopupMenuDivider(),
        if (!entry.isDir)
          PopupMenuItem(value: 'trash', child: const Text('Move to trash')),
        const PopupMenuItem(value: 'delete', child: Text('Delete…')),
      ],
    ).then((v) {
      switch (v) {
        case 'open':
          if (!entry.isDir) {
            onOpenEditor(entry);
          } else {
            onOpen(entry);
          }
        case 'rename':
          onRename(entry);
        case 'copy':
          onCopyPath(entry);
        case 'trash':
          onTrash(entry);
        case 'delete':
          onDelete(entry);
      }
    });
  }
}

class _FileTile extends StatefulWidget {
  const _FileTile({
    required this.entry,
    required this.highlighted,
    required this.viewMode,
    required this.showContext,
    required this.onTap,
    required this.onOpenEditor,
    required this.onSelect,
  });

  final FsEntry entry;
  final bool highlighted;
  final _ViewMode viewMode;
  final void Function(BuildContext, FsEntry, Offset) showContext;
  final VoidCallback onTap;
  final VoidCallback onOpenEditor;
  final VoidCallback onSelect;

  @override
  State<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends State<_FileTile> {
  bool _hovered = false;

  FsEntry get entry => widget.entry;

  IconData get _icon {
    if (entry.isDir) return Icons.folder_outlined;
    switch (entry.extension?.toLowerCase()) {
      case 'md':
      case 'txt':
        return Icons.description_outlined;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
        return Icons.image_outlined;
      case 'dart':
      case 'rs':
      case 'py':
      case 'js':
      case 'ts':
        return Icons.code;
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Color _tintFor(BuildContext context) {
    if (entry.isDir) return LumenColors.of(context).info;
    switch (entry.extension?.toLowerCase()) {
      case 'md':
      case 'txt':
        return LumenColors.of(context).primary;
      case 'dart':
      case 'rs':
      case 'py':
      case 'js':
        return LumenColors.codeString;
      case 'png':
      case 'jpg':
        return LumenColors.of(context).warning;
      default:
        return LumenColors.of(context).onSurfaceVariant;
    }
  }

  Color _hoverTint(BuildContext context) {
    final t = LumenColors.of(context);
    return entry.isDir ? t.info : t.primary;
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final radius = BorderRadius.circular(LumenColors.radiusMd);
    final folder = entry.isDir;

    final bg = widget.highlighted
        ? t.primaryContainer
        : _hovered
        ? folder
              ? t.info.withValues(alpha: 0.10)
              : t.glassHover
        : t.glass.withValues(
            alpha: widget.viewMode == _ViewMode.list ? 0.45 : 0,
          );
    final border = widget.highlighted
        ? Border.all(color: t.primary, width: 1)
        : _hovered
        ? Border.all(
            color: folder ? t.info.withValues(alpha: 0.55) : t.hairlineStrong,
            width: 1,
          )
        : null;

    final base = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        widget.onSelect();
        setState(() => _hovered = true);
      },
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: border,
          boxShadow: _hovered && !widget.highlighted
              ? [
                  glowShadow(
                    color: _hoverTint(context),
                    opacity: folder ? 0.12 : 0.07,
                    blur: 22,
                  ),
                ]
              : null,
        ),
        child: GestureDetector(
          onTap: widget.onTap,
          onDoubleTap: entry.isDir ? null : widget.onOpenEditor,
          onSecondaryTapDown: (d) =>
              widget.showContext(context, entry, d.globalPosition),
          child: _content(context),
        ),
      ),
    );
    return widget.viewMode == _ViewMode.grid
        ? Padding(padding: const EdgeInsets.all(4), child: base)
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
            child: base,
          );
  }

  Widget _content(BuildContext context) {
    if (widget.viewMode == _ViewMode.grid) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: _hovered ? 1.12 : 1.0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            child: Icon(
              _icon,
              size: 34,
              color: _hovered ? _hoverTint(context) : _tintFor(context),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              entry.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      );
    }
    return ListTile(
      dense: true,
      leading: Icon(
        _icon,
        color: _hovered ? _hoverTint(context) : _tintFor(context),
        size: 20,
      ),
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13.5),
      ),
      subtitle: entry.isSymlink
          ? Text(
              '→ ${entry.symlinkTarget ?? ''}',
              style: TextStyle(
                fontSize: 11,
                color: LumenColors.of(context).warning,
              ),
            )
          : null,
      trailing: Text(
        entry.isDir ? '' : formatBytes(entry.size),
        style: TextStyle(
          fontSize: 12,
          fontFamily: lumenMonoFont,
          color: LumenColors.of(context).onSurfaceVariant,
        ),
      ),
      mouseCursor: MouseCursor.defer,
      onTap: widget.onTap,
      onLongPress: () {
        final box = context.findRenderObject() as RenderBox?;
        widget.showContext(
          context,
          entry,
          box?.localToGlobal(Offset.zero) ?? Offset.zero,
        );
      },
    );
  }
}
