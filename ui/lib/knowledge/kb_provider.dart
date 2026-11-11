import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'kb_service.dart';

/// The knowledge-base API, bound to the encrypted journal store.
final kbServiceProvider = Provider<KbService>((ref) {
  return KbService(ref.watch(lumenFfiProvider));
});

/// The full-text search results for the current query.
///
/// The query is held separately so the search screen can debounce it without
/// re-running the search on every keystroke.
final kbSearchProvider =
    FutureProvider.autoDispose.family<List<KbSearchHit>, String>((ref, query) {
      final trimmed = query.trim();
      if (trimmed.isEmpty) return const [];
      return ref.watch(kbServiceProvider).search(trimmed);
    });

/// Every tag used in the vault, sorted.
final kbTagsProvider = FutureProvider<List<String>>((ref) async {
  final graph = await ref.watch(kbServiceProvider).graphData();
  final tags = <String>{};
  for (final node in graph.nodes) {
    tags.addAll(node.tags);
  }
  return tags.toList()..sort();
});

/// The graph, narrowed by a set of tags and a text query.
final kbGraphFilterProvider =
    FutureProvider.autoDispose.family<KbGraphData, (List<String>, String)>((
      ref,
      args,
    ) {
      final (tags, query) = args;
      if (tags.isEmpty && query.isEmpty) {
        return ref.watch(kbServiceProvider).graphData();
      }
      return ref.watch(kbServiceProvider).filterGraph(
        tags: tags,
        query: query.isEmpty ? null : query,
      );
    });
