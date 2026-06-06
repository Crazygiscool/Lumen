import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'project_detail_screen.dart';

class ProjectListScreen extends ConsumerWidget {
  const ProjectListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allEntries = ref.watch(entriesProvider);
    final projects = allEntries.where((e) => e.kind == 'project').toList();
    final cs = Theme.of(context).colorScheme;

    // Count child tasks per project
    final taskCount = <String, int>{};
    for (final e in allEntries) {
      if (e.parentProjectId != null && e.parentProjectId!.isNotEmpty) {
        taskCount[e.parentProjectId!] =
            (taskCount[e.parentProjectId!] ?? 0) + 1;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      body: projects.isEmpty
          ? Center(
              child: Text('No projects yet',
                  style: TextStyle(color: cs.onSurfaceVariant)))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.2,
              ),
              itemCount: projects.length,
              itemBuilder: (context, index) {
                final entry = projects[index];
                final title = entry.displayTitle.isNotEmpty
                    ? entry.displayTitle
                    : entry.id;
                final childCount = taskCount[entry.id] ?? 0;
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              ProjectDetailScreen(project: entry)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.folder, color: cs.primary, size: 32),
                          const Spacer(),
                          Text(title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 14, color: cs.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text('$childCount tasks',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
