import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shell/web/js_adblock.dart';

void main() {
  group('jsBlockScript', () {
    test('translates a network block rule into the injected payload', () {
      // Valid content-rule JSON as emitted by libublock (serde escapes `\`).
      final part = r'''
[
  {
    "trigger": {
      "url-filter": "^https?://(?:[^/]*\\.)?ads\\.example\\.com(?:[:/?#]|$)",
      "resource-type": ["image", "script"]
    },
    "action": {"type": "block"}
  }
]
''';
      final script = jsBlockScript([part]);
      expect(script, contains('window.__lumenAbInstalled'));
      expect(script, contains('"blocks"'));
      // The decoded regex is re-encoded into the script as JSON (`\\.`).
      expect(script, contains(r'ads\\.example\\.com'));
    });

    test('translates a cosmetic rule into a domain-scoped css entry', () {
      final part = r'''
[
  {
    "trigger": {"url-filter": "^https?://(?:[^/]*\\.)?example\\.com(?:[:/?#]|$)"},
    "action": {"type": "css-display-none", "selector": ".ad-banner"}
  }
]
''';
      final script = jsBlockScript([part]);
      expect(script, contains('display:none'));
      expect(script, contains('.ad-banner'));
      // The page-domain regex is carried through (JSON-escaped) and matched in
      // JS against location.href.
      expect(script, contains(r'example\\.com'));
      expect(script, contains('location.href'));
    });

    test('empty parts produce a script with no block rules', () {
      final script = jsBlockScript([]);
      expect(script, contains('"blocks":[]'));
    });
  });
}
