import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// WakaTime API access (stats only — no heartbeats are sent from Lumen).
///
/// Authentication uses HTTP Basic with the API key as the username and an
/// empty password, i.e. `base64("key:")`.
class WakatimeService {
  WakatimeService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _base = 'https://wakatime.com/api/v1';

  Map<String, String> _headers(String key) => {
    'Authorization':
        'Basic ${base64Encode(utf8.encode('$key:'))}',
    'Content-Type': 'application/json',
  };

  /// Validates the key and returns the associated user's display name.
  Future<String?> user(String key) async {
    final res = await _client.get(
      Uri.parse('$_base/users/current'),
      headers: _headers(key),
    );
    if (res.statusCode != 200) {
      throw WakatimeException(
        'WakaTime rejected the API key (${res.statusCode})',
        status: res.statusCode,
      );
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return j['data']?['display_name'] as String?;
  }

  /// Aggregated stats for the trailing [range] (`last_7_days`, `last_30_days`).
  Future<WakatimeStats> stats(
    String key, {
    String range = 'last_7_days',
  }) async {
    final res = await _client.get(
      Uri.parse('$_base/users/current/stats/$range'),
      headers: _headers(key),
    );
    if (res.statusCode != 200) {
      throw WakatimeException(
        'WakaTime stats failed (${res.statusCode})',
        status: res.statusCode,
      );
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return WakatimeStats.fromJson(j['data'] as Map<String, dynamic>? ?? {});
  }
}

class WakatimeException implements Exception {
  WakatimeException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() =>
      status == null ? 'WakaTime: $message' : 'WakaTime ($status): $message';
}

@immutable
class WakatimeStats {
  const WakatimeStats({
    this.totalSeconds = 0,
    this.humanTotal = '',
    this.dailyAverageHuman = '',
    this.totalActivities = 0,
    this.languages = const [],
  });

  final double totalSeconds;
  final String humanTotal;
  final String dailyAverageHuman;
  final int totalActivities;
  final List<WakatimeLanguage> languages;

  factory WakatimeStats.fromJson(Map<String, dynamic> j) {
    final rawLangs = (j['languages'] as List<dynamic>? ?? const []);
    return WakatimeStats(
      totalSeconds: (j['total_seconds'] as num?)?.toDouble() ?? 0,
      humanTotal: j['human_readable_total'] as String? ?? '',
      dailyAverageHuman: j['human_readable_daily_average'] as String? ?? '',
      totalActivities: (j['total_activities'] as num?)?.toInt() ?? 0,
      languages: [
        for (final l in rawLangs)
          WakatimeLanguage.fromJson(l as Map<String, dynamic>),
      ],
    );
  }
}

@immutable
class WakatimeLanguage {
  const WakatimeLanguage({
    required this.name,
    required this.percent,
    required this.humanTime,
  });
  final String name;
  final double percent;
  final String humanTime;

  factory WakatimeLanguage.fromJson(Map<String, dynamic> j) =>
      WakatimeLanguage(
        name: j['name'] as String? ?? 'Unknown',
        percent: (j['percent'] as num?)?.toDouble() ?? 0,
        humanTime: j['text'] as String? ?? '',
      );
}