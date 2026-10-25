import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ffi/lumen_ffi.dart';
import '../ffi/plugin_service.dart';
import '../ffi/vault_service.dart';
import '../journal/quotes.dart';

/// A sidebar destination contributed by an enabled plugin.
@immutable
class PluginSidebarPin {
  const PluginSidebarPin({
    required this.id,
    required this.pluginId,
    required this.label,
    this.icon = 'pin',
    this.action = 'plugin',
    this.priority = 0,
  });

  final String id;
  final String pluginId;
  final String label;
  final String icon;
  final String action;
  final int priority;
}

@immutable
class PluginDashboardCard {
  const PluginDashboardCard({
    required this.id,
    required this.pluginId,
    required this.title,
    this.subtitle,
    this.icon = 'dashboardCard',
    this.priority = 0,
  });

  final String id;
  final String pluginId;
  final String title;
  final String? subtitle;
  final String icon;
  final int priority;
}

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
  const AppSettings({
    this.themeSource = ThemeSource.system,
    this.journalVaultPath,
    this.activeThemePluginId,
  });
  final ThemeSource themeSource;

  /// Folder holding the encrypted journal (`.lumen/journal.json`).
  final String? journalVaultPath;

  /// Enabled plugin theme id to apply, or `null` for the default Lumen theme.
  final String? activeThemePluginId;

  AppSettings copyWith({
    ThemeSource? themeSource,
    String? journalVaultPath,
    String? activeThemePluginId,
    bool clearActiveThemePluginId = false,
  }) =>
      AppSettings(
        themeSource: themeSource ?? this.themeSource,
        journalVaultPath: journalVaultPath ?? this.journalVaultPath,
        activeThemePluginId: clearActiveThemePluginId
            ? null
            : (activeThemePluginId ?? this.activeThemePluginId),
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
      activeThemePluginId: prefs.getString('activeThemePluginId'),
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

  void setActiveThemePluginId(String? id) {
    if (id == null || id.isEmpty) {
      state = state.copyWith(clearActiveThemePluginId: true);
      _prefs?.remove('activeThemePluginId');
    } else {
      state = state.copyWith(activeThemePluginId: id);
      _prefs?.setString('activeThemePluginId', id);
    }
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

// ---------------------------------------------------------------------------
// Dashboard cards — order, visibility, and quote source (persisted in prefs).
// ---------------------------------------------------------------------------

/// A rearrangeable card on the journal dashboard.
enum DashboardCard {graph, dayNight, quote}

extension DashboardCardInfo on DashboardCard {
  String get id => name;

  String get label => switch (this) {
    DashboardCard.graph => 'Writing activity',
    DashboardCard.dayNight => 'Plan & reflect',
    DashboardCard.quote => 'Quote of the day',
  };

  IconData get icon => switch (this) {
    DashboardCard.graph => Icons.grid_view_outlined,
    DashboardCard.dayNight => Icons.wb_twilight,
    DashboardCard.quote => Icons.format_quote_outlined,
  };

  static DashboardCard? fromId(String id) {
    for (final c in DashboardCard.values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

const _defaultCardOrder = DashboardCard.values;

class DashboardPrefs {
  const DashboardPrefs({
    this.order = _defaultCardOrder,
    this.hidden = const {},
    this.quoteSource = QuoteSource.zenquotes,
    this.quoteApiKey = '',
    this.quoteCustomUrl = '',
  });

  final List<DashboardCard> order;
  final Set<DashboardCard> hidden;
  final QuoteSource quoteSource;

  /// Key for sources that need one (API Ninjas, optionally custom).
  final String quoteApiKey;

  /// Endpoint used when [quoteSource] is [QuoteSource.custom].
  final String quoteCustomUrl;

  List<DashboardCard> get visibleOrder =>
      [for (final c in order) if (!hidden.contains(c)) c];

  bool isVisible(DashboardCard card) => !hidden.contains(card);

  DashboardPrefs copyWith({
    List<DashboardCard>? order,
    Set<DashboardCard>? hidden,
    QuoteSource? quoteSource,
    String? quoteApiKey,
    String? quoteCustomUrl,
  }) => DashboardPrefs(
    order: order ?? this.order,
    hidden: hidden ?? this.hidden,
    quoteSource: quoteSource ?? this.quoteSource,
    quoteApiKey: quoteApiKey ?? this.quoteApiKey,
    quoteCustomUrl: quoteCustomUrl ?? this.quoteCustomUrl,
  );
}

class DashboardPrefsNotifier extends Notifier<DashboardPrefs> {
  DashboardPrefsNotifier([SharedPreferences? prefs]) : _prefs = prefs;

  final SharedPreferences? _prefs;

  static const _orderKey = 'dashboard.cardOrder';
  static const _hiddenKey = 'dashboard.hiddenCards';
  static const _quoteSourceKey = 'dashboard.quoteSource';
  static const _quoteApiKeyKey = 'dashboard.quoteApiKey';
  static const _quoteCustomUrlKey = 'dashboard.quoteCustomUrl';

  @override
  DashboardPrefs build() {
    final prefs = _prefs;
    if (prefs == null) return const DashboardPrefs();

    final savedOrder = prefs.getStringList(_orderKey) ?? const [];
    final order = <DashboardCard>[
      for (final id in savedOrder)
        ?DashboardCardInfo.fromId(id),
    ];
    // Append any cards added since the order was last saved.
    for (final c in DashboardCard.values) {
      if (!order.contains(c)) order.add(c);
    }

    final hidden = <DashboardCard>{
      for (final id in prefs.getStringList(_hiddenKey) ?? const [])
        ?DashboardCardInfo.fromId(id),
    };

    final sourceIndex = prefs.getInt(_quoteSourceKey) ?? 0;
    final stored =
        QuoteSource.values[sourceIndex.clamp(
          0,
          QuoteSource.values.length - 1,
        )];
    return DashboardPrefs(
      order: order,
      hidden: hidden,
      // Never restore a source the Settings UI cannot offer (an old build may
      // have persisted apiNinjas/custom).
      quoteSource: selectableQuoteSources.contains(stored)
          ? stored
          : QuoteSource.offline,
      quoteApiKey: prefs.getString(_quoteApiKeyKey) ?? '',
      quoteCustomUrl: prefs.getString(_quoteCustomUrlKey) ?? '',
    );
  }

  /// Moves a visible card to a new index. Indices are already adjusted for the
  /// removal by [ReorderableListView.onReorderItem] and the up/down buttons.
  void reorder(int oldIndex, int newIndex) => reorderMove(oldIndex, newIndex);

  void moveBy(DashboardCard card, int delta) {
    final visible = state.visibleOrder;
    final from = visible.indexOf(card);
    if (from < 0) return;
    final to = (from + delta).clamp(0, visible.length - 1);
    if (to == from) return;
    reorderMove(from, to);
  }

  /// Direct move used by the up/down buttons (no index adjustment).
  void reorderMove(int from, int to) {
    final visible = state.visibleOrder;
    if (from < 0 || from >= visible.length || to < 0 || to >= visible.length) {
      return;
    }
    final moved = visible.removeAt(from);
    visible.insert(to, moved);
    final hidden = [for (final c in state.order) if (state.hidden.contains(c)) c];
    _setOrder([...visible, ...hidden]);
  }

  void setVisible(DashboardCard card, bool visible) {
    final hidden = {...state.hidden};
    if (visible) {
      hidden.remove(card);
    } else {
      hidden.add(card);
    }
    state = state.copyWith(hidden: hidden);
    _prefs?.setStringList(_hiddenKey, [for (final c in hidden) c.id]);
  }

  void setQuoteSource(QuoteSource source) {
    state = state.copyWith(quoteSource: source);
    _prefs?.setInt(_quoteSourceKey, source.index);
  }

  void setQuoteApiKey(String key) {
    state = state.copyWith(quoteApiKey: key);
    _prefs?.setString(_quoteApiKeyKey, key);
  }

  void setQuoteCustomUrl(String url) {
    state = state.copyWith(quoteCustomUrl: url);
    _prefs?.setString(_quoteCustomUrlKey, url);
  }

  void resetLayout() {
    state = DashboardPrefs(
      quoteSource: state.quoteSource,
      quoteApiKey: state.quoteApiKey,
      quoteCustomUrl: state.quoteCustomUrl,
    );
    _prefs?.remove(_orderKey);
    _prefs?.remove(_hiddenKey);
  }

  void _setOrder(List<DashboardCard> order) {
    state = state.copyWith(order: order);
    _prefs?.setStringList(_orderKey, [for (final c in order) c.id]);
  }
}

final dashboardPrefsProvider =
    NotifierProvider<DashboardPrefsNotifier, DashboardPrefs>(
      DashboardPrefsNotifier.new,
    );

final pluginSidebarPinsProvider = Provider<List<PluginSidebarPin>>((ref) {
  try {
    final plugins = ref.watch(pluginsProvider);
    final pins = plugins.maybeWhen(
      data: (list) {
        final result = <PluginSidebarPin>[];
        for (final plugin in list.all) {
          if (!plugin.enabled) continue;
          final contributions = plugin.contributions['sidebar'];
          if (contributions is! List) continue;
          for (final raw in contributions) {
            if (raw is! Map) continue;
            final map = raw.cast<String, dynamic>();
            result.add(
              PluginSidebarPin(
                id: map['id']?.toString() ?? '${plugin.id}.${result.length}',
                pluginId: plugin.id,
                label: map['label']?.toString() ?? plugin.name,
                icon: map['icon']?.toString() ?? 'pin',
                action: map['action']?.toString() ?? 'plugin',
                priority: (map['priority'] as num?)?.toInt() ?? plugin.priority,
              ),
            );
          }
        }
        result.sort((a, b) => b.priority.compareTo(a.priority));
        return result;
      },
      orElse: () => const <PluginSidebarPin>[],
    );
    return pins;
  } catch (_) {
    return const <PluginSidebarPin>[];
  }
});

final pluginDashboardCardsProvider = Provider<List<PluginDashboardCard>>((ref) {
  try {
    final plugins = ref.watch(pluginsProvider);
    final cards = plugins.maybeWhen(
      data: (list) {
        final result = <PluginDashboardCard>[];
        for (final plugin in list.all) {
          if (!plugin.enabled) continue;
          final contributions = plugin.contributions['dashboardCards'];
          if (contributions is! List) continue;
          for (final raw in contributions) {
            if (raw is! Map) continue;
            final map = raw.cast<String, dynamic>();
            result.add(
              PluginDashboardCard(
                id: map['id']?.toString() ?? '${plugin.id}.card.${result.length}',
                pluginId: plugin.id,
                title: map['title']?.toString() ?? plugin.name,
                subtitle: map['subtitle']?.toString(),
                icon: map['icon']?.toString() ?? 'dashboardCard',
                priority: (map['priority'] as num?)?.toInt() ?? plugin.priority,
              ),
            );
          }
        }
        result.sort((a, b) => b.priority.compareTo(a.priority));
        return result;
      },
      orElse: () => const <PluginDashboardCard>[],
    );
    return cards;
  } catch (_) {
    return const <PluginDashboardCard>[];
  }
});
