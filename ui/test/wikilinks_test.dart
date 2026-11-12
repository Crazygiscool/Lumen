import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/knowledge/highlight.dart';
import 'package:lumen/knowledge/wikilinks.dart';

void main() {
  group('wikilinks', () {
    test('rewrites a link into a markdown link', () {
      final rewritten = rewriteWikilinks('See [[my note]] for details.');

      expect(
        rewritten,
        'See [my note](${wikilinkUri('my note')}) for details.\n',
      );
      expect(
        wikilinkTargetFromUri(wikilinkUri('my note')),
        'my note',
      );
    });

    test('keeps the display text of a piped link', () {
      final rewritten = rewriteWikilinks('[[my-note|My Note]]');

      expect(
        rewritten,
        '[My Note](${wikilinkUri('my-note')})\n',
      );
    });

    test('leaves code blocks and inline code alone', () {
      const source = '''
```
const link = [[not a link]];
```

Inline `[[also not a link]]` stays.
''';

      final rewritten = rewriteWikilinks(source);

      expect(rewritten, contains('[[not a link]]'));
      expect(rewritten, contains('`[[also not a link]]`'));
    });

    test('finds the link the caret is in', () {
      const text = 'A note about [[proj';

      final active = activeWikilink(text, text.length);

      expect(active, isNotNull);
      expect(active!.query, 'proj');
      expect(text.substring(active.start), '[[proj');
    });

    test('ignores a link that is already closed', () {
      const text = 'A link [[done]] and more';

      expect(activeWikilink(text, text.length), isNull);
    });

    test('ignores a link that spans lines', () {
      const text = 'A link [[start\nof a line';

      expect(activeWikilink(text, text.length), isNull);
    });

    test('inserts a finished link', () {
      const text = 'About [[proj';
      final active = activeWikilink(text, text.length)!;

      final updated = insertWikilink(
        text,
        active,
        target: 'project.md',
        display: 'Project',
      );

      expect(updated, 'About [[project.md|Project]]');
    });

    test('prettifies a normalized target', () {
      expect(prettifyTarget('my-note.md'), 'My Note');
      expect(prettifyTarget('my-note'), 'My Note');
    });

    test('folds link targets together', () {
      expect(wikilinkSlug('My Note.md'), 'my-note');
      expect(wikilinkSlug('my-note'), 'my-note');
      expect(wikilinkSlug('my note'), 'my-note');
      expect(wikilinkSlug('My_Note.md'), 'my-note');
      expect(wikilinkSlug('my note.md'), 'my-note');
    });

    test('finds the text around a link', () {
      const body = 'A first line that runs on for a while.\n'
          'Then a link to [[other-note]] in the middle.\n'
          'And a last line that also runs on for a while.';

      final context = wikilinkContext(body, 'other-note.md', radius: 20);

      expect(context, contains('a link to'));
      expect(context, contains('in the middle'));
      // The snippet is trimmed around the link, not the whole note.
      expect(context, isNot(contains('A first line')));
      expect(context, isNot(contains('a last line')));
    });

    test('finds no context for an unrelated target', () {
      const body = 'A link to [[other-note]] here.';

      expect(wikilinkContext(body, 'unrelated.md'), isEmpty);
    });
  });

  group('snippet highlighting', () {
    test('splits the matched terms out of a snippet', () {
      final spans = parseSnippet('a <b>match</b> here');

      expect(spans.map((s) => s.text), ['a ', 'match', ' here']);
      expect(spans.map((s) => s.matched), [false, true, false]);
    });

    test('handles several matches', () {
      final spans = parseSnippet('<b>one</b> and <b>two</b>');

      expect(spans.where((s) => s.matched).map((s) => s.text), [
        'one',
        'two',
      ]);
    });

    test('leaves a snippet without matches alone', () {
      final spans = parseSnippet('nothing here');

      expect(spans, hasLength(1));
      expect(spans.first.matched, isFalse);
    });
  });
}
