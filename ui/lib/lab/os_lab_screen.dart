import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/fs_service.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/lumen_colors.dart';
import '../theme/glass.dart';

class OsLabScreen extends ConsumerStatefulWidget {
  const OsLabScreen({super.key});

  @override
  ConsumerState<OsLabScreen> createState() => _OsLabScreenState();
}

class _OsLabScreenState extends ConsumerState<OsLabScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabC = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sys = ref.watch(systemServiceProvider);
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
                Icon(
                  Icons.memory,
                  size: 16,
                  color: LumenColors.of(context).info,
                ),
                const SizedBox(width: 8),
                Text(
                  'OS LAB',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    color: LumenColors.of(context).outline,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TabBar(
                    controller: _tabC,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'Hardware'),
                      Tab(text: 'Processes'),
                      Tab(text: 'Mounts'),
                      Tab(text: 'Disks'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabC,
            children: [
              _Hardware(service: sys),
              _ListPanel(service: sys, kind: 'processes'),
              _ListPanel(service: sys, kind: 'mounts'),
              _ListPanel(service: sys, kind: 'disks'),
            ],
          ),
        ),
      ],
    );
  }
}

class _Hardware extends ConsumerWidget {
  const _Hardware({required this.service});
  final SystemService service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hw = ref.watch(_hwProvider);
    return hw.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(
        child: Text(
          'Error: $e',
          style: TextStyle(color: LumenColors.of(context).error),
        ),
      ),
      data: (h) {
        final cores = (h['cpu_cores'] as num?)?.toInt() ?? 0;
        final memTotal = (h['mem_total_bytes'] as num?)?.toInt() ?? 0;
        final memUsed = (h['mem_used_bytes'] as num?)?.toInt() ?? 0;
        final cpuCount = (h['cpu_count'] as num?)?.toInt() ?? 0;
        final name = h['cpu_name'] as String? ?? '';
        final os = h['os'] as String? ?? '';
        final kernel = h['kernel'] as String? ?? '';
        final host = h['host_name'] as String? ?? '';

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Card(
              title: 'CPU',
              icon: Icons.memory,
              rows: [
                ('Name', name),
                ('Cores (logical)', '$cpuCount  ·  $cores physical'),
                ('OS', os),
                ('Kernel', kernel),
                ('Hostname', host),
              ],
            ),
            const SizedBox(height: 12),
            _Card(
              title: 'Memory',
              icon: Icons.speed_outlined,
              rows: [
                ('Total', formatBytes(memTotal)),
                ('Used', formatBytes(memUsed)),
                ('Free', formatBytes(memTotal - memUsed)),
              ],
              extra: LinearProgressIndicator(
                value: memTotal == 0 ? 0 : memUsed / memTotal,
              ),
            ),
          ],
        );
      },
    );
  }
}

final _hwProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.watch(systemServiceProvider).hardware();
});

class _ListPanel extends ConsumerWidget {
  const _ListPanel({required this.service, required this.kind});
  final SystemService service;
  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = kind == 'processes'
        ? ref.watch(_procProvider)
        : kind == 'mounts'
        ? ref.watch(_mountProvider)
        : ref.watch(_diskProvider);
    return pending.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(
        child: Text(
          'Error: $e',
          style: TextStyle(color: LumenColors.of(context).error),
        ),
      ),
      data: (rows) => ListView.builder(
        itemCount: rows.length,
        itemBuilder: (c, i) {
          final r = rows[i] as Map<String, dynamic>;
          if (kind == 'processes') {
            return ListTile(
              dense: true,
              leading: const Icon(Icons.memory, size: 16),
              title: Text(
                '${r['pid']}  ${r['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontFamily: lumenMonoFont),
              ),
              subtitle: Text(
                '${r['cpu']} CPU · ${r['mem']}',
                style: const TextStyle(fontSize: 11, fontFamily: lumenMonoFont),
              ),
            );
          }
          return ListTile(
            dense: true,
            leading: Icon(
              kind == 'mounts' ? Icons.storage_outlined : Icons.storage,
              size: 16,
            ),
            title: Text(
              (r['mount'] ?? r['name'] ?? '').toString(),
              style: const TextStyle(fontSize: 13, fontFamily: lumenMonoFont),
            ),
            subtitle: Text(
              kind == 'mounts'
                  ? '${r['fs_type']}  ${r['total_bytes'] ?? ''}B'
                  : '${r['model'] ?? r['name'] ?? ''}  ${r['total_bytes'] ?? ''}B',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontFamily: lumenMonoFont),
            ),
          );
        },
      ),
    );
  }
}

final _procProvider = FutureProvider.autoDispose<List<dynamic>>((ref) {
  return ref.watch(systemServiceProvider).processes();
});
final _mountProvider = FutureProvider.autoDispose<List<dynamic>>((ref) {
  return ref.watch(systemServiceProvider).mounts();
});
final _diskProvider = FutureProvider.autoDispose<List<dynamic>>((ref) {
  return ref.watch(systemServiceProvider).disks();
});

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.icon,
    required this.rows,
    this.extra,
  });
  final String title;
  final IconData icon;
  final List<(String, String)> rows;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: LumenColors.of(context).info),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        k,
                        style: TextStyle(
                          fontSize: 12,
                          color: LumenColors.of(context).onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        v,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: lumenMonoFont,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (extra != null) ...[const SizedBox(height: 8), extra!],
          ],
        ),
      ),
    );
  }
}
