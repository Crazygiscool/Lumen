import 'dart:io';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/lumen_colors.dart';
import 'graph_analytics.dart';
import 'graph_export.dart';
import 'kb_provider.dart';
import 'kb_service.dart';

/// A force-directed layout over the knowledge graph.
///
/// The layout is computed on the CPU, so it stays offline and adds no
/// dependency. Repulsion is approximated with a uniform grid, which keeps the
/// cost near-linear instead of quadratic — a vault with thousands of notes
/// still lays out in a fraction of a second.
class GraphLayout {
  GraphLayout(this.positions, this.size);

  /// Node id -> position in layout space.
  final Map<String, Offset> positions;
  final Size size;

  /// Lays the graph out inside [size].
  ///
  /// [focus] pins a note to the centre, so its neighbourhood stays legible.
  static GraphLayout compute(
    List<KbGraphNode> nodes,
    List<KbGraphEdge> edges,
    Size size, {
    String? focus,
  }) {
    if (nodes.isEmpty) {
      return GraphLayout(const {}, size);
    }

    final count = nodes.length;
    final index = <String, int>{};
    for (var i = 0; i < count; i++) {
      index[nodes[i].id] = i;
    }

    // Start on a ring so the first iteration does not have to break ties.
    final rng = math.Random(7);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.35;
    final positions = List<Offset>.generate(count, (i) {
      if (nodes[i].id == focus) return center;
      final angle = 2 * math.pi * i / count;
      final jitter = 0.85 + rng.nextDouble() * 0.3;
      return center +
          Offset(
            math.cos(angle) * radius * jitter,
            math.sin(angle) * radius * jitter,
          );
    });

    // The ideal distance between two nodes.
    final k = math.sqrt((size.width * size.height) / count) * 0.75;
    final iterations = count > 1500
        ? 50
        : count > 500
            ? 100
            : 220;

    final dx = List<double>.filled(count, 0);
    final dy = List<double>.filled(count, 0);
    final cell = math.max(k, 1.0);

    for (var step = 0; step < iterations; step++) {
      final cooling = 1 - step / iterations;
      for (var i = 0; i < count; i++) {
        dx[i] = 0;
        dy[i] = 0;
      }

      // Repulsion, approximated over the neighbouring grid cells only.
      final buckets = <int, List<int>>{};
      for (var i = 0; i < count; i++) {
        final key = _cellKeyFor(positions[i], cell);
        buckets.putIfAbsent(key, () => <int>[]).add(i);
      }

      for (var i = 0; i < count; i++) {
        final p = positions[i];
        final cx = (p.dx / cell).floor();
        final cy = (p.dy / cell).floor();
        for (var ox = -1; ox <= 1; ox++) {
          for (var oy = -1; oy <= 1; oy++) {
            final neighbours = buckets[_cellKey(cx + ox, cy + oy)];
            if (neighbours == null) continue;
            for (final j in neighbours) {
              if (j == i) continue;
              final q = positions[j];
              var vx = p.dx - q.dx;
              var vy = p.dy - q.dy;
              var dist = math.sqrt(vx * vx + vy * vy);
              if (dist < 0.01) {
                // Two nodes on the same spot: nudge them apart.
                vx = (rng.nextDouble() - 0.5) * 0.1;
                vy = (rng.nextDouble() - 0.5) * 0.1;
                dist = 0.01;
              }
              final force = (k * k) / dist;
              dx[i] += (vx / dist) * force;
              dy[i] += (vy / dist) * force;
            }
          }
        }
      }

      // Attraction along the edges.
      for (final edge in edges) {
        final a = index[edge.source];
        final b = index[edge.target];
        if (a == null || b == null) continue;
        final p = positions[a];
        final q = positions[b];
        final vx = q.dx - p.dx;
        final vy = q.dy - p.dy;
        final dist = math.max(math.sqrt(vx * vx + vy * vy), 0.01);
        final force = (dist * dist) / k;
        dx[a] += (vx / dist) * force;
        dy[a] += (vy / dist) * force;
        dx[b] -= (vx / dist) * force;
        dy[b] -= (vy / dist) * force;
      }

      // Gravity towards the centre keeps disconnected parts together.
      for (var i = 0; i < count; i++) {
        final p = positions[i];
        final vx = center.dx - p.dx;
        final vy = center.dy - p.dy;
        final dist = math.max(math.sqrt(vx * vx + vy * vy), 0.01);
        final force = math.min(dist * 0.06, k * 0.4);
        dx[i] += (vx / dist) * force;
        dy[i] += (vy / dist) * force;
      }

      final limit = k * 2 * cooling;
      for (var i = 0; i < count; i++) {
        final p = positions[i];
        final nx = (p.dx + dx[i].clamp(-limit, limit)).toDouble();
        final ny = (p.dy + dy[i].clamp(-limit, limit)).toDouble();
        // Keep the nodes inside the canvas.
        positions[i] = Offset(
          nx.clamp(24.0, math.max(24.0, size.width - 24)),
          ny.clamp(24.0, math.max(24.0, size.height - 24)),
        );
      }
    }

    return GraphLayout(
      {for (var i = 0; i < count; i++) nodes[i].id: positions[i]},
      size,
    );
  }

  /// The grid cell a position falls into.
  ///
  /// The coordinates are shifted into a positive range before they are
  /// packed, so negative positions cannot collide with positive ones.
  static int _cellKeyFor(Offset p, double cell) =>
      _cellKey((p.dx / cell).floor(), (p.dy / cell).floor());

  static int _cellKey(int cx, int cy) => (cx + 100000) * 200001 + (cy + 100000);
}

/// The knowledge graph, drawn as a force-directed map.
class GraphScreen extends ConsumerStatefulWidget {
  const GraphScreen({super.key});

  @override
  ConsumerState<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends ConsumerState<GraphScreen> {
  final _query = TextEditingController();
  final Set<String> _tags = {};
  String? _focus;
  Size _size = const Size(800, 600);
  GraphAnalytics? _analytics;
  bool _exporting = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final unlocked = ref.watch(journalVaultProvider).unlocked;

    if (!unlocked) {
      return Center(
        child: Text(
          'Unlock the journal to see its graph.',
          style: TextStyle(color: t.onSurfaceVariant),
        ),
      );
    }

    final graph = ref.watch(
      kbGraphFilterProvider((_tags.toList(), _query.text.trim())),
    );

    // Compute analytics when data changes.
    _analytics = graph.whenData((g) => GraphAnalyticsEngine.compute(g)).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.filter_alt_outlined),
                    hintText: 'Filter notes…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (_focus != null)
                TextButton.icon(
                  onPressed: () => setState(() => _focus = null),
                  icon: const Icon(Icons.center_focus_strong),
                  label: const Text('Whole graph'),
                ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _exporting ? null : () => _exportGraph(context),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                for (final tag
                    in ref.watch(kbTagsProvider).asData?.value ??
                        const <String>[])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: _tags.contains(tag),
                      label: Text(tag),
                      onSelected: (_) => setState(() {
                        if (!_tags.remove(tag)) _tags.add(tag);
                      }),
                      selectedColor: t.primary.withValues(alpha: 0.2),
                      checkmarkColor: t.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_analytics != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Graph Analytics',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _AnalyticsCard(
                        title: 'Notes',
                        value: _analytics!.stats.nodeCount.toString(),
                        subtitle: '${_analytics!.stats.edgeCount} edges',
                        icon: Icons.note_outlined,
                      ),
                    ),
                    Expanded(
                      child: _AnalyticsCard(
                        title: 'Clusters',
                        value: _analytics!.stats.clusterCount.toString(),
                        subtitle: '${(_analytics!.stats.density * 100).toStringAsFixed(1)}% density',
                        icon: Icons.layers_outlined,
                      ),
                    ),
                    Expanded(
                      child: _AnalyticsCard(
                        title: 'Orphan Notes',
                        value: _analytics!.stats.orphanCount.toString(),
                        subtitle: 'No links',
                        icon: Icons.person_outline,
                      ),
                    ),
                    Expanded(
                      child: _AnalyticsCard(
                        title: 'Avg Degree',
                        value: _analytics!.stats.averageDegree.toStringAsFixed(1),
                        subtitle: 'Avg links per note',
                        icon: Icons.share_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _analytics!.topCentral().take(5).map((path) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(
                            path.length > 30 ? '${path.substring(0, 27)}…' : path,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onPressed: () => setState(() => _focus = path),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
        Expanded(
          child: graph.when(
            loading: () => const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (e, _) => Center(
              child: Text(
                'Graph failed: $e',
                style: TextStyle(color: t.error),
              ),
            ),
            data: (data) {
              if (data.nodes.isEmpty) {
                return Center(
                  child: Text(
                    'No notes to map yet.',
                    style: TextStyle(color: t.onSurfaceVariant),
                  ),
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  _size = Size(
                    constraints.maxWidth.isFinite ? constraints.maxWidth : 800,
                    constraints.maxHeight.isFinite ? constraints.maxHeight : 600,
                  );
                  return _GraphCanvas(
                    data: data,
                    size: _size,
                    focus: _focus,
                    onNodeTap: (id) => setState(() => _focus = id),
                    onOpen: (id) => openJournalNote(ref, id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Export the graph to the user-selected location.
  Future<void> _exportGraph(BuildContext context) async {
    final graph = ref.read(
      kbGraphFilterProvider((_tags.toList(), _query.text.trim())),
    ).value;
    if (graph == null) return;

    final t = LumenColors.of(context);

    final format = await showDialog<GraphExportFormat>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Graph'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.format_line_spacing),
              title: const Text('GraphML'),
              subtitle: const Text('GraphML format (.graphml)'),
              onTap: () => Navigator.pop(context, GraphExportFormat.graphml),
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('JSON'),
              subtitle: const Text('JSON format (.json)'),
              onTap: () => Navigator.pop(context, GraphExportFormat.json),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (format == null || !context.mounted) return;

    final defaultName = 'lumen-graph-${DateTime.now().toIso8601String().substring(0, 10)}.${format.extension}';
    final downloadsDir = Directory('/storage/emulated/0/Download');
    final exportPath = '${downloadsDir.path}/$defaultName';

    final finalPath = '$exportPath.${format.extension}';
    final content = GraphExporter.export(graph, format);

    try {
      await File(finalPath).writeAsString(content);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Graph exported to $finalPath'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: t.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

/// A small analytics card showing one stat.
class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Container(
      width: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: t.primary),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: t.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: t.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The canvas the graph is drawn on.
class _GraphCanvas extends StatefulWidget {
  const _GraphCanvas({
    required this.data,
    required this.size,
    required this.focus,
    required this.onNodeTap,
    required this.onOpen,
  });

  final KbGraphData data;
  final Size size;
  final String? focus;
  final ValueChanged<String> onNodeTap;
  final ValueChanged<String> onOpen;

  @override
  State<_GraphCanvas> createState() => _GraphCanvasState();
}

class _GraphCanvasState extends State<_GraphCanvas> {
  late GraphLayout _layout;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(_GraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.size != widget.size ||
        oldWidget.focus != widget.focus) {
      _recompute();
    }
  }

  void _recompute() {
    _layout = GraphLayout.compute(
      widget.data.nodes,
      widget.data.edges,
      widget.size,
      focus: widget.focus,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);

    return InteractiveViewer(
      boundaryMargin: const EdgeInsets.all(120),
      minScale: 0.2,
      maxScale: 4,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final hit = _nodeAt(details.localPosition);
          if (hit == null) return;
          if (_selected == hit) {
            widget.onOpen(hit);
          } else {
            widget.onNodeTap(hit);
          }
          setState(() => _selected = hit);
        },
        child: CustomPaint(
          size: widget.size,
          painter: _GraphPainter(
            data: widget.data,
            layout: _layout,
            selected: _selected,
            primary: t.primary,
            onSurface: t.onSurface,
            onSurfaceVariant: t.onSurfaceVariant,
            surfaceHigh: t.surfaceHigh,
          ),
        ),
      ),
    );
  }

  /// The node under a point, if any.
  String? _nodeAt(Offset point) {
    String? best;
    var bestDistance = double.infinity;
    for (final node in widget.data.nodes) {
      final position = _layout.positions[node.id];
      if (position == null) continue;
      final radius = graphNodeRadius(node);
      final distance = (position - point).distance;
      if (distance <= radius + 4 && distance < bestDistance) {
        bestDistance = distance;
        best = node.id;
      }
    }
    return best;
  }
}

/// The radius a node is drawn with — bigger notes sit closer to the centre.
double graphNodeRadius(KbGraphNode node) {
  final weight = node.weight.clamp(1, 5000);
  return (6 + math.sqrt(weight) * 0.9).clamp(6.0, 26.0);
}

/// Draws the graph's edges and nodes.
class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.data,
    required this.layout,
    required this.selected,
    required this.primary,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.surfaceHigh,
  });

  final KbGraphData data;
  final GraphLayout layout;
  final String? selected;
  final Color primary;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color surfaceHigh;

  @override
  void paint(Canvas canvas, Size size) {
    final positions = layout.positions;

    // Edges first, so the nodes sit on top of them.
    for (final edge in data.edges) {
      final a = positions[edge.source];
      final b = positions[edge.target];
      if (a == null || b == null) continue;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = edge.type == KbEdgeType.wikilink ? 1.4 : 1
        ..color = switch (edge.type) {
          KbEdgeType.wikilink => primary.withValues(alpha: 0.55),
          KbEdgeType.backlink => primary.withValues(alpha: 0.3),
          KbEdgeType.tag => onSurfaceVariant.withValues(alpha: 0.25),
          KbEdgeType.temporal => onSurfaceVariant.withValues(alpha: 0.18),
        };

      canvas.drawLine(a, b, paint);
    }

    for (final node in data.nodes) {
      final position = positions[node.id];
      if (position == null) continue;
      final radius = graphNodeRadius(node);
      final isSelected = node.id == selected;

      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = isSelected
            ? primary
            : (node.tags.isEmpty
                  ? onSurfaceVariant.withValues(alpha: 0.55)
                  : primary.withValues(alpha: 0.75));
      canvas.drawCircle(position, radius, fill);

      canvas.drawCircle(
        position,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 2.5 : 1
          ..color = surfaceHigh.withValues(alpha: isSelected ? 0.9 : 0.4),
      );

      // Only the most connected notes get a label — otherwise the map turns
      // into a wall of text.
      if (radius > 11 || isSelected) {
        final painter = TextPainter(
          text: TextSpan(
            text: node.title,
            style: TextStyle(
              color: onSurface,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 120);
        painter.paint(canvas, position + Offset(-painter.width / 2, radius + 3));
      }
    }
  }

  @override
  bool shouldRepaint(_GraphPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.layout != layout ||
      oldDelegate.selected != selected ||
      oldDelegate.primary != primary;
}
