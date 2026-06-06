import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../core/providers.dart';

class ExportImportScreen extends ConsumerWidget {
  const ExportImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Export / Import')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ActionCard(
              icon: Icons.file_upload_outlined,
              title: 'Export All Entries',
              subtitle: 'Decrypt and save all entries as JSON',
              color: cs.primary,
              onTap: () => _exportAll(context, ref),
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.file_download_outlined,
              title: 'Import Entries',
              subtitle: 'Restore entries from a JSON backup file',
              color: cs.tertiary,
              onTap: () => _importEntries(context, ref),
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.upload_file,
              title: 'Export Project',
              subtitle: 'Export a single project as Markdown',
              color: cs.secondary,
              onTap: () => _exportProject(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportAll(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) return;
    final password = await _promptPassword(context);
    if (password == null) return;

    final json = ref.read(entriesProvider.notifier).exportAll(password);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save export file',
      fileName: 'lumen_export.json',
      type: FileType.any,
    );
    if (path == null) return;

    await File(path).writeAsString(json);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to $path')),
      );
    }
  }

  Future<void> _importEntries(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) return;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select import JSON file',
      type: FileType.any,
    );
    if (result == null || result.files.single.path == null) return;

    final json = await File(result.files.single.path!).readAsString();
    // Validate JSON array
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text('Invalid format: expected JSON array')),
          );
        }
        return;
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Invalid JSON file')),
        );
      }
      return;
    }

    final count = ref.read(entriesProvider.notifier).import(json);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $count entries')),
      );
    }
  }

  Future<void> _exportProject(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) return;
    final password = await _promptPassword(context);
    if (password == null) return;

    final entries = ref.read(entriesProvider);
    final projects = entries
        .where((e) => e.kind == 'project')
        .map((e) => e.displayTitle.isNotEmpty ? e.displayTitle : e.id)
        .toList();

    if (projects.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('No projects found')),
        );
      }
      return;
    }

    if (!context.mounted) return;
    final selection = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Project'),
        children: projects
            .map((p) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, p),
                  child: Text(p),
                ))
            .toList(),
      ),
    );
    if (selection == null) return;

    final entry = entries.firstWhere(
      (e) => e.displayTitle == selection,
      orElse: () => entries.first,
    );
    final md = ref.read(entriesProvider.notifier).exportProject(entry.id, password);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save project export',
      fileName: '${selection.replaceAll(' ', '_')}.md',
      type: FileType.any,
    );
    if (path == null) return;

    await File(path).writeAsString(md);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Project exported to $path')),
      );
    }
  }

  Future<String?> _promptPassword(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enter Password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right, color: color),
        onTap: onTap,
      ),
    );
  }
}
