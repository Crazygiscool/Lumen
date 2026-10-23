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
    text: (j['text'] ?? j['quote'] ?? '').toString().trim(),
    author:
        (j['author'] ??
                j['speaker'] ??
                j['character'] ??
                j['source'] ??
                'Unknown')
            .toString()
            .trim(),
  );
}

/// Where the dashboard quote comes from.
enum QuoteSource {
  /// A curated list bundled with the app. Works fully offline.
  offline,

  /// A public quotes API fetched at runtime. Requires internet.
  online,
}

extension QuoteSourceInfo on QuoteSource {
  String get label => switch (this) {
    QuoteSource.offline => 'Offline',
    QuoteSource.online => 'Online API',
  };
}

/// Provides the dashboard quote: offline by default, online when opted in.
class QuoteService {
  QuoteService({http.Client? client, Random? random})
    : _client = client ?? http.Client(),
      _random = random ?? Random();

  final http.Client _client;
  final Random _random;

  /// Public dataset used for the online source: a keyless, CORS-friendly JSON
  /// list of Harry Potter quotes. If it is unreachable the caller falls back to
  /// the bundled [offline] list.
  static const onlineEndpoint =
      'https://raw.githubusercontent.com/SyntaxOutlaw/HarryPotterAPI/main/'
      'app/data/quotes.json';

  Quote offline() => _offline[_random.nextInt(_offline.length)];

  /// Releases the underlying HTTP client.
  void close() => _client.close();

  /// Fetches a random quote from the configured online source.
  ///
  /// Throws on network/parse failure; callers fall back to [offline].
  Future<Quote> fetchOnline() async {
    final res = await _client
        .get(Uri.parse(onlineEndpoint))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      throw Exception('Quote source returned ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final items = _extractItems(body);
    if (items.isEmpty) throw Exception('Quote source returned no quotes');
    final picked =
        items.length == 1 ? items.first : items[_random.nextInt(items.length)];
    final quote = Quote.fromJson(picked);
    if (quote.text.isEmpty) throw Exception('Quote source returned an empty quote');
    return quote;
  }

  /// Handles both `[...]` and `{data: [...]}` / `{results: [...]}` shapes.
  static List<Map<String, dynamic>> _extractItems(Object? body) {
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
    }
    return const [];
  }

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
