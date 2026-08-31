// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_linux/src/webview_text_input.dart';

void main() {
  group('utf8ByteOffsetToUtf16', () {
    test('converts multi-byte scalars to Dart code-unit offsets', () {
      const text = 'A😀é中';

      expect(utf8ByteOffsetToUtf16(text, 0), 0);
      expect(utf8ByteOffsetToUtf16(text, 1), 1);
      expect(utf8ByteOffsetToUtf16(text, 5), 3);
      expect(utf8ByteOffsetToUtf16(text, 7), 4);
      expect(utf8ByteOffsetToUtf16(text, 10), 5);
    });

    test('clamps offsets inside and beyond encoded scalars', () {
      const text = 'A😀é';

      expect(utf8ByteOffsetToUtf16(text, 2), 1);
      expect(utf8ByteOffsetToUtf16(text, 99), text.length);
      expect(utf8ByteOffsetToUtf16(text, -4), 0);
    });
  });

  group('browserTextInputCommands', () {
    test('starts preedit with a Unicode-scalar cursor offset', () {
      const previous = TextEditingValue(
        text: 'word ',
        selection: TextSelection.collapsed(offset: 5),
      );
      const next = TextEditingValue(
        text: 'word 😀x',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 5, end: 8),
      );

      final commands = browserTextInputCommands(previous, next);

      expect(commands, hasLength(1));
      final command = commands.single as BrowserSetPreedit;
      expect(command.text, '😀x');
      expect(command.cursorOffset, 1);
    });

    test('updates an existing preedit without committing it', () {
      const previous = TextEditingValue(
        text: 'word n',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 5, end: 6),
      );
      const next = TextEditingValue(
        text: 'word に',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 5, end: 6),
      );

      final command =
          browserTextInputCommands(previous, next).single as BrowserSetPreedit;

      expect(command.text, 'に');
      expect(command.cursorOffset, 1);
    });

    test('commits the finalized replacement for a composition', () {
      const previous = TextEditingValue(
        text: 'word に',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 5, end: 6),
      );
      const next = TextEditingValue(
        text: 'word 日',
        selection: TextSelection.collapsed(offset: 6),
      );

      final command =
          browserTextInputCommands(previous, next).single as BrowserCommitText;

      expect(command.text, '日');
    });

    test('cancels composition when its marked text is removed', () {
      const previous = TextEditingValue(
        text: 'word に',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 5, end: 6),
      );
      const next = TextEditingValue(
        text: 'word ',
        selection: TextSelection.collapsed(offset: 5),
      );

      expect(
        browserTextInputCommands(previous, next).single,
        isA<BrowserCancelPreedit>(),
      );
    });

    test('commits a plain supplementary-plane character once', () {
      const previous = TextEditingValue(
        text: 'a',
        selection: TextSelection.collapsed(offset: 1),
      );
      const next = TextEditingValue(
        text: 'a😀',
        selection: TextSelection.collapsed(offset: 3),
      );

      final command =
          browserTextInputCommands(previous, next).single as BrowserCommitText;

      expect(command.text, '😀');
    });

    test('deletes one Unicode scalar before the cursor', () {
      const previous = TextEditingValue(
        text: 'a😀',
        selection: TextSelection.collapsed(offset: 3),
      );
      const next = TextEditingValue(
        text: 'a',
        selection: TextSelection.collapsed(offset: 1),
      );

      final command =
          browserTextInputCommands(previous, next).single
              as BrowserDeleteSurrounding;

      expect(command.offset, -1);
      expect(command.characterCount, 1);
    });

    test('lets a commit replace the active browser selection', () {
      const previous = TextEditingValue(
        text: 'abcd',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
      );
      const next = TextEditingValue(
        text: 'aXd',
        selection: TextSelection.collapsed(offset: 2),
      );

      final command =
          browserTextInputCommands(previous, next).single as BrowserCommitText;

      expect(command.text, 'X');
    });

    test('expresses autocorrection as deletion followed by commit', () {
      const previous = TextEditingValue(
        text: 'teh ',
        selection: TextSelection.collapsed(offset: 4),
      );
      const next = TextEditingValue(
        text: 'the ',
        selection: TextSelection.collapsed(offset: 4),
      );

      final commands = browserTextInputCommands(previous, next);

      expect(commands, hasLength(2));
      final deletion = commands.first as BrowserDeleteSurrounding;
      expect(deletion.offset, -3);
      expect(deletion.characterCount, 2);
      expect((commands.last as BrowserCommitText).text, 'he');
    });

    test('does not turn selection-only updates into text edits', () {
      const previous = TextEditingValue(
        text: 'abcd',
        selection: TextSelection.collapsed(offset: 1),
      );
      const next = TextEditingValue(
        text: 'abcd',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(browserTextInputCommands(previous, next), isEmpty);
    });
  });
}
