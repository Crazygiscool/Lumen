import 'package:flutter/foundation.dart';

import 'lumen_ffi.dart';

/// A discovered plugin (built-in or external) with its manifest metadata.
@immutable
class PluginInfo {
  const PluginInfo({
    required this.name,
    required this.version,
    required this.builtin,
    required this.enabled,
    this.author,
    this.description,
    this.hooks = const [],
  });

  final String name;
  final String version;
  final String? author;
  final String? description;
  final List<String> hooks;
  final bool builtin;
  final bool enabled;

  factory PluginInfo.fromJson(Map<String, dynamic> j) => PluginInfo(
    name: j['name'] as String? ?? '',
    version: j['version'] as String? ?? '',
    author: j['author'] as String?,
    description: j['description'] as String?,
    hooks: [
      for (final h in (j['hooks'] as List<dynamic>? ?? const [])) h as String,
    ],
    builtin: j['builtin'] as bool? ?? false,
    enabled: j['enabled'] as bool? ?? true,
  );

  PluginInfo copyWith({bool? enabled}) => PluginInfo(
    name: name,
    version: version,
    author: author,
    description: description,
    hooks: hooks,
    builtin: builtin,
    enabled: enabled ?? this.enabled,
  );
}

@immutable
class PluginList {
  const PluginList({
    required this.builtin,
    required this.external,
    required this.dir,
  });

  final List<PluginInfo> builtin;
  final List<PluginInfo> external;
  final String dir;

  List<PluginInfo> get all => [...builtin, ...external];

  factory PluginList.fromJson(Map<String, dynamic> j) => PluginList(
    builtin: [
      for (final p in (j['builtin'] as List<dynamic>? ?? const []))
        PluginInfo.fromJson(p as Map<String, dynamic>),
    ],
    external: [
      for (final p in (j['external'] as List<dynamic>? ?? const []))
        PluginInfo.fromJson(p as Map<String, dynamic>),
    ],
    dir: j['dir'] as String? ?? '',
  );
}

/// Lists installed plugins and toggles their enabled state. The inventory is
/// read from the plugin manifest on disk without loading any plugin code.
class PluginService {
  PluginService(this._ffi);

  final LumenFfi _ffi;

  Future<PluginList> list() async =>
      PluginList.fromJson(_ffi.plugins('plugins.list') as Map<String, dynamic>);

  Future<void> setEnabled(String name, bool enabled) =>
      _ffi.plugins('plugins.set_enabled', {'name': name, 'enabled': enabled});
}