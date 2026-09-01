import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_linux/webview_flutter_linux.dart'
    as linux_view;

import 'js_adblock.dart';
import 'native_adblock.dart';
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

  /// Compiled JS blocker to inject at the start of each page load. Non-empty
  /// enables blocking; empty disables it.
  String _blockScript = '';

  bool get hasFilters => _blockScript.isNotEmpty;

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
            _injectBlockScript();
          },
          onPageFinished: (u) {
            url.value = u;
            loading.value = false;
            loaded.value = true;
            unawaited(_refreshNavState());
          },
          onProgress: (p) {
            progress.value = p / 100;
            unawaited(_pollNativeBlocked());
          },
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
    unawaited(
      controller.addJavaScriptChannel(
        'lumen_ab',
        onMessageReceived: (message) {
          final n = int.tryParse(message.message) ?? 0;
          if (n <= 0) return;
          blockedCount.value += n;
          onBlocked.add(n);
        },
      ),
    );
    return controller;
  }

  /// Best-effort injection of the compiled blocker at page start.
  void _injectBlockScript() {
    final script = _blockScript;
    if (script.isEmpty) return;
    unawaited(_native.runJavaScript(script).catchError((_) => null));
  }

  /// On Linux, drains the native web-process blocked count into the shared
  /// stream/counter so the Lumen badge stays correct without page scripts.
  Future<void> _pollNativeBlocked() async {
    if (!Platform.isLinux) return;
    final renderer = _linuxController;
    if (renderer == null) return;
    final drained = await renderer.takeBlockedCount().catchError((_) => 0);
    if (drained <= 0) return;
    blockedCount.value += drained;
    onBlocked.add(drained);
  }

  Future<void> _refreshNavState() async {
    try {
      canGoBack.value = await _native.canGoBack();
      canGoForward.value = await _native.canGoForward();
    } catch (_) {}
  }

  /// Best-effort load of [urlString] into the native view.
  Future<void> loadUrl(String urlString) async {    final uri = Uri.tryParse(urlString);
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

  /// Installs ad-blocking filters on this webview.
  ///
  /// `parts` are the WebKit content-rule JSON documents produced by
  /// `libublock`. On Linux they are compiled to a binary blob and handed to the
  /// native WPE extension, which cancels matching subresource requests in the
  /// web process. The same parts are also translated to a JS blocker injected
  /// at page start on platforms without the native path.
  Future<void> setFilters(List<String> parts) async {
    _blockScript = parts.isEmpty ? '' : jsBlockScript(parts);
    _contentBlockRevision += 1;
    await _setNativeContentBlockRules(parts);
  }

  /// Removes every installed filter from this webview.
  Future<void> clearFilters() async {
    _blockScript = '';
    await _setNativeContentBlockRules(const []);
  }

  /// Linux: hands the compiled rule blob to the vendored WPE extension.
  Future<void> _setNativeContentBlockRules(List<String> parts) async {
    if (!Platform.isLinux) return;
    final renderer = _linuxController;
    if (renderer == null) return;
    final revision = parts.isEmpty ? 0 : _contentBlockRevision;
    final blob = revision == 0
        ? Uint8List(0)
        : buildContentRuleBlob(parts, version: revision);
    await renderer.setContentBlockRules(blob).catchError((_) => null);
  }

  /// Revision of the native rule blob; incremented when the compiled list
  /// changes so the web-process extension reloads.
  int _contentBlockRevision = 0;

  /// The Linux platform controller when this view runs on WPE, else null.
  ///
  /// Reached via the federated `WebViewController.platform` accessor, which
  /// returns the concrete `LinuxWebViewController` on Linux.
  linux_view.LinuxWebViewController? get _linuxController {
    if (!Platform.isLinux) return null;
    return _native.platform is linux_view.LinuxWebViewController
        ? _native.platform as linux_view.LinuxWebViewController
        : null;
  }

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
