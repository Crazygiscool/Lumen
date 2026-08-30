import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../ffi/ublock_service.dart';
import '../../state/providers.dart';
import 'web_controller.dart';
import 'web_controllers.dart';

final ublockFfiProvider = Provider<UblockService>((ref) {
  return UblockService(ref.watch(lumenFfiProvider));
});

/// uBlock Origin's first-party lists (uAssets), compiled to WebKit
/// content-rule JSON — the "same ad blocking as uBO" core.
const kUblockLists = <({String file, String label})>[
  (file: 'easylist.txt', label: 'EasyList'),
  (file: 'easyprivacy.txt', label: 'EasyPrivacy'),
  (file: 'filters.txt', label: 'uBlock filters'),
  (file: 'annoyances.txt', label: 'Annoyances'),
];

final _uassetsBase = Uri.parse(
  'https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters',
);

enum AdBlockStatus { off, downloading, compiling, ready, error }

@immutable
class AdBlockState {
  const AdBlockState({
    this.enabled = false,
    this.status = AdBlockStatus.off,
    this.parts = const [],
    this.stats = const {},
    this.exemptHosts = const {},
    this.blockedCount = 0,
    this.lastUpdated,
    this.error,
    this.fromCache = false,
  });

  final bool enabled;
  final AdBlockStatus status;
  final List<String> parts;
  final Map<String, dynamic> stats;
  final Set<String> exemptHosts;
  final int blockedCount;
  final DateTime? lastUpdated;
  final String? error;
  final bool fromCache;

  bool get ready => enabled && parts.isNotEmpty;

  int get ruleCount => (stats['rule_count'] as num?)?.toInt() ?? 0;

  int get skippedCount =>
      (stats['skipped'] is Map)
          ? (stats['skipped'] as Map).length
          : 0;

  int totalSkipped(String reason) =>
      (stats['skipped'] as Map?)?[reason] as int? ?? 0;

  AdBlockState copyWith({
    bool? enabled,
    AdBlockStatus? status,
    List<String>? parts,
    Map<String, dynamic>? stats,
    Set<String>? exemptHosts,
    int? blockedCount,
    DateTime? lastUpdated,
    String? error,
    bool? fromCache,
  }) => AdBlockState(
    enabled: enabled ?? this.enabled,
    status: status ?? this.status,
    parts: parts ?? this.parts,
    stats: stats ?? this.stats,
    exemptHosts: exemptHosts ?? this.exemptHosts,
    blockedCount: blockedCount ?? this.blockedCount,
    lastUpdated: lastUpdated ?? this.lastUpdated,
    error: error,
    fromCache: fromCache ?? this.fromCache,
  );
}

/// Downloads uAssets, compiles them via `libublock`, caches the result and
/// pushes the filters to every live embedded webview.
class AdBlockNotifier extends Notifier<AdBlockState> {
  AdBlockNotifier([SharedPreferences? prefs]) : _prefs = prefs;

  final SharedPreferences? _prefs;

  static final Directory cacheDir = Directory(
    p.join(
      Platform.environment['HOME'] ?? '/tmp',
      '.local',
      'share',
      'lumen',
      'ublock',
    ),
  );

  @override
  AdBlockState build() {
    final enabled = _prefs?.getBool('adBlockEnabled') ?? false;
    final exempt = {
      for (final h in _prefs?.getStringList('adBlockExempt') ?? <String>[]) h,
    };
    final cached = _loadCache();
    final state = AdBlockState(
      enabled: enabled,
      status: enabled ? AdBlockStatus.ready : AdBlockStatus.off,
      parts: cached.parts,
      stats: cached.stats,
      exemptHosts: exempt,
      lastUpdated: cached.lastUpdated,
      fromCache: cached.parts.isNotEmpty,
    );
    scheduleMicrotask(() {
      if (enabled) _refresh();
    });
    return state;
  }

  // -- cache ----------------------------------------------------------------

  ({List<String> parts, Map<String, dynamic> stats, DateTime? lastUpdated})
  _loadCache() {
    try {
      if (!cacheDir.existsSync()) {
        return (parts: <String>[], stats: <String, dynamic>{}, lastUpdated: null);
      }
      final parts = <String>[];
      for (final f in cacheDir.listSync()) {
        if (f is File && f.path.endsWith('.json')) {
          parts.add(f.readAsStringSync());
        }
      }
      final metaFile = File(p.join(cacheDir.path, 'meta.json'));
      Map<String, dynamic> stats = const {};
      DateTime? updated;
      if (metaFile.existsSync()) {
        final meta = (jsonDecode(metaFile.readAsStringSync()) as Map)
            .cast<String, dynamic>();
        stats = meta['stats'] as Map<String, dynamic>? ?? const {};
        updated = DateTime.tryParse(meta['updated'] as String? ?? '');
      }
      return (parts: parts, stats: stats, lastUpdated: updated);
    } catch (_) {
      return (parts: <String>[], stats: <String, dynamic>{}, lastUpdated: null);
    }
  }

  void _saveCache(List<String> parts, Map<String, dynamic> stats) {
    try {
      cacheDir.createSync(recursive: true);
      for (final f in cacheDir.listSync()) {
        if (f is File && f.path.endsWith('.json')) {
          f.deleteSync();
        }
      }
      var i = 0;
      for (final part in parts) {
        File(p.join(cacheDir.path, 'part_${i++}.json')).writeAsStringSync(part);
      }
      File(p.join(cacheDir.path, 'meta.json')).writeAsStringSync(
        jsonEncode({
          'stats': stats,
          'updated': DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  // -- actions --------------------------------------------------------------

  Future<void> toggle(bool value) async {
    if (value == state.enabled) return;
    state = state.copyWith(enabled: value);
    _prefs?.setBool('adBlockEnabled', value);
    if (value) {
      if (state.parts.isEmpty) {
        await _refresh();
      } else {
        state = state.copyWith(status: AdBlockStatus.ready, error: null);
        _applyToAll();
      }
    } else {
      state = state.copyWith(status: AdBlockStatus.off);
      _clearAll();
    }
  }

  /// Per-site pause/resume of ad-blocking on [host].
  Future<void> toggleExempt(String host) async {
    if (host.isEmpty) return;
    final next = {...state.exemptHosts};
    if (!next.add(host)) next.remove(host);
    state = state.copyWith(exemptHosts: next);
    _prefs?.setStringList('adBlockExempt', next.toList());
    _applyToAll();
  }

  bool isExempt(String host) => state.exemptHosts.contains(host);

  void recordBlocked(int n) {
    if (n <= 0) return;
    state = state.copyWith(blockedCount: state.blockedCount + n);
  }

  /// Re-downloads uAssets and recompiles. Uses cached list text as a fallback.
  Future<void> refresh({bool force = false}) async {
    final already = state.parts.isNotEmpty;
    if (already && !force) {
      state = state.copyWith(status: AdBlockStatus.ready, error: null);
      _applyToAll();
      return;
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    state = state.copyWith(status: AdBlockStatus.downloading, error: null);
    final lists = <({String file, String label, String text})>[];
    var anyNetwork = false;

    for (final l in kUblockLists) {
      final cachedFile = File(p.join(cacheDir.path, '${l.file}.txt'));
      var text = cachedFile.existsSync() ? cachedFile.readAsStringSync() : '';
      try {
        final res = await http
            .get(_uassetsBase.replace(path: '$_uassetsBase.path/${l.file}'))
            .timeout(const Duration(seconds: 30));
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          text = res.body;
          anyNetwork = true;
          cachedFile.createSync(recursive: true);
          cachedFile.writeAsStringSync(text);
        }
      } catch (_) {}
      lists.add((file: l.file, label: l.label, text: text));
    }

    if (!anyNetwork && lists.every((l) => l.text.isEmpty)) {
      state = state.copyWith(
        status: AdBlockStatus.error,
        error: 'Could not download filter lists and no cache is available.',
      );
      return;
    }

    state = state.copyWith(status: AdBlockStatus.compiling);
    try {
      final result = ref.read(ublockFfiProvider).compile([
        for (final l in lists) {'name': l.file, 'text': l.text},
      ]);
      state = state.copyWith(
        status: AdBlockStatus.ready,
        parts: result.parts,
        stats: result.stats,
        lastUpdated: DateTime.now(),
        fromCache: !anyNetwork,
        error: null,
      );
      _saveCache(result.parts, result.stats);
      _applyToAll();
    } catch (e) {
      state = state.copyWith(
        status: AdBlockStatus.error,
        error: e.toString(),
      );
    }
  }

  // -- push to live webviews --------------------------------------------------

  void _applyToAll() {
    for (final c in WebControllers.instance.all) {
      _apply(c);
    }
  }

  void _clearAll() {
    for (final c in WebControllers.instance.all) {
      unawaited(c.clearFilters());
    }
  }

  void _apply(LumenWebViewController c) {
    if (!state.enabled) {
      unawaited(c.clearFilters());
      return;
    }
    if (state.exemptHosts.contains(c.host) || state.parts.isEmpty) {
      unawaited(c.clearFilters());
      return;
    }
    unawaited(c.setFilters(state.parts));
  }
}

final adBlockProvider = NotifierProvider<AdBlockNotifier, AdBlockState>(
  AdBlockNotifier.new,
);