// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter/services.dart';

/// Complete editable-element state reported by WebKit.
final class NativeBrowserInputMethodState {
  /// Creates a browser input snapshot using Flutter's UTF-16 text offsets.
  const NativeBrowserInputMethodState({
    required this.focused,
    required this.text,
    required this.selection,
    required this.caretRect,
    required this.inputPurpose,
    required this.inputHints,
  });

  /// Whether a browser editable element owns input-method focus.
  final bool focused;

  /// Text surrounding the active browser selection.
  final String text;

  /// Active browser selection expressed in Dart UTF-16 code units.
  final TextSelection selection;

  /// Browser caret rectangle in logical WebView coordinates.
  final Rect caretRect;

  /// `WebKitInputPurpose` wire value.
  final int inputPurpose;

  /// `WebKitInputHints` bitmask.
  final int inputHints;

  /// Converts this native snapshot into the platform text-input model.
  TextEditingValue get editingValue => TextEditingValue(
    text: text,
    selection: selection,
    composing: TextRange.empty,
  );
}

/// Semantic operation accepted by WebKit's input-method context.
sealed class BrowserTextInputCommand {
  const BrowserTextInputCommand();
}

/// Replaces the browser's visible, uncommitted composition.
final class BrowserSetPreedit extends BrowserTextInputCommand {
  /// Creates a preedit update with a Unicode-scalar cursor offset.
  const BrowserSetPreedit(this.text, this.cursorOffset);

  /// Current uncommitted composition text.
  final String text;

  /// Cursor position within [text], counted as Unicode scalar values.
  final int cursorOffset;
}

/// Commits text into the active browser editor.
final class BrowserCommitText extends BrowserTextInputCommand {
  /// Creates a commit operation. An empty commit deletes an active selection.
  const BrowserCommitText(this.text);

  /// Final text produced by the platform input method.
  final String text;
}

/// Deletes surrounding browser text relative to the active cursor.
final class BrowserDeleteSurrounding extends BrowserTextInputCommand {
  /// Creates a deletion measured in Unicode scalar values.
  const BrowserDeleteSurrounding(this.offset, this.characterCount);

  /// Signed offset from the browser cursor to the first deleted character.
  final int offset;

  /// Number of Unicode scalar values to delete.
  final int characterCount;
}

/// Cancels browser preedit without committing text.
final class BrowserCancelPreedit extends BrowserTextInputCommand {
  /// Creates the stateless cancel operation.
  const BrowserCancelPreedit();
}

/// Converts a WebKit UTF-8 byte offset into a Dart UTF-16 code-unit offset.
///
/// Invalid offsets inside a multi-byte scalar are clamped to the preceding
/// scalar boundary. Offsets beyond the encoded text clamp to the string end.
int utf8ByteOffsetToUtf16(String text, int byteOffset) {
  final target = byteOffset.clamp(0, utf8.encode(text).length);
  var utf8Offset = 0;
  var utf16Offset = 0;
  for (final rune in text.runes) {
    final scalar = String.fromCharCode(rune);
    final nextUtf8Offset = utf8Offset + utf8.encode(scalar).length;
    if (nextUtf8Offset > target) break;
    utf8Offset = nextUtf8Offset;
    utf16Offset += scalar.length;
  }
  return utf16Offset;
}

/// Translates Flutter platform text changes into WebKit IME operations.
///
/// Flutter's Linux embedder owns the system GTK input context and reports its
/// full editing model through [TextInputClient]. WebKit consumes the semantic
/// inverse: preedit, commit, and delete-surrounding signals. This function
/// preserves composition as composition instead of flattening it into key
/// events, and measures all native command offsets in Unicode scalar values.
List<BrowserTextInputCommand> browserTextInputCommands(
  TextEditingValue previous,
  TextEditingValue next,
) {
  final previousComposing = _activeComposing(previous);
  final nextComposing = _activeComposing(next);

  if (nextComposing != null) {
    final preedit = nextComposing.textInside(next.text);
    final cursorCodeUnits = (next.selection.extentOffset - nextComposing.start)
        .clamp(0, preedit.length);
    return <BrowserTextInputCommand>[
      BrowserSetPreedit(
        preedit,
        preedit.substring(0, cursorCodeUnits).runes.length,
      ),
    ];
  }

  if (previousComposing != null) {
    final withoutPreedit =
        previousComposing.textBefore(previous.text) +
        previousComposing.textAfter(previous.text);
    final replacement = _replacementBetween(withoutPreedit, next.text);
    if (replacement.insertedText.isEmpty) {
      return const <BrowserTextInputCommand>[BrowserCancelPreedit()];
    }
    return <BrowserTextInputCommand>[
      BrowserCommitText(replacement.insertedText),
    ];
  }

  if (previous.text == next.text) return const <BrowserTextInputCommand>[];

  final replacement = _replacementBetween(previous.text, next.text);
  final selectionStart = previous.selection.start;
  final selectionEnd = previous.selection.end;
  if (previous.selection.isValid &&
      !previous.selection.isCollapsed &&
      replacement.oldStart == selectionStart &&
      replacement.oldEnd == selectionEnd) {
    return <BrowserTextInputCommand>[
      BrowserCommitText(replacement.insertedText),
    ];
  }

  final commands = <BrowserTextInputCommand>[];
  if (replacement.oldStart != replacement.oldEnd) {
    final cursor = previous.selection.isValid
        ? previous.selection.extentOffset
        : replacement.oldEnd;
    final scalarStart = previous.text
        .substring(0, replacement.oldStart)
        .runes
        .length;
    final scalarCursor = previous.text
        .substring(0, cursor.clamp(0, previous.text.length))
        .runes
        .length;
    final characterCount = previous.text
        .substring(replacement.oldStart, replacement.oldEnd)
        .runes
        .length;
    commands.add(
      BrowserDeleteSurrounding(scalarStart - scalarCursor, characterCount),
    );
  }
  if (replacement.insertedText.isNotEmpty) {
    commands.add(BrowserCommitText(replacement.insertedText));
  }
  return commands;
}

TextRange? _activeComposing(TextEditingValue value) {
  final range = value.composing;
  if (!range.isValid || range.isCollapsed) return null;
  if (range.start < 0 || range.end > value.text.length) return null;
  return range;
}

_TextReplacement _replacementBetween(String oldText, String newText) {
  var prefix = 0;
  final shortestLength = oldText.length < newText.length
      ? oldText.length
      : newText.length;
  while (prefix < shortestLength &&
      oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
    prefix += 1;
  }

  // Do not split a surrogate pair when the common prefix ends between its two
  // code units. Text editing offsets are UTF-16, but replacement boundaries
  // must still describe complete Unicode scalars before native conversion.
  if (prefix > 0 &&
      prefix < shortestLength &&
      _isHighSurrogate(oldText.codeUnitAt(prefix - 1)) &&
      _isLowSurrogate(oldText.codeUnitAt(prefix))) {
    prefix -= 1;
  }

  var oldSuffix = oldText.length;
  var newSuffix = newText.length;
  while (oldSuffix > prefix &&
      newSuffix > prefix &&
      oldText.codeUnitAt(oldSuffix - 1) == newText.codeUnitAt(newSuffix - 1)) {
    oldSuffix -= 1;
    newSuffix -= 1;
  }
  if (oldSuffix < oldText.length &&
      oldSuffix > prefix &&
      _isLowSurrogate(oldText.codeUnitAt(oldSuffix)) &&
      _isHighSurrogate(oldText.codeUnitAt(oldSuffix - 1))) {
    oldSuffix += 1;
    newSuffix += 1;
  }

  return _TextReplacement(
    oldStart: prefix,
    oldEnd: oldSuffix,
    insertedText: newText.substring(prefix, newSuffix),
  );
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xd800 && codeUnit <= 0xdbff;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xdc00 && codeUnit <= 0xdfff;

final class _TextReplacement {
  const _TextReplacement({
    required this.oldStart,
    required this.oldEnd,
    required this.insertedText,
  });

  final int oldStart;
  final int oldEnd;
  final String insertedText;
}
