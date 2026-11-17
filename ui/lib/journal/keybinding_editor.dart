import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

/// A snapshot of editor state for undo/redo.
class _EditorState {
  const _EditorState({required this.text, required this.selection});

  final String text;
  final TextSelection selection;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _EditorState &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          selection == other.selection;

  @override
  int get hashCode => Object.hash(text, selection);
}

/// A text editor with Vim/Emacs keybinding support.
///
/// Wraps a [TextField] with keyboard shortcut handling for Vim and Emacs
/// modes. In default mode, behaves like a normal text field.
///
/// In Vim mode:
/// - Normal mode: `h`/`j`/`k`/`l` move, `x` deletes char, `dd` deletes line,
///   `yy` yanks line, `p` pastes after, `P` pastes before, `u` undoes,
///   `Ctrl+r` redoes, `0`/`$` go to line start/end, `w`/`b` move by word,
///   `gg`/`G` go to doc start/end, `i` enters insert mode.
/// - Insert mode: normal typing, `Esc` returns to normal mode.
///
/// In Emacs mode:
/// - `C-f`/`C-b` move char, `C-p`/`C-n` move line, `C-a`/`C-e` line start/end,
///   `C-k` kill line, `C-y` yank.
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
    this.keybindingMode,
  });

  final TextEditingController controller;
  final void Function(String)? onChanged;
  final InputDecoration decoration;
  final TextStyle? style;
  final int? minLines;
  final int? maxLines;
  final bool expands;
  final TextAlignVertical? textAlignVertical;

  /// Override the keybinding mode from settings (useful for testing).
  final KeybindingMode? keybindingMode;

  @override
  ConsumerState<KeybindingEditor> createState() => _KeybindingEditorState();
}

class _KeybindingEditorState extends ConsumerState<KeybindingEditor> {
  /// Vim mode state: whether we're in insert mode or normal mode.
  /// Vim starts in normal mode.
  bool _vimInsertMode = false;

  /// Tracks consecutive `d` keypresses for the `dd` (delete line) command.
  int _vimDCount = 0;

  /// Tracks consecutive `y` keypresses for the `yy` (yank line) command.
  int _vimYCount = 0;

  /// Tracks consecutive `g` keypresses for the `gg` (go to top) command.
  int _vimGCount = 0;

  /// Timer that resets multi-key sequence counters after a short delay.
  Timer? _sequenceTimer;

  /// Focus node for the keyboard listener.
  late final FocusNode _focusNode;

  /// Undo/redo history stack. Each entry is a snapshot of (text, selection).
  final List<_EditorState> _history = [];
  final List<_EditorState> _future = [];

  /// Maximum number of undo steps to keep.
  static const int _maxHistory = 100;

  /// Whether we're currently replaying an undo/redo (to avoid recording it).
  bool _isReplaying = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _pushSnapshot();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _sequenceTimer?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    _focusNode.dispose();
    super.dispose();
  }

  /// Called whenever the controller changes (typing, pasting, etc.).
  /// Records a new snapshot for undo unless we're currently undoing/redoing.
  void _onControllerChanged() {
    if (_isReplaying) return;
    _pushSnapshot();
  }

  /// Push the current editor state onto the history stack.
  void _pushSnapshot() {
    final state = _EditorState(
      text: widget.controller.text,
      selection: widget.controller.selection,
    );
    // Don't push consecutive duplicates.
    if (_history.isNotEmpty && _history.last == state) return;
    _history.add(state);
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
    }
    _future.clear();
  }

  /// Replay a snapshot onto the controller without recording it.
  void _replay(_EditorState state) {
    _isReplaying = true;
    widget.controller.text = state.text;
    widget.controller.selection = state.selection;
    _isReplaying = false;
  }

  /// Undo the last change.
  void _undo() {
    if (_history.length <= 1) return;
    // Current state goes to future stack.
    final current = _history.removeLast();
    _future.add(current);
    final previous = _history.last;
    _replay(previous);
  }

  /// Redo the last undone change.
  void _redo() {
    if (_future.isEmpty) return;
    final next = _future.removeLast();
    _history.add(next);
    _replay(next);
  }

  /// Reset multi-key sequence counters after a delay.
  void _resetSequences() {
    _vimDCount = 0;
    _vimYCount = 0;
    _vimGCount = 0;
  }

  /// Start or restart the sequence reset timer.
  void _scheduleSequenceReset() {
    _sequenceTimer?.cancel();
    _sequenceTimer = Timer(const Duration(milliseconds: 500), _resetSequences);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final mode = widget.keybindingMode ?? settings.keybindingMode;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          // Escape always goes to normal mode in Vim.
          if (mode == KeybindingMode.vim && _vimInsertMode) {
            setState(() {
              _vimInsertMode = false;
              _resetSequences();
            });
            return;
          }
        }

        if (mode == KeybindingMode.vim) {
          _handleVimKey(event);
        } else if (mode == KeybindingMode.emacs) {
          _handleEmacsKey(event);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mode == KeybindingMode.vim)
            _ModeBadge(
              insertMode: _vimInsertMode,
            ),
          Expanded(
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
          ),
        ],
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
        setState(() {
          _vimInsertMode = true;
          _resetSequences();
        });
      } else if (logical == LogicalKeyboardKey.keyD) {
        // `d` starts a delete operator. Press `d` again quickly for `dd`.
        _vimDCount++;
        if (_vimDCount >= 2) {
          _resetSequences();
          _deleteLine();
        } else {
          _scheduleSequenceReset();
        }
      } else if (logical == LogicalKeyboardKey.keyY) {
        // `y` starts a yank operator. Press `y` again quickly for `yy`.
        _vimYCount++;
        if (_vimYCount >= 2) {
          _resetSequences();
          _yankLine();
        } else {
          _scheduleSequenceReset();
        }
      } else if (logical == LogicalKeyboardKey.keyP &&
          !HardwareKeyboard.instance.isShiftPressed) {
        // `p`: paste after cursor.
        _pasteAfter();
        _resetSequences();
      } else if (logical == LogicalKeyboardKey.keyP &&
          HardwareKeyboard.instance.isShiftPressed) {
        // `P`: paste before cursor.
        _pasteBefore();
        _resetSequences();
      } else if (logical == LogicalKeyboardKey.keyU &&
          !HardwareKeyboard.instance.isControlPressed) {
        // `u`: undo.
        _undo();
        _resetSequences();
      } else if (logical == LogicalKeyboardKey.keyR &&
          HardwareKeyboard.instance.isControlPressed) {
        // Ctrl+R: redo.
        _redo();
        _resetSequences();
      } else if (logical == LogicalKeyboardKey.keyX) {
        // `x`: delete character under cursor.
        _deleteCharForward();
        _resetSequences();
      } else if (logical == LogicalKeyboardKey.keyD &&
          HardwareKeyboard.instance.isShiftPressed) {
        // Shift+D: delete to end of line.
        _deleteToEndOfLine();
        _resetSequences();
      } else if (logical == LogicalKeyboardKey.keyY &&
          HardwareKeyboard.instance.isShiftPressed) {
        // Shift+Y: yank (copy) current line.
        _yankLine();
        _resetSequences();
      } else if (logical == LogicalKeyboardKey.keyH) {
        _moveCursor(-1);
        _resetSequences();
      } else if (logical == LogicalKeyboardKey.keyJ) {
        _moveCursorDown();
        _resetSequences();
      } else if (logical == LogicalKeyboardKey.keyK) {
        _moveCursorUp();
        _resetSequences();
      } else if (logical == LogicalKeyboardKey.keyL) {
        _moveCursor(1);
        _resetSequences();
      } else if (logical == LogicalKeyboardKey.digit0) {
        // `0`: go to line start.
        _moveToLineStart();
        _resetSequences();
      } else if (logical == LogicalKeyboardKey.dollar) {
        // `$`: go to line end.
        _moveToLineEnd();
        _resetSequences();
      } else if (logical == LogicalKeyboardKey.keyW) {
        // `w`: move to next word start.
        _moveToNextWord();
        _resetSequences();
      } else if (logical == LogicalKeyboardKey.keyB) {
        // `b`: move to previous word start.
        _moveToPrevWord();
        _resetSequences();
      } else if (logical == LogicalKeyboardKey.keyG &&
          !HardwareKeyboard.instance.isShiftPressed) {
        // `g` starts `gg` sequence.
        _vimGCount++;
        if (_vimGCount >= 2) {
          _resetSequences();
          _moveToDocStart();
        } else {
          _scheduleSequenceReset();
        }
      } else if (logical == LogicalKeyboardKey.keyG &&
          HardwareKeyboard.instance.isShiftPressed) {
        // Shift+G: go to doc end.
        _moveToDocEnd();
        _resetSequences();
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

  void _moveToNextWord() {
    final current = widget.controller.selection;
    final text = widget.controller.text;
    final start = current.base.offset;
    final after = text.substring(start);
    final wordMatch = RegExp(r'\w+').firstMatch(after);
    if (wordMatch != null) {
      widget.controller.selection = TextSelection.collapsed(
        offset: start + wordMatch.end,
      );
    }
  }

  void _moveToPrevWord() {
    final current = widget.controller.selection;
    final text = widget.controller.text;
    final start = current.base.offset;
    if (start == 0) return;
    final before = text.substring(0, start);
    final wordMatch = RegExp(r'\w+$').firstMatch(before);
    if (wordMatch != null) {
      widget.controller.selection = TextSelection.collapsed(
        offset: wordMatch.start,
      );
    } else {
      widget.controller.selection = TextSelection.collapsed(offset: 0);
    }
  }

  void _moveToDocStart() {
    widget.controller.selection =
        TextSelection.collapsed(offset: 0);
  }

  void _moveToDocEnd() {
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
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

  void _deleteLine() {
    final current = widget.controller.selection;
    final lineStart =
        _getLineStart(widget.controller.text, current.base.offset);
    final lineEnd =
        _getLineEnd(widget.controller.text, current.base.offset);
    // Include the newline if not the last line.
    final end = lineEnd < widget.controller.text.length ? lineEnd + 1 : lineEnd;
    widget.controller.text = widget.controller.text
        .replaceRange(lineStart, end, '');
    widget.controller.selection = TextSelection.collapsed(
      offset: lineStart.clamp(0, widget.controller.text.length),
    );
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

  void _pasteAfter() {
    if (_clipboard.isEmpty) return;
    final current = widget.controller.selection;
    final insertPos = current.base.offset;
    widget.controller.text = widget.controller.text
        .replaceRange(insertPos, insertPos, _clipboard);
    widget.controller.selection = TextSelection.collapsed(
      offset: insertPos + _clipboard.length,
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

/// A small badge indicating the current Vim mode (NORMAL or INSERT).
class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.insertMode});

  final bool insertMode;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final isInsert = insertMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isInsert ? t.colorScheme.primary : t.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            isInsert ? '-- INSERT --' : '-- NORMAL --',
            style: t.textTheme.labelSmall?.copyWith(
              color: isInsert
                  ? t.colorScheme.onPrimary
                  : t.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
          if (!isInsert)
            const Icon(Icons.edit, size: 10, color: Colors.white70),
        ],
      ),
    );
  }
}
