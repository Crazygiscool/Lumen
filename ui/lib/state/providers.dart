import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ffi/fs_service.dart';
import '../ffi/lumen_ffi.dart';
import '../ffi/plugin_service.dart';
import '../ffi/tank_service.dart';
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

/// Targets the separate encrypted journal store (may share a folder with the
/// vault knowledge base, but keeps its own passphrase/keys).
final journalVaultServiceProvider = Provider<VaultService>((ref) {
  return VaultService(ref.watch(lumenFfiProvider), store: 'journal');
});

// ---------------------------------------------------------------------------
// Vault (knowledge base) + journal stores
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

/// Unlock state for one encrypted store (`vault` = knowledge base,
/// `journal` = journal). Each store is unlocked independently with its own
/// passphrase via the store-aware [VaultService].
class VaultNotifier extends Notifier<VaultUiState> {
  VaultNotifier([this._store = 'vault']);

  final String _store;

  VaultService get _service => ref.read(
    _store == 'journal' ? journalVaultServiceProvider : vaultServiceProvider,
  );

  @override
  VaultUiState build() => const VaultUiState(unlocked: false);

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

/// Knowledge-base vault store.
final vaultProvider = NotifierProvider<VaultNotifier, VaultUiState>(
  VaultNotifier.new,
);

/// Journal store (independent passphrase/keys; may share the vault folder).
final journalVaultProvider =
    NotifierProvider<VaultNotifier, VaultUiState>(
      () => VaultNotifier('journal'),
    );

// ---------------------------------------------------------------------------
// Tank — encrypted off-site store for encrypt-any-file.
// ---------------------------------------------------------------------------

final tankServiceProvider = Provider<TankService>(
  (ref) => TankService(ref.watch(lumenFfiProvider)),
);

class TankNotifier extends Notifier<TankStatus> {
  @override
  TankStatus build() => const TankStatus(setup: false, unlocked: false);

  /// Restores the configured tank location (if any) from settings without
  /// needing the passphrase; keeps the session locked state as-is.
  Future<void> init() async {
    final path = ref.read(settingsProvider).tankPath;
    if (path == null || path.isEmpty) return;
    try {
      await ref.read(tankServiceProvider).setPath(path);
      await refresh();
    } catch (_) {
      // Not set up yet, or folder moved — leave state untouched.
    }
  }

  Future<void> refresh() async {
    state = await ref.read(tankServiceProvider).status();
  }

  /// Points the tank at [path] without persisting it or touching keys.
  /// Setup/unlock persist the chosen folder.
  Future<void> setPath(String path) async {
    await ref.read(tankServiceProvider).setPath(path);
    await refresh();
  }

  Future<void> setup(String path, String passphrase) async {
    await ref.read(tankServiceProvider).setup(path, passphrase);
    ref.read(settingsProvider.notifier).setTankPath(path);
    await refresh();
  }

  Future<void> unlock(String path, String passphrase) async {
    await ref.read(tankServiceProvider).unlock(path, passphrase);
    ref.read(settingsProvider.notifier).setTankPath(path);
    await refresh();
  }

  Future<void> lock() async {
    await ref.read(tankServiceProvider).lock();
    await refresh();
  }
}

final tankProvider = NotifierProvider<TankNotifier, TankStatus>(
  TankNotifier.new,
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
      late PluginList list;
      list = await service.list();
      var dirty = false;
      for (final p in list.all) {
        final saved = _prefs?.getBool(_key(p.name));
        if (saved != null && saved != p.enabled) {
          await service.setEnabled(p.name, saved);
          dirty = true;
        }
      }
      // set_enabled flips the core-side flag; refetch so the UI matches the
      // persisted choice.
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
// Lumen pages (tab destinations)
// ---------------------------------------------------------------------------

enum LumenSection {
  home,
  files,
  vault,
  graph,
  osLab,
  console,
  projects,
  github,
  settings,
  welcome,
  plugins,
}

/// The optional feature that gates [LumenSection], or null for always-on core
/// sections. When a feature is disabled its section is hidden everywhere.
extension LumenSectionFeature on LumenSection {
  LumenFeature? get feature => switch (this) {
    LumenSection.projects => LumenFeature.projects,
    LumenSection.github => LumenFeature.github,
    _ => null,
  };
}

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
    this.vaultPath,
    this.journalVaultPath,
    this.tankPath,
    this.githubToken,
    this.githubLogin,
    this.wakaApiKey,
  });
  final ThemeSource themeSource;
  final bool matchGtkAccent;
  final String? startPath;

  /// Persisted paths for the two encrypted stores. The knowledge base *is*
  /// the vault; the journal may live in the same folder.
  final String? vaultPath;
  final String? journalVaultPath;

  /// Location of the "tank": the third encrypted store that holds uniform
  /// ciphertext blobs for encrypt-any-file.
  final String? tankPath;

  /// Personal access tokens (stored locally, plaintext with the prefs).
  final String? githubToken;
  final String? githubLogin;
  final String? wakaApiKey;

  AppSettings copyWith({
    ThemeSource? themeSource,
    bool? matchGtkAccent,
    String? startPath,
    String? vaultPath,
    String? journalVaultPath,
    String? tankPath,
    String? githubToken,
    String? githubLogin,
    String? wakaApiKey,
  }) => AppSettings(
    themeSource: themeSource ?? this.themeSource,
    matchGtkAccent: matchGtkAccent ?? this.matchGtkAccent,
    startPath: startPath ?? this.startPath,
    vaultPath: vaultPath ?? this.vaultPath,
    journalVaultPath: journalVaultPath ?? this.journalVaultPath,
    tankPath: tankPath ?? this.tankPath,
    githubToken: githubToken ?? this.githubToken,
    githubLogin: githubLogin ?? this.githubLogin,
    wakaApiKey: wakaApiKey ?? this.wakaApiKey,
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
      startPath: prefs.getString('startPath'),
      vaultPath: prefs.getString('vaultPath') ?? prefs.getString('kbVaultPath'),
      journalVaultPath: prefs.getString('journalVaultPath'),
      tankPath: prefs.getString('tankPath'),
      githubToken: prefs.getString('githubToken'),
      githubLogin: prefs.getString('githubLogin'),
      wakaApiKey: prefs.getString('wakaApiKey'),
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

  void setVaultPath(String path) {
    state = state.copyWith(vaultPath: path);
    _prefs?.setString('vaultPath', path);
    _prefs?.remove('kbVaultPath');
  }

  void setJournalVaultPath(String path) {
    state = state.copyWith(journalVaultPath: path);
    _prefs?.setString('journalVaultPath', path);
  }

  void setTankPath(String path) {
    state = state.copyWith(tankPath: path);
    _prefs?.setString('tankPath', path);
  }

  void setGithubToken(String? value) {
    state = state.copyWith(githubToken: value);
    if (value == null) {
      _prefs?.remove('githubToken');
    } else {
      _prefs?.setString('githubToken', value);
    }
  }

  void setGithubLogin(String? value) {
    state = state.copyWith(githubLogin: value);
    if (value == null) {
      _prefs?.remove('githubLogin');
    } else {
      _prefs?.setString('githubLogin', value);
    }
  }

  void setWakaApiKey(String? value) {
    state = state.copyWith(wakaApiKey: value);
    if (value == null) {
      _prefs?.remove('wakaApiKey');
    } else {
      _prefs?.setString('wakaApiKey', value);
    }
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

// ---------------------------------------------------------------------------
// Onboarding (first-run getting-started wizard)
// ---------------------------------------------------------------------------

class OnboardingState {
  const OnboardingState({required this.done, this.goals = const []});
  final bool done;
  final List<Goal> goals;
}

@immutable
class Goal {
  const Goal({required this.text, this.id});
  final String text;
  final String? id;
}

class OnboardingNotifier extends Notifier<OnboardingState> {
  OnboardingNotifier([SharedPreferences? prefs]) : _prefs = prefs;

  final SharedPreferences? _prefs;

  @override
  OnboardingState build() {
    final prefs = _prefs;
    return OnboardingState(
      done: prefs?.getBool('onboardingDone') ?? false,
      goals: prefs == null ? const [] : _loadGoals(prefs),
    );
  }

  List<Goal> _loadGoals(SharedPreferences prefs) {
    final raw = prefs.getStringList('goals') ?? const [];
    return [
      for (final s in raw) Goal(text: s),
    ];
  }

  void _saveGoals(List<Goal> goals) {
    _prefs?.setStringList('goals', [for (final g in goals) g.text]);
  }

  void complete({List<Goal> goals = const []}) {
    final merged = [...state.goals, ...goals];
    state = OnboardingState(done: true, goals: merged);
    _prefs?.setBool('onboardingDone', true);
    _saveGoals(merged);
  }

  void skip() {
    state = OnboardingState(done: true, goals: state.goals);
    _prefs?.setBool('onboardingDone', true);
  }

  void restart() {
    state = OnboardingState(done: false, goals: state.goals);
    _prefs?.setBool('onboardingDone', false);
  }

  void addGoal(String text) {
    if (text.trim().isEmpty) return;
    final goals = [...state.goals, Goal(text: text.trim())];
    state = OnboardingState(done: state.done, goals: goals);
    _saveGoals(goals);
  }

  void removeGoal(String text) {
    final goals = [for (final g in state.goals) if (g.text != text) g];
    state = OnboardingState(done: state.done, goals: goals);
    _saveGoals(goals);
  }
}

final onboardingProvider = NotifierProvider<OnboardingNotifier, OnboardingState>(
  OnboardingNotifier.new,
);

// ---------------------------------------------------------------------------
// Feature registry — optional capabilities that can be toggled off (plugin
// model). Sections/cards gated by these are hidden when disabled, and their
// data is left untouched.
// ---------------------------------------------------------------------------

enum LumenFeature { projects, github, wakatime }

extension LumenFeatureInfo on LumenFeature {
  String get title => switch (this) {
    LumenFeature.projects => 'Projects',
    LumenFeature.github => 'GitHub',
    LumenFeature.wakatime => 'WakaTime',
  };

  String get description => switch (this) {
    LumenFeature.projects => 'Project manager with tasks, kanban board and gantt view.',
    LumenFeature.github => 'GitHub workflow: link projects, issues and pull requests.',
    LumenFeature.wakatime => 'Personal coding stats from WakaTime on the Home dashboard.',
  };

  String get key => switch (this) {
    LumenFeature.projects => 'featureProjects',
    LumenFeature.github => 'featureGithub',
    LumenFeature.wakatime => 'featureWakatime',
  };
}

class FeaturesState {
  const FeaturesState({
    this.projects = true,
    this.github = true,
    this.wakatime = true,
  });

  final bool projects;
  final bool github;
  final bool wakatime;

  bool enabled(LumenFeature feature) => switch (feature) {
    LumenFeature.projects => projects,
    LumenFeature.github => github,
    LumenFeature.wakatime => wakatime,
  };

  FeaturesState copyWith({bool? projects, bool? github, bool? wakatime}) =>
      FeaturesState(
        projects: projects ?? this.projects,
        github: github ?? this.github,
        wakatime: wakatime ?? this.wakatime,
      );
}

class FeaturesNotifier extends Notifier<FeaturesState> {
  FeaturesNotifier([SharedPreferences? prefs]) : _prefs = prefs;

  final SharedPreferences? _prefs;

  @override
  FeaturesState build() {
    final prefs = _prefs;
    if (prefs == null) return const FeaturesState();
    return FeaturesState(
      projects: prefs.getBool(LumenFeature.projects.key) ?? true,
      github: prefs.getBool(LumenFeature.github.key) ?? true,
      wakatime: prefs.getBool(LumenFeature.wakatime.key) ?? true,
    );
  }

  void set(LumenFeature feature, bool value) {
    state = switch (feature) {
      LumenFeature.projects => state.copyWith(projects: value),
      LumenFeature.github => state.copyWith(github: value),
      LumenFeature.wakatime => state.copyWith(wakatime: value),
    };
    _prefs?.setBool(feature.key, value);
  }
}

final featuresProvider = NotifierProvider<FeaturesNotifier, FeaturesState>(
  FeaturesNotifier.new,
);
