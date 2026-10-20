import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ffi/lumen_ffi.dart';
import 'package:lumen/ffi/plugin_service.dart';
import 'package:lumen/ffi/vault_service.dart';

/// A synchronous fake for the native bridge. The real bridge returns plain
/// values, so service methods must wrap them in futures themselves.
class FakeFfi implements LumenFfi {
  final List<String> calls = [];

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
}
