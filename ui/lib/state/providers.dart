import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ffi/fs_service.dart';
import '../ffi/lumen_ffi.dart';
import '../ffi/vault_service.dart';
import '../shell/tabs/tabs_provider.dart';
import '../theme/lumen_colors.dart';

final lumenFfiProvider = Provider<LumenFfi>((ref) {
  final ffi = LumenFfi.instance;
  ffi.init();
  return ffi;
});

final fsServiceProvider = Provider<FsService>((ref) {
  return FsService(ref.watch(lumenFfiProvider));
});

final systemServiceProvider = Provider<SystemService>((ref) {
  return SystemService(ref.watch(lumenFfiProvider));
});

final vaultServiceProvider = Provider<VaultService>((ref) {
  return VaultService(ref.watch(lumenFfiProvider));
});

// ---------------------------------------------------------------------------
// Vault
// ---------------------------------------------------------------------------

class VaultUiState {
  const VaultUiState({required this.unlocked, this.root, this.error});
  final bool unlocked;
  final String? root;
  final String? error;

  VaultUiState copyWith({bool? unlocked, String? root, String? error}) =>
      VaultUiState(
        unlocked: unlocked ?? this.unlocked,
        root: root ?? this.root,
        error: error,
      );
}

class VaultNotifier extends Notifier<VaultUiState> {
  @override
  VaultUiState build() => const VaultUiState(unlocked: false);

  Future<void> create(String path, String passphrase) async {
    final service = ref.read(vaultServiceProvider);
    await service.create(path, passphrase);
    await service.unlock(path, passphrase);
    state = VaultUiState(unlocked: true, root: path);
  }

  Future<void> unlock(String path, String passphrase) async {
    try {
      final service = ref.read(vaultServiceProvider);
      await service.unlock(path, passphrase);
      state = VaultUiState(unlocked: true, root: path, error: null);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> lock() async {
    await ref.read(vaultServiceProvider).lock();
    state = const VaultUiState(unlocked: false);
  }

  Future<bool> recover() async {
    final service = ref.read(vaultServiceProvider);
    final unlocked = await service.isUnlocked();
    if (unlocked) {
      final info = await service.info();
      state = VaultUiState(unlocked: true, root: info['root'] as String?);
    }
    return unlocked;
  }
}

final vaultProvider = NotifierProvider<VaultNotifier, VaultUiState>(
  VaultNotifier.new,
);

// ---------------------------------------------------------------------------
// Lumen pages (tab destinations)
// ---------------------------------------------------------------------------

enum LumenSection { files, vault, graph, osLab, console, settings }

// ---------------------------------------------------------------------------
// Directory (Files view) — one explorer session per tab
// ---------------------------------------------------------------------------

class DirState {
  const DirState({required this.path, required this.entries, this.showHidden});
  final String path;
  final List<FsEntry> entries;
  final bool? showHidden;
}

class DirNotifier extends AsyncNotifier<DirState> {
  DirNotifier(this.tabId);

  final String tabId;

  @override
  Future<DirState> build() {
    final home = Platform.environment['HOME'] ?? '/';
    final start = _startFor(tabId) ?? home;
    return _fetch(start, false);
  }

  /// Starts a files tab at the directory its `lumen://files/…` url points to
  /// (best effort — falls back to HOME for plain files tabs).
  String? _startFor(String tabId) {
    try {
      return ref.read(tabsProvider).tabById(tabId)?.path;
    } catch (_) {
      return null;
    }
  }

  Future<DirState> _fetch(String path, bool showHidden) async {
    final fs = ref.read(fsServiceProvider);
    final entries = await fs.list(path, showHidden: showHidden);
    return DirState(path: path, entries: entries, showHidden: showHidden);
  }

  bool _hidden() => state.value?.showHidden ?? false;

  Future<void> cd(String path) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(path, _hidden()));
  }

  Future<void> toggleHidden() async {
    final current = state.value;
    if (current == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _fetch(current.path, !(current.showHidden ?? false)),
    );
  }

  Future<void> refresh() async {
    final current = state.value;
    if (current == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _fetch(current.path, current.showHidden ?? false),
    );
  }
}

/// File explorer state, isolated per tab (`tabId`).
final fileExplorerProvider =
    AsyncNotifierProvider.family<DirNotifier, DirState, String>(
      DirNotifier.new,
    );

// ---------------------------------------------------------------------------
// Vault explorer position — isolated per tab so each vault tab keeps its own
// selected/editing note. Unlock state itself stays app-wide (vaultProvider).
// ---------------------------------------------------------------------------

class VaultNavState {
  const VaultNavState({this.folder, this.selected, this.editing});
  final String? folder;
  final String? selected;
  final String? editing;
}

class VaultNavNotifier extends Notifier<VaultNavState> {
  VaultNavNotifier(this.tabId);

  final String tabId;

  @override
  VaultNavState build() => const VaultNavState();

  void openNote(String relPath) =>
      state = VaultNavState(selected: relPath, editing: relPath);

  void openFolder(String? folder) => state = VaultNavState(folder: folder);

  void select(String? relPath) =>
      state = VaultNavState(folder: state.folder, selected: relPath);

  void closeEditor() =>
      state = VaultNavState(folder: state.folder, selected: state.selected);
}

final vaultNavProvider =
    NotifierProvider.family<VaultNavNotifier, VaultNavState, String>(
      VaultNavNotifier.new,
    );

// ---------------------------------------------------------------------------
// Theme / GTK
// ---------------------------------------------------------------------------

/// How the app picks its theme: follow the desktop (GTK), force dark, or light.
enum ThemeSource { system, dark, light }

/// Snapshot of the host desktop's GTK theme (parsed from `sys.gtk`).
@immutable
class GtkTheme {
  const GtkTheme({
    required this.available,
    this.colorScheme,
    this.themeName,
    this.accentName,
  });

  final bool available;
  final String? colorScheme;
  final String? themeName;
  final String? accentName;

  factory GtkTheme.fromJson(Map<String, dynamic> j) => GtkTheme(
    available: j['available'] as bool? ?? false,
    colorScheme: j['color_scheme'] as String?,
    themeName: j['theme_name'] as String?,
    accentName: j['accent_name'] as String?,
  );
}

/// Detects the host's GTK theme. Falls back to [null] when the native library
/// is missing or the request fails, so the app degrades to default dark.
final gtkThemeProvider = FutureProvider.autoDispose<GtkTheme?>((ref) async {
  try {
    final data = await ref.read(systemServiceProvider).gtk();
    return GtkTheme.fromJson(data);
  } catch (_) {
    return null;
  }
});

/// Resolves the effective [ThemeMode] from user preference + GTK readout.
ThemeMode resolveThemeMode(ThemeSource source, GtkTheme? gtk) {
  switch (source) {
    case ThemeSource.system:
      return gtkSchemeToMode(gtk?.colorScheme) ?? ThemeMode.dark;
    case ThemeSource.dark:
      return ThemeMode.dark;
    case ThemeSource.light:
      return ThemeMode.light;
  }
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class AppSettings {
  const AppSettings({
    this.themeSource = ThemeSource.system,
    this.matchGtkAccent = true,
    this.startPath,
  });
  final ThemeSource themeSource;
  final bool matchGtkAccent;
  final String? startPath;

  AppSettings copyWith({
    ThemeSource? themeSource,
    bool? matchGtkAccent,
    String? startPath,
  }) => AppSettings(
    themeSource: themeSource ?? this.themeSource,
    matchGtkAccent: matchGtkAccent ?? this.matchGtkAccent,
    startPath: startPath ?? this.startPath,
  );
}

class SettingsNotifier extends Notifier<AppSettings> {
  SettingsNotifier([SharedPreferences? prefs]) : _prefs = prefs;

  final SharedPreferences? _prefs;

  @override
  AppSettings build() {
    final prefs = _prefs;
    if (prefs == null) return const AppSettings();
    return AppSettings(
      themeSource:
          ThemeSource.values[(prefs.getInt('themeSource') ?? 0).clamp(
            0,
            ThemeSource.values.length - 1,
          )],
      matchGtkAccent: prefs.getBool('matchGtkAccent') ?? true,
    );
  }

  void setThemeSource(ThemeSource source) {
    state = state.copyWith(themeSource: source);
    _prefs?.setInt('themeSource', source.index);
  }

  void setMatchGtkAccent(bool value) {
    state = state.copyWith(matchGtkAccent: value);
    _prefs?.setBool('matchGtkAccent', value);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
