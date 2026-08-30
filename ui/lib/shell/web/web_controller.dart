import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'web_controllers.dart';
import 'web_plugin_probe.dart';

/// Controller for a single embedded web tab. Talks to the `lumen_webview`
/// Linux plugin over a per-view [`MethodChannel`] (`lumen.webview/<id>`).
///
/// The Linux embedder renders the webview into an engine texture (the same
/// mechanism `webview_flutter_linux` uses — there is no platform-view API on
/// Linux). [createTexture] asks the plugin to realise the WebKitGTK view and
/// returns the texture id that a [Texture] widget should display.
///
/// The controller is a plain object (not a provider): a [LumenWebView] widget
/// owns one per tab and registers it in [WebControllers] so the ad-blocker
/// can push content filters to every live webview.
class LumenWebViewController {
  LumenWebViewController(this.id) {
    _channel = MethodChannel('lumen.webview/$id');
    _channel.setMethodCallHandler(_onCall);
  }

  final String id;

  late final MethodChannel _channel;
  bool _disposed = false;

  /// Engine texture id returned by `createTexture`, or null before creation.
  int? textureId;

  final ValueNotifier<String> url = ValueNotifier<String>('');
  final ValueNotifier<String> title = ValueNotifier<String>('');
  final ValueNotifier<double> progress = ValueNotifier<double>(0);
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);
  final ValueNotifier<bool> canGoBack = ValueNotifier<bool>(false);
  final ValueNotifier<bool> canGoForward = ValueNotifier<bool>(false);

  /// True once the native layer reported a fully-loaded page.
  final ValueNotifier<bool> loaded = ValueNotifier<bool>(false);

  /// Raised when the native layer fails to load (→ fall back to system
  /// browser). Payload is the failing URL.
  final StreamController<String> onLoadFailed =
      StreamController<String>.broadcast();

  /// Emits every blocked request count increment (used to update the global
  /// counter / badge).
  final StreamController<int> onBlocked = StreamController<int>.broadcast();

  /// Total requests blocked by content filters for this webview.
  final ValueNotifier<int> blockedCount = ValueNotifier<int>(0);

  String get host {
    final u = Uri.tryParse(url.value);
    return u?.host ?? '';
  }

  /// Origin `scheme://host[:port]` used for per-site ad-block checks.
  String get origin => Uri.tryParse(url.value)?.origin ?? url.value;

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'onUrlChanged':
        final u = call.arguments as String?;
        if (u != null) url.value = u;
        loaded.value = false;
      case 'onTitleChanged':
        final t = call.arguments as String?;
        if (t != null) title.value = t;
      case 'onProgress':
        final p = (call.arguments as num?)?.toDouble() ?? 0;
        progress.value = p;
      case 'onLoadState':
        final s = call.arguments as String?;
        loading.value = s == 'started' || s == 'committed';
        if (s == 'finished') loaded.value = true;
        if (s == 'failed') {
          loading.value = false;
        }
      case 'onNavigation':
        final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
        canGoBack.value = args['back'] as bool? ?? false;
        canGoForward.value = args['forward'] as bool? ?? false;
      case 'onBlocked':
        final n = (call.arguments as num?)?.toInt() ?? 1;
        blockedCount.value += n;
        onBlocked.add(n);
      case 'onLoadFailed':
        final u = call.arguments as String?;
        if (u != null) onLoadFailed.add(u);
    }
  }

  /// Realises the native webview and loads [url] via the probe channel.
  /// Returns the texture id from the native layer, or null on failure.
  Future<int?> createTexture(String urlString) async {
    final r = await WebPluginProbe.createView(id, urlString);
    textureId = r;
    return r;
  }

  /// Tells the native view its on-screen size in logical pixels.
  Future<void> setSize(double width, double height) async {
    if (textureId == null) return;
    await _channel.invokeMethod('setSize', {'w': width, 'h': height});
  }

  Future<void> loadUrl(String urlString) async {
    await _channel.invokeMethod('loadUrl', {'url': urlString});
  }

  Future<void> goBack() async {
    await _channel.invokeMethod('goBack');
  }

  Future<void> goForward() async {
    await _channel.invokeMethod('goForward');
  }

  Future<void> reload() async {
    await _channel.invokeMethod('reload');
  }

  Future<void> stop() async {
    await _channel.invokeMethod('stop');
  }

  /// Installs the given WebKit content-rule JSON documents as the webview's
  /// ad-blocking filters. Parts replace any previously applied list.
  Future<void> setFilters(List<String> parts) async {
    await _channel.invokeMethod('setContentFilters', {'parts': parts});
  }

  /// Removes every installed content filter from this webview.
  Future<void> clearFilters() async {
    await _channel.invokeMethod('clearContentFilters');
  }

  Future<String?> evaluateJavascript(String javaScript) async {
    final r = await _channel.invokeMethod('evaluateJavascript', {
      'js': javaScript,
    });
    return r as String?;
  }

  /// Best-effort destroy of native resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    WebControllers.instance.unregister(this);
    try {
      await _channel.invokeMethod('dispose').timeout(const Duration(seconds: 2));
    } catch (_) {}
    url.dispose();
    title.dispose();
    progress.dispose();
    loading.dispose();
    canGoBack.dispose();
    canGoForward.dispose();
    loaded.dispose();
    blockedCount.dispose();
    await onBlocked.close();
    await onLoadFailed.close();
  }
}