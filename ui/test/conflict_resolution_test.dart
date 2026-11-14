import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ffi/lumen_ffi.dart';
import 'package:lumen/ffi/sync_service.dart';
import 'package:lumen/sync/conflict_resolution_screen.dart';

/// A native bridge fake that serves the difference between two versions.
class _FakeFfi implements LumenFfi {
  final List<String> methods = [];
  final List<Map<String, Object?>> args = [];

  /// The lines the core sends for the difference.
  List<Map<String, Object?>> lines = const [
    {'kind': 'same', 'text': '# Gamma'},
    {'kind': 'removed', 'text': 'the local line'},
    {'kind': 'added', 'text': 'the remote line'},
  ];

  /// Whether resolving the conflict works.
  bool resolveFails = false;

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
      case 'kb.sync.conflict_diff':
        return <String, Object?>{'lines': lines};
      case 'kb.sync.resolve_conflict':
        if (resolveFails) {
          throw StateError('the conflict could not be resolved');
        }
        return <String, Object?>{'resolved': args['path']};
      default:
        return <String, Object?>{};
    }
  }
}

SyncConflict _conflict() => SyncConflict(
  path: 'gamma.md',
  localModified: DateTime.utc(2026, 2, 3, 12),
  remoteModified: DateTime.utc(2026, 2, 3, 13),
  localHash: 'aaaaaaaabbbb',
  remoteHash: 'ccccccccdddd',
);

void main() {
  testWidgets('the difference between the two versions is shown', (
    tester,
  ) async {
    final ffi = _FakeFfi();

    await tester.pumpWidget(
      MaterialApp(
        home: ConflictResolutionScreen(
          conflict: _conflict(),
          vaultPath: '/vault',
          service: SyncService(ffi),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('# Gamma'), findsOneWidget);
    expect(find.text('the local line'), findsOneWidget);
    expect(find.text('the remote line'), findsOneWidget);

    // The difference is asked of the core, with the note and the vault.
    expect(ffi.methods, ['kb.sync.conflict_diff']);
    expect(ffi.args.first['path'], 'gamma.md');
    expect(ffi.args.first['vault_path'], '/vault');
  });

  testWidgets('keeping the local version resolves the conflict', (
    tester,
  ) async {
    final ffi = _FakeFfi();

    await tester.pumpWidget(
      MaterialApp(
        home: ConflictResolutionScreen(
          conflict: _conflict(),
          vaultPath: '/vault',
          service: SyncService(ffi),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep Local'));
    await tester.pumpAndSettle();

    expect(ffi.methods, contains('kb.sync.resolve_conflict'));
    final resolve = ffi.args.firstWhere(
      (a) => a['path'] == 'gamma.md' && a.containsKey('keep_local'),
    );
    expect(resolve['keep_local'], isTrue);
    // The version the other side sent is kept inside the vault, so the core
    // needs to know where the vault is.
    expect(resolve['vault_path'], '/vault');
  });

  testWidgets('keeping the remote version resolves the conflict', (
    tester,
  ) async {
    final ffi = _FakeFfi();

    await tester.pumpWidget(
      MaterialApp(
        home: ConflictResolutionScreen(
          conflict: _conflict(),
          vaultPath: '/vault',
          service: SyncService(ffi),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep Remote'));
    await tester.pumpAndSettle();

    final resolve = ffi.args.firstWhere(
      (a) => a['path'] == 'gamma.md' && a.containsKey('keep_local'),
    );
    expect(resolve['keep_local'], isFalse);
  });

  testWidgets('a failure to resolve is said so', (tester) async {
    final ffi = _FakeFfi()..resolveFails = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConflictResolutionScreen(
            conflict: _conflict(),
            vaultPath: '/vault',
            service: SyncService(ffi),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep Local'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not resolve'), findsOneWidget);
  });
}
