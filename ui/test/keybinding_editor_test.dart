import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumen/journal/keybinding_editor.dart';
import 'package:lumen/state/providers.dart';

void main() {
  group('KeybindingMode', () {
    test('labels are non-empty', () {
      for (final mode in KeybindingMode.values) {
        expect(mode.label, isNotEmpty);
      }
    });

    test('descriptions are non-empty', () {
      for (final mode in KeybindingMode.values) {
        expect(mode.description, isNotEmpty);
      }
    });

    test('vim and emacs have distinct labels', () {
      expect(KeybindingMode.vim.label, 'Vim');
      expect(KeybindingMode.emacs.label, 'Emacs');
      expect(KeybindingMode.defaultMode.label, 'Default');
    });
  });

  group('KeybindingEditor widget', () {
    testWidgets('renders in default mode without crashing', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: KeybindingEditor(controller: controller, expands: true),
            ),
          ),
        ),
      );

      expect(find.byType(KeybindingEditor), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('-- NORMAL --'), findsNothing);
      expect(find.text('-- INSERT --'), findsNothing);

      controller.dispose();
    });

    testWidgets('shows NORMAL badge in vim mode', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: KeybindingEditor(
                controller: controller,
                expands: true,
                keybindingMode: KeybindingMode.vim,
              ),
            ),
          ),
        ),
      );

      expect(find.text('-- NORMAL --'), findsOneWidget);
      expect(find.text('-- INSERT --'), findsNothing);

      controller.dispose();
    });

    testWidgets('default mode does not show mode badge', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: KeybindingEditor(controller: controller, expands: true),
            ),
          ),
        ),
      );

      expect(find.text('-- NORMAL --'), findsNothing);
      expect(find.text('-- INSERT --'), findsNothing);

      controller.dispose();
    });

    testWidgets('emacs mode does not show vim badge', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: KeybindingEditor(
                controller: controller,
                expands: true,
                keybindingMode: KeybindingMode.emacs,
              ),
            ),
          ),
        ),
      );

      expect(find.text('-- NORMAL --'), findsNothing);
      expect(find.text('-- INSERT --'), findsNothing);

      controller.dispose();
    });
  });
}
