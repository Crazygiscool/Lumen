import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ffi/lumen_ffi.dart';
import 'package:lumen/ffi/sync_service.dart';
import 'package:lumen/sync/webdav_setup_screen.dart';

/// A native bridge fake that serves the configuration and the keyring.
class _FakeFfi implements LumenFfi {
  final List<String> methods = [];
  final List<Map<String, Object?>> args = [];

  /// Whether the account answers.
  bool connected = true;

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
      case 'kb.config.get':
        return <String, Object?>{
          'sync': {
            'method': 'none',
            'webdav': {'url': '', 'username': '', 'encrypt': true},
          },
        };
      case 'kb.config.set':
        return <String, Object?>{'saved': true};
      case 'kb.sync.credentials.status':
        return <String, Object?>{
          'available': true,
          'password': false,
          'passphrase': false,
        };
      case 'kb.sync.credentials.set':
        return <String, Object?>{'saved': true};
      case 'kb.sync.webdav.connect':
        if (!connected) throw StateError('the account did not answer');
        return <String, Object?>{'connected': true};
      default:
        return <String, Object?>{};
    }
  }
}

/// The account that was written to the configuration.
Map<String, dynamic> _writtenConfig(_FakeFfi ffi) {
  final write = ffi.args.firstWhere((a) => a.containsKey('config'));
  final config = write['config'] as Map<String, dynamic>;
  return (config['sync'] as Map<String, dynamic>)['webdav']
      as Map<String, dynamic>;
}

/// Press the button that saves the account.
///
/// The form is longer than the test window, so the button is brought into
/// view first.
Future<void> _save(WidgetTester tester) async {
  final button = find.text('Save and test');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the secrets go to the keyring, the settings to the config', (
    tester,
  ) async {
    final ffi = _FakeFfi();

    await tester.pumpWidget(
      MaterialApp(home: WebDAVSetupScreen(service: SyncService(ffi))),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Address'),
      'https://dav.example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Account'), 'me');
    await tester.enterText(
      find.widgetWithText(TextField, 'Password of the account'),
      'hunter2',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Passphrase for the uploads'),
      'a different secret',
    );

    await _save(tester);

    expect(ffi.methods, contains('kb.sync.credentials.set'));
    expect(ffi.methods, contains('kb.sync.webdav.connect'));

    // The secrets were kept in the keyring.
    final credentials = ffi.args.firstWhere(
      (a) => a.containsKey('password') && a.containsKey('passphrase'),
    );
    expect(credentials['password'], 'hunter2');
    expect(credentials['passphrase'], 'a different secret');

    // The address and the name of the account went to the configuration,
    // and the secrets did not.
    final webdav = _writtenConfig(ffi);
    expect(webdav['url'], 'https://dav.example.com');
    expect(webdav['username'], 'me');
    expect(webdav['encrypt'], isTrue);
    expect(webdav.containsKey('password'), isFalse);
    expect(webdav.containsKey('encryption_passphrase'), isFalse);
  });

  testWidgets('the uploads are not encrypted without a passphrase', (
    tester,
  ) async {
    final ffi = _FakeFfi();

    await tester.pumpWidget(
      MaterialApp(home: WebDAVSetupScreen(service: SyncService(ffi))),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Address'),
      'https://dav.example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Account'), 'me');

    await _save(tester);

    // The passphrase is needed, because the uploads are encrypted.
    expect(find.textContaining('passphrase is needed'), findsOneWidget);
    expect(ffi.methods, isNot(contains('kb.sync.credentials.set')));
  });

  testWidgets('an account that does not answer is said so', (tester) async {
    final ffi = _FakeFfi()..connected = false;

    await tester.pumpWidget(
      MaterialApp(home: WebDAVSetupScreen(service: SyncService(ffi))),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Address'),
      'https://dav.example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Account'), 'me');
    await tester.enterText(
      find.widgetWithText(TextField, 'Password of the account'),
      'hunter2',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Passphrase for the uploads'),
      'a different secret',
    );

    await _save(tester);

    expect(find.textContaining('did not answer'), findsOneWidget);
  });
}
