import 'package:flutter/material.dart';

import 'file_workspace_provider.dart';

/// Renders the [PaneArea] split tree: one widget per pane, laid out in rows
/// and columns with draggable dividers between them.
class SplitGrid extends StatelessWidget {
  const SplitGrid({
    super.key,
    required this.layout,
    required this.onAdaptWeight,
    required this.paneBuilder,
  });

  final PaneArea layout;

  /// Reports `(steerPaneId, fraction)` so the workspace can shift weight
  /// toward the pane on the "pushed" side of a divider.
  final void Function(String steerId, double fraction) onAdaptWeight;

  final Widget Function(EditorPaneState pane) paneBuilder;

  @override
  Widget build(BuildContext context) {
    return _Node(layout: layout, onAdaptWeight: onAdaptWeight, paneBuilder: paneBuilder);
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.layout, required this.onAdaptWeight, required this.paneBuilder});

  final PaneArea layout;
  final void Function(String steerId, double fraction) onAdaptWeight;
  final Widget Function(EditorPaneState pane) paneBuilder;

  @override
  Widget build(BuildContext context) {
    switch (layout) {
      case PaneLeaf(:final pane):
        return paneBuilder(pane);
      case PaneSplit(:final axis, :final children, :final weights):
        final childrenWidgets = <Widget>[];
        for (var i = 0; i < children.length; i++) {
          if (i > 0) {
            childrenWidgets.add(
              _SplitDivider(
                axis: axis,
                onDrag: (fraction) {
                  final steer = leafPaneIds(children[i]).first;
                  onAdaptWeight(steer, fraction);
                },
              ),
            );
          }
          final flex = (weights[i] * 10000).round().clamp(1, 1 << 30);
          childrenWidgets.add(
            Expanded(
              flex: flex,
              child: _Node(
                layout: children[i],
                onAdaptWeight: onAdaptWeight,
                paneBuilder: paneBuilder,
              ),
            ),
          );
        }
        return axis == Axis.horizontal
            ? Row(children: childrenWidgets)
            : Column(children: childrenWidgets);
    }
  }
}

class _SplitDivider extends StatelessWidget {
  const _SplitDivider({required this.axis, required this.onDrag});

  final Axis axis;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final horizontal = axis == Axis.horizontal;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: horizontal
          ? (d) => _drag(d.delta.dx, context)
          : null,
      onVerticalDragUpdate: horizontal
          ? null
          : (d) => _drag(d.delta.dy, context),
      child: MouseRegion(
        cursor: horizontal
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        child: Container(
          width: horizontal ? 5 : null,
          height: horizontal ? null : 5,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: horizontal ? 1 : null,
              height: horizontal ? null : 1,
              color: theme.colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }

  void _drag(double delta, BuildContext context) {
    if (delta == 0) return;
    final box = context.findRenderObject() as RenderBox?;
    final extent = axis == Axis.horizontal
        ? (box?.size.width ?? 0)
        : (box?.size.height ?? 0);
    if (extent <= 0) return;
    onDrag(delta / extent);
  }
}