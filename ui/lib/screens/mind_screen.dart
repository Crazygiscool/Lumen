import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reactive_mind_map/reactive_mind_map.dart';

import '../core/models/journal_entry.dart';
import '../core/providers.dart';
import 'entry_view_screen.dart';

class MindScreen extends ConsumerWidget {
  const MindScreen({super.key});

  MindMapData _buildTree(List<JournalEntry> entries) {
    final kindMap = <String, List<JournalEntry>>{};
    for (final e in entries) {
      kindMap.putIfAbsent(e.kind, () => []).add(e);
    }

    return MindMapData(
      id: 'root',
      title: 'Lumen',
      children: kindMap.entries.map((entry) {
        final kind = entry.key;
        final kindEntries = entry.value;
        return MindMapData(
          id: 'kind_$kind',
          title: kind,
          children: kindEntries.take(20).map((e) {
            final title = e.displayTitle.isNotEmpty ? e.displayTitle : e.id;
            return MindMapData(
              id: e.id,
              title: title,
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allEntries = ref.watch(entriesProvider);
    final cs = Theme.of(context).colorScheme;

    if (allEntries.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mind Map')),
        body: Center(
          child: Text('Add entries to see the mind map',
              style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      );
    }

    final data = _buildTree(allEntries);

    return Scaffold(
      appBar: AppBar(title: const Text('Mind Map')),
      body: MindMapWidget(
        data: data,
        style: MindMapStyle(
          backgroundColor: Colors.transparent,
          layout: MindMapLayout.radial,
          defaultNodeColors: [
            cs.primary,
            cs.secondary,
            cs.tertiary,
            cs.error,
          ],
          levelSpacing: 100,
          nodeMargin: 12,
          textPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          nodeShape: NodeShape.roundedRectangle,
          defaultTextStyle: TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: cs.onSurface,
          ),
          connectionColor: cs.outlineVariant,
          connectionWidth: 1.5,
        ),
        cameraFocus: CameraFocus.fitAll,
        isNodesCollapsed: false,
        onNodeTap: (node) {
          // Open entry view for leaf nodes (entries), not kind groups
          if (node.id.startsWith('kind_')) return;
          final entry = allEntries.where((e) => e.id == node.id).firstOrNull;
          if (entry != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => EntryViewScreen(entry: entry)),
            );
          }
        },
      ),
    );
  }
}
