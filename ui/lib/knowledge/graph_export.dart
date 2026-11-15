import 'dart:convert';

import 'kb_service.dart';

/// Export format options for graph data.
enum GraphExportFormat {
  graphml,
  json,
}

/// Exports the graph to GraphML or JSON format.
class GraphExporter {
  /// Export the graph data to the given format.
  ///
  /// Returns the serialized export string.
  static String export(KbGraphData data, GraphExportFormat format) {
    switch (format) {
      case GraphExportFormat.graphml:
        return _exportGraphML(data);
      case GraphExportFormat.json:
        return _exportJSON(data);
    }
  }

  /// Export to GraphML format (graphml.org).
  static String _exportGraphML(KbGraphData data) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<graphml xmlns="http://graphml.graphdrawing.org/xmlns"');
    buffer.writeln('         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"');
    buffer.writeln('         xsi:schemaLocation="http://graphml.graphdrawing.org/xmlns"');
    buffer.writeln('         http://graphml.graphdrawing.org/xmlns/1.0/graphml.xsd">');
    buffer.writeln('  <key id="d0" for="node" attr.name="title" attr.type="string"/>');
    buffer.writeln('  <key id="d1" for="node" attr.name="weight" attr.type="int"/>');
    buffer.writeln('  <key id="d2" for="node" attr.name="tags" attr.type="string"/>');
    buffer.writeln('  <key id="d3" for="edge" attr.name="type" attr.type="string"/>');
    buffer.writeln('  <graph id="G" edgedefault="undirected">');

    // Write nodes.
    for (final node in data.nodes) {
      buffer.writeln('    <node id="${_escape(node.id)}">');
      buffer.writeln('      <data key="d0">${_escape(node.title)}</data>');
      buffer.writeln('      <data key="d1">${node.weight}</data>');
      buffer.writeln('      <data key="d2">${_escape(node.tags.join(', '))}</data>');
      buffer.writeln('    </node>');
    }

    // Write edges.
    for (final edge in data.edges) {
      buffer.writeln(
        '    <edge source="${_escape(edge.source)}" target="${_escape(edge.target)}">',
      );
      buffer.writeln('      <data key="d3">${_edgeTypeName(edge.type)}</data>');
      buffer.writeln('    </edge>');
    }

    buffer.writeln('  </graph>');
    buffer.writeln('</graphml>');
    return buffer.toString();
  }

  /// Export to JSON format.
  static String _exportJSON(KbGraphData data) {
    final nodes = <Map<String, dynamic>>[];
    for (final node in data.nodes) {
      nodes.add({
        'id': node.id,
        'path': node.id,
        'title': node.title,
        'tags': node.tags,
        'weight': node.weight,
        'frontmatter': node.frontmatter.toJson(),
      });
    }

    final edges = <Map<String, dynamic>>[];
    for (final edge in data.edges) {
      edges.add({
        'source': edge.source,
        'target': edge.target,
        'type': _edgeTypeName(edge.type),
      });
    }

    final map = <String, dynamic>{
      'nodes': nodes,
      'edges': edges,
      'stats': {
        'nodeCount': data.nodes.length,
        'edgeCount': data.edges.length,
      },
    };

    return const JsonEncoder.withIndent('  ').convert(map);
  }

  static String _edgeTypeName(KbEdgeType type) {
    switch (type) {
      case KbEdgeType.wikilink:
        return 'wikilink';
      case KbEdgeType.backlink:
        return 'backlink';
      case KbEdgeType.tag:
        return 'tag';
      case KbEdgeType.temporal:
        return 'temporal';
    }
  }

  static String _escape(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

/// File extension for each export format.
extension GraphExportFormatExtension on GraphExportFormat {
  String get extension {
    switch (this) {
      case GraphExportFormat.graphml:
        return 'graphml';
      case GraphExportFormat.json:
        return 'json';
    }
  }

  String get mimeType {
    switch (this) {
      case GraphExportFormat.graphml:
        return 'application/xml';
      case GraphExportFormat.json:
        return 'application/json';
    }
  }

  String get label {
    switch (this) {
      case GraphExportFormat.graphml:
        return 'GraphML (.graphml)';
      case GraphExportFormat.json:
        return 'JSON (.json)';
    }
  }
}
