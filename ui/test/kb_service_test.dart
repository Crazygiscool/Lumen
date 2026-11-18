import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ffi/lumen_ffi.dart';
import 'package:lumen/knowledge/kb_service.dart';

/// A fake native bridge that records the knowledge-base calls it receives.
class _FakeFfi implements LumenFfi {
  _FakeFfi(this.responses);

  final Map<String, Object?> responses;
  final List<String> methods = [];
  final List<Map<String, Object?>> args = [];

  @override
  bool get ready => true;

  @override
  String? get initError => null;

  @override
  void init() {}

  @override
  Object? core(String method, [Map<String, Object?> args = const {}]) =>
      <String, Object?>{};

  @override
  Object? plugins(String method, [Map<String, Object?> args = const {}]) =>
      <String, Object?>{};

  @override
  Object? kb(String method, [Map<String, Object?> args = const {}]) {
    methods.add(method);
    this.args.add(args);
    return responses[method];
  }
}

void main() {
  group('KbService', () {
    test('search returns parsed hits', () async {
      final ffi = _FakeFfi({
        'kb.search.query': {
          'hits': [
            {
              'path': 'alpha.md',
              'title': 'Alpha',
              'snippet': 'a <b>match</b> here',
              'score': 1.5,
            },
          ],
        },
      });
      final service = KbService(ffi);

      final hits = await service.search('match', limit: 10);

      expect(hits, hasLength(1));
      expect(hits.first.path, 'alpha.md');
      expect(hits.first.title, 'Alpha');
      expect(hits.first.snippet, 'a <b>match</b> here');
      expect(hits.first.score, 1.5);
      expect(ffi.methods, ['kb.search.query']);
      expect(ffi.args.first['query'], 'match');
      expect(ffi.args.first['limit'], 10);
      // The store is named, not a path — the core resolves it.
      expect(ffi.args.first['store'], 'journal');
    });

    test('frontmatter keeps unknown fields', () async {
      final ffi = _FakeFfi({
        'kb.frontmatter.get': {
          'tags': ['work'],
          'title': 'Beta',
          'project': 'lumen',
          'stars': 3,
        },
      });
      final service = KbService(ffi);

      final fm = await service.getFrontmatter('beta.md');

      expect(fm.tags, ['work']);
      expect(fm.title, 'Beta');
      expect(fm.custom['project'], 'lumen');
      expect(fm.custom['stars'], 3);

      // The known fields are not repeated in the custom map.
      expect(fm.toJson()['tags'], ['work']);
      expect(fm.toJson()['title'], 'Beta');
      expect(fm.toJson()['project'], 'lumen');
    });

    test('wikilink resolution reports a missing target', () async {
      final ffi = _FakeFfi({
        'kb.wikilinks.resolve': {'path': ''},
        'kb.wikilinks.backlinks': {
          'backlinks': ['alpha.md', 'gamma.md'],
        },
      });
      final service = KbService(ffi);

      expect(await service.resolveWikilink('nothing'), isNull);
      expect(await service.backlinks('beta.md'), ['alpha.md', 'gamma.md']);
    });

    test('daily template rendering asks for the given date', () async {
      final ffi = _FakeFfi({
        'kb.template.daily_path': {'path': '2026-02-03.md'},
        'kb.template.daily_render': {'content': '# 2026-02-03'},
      });
      final service = KbService(ffi);

      final date = DateTime(2026, 2, 3);
      expect(await service.dailyNotePath(date), '2026-02-03.md');
      expect(await service.renderDailyTemplate(date), '# 2026-02-03');
      expect(ffi.args.first['date_ms'], date.millisecondsSinceEpoch);
    });
  });
}
