import 'package:flutter/foundation.dart';

import 'kb_service.dart';

/// Analytics computed over the knowledge graph.
///
/// All computations run locally on the device — no data is sent anywhere.
@immutable
class GraphAnalytics {
  const GraphAnalytics({
    required this.centrality,
    required this.clusters,
    required this.orphans,
    required this.stats,
  });

  /// PageRank centrality score per note (0.0 = peripheral, 1.0 = hub).
  final Map<String, double> centrality;

  /// Cluster id -> list of note paths in that cluster.
  final Map<int, List<String>> clusters;

  /// Notes with no incoming or outgoing links (isolated nodes).
  final List<String> orphans;

  /// Summary statistics.
  final GraphStats stats;

  /// The top-N most central notes, sorted by centrality descending.
  List<String> topCentral({int count = 10}) {
    final sorted = centrality.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(count).map((e) => e.key).toList();
  }
}

/// Summary statistics for the graph.
@immutable
class GraphStats {
  const GraphStats({
    required this.nodeCount,
    required this.edgeCount,
    required this.averageDegree,
    required this.density,
    required this.clusterCount,
    required this.orphanCount,
  });

  final int nodeCount;
  final int edgeCount;
  final double averageDegree;
  final double density;
  final int clusterCount;
  final int orphanCount;
}

/// Computes graph analytics over nodes and edges.
class GraphAnalyticsEngine {
  /// Compute all analytics over the given graph data.
  static GraphAnalytics compute(KbGraphData data) {
    final nodes = data.nodes;
    final edges = data.edges;

    final nodeCount = nodes.length;
    final edgeCount = edges.length;

    // Build adjacency lists.
    final adjacency = <String, Set<String>>{};
    for (final n in nodes) {
      adjacency[n.id] = {};
    }
    for (final e in edges) {
      adjacency[e.source]?.add(e.target);
      adjacency[e.target]?.add(e.source);
    }

    // --- Centrality: PageRank ---
    final centrality = _pagerank(nodes, edges);

    // --- Clusters: connected components via union-find ---
    final clusters = _connectedComponents(nodes, edges);

    // --- Orphans: nodes with no edges ---
    final orphans = nodes
        .where((n) => adjacency[n.id]!.isEmpty)
        .map((n) => n.id)
        .toList();

    // --- Statistics ---
    final avgDegree = nodeCount > 0 ? (2 * edgeCount) / nodeCount : 0.0;
    final maxPossible = nodeCount > 1 ? nodeCount * (nodeCount - 1) / 2 : 1;
    final density = edgeCount / maxPossible;

    return GraphAnalytics(
      centrality: centrality,
      clusters: clusters,
      orphans: orphans,
      stats: GraphStats(
        nodeCount: nodeCount,
        edgeCount: edgeCount,
        averageDegree: avgDegree,
        density: density,
        clusterCount: clusters.length,
        orphanCount: orphans.length,
      ),
    );
  }

  /// PageRank centrality with damping factor 0.85, 50 iterations.
  static Map<String, double> _pagerank(
    List<KbGraphNode> nodes,
    List<KbGraphEdge> edges,
  ) {
    final n = nodes.length;
    if (n == 0) return {};

    final index = <String, int>{};
    for (var i = 0; i < n; i++) {
      index[nodes[i].id] = i;
    }

    // Out-degree per node.
    final outDegree = <int, int>{};
    for (var i = 0; i < n; i++) {
      outDegree[i] = 0;
    }
    for (final e in edges) {
      final a = index[e.source];
      final b = index[e.target];
      if (a != null && b != null && a != b) {
        outDegree[a] = (outDegree[a] ?? 0) + 1;
        outDegree[b] = (outDegree[b] ?? 0) + 1;
      }
    }

    // Initialize ranks.
    final ranks = List<double>.filled(n, 1.0 / n);
    const damping = 0.85;
    const iterations = 50;

    for (var iter = 0; iter < iterations; iter++) {
      final newRanks = List<double>.filled(n, (1 - damping) / n);
      for (var i = 0; i < n; i++) {
        final out = outDegree[i] ?? 0;
        if (out == 0) {
          // Dangling node: distribute rank to all nodes.
          final share = damping * ranks[i] / n;
          for (var j = 0; j < n; j++) {
            newRanks[j] += share;
          }
        } else {
          // Distribute rank to neighbors.
          for (final e in edges) {
            if (index[e.source] == i && index[e.target] != i) {
              final j = index[e.target]!;
              newRanks[j] += damping * ranks[i] / out;
            }
            if (index[e.target] == i && index[e.source] != i) {
              final j = index[e.source]!;
              newRanks[j] += damping * ranks[i] / out;
            }
          }
        }
      }
      ranks.replaceRange(0, n, newRanks);
    }

    return {for (var i = 0; i < n; i++) nodes[i].id: ranks[i]};
  }

  /// Connected components via union-find.
  static Map<int, List<String>> _connectedComponents(
    List<KbGraphNode> nodes,
    List<KbGraphEdge> edges,
  ) {
    final n = nodes.length;
    final index = <String, int>{};
    for (var i = 0; i < n; i++) {
      index[nodes[i].id] = i;
    }

    final parent = List<int>.generate(n, (i) => i);
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }
    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (final e in edges) {
      final a = index[e.source];
      final b = index[e.target];
      if (a != null && b != null) {
        union(a, b);
      }
    }

    final components = <int, List<String>>{};
    for (var i = 0; i < n; i++) {
      final root = find(i);
      components.putIfAbsent(root, () => []).add(nodes[i].id);
    }

    return components;
  }
}
