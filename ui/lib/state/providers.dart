import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ffi/lumen_ffi.dart';
import '../ffi/plugin_service.dart';
import '../ffi/vault_service.dart';

final lumenFfiProvider = Provider<LumenFfi>((ref) {
  final ffi = LumenFfi.instance;
  ffi.init();
  return ffi;
});

/// Targets the encrypted journal store (Markdown notes; its own passphrase).
final journalVaultServiceProvider = Provider<VaultService>((ref) {
  return VaultService(ref.watch(lumenFfiProvider), store: 'journal');
});

// ---------------------------------------------------------------------------
// Journal store unlock state
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

/// Unlock state for the encrypted journal store.
class VaultNotifier extends Notifier<VaultUiState> {
  @override
  VaultUiState build() => const VaultUiState(unlocked: false);

  VaultService get _service => ref.read(journalVaultServiceProvider);

  Future<void> create(String path, String passphrase) async {
    final service = _service;
    await service.create(path, passphrase);
    await service.unlock(path, passphrase);
    state = VaultUiState(unlocked: true, root: path);
  }

  Future<void> unlock(String path, String passphrase) async {
    try {
      final service = _service;
      await service.unlock(path, passphrase);
      state = VaultUiState(unlocked: true, root: path, error: null);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> lock() async {
    await _service.lock();
    state = const VaultUiState(unlocked: false);
  }

  /// Re-attaches to an already-unlocked journal after an app restart.
  Future<bool> recover() async {
    final service = _service;
    final unlocked = await service.isUnlocked();
    if (unlocked) {
      final info = await service.info();
      state = VaultUiState(unlocked: true, root: info['root'] as String?);
    }
    return unlocked;
  }
}

final journalVaultProvider = NotifierProvider<VaultNotifier, VaultUiState>(
  VaultNotifier.new,
);

// ---------------------------------------------------------------------------
// Plugins — inventory + enable/disable (toggles persisted in prefs).
// ---------------------------------------------------------------------------

final pluginServiceProvider = Provider<PluginService>(
  (ref) => PluginService(ref.watch(lumenFfiProvider)),
);

class PluginNotifier extends AsyncNotifier<PluginList> {
  PluginNotifier([this._prefs]);

  final SharedPreferences? _prefs;

  static String _key(String name) => 'pluginEnabled.$name';

  @override
  Future<PluginList> build() async {
    try {
      final service = ref.read(pluginServiceProvider);
      var list = await service.list();
      var dirty = false;
      for (final p in list.all) {
        final saved = _prefs?.getBool(_key(p.name));
        if (saved != null && saved != p.enabled) {
          await service.setEnabled(p.name, saved);
          dirty = true;
        }
      }
      if (dirty) list = await service.list();
      return list;
    } catch (e) {
      throw Exception('Could not read plugins: $e');
    }
  }

  Future<void> toggle(PluginInfo plugin, bool value) async {
    await ref.read(pluginServiceProvider).setEnabled(plugin.name, value);
    _prefs?.setBool(_key(plugin.name), value);
    state = await AsyncValue.guard(ref.read(pluginServiceProvider).list);
  }
}

final pluginsProvider = AsyncNotifierProvider<PluginNotifier, PluginList>(
  PluginNotifier.new,
);

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

enum LumenSection { journal, import, plugins, settings }

extension LumenSectionInfo on LumenSection {
  String get label => switch (this) {
    LumenSection.journal => 'Journal',
    LumenSection.import => 'Import',
    LumenSection.plugins => 'Plugins',
    LumenSection.settings => 'Settings',
  };

  IconData get icon => switch (this) {
    LumenSection.journal => Icons.edit_note,
    LumenSection.import => Icons.file_download_outlined,
    LumenSection.plugins => Icons.extension_outlined,
    LumenSection.settings => Icons.settings_outlined,
  };
}

/// Currently visible section in the simplified shell.
class SectionNotifier extends Notifier<LumenSection> {
  @override
  LumenSection build() => LumenSection.journal;

  void select(LumenSection section) => state = section;
}

final selectedSectionProvider = NotifierProvider<SectionNotifier, LumenSection>(
  SectionNotifier.new,
);

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

/// How the app picks its theme: follow the desktop, force dark, or light.
enum ThemeSource { system, dark, light }

ThemeMode resolveThemeMode(ThemeSource source) => switch (source) {
  ThemeSource.system => ThemeMode.system,
  ThemeSource.dark => ThemeMode.dark,
  ThemeSource.light => ThemeMode.light,
};

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class AppSettings {
  const AppSettings({this.themeSource = ThemeSource.system, this.journalVaultPath});
  final ThemeSource themeSource;

  /// Folder holding the encrypted journal (`.lumen/journal.json`).
  final String? journalVaultPath;

  AppSettings copyWith({ThemeSource? themeSource, String? journalVaultPath}) =>
      AppSettings(
        themeSource: themeSource ?? this.themeSource,
        journalVaultPath: journalVaultPath ?? this.journalVaultPath,
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
      themeSource: ThemeSource.values[(prefs.getInt('themeSource') ?? 0).clamp(
        0,
        ThemeSource.values.length - 1,
      )],
      journalVaultPath: prefs.getString('journalVaultPath'),
    );
  }

  void setThemeSource(ThemeSource source) {
    state = state.copyWith(themeSource: source);
    _prefs?.setInt('themeSource', source.index);
  }

  void setJournalVaultPath(String path) {
    state = state.copyWith(journalVaultPath: path);
    _prefs?.setString('journalVaultPath', path);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
