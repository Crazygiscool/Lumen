import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ffi/lumen_ffi.dart';
import 'package:lumen/ffi/sync_service.dart';
import 'package:lumen/settings/sync_settings_screen.dart';

/// A native bridge fake that serves the sync API.
class _FakeFfi implements LumenFfi {
  final List<String> methods = [];
  final List<Map<String, Object?>> args = [];

  /// The method the status reports.
  String method = 'webdav';

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
    switch (method) {
      case 'kb.sync.init':
        return <String, Object?>{'initialized': true};
      case 'kb.sync.status':
        return <String, Object?>{
          'enabled': true,
          'method': this.method,
          'pending_changes': 0,
          'conflicts': const [],
          'device_status': const [],
          if (this.method == 'syncthing')
            'device_error': 'Syncthing is not running',
        };
      case 'kb.sync.webdav.sync':
        return <String, Object?>{
          'uploaded': ['a.md'],
          'downloaded': <String>[],
          'deleted': <String>[],
          'conflicts': <dynamic>[],
          'errors': <String>[],
        };
      case 'kb.config.get':
        return <String, Object?>{
          'sync': {
            'method': this.method,
            'webdav': {
              'url': 'https://dav.example.com',
              'username': 'me',
              'encrypt': true,
            },
          },
        };
      case 'kb.config.set':
        return <String, Object?>{'saved': true};
      default:
        return <String, Object?>{};
    }
  }
}

/// The screen, with the service built on the fake.
Widget _screen(_FakeFfi ffi) => MaterialApp(
  home: SyncSettingsScreen(vaultPath: '/vault', service: SyncService(ffi)),
);

void main() {
  testWidgets('the reason the devices are missing is shown', (tester) async {
    final ffi = _FakeFfi()..method = 'syncthing';

    await tester.pumpWidget(_screen(ffi));
    await tester.pumpAndSettle();

    expect(find.text('Syncthing is not running'), findsOneWidget);
  });

  testWidgets('syncing now sends the notes when the method is WebDAV', (
    tester,
  ) async {
    final ffi = _FakeFfi()..method = 'webdav';

    await tester.pumpWidget(_screen(ffi));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sync Now'));
    await tester.pumpAndSettle();

    expect(ffi.methods, contains('kb.sync.webdav.sync'));
    final index = ffi.methods.indexOf('kb.sync.webdav.sync');
    final sync = ffi.args[index];
    expect(sync['vault_path'], '/vault');
    // The address and the name of the account are read by the core from the
    // configuration, so they do not travel through the app.
    expect(sync.containsKey('url'), isFalse);
    expect(sync.containsKey('password'), isFalse);
  });

  testWidgets('what the sync did is said', (tester) async {
    final ffi = _FakeFfi()..method = 'webdav';

    await tester.pumpWidget(_screen(ffi));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sync Now'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 sent'), findsOneWidget);
  });

  testWidgets('syncing now does not send anything for Syncthing', (
    tester,
  ) async {
    final ffi = _FakeFfi()..method = 'syncthing';

    await tester.pumpWidget(_screen(ffi));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sync Now'));
    await tester.pumpAndSettle();

    // Syncthing syncs on its own, so there is nothing for Lumen to push.
    expect(ffi.methods, isNot(contains('kb.sync.webdav.sync')));
  });

  testWidgets('choosing a method writes it to the configuration', (
    tester,
  ) async {
    final ffi = _FakeFfi()..method = 'webdav';

    await tester.pumpWidget(_screen(ffi));
    await tester.pumpAndSettle();

    await tester.tap(find.text('None (Manual)'));
    await tester.pumpAndSettle();

    expect(ffi.methods, contains('kb.config.set'));
    final write = ffi.args.firstWhere((a) => a.containsKey('config'));
    final config = write['config'] as Map<String, dynamic>;
    final sync = config['sync'] as Map<String, dynamic>;
    expect(sync['method'], 'none');
  });
}
