import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/journal/journal_service.dart';
import 'package:lumen/state/providers.dart';
import 'package:lumen/theme/app_theme.dart';

void main() {
  test('both themes build', () {
    expect(buildLumenTheme(dark: true), isNotNull);
    expect(buildLumenTheme(dark: false), isNotNull);
  });

  test('sections map to labels and icons', () {
    expect(LumenSection.values, hasLength(4));
    for (final section in LumenSection.values) {
      expect(section.label, isNotEmpty);
    }
    expect(LumenSection.journal.label, 'Journal');
    expect(LumenSection.import.label, 'Import');
  });

  test('theme source resolves to a ThemeMode', () {
    expect(resolveThemeMode(ThemeSource.dark), ThemeMode.dark);
    expect(resolveThemeMode(ThemeSource.light), ThemeMode.light);
    expect(resolveThemeMode(ThemeSource.system), ThemeMode.system);
  });

  test('journal titles strip date prefixes and separators', () {
    JournalNote note(String name) => JournalNote(
      relPath: name,
      name: name,
      modifiedMs: 0,
      size: 0,
    );

    expect(note('2026-10-19.md').displayTitle, 'Daily entry');
    expect(note('2026-10-19-test-entry.md').displayTitle, 'test entry');
    expect(note('custom_note.md').displayTitle, 'custom note');
  });
}
