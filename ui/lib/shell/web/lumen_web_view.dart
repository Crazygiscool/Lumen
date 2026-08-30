import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tabs/tab_model.dart';
import '../tabs/tabs_provider.dart';
import 'ad_block_service.dart';
import 'web_controller.dart';
import 'web_controllers.dart';
import 'web_plugin_probe.dart';

/// Embedded browser view for a web tab (Linux: WebKitGTK rendered into an
/// engine texture via the `lumen_webview` plugin).
///
/// If the native plugin is unavailable the widget degrades to the old
/// "open in system browser" experience instead of breaking the tab.
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
  Future<int?>? _textureFuture;
  bool _probeDone = false;
  bool _pluginAvailable = false;
  bool _loadFailed = false;
  final List<StreamSubscription<void>> _subs = [];
  final List<StreamSubscription<int>> _blockSubs = [];

  @override
  void initState() {
    super.initState();
    final c = LumenWebViewController(widget.tabId);
    _controller = c;
    WebControllers.instance.register(c);
    _wire(c);
    _probe(c);
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

  Future<void> _probe(LumenWebViewController c) async {
    final available = await WebPluginProbe.ping();
    if (!mounted) return;
    setState(() {
      _probeDone = true;
      _pluginAvailable = available;
    });
    if (!available) return;
    _textureFuture = c.createTexture(widget.startUrl);
    final id = await _textureFuture;
    if (!mounted || id == null) return;
    setState(() {});
    _applyAdBlock();
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

  Future<void> _probeRetry() async {
    setState(() {
      _probeDone = false;
      _pluginAvailable = false;
    });
    await WebPluginProbe.ping();
    if (!mounted) return;
    final c = _controller;
    if (c == null) return;
    await _probe(c);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AdBlockState>(adBlockProvider, (_, _) => _applyAdBlock());

    if (!_probeDone) {
      return const SizedBox.shrink();
    }
    if (_loadFailed) {
      return _FailedView(
        url: widget.startUrl,
        onOpenExternally: () => openInSystemBrowser(widget.startUrl),
        onReload: () {
          setState(() => _loadFailed = false);
          ref.read(tabsProvider.notifier).reload();
        },
      );
    }
    if (!_pluginAvailable) {
      return _Fallback(
        url: widget.startUrl,
        onOpenExternally: () => openInSystemBrowser(widget.startUrl),
        onRetry: _probeRetry,
      );
    }

    final c = _controller!;
    final textureId = c.textureId;

    return Stack(
      children: [
        Positioned.fill(child: _surface(c, textureId)),
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

  Widget _surface(LumenWebViewController c, int? textureId) {
    if (textureId == null) {
      return FutureBuilder<int?>(
        future: _textureFuture,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Could not create the native web view.'),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => openInSystemBrowser(widget.startUrl),
                    child: const Text('Open in system browser'),
                  ),
                ],
              ),
            );
          }
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          if (w > 0 && h > 0) {
            Future<void>.microtask(() => c.setSize(w, h));
          }
        }
        return Texture(
          textureId: textureId,
          filterQuality: FilterQuality.medium,
        );
      },
    );
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
    required this.onRetry,
  });
  final String url;
  final VoidCallback onOpenExternally;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _FallbackShell(
      icon: Icons.extension_off_outlined,
      title: 'Embedded browser unavailable',
      body: [
        'The embedded browser needs the WebKitGTK runtime (webkit2gtk-4.1) '
        'that Lumen was built against. Install it for your distribution, then '
        'retry:',
        '• Debian / Ubuntu:  sudo apt install libwebkit2gtk-4.1-0',
        '• Fedora:           sudo dnf install webkit2gtk4.1',
        '• Arch:             sudo pacman -S webkit2gtk-4.1',
        'Until then you can open pages in your system browser instead.',
      ],
      url: url,
      onOpenExternally: onOpenExternally,
      onRetry: onRetry,
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
    required this.onRetry,
  });
  final IconData icon;
  final String title;
  final List<String> body;
  final String url;
  final VoidCallback onOpenExternally;
  final VoidCallback onRetry;

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