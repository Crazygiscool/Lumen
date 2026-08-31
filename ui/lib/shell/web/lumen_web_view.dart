import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../tabs/tab_model.dart';
import '../tabs/tabs_provider.dart';
import 'ad_block_service.dart';
import 'web_controller.dart';

/// Embedded browser view for a web tab (Linux: WPE WebKit rendered into an
/// engine texture via the `webview_flutter` / `webview_flutter_linux`
/// federated plugin).
///
/// On platforms that do not host an embedded webview (non-Linux desktop) the
/// widget degrades to the "open in system browser" experience instead of
/// breaking the tab.
class LumenWebView extends ConsumerStatefulWidget {
  const LumenWebView({
    super.key,
    required this.tabId,
    required this.startUrl,
  });

  final String tabId;
  final String startUrl;

  @override
  ConsumerState<LumenWebView> createState() => _LumenWebViewState();
}

class _LumenWebViewState extends ConsumerState<LumenWebView> {
  LumenWebViewController? _controller;
  bool _pluginAvailable = false;
  bool _loadFailed = false;
  final List<StreamSubscription<void>> _subs = [];
  final List<StreamSubscription<int>> _blockSubs = [];

  @override
  void initState() {
    super.initState();
    final c = LumenWebViewController(widget.tabId);
    _controller = c;
    _wire(c);
    _pluginAvailable = _isSupported();
    if (_pluginAvailable) {
      c.loadUrl(widget.startUrl);
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    for (final s in _blockSubs) {
      s.cancel();
    }
    final c = _controller;
    if (c != null) {
      c.url.removeListener(_onUrlChanged);
      c.title.removeListener(_onTitleChanged);
      unawaited(c.dispose());
    }
    super.dispose();
  }

  bool _isSupported() {
    if (kIsWeb) return false;
    return Platform.isLinux ||
        Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS;
  }

  void _onUrlChanged() {
    ref.read(tabsProvider.notifier).syncWeb(widget.tabId, url: _controller?.url.value);
  }

  void _onTitleChanged() {
    ref.read(tabsProvider.notifier).syncWeb(widget.tabId, title: _controller?.title.value);
  }

  void _wire(LumenWebViewController c) {
    c.url.addListener(_onUrlChanged);
    c.title.addListener(_onTitleChanged);
    _subs.add(
      c.onLoadFailed.stream.listen((url) {
        if (!mounted) return;
        setState(() => _loadFailed = true);
        openInSystemBrowser(url);
      }),
    );
    _blockSubs.add(
      c.onBlocked.stream.listen(
        (n) => ref.read(adBlockProvider.notifier).recordBlocked(n),
      ),
    );
  }

  void _openExternal() async {
    final url = _controller?.url.value ?? widget.startUrl;
    await openInSystemBrowser(url);
  }

  void _retry() {
    setState(() => _loadFailed = false);
    _controller?.loadUrl(widget.startUrl);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AdBlockState>(adBlockProvider, (_, _) => _applyAdBlock());

    if (!_pluginAvailable) {
      return _Fallback(
        url: widget.startUrl,
        onOpenExternally: _openExternal,
      );
    }
    if (_loadFailed) {
      return _FailedView(
        url: widget.startUrl,
        onOpenExternally: _openExternal,
        onReload: _retry,
      );
    }

    final c = _controller!;
    return Stack(
      children: [
        Positioned.fill(
          child: WebViewWidget(controller: c.native),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _ProgressLine(
            loading: c.loading,
            progress: c.progress,
          ),
        ),
      ],
    );
  }

  /// (Re)applies ad-blocking to this webview whenever the global toggle, the
  /// current compiled list, or this host's exemption changes.
  void _applyAdBlock() {
    final ad = ref.read(adBlockProvider);
    final c = _controller;
    if (c == null) return;
    if (!ad.enabled || ad.exemptHosts.contains(c.host) || ad.parts.isEmpty) {
      unawaited(c.clearFilters());
    } else {
      unawaited(c.setFilters(ad.parts));
    }
  }
}

/// Thin progress indicator over the top edge while a page loads.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.loading, required this.progress});

  final ValueListenable<bool> loading;
  final ValueListenable<double> progress;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: loading,
      builder: (context, isLoading, _) {
        if (!isLoading) return const SizedBox.shrink();
        return ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, p, _) => LinearProgressIndicator(
            value: p.clamp(0.0, 1.0),
            minHeight: 2,
            backgroundColor: Colors.transparent,
          ),
        );
      },
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.url,
    required this.onOpenExternally,
  });
  final String url;
  final VoidCallback onOpenExternally;

  @override
  Widget build(BuildContext context) {
    return _FallbackShell(
      icon: Icons.extension_off_outlined,
      title: 'Embedded browser unavailable',
      body: [
        'An embedded browser is only available on Linux (WPE WebKit). '
        'Open this page in your system browser instead.',
      ],
      url: url,
      onOpenExternally: onOpenExternally,
    );
  }
}

class _FailedView extends StatelessWidget {
  const _FailedView({
    required this.url,
    required this.onOpenExternally,
    required this.onReload,
  });
  final String url;
  final VoidCallback onOpenExternally;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return _FallbackShell(
      icon: Icons.cloud_off_outlined,
      title: 'This page failed to load embedded',
      body: [
        'The site may be blocking the embedded browser, or the native view '
        'was interrupted.',
      ],
      url: url,
      onOpenExternally: onOpenExternally,
      onRetry: onReload,
    );
  }
}

class _FallbackShell extends StatelessWidget {
  const _FallbackShell({
    required this.icon,
    required this.title,
    required this.body,
    required this.url,
    required this.onOpenExternally,
    this.onRetry,
  });
  final IconData icon;
  final String title;
  final List<String> body;
  final String url;
  final VoidCallback onOpenExternally;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 40, color: t.primary),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final line in body)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: t.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                url,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, fontFamily: 'Geist Mono'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: onOpenExternally,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open in system browser'),
                  ),
                  if (onRetry != null)
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
