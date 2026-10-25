import 'package:flutter/material.dart';

import '../ffi/plugin_service.dart';

/// Semantic icon catalog. UI code should reference [AppIcons] and resolve
/// through here rather than hard-coding `Icons.*`, which lets plugins replace
/// icon variants via contribution maps.
class AppIcons {
  AppIcons._();

  static final Map<String, IconData> _builtin = <String, IconData>{
    'add': Icons.add,
    'close': Icons.close,
    'delete': Icons.delete_outline,
    'edit': Icons.edit_outlined,
    'eye': Icons.visibility_outlined,
    'image': Icons.image_outlined,
    'lock': Icons.lock_outline,
    'unlock': Icons.lock_open,
    'save': Icons.save_outlined,
    'search': Icons.search,
    'settings': Icons.settings,
    'plugin': Icons.extension_outlined,
    'import': Icons.file_download_outlined,
    'journal': Icons.article_outlined,
    'dashboard': Icons.dashboard_outlined,
    'refresh': Icons.refresh,
    'attach': Icons.image_outlined,
    'folder': Icons.folder_open,
    'chevronRight': Icons.chevron_right,
    'pin': Icons.push_pin_outlined,
    'dashboardCard': Icons.dashboard_customize_outlined,
  };

  static Map<String, String> _activePack = const <String, String>{};

  static void setActivePack(Map<String, dynamic>? contributions) {
    final icons = contributions?['icons'];
    if (icons is Map) {
      _activePack = icons.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } else {
      _activePack = const <String, String>{};
    }
  }

  static IconData resolve(String name) {
    final override = _activePack[name];
    if (override != null && _builtin.containsKey(override)) {
      return _builtin[override]!;
    }
    // External code-point overrides are not supported by the const
    // IconData constructor; named icon variants cover the supported cases.
    return _builtin[name] ?? Icons.widgets_outlined;
  }

  static IconData get add => resolve('add');
  static IconData get close => resolve('close');
  static IconData get delete => resolve('delete');
  static IconData get edit => resolve('edit');
  static IconData get eye => resolve('eye');
  static IconData get image => resolve('image');
  static IconData get lock => resolve('lock');
  static IconData get unlock => resolve('unlock');
  static IconData get save => resolve('save');
  static IconData get search => resolve('search');
  static IconData get settings => resolve('settings');
  static IconData get plugin => resolve('plugin');
  static IconData get import => resolve('import');
  static IconData get journal => resolve('journal');
  static IconData get dashboard => resolve('dashboard');
  static IconData get refresh => resolve('refresh');
  static IconData get attach => resolve('attach');
  static IconData get folder => resolve('folder');
  static IconData get chevronRight => resolve('chevronRight');
  static IconData get pin => resolve('pin');
  static IconData get dashboardCard => resolve('dashboardCard');
}

/// Resolves icon contribution packs from enabled plugins.
List<Map<String, dynamic>> resolveIconPacks(List<PluginInfo> plugins) {
  return [
    for (final plugin in plugins)
      if (plugin.enabled && plugin.contributions['icons'] is Map)
        plugin.contributions['icons'] as Map<String, dynamic>,
  ];
}