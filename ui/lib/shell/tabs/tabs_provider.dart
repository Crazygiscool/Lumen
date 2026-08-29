import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../state/providers.dart';
import '../web/web_controller.dart';
import '../web/web_controllers.dart';
import 'tab_model.dart';

@immutable
class TabsState {
  const TabsState({required this.tabs, this.activeId});

  final List<LumenTab> tabs;
  final String? activeId;

  LumenTab? get active {
    for (final t in tabs) {
      if (t.id == activeId) return t;
    }
    return tabs.isEmpty ? null : tabs.last;
  }

  int get activeIndex {
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i].id == activeId) return i;
    }
    return tabs.length - 1;
  }

  LumenTab? tabById(String id) {
    for (final t in tabs) {
      if (t.id == id) return t;
    }
    return null;
  }
}

class TabsNotifier extends Notifier<TabsState> {
  TabsNotifier([SharedPreferences? prefs]) : _prefs = prefs;

  final SharedPreferences? _prefs;
  int _seq = 0;

  @override
  TabsState build() {
    final prefs = _prefs;
    if (prefs != null) {
      final urls = prefs.getStringList('tabs') ?? const [];
      final tabs = [for (final u in urls) _tabForUrl(u)];
      if (tabs.isNotEmpty) {
        final idx = (prefs.getInt('tabActive') ?? 0).clamp(0, tabs.length - 1);
        return TabsState(tabs: tabs, activeId: tabs[idx].id);
      }
    }
    final t = _tabForSpec(newTabSpec);
    return TabsState(tabs: [t], activeId: t.id);
  }

  LumenTab _tabForUrl(String url) =>
      LumenTab(id: _newId(), spec: resolveInput(url));

  LumenTab _tabForSpec(TabSpec spec) => LumenTab(id: _newId(), spec: spec);

  String _newId() => 't${_seq++}_${DateTime.now().microsecondsSinceEpoch}';

  /// Opens a new tab. Returns the new tab id.
  String newTab({String? input, bool activate = true}) {
    final spec = resolveInput(input ?? '', homePath: _homePath());
    final tab = _tabForSpec(spec);
    state = TabsState(
      tabs: [...state.tabs, tab],
      activeId: activate ? tab.id : state.activeId,
    );
    _dispatch(tab);
    _persist();
    return tab.id;
  }

  void activate(String id) {
    if (state.activeId == id) return;
    state = TabsState(tabs: state.tabs, activeId: id);
  }

  /// Focuses an existing tab for [page], or opens a fresh one.
  String activatePage(LumenSection page) {
    for (final t in state.tabs) {
      if (t.kind == TabKind.lumen && t.page == page) {
        state = TabsState(tabs: state.tabs, activeId: t.id);
        return t.id;
      }
    }
    return newTab(input: 'lumen://${page.pathName}');
  }

  void closeTab(String id) {
    final i = state.tabs.indexWhere((t) => t.id == id);
    if (i < 0) return;

    ref.invalidate(fileExplorerProvider(id));
    ref.invalidate(vaultNavProvider(id));

    if (state.tabs.length <= 1) {
      final t = _tabForSpec(newTabSpec);
      state = TabsState(tabs: [t], activeId: t.id);
      _persist();
      return;
    }

    final tabs = [...state.tabs];
    tabs.removeAt(i);
    var activeId = state.activeId;
    if (activeId == id) {
      activeId = tabs[i < tabs.length ? i : i - 1].id;
    }
    state = TabsState(tabs: tabs, activeId: activeId);
    _persist();
  }

  /// Navigates the [tabId] tab (defaults to the active one) to [input].
  String navigate(String input, {String? tabId}) {
    final target = tabId ?? state.activeId;
    final i = state.tabs.indexWhere((t) => t.id == target);
    if (i < 0 || target == null) {
      return newTab(input: input);
    }
    final spec = resolveInput(input, homePath: _homePath());
    final tabs = [...state.tabs];
    tabs[i] = tabs[i].navigate(spec);
    state = TabsState(tabs: tabs, activeId: state.activeId);
    _dispatch(tabs[i]);
    if (spec.kind == TabKind.web) {
      final web = WebControllers.instance[tabs[i].id];
      if (web != null) {
        unawaited(web.loadUrl(spec.url));
      }
    }
    _persist();
    return tabs[i].id;
  }

  /// Live sync from an embedded webview (url/title) for [tabId].
  void syncWeb(String tabId, {String? url, String? title}) {
    final i = state.tabs.indexWhere((t) => t.id == tabId);
    if (i < 0) return;
    final updated = state.tabs[i].syncWeb(url: url, title: title);
    if (identical(updated.spec.url, state.tabs[i].spec.url) &&
        identical(updated.spec.title, state.tabs[i].spec.title)) {
      return;
    }
    final tabs = [...state.tabs];
    tabs[i] = updated;
    state = TabsState(tabs: tabs, activeId: state.activeId);
    _persist();
  }

  /// The embedded webview (if any) for [tabId]'s tab.
  LumenWebViewController? _web(String? tabId) {
    if (tabId == null) return null;
    final tab = state.tabById(tabId);
    if (tab == null || tab.kind != TabKind.web) return null;
    return WebControllers.instance[tabId];
  }

  bool back() => _step(-1);

  bool forward() => _step(1);

  bool _step(int delta) {
    final id = state.activeId;
    final web = _web(id);
    if (web != null) {
      // The WebView owns its own history.
      if (delta < 0) {
        unawaited(web.goBack());
      } else {
        unawaited(web.goForward());
      }
      return true;
    }
    final i = state.tabs.indexWhere((t) => t.id == id);
    if (i < 0) return false;
    final before = state.tabs[i];
    final after = delta < 0 ? before.goBack() : before.goForward();
    if (after.historyIndex == before.historyIndex) return false;
    final tabs = [...state.tabs];
    tabs[i] = after;
    state = TabsState(tabs: tabs, activeId: state.activeId);
    _persist();
    return true;
  }

  void reload() {
    final id = state.activeId;
    final web = _web(id);
    if (web != null) {
      unawaited(web.reload());
      return;
    }
    final tab = state.tabById(id ?? '');
    if (tab == null) return;
    _dispatch(tab, reload: true);
  }

  void _dispatch(LumenTab tab, {bool reload = false}) {
    if (tab.kind != TabKind.lumen) return;
    final path = tab.path;
    if (tab.page == LumenSection.files) {
      unawaited(_dispatchFiles(tab.id, path, reload));
    } else if (tab.page == LumenSection.vault &&
        path != null &&
        path.isNotEmpty) {
      final n = ref.read(vaultNavProvider(tab.id).notifier);
      if (path.toLowerCase().endsWith('.md')) {
        n.openNote(path);
      } else {
        n.openFolder(path);
      }
    }
  }

  Future<void> _dispatchFiles(String tabId, String? path, bool reload) async {
    final n = ref.read(fileExplorerProvider(tabId).notifier);
    if (path != null && path.isNotEmpty) {
      await n.cd(path);
    } else if (reload) {
      await n.refresh();
    }
  }

  String _homePath() => Platform.environment['HOME'] ?? '/';

  void _persist() => unawaited(_writePrefs());

  Future<void> _writePrefs() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setStringList('tabs', [for (final t in state.tabs) t.url]);
    await prefs.setInt('tabActive', state.activeIndex);
  }
}

final tabsProvider = NotifierProvider<TabsNotifier, TabsState>(
  TabsNotifier.new,
);
