import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'lumen_ffi.dart';

/// Results of compiling filter lists into WebKit content-rule JSON parts.
@immutable
class UblockCompileResult {
  const UblockCompileResult({required this.parts, required this.stats});

  /// One JSON document per WebKit content-filter slot (respects the ~50k
  /// rule / ~150k ability caps).
  final List<String> parts;
  final Map<String, dynamic> stats;
}

/// Thin wrapper over `libublock`'s `ublock_call` FFI dispatch.
class UblockService {
  UblockService(this._ffi);

  final LumenFfi _ffi;

  String version() =>
      (_ffi.ublock('ublock.version') as Map<String, dynamic>)['version']
          as String? ??
      '?';

  UblockCompileResult compile(
    List<Map<String, Object?>> lists, {
    int? maxRulesPerPart,
  }) {
    final data = _ffi.ublock('ublock.compile', {
      'lists': lists,
      'max_rules_per_part': ?maxRulesPerPart,
    }) as Map<String, dynamic>;
    final parts = [
      for (final p in (data['parts'] as List? ?? const [])) p as String,
    ];
    final stats = (data['stats'] as Map<String, dynamic>?) ?? {};
    final parsed = {
      for (final e in stats.entries)
        e.key: e.value is String
            ? e.value
            : e.value is num
            ? e.value as num
            : jsonEncode(e.value),
    };
    return UblockCompileResult(parts: parts, stats: parsed);
  }
}