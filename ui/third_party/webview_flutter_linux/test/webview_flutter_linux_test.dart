// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_linux/webview_flutter_linux.dart';
import 'package:webview_flutter_linux/src/native_frame_renderer.dart';
import 'package:webview_flutter_linux/src/native_website_data_store.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  setUp(WebViewFlutterLinux.registerWith);

  test('registers the Linux WebView platform', () {
    expect(WebViewPlatform.instance, isA<WebViewFlutterLinux>());
  });

  test('creates all federated platform delegates', () {
    final platform = WebViewPlatform.instance!;
    final controller = platform.createPlatformWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    expect(controller, isA<LinuxWebViewController>());
    expect(
      platform.createPlatformNavigationDelegate(
        const PlatformNavigationDelegateCreationParams(),
      ),
      isA<LinuxNavigationDelegate>(),
    );
    expect(
      platform.createPlatformCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
      isA<LinuxWebViewCookieManager>(),
    );
    expect(
      platform.createPlatformWebViewWidget(
        PlatformWebViewWidgetCreationParams(controller: controller),
      ),
      isA<LinuxWebViewWidget>(),
    );
  });

  test('retains WPE capability policies before native attachment', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    expect(controller.mediaPlaybackAllowsInline, isNull);
    expect(controller.webRtcEnabled, isNull);
    expect(controller.mockCaptureDevicesEnabled, isFalse);
    expect(controller.encryptedMediaEnabled, isNull);
    expect(controller.allowFileAccessFromFileUrls, isNull);
    expect(controller.allowUniversalAccessFromFileUrls, isNull);

    await controller.setMediaPlaybackAllowsInline(false);
    await controller.setWebRtcEnabled(false);
    await controller.setMockCaptureDevicesEnabled(true);
    await controller.setEncryptedMediaEnabled(true);
    await controller.setAllowFileAccessFromFileUrls(false);
    await controller.setAllowUniversalAccessFromFileUrls(true);

    expect(controller.mediaPlaybackAllowsInline, isFalse);
    expect(controller.webRtcEnabled, isFalse);
    expect(controller.mockCaptureDevicesEnabled, isTrue);
    expect(controller.encryptedMediaEnabled, isTrue);
    expect(controller.allowFileAccessFromFileUrls, isFalse);
    expect(controller.allowUniversalAccessFromFileUrls, isTrue);
  });

  test('decodes WPE setting and host-support capability bits separately', () {
    const state = LinuxWebViewCapabilityState.fromFlags(
      (1 << 0) | (1 << 1) | (1 << 4) | (1 << 5) | (1 << 9),
    );

    expect(state.inlineMediaPlaybackEnabled, isTrue);
    expect(state.webRtcSettingEnabled, isTrue);
    expect(state.webRtcSupportedByHost, isFalse);
    expect(state.encryptedMediaSettingEnabled, isFalse);
    expect(state.encryptedMediaSupportedByHost, isTrue);
    expect(state.fileAccessFromFileUrlsEnabled, isFalse);
    expect(state.universalAccessFromFileUrlsEnabled, isTrue);
    expect(state.javaScriptClipboardAccessEnabled, isTrue);
  });

  test(
    'validates cookie paths and lookup schemes before native work',
    () async {
      final manager = LinuxWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      );

      expect(
        () => manager.setCookie(
          const WebViewCookie(
            name: 'probe',
            value: 'value',
            domain: 'example.com',
            path: '/invalid;path',
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        manager.getCookies(Uri.parse('file:///tmp/index.html')),
        throwsArgumentError,
      );
    },
  );

  test('tracks URL and history before a widget is attached', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.loadRequest(
      LoadRequestParams(uri: Uri.parse('https://example.com/one')),
    );
    await controller.loadRequest(
      LoadRequestParams(uri: Uri.parse('https://example.com/two')),
    );

    expect(await controller.currentUrl(), 'https://example.com/two');
    expect(await controller.canGoBack(), isTrue);
    expect(await controller.canGoForward(), isFalse);

    await controller.goBack();
    expect(await controller.currentUrl(), 'https://example.com/one');
    expect(await controller.canGoForward(), isTrue);
  });

  test('controller disposal is idempotent and terminal', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    expect(controller.isDisposed, isFalse);
    controller.dispose();
    controller.dispose();
    expect(controller.isDisposed, isTrue);

    await expectLater(
      controller.loadRequest(
        LoadRequestParams(uri: Uri.parse('https://example.com/after-dispose')),
      ),
      throwsStateError,
    );
    await expectLater(
      controller.runJavaScript('document.title'),
      throwsStateError,
    );
  });

  test('reports changes to backward-history availability', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final changes = <bool>[];

    await controller.setOnCanGoBackChange(changes.add);
    await controller.loadRequest(
      LoadRequestParams(uri: Uri.parse('https://example.com/first')),
    );
    await controller.loadRequest(
      LoadRequestParams(uri: Uri.parse('https://example.com/second')),
    );
    await controller.goBack();

    expect(changes, <bool>[true, false]);
  });

  test('resolves Flutter asset keys inside the Linux bundle', () {
    expect(
      resolveLinuxFlutterAssetUri(
        executablePath: '/opt/example/browser',
        assetKey: 'assets/pages/index file.html',
      ),
      Uri.parse(
        'file:///opt/example/data/flutter_assets/'
        'assets/pages/index%20file.html',
      ),
    );

    for (final key in <String>['', '/etc/passwd', '../secret', './page.html']) {
      expect(
        () => resolveLinuxFlutterAssetUri(
          executablePath: '/opt/example/browser',
          assetKey: key,
        ),
        throwsArgumentError,
        reason: key,
      );
    }
  });

  test('retains HTML base URL navigation before attachment', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.loadRequest(
      LoadRequestParams(uri: Uri.parse('https://example.com/before')),
    );
    await controller.loadHtmlString(
      '<title>Native HTML</title><img src="images/probe.png">',
      baseUrl: 'https://assets.example.com/document/',
    );

    expect(
      await controller.currentUrl(),
      'https://assets.example.com/document/',
    );
    expect(await controller.canGoBack(), isTrue);

    await controller.goBack();
    expect(await controller.currentUrl(), 'https://example.com/before');
    await controller.goForward();
    expect(
      await controller.currentUrl(),
      'https://assets.example.com/document/',
    );
    await controller.reload();
    expect(
      await controller.currentUrl(),
      'https://assets.example.com/document/',
    );
  });

  test(
    'accepts safe GET headers, GET bodies, and complete POST requests',
    () async {
      final controller = LinuxWebViewController(
        const PlatformWebViewControllerCreationParams(),
      );

      await controller.loadRequest(
        LoadRequestParams(
          uri: Uri.parse('https://example.com/headers'),
          headers: const <String, String>{'X-WebView-Probe': 'flutter-linux'},
        ),
      );
      expect(await controller.currentUrl(), 'https://example.com/headers');

      await expectLater(
        controller.loadRequest(
          LoadRequestParams(
            uri: Uri.parse('https://example.com'),
            headers: const <String, String>{'Bad Header': 'value'},
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        controller.loadRequest(
          LoadRequestParams(
            uri: Uri.parse('https://example.com'),
            headers: const <String, String>{'X-Probe': 'safe\r\ninjected'},
          ),
        ),
        throwsArgumentError,
      );
      await controller.loadRequest(
        LoadRequestParams(
          uri: Uri.parse('https://example.com/post'),
          method: LoadRequestMethod.post,
          headers: const <String, String>{
            'Content-Type': 'application/octet-stream',
            'X-WebView-Probe': 'post-header-present',
          },
          body: Uint8List.fromList(<int>[0, 1, 2, 255]),
        ),
      );
      expect(await controller.currentUrl(), 'https://example.com/post');

      await controller.loadRequest(
        LoadRequestParams(
          uri: Uri.parse('https://example.com/get-body'),
          body: Uint8List.fromList(<int>[1]),
        ),
      );
      expect(await controller.currentUrl(), 'https://example.com/get-body');
    },
  );

  test('honors navigation prevention', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final delegate = LinuxNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    await delegate.setOnNavigationRequest((_) => NavigationDecision.prevent);
    await controller.setPlatformNavigationDelegate(delegate);

    await controller.loadRequest(
      LoadRequestParams(uri: Uri.parse('https://example.com/blocked')),
    );

    expect(await controller.currentUrl(), isNull);
  });

  test('reports native lifecycle, redirects, and progress in order', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final delegate = LinuxNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    final callbacks = <String>[];
    await delegate.setOnUrlChange(
      (change) => callbacks.add('url:${change.url}'),
    );
    await delegate.setOnPageStarted((url) => callbacks.add('started:$url'));
    await delegate.setOnProgress(
      (progress) => callbacks.add('progress:$progress'),
    );
    await delegate.setOnPageFinished((url) => callbacks.add('finished:$url'));
    await controller.setPlatformNavigationDelegate(delegate);

    await controller.loadRequest(
      LoadRequestParams(uri: Uri.parse('https://example.com/one')),
    );
    controller.didReceiveNavigationEvents(const [
      NativeNavigationEvent(
        kind: NativeNavigationEventKind.started,
        url: 'https://example.com/one',
        progress: 0,
      ),
      NativeNavigationEvent(
        kind: NativeNavigationEventKind.progress,
        url: 'https://example.com/one',
        progress: 42,
      ),
      NativeNavigationEvent(
        kind: NativeNavigationEventKind.progress,
        url: 'https://example.com/one',
        progress: 42,
      ),
      NativeNavigationEvent(
        kind: NativeNavigationEventKind.finished,
        url: 'https://example.com/one',
        progress: 100,
      ),
    ]);

    expect(callbacks, [
      'url:https://example.com/one',
      'progress:0',
      'started:https://example.com/one',
      'progress:42',
      'progress:100',
      'finished:https://example.com/one',
    ]);

    callbacks.clear();
    controller.didReceiveNavigationEvents(const [
      NativeNavigationEvent(
        kind: NativeNavigationEventKind.started,
        url: 'https://example.com/two',
        progress: 0,
      ),
      NativeNavigationEvent(
        kind: NativeNavigationEventKind.redirected,
        url: 'https://example.com/three',
        progress: 0,
      ),
      NativeNavigationEvent(
        kind: NativeNavigationEventKind.committed,
        url: 'https://example.com/three',
        progress: 0,
      ),
      NativeNavigationEvent(
        kind: NativeNavigationEventKind.finished,
        url: 'https://example.com/three',
        progress: 100,
      ),
    ]);

    expect(await controller.currentUrl(), 'https://example.com/three');
    expect(await controller.canGoBack(), isTrue);
    expect(callbacks, [
      'url:https://example.com/two',
      'progress:0',
      'started:https://example.com/two',
      'url:https://example.com/three',
      'progress:100',
      'finished:https://example.com/three',
    ]);

    await controller.goBack();
    expect(await controller.currentUrl(), 'https://example.com/one');
    expect(await controller.canGoForward(), isTrue);
  });

  test('ignores the implicit initial about blank lifecycle', () {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    controller.didReceiveNavigationEvents(const [
      NativeNavigationEvent(
        kind: NativeNavigationEventKind.started,
        url: 'about:blank',
        progress: 0,
      ),
      NativeNavigationEvent(
        kind: NativeNavigationEventKind.finished,
        url: 'about:blank',
        progress: 100,
      ),
    ]);

    expect(controller.currentUrl(), completion(isNull));
    expect(controller.canGoBack(), completion(isFalse));
  });

  test('ignores a racing initial blank after a request is queued', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final delegate = LinuxNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    final callbacks = <String>[];
    await delegate.setOnUrlChange(
      (change) => callbacks.add('url:${change.url}'),
    );
    await delegate.setOnPageFinished((url) => callbacks.add('finished:$url'));
    await controller.setPlatformNavigationDelegate(delegate);
    await controller.loadRequest(
      LoadRequestParams(uri: Uri.parse('https://example.com/requested')),
    );

    controller.didReceiveNavigationEvents(const [
      NativeNavigationEvent(
        kind: NativeNavigationEventKind.started,
        url: 'about:blank',
        progress: 0,
      ),
      NativeNavigationEvent(
        kind: NativeNavigationEventKind.finished,
        url: 'about:blank',
        progress: 100,
      ),
    ]);

    expect(await controller.currentUrl(), 'https://example.com/requested');
    expect(callbacks, isEmpty);
  });

  test('reports native resource and HTTP response errors', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final delegate = LinuxNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    WebResourceError? resourceError;
    HttpResponseError? httpError;
    await delegate.setOnWebResourceError((error) => resourceError = error);
    await delegate.setOnHttpError((error) => httpError = error);
    await controller.setPlatformNavigationDelegate(delegate);

    controller.didReceiveNavigationEvents(const <NativeNavigationEvent>[
      NativeNavigationEvent(
        kind: NativeNavigationEventKind.resourceError,
        url: 'missing-scheme://page',
        progress: 0,
        code: 301,
        detail: 'Unsupported URI scheme',
        isMainFrame: false,
      ),
      NativeNavigationEvent(
        kind: NativeNavigationEventKind.httpError,
        url: 'https://example.com/missing',
        progress: 0,
        code: 404,
      ),
    ]);

    expect(resourceError?.errorCode, 301);
    expect(resourceError?.errorType, WebResourceErrorType.unsupportedScheme);
    expect(resourceError?.description, 'Unsupported URI scheme');
    expect(resourceError?.isForMainFrame, isFalse);
    expect(resourceError?.url, 'missing-scheme://page');
    expect(httpError?.response?.statusCode, 404);
    expect(httpError?.request?.uri, Uri.parse('https://example.com/missing'));
  });

  test(
    'reports web-process termination through the federated error type',
    () async {
      final controller = LinuxWebViewController(
        const PlatformWebViewControllerCreationParams(),
      );
      final delegate = LinuxNavigationDelegate(
        const PlatformNavigationDelegateCreationParams(),
      );
      WebResourceError? resourceError;
      await delegate.setOnWebResourceError((error) => resourceError = error);
      await controller.setPlatformNavigationDelegate(delegate);

      expect(
        NativeNavigationEventKind.fromWireValue(8),
        NativeNavigationEventKind.webProcessTerminated,
      );
      controller.didReceiveNavigationEvents(const <NativeNavigationEvent>[
        NativeNavigationEvent(
          kind: NativeNavigationEventKind.webProcessTerminated,
          url: 'https://example.com/recoverable',
          progress: 0,
          code: 2,
          detail: 'WPE WebKit web process was terminated by an API request.',
        ),
      ]);

      expect(resourceError?.errorCode, 2);
      expect(
        resourceError?.errorType,
        WebResourceErrorType.webContentProcessTerminated,
      );
      expect(resourceError?.isForMainFrame, isTrue);
      expect(resourceError?.url, 'https://example.com/recoverable');
      expect(resourceError?.description, contains('terminated by an API'));
    },
  );

  group('JavaScript result decoding', () {
    test('preserves JSON primitive and structured values', () {
      expect(decodeJavaScriptResult(0, '42'), 42);
      expect(decodeJavaScriptResult(0, 'true'), isTrue);
      expect(decodeJavaScriptResult(0, '"hello"'), 'hello');
      expect(decodeJavaScriptResult(0, '[1,"two"]'), <Object>[1, 'two']);
      expect(decodeJavaScriptResult(0, '{"answer":42}'), <String, Object>{
        'answer': 42,
      });
    });

    test('maps JavaScript null and undefined to Dart null', () {
      expect(decodeJavaScriptResult(1, ''), isNull);
      expect(decodeJavaScriptResult(2, ''), isNull);
    });

    test('normalizes public string and null results like Android WebView', () {
      expect(normalizeJavaScriptResult('Tom'), '"Tom"');
      expect(normalizeJavaScriptResult('say "hello"'), '"say \\"hello\\""');
      expect(normalizeJavaScriptResult(null), 'null');
      expect(normalizeJavaScriptResult(42), 42);
      expect(normalizeJavaScriptResult(true), isTrue);
      expect(normalizeJavaScriptResult(<Object>[1, 'two']), <Object>[1, 'two']);
    });

    test('turns native JavaScript failures into PlatformException', () {
      expect(
        () => decodeJavaScriptResult(
          -1,
          'ReferenceError: missing is not defined',
        ),
        throwsA(
          isA<PlatformException>()
              .having((error) => error.code, 'code', 'javascript_error')
              .having(
                (error) => error.message,
                'message',
                contains('ReferenceError'),
              ),
        ),
      );
    });

    test('distinguishes unsupported result types from script failures', () {
      expect(
        () => decodeJavaScriptResult(3, 'Unsupported result type'),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'javascript_result_unsupported',
          ),
        ),
      );
    });
  });

  group('JavaScript-backed controller values', () {
    test('decodes a structured scroll position', () {
      expect(
        decodeJavaScriptScrollPosition(<Object>[12, 34.5]),
        const Offset(12, 34.5),
      );
    });

    test('rejects malformed scroll positions', () {
      expect(
        () => decodeJavaScriptScrollPosition(<Object>[12]),
        throwsA(isA<StateError>()),
      );
      expect(
        () => decodeJavaScriptScrollPosition('12,34'),
        throwsA(isA<StateError>()),
      );
    });
  });

  test(
    'clears website data before attachment and matches concurrent IDs',
    () async {
      final started = <(int, int)>[];
      final results = <({int requestId, int status})>[];
      final store = NativeWebsiteDataStore(
        start: (requestId, types) {
          started.add((requestId, types));
          if (requestId == 2) {
            results
              ..add((requestId: 2, status: 0))
              ..add((requestId: 1, status: 0));
          }
          return 0;
        },
        resultCount: () => results.length,
        resultRequestId: () => results.first.requestId,
        resultStatus: () => results.first.status,
        resultErrorLength: () => 0,
        copyResultError: (_, _) => 0,
        popResult: () {
          results.removeAt(0);
          return 0;
        },
      );

      final controller = LinuxWebViewController.forTesting(
        const PlatformWebViewControllerCreationParams(),
        websiteDataStore: store,
      );

      await Future.wait(<Future<void>>[
        controller.clearCache(),
        controller.clearLocalStorage(),
      ]);

      expect(started, <(int, int)>[(1, 0x807), (2, 0x10)]);
      expect(results, isEmpty);
    },
  );

  test('accepts JavaScript mode changes before widget attachment', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await expectLater(
      controller.setJavaScriptMode(JavaScriptMode.disabled),
      completes,
    );
    await expectLater(
      controller.setJavaScriptMode(JavaScriptMode.unrestricted),
      completes,
    );
  });

  test('retains Linux browser capability settings before attachment', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    expect(controller.mediaPlaybackRequiresUserGesture, isTrue);
    expect(controller.inspectable, isFalse);
    expect(controller.geolocationEnabled, isTrue);
    expect(controller.javaScriptCanOpenWindowsAutomatically, isTrue);
    expect(controller.javaScriptCanAccessClipboard, isFalse);

    await controller.setMediaPlaybackRequiresUserGesture(false);
    await controller.setInspectable(true);
    await controller.setGeolocationEnabled(false);
    await controller.setJavaScriptCanOpenWindowsAutomatically(false);
    await controller.setJavaScriptCanAccessClipboard(true);

    expect(controller.mediaPlaybackRequiresUserGesture, isFalse);
    expect(controller.inspectable, isTrue);
    expect(controller.geolocationEnabled, isFalse);
    expect(controller.javaScriptCanOpenWindowsAutomatically, isFalse);
    expect(controller.javaScriptCanAccessClipboard, isTrue);
    await controller.setGeolocationEnabled(true);
    await controller.setJavaScriptCanOpenWindowsAutomatically(true);
    await controller.setJavaScriptCanAccessClipboard(false);
    expect(controller.geolocationEnabled, isTrue);
    expect(controller.javaScriptCanOpenWindowsAutomatically, isTrue);
    expect(controller.javaScriptCanAccessClipboard, isFalse);
  });

  test('retains zoom and background settings before attachment', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.enableZoom(false);
    expect(controller.zoomEnabled, isFalse);
    await expectLater(
      controller.setBackgroundColor(const Color(0xff123456)),
      completes,
    );
    await controller.enableZoom(true);
    expect(controller.zoomEnabled, isTrue);
  });

  test('retains validated text zoom before attachment', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    expect(controller.textZoom, 100);
    await controller.setTextZoom(175);
    expect(controller.textZoom, 175);
    await controller.setTextZoom(100);
    expect(controller.textZoom, 100);

    await expectLater(controller.setTextZoom(9), throwsArgumentError);
    await expectLater(controller.setTextZoom(1001), throwsArgumentError);
    expect(controller.textZoom, 100);
  });

  test('retains scrollbar and overscroll settings before attachment', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    expect(controller.supportsSetScrollBarsEnabled(), isTrue);
    await controller.setVerticalScrollBarEnabled(false);
    await controller.setHorizontalScrollBarEnabled(false);
    await controller.setOverScrollMode(WebViewOverScrollMode.never);

    expect(controller.verticalScrollBarEnabled, isFalse);
    expect(controller.horizontalScrollBarEnabled, isFalse);
    expect(controller.overScrollMode, WebViewOverScrollMode.never);
  });

  test('routes JavaScript channel messages and supports removal', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final received = <String>[];
    await controller.addJavaScriptChannel(
      JavaScriptChannelParams(
        name: 'Echo',
        onMessageReceived: (message) => received.add(message.message),
      ),
    );

    controller.didReceiveJavaScriptMessages(const <NativeJavaScriptMessage>[
      NativeJavaScriptMessage(channel: 'Echo', message: 'first'),
      NativeJavaScriptMessage(channel: 'Unknown', message: 'ignored'),
      NativeJavaScriptMessage(channel: 'Echo', message: '(null)'),
    ]);
    expect(received, <String>['first', '(null)']);

    await controller.removeJavaScriptChannel('Echo');
    controller.didReceiveJavaScriptMessages(const <NativeJavaScriptMessage>[
      NativeJavaScriptMessage(channel: 'Echo', message: 'after removal'),
    ]);
    expect(received, <String>['first', '(null)']);
    await expectLater(controller.removeJavaScriptChannel('Echo'), completes);
  });

  test('requires non-empty unique JavaScript channel names', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final channel = JavaScriptChannelParams(
      name: 'Echo',
      onMessageReceived: (_) {},
    );

    await controller.addJavaScriptChannel(channel);
    await expectLater(
      controller.addJavaScriptChannel(channel),
      throwsArgumentError,
    );
    await expectLater(
      controller.addJavaScriptChannel(
        JavaScriptChannelParams(name: '', onMessageReceived: (_) {}),
      ),
      throwsArgumentError,
    );
  });

  test('routes JavaScript dialogs through federated callbacks', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final callbacks = <String>[];
    await controller.setOnJavaScriptAlertDialog((request) async {
      callbacks.add('alert:${request.message}:${request.url}');
    });
    await controller.setOnJavaScriptConfirmDialog((request) async {
      callbacks.add('confirm:${request.message}:${request.url}');
      return true;
    });
    await controller.setOnJavaScriptTextInputDialog((request) async {
      callbacks.add(
        'prompt:${request.message}:${request.url}:${request.defaultText}',
      );
      return 'Flutter response';
    });

    final alert = await controller.decideJavaScriptDialogRequest(
      const NativeJavaScriptDialogRequest(
        id: 1,
        kind: NativeJavaScriptDialogKind.alert,
        message: 'Heads up',
        url: 'https://example.com/alert',
        defaultText: null,
      ),
    );
    final confirm = await controller.decideJavaScriptDialogRequest(
      const NativeJavaScriptDialogRequest(
        id: 2,
        kind: NativeJavaScriptDialogKind.confirm,
        message: 'Continue?',
        url: 'https://example.com/confirm',
        defaultText: null,
      ),
    );
    final prompt = await controller.decideJavaScriptDialogRequest(
      const NativeJavaScriptDialogRequest(
        id: 3,
        kind: NativeJavaScriptDialogKind.prompt,
        message: 'Your answer?',
        url: 'https://example.com/prompt',
        defaultText: 'Default answer',
      ),
    );
    final beforeUnload = await controller.decideJavaScriptDialogRequest(
      const NativeJavaScriptDialogRequest(
        id: 4,
        kind: NativeJavaScriptDialogKind.beforeUnloadConfirm,
        message: 'Leave?',
        url: 'https://example.com/unload',
        defaultText: null,
      ),
    );

    expect(alert, (confirmed: true, promptText: null));
    expect(confirm, (confirmed: true, promptText: null));
    expect(prompt, (confirmed: true, promptText: 'Flutter response'));
    expect(beforeUnload, (confirmed: true, promptText: null));
    expect(callbacks, <String>[
      'alert:Heads up:https://example.com/alert',
      'confirm:Continue?:https://example.com/confirm',
      'prompt:Your answer?:https://example.com/prompt:Default answer',
      'confirm:Leave?:https://example.com/unload',
    ]);
  });

  test('dismisses JavaScript dialogs when no callback is registered', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    expect(
      await controller.decideJavaScriptDialogRequest(
        const NativeJavaScriptDialogRequest(
          id: 1,
          kind: NativeJavaScriptDialogKind.confirm,
          message: 'Continue?',
          url: 'https://example.com',
          defaultText: null,
        ),
      ),
      (confirmed: false, promptText: null),
    );
    expect(
      await controller.decideJavaScriptDialogRequest(
        const NativeJavaScriptDialogRequest(
          id: 2,
          kind: NativeJavaScriptDialogKind.prompt,
          message: 'Answer?',
          url: 'https://example.com',
          defaultText: 'Default',
        ),
      ),
      (confirmed: false, promptText: null),
    );
  });

  test(
    'normalizes Flutter file-selector results before native delivery',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'linux-webview-file-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final selectedFile = File('${directory.path}/selected.txt')
        ..writeAsStringSync('selected by Flutter');
      final acceptedTypes = <String>['text/plain'];
      final initialFiles = <String>['/tmp/previous.txt'];
      LinuxFileSelectorParams? received;
      final controller = LinuxWebViewController(
        const PlatformWebViewControllerCreationParams(),
      );
      await controller.setOnShowFileSelector((params) async {
        received = params;
        return <String>[selectedFile.uri.toString()];
      });

      final nativeRequest = NativeFileChooserRequest(
        id: 17,
        allowsMultiple: true,
        acceptedMimeTypes: acceptedTypes,
        selectedFiles: initialFiles,
      );
      acceptedTypes.clear();
      initialFiles.clear();
      final result = await controller.decideFileChooserRequest(nativeRequest);

      expect(result, <String>[selectedFile.absolute.path]);
      expect(received?.mode, LinuxFileSelectorMode.openMultiple);
      expect(received?.acceptedMimeTypes, <String>['text/plain']);
      expect(received?.initialFiles, <String>['/tmp/previous.txt']);
      expect(
        () => received!.acceptedMimeTypes.add('image/png'),
        throwsUnsupportedError,
      );
      expect(() => result.add('/tmp/other.txt'), throwsUnsupportedError);
    },
  );

  test('cancels file selection when no callback is registered', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    expect(
      await controller.decideFileChooserRequest(
        NativeFileChooserRequest(
          id: 1,
          allowsMultiple: false,
          acceptedMimeTypes: const <String>[],
          selectedFiles: const <String>[],
        ),
      ),
      isEmpty,
    );
  });

  test('rejects multiple files for a single-selection input', () async {
    final directory = Directory.systemTemp.createTempSync(
      'linux-webview-file-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final first = File('${directory.path}/first.txt')
      ..writeAsStringSync('first');
    final second = File('${directory.path}/second.txt')
      ..writeAsStringSync('second');
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    await controller.setOnShowFileSelector(
      (_) async => <String>[first.path, second.path],
    );
    final errors = <FlutterErrorDetails>[];
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previousErrorHandler);

    final result = await controller.decideFileChooserRequest(
      NativeFileChooserRequest(
        id: 2,
        allowsMultiple: false,
        acceptedMimeTypes: const <String>['text/plain'],
        selectedFiles: const <String>[],
      ),
    );

    expect(result, isEmpty);
    expect(errors, hasLength(1));
    expect(errors.single.exception, isA<StateError>());
  });

  test('normalizes an asynchronous download destination', () async {
    final directory = Directory.systemTemp.createTempSync(
      'linux-webview-download-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    LinuxWebViewDownloadRequest? received;
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    await controller.setOnDownloadDestination((request) async {
      received = request;
      return LinuxWebViewDownloadDestination(
        File('${directory.path}/result.bin').uri.toString(),
        allowOverwrite: true,
      );
    });

    final result = await controller.decideDownloadRequest(
      const NativeDownloadRequest(
        id: 41,
        uri: 'https://example.com/result.bin',
        suggestedFilename: 'result.bin',
        mimeType: 'application/octet-stream',
        contentLength: 8192,
      ),
    );

    expect(received?.id, 41);
    expect(received?.url, 'https://example.com/result.bin');
    expect(received?.suggestedFilename, 'result.bin');
    expect(received?.mimeType, 'application/octet-stream');
    expect(received?.contentLength, 8192);
    expect(result?.path, '${directory.absolute.path}/result.bin');
    expect(result?.allowOverwrite, isTrue);
  });

  test(
    'cancels downloads when no destination callback is registered',
    () async {
      final controller = LinuxWebViewController(
        const PlatformWebViewControllerCreationParams(),
      );

      expect(
        await controller.decideDownloadRequest(
          const NativeDownloadRequest(
            id: 1,
            uri: 'https://example.com/file.txt',
            suggestedFilename: 'file.txt',
            mimeType: 'text/plain',
            contentLength: null,
          ),
        ),
        isNull,
      );
    },
  );

  test('routes correlated download lifecycle events', () async {
    final received = <LinuxWebViewDownloadEvent>[];
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    await controller.setOnDownloadEvent(received.add);

    controller.didReceiveDownloadEvents(const <NativeDownloadEvent>[
      NativeDownloadEvent(
        id: 7,
        kind: NativeDownloadEventKind.createdDestination,
        receivedBytes: 0,
        contentLength: 100,
        errorCode: 0,
        destination: '/tmp/file.bin',
        detail: null,
      ),
      NativeDownloadEvent(
        id: 7,
        kind: NativeDownloadEventKind.progress,
        receivedBytes: 40,
        contentLength: 100,
        errorCode: 0,
        destination: '/tmp/file.bin',
        detail: null,
      ),
      NativeDownloadEvent(
        id: 7,
        kind: NativeDownloadEventKind.finished,
        receivedBytes: 100,
        contentLength: 100,
        errorCode: 0,
        destination: '/tmp/file.bin',
        detail: null,
      ),
    ]);

    expect(received.map((event) => event.kind), <LinuxWebViewDownloadEventKind>[
      LinuxWebViewDownloadEventKind.createdDestination,
      LinuxWebViewDownloadEventKind.progress,
      LinuxWebViewDownloadEventKind.finished,
    ]);
    expect(received[1].id, 7);
    expect(received[1].progress, 0.4);
    expect(received.last.destination, '/tmp/file.bin');
  });

  test('preserves immutable HTML option-menu metadata', () {
    final sourceItems = <BrowserOptionMenuItem>[
      const BrowserOptionMenuItem(
        index: 0,
        label: 'GPU paths',
        tooltip: null,
        isGroupLabel: true,
        isGroupChild: false,
        isEnabled: false,
        isSelected: false,
      ),
      const BrowserOptionMenuItem(
        index: 1,
        label: 'DMA-BUF texture',
        tooltip: 'Accelerated',
        isGroupLabel: false,
        isGroupChild: true,
        isEnabled: true,
        isSelected: true,
      ),
    ];
    final menu = NativeBrowserOptionMenu(
      bounds: const Rect.fromLTWH(10, 20, 180, 36),
      items: sourceItems,
    );
    sourceItems.clear();

    expect(menu.bounds, const Rect.fromLTWH(10, 20, 180, 36));
    expect(menu.items, hasLength(2));
    expect(menu.items.first.isGroupLabel, isTrue);
    expect(menu.items.last.isGroupChild, isTrue);
    expect(menu.items.last.isSelected, isTrue);
    expect(menu.items.last.tooltip, 'Accelerated');
    expect(() => menu.items.clear(), throwsUnsupportedError);
  });

  test('decodes common and WPE-specific permission resources', () {
    expect(
      decodeNativePermissionResourceTypes(
        (1 << 0) | (1 << 1) | (1 << 2) | (1 << 4),
      ),
      <WebViewPermissionResourceType>{
        WebViewPermissionResourceType.camera,
        WebViewPermissionResourceType.microphone,
        LinuxWebViewPermissionResourceType.displayCapture,
        LinuxWebViewPermissionResourceType.notifications,
      },
    );
    expect(
      decodeNativePermissionResourceTypes(1 << 31),
      <WebViewPermissionResourceType>{
        LinuxWebViewPermissionResourceType.unknown,
      },
    );
  });

  test('resolves a Linux permission request exactly once', () async {
    bool? allowed;
    final request = LinuxWebViewPermissionRequest(
      types: const <WebViewPermissionResourceType>{
        WebViewPermissionResourceType.camera,
      },
      onDecision: (decision) async => allowed = decision,
    );

    expect(request.isResolved, isFalse);
    await request.grant();
    expect(request.isResolved, isTrue);
    expect(allowed, isTrue);
    await expectLater(request.deny(), throwsStateError);
  });

  test('preserves Web Notification click and close lifecycle', () async {
    var clickCount = 0;
    var closeCount = 0;
    final notification = LinuxWebViewNotification(
      id: 17,
      title: 'Build finished',
      body: 'The Linux artifact is ready.',
      tag: 'build-status',
      url: Uri.parse('https://example.test/builds/17'),
      onClick: () async => clickCount += 1,
      onClose: () async => closeCount += 1,
    );

    expect(notification.id, 17);
    expect(notification.title, 'Build finished');
    expect(notification.body, 'The Linux artifact is ready.');
    expect(notification.tag, 'build-status');
    expect(notification.url, Uri.parse('https://example.test/builds/17'));
    expect(notification.isClicked, isFalse);
    expect(notification.isClosed, isFalse);

    await notification.click();
    expect(clickCount, 1);
    expect(notification.isClicked, isTrue);
    expect(notification.isClosed, isFalse);
    await expectLater(notification.click(), throwsStateError);

    await notification.close();
    await notification.onClosed;
    expect(closeCount, 1);
    expect(notification.isClosed, isTrue);

    await notification.close();
    expect(closeCount, 1);
    await expectLater(notification.click(), throwsStateError);
  });

  test('accepts a permission callback before widget attachment', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await expectLater(
      controller.setOnPlatformPermissionRequest((_) {}),
      completes,
    );
  });

  test('resolves a Linux HTTP authentication request exactly once', () {
    WebViewCredential? submittedCredential;
    var cancelled = false;
    final request = LinuxHttpAuthRequest(
      host: 'secure.example.com',
      realm: 'Members',
      onProceed: (credential) => submittedCredential = credential,
      onCancel: () => cancelled = true,
    );

    expect(request.host, 'secure.example.com');
    expect(request.realm, 'Members');
    expect(request.isResolved, isFalse);
    request.onProceed(
      const WebViewCredential(user: 'flutter', password: 'secret'),
    );
    expect(request.isResolved, isTrue);
    expect(submittedCredential?.user, 'flutter');
    expect(submittedCredential?.password, 'secret');
    expect(cancelled, isFalse);
    expect(request.onCancel, throwsStateError);
  });

  test('stores the HTTP authentication callback before attachment', () async {
    final delegate = LinuxNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    HttpAuthRequest? received;

    await delegate.setOnHttpAuthRequest((request) => received = request);
    final request = LinuxHttpAuthRequest(
      host: 'example.com',
      realm: null,
      onProceed: (_) {},
      onCancel: () {},
    );
    delegate.onHttpAuthRequest?.call(request);

    expect(received, same(request));
  });

  test('describes every WPE TLS certificate failure flag', () {
    expect(
      tlsErrorDescriptionForWpeFlags((1 << 0) | (1 << 3)),
      'TLS certificate validation failed: unknown certificate authority, '
      'certificate has expired.',
    );
    expect(
      tlsErrorDescriptionForWpeFlags(0),
      'TLS certificate validation failed.',
    );
    expect(
      tlsErrorDescriptionForWpeFlags(1 << 12),
      contains('unknown certificate validation error'),
    );
  });

  test('resolves a Linux TLS certificate error exactly once', () async {
    bool? proceeded;
    final error = LinuxSslAuthError(
      certificate: null,
      description: 'Test certificate failure',
      url: 'https://127.0.0.1:9443/',
      errorFlags: 1,
      onDecision: (decision) async => proceeded = decision,
    );

    expect(error.isResolved, isFalse);
    await error.proceed();
    expect(error.isResolved, isTrue);
    expect(proceeded, isTrue);
    await expectLater(error.cancel(), throwsStateError);
  });

  test('stores the TLS authentication callback before attachment', () async {
    final delegate = LinuxNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    PlatformSslAuthError? received;

    await delegate.setOnSSlAuthError((error) => received = error);
    final error = LinuxSslAuthError(
      certificate: null,
      description: 'Test certificate failure',
      url: 'https://example.com/',
      errorFlags: 1,
      onDecision: (_) async {},
    );
    delegate.onSslAuthError?.call(error);

    expect(received, same(error));
  });

  test(
    'routes console and scroll events through the internal bridge',
    () async {
      final controller = LinuxWebViewController(
        const PlatformWebViewControllerCreationParams(),
      );
      JavaScriptConsoleMessage? consoleMessage;
      ScrollPositionChange? scrollPosition;
      await controller.setOnConsoleMessage(
        (message) => consoleMessage = message,
      );
      await controller.setOnScrollPositionChange(
        (position) => scrollPosition = position,
      );

      controller.didReceiveJavaScriptMessages(const <NativeJavaScriptMessage>[
        NativeJavaScriptMessage(
          channel: '__webviewFlutterLinuxEvents_0_1',
          message: '{"type":"console","level":"warning","message":"careful"}',
        ),
        NativeJavaScriptMessage(
          channel: '__webviewFlutterLinuxEvents_0_1',
          message: '{"type":"scroll","x":12.5,"y":34}',
        ),
      ]);

      expect(consoleMessage?.level, JavaScriptLogLevel.warning);
      expect(consoleMessage?.message, 'careful');
      expect(scrollPosition?.x, 12.5);
      expect(scrollPosition?.y, 34);

      await controller.setOnScrollPositionChange(null);
      controller.didReceiveJavaScriptMessages(const <NativeJavaScriptMessage>[
        NativeJavaScriptMessage(
          channel: '__webviewFlutterLinuxEvents_0_1',
          message: '{"type":"scroll","x":99,"y":99}',
        ),
      ]);
      expect(scrollPosition?.x, 12.5);
    },
  );

  test('accepts custom user agent changes before widget attachment', () async {
    final controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await expectLater(controller.setUserAgent('ExampleBrowser/1.0'), completes);
    await expectLater(controller.setUserAgent(null), completes);
  });
}
