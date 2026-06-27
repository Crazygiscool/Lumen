import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumen/utils/theme.dart';
import 'package:lumen/widgets/status_badge.dart';
import 'package:lumen/widgets/empty_state.dart';

void main() {
  group('Theme', () {
    test('buildLumenTheme returns dark theme', () {
      final theme = buildLumenTheme();
      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, true);
    });

    test('theme has Geist font family', () {
      final theme = buildLumenTheme();
      expect(theme.textTheme.bodyLarge?.fontFamily, 'Geist');
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Geist');
      expect(theme.textTheme.displayLarge?.fontFamily, 'Geist');
    });

    test('theme has no card elevation', () {
      final theme = buildLumenTheme();
      expect(theme.cardTheme.elevation, 0);
    });
  });

  group('StatusBadge', () {
    test('statusColor returns correct colors', () {
      expect(statusColor('done'), Colors.green);
      expect(statusColor('in_progress'), Colors.blue);
      expect(statusColor('todo'), Colors.grey);
      expect(statusColor('unknown'), Colors.grey);
    });

    testWidgets('renders a small colored circle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusBadge('done', size: 12),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.green);
      expect(decoration.shape, BoxShape.circle);
      expect(container.constraints?.maxWidth, 12);
    });
  });

  group('EmptyState', () {
    testWidgets('displays the provided message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyState(message: 'No entries found'),
          ),
        ),
      );

      expect(find.text('No entries found'), findsOneWidget);
    });
  });
}
