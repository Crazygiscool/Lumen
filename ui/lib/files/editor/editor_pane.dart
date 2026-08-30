import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/lumen_colors.dart';
import 'file_workspace_provider.dart';

/// A single editor viewport for one open file: header (filename + actions),
/// line-number gutter and a text field. Supports Ctrl+S (save), Ctrl+W
/// (close) and built-in undo via [UndoHistoryController].
class EditorPaneView extends StatefulWidget {
  const EditorPaneView({
    super.key,
    required this.pane,
    required this.notifier,
    required this.active,
    required this.onFocusPane,
  });

  final EditorPaneState pane;
  final FileWorkspaceNotifier notifier;
  final bool active;
  final VoidCallback onFocusPane;

  @override
  State<EditorPaneView> createState() => _EditorPaneViewState();
}

class _EditorPaneViewState extends State<EditorPaneView> {
  late final TextEditingController _ctl;
  late final FocusNode _fieldFocus;
  late String _savedText;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.pane.text);
    _savedText = widget.pane.text;
    _fieldFocus = FocusNode();
  }

  @override
  void didUpdateWidget(EditorPaneView old) {
    super.didUpdateWidget(old);
    if (widget.pane.id != old.pane.id) {
      _ctl.text = widget.pane.text;
    } else if (!widget.pane.dirty && _ctl.text != widget.pane.text) {
      // External reload after discarding changes.
      _ctl.text = widget.pane.text;
    }
    _savedText = widget.pane.text;
  }

  @override
  void dispose() {
    _ctl.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  bool get _dirty => widget.pane.editable && _ctl.text != _savedText;

  void _onChanged(String _) {
    setState(() {});
    final dirty = _dirty;
    if (dirty != widget.pane.dirty) {
      widget.notifier.syncDirty(widget.pane.id, dirty);
    }
  }

  Future<void> _save() async {
    if (!_dirty) return;
    final ok = await widget.notifier.save(widget.pane.id, _ctl.text);
    if (ok && mounted) setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final kb = HardwareKeyboard.instance;
    if (!(kb.isControlPressed || kb.isMetaPressed)) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyS:
        if (_dirty) _save();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyW:
        widget.notifier.closePane(widget.pane.id);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final pane = widget.pane;

    return Focus(
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onFocusPane,
        child: Container(
          color: t.glass.withValues(alpha: 0.35),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, t),
              const Divider(height: 1),
              Expanded(
                child: pane.error != null
                    ? _errorBody(t, pane.error!)
                    : _body(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, LumenPalette t) {
    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 8),
      color: widget.active
          ? t.primaryContainer.withValues(alpha: 0.45)
          : t.surfaceLow,
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 14, color: t.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              widget.pane.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 6),
          if (widget.pane.dirty)
            Tooltip(
              message: 'Unsaved changes',
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: t.warning,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          const Spacer(),
          _iconTooltip(
            context,
            Icons.refresh,
            'Discard changes',
            onPressed: () => widget.notifier.reload(widget.pane.id),
          ),
          _iconTooltip(
            context,
            Icons.save_outlined,
            'Save (Ctrl+S)',
            color: widget.pane.dirty ? t.primary : null,
            onPressed: _dirty ? _save : null,
          ),
          _iconTooltip(
            context,
            Icons.vertical_split,
            'Split right (side by side)',
            onPressed: () => widget.notifier.splitActive(Axis.horizontal),
          ),
          _iconTooltip(
            context,
            Icons.horizontal_split,
            'Split down',
            onPressed: () => widget.notifier.splitActive(Axis.vertical),
          ),
          _iconTooltip(
            context,
            Icons.close,
            'Close (Ctrl+W)',
            onPressed: () => widget.notifier.closePane(widget.pane.id),
          ),
        ],
      ),
    );
  }

  Widget _iconTooltip(
    BuildContext context,
    IconData icon,
    String tooltip, {
    VoidCallback? onPressed,
    Color? color,
  }) {
    final t = LumenColors.of(context);
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 15,
      icon: Icon(icon, color: color ?? t.onSurfaceVariant),
      onPressed: onPressed,
    );
  }

  Widget _body(BuildContext context) {
    final t = LumenColors.of(context);
    const lineHeight = 13.0 * 1.4;
    final lineCount = '\n'.allMatches(_ctl.text).length + 1;

    return SingleChildScrollView(
      child: SizedBox(
        width: double.infinity,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              padding: const EdgeInsets.only(top: 4, right: 6),
              decoration: BoxDecoration(
                color: t.surfaceLow,
                border: Border(
                  right: BorderSide(color: t.hairline, width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 1; i <= lineCount; i++)
                    SizedBox(
                      height: lineHeight,
                      child: Text(
                        '$i',
                        style: TextStyle(
                          fontSize: 12,
                          height: lineHeight / 12,
                          fontFamily: lumenMonoFont,
                          color: t.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minWidth: 280),
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: TextField(
                  controller: _ctl,
                  focusNode: _fieldFocus,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.none,
                  enableSuggestions: false,
                  autocorrect: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  style: const TextStyle(
                    fontFamily: lumenMonoFont,
                    fontSize: 13,
                    height: 1.4,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onChanged: _onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBody(LumenPalette t, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: t.error),
        ),
      ),
    );
  }
}