import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../core/providers.dart';

class StoicImportScreen extends ConsumerStatefulWidget {
  const StoicImportScreen({super.key});

  @override
  ConsumerState<StoicImportScreen> createState() => _StoicImportScreenState();
}

class _StoicImportScreenState extends ConsumerState<StoicImportScreen> {
  String? _selectedDir;
  bool _loading = false;
  int? _result;
  String? _importUser;

  @override
  void initState() {
    super.initState();
    _importUser = ref.read(userProvider).currentUser;
  }

  Future<void> _pickDirectory() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Stoic Export Directory or .zip file',
    );
    if (dir != null) {
      setState(() => _selectedDir = dir);
      return;
    }
    // Fall back to file picker for .zip
    final file = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      dialogTitle: 'Select Stoic Export .zip file',
    );
    if (file != null && file.files.isNotEmpty) {
      setState(() => _selectedDir = file.files.single.path);
    }
  }

  Future<void> _import() async {
    if (_selectedDir == null || _importUser == null) return;

    final isUnlocked = ref.read(authProvider);
    final password = isUnlocked ? '' : (await _promptPassword(context));
    if (!isUnlocked && (password == null || password.isEmpty)) return;

    setState(() => _loading = true);

    final lumen = ref.read(lumenCoreProvider);
    final count = await Future(() => lumen.importStoic(_selectedDir!, password ?? '', _importUser!));

    if (count > 0) {
      ref.read(entriesProvider.notifier).refresh();
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = count;
    });
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
            child: const Text('Start Import'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final userState = ref.watch(userProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import from Stoic'),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: DropdownButtonFormField<String>(
                value: userState.allUsers.contains(_importUser) ? _importUser : null,
                decoration: InputDecoration(
                  labelText: 'Import as User',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: userState.allUsers.map((u) => DropdownMenuItem(
                  value: u,
                  child: Text(u),
                )).toList(),
                onChanged: (v) => setState(() => _importUser = v),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: Icon(Icons.folder_open, color: cs.primary),
              title: Text(_selectedDir != null
                  ? _selectedDir!.split('/').last
                  : 'Select Stoic Export (dir or .zip)'),
                subtitle: Text(_selectedDir ?? 'Tap to choose'),
                trailing: Icon(Icons.chevron_right, color: cs.primary),
                onTap: _loading ? null : _pickDirectory,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: (_selectedDir != null && !_loading) ? _import : null,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(_loading ? 'Importing...' : 'Import Stoic Entries'),
            ),
            if (_result != null) ...[
              const SizedBox(height: 24),
              Card(
                color: cs.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle, color: cs.primary, size: 48),
                      const SizedBox(height: 8),
                      Text(
                        'Import Complete',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Imported $_result entries',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
