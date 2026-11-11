import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ffi/lumen_ffi.dart';
import 'package:lumen/ffi/plugin_service.dart';
import 'package:lumen/ffi/sync_service.dart';
import 'package:lumen/ffi/vault_service.dart';

/// A synchronous fake for the native bridge. The real bridge returns plain
/// values, so service methods must wrap them in futures themselves.
class FakeFfi implements LumenFfi {
  final List<String> calls = [];

  /// Calls that went through the knowledge-base entry point. Kept apart from
  /// [calls] so a test can prove they did not reach the vault dispatcher.
  final List<String> kbCalls = [];

  @override
  bool get ready => true;

  @override
  String? get initError => null;

  @override
  void init() {}

  @override
  Object? core(String method, [Map<String, Object?> args = const {}]) {
    calls.add(method);
    return <String, Object?>{'unlocked': true, 'text': 'body'};
  }

  @override
  Object? plugins(String method, [Map<String, Object?> args = const {}]) {
    calls.add(method);
    if (method == 'plugins.list') {
      return <String, Object?>{
        'builtin': const [],
        'external': const [],
        'dir': '',
      };
    }
    return <String, Object?>{'feedback': const ['ok']};
  }

  @override
  Object? kb(String method, [Map<String, Object?> args = const {}]) {
    kbCalls.add(method);
    if (method == 'kb.sync.status') {
      return <String, Object?>{
        'enabled': true,
        'method': 'syncthing',
        'last_sync': null,
        'pending_changes': 0,
        'conflicts': const [],
        'device_status': const [],
      };
    }
    if (method == 'kb.sync.conflicts') {
      return <String, Object?>{'conflicts': const []};
    }
    if (method == 'kb.sync.generate_syncthing_config') {
      return <String, Object?>{'config': '<folder/>'};
    }
    return <String, Object?>{};
  }
}

void main() {
  test('vault mutations resolve as futures', () async {
    final ffi = FakeFfi();
    final vault = VaultService(ffi);

    await vault.create('/tmp/journal', 'passphrase');
    await vault.unlock('/tmp/journal', 'passphrase');
    await vault.writeText('note.md', 'body');
    await vault.delete('note.md');
    await vault.lock();

    expect(ffi.calls, [
      'vault.create',
      'vault.unlock',
      'vault.write_text',
      'vault.delete',
      'vault.lock',
    ]);
  });

  test('plugin mutations resolve as futures', () async {
    final ffi = FakeFfi();
    final plugins = PluginService(ffi);

    await plugins.setEnabled('wordcount', false);
    expect(await plugins.run('note.md', 'Note', 'body'), ['ok']);
    expect(ffi.calls, ['plugins.set_enabled', 'plugins.run']);
  });

  test('sync calls go through the knowledge base entry point', () async {
    final ffi = FakeFfi();
    final sync = SyncService(ffi);

    await sync.init('/tmp/journal');
    final status = await sync.status();
    expect(status.enabled, isTrue);
    expect(status.method, SyncMethod.syncthing);
    expect(await sync.conflicts(), isEmpty);
    expect(await sync.generateSyncthingConfig('/tmp/journal'), '<folder/>');

    // The vault dispatcher does not know these methods, so they must not
    // reach it.
    expect(ffi.calls, isEmpty);
    expect(ffi.kbCalls, [
      'kb.sync.init',
      'kb.sync.status',
      'kb.sync.conflicts',
      'kb.sync.generate_syncthing_config',
    ]);
  });
}
