import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/lumen_colors.dart';
import '../theme/glass.dart';

class ConsoleScreen extends StatefulWidget {
  const ConsoleScreen({super.key});

  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  final List<_Line> _lines = [];
  final _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  final List<StreamSubscription<String>> _subs = [];
  Process? _process;
  bool _busy = false;

  @override
  void dispose() {
    _process?.kill();
    for (final s in _subs) {
      s.cancel();
    }
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _log(String text, {Color? color, bool isCmd = false}) {
    setState(() => _lines.add(_Line(text, color: color, isCmd: isCmd)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  String get _cwd => Platform.environment['HOME'] ?? '/';

  Future<void> _run(String command) async {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return;
    _input.clear();
    _log(command, isCmd: true);

    final onSurface = LumenColors.of(context).onSurface;
    final warn = LumenColors.of(context).warning;

    final isBuiltin = await _tryBuiltin(trimmed);
    if (isBuiltin) return;

    setState(() => _busy = true);
    try {
      final shell = Platform.isWindows ? 'powershell.exe' : '/bin/sh';
      final args = Platform.isWindows
          ? <String>['-Command', trimmed]
          : <String>['-c', trimmed];
      final process = await Process.start(
        shell,
        args,
        workingDirectory: _cwd,
        runInShell: true,
      );
      _process = process;
      _subs
        ..add(
          process.stdout
              .transform(utf8.decoder)
              .listen((c) => _log(c, color: onSurface)),
        )
        ..add(
          process.stderr
              .transform(utf8.decoder)
              .listen((c) => _log(c, color: warn)),
        );
      final code = await process.exitCode;
      _process = null;
      for (final s in _subs) {
        s.cancel();
      }
      _subs.clear();
      if (mounted) {
        setState(() => _busy = false);
        _log(
          '→ exited with code $code',
          color: LumenColors.of(context).onSurfaceVariant,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _log('error: $e', color: LumenColors.of(context).error);
      }
    }
  }

  Future<bool> _tryBuiltin(String cmd) async {
    if (cmd == 'clear' || cmd == 'cls') {
      setState(_lines.clear);
      return true;
    }
    if (cmd == 'whoami') {
      _log(Platform.environment['USER'] ?? 'unknown');
      return true;
    }
    if (cmd == 'pwd') {
      _log(_cwd);
      return true;
    }
    if (cmd.startsWith('cd ')) {
      // cd is only cosmetic here; the shell keeps its own cwd so we accept silently.
      _log(
        'note: cd affects the shell session only',
        color: LumenColors.of(context).onSurfaceVariant,
      );
      return true;
    }
    if (cmd == 'help' || cmd == '?') {
      _log(
        'Lumen console — runs commands in /bin/sh via subprocess.',
        color: LumenColors.of(context).info,
      );
      _log(
        'Built-ins: clear · whoami · pwd · help',
        color: LumenColors.of(context).info,
      );
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: Glass(
            blurSigma: 14,
            radius: 0,
            fill: LumenColors.of(context).surfaceContainer,
            border: false,
            child: Row(
              children: [
                const Icon(
                  Icons.terminal,
                  size: 16,
                  color: LumenColors.codeString,
                ),
                const SizedBox(width: 8),
                Text(
                  'CONSOLE',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    color: LumenColors.of(context).outline,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    _cwd,
                    style: TextStyle(
                      fontSize: 12,
                      color: LumenColors.of(context).onSurfaceVariant,
                      fontFamily: lumenMonoFont,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => setState(_lines.clear),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Container(
            color: LumenColors.codeBackground,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _lines.length,
              itemBuilder: (c, i) {
                final l = _lines[i];
                return Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: Text(
                    l.text,
                    style: TextStyle(
                      color: l.color ?? LumenColors.of(context).onSurface,
                      fontFamily: lumenMonoFont,
                      fontSize: 12.5,
                      fontWeight: l.isCmd ? FontWeight.w600 : FontWeight.w400,
                      height: 1.45,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Divider(height: 1),
        Glass(
          blurSigma: 14,
          radius: 0,
          fill: LumenColors.of(context).surfaceContainer,
          border: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(
              children: [
                const Text(
                  '> ',
                  style: TextStyle(fontSize: 14, color: LumenColors.codeString),
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    style: const TextStyle(
                      fontFamily: lumenMonoFont,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: _busyMsg,
                      border: InputBorder.none,
                      filled: false,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintStyle: TextStyle(
                        color: LumenColors.of(context).onSurfaceVariant,
                        fontFamily: lumenMonoFont,
                      ),
                    ),
                    onSubmitted: _run,
                  ),
                ),
                IconButton(
                  tooltip: 'Run',
                  icon: const Icon(Icons.play_arrow, size: 18),
                  onPressed: _busy ? null : () => _run(_input.text),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

const _busyMsg = 'running… press Enter';

class _Line {
  _Line(this.text, {this.color, this.isCmd = false});
  final String text;
  final Color? color;
  final bool isCmd;
}
