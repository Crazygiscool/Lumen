import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/fs_service.dart';
import '../../state/providers.dart';

// ---------------------------------------------------------------------------
// Editor workspace — a per-tab set of open files arranged in a split tree so
// several editors can sit side by side (or stacked) at once.
// ---------------------------------------------------------------------------

@immutable
class EditorPaneState {
  const EditorPaneState({
    required this.id,
    required this.path,
    this.text = '',
    this.dirty = false,
    this.loading = false,
    this.error,
  });

  final String id;
  final String path;

  /// Last saved (or freshly loaded) buffer content.
  final String text;
  final bool dirty;
  final bool loading;
  final String? error;

  String get name => _basename(path);
  bool get editable => error == null && !loading;

  EditorPaneState copyWith({
    String? text,
    bool? dirty,
    bool? loading,
    bool clearError = false,
    String? error,
  }) => EditorPaneState(
    id: id,
    path: path,
    text: text ?? this.text,
    dirty: dirty ?? this.dirty,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );
}

/// A node in the editor layout tree: either a single pane or a split.
sealed class PaneArea {
  const PaneArea();
}

@immutable
class PaneLeaf extends PaneArea {
  const PaneLeaf({required this.pane});
  final EditorPaneState pane;
}

@immutable
class PaneSplit extends PaneArea {
  const PaneSplit({
    required this.axis,
    required this.children,
    required this.weights,
  });

  final Axis axis;
  final List<PaneArea> children;

  /// Must sum to 1.0; matched to [children] by index.
  final List<double> weights;
}

List<String> leafPaneIds(PaneArea node) {
  switch (node) {
    case PaneLeaf(:final pane):
      return [pane.id];
    case PaneSplit(:final children):
      return [for (final c in children) ...leafPaneIds(c)];
  }
}

/// All editor panes under [node], depth-first.
List<EditorPaneState> panesOf(PaneArea node) {
  switch (node) {
    case PaneLeaf(:final pane):
      return [pane];
    case PaneSplit(:final children):
      return [for (final c in children) ...panesOf(c)];
  }
}

/// Returns the tree with [leafId] removed, collapsing single-child splits.
/// Returns null when nothing remains.
PaneArea? removeLeafFrom(PaneArea node, String leafId) {
  switch (node) {
    case PaneLeaf(:final pane):
      return pane.id == leafId ? null : node;
    case PaneSplit(:final axis, :final children, :final weights):
      final kept = <(PaneArea, double)>[];
      for (var i = 0; i < children.length; i++) {
        final r = removeLeafFrom(children[i], leafId);
        if (r != null) kept.add((r, weights[i]));
      }
      if (kept.isEmpty) return null;
      if (kept.length == 1) return kept.first.$1;
      final total = kept.fold(0.0, (a, e) => a + e.$2);
      return PaneSplit(
        axis: axis,
        children: [for (final e in kept) e.$1],
        weights: [for (final e in kept) e.$2 / total],
      );
  }
}

/// Splits the leaf [leafId] so [replacement] joins it along [axis].
PaneArea splitLeafWith(
  PaneArea node,
  String leafId,
  PaneArea replacement,
  Axis axis,
) {
  switch (node) {
    case PaneLeaf(:final pane):
      if (pane.id == leafId) {
        return PaneSplit(
          axis: axis,
          children: [node, replacement],
          weights: const [0.5, 0.5],
        );
      }
      return node;
    case PaneSplit(:final axis, :final children, :final weights):
      final out = <PaneArea>[];
      final ws = <double>[];
      for (var i = 0; i < children.length; i++) {
        out.add(splitLeafWith(children[i], leafId, replacement, axis));
        ws.add(weights[i]);
      }
      return PaneSplit(axis: axis, children: out, weights: ws);
  }
}

/// Moves [fraction] of weight from a pane's left neighbour to the pane
/// containing [steerId] (negative [fraction] shrinks it). Fractions are
/// normalised to a (0.1, 0.9) share of the affected pair.
PaneArea adjustWeightToward(PaneArea node, String steerId, double fraction) {
  switch (node) {
    case PaneLeaf():
      return node;
    case PaneSplit(:final axis, :final children, :final weights):
      final out = <PaneArea>[];
      final ws = <double>[...weights];
      for (var i = 0; i < children.length; i++) {
        if (leafPaneIds(children[i]).contains(steerId)) {
          out.add(adjustWeightToward(children[i], steerId, fraction));
          if (i > 0) {
            final pairSum = ws[i - 1] + ws[i];
            final left = (weights[i - 1] + fraction)
              .clamp(pairSum * 0.10, pairSum * 0.90)
              .toDouble();
            ws[i - 1] = left;
            ws[i] = pairSum - left;
          }
        } else {
          out.add(children[i]);
        }
      }
      return PaneSplit(axis: axis, children: out, weights: ws);
  }
}

@immutable
class EditorWorkspaceState {
  const EditorWorkspaceState({this.layout, this.activePaneId});
  final PaneArea? layout;
  final String? activePaneId;

  bool get hasPanes => layout != null;
}

class FileWorkspaceNotifier extends Notifier<EditorWorkspaceState> {
  FileWorkspaceNotifier(this.tabId);

  final String tabId;

  int _seq = 0;

  @override
  EditorWorkspaceState build() => const EditorWorkspaceState();

  FsService get _fs => ref.read(fsServiceProvider);

  String _newId() => 'e${_seq++}_${DateTime.now().microsecondsSinceEpoch}';

  void _set(PaneArea? layout, {String? activePaneId}) {
    state = EditorWorkspaceState(
      layout: layout,
      activePaneId:
          activePaneId ?? state.activePaneId ?? (layout == null ? null : leafPaneIds(layout).first),
    );
  }

  /// Opens [path] in the editor. When the file is already open the existing
  /// pane is focused; otherwise it is added side by side with the active pane.
  Future<void> openFile(String path) async {
    final existing = state.layout;
    for (final pane in existing == null ? const <EditorPaneState>[] : panesOf(existing)) {
      if (pane.path == path) {
        state = EditorWorkspaceState(layout: existing, activePaneId: pane.id);
        return;
      }
    }

    EditorPaneState loaded;
    try {
      final text = await _fs.readText(path);
      loaded = EditorPaneState(id: _newId(), path: path, text: text);
    } catch (e) {
      loaded = EditorPaneState(
        id: _newId(),
        path: path,
        error: 'Could not read file.\n${e.toString()}',
      );
    }

    final current = state.layout;
    if (current == null) {
      _set(PaneLeaf(pane: loaded), activePaneId: loaded.id);
      return;
    }
    final active = state.activePaneId ?? leafPaneIds(current).first;
    final merged = splitLeafWith(
      current,
      active,
      PaneLeaf(pane: loaded),
      Axis.horizontal,
    );
    _set(merged, activePaneId: loaded.id);
  }

  /// Splits the active pane (duplicating its file into a second view).
  void splitActive(Axis axis) {
    final layout = state.layout;
    if (layout == null) return;
    final activeId = state.activePaneId;
    final target = [
      for (final p in panesOf(layout))
        if (p.id == activeId) p,
    ].firstOrNull;
    if (target == null) return;

    final copy = EditorPaneState(
      id: _newId(),
      path: target.path,
      text: target.text,
      error: target.error,
    );
    final merged = splitLeafWith(
      layout,
      target.id,
      PaneLeaf(pane: copy),
      axis,
    );
    _set(merged, activePaneId: copy.id);
  }

  void closePane(String id) {
    final layout = state.layout;
    if (layout == null) return;
    final next = removeLeafFrom(layout, id);
    _set(next, activePaneId: next == null ? null : leafPaneIds(next).first);
  }

  void closeAll() => _set(null);

  void focusPane(String id) {
    final layout = state.layout;
    if (layout == null) return;
    if (leafPaneIds(layout).contains(id)) {
      state = EditorWorkspaceState(layout: layout, activePaneId: id);
    }
  }

  void syncDirty(String id, bool dirty) {
    final layout = state.layout;
    if (layout == null) return;
    final before = [
      for (final p in panesOf(layout))
        if (p.id == id) p,
    ].firstOrNull;
    if (before == null || before.dirty == dirty) return;
    PaneArea rewrite(PaneArea node) {
      switch (node) {
        case PaneLeaf(:final pane):
          if (pane.id == id) return PaneLeaf(pane: pane.copyWith(dirty: dirty));
          return node;
        case PaneSplit(:final axis, :final children, :final weights):
          return PaneSplit(
            axis: axis,
            children: [for (final c in children) rewrite(c)],
            weights: weights,
          );
      }
    }

    _set(rewrite(layout));
  }

  /// Persists [text] for [id]. Returns false when the pane is uneditable.
  Future<bool> save(String id, String text) async {
    final layout = state.layout;
    if (layout == null) return false;
    final pane = [
      for (final p in panesOf(layout))
        if (p.id == id) p,
    ].firstOrNull;
    if (pane == null || !pane.editable) return false;
    try {
      await _fs.writeText(pane.path, text);
    } catch (e) {
      return false;
    }
    PaneArea rewrite(PaneArea node) {
      switch (node) {
        case PaneLeaf(pane: final leaf):
          if (leaf.id == id) {
            return PaneLeaf(pane: EditorPaneState(
              id: id,
              path: pane.path,
              text: text,
              dirty: false,
              error: null,
            ));
          }
          return node;
        case PaneSplit(:final axis, :final children, :final weights):
          return PaneSplit(
            axis: axis,
            children: [for (final c in children) rewrite(c)],
            weights: weights,
          );
      }
    }

    state = EditorWorkspaceState(
      layout: rewrite(layout),
      activePaneId: state.activePaneId,
    );
    return true;
  }

  /// Discards unsaved edits by reloading the file from disk.
  Future<void> reload(String id) async {
    final layout = state.layout;
    if (layout == null) return;
    final pane = [
      for (final p in panesOf(layout))
        if (p.id == id) p,
    ].firstOrNull;
    if (pane == null) return;
    String text;
    String? error;
    try {
      text = await _fs.readText(pane.path);
    } catch (e) {
      error = 'Could not read file.\n${e.toString()}';
      text = pane.text;
    }
    PaneArea rewrite(PaneArea node) {
      switch (node) {
        case PaneLeaf(pane: final leaf):
          if (leaf.id == id) {
            return PaneLeaf(
              pane: EditorPaneState(
                id: id,
                path: pane.path,
                text: text,
                dirty: false,
                error: error,
              ),
            );
          }
          return node;
        case PaneSplit(:final axis, :final children, :final weights):
          return PaneSplit(
            axis: axis,
            children: [for (final c in children) rewrite(c)],
            weights: weights,
          );
      }
    }

    state = EditorWorkspaceState(
      layout: rewrite(layout),
      activePaneId: state.activePaneId,
    );
  }

  void adjustWeight(String steerId, double fraction) {
    final layout = state.layout;
    if (layout == null) return;
    _set(adjustWeightToward(layout, steerId, fraction));
  }
}

/// Editor workspace state, isolated per tab (`tabId`).
final fileWorkspaceProvider =
    NotifierProvider.family<FileWorkspaceNotifier, EditorWorkspaceState, String>(
      FileWorkspaceNotifier.new,
    );

String _basename(String p) {
  var s = p;
  while (s.endsWith('/') || s.endsWith('\\')) {
    s = s.substring(0, s.length - 1);
  }
  final parts = s.split(RegExp(r'[/\\]'));
  String? last;
  for (final part in parts) {
    if (part.isNotEmpty) last = part;
  }
  return last ?? s;
}