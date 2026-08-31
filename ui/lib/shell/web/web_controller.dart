import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'web_controllers.dart';

/// Controller for a single embedded web tab, backed by the federated
/// `webview_flutter` API (WPE WebKit on Linux via `webview_flutter_linux`).
///
/// On Linux the embedder renders the webview into an engine texture that the
/// `webview_flutter` widget presents; there is no platform-view API there.
///
/// The controller is a plain object (not a provider): a [LumenWebView] widget
/// owns one per tab and registers it in [WebControllers] so the ad-blocker
/// can push filters to every live webview.
class LumenWebViewController {
  LumenWebViewController(this.id) {
    WebControllers.instance.register(this);
  }

  final String id;

  late final WebViewController _native = _createNative();
  bool _disposed = false;

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

  /// Total requests blocked by filters for this webview.
  final ValueNotifier<int> blockedCount = ValueNotifier<int>(0);

  /// The underlying federated controller, exposed for symbols that need the
  /// real `WebViewController` (e.g. a [WebViewWidget]).
  WebViewController get native => _native;

  String get host {
    final u = Uri.tryParse(url.value);
    return u?.host ?? '';
  }

  /// Origin `scheme://host[:port]` used for per-site ad-block checks.
  String get origin => Uri.tryParse(url.value)?.origin ?? url.value;

  WebViewController _createNative() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (u) {
            url.value = u;
            loading.value = true;
            loaded.value = false;
          },
          onPageFinished: (u) {
            url.value = u;
            loading.value = false;
            loaded.value = true;
            unawaited(_refreshNavState());
          },
          onProgress: (p) => progress.value = p / 100,
          onUrlChange: (change) {
            final u = change.url;
            if (u == null) return;
            if (u != url.value) url.value = u.toString();
            unawaited(_refreshNavState());
          },
          onWebResourceError: (error) {
            final u = error.url ?? url.value;
            onLoadFailed.add(u);
          },
        ),
      );
    return controller;
  }

  Future<void> _refreshNavState() async {
    try {
      canGoBack.value = await _native.canGoBack();
      canGoForward.value = await _native.canGoForward();
    } catch (_) {}
  }

  /// Best-effort load of [urlString] into the native view.
  Future<void> loadUrl(String urlString) async {
    final uri = Uri.tryParse(urlString);
    if (uri == null) return;
    loading.value = true;
    try {
      await _native.loadRequest(uri);
    } catch (_) {
      onLoadFailed.add(urlString);
    }
  }

  Future<void> goBack() async {
    await _native.goBack();
  }

  Future<void> goForward() async {
    await _native.goForward();
  }

  Future<void> reload() async {
    await _native.reload();
  }

  Future<void> stop() async {
    // The federated API has no stop; reload is the closest safe reset.
    await _native.reload();
  }

  /// Installs ad-blocking filters (WebKit content-rule JSON) on this webview.
  ///
  /// Staged: the federated webview has no content-rule API, so this is a
  /// no-op until the JS-injection port lands.
  Future<void> setFilters(List<String> parts) async {}

  /// Removes every installed filter from this webview.
  Future<void> clearFilters() async {}

  /// Best-effort destroy of native resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    WebControllers.instance.unregister(this);
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
