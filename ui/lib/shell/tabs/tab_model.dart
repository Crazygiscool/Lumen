import 'dart:io';

import 'package:flutter/material.dart';

import '../../state/providers.dart';

enum TabKind { newtab, lumen, web }

extension LumenSectionInfo on LumenSection {
  String get title => switch (this) {
    LumenSection.files => 'Files',
    LumenSection.vault => 'Vault',
    LumenSection.graph => 'Graph',
    LumenSection.osLab => 'OS Lab',
    LumenSection.console => 'Console',
    LumenSection.settings => 'Settings',
  };

  String get pathName => switch (this) {
    LumenSection.files => 'files',
    LumenSection.vault => 'vault',
    LumenSection.graph => 'graph',
    LumenSection.osLab => 'oslab',
    LumenSection.console => 'console',
    LumenSection.settings => 'settings',
  };

  IconData get icon => switch (this) {
    LumenSection.files => Icons.folder_outlined,
    LumenSection.vault => Icons.lock_outline,
    LumenSection.graph => Icons.hub_outlined,
    LumenSection.osLab => Icons.memory,
    LumenSection.console => Icons.terminal,
    LumenSection.settings => Icons.settings_outlined,
  };
}

const _pageNames = <String, LumenSection>{
  'files': LumenSection.files,
  'vault': LumenSection.vault,
  'graph': LumenSection.graph,
  'oslab': LumenSection.osLab,
  'lab': LumenSection.osLab,
  'console': LumenSection.console,
  'settings': LumenSection.settings,
};

const newTabSpec = TabSpec(
  kind: TabKind.newtab,
  url: 'lumen://newtab',
  title: 'New Tab',
);

/// A resolved "what should this tab show" from raw address-bar input.
@immutable
class TabSpec {
  const TabSpec({
    required this.kind,
    this.page,
    this.url = '',
    this.title = '',
    this.path,
  });

  final TabKind kind;
  final LumenSection? page;
  final String url;
  final String title;
  final String? path;
}

/// Turns raw address-bar text into a [TabSpec]:
/// lumen:// pages, web urls (external browser) and plain-text search.
TabSpec resolveInput(String raw, {String homePath = ''}) {
  final input = raw.trim();
  if (input.isEmpty) return newTabSpec;

  final lower = input.toLowerCase();
  if (lower.startsWith('lumen:')) {
    var rest = input.substring('lumen:'.length);
    rest = rest.replaceFirst(RegExp(r'^//'), '');
    rest = rest.replaceFirst(RegExp(r'^/+'), '');
    final slash = rest.indexOf('/');
    final name = (slash == -1 ? rest : rest.substring(0, slash)).toLowerCase();
    final section = _pageNames[name];
    if (section == null) return newTabSpec;

    if (slash == -1 || slash >= rest.length - 1) {
      return TabSpec(
        kind: TabKind.lumen,
        page: section,
        url: 'lumen://${section.pathName}',
        title: section.title,
      );
    }

    final segment = Uri.decodeComponent(rest.substring(slash + 1));
    if (section == LumenSection.files) {
      var path = segment.isEmpty ? homePath : segment;
      if (!path.startsWith('/')) {
        path = homePath.isEmpty ? '/$path' : '$homePath/$path';
      }
      final encoded = Uri.encodeFull(path);
      return TabSpec(
        kind: TabKind.lumen,
        page: section,
        url: 'lumen://files//$encoded',
        title: 'Files · ${_basename(path)}',
        path: path,
      );
    }
    if (section == LumenSection.vault) {
      if (segment.isEmpty) {
        return TabSpec(
          kind: TabKind.lumen,
          page: section,
          url: 'lumen://vault',
          title: section.title,
        );
      }
      final encoded = Uri.encodeFull(segment);
      return TabSpec(
        kind: TabKind.lumen,
        page: section,
        url: 'lumen://vault/$encoded',
        title: 'Vault · ${_basename(segment)}',
        path: segment,
      );
    }
    return TabSpec(
      kind: TabKind.lumen,
      page: section,
      url: 'lumen://${section.pathName}',
      title: section.title,
    );
  }

  final web = _asWebUrl(input);
  if (web != null) {
    final host = Uri.tryParse(web)?.host ?? '';
    return TabSpec(
      kind: TabKind.web,
      url: web,
      title: host.isEmpty ? 'Web' : host,
    );
  }

  return TabSpec(
    kind: TabKind.web,
    url: 'https://duckduckgo.com/?q=${Uri.encodeQueryComponent(input)}',
    title: 'Search · $input',
  );
}

String? _asWebUrl(String input) {
  final lower = input.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    final u = Uri.tryParse(input);
    if (u != null && u.host.isNotEmpty) return input;
    return null;
  }
  if (lower.startsWith('www.')) return 'https://$input';
  if (RegExp(r'^localhost(:\d+)?(/.*)?$').hasMatch(lower)) {
    return 'https://$input';
  }
  final domain = RegExp(
    r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+([:/?#][^\s]*)?$',
  );
  if (domain.hasMatch(lower)) {
    final u = Uri.tryParse('https://$input');
    if (u != null && u.host.isNotEmpty) return 'https://$input';
  }
  return null;
}

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

/// Opens [url] in the host operating system's default browser / handler.
Future<bool> openInSystemBrowser(String url) async {
  try {
    if (Platform.isWindows) {
      final res = await Process.run('cmd', ['/c', 'start', '', url]);
      return res.exitCode == 0;
    }
    final cmd = Platform.isMacOS ? 'open' : 'xdg-open';
    final res = await Process.run(cmd, [url]);
    return res.exitCode == 0;
  } catch (_) {
    return false;
  }
}

@immutable
class LumenHistoryEntry {
  const LumenHistoryEntry({
    required this.kind,
    required this.url,
    this.title = '',
    this.page,
  });

  final TabKind kind;
  final String url;
  final String title;
  final LumenSection? page;
}

@immutable
class LumenTab {
  const LumenTab({
    required this.id,
    required this.spec,
    this.history = const [],
    this.historyIndex = -1,
  });

  final String id;
  final TabSpec spec;
  final List<LumenHistoryEntry> history;
  final int historyIndex;

  String get url => spec.url;
  String get title => spec.title;
  TabKind get kind => spec.kind;
  LumenSection? get page => spec.page;
  String? get path => spec.path;

  bool get canGoBack => historyIndex > 0;
  bool get canGoForward =>
      historyIndex >= 0 && historyIndex < history.length - 1;

  IconData get icon {
    if (kind == TabKind.lumen) return page?.icon ?? Icons.pages;
    if (kind == TabKind.web) return Icons.public;
    return Icons.window;
  }

  LumenTab copyWith({
    TabSpec? spec,
    List<LumenHistoryEntry>? history,
    int? historyIndex,
  }) {
    return LumenTab(
      id: id,
      spec: spec ?? this.spec,
      history: history ?? this.history,
      historyIndex: historyIndex ?? this.historyIndex,
    );
  }

  LumenTab navigate(TabSpec next) {
    final trimmed = history.sublist(0, historyIndex + 1);
    final extended = [
      ...trimmed,
      LumenHistoryEntry(
        kind: next.kind,
        url: next.url,
        title: next.title,
        page: next.page,
      ),
    ];
    return copyWith(
      spec: next,
      history: extended,
      historyIndex: extended.length - 1,
    );
  }

  LumenTab goBack() {
    if (!canGoBack) return this;
    final e = history[historyIndex - 1];
    return copyWith(
      spec: TabSpec(kind: e.kind, page: e.page, url: e.url, title: e.title),
      historyIndex: historyIndex - 1,
    );
  }

  LumenTab goForward() {
    if (!canGoForward) return this;
    final e = history[historyIndex + 1];
    return copyWith(
      spec: TabSpec(kind: e.kind, page: e.page, url: e.url, title: e.title),
      historyIndex: historyIndex + 1,
    );
  }

  /// Live URL/title update from the embedded webview. The WebView owns its own
  /// history, so this only touches the current spec + head history entry.
  LumenTab syncWeb({String? url, String? title}) {
    if (kind != TabKind.web) return this;
    var next = spec;
    next = TabSpec(
      kind: next.kind,
      page: next.page,
      url: url ?? next.url,
      title: title ?? next.title,
    );
    final h = [...history];
    final idx = historyIndex < 0 ? 0 : historyIndex;
    if (idx >= 0 && idx < h.length) {
      final e = h[idx];
      h[idx] = LumenHistoryEntry(
        kind: e.kind,
        url: url ?? e.url,
        title: title ?? e.title,
        page: e.page,
      );
    } else if (url != null) {
      h.add(
        LumenHistoryEntry(
          kind: next.kind,
          url: url,
          title: title ?? next.title,
          page: next.page,
        ),
      );
    }
    return copyWith(
      spec: next,
      history: h,
      historyIndex: historyIndex < 0 && h.isNotEmpty ? h.length - 1 : historyIndex,
    );
  }
}
