import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

/// A text editor with Vim/Emacs keybinding support.
///
/// Wraps a [TextField] with keyboard shortcut handling for Vim and Emacs
/// modes. In default mode, behaves like a normal text field.
class KeybindingEditor extends ConsumerStatefulWidget {
  const KeybindingEditor({
    super.key,
    required this.controller,
    this.onChanged,
    this.decoration = const InputDecoration(),
    this.style,
    this.minLines,
    this.maxLines,
    this.expands = false,
    this.textAlignVertical,
  });

  final TextEditingController controller;
  final void Function(String)? onChanged;
  final InputDecoration decoration;
  final TextStyle? style;
  final int? minLines;
  final int? maxLines;
  final bool expands;
  final TextAlignVertical? textAlignVertical;

  @override
  ConsumerState<KeybindingEditor> createState() => _KeybindingEditorState();
}

class _KeybindingEditorState extends ConsumerState<KeybindingEditor> {
  /// Vim mode state: whether we're in insert mode or normal mode.
  bool _vimInsertMode = true;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          // Escape always goes to normal mode in Vim.
          if (settings.keybindingMode == KeybindingMode.vim &&
              _vimInsertMode) {
            setState(() => _vimInsertMode = true);
            return;
          }
        }

        if (settings.keybindingMode == KeybindingMode.vim) {
          _handleVimKey(event);
        } else if (settings.keybindingMode == KeybindingMode.emacs) {
          _handleEmacsKey(event);
        }
      },
      child: TextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        decoration: widget.decoration,
        style: widget.style,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        expands: widget.expands,
        textAlignVertical: widget.textAlignVertical,
      ),
    );
  }

  /// Handle Vim-mode key events.
  void _handleVimKey(KeyEvent event) {
    final logical = event.logicalKey;

    if (!_vimInsertMode) {
      // Normal mode.
      if (logical == LogicalKeyboardKey.keyI) {
        // Enter insert mode.
        setState(() => _vimInsertMode = true);
      } else if (logical == LogicalKeyboardKey.keyH) {
        _moveCursor(-1);
      } else if (logical == LogicalKeyboardKey.keyJ) {
        _moveCursorDown();
      } else if (logical == LogicalKeyboardKey.keyK) {
        _moveCursorUp();
      } else if (logical == LogicalKeyboardKey.keyL) {
        _moveCursor(1);
      } else if (logical == LogicalKeyboardKey.keyD &&
          HardwareKeyboard.instance.isShiftPressed) {
        // Shift+D: delete to end of line.
        _deleteToEndOfLine();
      } else if (logical == LogicalKeyboardKey.keyY &&
          HardwareKeyboard.instance.isShiftPressed) {
        // Shift+Y: yank (copy) current line.
        _yankLine();
      } else if (logical == LogicalKeyboardKey.keyP &&
          HardwareKeyboard.instance.isShiftPressed) {
        // Shift+P: paste before cursor.
        _pasteBefore();
      } else if (logical == LogicalKeyboardKey.keyX) {
        // x: delete character under cursor.
        _deleteCharForward();
      }
    } else {
      // Insert mode: any printable character is inserted by the TextField.
      // Escape is handled above.
    }
  }

  /// Handle Emacs-mode key events.
  void _handleEmacsKey(KeyEvent event) {
    final logical = event.logicalKey;
    final isCtrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (!isCtrl) return;

    if (logical == LogicalKeyboardKey.keyF) {
      // C-f: forward character.
      _moveCursor(1);
    } else if (logical == LogicalKeyboardKey.keyB) {
      // C-b: backward character.
      _moveCursor(-1);
    } else if (logical == LogicalKeyboardKey.keyP) {
      // C-p: previous line.
      _moveCursorUp();
    } else if (logical == LogicalKeyboardKey.keyN) {
      // C-n: next line.
      _moveCursorDown();
    } else if (logical == LogicalKeyboardKey.keyA) {
      // C-a: beginning of line.
      _moveToLineStart();
    } else if (logical == LogicalKeyboardKey.keyE) {
      // C-e: end of line.
      _moveToLineEnd();
    } else if (logical == LogicalKeyboardKey.keyK) {
      // C-k: kill line.
      _killLine();
    } else if (logical == LogicalKeyboardKey.keyY) {
      // C-y: yank (paste).
      _yank();
    }
  }

  void _moveCursor(int offset) {
    final current = widget.controller.selection;
    final newPos = current.base.offset + offset;
    if (newPos >= 0 && newPos <= widget.controller.text.length) {
      widget.controller.selection = TextSelection.collapsed(offset: newPos);
    }
  }

  void _moveCursorUp() {
    final current = widget.controller.selection;
    final lines = widget.controller.text.split('\n');
    final currentLine =
        _getCurrentLineIndex(widget.controller.text, current.base.offset);
    if (currentLine > 0) {
      final prevLine = lines[currentLine - 1];
      final col = _getColumn(widget.controller.text, current.base.offset);
      final newCol = col.clamp(0, prevLine.length);
      final prevLineStart = lines.take(currentLine - 1).fold<int>(
        0,
        (sum, line) => sum + line.length + 1,
      );
      widget.controller.selection = TextSelection.collapsed(
        offset: prevLineStart + newCol,
      );
    }
  }

  void _moveCursorDown() {
    final current = widget.controller.selection;
    final lines = widget.controller.text.split('\n');
    final currentLine =
        _getCurrentLineIndex(widget.controller.text, current.base.offset);
    if (currentLine < lines.length - 1) {
      final nextLine = lines[currentLine + 1];
      final col = _getColumn(widget.controller.text, current.base.offset);
      final newCol = col.clamp(0, nextLine.length);
      final nextLineStart = lines.take(currentLine + 1).fold<int>(
        0,
        (sum, line) => sum + line.length + 1,
      );
      widget.controller.selection = TextSelection.collapsed(
        offset: nextLineStart + newCol,
      );
    }
  }

  void _moveToLineStart() {
    final current = widget.controller.selection;
    final lineStart =
        _getLineStart(widget.controller.text, current.base.offset);
    widget.controller.selection = TextSelection.collapsed(offset: lineStart);
  }

  void _moveToLineEnd() {
    final current = widget.controller.selection;
    final lineEnd =
        _getLineEnd(widget.controller.text, current.base.offset);
    widget.controller.selection = TextSelection.collapsed(offset: lineEnd);
  }

  void _deleteCharForward() {
    final current = widget.controller.selection;
    if (current.base.offset < widget.controller.text.length) {
      widget.controller.text = widget.controller.text
          .replaceRange(current.base.offset, current.base.offset + 1, '');
      widget.controller.selection = TextSelection.collapsed(
          offset: current.base.offset);
    }
  }

  void _deleteToEndOfLine() {
    final current = widget.controller.selection;
    final lineEnd =
        _getLineEnd(widget.controller.text, current.base.offset);
    if (current.base.offset < lineEnd) {
      widget.controller.text = widget.controller.text
          .replaceRange(current.base.offset, lineEnd, '');
      widget.controller.selection = TextSelection.collapsed(
          offset: current.base.offset);
    }
  }

  void _yankLine() {
    final current = widget.controller.selection;
    final lineStart =
        _getLineStart(widget.controller.text, current.base.offset);
    final lineEnd =
        _getLineEnd(widget.controller.text, current.base.offset);
    final line = widget.controller.text.substring(lineStart, lineEnd);
    // Include the newline if not the last line.
    final withNewline = lineEnd < widget.controller.text.length
        ? '$line\n'
        : line;
    _clipboard = withNewline;
  }

  void _pasteBefore() {
    if (_clipboard.isEmpty) return;
    final current = widget.controller.selection;
    widget.controller.text = widget.controller.text
        .replaceRange(current.base.offset, current.base.offset, _clipboard);
    widget.controller.selection = TextSelection.collapsed(
      offset: current.base.offset + _clipboard.length,
    );
  }

  void _killLine() {
    final current = widget.controller.selection;
    final lineEnd =
        _getLineEnd(widget.controller.text, current.base.offset);
    if (current.base.offset < lineEnd) {
      _clipboard = widget.controller.text
          .substring(current.base.offset, lineEnd);
      // Include newline if present.
      if (lineEnd < widget.controller.text.length) {
        _clipboard += '\n';
      }
      widget.controller.text = widget.controller.text
          .replaceRange(current.base.offset,
              lineEnd + (_clipboard.endsWith('\n') ? 1 : 0), '');
      widget.controller.selection = TextSelection.collapsed(
          offset: current.base.offset);
    }
  }

  void _yank() {
    if (_clipboard.isEmpty) return;
    final current = widget.controller.selection;
    widget.controller.text = widget.controller.text
        .replaceRange(current.base.offset, current.base.offset, _clipboard);
    widget.controller.selection = TextSelection.collapsed(
      offset: current.base.offset + _clipboard.length,
    );
  }

  String _clipboard = '';

  int _getCurrentLineIndex(String text, int pos) {
    return text.substring(0, pos).split('\n').length - 1;
  }

  int _getColumn(String text, int pos) {
    final lineStart = text.lastIndexOf('\n', pos - 1) + 1;
    return pos - lineStart;
  }

  int _getLineStart(String text, int pos) {
    return text.lastIndexOf('\n', pos - 1) + 1;
  }

  int _getLineEnd(String text, int pos) {
    final newlineIdx = text.indexOf('\n', pos);
    return newlineIdx == -1 ? text.length : newlineIdx;
  }
}
