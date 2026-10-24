import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A quote shown on the journal dashboard.
@immutable
class Quote {
  const Quote({required this.text, required this.author});

  final String text;
  final String author;

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
    text: (j['text'] ?? j['quote'] ?? j['q'] ?? '').toString().trim(),
    author:
        (j['author'] ??
                j['a'] ??
                j['speaker'] ??
                j['character'] ??
                j['source'] ??
                'Unknown')
            .toString()
            .trim(),
  );
}

/// A quote source that failed in a way worth surfacing to the user.
class QuoteException implements Exception {
  QuoteException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Where the dashboard quote comes from.
enum QuoteSource {
  /// ZenQuotes' public random endpoint. Keyless; the default.
  zenquotes,

  /// A curated Harry Potter list bundled with the app. Fully offline.
  offline,

  /// API Ninjas v2 random quotes. Requires a (free) API key.
  apiNinjas,

  /// Any JSON URL the user provides (optionally with an `X-Api-Key`).
  custom,
}

/// Sources the Settings UI offers.
///
/// `apiNinjas` and `custom` need an API key or URL that has no entry UI yet, so
/// they are kept in the model but hidden until that exists.
const List<QuoteSource> selectableQuoteSources = [
  QuoteSource.offline,
  QuoteSource.zenquotes,
];

extension QuoteSourceInfo on QuoteSource {
  String get label => switch (this) {
    QuoteSource.zenquotes => 'ZenQuotes (no key)',
    QuoteSource.offline => 'Harry Potter (offline)',
    QuoteSource.apiNinjas => 'API Ninjas (key)',
    QuoteSource.custom => 'Custom URL',
  };

  String get description => switch (this) {
    QuoteSource.zenquotes =>
      'Public random quotes from zenquotes.io. No API key needed.',
    QuoteSource.offline =>
      'A bundled list of Harry Potter quotes. Works with no network.',
    QuoteSource.apiNinjas =>
      'Free key from api-ninjas.com. Paste it below.',
    QuoteSource.custom =>
      'Point at your own JSON endpoint (a quote list or single object).',
  };

  bool get needsApiKey => this == QuoteSource.apiNinjas;
  bool get allowsApiKey =>
      this == QuoteSource.apiNinjas || this == QuoteSource.custom;
  bool get needsUrl => this == QuoteSource.custom;
}

/// Provides the dashboard quote from the selected source.
class QuoteService {
  QuoteService({
    http.Client? client,
    Random? random,
    this.source = QuoteSource.zenquotes,
    this.apiKey = '',
    this.customUrl = '',
  }) : _client = client ?? http.Client(),
       _random = random ?? Random();

  final http.Client _client;
  final Random _random;
  final QuoteSource source;
  final String apiKey;
  final String customUrl;

  static const zenquotesEndpoint = 'https://zenquotes.io/api/random';
  static const apiNinjasEndpoint = 'https://api.api-ninjas.com/v2/randomquotes';

  /// A random quote from the bundled Harry Potter list (no network).
  Quote offline() => offlineRandom(_random);

  /// A random quote from the bundled list, usable without a service instance.
  static Quote offlineRandom([Random? random]) {
    final r = random ?? Random();
    return _offline[r.nextInt(_offline.length)];
  }

  /// Fetches a quote from the configured source.
  ///
  /// Throws [QuoteException] with a user-facing message on failure; callers
  /// fall back to the bundled offline list.
  Future<Quote> fetch() async {
    switch (source) {
      case QuoteSource.offline:
        return offline();
      case QuoteSource.zenquotes:
        return _get(zenquotesEndpoint);
      case QuoteSource.apiNinjas:
        final key = apiKey.trim();
        if (key.isEmpty) {
          throw QuoteException('Add your API Ninjas key in Settings.');
        }
        return _get(apiNinjasEndpoint, headers: {'X-Api-Key': key});
      case QuoteSource.custom:
        final url = customUrl.trim();
        if (url.isEmpty) {
          throw QuoteException('Add a custom quote URL in Settings.');
        }
        final uri = Uri.tryParse(url);
        if (uri == null || !uri.hasScheme) {
          throw QuoteException('That custom URL doesn\u2019t look valid.');
        }
        final key = apiKey.trim();
        return _get(
          url,
          headers: key.isEmpty ? null : {'X-Api-Key': key},
        );
    }
  }

  Future<Quote> _get(String url, {Map<String, String>? headers}) async {
    final res = await _client
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      throw QuoteException('Quote source returned ${res.statusCode}.');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final items = extractItems(body);
    if (items.isEmpty) {
      throw QuoteException('Quote source returned no quotes.');
    }
    final picked =
        items.length == 1 ? items.first : items[_random.nextInt(items.length)];
    final quote = Quote.fromJson(picked);
    if (quote.text.isEmpty) {
      throw QuoteException('Quote source returned an empty quote.');
    }
    return quote;
  }

  /// Handles the common response shapes: a list, `{data: [...]}`,
  /// `{results: [...]}`, or a single quote object.
  @visibleForTesting
  static List<Map<String, dynamic>> extractItems(Object? body) {
    if (body is List) {
      return body.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    if (body is Map) {
      final data = body['data'] ?? body['results'] ?? body['quotes'];
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
      if (body.containsKey('quote') ||
          body.containsKey('text') ||
          body.containsKey('q')) {
        return [body.cast<String, dynamic>()];
      }
    }
    return const [];
  }

  /// Releases the underlying HTTP client.
  void close() => _client.close();

  /// Curated Harry Potter quotes bundled so the card always works offline.
  static const List<Quote> _offline = [
    Quote(
      text: 'It does not do to dwell on dreams and forget to live.',
      author: 'Albus Dumbledore',
    ),
    Quote(
      text: 'Happiness can be found even in the darkest of times, if one only '
          'remembers to turn on the light.',
      author: 'Albus Dumbledore',
    ),
    Quote(
      text: 'It is our choices, Harry, that show what we truly are, far more '
          'than our abilities.',
      author: 'Albus Dumbledore',
    ),
    Quote(
      text: 'We are only as strong as we are united, as weak as we are divided.',
      author: 'Albus Dumbledore',
    ),
    Quote(
      text: 'It matters not what someone is born, but what they grow to be.',
      author: 'Albus Dumbledore',
    ),
    Quote(
      text: 'Wit beyond measure is man\u2019s greatest treasure.',
      author: 'Rowena Ravenclaw',
    ),
    Quote(
      text: 'Help will always be given at Hogwarts to those who ask for it.',
      author: 'Albus Dumbledore',
    ),
    Quote(
      text: 'Differences of habit and language are nothing at all if our aims '
          'are identical and our hearts are open.',
      author: 'Albus Dumbledore',
    ),
    Quote(
      text: 'There are some things you can\u2019t share without ending up liking '
          'each other.',
      author: 'Albus Dumbledore',
    ),
    Quote(
      text: 'Do not pity the dead, Harry. Pity the living, and, above all, '
          'those who live without love.',
      author: 'Albus Dumbledore',
    ),
    Quote(
      text: 'Of course it is happening inside your head, Harry, but why on '
          'earth should that mean that it is not real?',
      author: 'Albus Dumbledore',
    ),
    Quote(
      text: 'You sort of start thinking anything\u2019s possible if you\u2019ve got '
          'enough nerve.',
      author: 'Ginny Weasley',
    ),
    Quote(
      text: 'It\u2019s not how much time you have, it\u2019s how you use it.',
      author: 'Albus Dumbledore',
    ),
    Quote(
      text: 'Understanding is the first step to acceptance, and only with '
          'acceptance can there be recovery.',
      author: 'Albus Dumbledore',
    ),
    Quote(
      text: 'Never trust anything that can think for itself if you can\u2019t see '
          'where it keeps its brain.',
      author: 'Arthur Weasley',
    ),
    Quote(
      text: 'Whatever house I\u2019m in, I hope she\u2019s not in it.',
      author: 'Ron Weasley',
    ),
    Quote(
      text: 'We\u2019ve all got both light and dark inside us. What matters is the '
          'part we choose to act on.',
      author: 'Sirius Black',
    ),
    Quote(
      text: 'The world isn\u2019t split into good people and Death Eaters.',
      author: 'Sirius Black',
    ),
    Quote(
      text: 'If you want to know what a man\u2019s like, take a good look at how '
          'he treats his inferiors, not his equals.',
      author: 'Sirius Black',
    ),
    Quote(
      text: 'You\u2019re a wizard, Harry.',
      author: 'Rubeus Hagrid',
    ),
    Quote(
      text: 'I am not worried, Harry. I am with you.',
      author: 'Albus Dumbledore',
    ),
    Quote(
      text: 'Greatness inspires envy, envy engenders spite, spite spawns lies.',
      author: 'Tom Riddle',
    ),
    Quote(
      text: 'To the well-organised mind, death is but the next great adventure.',
      author: 'Albus Dumbledore',
    ),
    Quote(
      text: 'It is the unknown we fear when we look upon death and darkness, '
          'nothing more.',
      author: 'Albus Dumbledore',
    ),
  ];
}
