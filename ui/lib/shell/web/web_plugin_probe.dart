import 'dart:async';

import 'package:flutter/services.dart';

/// Detects whether the native `lumen_webview` plugin is available.
///
/// The plugin, when registered, answers a `ping` on `lumen.webview/probe`
/// and pushes an `onReady` event. If neither arrives the platform view cannot
/// be created and [LumenWebView] falls back to the system-browser experience.
class WebPluginProbe {
  WebPluginProbe._();

  static final MethodChannel _channel = MethodChannel('lumen.webview/probe');
  static bool _ready = false;
  static Future<bool>? _waiting;

  /// Resolves true when the native plugin is responding.
  static Future<bool> ping({Duration timeout = const Duration(seconds: 4)}) {
    if (_ready) return Future.value(true);
    _waiting ??= () async {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onReady') {
          _ready = true;
        }
      });
      try {
        await _channel.invokeMethod('ping').timeout(timeout);
      } catch (_) {
        // Not available — leave _ready false.
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return _ready;
    }();
    return _waiting!;
  }

  static void markReady() => _ready = true;

  /// Realises a native WebView for [id] and loads [url]. Returns the engine
  /// texture id, or null if the plugin is unavailable / creation failed.
  /// The rest of the per-view channel (`lumen.webview/<id>`) only becomes
  /// active once this succeeds, so callers must await before sending anything.
  static Future<int?> createView(String id, String url) async {
    try {
      final int? textureId = await _channel.invokeMethod<int>(
        'createView',
        {'id': id, 'url': url},
      );
      if (textureId != null) _ready = true;
      return textureId;
    } catch (_) {
      return null;
    }
  }
}