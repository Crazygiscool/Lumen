import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ffi/lumen_ffi.dart';
import 'package:lumen/ffi/sync_service.dart';

/// A fake native bridge that records the sync calls it receives.
class _FakeFfi implements LumenFfi {
  _FakeFfi(this.responses);

  final Map<String, Object?> responses;
  final List<String> methods = [];
  final List<Map<String, Object?>> args = [];

  @override
  bool get ready => true;

  @override
  String? get initError => null;

  @override
  void init() {}

  @override
  Object? core(String method, [Map<String, Object?> args = const {}]) =>
      <String, Object?>{};

  @override
  Object? plugins(String method, [Map<String, Object?> args = const {}]) =>
      <String, Object?>{};

  @override
  Object? kb(String method, [Map<String, Object?> args = const {}]) {
    methods.add(method);
    this.args.add(args);
    return responses[method];
  }
}

void main() {
  group('SyncService', () {
    test('the status reports why the devices could not be asked', () async {
      final ffi = _FakeFfi({
        'kb.sync.status': {
          'enabled': true,
          'method': 'syncthing',
          'pending_changes': 3,
          'device_status': const [],
          'device_error': 'Syncthing is not running',
        },
      });
      final service = SyncService(ffi);

      final status = await service.status();

      expect(status.enabled, isTrue);
      expect(status.method, SyncMethod.syncthing);
      expect(status.pendingChanges, 3);
      expect(status.deviceError, 'Syncthing is not running');
    });

    test('a status without a reason has none', () async {
      final ffi = _FakeFfi({
        'kb.sync.status': {'enabled': true, 'method': 'none'},
      });
      final service = SyncService(ffi);

      expect((await service.status()).deviceError, isNull);
    });

    test('the two versions of a conflict are read from the core', () async {
      final ffi = _FakeFfi({
        'kb.sync.conflict_versions': {
          'local': '# Local\n',
          'remote': '# Remote\n',
        },
      });
      final service = SyncService(ffi);

      final versions = await service.conflictVersions(
        vaultPath: '/vault',
        path: 'alpha.md',
      );

      expect(versions.local, '# Local\n');
      expect(versions.remote, '# Remote\n');
      expect(ffi.methods, ['kb.sync.conflict_versions']);
      expect(ffi.args.first['vault_path'], '/vault');
      expect(ffi.args.first['path'], 'alpha.md');
    });

    test('the difference between the versions is parsed', () async {
      final ffi = _FakeFfi({
        'kb.sync.conflict_diff': {
          'lines': [
            {'kind': 'same', 'text': '# Gamma'},
            {'kind': 'removed', 'text': 'local'},
            {'kind': 'added', 'text': 'remote'},
          ],
        },
      });
      final service = SyncService(ffi);

      final lines = await service.conflictDiff(
        vaultPath: '/vault',
        path: 'gamma.md',
      );

      expect(lines, hasLength(3));
      expect(lines[0].kind, DiffKind.same);
      expect(lines[1].kind, DiffKind.removed);
      expect(lines[1].text, 'local');
      expect(lines[2].kind, DiffKind.added);
      expect(lines[2].text, 'remote');
    });

    test('a difference between two texts is asked for', () async {
      final ffi = _FakeFfi({
        'kb.diff.lines': {
          'lines': [
            {'kind': 'same', 'text': 'one'},
          ],
        },
      });
      final service = SyncService(ffi);

      final lines = await service.diffLines(oldText: 'one\n', newText: 'one\n');

      expect(lines, hasLength(1));
      expect(ffi.methods, ['kb.diff.lines']);
      expect(ffi.args.first['old'], 'one\n');
      expect(ffi.args.first['new'], 'one\n');
    });

    test(
      'the secrets are kept in the keyring, not in the configuration',
      () async {
        final ffi = _FakeFfi({
          'kb.sync.credentials.set': <String, Object?>{},
          'kb.sync.credentials.status': {
            'available': true,
            'password': true,
            'passphrase': false,
          },
        });
        final service = SyncService(ffi);

        await service.setCredentials(password: 'hunter2');
        final status = await service.credentialsStatus();

        expect(ffi.methods, [
          'kb.sync.credentials.set',
          'kb.sync.credentials.status',
        ]);
        // Only the password was given, so the passphrase is not asked about.
        expect(ffi.args.first['password'], 'hunter2');
        expect(ffi.args.first.containsKey('passphrase'), isFalse);
        expect(status.available, isTrue);
        expect(status.hasPassword, isTrue);
        expect(status.hasPassphrase, isFalse);
      },
    );

    test('the WebDAV connection is tested without the password', () async {
      final ffi = _FakeFfi({
        'kb.sync.webdav.connect': {'connected': true},
      });
      final service = SyncService(ffi);

      await service.connectWebDAV(
        url: 'https://dav.example.com',
        username: 'me',
        encrypt: true,
      );

      expect(ffi.methods, ['kb.sync.webdav.connect']);
      // The password is read by the core from the keyring, so it does not
      // travel through the app.
      expect(ffi.args.first.containsKey('password'), isFalse);
      expect(ffi.args.first['url'], 'https://dav.example.com');
      expect(ffi.args.first['username'], 'me');
      expect(ffi.args.first['encrypt'], isTrue);
    });

    test('the WebDAV settings are read back', () async {
      final ffi = _FakeFfi({
        'kb.config.get': {
          'sync': {
            'method': 'webdav',
            'webdav': {
              'url': 'https://dav.example.com',
              'username': 'me',
              'encrypt': false,
            },
          },
        },
      });
      final service = SyncService(ffi);

      final settings = await service.webdavSettings();

      expect(settings.url, 'https://dav.example.com');
      expect(settings.username, 'me');
      expect(settings.encrypt, isFalse);
    });

    test('the notes are sent and taken, and what happened is said', () async {
      final ffi = _FakeFfi({
        'kb.sync.webdav.sync': {
          'uploaded': ['a.md'],
          'downloaded': ['b.md', 'c.md'],
          'deleted': <String>[],
          'conflicts': <dynamic>[],
          'errors': <String>[],
        },
      });
      final service = SyncService(ffi);

      final report = await service.syncWebDAV(vaultPath: '/vault');

      expect(ffi.methods, ['kb.sync.webdav.sync']);
      expect(ffi.args.first['vault_path'], '/vault');
      expect(ffi.args.first.containsKey('password'), isFalse);
      expect(report.uploaded, ['a.md']);
      expect(report.downloaded, ['b.md', 'c.md']);
      expect(report.conflicts, isEmpty);
      expect(report.isEmpty, isFalse);
    });

    test('a conflict says where it came from', () async {
      final ffi = _FakeFfi({
        'kb.sync.status': {
          'enabled': true,
          'method': 'webdav',
          'conflicts': [
            {
              'path': 'alpha.md',
              'local_modified': '2026-01-01T00:00:00Z',
              'remote_modified': '2026-01-02T00:00:00Z',
              'local_hash': 'aaa',
              'remote_hash': 'bbb',
              'source': 'webdav',
            },
          ],
        },
      });
      final service = SyncService(ffi);

      final status = await service.status();

      expect(status.conflicts, hasLength(1));
      expect(status.conflicts.first.source, 'webdav');
    });

    test('a conflict of Syncthing says so', () async {
      final ffi = _FakeFfi({
        'kb.sync.status': {
          'enabled': true,
          'method': 'syncthing',
          'conflicts': [
            {
              'path': 'alpha.md',
              'local_modified': '2026-01-01T00:00:00Z',
              'remote_modified': '2026-01-02T00:00:00Z',
              'local_hash': 'aaa',
              'remote_hash': 'bbb',
            },
          ],
        },
      });
      final service = SyncService(ffi);

      final status = await service.status();

      expect(status.conflicts.first.source, 'syncthing');
    });

    test('a conflict is settled with the folder of the vault', () async {
      final ffi = _FakeFfi({'kb.sync.resolve_conflict': <String, Object?>{}});
      final service = SyncService(ffi);

      await service.resolveConflict(
        'alpha.md',
        keepLocal: true,
        vaultPath: '/vault',
      );

      expect(ffi.methods, ['kb.sync.resolve_conflict']);
      expect(ffi.args.first['path'], 'alpha.md');
      expect(ffi.args.first['keep_local'], isTrue);
      expect(ffi.args.first['vault_path'], '/vault');
    });

    test('the sync method is written to the configuration', () async {
      final ffi = _FakeFfi({
        'kb.config.get': {
          'sync': {
            'method': 'none',
            'webdav': {'url': '', 'username': '', 'encrypt': true},
          },
        },
        'kb.config.set': <String, Object?>{},
      });
      final service = SyncService(ffi);

      await service.setSyncMethod(SyncMethod.webdav);

      expect(ffi.methods, ['kb.config.get', 'kb.config.set']);
      final written = ffi.args.last['config'] as Map<String, dynamic>;
      final sync = written['sync'] as Map<String, dynamic>;
      expect(sync['method'], 'webdav');
      // The rest of the configuration is left alone.
      expect((sync['webdav'] as Map)['url'], '');
    });

    test('the WebDAV settings are written to the configuration', () async {
      final ffi = _FakeFfi({
        'kb.config.get': {
          'sync': {
            'method': 'webdav',
            'webdav': {'url': '', 'username': '', 'encrypt': false},
          },
        },
        'kb.config.set': <String, Object?>{},
      });
      final service = SyncService(ffi);

      await service.setWebDAVSettings(
        url: 'https://dav.example.com',
        username: 'me',
        encrypt: true,
      );

      final written = ffi.args.last['config'] as Map<String, dynamic>;
      final sync = written['sync'] as Map<String, dynamic>;
      final webdav = sync['webdav'] as Map<String, dynamic>;
      expect(webdav['url'], 'https://dav.example.com');
      expect(webdav['username'], 'me');
      expect(webdav['encrypt'], isTrue);
      // The password and the passphrase are not in the configuration.
      expect(webdav.containsKey('password'), isFalse);
      expect(webdav.containsKey('encryption_passphrase'), isFalse);
    });
  });
}
