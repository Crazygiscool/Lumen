import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../ffi/plugin_service.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/lumen_colors.dart';
import '../widgets/path_picker.dart';

/// Shows the installed plugin inventory (built-in + on-disk external) and lets
/// you toggle which plugins run. The listing reads `plugin.toml` manifests and
/// never executes plugin code.
class PluginsScreen extends ConsumerWidget {
  const PluginsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(pluginsProvider);
    final t = LumenColors.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: section.when(
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load plugins.\n$e',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.error),
            ),
          ),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Plugins',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Built-in tools plus plugins from disk. Toggle a plugin off to '
              'stop it from running; its data is kept.',
              style: TextStyle(fontSize: 13, color: t.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            _PluginGroup(
              title: 'Built-in',
              plugins: list.builtin,
              notifier: ref.read(pluginsProvider.notifier),
            ),
            const SizedBox(height: 20),
            _PluginGroup(
              title: 'External',
              plugins: list.external,
              notifier: ref.read(pluginsProvider.notifier),
            ),
            const SizedBox(height: 16),
            if (list.external.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'No external plugins installed. Drop a plugin folder '
                  '(containing plugin.toml and lib<name>.so) into:',
                  style: TextStyle(fontSize: 12.5, color: t.onSurfaceVariant),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: t.surfaceLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.hairline),
              ),
              child: Text(
                list.dir.isEmpty ? '~/.config/Lumen/plugins/' : list.dir,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: lumenMonoFont,
                  color: t.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(pluginsProvider),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reload plugins'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final picked = await showPathPicker(
                      context,
                      mode: PathPickerMode.directory,
                      title: 'Choose a plugin folder',
                    );
                    if (picked == null || !context.mounted) return;
                    final ok = await _installPluginFromFolder(
                      picked,
                      list.dir.isEmpty ? null : list.dir,
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok
                            ? 'Plugin installed. Reloaded plugin list.'
                            : 'Plugin folder must contain plugin.toml.'),
                      ),
                    );
                    ref.invalidate(pluginsProvider);
                  },
                  icon: const Icon(Icons.add_box_outlined, size: 18),
                  label: const Text('Install from folder'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PluginGroup extends StatelessWidget {
  const _PluginGroup({
    required this.title,
    required this.plugins,
    required this.notifier,
  });

  final String title;
  final List<PluginInfo> plugins;
  final PluginNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            color: t.outline,
          ),
        ),
        const SizedBox(height: 8),
        if (plugins.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'None found.',
              style: TextStyle(fontSize: 13, color: t.onSurfaceVariant),
            ),
          )
        else
          for (final p in plugins)
            _PluginTile(
              plugin: p,
              onChanged: (v) => notifier.toggle(p, v),
            ),
      ],
    );
  }
}

class _PluginTile extends ConsumerWidget {
  const _PluginTile({required this.plugin, required this.onChanged});

  final PluginInfo plugin;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LumenColors.of(context);
    final pluginService = ref.read(pluginServiceProvider);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: t.glass.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            plugin.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFamily: lumenMonoFont,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: t.surfaceContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'v${plugin.version}',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: t.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (plugin.description != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        plugin.description!,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: t.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (plugin.hooks.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 5,
                        runSpacing: 3,
                        children: [
                          for (final hook in plugin.hooks)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: t.primaryContainer
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                hook,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: lumenMonoFont,
                                  color: t.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (plugin.contributions.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 5,
                        runSpacing: 3,
                        children: [
                          for (final key in plugin.contributions.keys)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: t.secondaryContainer
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                key,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: lumenMonoFont,
                                  color: t.onSecondaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (plugin.permissions.readNotes ||
                        plugin.permissions.writeNotes ||
                        plugin.permissions.network ||
                        plugin.permissions.fsRead.isNotEmpty ||
                        plugin.permissions.fsWrite.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Permissions',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: t.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _PermissionChip(
                            label: 'Read notes',
                            value: plugin.permissions.readNotes,
                            onChanged: (v) => _togglePermission(
                              ref,
                              plugin,
                              'read_notes',
                              v,
                            ),
                          ),
                          _PermissionChip(
                            label: 'Write notes',
                            value: plugin.permissions.writeNotes,
                            onChanged: (v) => _togglePermission(
                              ref,
                              plugin,
                              'write_notes',
                              v,
                            ),
                          ),
                          _PermissionChip(
                            label: 'Network',
                            value: plugin.permissions.network,
                            onChanged: (v) => _togglePermission(
                              ref,
                              plugin,
                              'network',
                              v,
                            ),
                          ),
                        ],
                      ),
                      if (plugin.permissions.fsRead.isNotEmpty ||
                          plugin.permissions.fsWrite.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final p in plugin.permissions.fsRead)
                              _PermissionChip(
                                label: 'FS read: $p',
                                value: true,
                                onChanged: (v) => _togglePermission(
                                  ref,
                                  plugin,
                                  'fs_read',
                                  v,
                                ),
                              ),
                            for (final p in plugin.permissions.fsWrite)
                              _PermissionChip(
                                label: 'FS write: $p',
                                value: true,
                                onChanged: (v) => _togglePermission(
                                  ref,
                                  plugin,
                                  'fs_write',
                                  v,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              Switch(
                value: plugin.enabled,
                onChanged: onChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A tappable chip for toggling a permission.
class _PermissionChip extends StatelessWidget {
  const _PermissionChip({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 11)),
      selected: value,
      onSelected: onChanged,
      selectedColor: t.primary.withValues(alpha: 0.15),
      checkmarkColor: t.primary,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Toggles a single permission for a plugin.
Future<void> _togglePermission(
  WidgetRef ref,
  PluginInfo plugin,
  String permission,
  bool value,
) async {
  final service = ref.read(pluginServiceProvider);
  // The FFI method takes individual permission flags; we need to preserve
  // existing permissions and only change the one being toggled.
  final current = plugin.permissions;
  final readNotes = permission == 'read_notes' ? value : current.readNotes;
  final writeNotes = permission == 'write_notes' ? value : current.writeNotes;
  final network = permission == 'network' ? value : current.network;
  final fsRead = permission == 'fs_read'
      ? (value ? [...current.fsRead] : <String>[])
      : current.fsRead;
  final fsWrite = permission == 'fs_write'
      ? (value ? [...current.fsWrite] : <String>[])
      : current.fsWrite;

  try {
    await service.setPluginPermissions(
      plugin.name,
      readNotes: readNotes,
      writeNotes: writeNotes,
      network: network,
      fsRead: fsRead,
      fsWrite: fsWrite,
    );
    // Update local state optimistically
    // (The plugin list will be re-fetched on next screen open)
  } catch (e) {
    throw e;
  }
}

Future<bool> _installPluginFromFolder(String source, String? destRoot) async {
  final sourceDir = Directory(source);
  if (!await sourceDir.exists()) return false;
  if (!await File(p.join(source, 'plugin.toml')).exists()) return false;

  final root = destRoot == null || destRoot.isEmpty
      ? Directory(p.join(
          Platform.environment['HOME'] ?? Directory.current.path,
          '.config',
          'Lumen',
          'plugins',
        ))
      : Directory(destRoot);
  await root.create(recursive: true);

  final target = Directory(p.join(root.path, p.basename(source)));
  if (await target.exists()) {
    await target.delete(recursive: true);
  }
  await target.create(recursive: true);
  await _copyDirectory(sourceDir, target);
  return true;
}

Future<void> _copyDirectory(Directory source, Directory target) async {
  await for (final entity in source.list()) {
    final destination = p.join(target.path, p.basename(entity.path));
    if (entity is Directory) {
      await _copyDirectory(entity, Directory(destination));
    } else if (entity is File) {
      await File(destination).parent.create(recursive: true);
      await entity.copy(destination);
    }
  }
}
