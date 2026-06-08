import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reactive_mind_map/reactive_mind_map.dart';

import '../core/models/journal_entry.dart';
import '../core/providers.dart';
import '../utils/responsive.dart';
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final narrow = isNarrow(context);

    if (allEntries.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: narrow ? null : AppBar(
          title: const Text('Mind Map'),
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bubble_chart_outlined, size: 64, color: cs.outlineVariant),
              const SizedBox(height: 16),
              Text('Add entries to see the mind map',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    final data = _buildTree(allEntries);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: narrow ? null : AppBar(
        title: const Text('Mind Map'),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
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
          levelSpacing: 120,
          nodeMargin: 16,
          textPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          nodeShape: NodeShape.roundedRectangle,
          defaultTextStyle: theme.textTheme.bodyMedium?.copyWith(
            fontFamily: 'Geist',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ) ?? TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
          connectionColor: cs.outlineVariant,
          connectionWidth: 2.0,
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
