import 'package:flutter/material.dart';

import '../ffi/lumen_ffi.dart';
import '../ffi/sync_service.dart';
import '../theme/lumen_colors.dart';

/// Sets up a WebDAV account.
///
/// Two secrets are asked for, and they are not the same one: the password
/// of the account is known to the server, while the passphrase that
/// encrypts the uploads is not. Both are kept in the operating system's
/// keyring, and only the address and the name of the account are written
/// to the configuration.
class WebDAVSetupScreen extends StatefulWidget {
  const WebDAVSetupScreen({super.key, this.service});

  /// The service to ask; the native one is used when none is given.
  final SyncService? service;

  @override
  State<WebDAVSetupScreen> createState() => _WebDAVSetupScreenState();
}

class _WebDAVSetupScreenState extends State<WebDAVSetupScreen> {
  late final SyncService _service =
      widget.service ?? SyncService(LumenFfi.instance);

  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passphraseController = TextEditingController();

  bool _encrypt = true;
  bool _busy = false;
  bool _saved = false;
  String? _error;
  CredentialStatus? _credentials;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  /// Read what is already known: the account, and the secrets.
  Future<void> _load() async {
    try {
      final config = await _service.config();
      final sync = config['sync'];
      final webdav = sync is Map ? sync['webdav'] : null;
      final credentials = await _service.credentialsStatus();
      if (!mounted) return;
      setState(() {
        if (webdav is Map) {
          _urlController.text = webdav['url'] as String? ?? '';
          _usernameController.text = webdav['username'] as String? ?? '';
          _encrypt = webdav['encrypt'] as bool? ?? true;
        }
        _credentials = credentials;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Keep the secrets and the settings, and test the account.
  Future<void> _save() async {
    final url = _urlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final passphrase = _passphraseController.text;

    if (url.isEmpty) {
      setState(() => _error = 'The address of the server is needed.');
      return;
    }
    if (username.isEmpty) {
      setState(() => _error = 'The name of the account is needed.');
      return;
    }
    if (_encrypt && passphrase.isEmpty) {
      setState(
        () => _error =
            'The uploads are encrypted, so a passphrase is needed for them.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
    });

    try {
      // The secrets go to the keyring first, so they are there before the
      // account is tested.
      await _service.setCredentials(
        password: password.isEmpty ? null : password,
        passphrase: passphrase.isEmpty ? null : passphrase,
      );
      await _service.setWebDAVSettings(
        url: url,
        username: username,
        encrypt: _encrypt,
      );
      await _service.connectWebDAV(
        url: url,
        username: username,
        encrypt: _encrypt,
      );

      if (!mounted) return;
      setState(() {
        _busy = false;
        _saved = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The account was saved and answered.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    final credentials = _credentials;

    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Server', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Address',
              hintText: 'https://cloud.example.com/dav',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(labelText: 'Account'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password of the account',
              helperText: 'Kept in the keyring of this machine.',
            ),
          ),
          const SizedBox(height: 24),
          Text('Encryption', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _encrypt,
            onChanged: (value) => setState(() => _encrypt = value),
            title: const Text('Encrypt the uploads'),
            subtitle: const Text(
              'The files are encrypted before they leave the machine, so the '
              'server cannot read them.',
            ),
            contentPadding: EdgeInsets.zero,
          ),
          if (_encrypt)
            TextField(
              controller: _passphraseController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Passphrase for the uploads',
                helperText:
                    'Not the password of the account: the server knows that '
                    'one, and a server that could read the notes would know '
                    'too much.',
              ),
            ),
          const SizedBox(height: 16),
          if (credentials != null)
            Text(
              _credentialSummary(credentials),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: t.error)),
          ],
          if (_saved) ...[
            const SizedBox(height: 12),
            Text('The account was saved.', style: TextStyle(color: t.success)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save, size: 18),
            label: const Text('Save and test'),
          ),
        ],
      ),
    );
  }

  /// What is already kept, in one line.
  static String _credentialSummary(CredentialStatus status) {
    if (!status.available) {
      return 'This machine has no keyring Lumen can use, so the secrets '
          'cannot be kept.';
    }
    final parts = <String>[
      if (status.hasPassword) 'the password is kept' else 'no password kept',
      if (status.hasPassphrase)
        'the passphrase is kept'
      else
        'no passphrase kept',
    ];
    return 'In the keyring: ${parts.join(', ')}.';
  }
}
