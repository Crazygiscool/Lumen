import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ffi/lumen_ffi.dart';
import 'package:lumen/knowledge/kb_service.dart';
import 'package:lumen/settings/template_editor.dart';
import 'package:lumen/state/providers.dart';
import 'package:lumen/theme/app_theme.dart';

/// A native bridge fake that serves the template API.
class _FakeFfi implements LumenFfi {
  _FakeFfi();

  String content = '# {{date}}\n';
  String path = '/tmp/lumen/templates/daily.md';
  final List<String> rendered = [];

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
    switch (method) {
      case 'kb.template.get':
        return <String, Object?>{'path': path, 'content': content};
      case 'kb.template.save':
        content = args['content'] as String;
        return <String, Object?>{'path': path, 'saved': true};
      case 'kb.template.render':
        rendered.add(args['template'] as String);
        return <String, Object?>{
          'content': '# rendered\n',
        };
      default:
        return <String, Object?>{};
    }
  }
}

Future<ProviderContainer> _pumpEditor(
  WidgetTester tester,
  _FakeFfi ffi,
) async {
  final container = ProviderContainer(
    overrides: [lumenFfiProvider.overrideWithValue(ffi)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLumenTheme(dark: true),
        home: const TemplateEditorScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('the editor shows the template and its path', (tester) async {
    final ffi = _FakeFfi();
    await _pumpEditor(tester, ffi);

    expect(find.text('Daily Template'), findsOneWidget);
    expect(find.text('/tmp/lumen/templates/daily.md'), findsOneWidget);
    // The template text is in the editor.
    expect(find.textContaining('# {{date}}'), findsWidgets);
  });

  testWidgets('the placeholder chips are offered', (tester) async {
    final ffi = _FakeFfi();
    await _pumpEditor(tester, ffi);

    expect(find.text('{{date}}'), findsOneWidget);
    expect(find.text('{{yesterday}}'), findsOneWidget);
    expect(find.text('{{week}}'), findsOneWidget);
  });

  testWidgets('the preview is rendered through the core', (tester) async {
    final ffi = _FakeFfi();
    await _pumpEditor(tester, ffi);

    // The core renders the preview, so it cannot drift from the real note.
    expect(ffi.rendered, isNotEmpty);
    expect(ffi.rendered.last, contains('{{date}}'));
    expect(find.textContaining('rendered'), findsWidgets);
  });

  testWidgets('saving stores the template through the core', (tester) async {
    final ffi = _FakeFfi();
    await _pumpEditor(tester, ffi);

    await tester.enterText(find.byType(TextField).first, '# {{date}} edited');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Save template'));
    await tester.pumpAndSettle();

    expect(ffi.content, '# {{date}} edited');
    expect(find.text('Template saved'), findsOneWidget);
  });

  test('the service reads and writes the template', () async {
    final ffi = _FakeFfi();
    final service = KbService(ffi);

    final template = await service.template();
    expect(template.path, '/tmp/lumen/templates/daily.md');
    expect(template.content, '# {{date}}\n');

    final saved = await service.saveTemplate('# new');
    expect(saved, '/tmp/lumen/templates/daily.md');
    expect(ffi.content, '# new');
  });
}
