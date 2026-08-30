import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Thin wrapper over the GitHub REST API using a personal access token.
///
/// Every method returns fresh objects and throws [GithubException] on failure,
/// so callers can display a message and stay offline-first.
class GithubService {
  GithubService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _base = 'https://api.github.com';

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_base$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> _get(String token, String path,
      [Map<String, String>? query]) async {
    final res = await _client.get(_uri(path, query), headers: _headers(token));
    final body = _decode(res);
    if (res.statusCode != 200) {
      throw GithubException(
        body['message'] as String? ?? 'GitHub request failed',
        status: res.statusCode,
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String token,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final req = http.Request(method, _uri(path))
      ..headers.addAll(_headers(token));
    if (body != null) {
      req.body = jsonEncode(body);
      req.headers['Content-Type'] = 'application/json';
    }
    final streamed = await _client.send(req);
    final res = await http.Response.fromStream(streamed);
    final decoded = _decode(res);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw GithubException(
        decoded['message'] as String? ?? 'GitHub request failed',
        status: res.statusCode,
      );
    }
    return decoded;
  }

  Map<String, dynamic> _decode(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      return body is Map<String, dynamic> ? body : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Fetches the authenticated user (verifies the token).
  Future<GithubUser> me(String token) async {
    final j = await _get(token, '/user');
    return GithubUser(
      login: j['login'] as String? ?? '',
      name: j['name'] as String?,
      avatarUrl: j['avatar_url'] as String?,
    );
  }

  /// The user's own repositories (not forks), most recently updated first.
  Future<List<GithubRepo>> repos(String token) async {
    final out = <GithubRepo>[];
    var page = 1;
    while (true) {
      final res = await _client.get(
        _uri('/user/repos', {
          'per_page': '100',
          'page': '$page',
          'sort': 'updated',
        }),
        headers: _headers(token),
      );
      if (res.statusCode != 200) {
        final msg = _decode(res)['message'] as String? ?? 'GitHub request failed';
        throw GithubException(msg, status: res.statusCode);
      }
      final list = jsonDecode(res.body) as List<dynamic>;
      out.addAll([
        for (final r in list)
          GithubRepo.fromJson(r as Map<String, dynamic>),
      ]);
      if (list.length < 100) break;
      page++;
    }
    return [
      for (final r in out)
        if (!r.fork) r,
    ];
  }

  /// Issues for [repo] (`owner/name`), optionally filtered by [state].
  Future<List<GithubIssue>> issues(
    String token,
    String repo, {
    String state = 'open',
  }) async {
    final res = await _client.get(
      _uri('/repos/$repo/issues', {'state': state, 'per_page': '100'}),
      headers: _headers(token),
    );
    if (res.statusCode != 200) {
      throw GithubException(
        _decode(res)['message'] as String? ?? 'GitHub request failed',
        status: res.statusCode,
      );
    }
    return [
      for (final i in jsonDecode(res.body) as List<dynamic>)
        GithubIssue.fromJson(i as Map<String, dynamic>),
    ];
  }

  Future<GithubIssue> createIssue(
    String token,
    String repo,
    String title, {
    String? body,
  }) async {
    final j = await _send('POST', token, '/repos/$repo/issues', body: {
      'title': title,
      if (body != null && body.isNotEmpty) 'body': body,
    });
    return GithubIssue.fromJson(j);
  }

  Future<void> setIssueState(
    String token,
    String repo,
    int number, {
    required bool closed,
  }) async {
    await _send('PATCH', token, '/repos/$repo/issues/$number', body: {
      'state': closed ? 'closed' : 'open',
    });
  }

  /// Recent pull requests for [repo].
  Future<List<GithubPull>> pulls(String token, String repo) async {
    final res = await _client.get(
      _uri('/repos/$repo/pulls', {'state': 'all', 'per_page': '20'}),
      headers: _headers(token),
    );
    if (res.statusCode != 200) {
      throw GithubException(
        _decode(res)['message'] as String? ?? 'GitHub request failed',
        status: res.statusCode,
      );
    }
    return [
      for (final p in jsonDecode(res.body) as List<dynamic>)
        GithubPull.fromJson(p as Map<String, dynamic>),
    ];
  }
}

class GithubException implements Exception {
  GithubException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() =>
      status == null ? 'GitHub: $message' : 'GitHub ($status): $message';
}

@immutable
class GithubUser {
  const GithubUser({required this.login, this.name, this.avatarUrl});
  final String login;
  final String? name;
  final String? avatarUrl;
}

@immutable
class GithubRepo {
  const GithubRepo({
    required this.fullName,
    this.description,
    this.pushedAt,
    this.fork = false,
  });
  final String fullName;
  final String? description;
  final DateTime? pushedAt;
  final bool fork;

  factory GithubRepo.fromJson(Map<String, dynamic> j) => GithubRepo(
    fullName: j['full_name'] as String? ?? '',
    description: j['description'] as String?,
    pushedAt: DateTime.tryParse(j['pushed_at'] as String? ?? ''),
    fork: j['fork'] as bool? ?? false,
  );
}

@immutable
class GithubIssue {
  const GithubIssue({
    required this.number,
    required this.title,
    required this.state,
    this.htmlUrl,
    this.updatedAt,
    this.user,
  });
  final int number;
  final String title;
  final String state;
  final String? htmlUrl;
  final DateTime? updatedAt;
  final String? user;

  factory GithubIssue.fromJson(Map<String, dynamic> j) => GithubIssue(
    number: (j['number'] as num?)?.toInt() ?? 0,
    title: j['title'] as String? ?? '',
    state: j['state'] as String? ?? 'open',
    htmlUrl: j['html_url'] as String?,
    updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? ''),
    user: ((j['user'] as Map<String, dynamic>?)?['login']) as String?,
  );
}

@immutable
class GithubPull {
  const GithubPull({
    required this.number,
    required this.title,
    required this.state,
    this.htmlUrl,
    this.user,
    this.updatedAt,
  });
  final int number;
  final String title;
  final String state;
  final String? htmlUrl;
  final String? user;
  final DateTime? updatedAt;

  factory GithubPull.fromJson(Map<String, dynamic> j) => GithubPull(
    number: (j['number'] as num?)?.toInt() ?? 0,
    title: j['title'] as String? ?? '',
    state: j['state'] as String? ?? 'open',
    htmlUrl: j['html_url'] as String?,
    user: ((j['user'] as Map<String, dynamic>?)?['login']) as String?,
    updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? ''),
  );
}